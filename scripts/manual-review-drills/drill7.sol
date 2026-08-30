// DRILL 7 — Level 6: Real Audit Patterns (from accepted C4/Sherlock bugs)
// Timer: 30 min | Focus: Patterns that ACTUALLY got accepted and paid
// These are REAL bug patterns from real contests, anonymized.
// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title ProtocolX — lending + staking + rewards (composite protocol)
contract ProtocolX is ReentrancyGuard {
    IERC20 public immutable collateralToken;
    IERC20 public immutable debtToken;
    IERC20 public immutable rewardToken;
    
    // Lending state
    mapping(address => uint256) public collateral;
    mapping(address => uint256) public debt;
    uint256 public totalCollateral;
    uint256 public totalDebt;
    uint256 public borrowRate = 5e16; // 5% annual
    
    // Staking state
    mapping(address => uint256) public staked;
    uint256 public totalStaked;
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    uint256 public lastUpdateTime;
    uint256 public rewardRate = 1e18; // 1 token/sec
    
    // Fee state
    uint256 public protocolFee = 1000; // 10%
    address public feeRecipient;
    uint256 public accumulatedFees;
    
    // Interest accrual
    uint256 public interestIndex = 1e18;
    uint256 public lastInterestUpdate;
    mapping(address => uint256) public userInterestIndex;
    
    constructor(address _collateral, address _debt, address _reward, address _feeRecipient) {
        collateralToken = IERC20(_collateral);
        debtToken = IERC20(_debt);
        rewardToken = IERC20(_reward);
        feeRecipient = _feeRecipient;
        lastUpdateTime = block.timestamp;
        lastInterestUpdate = block.timestamp;
    }
    
    // ============ LENDING ============
    
    function depositCollateral(uint256 amount) external nonReentrant {
        _accrueInterest();
        _updateReward(msg.sender);
        
        collateralToken.transferFrom(msg.sender, address(this), amount);
        collateral[msg.sender] += amount;
        totalCollateral += amount;
    }
    
    function borrow(uint256 amount) external nonReentrant {
        _accrueInterest();
        _updateReward(msg.sender);
        
        require(collateral[msg.sender] * 2 >= (debt[msg.sender] + amount) * 3, "LTV");
        
        debt[msg.sender] += amount;
        totalDebt += amount;
        userInterestIndex[msg.sender] = interestIndex;
        
        debtToken.transfer(msg.sender, amount);
    }
    
    function repay(uint256 amount) external nonReentrant {
        _accrueInterest();
        _updateReward(msg.sender);
        
        uint256 currentDebt = _currentDebt(msg.sender);
        uint256 repayAmount = amount > currentDebt ? currentDebt : amount;
        
        debtToken.transferFrom(msg.sender, address(this), repayAmount);
        
        // Split: principal goes to pool, interest fee goes to protocol
        uint256 interestPortion = currentDebt - debt[msg.sender];
        uint256 fee = interestPortion * protocolFee / 10000;
        
        debt[msg.sender] = currentDebt - repayAmount;
        totalDebt -= repayAmount - fee;
        accumulatedFees += fee;
        
        userInterestIndex[msg.sender] = interestIndex;
    }
    
    function withdrawCollateral(uint256 amount) external nonReentrant {
        _accrueInterest();
        _updateReward(msg.sender);
        
        require(collateral[msg.sender] >= amount, "insufficient");
        uint256 newCollateral = collateral[msg.sender] - amount;
        require(newCollateral * 2 >= _currentDebt(msg.sender) * 3, "LTV");
        
        collateral[msg.sender] = newCollateral;
        totalCollateral -= amount;
        
        collateralToken.transfer(msg.sender, amount);
    }
    
    // ============ STAKING ============
    
    function stake(uint256 amount) external nonReentrant {
        _updateReward(msg.sender);
        
        debtToken.transferFrom(msg.sender, address(this), amount);
        staked[msg.sender] += amount;
        totalStaked += amount;
    }
    
    function unstake(uint256 amount) external nonReentrant {
        _updateReward(msg.sender);
        
        require(staked[msg.sender] >= amount, "insufficient");
        staked[msg.sender] -= amount;
        totalStaked -= amount;
        
        debtToken.transfer(msg.sender, amount);
    }
    
    function claimRewards() external nonReentrant {
        _updateReward(msg.sender);
        
        uint256 reward = rewards[msg.sender];
        rewards[msg.sender] = 0;
        
        rewardToken.transfer(msg.sender, reward);
    }
    
    // ============ INTERNAL ============
    
    function _accrueInterest() internal {
        if (totalDebt == 0) {
            lastInterestUpdate = block.timestamp;
            return;
        }
        uint256 elapsed = block.timestamp - lastInterestUpdate;
        uint256 ratePerSecond = borrowRate / (365 days);
        interestIndex += interestIndex * ratePerSecond * elapsed / 1e18;
        lastInterestUpdate = block.timestamp;
    }
    
    function _currentDebt(address user) internal view returns (uint256) {
        if (userInterestIndex[user] == 0) return debt[user];
        return debt[user] * interestIndex / userInterestIndex[user];
    }
    
    function _updateReward(address user) internal {
        rewardPerTokenStored = _rewardPerToken();
        lastUpdateTime = block.timestamp;
        
        if (user != address(0)) {
            rewards[user] = _earned(user);
            userRewardPerTokenPaid[user] = rewardPerTokenStored;
        }
    }
    
    function _rewardPerToken() internal view returns (uint256) {
        if (totalStaked == 0) return rewardPerTokenStored;
        return rewardPerTokenStored + 
            (block.timestamp - lastUpdateTime) * rewardRate * 1e18 / totalStaked;
    }
    
    function _earned(address user) internal view returns (uint256) {
        return staked[user] * (_rewardPerToken() - userRewardPerTokenPaid[user]) / 1e18 
            + rewards[user];
    }
    
    // ============ VIEWS ============
    
    function getUserDebt(address user) external view returns (uint256) {
        return _currentDebt(user);
    }
    
    function getHealthFactor(address user) external view returns (uint256) {
        uint256 currentDebt = _currentDebt(user);
        if (currentDebt == 0) return type(uint256).max;
        return collateral[user] * 2 * 1e18 / (currentDebt * 3);
    }
}

/*
=== HINTS ===

Hint 1: repay() — look at how totalDebt is updated.
        totalDebt -= repayAmount - fee
        But debt[msg.sender] = currentDebt - repayAmount
        Are these consistent?

Hint 2: _currentDebt uses interestIndex ratio.
        userInterestIndex is updated in borrow() and repay().
        But NOT in depositCollateral() or withdrawCollateral().
        What happens if interest accrues between deposit and borrow?

Hint 3: _updateReward is called in lending functions too.
        depositCollateral calls _updateReward.
        But staked[msg.sender] might be 0.
        Is there a cross-contamination between lending and staking?

Hint 4: repay() calculates interestPortion = currentDebt - debt[msg.sender]
        But debt[msg.sender] is the OLD principal (before interest scaling).
        currentDebt = debt * interestIndex / userIndex.
        interestPortion = debt * (interestIndex/userIndex - 1)
        Is this the actual interest? Or is it inflated/deflated?

Hint 5: What if totalDebt becomes 0 but totalStaked > 0?
        _accrueInterest: if totalDebt == 0, skip.
        But stakers still earn rewards.
        Where do rewards come from? rewardToken.balanceOf(this).
        What if it runs out?

=== ANSWER KEY ===

BUG 1 (CRITICAL): totalDebt accounting inconsistency in repay()
  repay():
    currentDebt = debt[user] * interestIndex / userIndex  // includes interest
    repayAmount = min(amount, currentDebt)
    
    debt[user] = currentDebt - repayAmount  // new principal
    totalDebt -= repayAmount - fee           // ← BUG
    
  Problem:
    totalDebt tracks SUM of all users' debt[user] (principal)
    But repayAmount includes INTEREST
    totalDebt should decrease by: principal portion of repayment
    Instead decreases by: repayAmount - fee (includes interest - fee)
    
  Example:
    User debt = 100 (principal)
    interestIndex/userIndex = 1.1 (10% interest)
    currentDebt = 110
    User repays 110 (full)
    
    debt[user] = 110 - 110 = 0  ✅
    totalDebt -= 110 - fee(1) = 109  ← WRONG
    Should be: totalDebt -= 100 (original principal)
    
    totalDebt is now 9 LESS than sum of all debt[user]
    → totalDebt UNDERCOUNTS
    → Next borrower can borrow more than pool actually has
    → INSOLVENCY
    
  SEVERITY: CRITICAL — accounting drift → insolvency

BUG 2 (HIGH): Interest charged on wrong base
  _currentDebt: debt[user] * interestIndex / userInterestIndex[user]
  
  userInterestIndex is set in borrow() and repay().
  But depositCollateral() calls _accrueInterest() which updates
  the GLOBAL interestIndex, not userInterestIndex.
  
  Timeline:
    T0: User borrows 100. userIndex = 1.0, debt = 100
    T1: Interest accrues. interestIndex = 1.05
    T2: User deposits more collateral.
        _accrueInterest() runs. interestIndex = 1.06
        userInterestIndex NOT updated (still 1.0)
    T3: User repays.
        currentDebt = 100 * 1.06 / 1.0 = 106
        But user only owed interest from T0 to T3.
        Interest from T1 to T2 was already "accrued" but
        user didn't interact, so it's correct.
        
        Actually: this IS correct. interestIndex/userIndex
        gives the full accrued interest since last interaction.
        FALSE ALARM. ✅
        
  BUT: What if userInterestIndex = 0?
    _currentDebt: if userInterestIndex == 0, return debt[user]
    This means: user who deposited collateral but never borrowed
    has userInterestIndex = 0.
    If they then borrow: userInterestIndex set to current interestIndex.
    Correct. ✅

BUG 3 (HIGH): Staking rewards from thin air
  _updateReward is called in ALL functions (lending + staking).
  lastUpdateTime is GLOBAL.
  
  If no one stakes (totalStaked = 0):
    _rewardPerToken: returns rewardPerTokenStored (no change)
    lastUpdateTime still updates to block.timestamp
    
  If someone stakes after long empty period:
    _rewardPerToken: (block.timestamp - lastUpdateTime) * rate / totalStaked
    lastUpdateTime was recently updated (by lending operations)
    → elapsed is small
    → Correct. No phantom rewards. ✅
    
  FALSE ALARM. lastUpdateTime updates on every _updateReward call.

BUG 4 (MEDIUM): repay() fee calculation on inflated interest
  interestPortion = currentDebt - debt[msg.sender]
  
  currentDebt = debt * interestIndex / userIndex (scaled up)
  debt[msg.sender] = original principal (not scaled)
  
  interestPortion = debt * (interestIndex/userIndex - 1)
  
  This is the TOTAL interest accrued since last interaction.
  Fee = interestPortion * 10%
  
  But: if user makes partial repayments:
    After first repay: userIndex updated to current interestIndex
    After second repay: interestPortion = debt * (newIndex/updatedIndex - 1)
    → Only interest since LAST repay. Correct. ✅
    
  BUT: fee is taken from repayment, reducing totalDebt.
  totalDebt -= repayAmount - fee
  The fee stays in the contract (accumulatedFees).
  But totalDebt reduction includes the fee portion.
  → totalDebt decreases by LESS than repayAmount
  → totalDebt > sum of individual debts
  → OVERCOUNT (opposite of Bug 1!)
  
  Wait: Bug 1 said undercount. Let me re-check.
  
  totalDebt -= repayAmount - fee
  repayAmount = 110, fee = 1
  totalDebt -= 109
  
  But individual debt went from 100 to 0 (decrease of 100).
  totalDebt decreased by 109, individual by 100.
  totalDebt decreased MORE than individual sum.
  → totalDebt UNDERCOUNTS by 9.
  
  Confirmed: Bug 1 is correct. CRITICAL.

BUG 5 (MEDIUM): No liquidation mechanism
  getHealthFactor exists but no liquidate() function.
  If collateral value drops below LTV:
    → No way to liquidate underwater positions
    → Bad debt accumulates
    → Pool becomes insolvent
    
  SEVERITY: MEDIUM — missing critical function
  (Design flaw, not code bug)

LESSONS:
  1. ACCOUNTING CONSISTENCY: totalX must always equal sum of
     individual X. Check every function that modifies both.
     repay() modifies debt[user] AND totalDebt differently.
     → This is the #1 source of HIGH/CRITICAL bugs in DeFi.
  
  2. INTEREST + FEE: When interest is split (principal vs interest),
     make sure the TOTAL accounting still balances.
     fee extraction creates a "leak" in the accounting.
  
  3. FALSE ALARMS ARE OK: Drill 3 and this drill both had
     false alarms. That's NORMAL. Expert auditors have 80%
     false alarm rate. The skill is: quickly identify and
     DISMISS false alarms, then focus on real ones.
  
  4. MISSING FUNCTIONS: Sometimes the bug is what's NOT there.
     No liquidation = no way to handle bad debt.
     Always ask: "what happens in the worst case?"
*/
