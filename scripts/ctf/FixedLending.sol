// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @title Fixed Lending Pool — all 3 bugs patched
contract FixedLending {
    mapping(address => uint256) public deposits;
    mapping(address => uint256) public borrows;
    mapping(address => uint256) public collateral; // FIX 2: collateral tracking
    uint256 public totalDeposits;
    uint256 public totalBorrows;
    IERC20 public token;
    uint256 public constant COLLATERAL_RATIO = 150; // 150% collateralization

    constructor(address _token) {
        token = IERC20(_token);
    }

    function deposit(uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);
        deposits[msg.sender] += amount;
        totalDeposits += amount;
    }

    // FIX 1: CEI — state update BEFORE external call
    function withdraw(uint256 amount) external {
        require(deposits[msg.sender] >= amount, "insufficient");
        deposits[msg.sender] -= amount;     // state FIRST
        totalDeposits -= amount;
        token.transfer(msg.sender, amount); // external call SECOND
    }

    // FIX 2: Require collateral
    function addCollateral(uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);
        collateral[msg.sender] += amount;
    }

    function borrow(uint256 amount) external {
        // FIX 2: Check collateral
        uint256 maxBorrow = collateral[msg.sender] * 100 / COLLATERAL_RATIO;
        require(borrows[msg.sender] + amount <= maxBorrow, "insufficient collateral");
        require(totalBorrows + amount <= totalDeposits, "insufficient liquidity");
        borrows[msg.sender] += amount;
        totalBorrows += amount;
        token.transfer(msg.sender, amount);
    }

    function repay(uint256 amount) external {
        require(borrows[msg.sender] >= amount, "no debt");
        token.transferFrom(msg.sender, address(this), amount);
        borrows[msg.sender] -= amount;
        totalBorrows -= amount;
    }

    // FIX 3: Remove sync() — don't use balanceOf for accounting
    // Internal accounting (deposits/borrows) is the source of truth
}
