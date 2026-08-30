// DRILL 4 — Level 3: Two Contracts, Cross-Contract State
// Timer: 15 min | Actors: depositor, borrower, keeper
// Focus: State desync between contracts, callback manipulation
// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title VaultManager — manages collateralized debt positions
contract VaultManager is ReentrancyGuard {
    struct Vault {
        uint256 collateral;     // ETH deposited
        uint256 debt;           // stablecoin minted
        uint256 lastUpdate;
    }
    
    IERC20 public immutable stablecoin;
    IPriceFeed public priceFeed;
    IVaultHook public hook;
    
    mapping(address => Vault) public vaults;
    uint256 public totalDebt;
    uint256 public totalCollateral;
    
    uint256 public constant MIN_COLLATERAL_RATIO = 150; // 150%
    uint256 public constant LIQUIDATION_RATIO = 120;    // 120%
    uint256 public constant LIQUIDATION_PENALTY = 10;   // 10%
    
    constructor(address _stable, address _priceFeed, address _hook) {
        stablecoin = IERC20(_stable);
        priceFeed = IPriceFeed(_priceFeed);
        hook = IVaultHook(_hook);
    }
    
    function openVault() external payable nonReentrant {
        require(vaults[msg.sender].collateral == 0, "exists");
        require(msg.value > 0, "no collateral");
        
        vaults[msg.sender] = Vault({
            collateral: msg.value,
            debt: 0,
            lastUpdate: block.timestamp
        });
        totalCollateral += msg.value;
        
        hook.onVaultOpened(msg.sender, msg.value);
    }
    
    function mintStable(uint256 amount) external nonReentrant {
        Vault storage v = vaults[msg.sender];
        require(v.collateral > 0, "no vault");
        
        uint256 newDebt = v.debt + amount;
        uint256 collateralValue = v.collateral * priceFeed.getPrice() / 1e18;
        require(collateralValue * 100 / newDebt >= MIN_COLLATERAL_RATIO, "undercollateralized");
        
        v.debt = newDebt;
        v.lastUpdate = block.timestamp;
        totalDebt += amount;
        
        stablecoin.transfer(msg.sender, amount);
        
        hook.onDebtChanged(msg.sender, newDebt);
    }
    
    function repay(uint256 amount) external nonReentrant {
        Vault storage v = vaults[msg.sender];
        require(amount <= v.debt, "over repay");
        
        stablecoin.transferFrom(msg.sender, address(this), amount);
        
        v.debt -= amount;
        v.lastUpdate = block.timestamp;
        totalDebt -= amount;
        
        hook.onDebtChanged(msg.sender, v.debt);
    }
    
    function withdrawCollateral(uint256 amount) external nonReentrant {
        Vault storage v = vaults[msg.sender];
        require(amount <= v.collateral, "insufficient");
        
        uint256 newCollateral = v.collateral - amount;
        if (v.debt > 0) {
            uint256 collateralValue = newCollateral * priceFeed.getPrice() / 1e18;
            require(collateralValue * 100 / v.debt >= MIN_COLLATERAL_RATIO, "undercollateralized");
        }
        
        v.collateral = newCollateral;
        totalCollateral -= amount;
        
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "transfer failed");
        
        hook.onCollateralChanged(msg.sender, newCollateral);
    }
    
    function liquidate(address target) external nonReentrant {
        Vault storage v = vaults[target];
        require(v.debt > 0, "no debt");
        
        uint256 collateralValue = v.collateral * priceFeed.getPrice() / 1e18;
        require(collateralValue * 100 / v.debt < LIQUIDATION_RATIO, "healthy");
        
        uint256 penalty = v.collateral * LIQUIDATION_PENALTY / 100;
        uint256 liquidatorReward = penalty;
        uint256 debtToRepay = v.debt;
        
        // Liquidator repays debt
        stablecoin.transferFrom(msg.sender, address(this), debtToRepay);
        
        // Liquidator gets collateral + penalty
        uint256 collateralOut = v.collateral;
        v.collateral = 0;
        v.debt = 0;
        totalDebt -= debtToRepay;
        totalCollateral -= collateralOut;
        
        (bool ok,) = msg.sender.call{value: collateralOut}("");
        require(ok, "transfer failed");
        
        hook.onLiquidation(target, msg.sender, collateralOut);
    }
    
    function getVaultValue(address user) external view returns (uint256) {
        return vaults[user].collateral * priceFeed.getPrice() / 1e18;
    }
}

/// @title PriceFeed — TWAP oracle with keeper updates
contract PriceFeed is IPriceFeed {
    uint256 public price;
    uint256 public lastUpdate;
    uint256 public updateCount;
    address public keeper;
    
    // Ring buffer for TWAP
    uint256[10] public priceHistory;
    uint256[10] public timeHistory;
    uint256 public historyIndex;
    
    constructor(address _keeper, uint256 _initialPrice) {
        keeper = _keeper;
        price = _initialPrice;
        lastUpdate = block.timestamp;
    }
    
    function updatePrice(uint256 newPrice) external {
        require(msg.sender == keeper, "not keeper");
        require(newPrice > 0, "zero price");
        
        // Store in ring buffer
        priceHistory[historyIndex] = price;
        timeHistory[historyIndex] = block.timestamp;
        historyIndex = (historyIndex + 1) % 10;
        
        price = newPrice;
        lastUpdate = block.timestamp;
        updateCount++;
    }
    
    function getPrice() external view returns (uint256) {
        // Return TWAP if enough history, else spot
        if (updateCount < 10) return price;
        
        uint256 sum;
        for (uint256 i = 0; i < 10; i++) {
            sum += priceHistory[i];
        }
        return sum / 10;
    }
    
    function getSpotPrice() external view returns (uint256) {
        return price;
    }
}

interface IPriceFeed {
    function getPrice() external view returns (uint256);
}

interface IVaultHook {
    function onVaultOpened(address user, uint256 collateral) external;
    function onDebtChanged(address user, uint256 newDebt) external;
    function onCollateralChanged(address user, uint256 newCollateral) external;
    function onLiquidation(address target, address liquidator, uint256 collateral) external;
}

/*
=== HINTS ===

Hint 1: liquidate() — liquidator gets ALL collateral, not just enough to cover debt.
        Is that correct? What if collateral >> debt?

Hint 2: PriceFeed TWAP — priceHistory stores OLD price, not new.
        When is the NEW price included in TWAP?

Hint 3: hook.onLiquidation() is called AFTER state changes but BEFORE...
        wait, no. State changes happen first. But hook is external call.
        What can hook do?

Hint 4: withdrawCollateral sends ETH via call. Hook is called AFTER.
        Can user re-enter via receive() fallback?
        → nonReentrant blocks it. But what about hook?

Hint 5: mintStable checks collateral ratio using priceFeed.getPrice().
        getPrice() returns TWAP. But spot price could be different.
        Can you mint at TWAP price but get liquidated at spot price?

=== ANSWER KEY ===

BUG 1 (HIGH): Liquidator gets ALL collateral, not proportional
  liquidate():
    collateralOut = v.collateral  // ALL of it
    liquidator pays: debtToRepay (just the debt)
    
  Example:
    Vault: 100 ETH collateral ($200K), 50K debt
    Ratio drops below 120%
    Liquidator pays 50K stablecoin
    Liquidator gets 100 ETH ($200K)
    PROFIT: $150K
    
  Should be: liquidator gets enough collateral to cover debt + penalty
  Not: ALL collateral regardless of debt size
  
  SEVERITY: HIGH — massive over-payment to liquidator

BUG 2 (HIGH): TWAP manipulation via keeper
  getPrice() returns average of priceHistory[0..9]
  priceHistory stores PREVIOUS prices (before update)
  
  Attack (if keeper compromised):
    1. Set price to 1000x normal for 1 update
    2. priceHistory[0] = 1000x (stored as "previous")
    3. Next 9 updates: normal price
    4. TWAP = (1000x + 9*normal) / 10 = ~100x normal
    
  With 100x price:
    → Collateral appears 100x more valuable
    → Can mint 100x more stablecoin
    → Then price normalizes → undercollateralized
    → Run away with minted stablecoins
    
  SEVERITY: HIGH if keeper is single EOA
            MEDIUM if keeper is multisig/DAO

BUG 3 (MEDIUM): Hook reentrancy window
  All hook calls happen AFTER state changes (good)
  But hook is an EXTERNAL call to arbitrary contract
  
  In liquidate():
    1. State updated (v.collateral = 0, v.debt = 0)
    2. ETH sent to liquidator
    3. hook.onLiquidation() called
    
  Hook can't re-enter VaultManager (nonReentrant)
  But hook CAN:
    → Call PriceFeed.updatePrice() if hook == keeper
    → Manipulate price for NEXT liquidation
    → Not direct reentrancy, but cross-contract manipulation
    
  SEVERITY: MEDIUM — depends on hook permissions

BUG 4 (LOW): TWAP includes stale data
  If no updates for 30 days:
    getPrice() returns average of 10 old prices
    All from 30 days ago
    → Stale oracle
    → No freshness check (no require on lastUpdate)
  
  SEVERITY: LOW — stale oracle, no time-bound check

BUG 5 (INFO): totalCollateral accounting in liquidate
  totalCollateral -= collateralOut (full amount)
  But liquidator got ALL collateral
  → Accounting is correct (all collateral left the system)
  → SAFE ✅

LESSONS:
  1. "Liquidator gets all collateral" is a classic bug.
     Always check: does the reward match the work?
  2. Oracle manipulation: WHO controls the input?
     Single keeper = single point of failure.
  3. TWAP is only as good as its update frequency.
     No freshness check = stale data risk.
  4. External hooks = trust boundary. What can they touch?
*/
