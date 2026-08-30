// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "../src/Drill8C_Differential.sol";

contract Drill8C_Test is Test {
    SafeLending safe;
    UnsafeLending unsafe;

    function setUp() public {
        safe = new SafeLending();
        unsafe = new UnsafeLending();
    }

    function test_Differential_SafeRejectsHugeBorrow() public {
        vm.expectRevert("exceeds limit");
        safe.borrow(2000 ether);
    }

    function test_Differential_UnsafeAcceptsHugeBorrow() public {
        unsafe.borrow(2000 ether);
        assertEq(unsafe.borrowed(address(this)), 2000 ether);
    }
}
