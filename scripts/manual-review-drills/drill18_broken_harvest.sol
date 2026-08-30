// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * DRILL 18: THE BROKEN HARVEST
 * Difficulty: EXPERT
 * Focus: Reward accrual math / integer division / emergency-withdraw griefing
 *
 * Real-world protocol: MasterChef, Synthetix StakingRewards, Curve Gauge
 * These patterns appear in 20+ C4/Sherlock findings.
 *
 * THREE POTENTIAL BUGS. FIND THEM. JUDGE HONESTLY.
 */

// ============================================================
// TOKEN (plain ERC20, no hooks)
// ============================================================
contract StakeToken {
    string public name = "STK";
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
        require(allowance[from][msg.sender] >= amount, "not approved");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract RewardToken {
    string public name = "RWD";
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
        require(allowance[from][msg.sender] >= amount, "not approved");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

// ============================================================
// STAKING POOL — a very common reward-accrual pattern
// ============================================================
contract StakingPool {
    StakeToken public stakingToken;
    RewardToken public rewardToken;

    uint256 public totalStaked;
    uint256 public rewardRate;
    uint256 public rewardPerShareStored; // scaled by 1e12
    uint256 public lastUpdateTime;
    uint256 public periodFinish;
    uint256 public constant REWARD_PRECISION = 1e12;

    mapping(address => uint256) public balanceOf;          // staked balance
    mapping(address => uint256) public userRewardPerShare; // snapshot
    mapping(address => uint256) public rewards;            // pending claimable

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event EmergencyWithdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardNotified(uint256 reward, uint256 duration);

    constructor(address _stakingToken, address _rewardToken) {
        stakingToken = StakeToken(_stakingToken);
        rewardToken = RewardToken(_rewardToken);
    }

    // ============================================================
    // CORE FUNCTIONS
    // ============================================================

    function stake(uint256 amount) external updateReward(msg.sender) {
        require(amount > 0, "zero amount");
        stakingToken.transferFrom(msg.sender, address(this), amount);
        balanceOf[msg.sender] += amount;
        totalStaked += amount;
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) external updateReward(msg.sender) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        _claimPendingReward(msg.sender);
        balanceOf[msg.sender] -= amount;
        totalStaked -= amount;
        stakingToken.transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() external updateReward(msg.sender) {
        _claimPendingReward(msg.sender);
    }

    function emergencyWithdraw() external {
        // "Safety" exit: withdraw immediately, skip reward claim
        uint256 amount = balanceOf[msg.sender];
        require(amount > 0, "nothing staked");

        // DO update the global reward per share (so remaining stakers get the share)
        // but DO NOT claim the user's pending rewards.
        rewardPerShareStored = _rewardPerShare();
        lastUpdateTime = _lastTimeRewardApplicable();

        balanceOf[msg.sender] = 0;
        totalStaked -= amount;
        stakingToken.transfer(msg.sender, amount);
        emit EmergencyWithdrawn(msg.sender, amount);
    }

    // ============================================================
    // OWNER — add rewards
    // ============================================================
    function notifyRewardAmount(uint256 reward, uint256 duration) external {
        // In production this would be a reward distributor, not owner-only;
        // that's irrelevant to the bugs.
        rewardToken.transferFrom(msg.sender, address(this), reward);

        if (block.timestamp >= periodFinish) {
            rewardRate = reward / duration;  // <--- integer division, no precision
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / duration;
        }

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + duration;
        emit RewardNotified(reward, duration);
    }

    // ============================================================
    // VIEWS
    // ============================================================
    function earned(address account) public view returns (uint256) {
        uint256 pending;
        if (balanceOf[account] > 0) {
            pending = balanceOf[account]
                * (_rewardPerShare() - userRewardPerShare[account])
                / REWARD_PRECISION;
        }
        return pending + rewards[account];
    }

    function _rewardPerShare() internal view returns (uint256) {
        if (totalStaked == 0) return rewardPerShareStored;
        uint256 timeElapsed = _lastTimeRewardApplicable() - lastUpdateTime;
        uint256 newRewards = timeElapsed * rewardRate;
        return rewardPerShareStored + (newRewards * REWARD_PRECISION / totalStaked);
    }

    function _lastTimeRewardApplicable() internal view returns (uint256) {
        uint256 t = block.timestamp;
        return t < periodFinish ? t : periodFinish;
    }

    // ============================================================
    // INTERNAL
    // ============================================================
    modifier updateReward(address account) {
        rewardPerShareStored = _rewardPerShare();
        lastUpdateTime = _lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerShare[account] = rewardPerShareStored;
        }
        _;
    }

    function _claimPendingReward(address account) internal {
        uint256 pending = rewards[account];
        if (pending > 0) {
            rewards[account] = 0;
            rewardToken.transfer(account, pending);
            emit RewardPaid(account, pending);
        }
    }
}

/**
 * THREE POTENTIAL BUGS. SOME ARE REAL, SOME ARE NOT.
 * YOUR TASK: trace every path, prove with exact numbers.
 *
 * ============================================================
 * BUG #1 HINTS (rewardRate integer division)
 * ============================================================
 * Line: rewardRate = reward / duration
 *
 * No decimals. No scaling. Simple integer division.
 *
 * If reward = 1e18 and duration = 30 days (2,592,000 seconds):
 *   rewardRate = 1e18 / 2,592,000 = 385,802,469,135
 *   → works — rewardRate > 0
 *
 * But what if reward = 1000e18 and duration = 1 year (31,536,000)?
 *   rewardRate = 1000e18 / 31,536,000 = ~31,709,791,983
 *   → still works
 *
 * What about a SHORT reward period with a SMALL reward?
 *   reward = 1000 (dust), duration = 7 days = 604,800
 *   rewardRate = 1000 / 604,800 = 0
 *   → ZERO reward rate!
 *
 * Is this exploitable? Or just informational (admin mistake)?
 * Can the attacker force a zero rewardRate?
 * Where does the reward token go if rewardRate = 0?
 *
 * ============================================================
 * BUG #2 HINTS (emergencyWithdraw burns user rewards)
 * ============================================================
 * Look carefully at emergencyWithdraw():
 *   1. Updates global rewardPerShareStored and lastUpdateTime
 *   2. clears balanceOf[msg.sender]
 *   3. transfers staking tokens back
 *   4. does NOT call _claimPendingReward()
 *   5. does NOT update userRewardPerShare[msg.sender]
 *   6. does NOT update rewards[msg.sender]
 *
 * The user walks away with their stake but FORGOES all pending rewards.
 *
 * Where do those rewards go? They're "baked into" rewardPerShareStored.
 * The higher rewardPerShareStored means the REMAINING stakers will claim
 * those rewards on their NEXT interaction (deposit/withdraw/getReward).
 *
 * ATTACK PATH: Alice stakes 1000 tokens. Bob stakes 1000 tokens.
 * Pool runs for 7 days. Alice calls emergencyWithdraw() on day 6.
 * What happens to Alice's pending rewards? Who gets them?
 *
 * Calculate EXACT numbers.
 *
 * ============================================================
 * BUG #3 HINTS (reward extension dilution)
 * ============================================================
 * Line: if an existing reward period is active and notifyRewardAmount
 * is called again, the remaining time is recalculated:
 *   leftover = remaining * rewardRate;
 *   rewardRate = (reward + leftover) / duration;  // NEW duration!
 *
 * This means if the current period has 1 day left with rate=100/day,
 * and you add 100 rewards with duration=30 days:
 *   remaining = 1 day    leftover = 1 * 100 = 100
 *   rewardRate = (100 + 100) / 30 days = ~0.000077/second
 *   → The reward rate just got CRUSHED, spreading rewards over 30 days.
 *
 * Is this a bug or documented behavior?
 * Same pattern exists in Synthetix StakingRewards.sol.
 * Honest verdict: ________________________________
 *
 * ============================================================
 * YOUR TASK
 * ============================================================
 * 1. Determine which bugs are real and exploitable
 * 2. Prove the REAL bugs with EXACT Foundry numbers
 * 3. For any false alarms: explain WHY honestly
 * 4. For each: severity + real-world precedent
 *
 * REMEMBER: emergencyWithdraw is particularly subtle because
 * the reward "theft" happens through accounting, not through
 * an explicit drain. Trace the rewardPerShare math carefully.
 */
