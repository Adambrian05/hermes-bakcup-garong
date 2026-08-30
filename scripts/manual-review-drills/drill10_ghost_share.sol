// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * DRILL 10: THE GHOST SHARE
 * Difficulty: HARD+
 * Focus: Share manipulation, cross-tx attack, rounding exploitation
 * 
 * THIS DRILL HAS A REAL BUG. Find it. Prove it with exact numbers.
 * 
 * RULES:
 * - No tools. Read the code.
 * - The bug is EXPLOITABLE for profit.
 * - You need to show: attacker starts with X, ends with Y > X.
 * - The victim loses exactly (Y - X).
 * - Show the EXACT transaction sequence.
 */

// ============================================================
// CONTRACT 1: YieldVault (ERC4626-like with reward distribution)
// ============================================================
contract YieldVault {
    uint256 public totalShares;
    uint256 public totalDeposits;  // principal only (not including yield)
    uint256 public totalYield;     // accumulated yield
    
    mapping(address => uint256) public shares;
    mapping(address => uint256) public yieldCheckpoint; // per-user yield snapshot
    
    uint256 public yieldPerShare;  // accumulated yield per share (scaled by 1e18)
    uint256 private lastYieldUpdate;
    
    // Yield accrues over time (simulated)
    uint256 public yieldRate; // yield per second per total deposit (scaled 1e18)

    constructor() {
        lastYieldUpdate = block.timestamp;
        yieldRate = 1e12; // small yield rate
    }

    function _accrueYield() internal {
        if (totalDeposits == 0) {
            lastYieldUpdate = block.timestamp;
            return;
        }
        uint256 elapsed = block.timestamp - lastYieldUpdate;
        if (elapsed == 0) return;
        
        uint256 newYield = totalDeposits * yieldRate * elapsed / 1e18;
        totalYield += newYield;
        yieldPerShare += newYield * 1e18 / totalShares;
        lastYieldUpdate = block.timestamp;
    }

    function totalAssets() public view returns (uint256) {
        uint256 elapsed = block.timestamp - lastYieldUpdate;
        uint256 pendingYield = 0;
        if (totalDeposits > 0 && elapsed > 0) {
            pendingYield = totalDeposits * yieldRate * elapsed / 1e18;
        }
        return totalDeposits + totalYield + pendingYield;
    }

    function deposit(uint256 assets) external returns (uint256 sharesOut) {
        _accrueYield();
        require(assets > 0, "zero");
        
        uint256 currentAssets = totalDeposits + totalYield;
        
        if (totalShares == 0) {
            sharesOut = assets;
        } else {
            sharesOut = assets * totalShares / currentAssets;
        }
        
        totalShares += sharesOut;
        totalDeposits += assets;
        shares[msg.sender] += sharesOut;
        yieldCheckpoint[msg.sender] = yieldPerShare;
    }

    function withdraw(uint256 sharesIn) external returns (uint256 assetsOut) {
        _accrueYield();
        require(sharesIn > 0 && sharesIn <= shares[msg.sender], "bad");
        
        uint256 currentAssets = totalDeposits + totalYield;
        assetsOut = sharesIn * currentAssets / totalShares;
        
        // Calculate user's yield portion
        uint256 userYield = sharesIn * (yieldPerShare - yieldCheckpoint[msg.sender]) / 1e18;
        
        shares[msg.sender] -= sharesIn;
        totalShares -= sharesIn;
        
        // HERE IS THE INTERESTING PART:
        // We reduce totalDeposits by the principal portion
        uint256 principalPortion = assetsOut > userYield ? assetsOut - userYield : 0;
        totalDeposits -= principalPortion;
        totalYield -= userYield;
        
        yieldCheckpoint[msg.sender] = yieldPerShare;
        
        // In real code: IERC20(asset).transfer(msg.sender, assetsOut);
    }

    function withdrawAll() external returns (uint256 assetsOut) {
        uint256 userShares = shares[msg.sender];
        require(userShares > 0, "no shares");
        
        // Delegate to withdraw
        _accrueYield();
        
        uint256 currentAssets = totalDeposits + totalYield;
        assetsOut = userShares * currentAssets / totalShares;
        
        uint256 userYield = userShares * (yieldPerShare - yieldCheckpoint[msg.sender]) / 1e18;
        
        shares[msg.sender] = 0;
        totalShares -= userShares;
        
        uint256 principalPortion = assetsOut > userYield ? assetsOut - userYield : 0;
        totalDeposits -= principalPortion;
        totalYield -= userYield;
        
        // In real code: IERC20(asset).transfer(msg.sender, assetsOut);
    }

    function pendingYield(address user) external view returns (uint256) {
        uint256 elapsed = block.timestamp - lastYieldUpdate;
        uint256 currentYPS = yieldPerShare;
        if (totalDeposits > 0 && elapsed > 0 && totalShares > 0) {
            uint256 pending = totalDeposits * yieldRate * elapsed / 1e18;
            currentYPS += pending * 1e18 / totalShares;
        }
        return shares[user] * (currentYPS - yieldCheckpoint[user]) / 1e18;
    }
}

// ============================================================
// CONTRACT 2: StakingRewards (distributes rewards based on vault shares)
// ============================================================
contract StakingRewards {
    YieldVault public immutable vault;
    
    uint256 public rewardRate = 1e15; // rewards per second
    uint256 public lastRewardUpdate;
    uint256 public rewardPerShare; // scaled 1e18
    uint256 public totalStaked; // total vault shares staked here
    
    mapping(address => uint256) public stakedShares;
    mapping(address => uint256) public rewardCheckpoint;
    mapping(address => uint256) public claimableRewards;

    constructor(address _vault) {
        vault = YieldVault(_vault);
        lastRewardUpdate = block.timestamp;
    }

    function _updateRewards() internal {
        if (totalStaked == 0) {
            lastRewardUpdate = block.timestamp;
            return;
        }
        uint256 elapsed = block.timestamp - lastRewardUpdate;
        if (elapsed == 0) return;
        
        uint256 newRewards = rewardRate * elapsed;
        rewardPerShare += newRewards * 1e18 / totalStaked;
        lastRewardUpdate = block.timestamp;
    }

    // Stake vault shares to earn rewards
    function stake(uint256 sharesAmount) external {
        _updateRewards();
        require(sharesAmount > 0, "zero");
        
        // In real code: vault.transferFrom(msg.sender, address(this), sharesAmount);
        
        // Accrue pending rewards before updating
        claimableRewards[msg.sender] += 
            stakedShares[msg.sender] * (rewardPerShare - rewardCheckpoint[msg.sender]) / 1e18;
        
        stakedShares[msg.sender] += sharesAmount;
        totalStaked += sharesAmount;
        rewardCheckpoint[msg.sender] = rewardPerShare;
    }

    // Unstake vault shares
    function unstake(uint256 sharesAmount) external {
        _updateRewards();
        require(sharesAmount <= stakedShares[msg.sender], "too much");
        
        claimableRewards[msg.sender] += 
            stakedShares[msg.sender] * (rewardPerShare - rewardCheckpoint[msg.sender]) / 1e18;
        
        stakedShares[msg.sender] -= sharesAmount;
        totalStaked -= sharesAmount;
        rewardCheckpoint[msg.sender] = rewardPerShare;
        
        // In real code: vault.transfer(msg.sender, sharesAmount);
    }

    // Claim accumulated rewards
    function claimRewards() external returns (uint256) {
        _updateRewards();
        
        claimableRewards[msg.sender] += 
            stakedShares[msg.sender] * (rewardPerShare - rewardCheckpoint[msg.sender]) / 1e18;
        rewardCheckpoint[msg.sender] = rewardPerShare;
        
        uint256 rewards = claimableRewards[msg.sender];
        claimableRewards[msg.sender] = 0;
        
        // In real code: IERC20(rewardToken).transfer(msg.sender, rewards);
        return rewards;
    }

    function earned(address user) external view returns (uint256) {
        uint256 elapsed = block.timestamp - lastRewardUpdate;
        uint256 currentRPS = rewardPerShare;
        if (totalStaked > 0 && elapsed > 0) {
            currentRPS += rewardRate * elapsed * 1e18 / totalStaked;
        }
        return claimableRewards[user] + 
            stakedShares[user] * (currentRPS - rewardCheckpoint[user]) / 1e18;
    }
}

// ============================================================
// CONTRACT 3: FlashMinter (flash loans with fee)
// ============================================================
contract FlashMinter {
    uint256 public constant FEE_BPS = 9; // 0.09% fee
    
    function flashLoan(uint256 amount, address target, bytes calldata data) external {
        uint256 fee = amount * FEE_BPS / 10000;
        
        // In real code: IERC20(token).transfer(target, amount);
        
        // Callback
        (bool success,) = target.call(data);
        require(success, "flash loan failed");
        
        // In real code: require(IERC20(token).balanceOf(address(this)) >= amount + fee);
    }
}

/**
 * THE BUG EXISTS. Find it.
 * 
 * HINTS (in order of subtlety):
 * 
 * 1. Look at how totalDeposits and totalYield are tracked SEPARATELY.
 *    What happens when you withdraw MORE yield than your "fair share"?
 * 
 * 2. Look at the principalPortion calculation in withdraw():
 *    principalPortion = assetsOut - userYield
 *    What if userYield is calculated WRONG?
 * 
 * 3. The yieldCheckpoint is updated to yieldPerShare AFTER withdrawal.
 *    But what about the shares that REMAIN? Do they get the right checkpoint?
 * 
 * 4. MULTI-TX: What if you deposit, wait for yield, withdraw PARTIAL,
 *    then deposit AGAIN? What happens to the checkpoint?
 * 
 * 5. COMPOSE: StakingRewards tracks shares. YieldVault tracks shares.
 *    If you unstake from StakingRewards and withdraw from YieldVault
 *    in the right order... what gets double-counted?
 * 
 * ATTACK SCENARIO TO PROVE:
 * - Attacker starts with 100 ETH
 * - Show exact tx sequence
 * - Show exact profit in wei
 * - Show who loses and exactly how much
 */
