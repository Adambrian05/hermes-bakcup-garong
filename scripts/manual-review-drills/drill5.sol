// DRILL 5 — Level 4: Multi-TX Timing Attack
// Timer: 20 min | Actors: depositor, attacker, admin
// Focus: State changes across MULTIPLE transactions, timing windows
// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title EpochVault — deposits earn yield per epoch, admin sets strategy
contract EpochVault is ReentrancyGuard {
    IERC20 public immutable asset;
    
    uint256 public constant EPOCH_DURATION = 7 days;
    uint256 public epochStart;
    uint256 public currentEpoch;
    
    uint256 public totalDeposits;
    uint256 public epochYield;          // yield earned this epoch
    uint256 public lastEpochYield;      // yield from previous epoch
    
    mapping(address => uint256) public deposits;
    mapping(address => uint256) public lastEpochClaimed;
    mapping(address => uint256) public depositEpoch;  // epoch when deposited
    
    address public strategy;
    address public admin;
    
    constructor(address _asset, address _strategy) {
        asset = IERC20(_asset);
        strategy = _strategy;
        admin = msg.sender;
        epochStart = block.timestamp;
        currentEpoch = 1;
    }
    
    function deposit(uint256 amount) external nonReentrant {
        _settleEpoch();
        
        asset.transferFrom(msg.sender, address(this), amount);
        deposits[msg.sender] += amount;
        totalDeposits += amount;
        depositEpoch[msg.sender] = currentEpoch;
    }
    
    function withdraw(uint256 amount) external nonReentrant {
        _settleEpoch();
        require(deposits[msg.sender] >= amount, "insufficient");
        
        deposits[msg.sender] -= amount;
        totalDeposits -= amount;
        
        asset.transfer(msg.sender, amount);
    }
    
    /// @notice Claim yield from completed epochs
    function claimYield() external nonReentrant {
        _settleEpoch();
        
        uint256 claimable = _calcClaimable(msg.sender);
        require(claimable > 0, "nothing to claim");
        
        lastEpochClaimed[msg.sender] = currentEpoch - 1;
        
        asset.transfer(msg.sender, claimable);
    }
    
    /// @notice Admin harvests yield from strategy
    function harvestYield() external {
        require(msg.sender == admin, "not admin");
        
        uint256 before = asset.balanceOf(address(this));
        IStrategy(strategy).harvest();
        uint256 yield = asset.balanceOf(address(this)) - before;
        
        epochYield += yield;
    }
    
    /// @notice Admin can change strategy
    function setStrategy(address _strategy) external {
        require(msg.sender == admin, "not admin");
        // Withdraw all from old strategy
        uint256 balance = asset.balanceOf(address(this));
        if (balance > 0) {
            IStrategy(strategy).withdrawAll();
        }
        strategy = _strategy;
    }
    
    function _settleEpoch() internal {
        if (block.timestamp < epochStart + EPOCH_DURATION) return;
        
        // Settle previous epoch
        lastEpochYield = epochYield;
        epochYield = 0;
        
        // Advance epoch
        uint256 elapsed = block.timestamp - epochStart;
        uint256 epochsPassed = elapsed / EPOCH_DURATION;
        currentEpoch += epochsPassed;
        epochStart += epochsPassed * EPOCH_DURATION;
    }
    
    function _calcClaimable(address user) internal view returns (uint256) {
        if (deposits[user] == 0) return 0;
        if (depositEpoch[user] >= currentEpoch) return 0;
        
        // User gets proportional share of last epoch's yield
        uint256 share = deposits[user] * 1e18 / totalDeposits;
        return lastEpochYield * share / 1e18;
    }
    
    function getAPY() external view returns (uint256) {
        if (totalDeposits == 0) return 0;
        return lastEpochYield * 52 * 1e18 / totalDeposits; // annualized
    }
}

interface IStrategy {
    function harvest() external;
    function withdrawAll() external;
}

/*
=== HINTS ===

Hint 1: _settleEpoch() is called inside deposit/withdraw/claim.
        But harvestYield() does NOT call _settleEpoch().
        What happens if admin harvests in epoch 1, then epoch rolls over,
        then admin harvests again in epoch 2?

Hint 2: _calcClaimable uses lastEpochYield (SINGULAR epoch).
        What if user doesn't claim for 3 epochs?
        Do they get 3x yield or 1x?

Hint 3: deposit() calls _settleEpoch() which resets epochYield = 0.
        What if admin harvests BEFORE anyone deposits in new epoch?
        epochYield accumulates. Then someone deposits.
        _settleEpoch doesn't trigger (epoch just started).
        Then epoch ends. lastEpochYield = epochYield (includes pre-deposit harvest).
        But totalDeposits was 0 when harvest happened!

Hint 4: setStrategy() calls withdrawAll() on OLD strategy.
        But what if old strategy is malicious and re-enters?
        → nonReentrant? No! setStrategy has NO nonReentrant!

Hint 5: Multiple epochs pass without any interaction.
        _settleEpoch: epochsPassed = elapsed / EPOCH_DURATION
        But lastEpochYield only stores ONE epoch's yield.
        What about epochs 2, 3, 4...?

=== ANSWER KEY ===

BUG 1 (CRITICAL): Yield loss when multiple epochs pass
  _settleEpoch():
    lastEpochYield = epochYield  // only stores LATEST
    epochYield = 0
    currentEpoch += epochsPassed  // skips multiple epochs
  
  If 3 epochs pass without interaction:
    Epoch 1 yield: 100 (harvested)
    Epoch 2 yield: 100 (harvested)
    Epoch 3 yield: 100 (harvested)
    
    _settleEpoch called in epoch 4:
    lastEpochYield = epochYield = 300 (all accumulated!)
    
    Wait — epochYield accumulates across epochs because
    harvestYield() doesn't call _settleEpoch().
    So epochYield = 300 (3 epochs of harvest).
    lastEpochYield = 300.
    
    User claims: gets share of 300.
    But they should get share of 100 per epoch × 3 epochs.
    
    Actually... 300 / 3 = 100 per epoch. Same total.
    
    BUT: _calcClaimable only pays ONCE (lastEpochYield).
    lastEpochClaimed = currentEpoch - 1.
    User can only claim ONCE for all missed epochs.
    
    If user deposited in epoch 1 and claims in epoch 4:
    Gets: share of 300 (3 epochs accumulated)
    Should get: share of 100 × 3 = 300
    → SAME. Actually correct by accident.
    
    FALSE ALARM on total amount. ✅
    
    BUT: What if user deposits in epoch 2?
    depositEpoch = 2. currentEpoch = 4.
    _calcClaimable: depositEpoch(2) < currentEpoch(4) → OK
    Gets: share of lastEpochYield(300)
    But they were only deposited for 2 epochs, not 3!
    → OVERPAYMENT. Gets 3 epochs of yield for 2 epochs of deposit.
    
    SEVERITY: MEDIUM — overpayment to late depositors

BUG 2 (HIGH): setStrategy() has NO nonReentrant
  setStrategy():
    1. IStrategy(strategy).withdrawAll()  ← external call
    2. strategy = _strategy
  
  If old strategy is malicious:
    withdrawAll() can call back into EpochVault
    → deposit(), withdraw(), claimYield() all have nonReentrant
    → BUT: setStrategy() itself does NOT
    → Re-entrancy via setStrategy → withdrawAll → deposit
    → Wait: deposit has nonReentrant, so re-entry blocked
    
    Actually: the reentrancy guard is per-function.
    setStrategy doesn't have it. But the functions it could
    re-enter DO have it. So re-entry into deposit/withdraw
    is blocked.
    
    BUT: setStrategy → withdrawAll → setStrategy (re-enter!)
    → Can change strategy TWICE in one tx
    → First withdrawAll drains old strategy
    → Re-entered setStrategy: withdrawAll on NEW strategy
    → Drains new strategy too!
    
    SEVERITY: HIGH if admin is compromised
              LOW if admin is trusted (admin-only function)

BUG 3 (HIGH): harvestYield doesn't settle epoch
  harvestYield() adds to epochYield but doesn't call _settleEpoch()
  
  Timeline:
    Epoch 1 start: epochYield = 0
    Admin harvests: epochYield = 100
    Epoch 1 ends, epoch 2 starts (no one calls _settleEpoch)
    Admin harvests: epochYield = 200 (100 from epoch 1 + 100 from epoch 2)
    Epoch 2 ends, epoch 3 starts
    User calls claimYield → _settleEpoch:
      lastEpochYield = 200
      currentEpoch = 3
    
    User gets share of 200 (2 epochs of yield)
    But _calcClaimable pays ONCE
    → If user was deposited for both epochs: correct (200)
    → If user deposited in epoch 2 only: gets 200, should get 100
    → OVERPAYMENT
    
  SEVERITY: HIGH — epoch boundary not enforced on harvest

BUG 4 (MEDIUM): totalDeposits = 0 division
  _calcClaimable: share = deposits[user] * 1e18 / totalDeposits
  If totalDeposits = 0: DIVISION BY ZERO → revert
  
  When can this happen?
    All users withdraw, but epochYield > 0
    No one can claim (revert on division)
    Yield stuck forever
    
  SEVERITY: MEDIUM — permanent fund lock

BUG 5 (LOW): getAPY uses lastEpochYield
  If no epoch has settled: lastEpochYield = 0
  APY shows 0% even if yield is accumulating
  → Misleading but not exploitable
  SEVERITY: LOW/INFO

LESSONS:
  1. Epoch-based systems: ALWAYS settle on every state-changing call.
     Missing _settleEpoch in harvestYield = epoch boundary violation.
  2. "Admin-only" doesn't mean "safe". Admin can be compromised.
     Missing nonReentrant on admin function = reentrancy vector.
  3. Division by zero in DeFi = permanent DoS. Always check denominator.
  4. Multi-epoch skip: what happens to users who join mid-way?
     Always track PER-USER epoch participation, not global.
*/
