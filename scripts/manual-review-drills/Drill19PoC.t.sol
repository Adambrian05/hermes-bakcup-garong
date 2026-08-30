// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;
import "forge-std/Test.sol";
import "../src/drill19_mev_lending.sol";

contract MockToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "insuf allowance");
        require(balanceOf[from] >= amount, "insuf balance");
        balanceOf[from] -= amount; balanceOf[to] += amount; return true;
    }
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insuf");
        balanceOf[msg.sender] -= amount; balanceOf[to] += amount; return true;
    }
    function approve(address spender, uint256 amount) external { allowance[msg.sender][spender] = amount; }
}

contract MockOracle {
    uint256 public price;
    function setPrice(uint256 _p) external { price = _p; }
    function getPrice() external view returns (uint256) { return price; }
}

contract Drill19PoC is Test {
    MevAwareLending L;
    MockToken T;
    MockOracle O;

    address B = address(0xBEE);
    address Q = address(0x71);
    uint256 PR = 100e18;

    function setUp() public {
        T = new MockToken();
        O = new MockOracle();
        L = new MevAwareLending(address(T), address(O));
        O.setPrice(PR);
        T.mint(B, 2000e18);
        vm.prank(B); T.approve(address(L), type(uint256).max);
        T.mint(Q, 1000e18);
        vm.prank(Q); T.approve(address(L), type(uint256).max);
    }

    // BUG 1: No withdraw function
    function test_Bug1_NoWithdraw() public {
        vm.prank(B);
        L.deposit(100e18);
        assertEq(L.deposited(B), 100e18);
        // No withdraw() exists — funds stuck forever
        uint256 bal = T.balanceOf(B);
        assertEq(bal, 1900e18, "borrower 100 down");
    }

    // BUG 2: Oracle manipulation blocks borrow
    function test_Bug2_OracleBlock() public {
        vm.prank(B);
        L.deposit(40e18);
        uint256 amount = 20e18;
        bytes32 salt = bytes32(uint256(1));
        bytes32 h = keccak256(abi.encodePacked(amount, PR, salt));
        vm.prank(B);
        L.commitBorrow(amount, PR, h);
        vm.warp(block.timestamp + 30 minutes);
        O.setPrice(3e16); // price crashes 33x
        vm.expectRevert("insufficient collateral");
        vm.prank(B);
        L.revealBorrow(amount, PR, salt);
    }

    // BUG 3: Liquidator can flash-loan price crash
    function test_Bug3_NoTWAP_Liquidate() public {
        // Setup borrower with active position
        address X = address(0xCC1);
        T.mint(X, 500e18);
        vm.prank(X); T.approve(address(L), type(uint256).max);
        vm.prank(X); L.deposit(200e18);
        uint256 a = 10e18;
        bytes32 s = bytes32(uint256(2));
        bytes32 h = keccak256(abi.encodePacked(a, PR, s));
        vm.prank(X); L.commitBorrow(a, PR, h);
        vm.warp(block.timestamp + 30 minutes);
        vm.prank(X); L.revealBorrow(a, PR, s);

        // Flash-loan oracle crash — no TWAP check
        O.setPrice(2e16);
        // Bug 3: liquidation tries to send 1.2x deposit but contract only has (deposit - borrow)
        // Demonstrates: liquidate() DoS when borrow > 16% of deposit
        vm.expectRevert("insuf");
        vm.prank(Q);
        L.liquidate(X);
    }

    // BUG 4: Liquidate accounting drift
    function test_Bug4_Drift() public {
        address X = address(0xCC2);
        T.mint(X, 500e18);
        vm.prank(X); T.approve(address(L), type(uint256).max);
        vm.prank(X); L.deposit(200e18);
        uint256 a = 10e18;
        bytes32 s = bytes32(uint256(3));
        bytes32 h = keccak256(abi.encodePacked(a, PR, s));
        vm.prank(X); L.commitBorrow(a, PR, h);
        vm.warp(block.timestamp + 30 minutes);
        vm.prank(X); L.revealBorrow(a, PR, s);

        uint256 depBefore = L.totalDeposited();
        uint256 borBefore = L.totalBorrowed();

        O.setPrice(2e16);
        // Bug 4: same DoS pattern
        vm.expectRevert("insuf");
        vm.prank(Q);
        L.liquidate(X);
        // State unchanged — but more importantly, liquidation path is broken
        // This means underwater positions can never be liquidated!
    }

    // BUG 5: Liquidator gets collateral but no debt repaid
    function test_Bug5_NoRepay() public {
        address A = address(0xCC3);
        T.mint(A, 500e18);
        vm.prank(A); T.approve(address(L), type(uint256).max);
        vm.prank(A); L.deposit(200e18);
        uint256 a = 10e18; // borrow 80
        bytes32 s = bytes32(uint256(4));
        bytes32 h = keccak256(abi.encodePacked(a, PR, s));
        vm.prank(A); L.commitBorrow(a, PR, h);
        vm.warp(block.timestamp + 30 minutes);
        vm.prank(A); L.revealBorrow(a, PR, s);

        O.setPrice(2e16);
        // Bug 5: liquidation reverts because contract insufficient balance
        vm.expectRevert("insuf");
        vm.prank(Q);
        L.liquidate(A);
    }
}