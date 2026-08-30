// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * DRILL 9: THE SILENT DRAIN
 * Difficulty: HARD
 * Focus: Economic exploit, rounding manipulation, cross-function composition
 * 
 * RULES:
 * - Read the code. No tools.
 * - Form a hypothesis about how to extract value.
 * - Prove it with math (exact numbers, not "approximately").
 * - You have 3 contracts that interact. The bug is NOT in any single contract.
 *   It's in how they COMPOSE.
 * 
 * HINT: Follow the rounding. Every division is a choice. Someone pays for every wei lost.
 */

// ============================================================
// CONTRACT 1: VaultPool (ERC4626-like vault)
// ============================================================
contract VaultPool {
    string public name = "Drill Vault";
    uint256 public totalShares;
    uint256 public totalAssets;
    mapping(address => uint256) public shares;
    mapping(address => uint256) public assetBalance; // internal accounting

    // Deposit assets, receive shares
    function deposit(uint256 assets) external returns (uint256 sharesOut) {
        require(assets > 0, "zero");
        
        if (totalShares == 0) {
            sharesOut = assets; // first depositor: 1:1
        } else {
            sharesOut = assets * totalShares / totalAssets;
        }
        
        totalShares += sharesOut;
        totalAssets += assets;
        shares[msg.sender] += sharesOut;
        assetBalance[msg.sender] += assets;
        
        // In real code: IERC20(asset).transferFrom(msg.sender, address(this), assets);
    }

    // Withdraw assets by burning shares
    function withdraw(uint256 sharesIn) external returns (uint256 assetsOut) {
        require(sharesIn > 0 && sharesIn <= shares[msg.sender], "bad shares");
        
        assetsOut = sharesIn * totalAssets / totalShares;
        
        shares[msg.sender] -= sharesIn;
        totalShares -= sharesIn;
        totalAssets -= assetsOut;
        assetBalance[msg.sender] -= assetsOut;
        
        // In real code: IERC20(asset).transfer(msg.sender, assetsOut);
    }

    // Donate assets to the vault (increases value of all shares)
    function donate(uint256 assets) external {
        require(assets > 0, "zero");
        totalAssets += assets;
        // In real code: IERC20(asset).transferFrom(msg.sender, address(this), assets);
    }

    function pricePerShare() external view returns (uint256) {
        if (totalShares == 0) return 1e18;
        return totalAssets * 1e18 / totalShares;
    }
}

// ============================================================
// CONTRACT 2: LendingMarket (borrows against vault shares)
// ============================================================
contract LendingMarket {
    VaultPool public immutable vault;
    
    uint256 public constant LTV = 80e16; // 80% loan-to-value
    uint256 public constant LIQUIDATION_THRESHOLD = 85e16; // 85%
    uint256 public constant LIQUIDATION_PENALTY = 5e16; // 5%
    
    struct Position {
        uint256 collateralShares; // vault shares locked
        uint256 debt;             // tokens borrowed
    }
    
    mapping(address => Position) public positions;
    uint256 public totalDebt;
    uint256 public reserveBalance; // liquidation reserves

    constructor(address _vault) {
        vault = VaultPool(_vault);
    }

    // Lock vault shares as collateral, borrow tokens
    function borrow(uint256 sharesAmount, uint256 borrowAmount) external {
        require(sharesAmount > 0, "zero shares");
        
        // Transfer shares from user to this contract
        // In real code: vault.transferFrom(msg.sender, address(this), sharesAmount);
        
        uint256 collateralValue = sharesAmount * vault.totalAssets() / vault.totalShares();
        uint256 maxBorrow = collateralValue * LTV / 1e18;
        require(borrowAmount <= maxBorrow, "undercollateralized");
        
        positions[msg.sender].collateralShares += sharesAmount;
        positions[msg.sender].debt += borrowAmount;
        totalDebt += borrowAmount;
        
        // In real code: IERC20(token).transfer(msg.sender, borrowAmount);
    }

    // Repay debt
    function repay(uint256 amount) external {
        uint256 debt = positions[msg.sender].debt;
        uint256 repayAmount = amount > debt ? debt : amount;
        
        positions[msg.sender].debt -= repayAmount;
        totalDebt -= repayAmount;
        
        // In real code: IERC20(token).transferFrom(msg.sender, address(this), repayAmount);
    }

    // Withdraw collateral (if position is healthy after)
    function withdrawCollateral(uint256 sharesAmount) external {
        Position storage pos = positions[msg.sender];
        require(sharesAmount <= pos.collateralShares, "too much");
        
        pos.collateralShares -= sharesAmount;
        
        // Check position still healthy
        if (pos.debt > 0) {
            uint256 remainingValue = pos.collateralShares * vault.totalAssets() / vault.totalShares();
            require(pos.debt * 1e18 / remainingValue <= LTV, "would be undercollateralized");
        }
        
        // In real code: vault.transfer(msg.sender, sharesAmount);
    }

    // Liquidate an unhealthy position
    function liquidate(address user) external {
        Position storage pos = positions[user];
        require(pos.debt > 0, "no debt");
        
        uint256 collateralValue = pos.collateralShares * vault.totalAssets() / vault.totalShares();
        uint256 healthRatio = pos.debt * 1e18 / collateralValue;
        require(healthRatio > LIQUIDATION_THRESHOLD, "position healthy");
        
        // Liquidator pays the debt
        uint256 debtToRepay = pos.debt;
        
        // Calculate shares to seize (debt value + penalty)
        uint256 seizeValue = debtToRepay * (1e18 + LIQUIDATION_PENALTY) / 1e18;
        uint256 sharesToSeize = seizeValue * vault.totalShares() / vault.totalAssets();
        
        // Cap at available collateral
        if (sharesToSeize > pos.collateralShares) {
            sharesToSeize = pos.collateralShares;
        }
        
        // Update position
        pos.collateralShares -= sharesToSeize;
        pos.debt = 0;
        totalDebt -= debtToRepay;
        
        // Liquidator gets the seized shares
        // In real code: vault.transfer(msg.sender, sharesToSeize);
        
        // Liquidator paid the debt
        // In real code: IERC20(token).transferFrom(msg.sender, address(this), debtToRepay);
    }

    function getHealthRatio(address user) external view returns (uint256) {
        Position storage pos = positions[user];
        if (pos.debt == 0) return type(uint256).max;
        uint256 collateralValue = pos.collateralShares * vault.totalAssets() / vault.totalShares();
        return collateralValue * 1e18 / pos.debt;
    }
}

// ============================================================
// CONTRACT 3: FlashOracle (manipulable price source)
// ============================================================
contract FlashOracle {
    VaultPool public immutable vault;
    uint256 public lastPrice;
    uint256 public lastUpdate;
    
    constructor(address _vault) {
        vault = VaultPool(_vault);
        lastPrice = 1e18;
        lastUpdate = block.timestamp;
    }

    // "TWAP" that's actually just a spot price with stale fallback
    function getPrice() external returns (uint256) {
        uint256 currentPrice = vault.totalAssets() * 1e18 / vault.totalShares();
        
        // "Smoothing": average with last price (but only if updated > 1 block ago)
        if (block.timestamp > lastUpdate) {
            lastPrice = (currentPrice + lastPrice) / 2;
            lastUpdate = block.timestamp;
        }
        
        return lastPrice;
    }

    // Used by LendingMarket for "safer" valuations (but is it?)
    function getConservativePrice() external view returns (uint256) {
        uint256 currentPrice = vault.totalAssets() * 1e18 / vault.totalShares();
        // "Conservative" = min of current and last
        return currentPrice < lastPrice ? currentPrice : lastPrice;
    }
}

/**
 * QUESTIONS:
 * 
 * Q1: Can an attacker use donate() to manipulate the oracle and profit
 *     from liquidations? Trace the exact flow with numbers.
 * 
 * Q2: The LendingMarket uses vault.totalAssets()/totalShares() directly
 *     for collateral valuation. Can an attacker exploit the rounding
 *     in deposit/withdraw to get more collateral value than they deposited?
 *     (Hint: what happens with 1 wei of shares?)
 * 
 * Q3: The "conservative price" in FlashOracle — is it actually conservative?
 *     Can an attacker make it return a HIGHER price than reality?
 * 
 * Q4: Compose all three: Can an attacker open a position, manipulate the vault,
 *     get liquidated PROFITABLY (i.e., the seized shares are worth MORE than
 *     the debt they "owe")? Show the exact numbers.
 * 
 * Q5: BONUS — If the vault has only 1 share outstanding (totalShares = 1),
 *     what happens to the lending market's collateral calculation?
 *     Can this be weaponized?
 */
