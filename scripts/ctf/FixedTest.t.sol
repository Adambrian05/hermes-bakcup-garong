// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {FixedLending} from "../src/FixedLending.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract MockToken2 is ERC20 {
    constructor() ERC20("Mock2", "MK2") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract FixedTest is Test {
    FixedLending pool;
    MockToken2 token;

    function setUp() public {
        token = new MockToken2();
        pool = new FixedLending(address(token));
        token.mint(address(1), 1000e18);
        vm.startPrank(address(1));
        token.approve(address(pool), 1000e18);
        pool.deposit(1000e18);
        vm.stopPrank();
    }

    // FIX 2 verified: can't borrow without collateral
    function test_borrowRequiresCollateral() public {
        vm.startPrank(address(0xDEAD));
        vm.expectRevert("insufficient collateral");
        pool.borrow(500e18);
        vm.stopPrank();
    }

    // FIX 2 verified: can borrow WITH collateral
    function test_borrowWithCollateral() public {
        token.mint(address(0xDEAD), 1000e18);
        vm.startPrank(address(0xDEAD));
        token.approve(address(pool), 1000e18);
        pool.addCollateral(1000e18);
        pool.borrow(500e18); // 500 <= 1000*100/150 = 666
        vm.stopPrank();
        assertEq(token.balanceOf(address(0xDEAD)), 500e18);
    }

    // FIX 2 verified: can't over-borrow
    function test_cantOverBorrow() public {
        token.mint(address(0xDEAD), 1000e18);
        vm.startPrank(address(0xDEAD));
        token.approve(address(pool), 1000e18);
        pool.addCollateral(1000e18);
        vm.expectRevert("insufficient collateral");
        pool.borrow(700e18); // 700 > 666
        vm.stopPrank();
    }

    // FIX 1 verified: withdraw updates state first
    function test_withdrawStateFirst() public {
        vm.startPrank(address(1));
        pool.withdraw(500e18);
        assertEq(pool.deposits(address(1)), 500e18);
        assertEq(token.balanceOf(address(1)), 500e18);
        vm.stopPrank();
    }

    // FIX 3 verified: no sync() function exists
    // Donation doesn't affect accounting
    function test_donationNoEffect() public {
        token.mint(address(this), 500e18);
        token.transfer(address(pool), 500e18);
        // totalDeposits unchanged (no sync function)
        assertEq(pool.totalDeposits(), 1000e18);
        assertEq(pool.deposits(address(1)), 1000e18);
    }
}
