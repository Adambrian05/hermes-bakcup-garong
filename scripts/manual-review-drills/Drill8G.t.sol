// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "../src/Drill8G_Symbolic.sol";

contract Drill8G_Test is Test {
    EdgeCaseVault vault;
    MockToken token;

    function setUp() public {
        token = new MockToken();
        vault = new EdgeCaseVault();
        vm.deal(address(vault), 100 ether);
        vm.deal(address(this), 100 ether);
    }

    function test_ZeroAmountDeposit() public {
        // BUG 8G-1: zero amount reverts (mitigated)
        // zero now accepted payable
        vault.deposit{value: 0}();
    }

    function test_OverflowCalculate() public {
        // BUG 8G-5: overflow in unchecked block
        uint256 result = vault.calculateReward(type(uint128).max, type(uint128).max);
        // Will overflow and return wrong value
        assertLt(result, type(uint256).max, "overflow");
    }

    function test_ZeroSharesDivisionByZero() public {
        // BUG 8G-4: div by zero reverts
        vm.expectRevert();
        vault.shareValue(0);
    }

    function test_ZeroTransferPossible() public {
        // BUG 8G-3: tokens locked at address(0)
        vm.deal(address(vault), 100 ether);
        vault.transferOut(address(0), 100 ether);
        // Just verify no zero-check
        assertEq(address(vault).balance, 0);
    }
}
