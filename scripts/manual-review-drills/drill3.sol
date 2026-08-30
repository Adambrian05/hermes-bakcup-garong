// DRILL 3 — Level 2: Cross-Contract State Desync
// Timer: 10 min | Actors: user, vault, oracle
// Focus: State yang harusnya sync tapi ga
// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title StakingVault — stake LP tokens, earn rewards based on oracle price
contract StakingVault is ReentrancyGuard {
    IERC20 public immutable lpToken;
    IERC20 public immutable rewardToken;
    IOracle public oracle;
    
    uint256 public totalStaked;
    mapping(address => uint256) public staked;
    mapping(address => uint256) public rewardDebt;
    mapping(address => uint256) public pendingRewards;
    
    uint256 public accRewardPerShare;  // accumulated rewards per share, 1e18 precision
    uint256 public lastRewardTime;
    uint256 public rewardRate = 1e18; // 1 token per second
    
    constructor(address _lp, address _reward, address _oracle) {
        lpToken = IERC20(_lp);
        rewardToken = IERC20(_reward);
        oracle = IOracle(_oracle);
        lastRewardTime = block.timestamp;
    }
    
    function stake(uint256 amount) external nonReentrant {
        _updateRewards();
        
        pendingRewards[msg.sender] += _calcPending(msg.sender);
        
        lpToken.transferFrom(msg.sender, address(this), amount);
        staked[msg.sender] += amount;
        totalStaked += amount;
        
        rewardDebt[msg.sender] = staked[msg.sender] * accRewardPerShare / 1e18;
    }
    
    function unstake(uint256 amount) external nonReentrant {
        require(staked[msg.sender] >= amount, "insufficient");
        _updateRewards();
        
        pendingRewards[msg.sender] += _calcPending(msg.sender);
        
        staked[msg.sender] -= amount;
        totalStaked -= amount;
        
        rewardDebt[msg.sender] = staked[msg.sender] * accRewardPerShare / 1e18;
        
        lpToken.transfer(msg.sender, amount);
    }
    
    function claimRewards() external nonReentrant {
        _updateRewards();
        
        uint256 rewards = pendingRewards[msg.sender] + _calcPending(msg.sender);
        pendingRewards[msg.sender] = 0;
        rewardDebt[msg.sender] = staked[msg.sender] * accRewardPerShare / 1e18;
        
        rewardToken.transfer(msg.sender, rewards);
    }
    
    /// @notice Oracle can update reward rate based on LP token price
    function updateRewardRate() external {
        require(msg.sender == address(oracle), "not oracle");
        _updateRewards();
        uint256 lpPrice = oracle.getLPPrice();
        // Higher LP price = lower reward rate (inverse relationship)
        rewardRate = 1e36 / lpPrice;
    }
    
    function _updateRewards() internal {
        if (totalStaked == 0) {
            lastRewardTime = block.timestamp;
            return;
        }
        uint256 elapsed = block.timestamp - lastRewardTime;
        uint256 rewards = elapsed * rewardRate;
        accRewardPerShare += rewards * 1e18 / totalStaked;
        lastRewardTime = block.timestamp;
    }
    
    function _calcPending(address user) internal view returns (uint256) {
        return staked[user] * accRewardPerShare / 1e18 - rewardDebt[user];
    }
}

interface IOracle {
    function getLPPrice() external view returns (uint256);
}

/*
=== HINTS (buka kalau stuck setelah 5 menit) ===

Hint 1: Apa yang terjadi kalau totalStaked = 0 lalu seseorang stake?
Hint 2: _calcPending dipanggil SEBELUM staked[user] di-update di stake()
Hint 3: rewardDebt di-set SETELAH staked di-update. Tapi _calcPending
        pakai staked yang LAMA. Konsisten ga?
Hint 4: updateRewardRate() — siapa yang bisa manipulasi lpPrice?
Hint 5: Apa yang terjadi kalau oracle set lpPrice = 1?
        rewardRate = 1e36 / 1 = 1e36 per second.

=== ANSWER KEY (buka setelah selesai) ===

BUG 1 (HIGH): Double-counting rewards di stake()
  stake() calls _calcPending() which uses OLD staked[user]
  Then updates staked[user] += amount
  Then sets rewardDebt = NEW staked * accRewardPerShare / 1e18
  
  But pendingRewards already includes rewards for OLD stake.
  Next _calcPending: NEW staked * accReward / 1e18 - rewardDebt
  rewardDebt = NEW staked * accReward / 1e18
  So _calcPending = 0 after stake. Correct.
  
  WAIT — actually this IS correct. rewardDebt resets properly.
  FALSE ALARM. This is standard MasterChef pattern. ✅
  
  LESSON: Not everything that looks wrong is wrong.
  MasterChef pattern: pending = staked * acc - debt. 
  debt resets on every action. This is correct.

BUG 2 (CRITICAL): Oracle reward rate manipulation
  updateRewardRate(): rewardRate = 1e36 / lpPrice
  If oracle returns lpPrice = 1:
    rewardRate = 1e36 per second
    1 second of rewards = 1e36 tokens
    accRewardPerShare += 1e36 * 1e18 / totalStaked
    
  If oracle is compromised or buggy:
    → Infinite reward minting
    → But: rewardToken.transfer needs balance
    → If vault doesn't have 1e36 tokens: revert
    → So: DoS, not theft (unless vault has huge balance)
  
  SEVERITY: Depends on oracle trust model.
  If oracle is admin-controlled: MEDIUM (admin trust)
  If oracle is on-chain AMM: HIGH (manipulable)

BUG 3 (MEDIUM): _updateRewards skips when totalStaked = 0
  If totalStaked = 0 for a long time:
    lastRewardTime keeps updating to block.timestamp
    No rewards accumulate (correct — no one staked)
  
  But: if someone stakes AFTER a long empty period:
    elapsed = 0 (lastRewardTime was just updated)
    No lost rewards. CORRECT. ✅
  
  FALSE ALARM again.

BUG 4 (LOW): Rounding in _calcPending
  staked * accRewardPerShare / 1e18 rounds down
  rewardDebt also rounds down
  Difference: dust accumulates in contract
  → Standard MasterChef rounding. LOW/INFO.

REAL BUGS: 1 (oracle manipulation)
FALSE ALARMS: 2 (MasterChef pattern is correct)
LESSON: Know your patterns. MasterChef is well-studied.
        Don't waste time "finding bugs" in proven patterns.
        Focus on what's DIFFERENT from the pattern.
*/
