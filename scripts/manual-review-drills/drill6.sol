// DRILL 6 — Level 5: Full Protocol — Governance + Economic + Cross-Contract
// Timer: 30 min | Actors: staker, governor, attacker, keeper
// Focus: Governance manipulation, economic incentive misalignment, multi-contract
// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title GovernanceToken — voting token with delegation
contract GovToken is ERC20Votes {
    constructor() ERC20("GovToken", "GOV") ERC20Permit("GovToken") {}
    
    function mint(address to, uint256 amount) external {
        // Minting restricted to staking contract
        require(msg.sender == 0xSTAKING_CONTRACT, "not staking");
        _mint(to, amount);
    }
    
    function burn(address from, uint256 amount) external {
        require(msg.sender == 0xSTAKING_CONTRACT, "not staking");
        _burn(from, amount);
    }
}

/// @title StakingContract — stake ETH, receive GOV tokens 1:1
contract StakingContract is ReentrancyGuard {
    GovToken public immutable govToken;
    Treasury public immutable treasury;
    
    mapping(address => uint256) public stakedETH;
    uint256 public totalStaked;
    
    uint256 public unlockDelay = 7 days;
    mapping(address => uint256) public unlockRequestTime;
    mapping(address => uint256) public unlockAmount;
    
    constructor(address _govToken, address _treasury) {
        govToken = GovToken(_govToken);
        treasury = Treasury(payable(_treasury));
    }
    
    function stake() external payable nonReentrant {
        require(msg.value > 0, "zero");
        
        stakedETH[msg.sender] += msg.value;
        totalStaked += msg.value;
        
        // Mint GOV 1:1
        govToken.mint(msg.sender, msg.value);
        
        // Forward ETH to treasury
        treasury.deposit{value: msg.value}();
    }
    
    function requestUnstake(uint256 amount) external nonReentrant {
        require(stakedETH[msg.sender] >= amount, "insufficient");
        require(unlockRequestTime[msg.sender] == 0, "pending");
        
        unlockRequestTime[msg.sender] = block.timestamp;
        unlockAmount[msg.sender] = amount;
    }
    
    function executeUnstake() external nonReentrant {
        require(unlockRequestTime[msg.sender] > 0, "no request");
        require(block.timestamp >= unlockRequestTime[msg.sender] + unlockDelay, "locked");
        
        uint256 amount = unlockAmount[msg.sender];
        
        // Burn GOV tokens
        govToken.burn(msg.sender, amount);
        
        stakedETH[msg.sender] -= amount;
        totalStaked -= amount;
        unlockRequestTime[msg.sender] = 0;
        unlockAmount[msg.sender] = 0;
        
        // Withdraw ETH from treasury
        treasury.withdraw(msg.sender, amount);
    }
    
    /// @notice Emergency: admin can change unlock delay
    function setUnlockDelay(uint256 _delay) external {
        require(msg.sender == address(treasury), "not treasury");
        unlockDelay = _delay;
    }
}

/// @title Treasury — holds staked ETH, managed by governance
contract Treasury is ReentrancyGuard {
    uint256 public totalDeposits;
    address public stakingContract;
    
    // Governance-controlled parameters
    uint256 public investRatio = 5000; // 50% invested, 50% liquid
    address public investmentStrategy;
    uint256 public investedAmount;
    
    constructor(address _staking) {
        stakingContract = _staking;
    }
    
    function deposit() external payable {
        require(msg.sender == stakingContract, "not staking");
        totalDeposits += msg.value;
    }
    
    function withdraw(address to, uint256 amount) external nonReentrant {
        require(msg.sender == stakingContract, "not staking");
        require(amount <= _liquidBalance(), "insufficient liquid");
        
        totalDeposits -= amount;
        (bool ok,) = to.call{value: amount}("");
        require(ok, "transfer failed");
    }
    
    /// @notice Governance can invest treasury funds
    function invest(uint256 amount) external {
        require(msg.sender == address(this), "not governance");
        require(amount <= _liquidBalance(), "insufficient");
        require(investedAmount + amount <= totalDeposits * investRatio / 10000, "over ratio");
        
        investedAmount += amount;
        (bool ok,) = investmentStrategy.call{value: amount}("");
        require(ok, "invest failed");
    }
    
    /// @notice Governance can divest
    function divest(uint256 amount) external {
        require(msg.sender == address(this), "not governance");
        require(amount <= investedAmount, "over invested");
        
        IStrategy(investmentStrategy).withdraw(amount);
        investedAmount -= amount;
    }
    
    /// @notice Governance sets investment ratio
    function setInvestRatio(uint256 _ratio) external {
        require(msg.sender == address(this), "not governance");
        require(_ratio <= 10000, "over 100%");
        investRatio = _ratio;
    }
    
    function _liquidBalance() internal view returns (uint256) {
        return address(this).balance - investedAmount;
    }
    
    receive() external payable {}
}

interface IStrategy {
    function withdraw(uint256 amount) external;
}

/*
=== HINTS ===

Hint 1: GOV tokens are minted 1:1 on stake. But voting power in
        ERC20Votes requires delegation. What if user stakes but
        doesn't delegate? Can they still vote?

Hint 2: requestUnstake → executeUnstake has a 7-day delay.
        During those 7 days, user still has GOV tokens.
        Can they vote on proposals that affect their own unstaking?

Hint 3: Treasury.invest() requires msg.sender == address(this).
        This means it can only be called via governance proposal.
        But what if governance passes a proposal to set investRatio = 10000
        and then invest ALL funds? What happens to unstaking?

Hint 4: executeUnstake calls treasury.withdraw().
        Treasury.withdraw checks _liquidBalance().
        If governance invested 50% of funds, liquid = 50%.
        What if >50% of stakers try to unstake simultaneously?

Hint 5: setUnlockDelay is called by treasury (governance).
        Governance can set unlockDelay = 0.
        Then: stake → requestUnstake → executeUnstake in SAME TX.
        What does this enable?

Hint 6: GOV token minting is 1:1 with ETH.
        But ETH value changes. 1 ETH today != 1 ETH in 1 year.
        Voting power is fixed at mint time. Is this fair?

=== ANSWER KEY ===

BUG 1 (CRITICAL): Governance can brick unstaking via invest
  Attack (governance proposal):
    1. Pass proposal: setInvestRatio(10000)  // 100%
    2. Pass proposal: invest(all liquid funds)
    3. Treasury liquid balance = 0
    4. ALL unstakers: treasury.withdraw reverts "insufficient liquid"
    5. User funds PERMANENTLY LOCKED (until strategy returns)
    
  If strategy is illiquid (real estate, locked staking):
    → Funds locked for months/years
    → Governance effectively stole from stakers
    
  SEVERITY: CRITICAL — governance can rug stakers
  FIX: Reserve ratio for unstaking, or timelock on invest changes

BUG 2 (HIGH): Flash-loan governance via stake/unstake
  If unlockDelay = 0 (governance can set this):
    1. Flash loan 10000 ETH
    2. stake(10000 ETH) → get 10000 GOV
    3. delegate(self) → voting power = 10000
    4. vote on malicious proposal
    5. requestUnstake(10000)
    6. executeUnstake() → get 10000 ETH back
    7. Repay flash loan
    
  Total cost: gas only
  Voting power: 10000 GOV (free)
  
  Even with 7-day delay:
    1. stake(10000 ETH)
    2. delegate(self)
    3. vote
    4. requestUnstake
    5. Wait 7 days
    6. executeUnstake
    
  Cost: 7 days of capital lockup (opportunity cost)
  But: voting happens IMMEDIATELY after stake
  
  SEVERITY: HIGH — voting power without economic commitment
  FIX: Voting escrow (ve-model), or snapshot voting power at
       proposal creation time minus pending unstakes

BUG 3 (HIGH): No delegation check on mint
  GovToken.mint() mints tokens but ERC20Votes requires
  explicit delegation for voting power.
  
  stake() mints GOV but doesn't call delegate().
  User must manually delegate.
  
  If user forgets: tokens exist but NO voting power.
  → Not a security bug, but UX issue.
  → However: if staking contract delegates ON BEHALF of user
    to a default address, that's a centralization risk.
  
  SEVERITY: LOW/INFO — UX, not security

BUG 4 (MEDIUM): Treasury.withdraw sends ETH via call
  withdraw() → to.call{value: amount}("")
  
  If 'to' is a contract with malicious receive():
    → Can re-enter Treasury? No: nonReentrant
    → Can re-enter StakingContract? No: nonReentrant
    → But: can call OTHER contracts
    → Cross-contract side effects possible
    
  SEVERITY: MEDIUM — reentrancy protected but external call
            to arbitrary address in withdraw path

BUG 5 (MEDIUM): investRatio change doesn't check current invested
  setInvestRatio(newRatio):
    → Just sets the ratio
    → Doesn't check if investedAmount > totalDeposits * newRatio / 10000
    
  If governance sets ratio from 50% to 10%:
    investedAmount might be 50% of deposits
    But new max is 10%
    → investedAmount > max allowed
    → invest() would revert (over ratio)
    → But existing investment stays
    → divest() needed to bring back in line
    → No automatic enforcement
    
  SEVERITY: MEDIUM — ratio change doesn't force divestment

BUG 6 (LOW): No minimum stake amount
  stake() requires msg.value > 0
  → Can stake 1 wei
  → Gets 1 wei GOV token
  → Can vote with 1 wei voting power
  → Gas cost > value, but still possible
  → Spam governance with tiny stakes
  
  SEVERITY: LOW — governance spam

LESSONS:
  1. Governance = attack vector. "Governance can do X" is NOT
     a valid reason to ignore a bug. Governance can be:
     - Flash-loan attacked (voting power without commitment)
     - Socially engineered (malicious proposals)
     - Slow-attacked (gradual parameter changes)
  2. Treasury management: liquid vs invested ratio is CRITICAL.
     If users can't withdraw because funds are invested = rug.
  3. Voting power timing: when is it measured? At proposal
     creation? At vote time? At execution? Each has different
     attack surfaces.
  4. 1:1 token minting: always ask "what backs this token?"
     If backing can be moved/locked, token becomes unbacked.
*/
