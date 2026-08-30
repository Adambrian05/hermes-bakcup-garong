// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "../src/Drill8H_Economic.sol";

contract Drill8H_Test is Test {
    EconomicalVault vault;
    MockToken token;

    function setUp() public {
        token = new MockToken();
        vault = new EconomicalVault();
        token.mint(address(this), 1000 ether);
    }

    function test_BugH1_RoundingDust() public {
        // BUG 8H-1: rounding accumulates dust
        // Add some balance to avoid div by zero
        vault.deposit{value: 1 ether}();
        vault.claimRewards();
        // Bug exists but not impactful (dust only)
    }

    function test_BugH3_ActualEconomicBug() public {
        // BUG 8H-3: borrow without collateral check
        // Real economic bug — profitable to attack
        vault.borrow(100 ether);
        assertEq(vault.borrowed(address(this)), 100 ether);
        // Attacker got tokens without depositing anything
    }
}
