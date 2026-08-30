// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @title Vulnerable Lending Pool — CTF Exercise
/// @notice Contains 3 bugs: CEI violation, no collateral, donation attack
contract VulnerableLending {
    mapping(address => uint256) public deposits;
    mapping(address => uint256) public borrows;
    uint256 public totalDeposits;
    uint256 public totalBorrows;
    IERC20 public token;

    constructor(address _token) {
        token = IERC20(_token);
    }

    function deposit(uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);
        deposits[msg.sender] += amount;
        totalDeposits += amount;
    }

    // BUG 1: CEI violation — transfer BEFORE state update
    function withdraw(uint256 amount) external {
        require(deposits[msg.sender] >= amount, "insufficient");
        token.transfer(msg.sender, amount); // external call FIRST
        deposits[msg.sender] -= amount;     // state update SECOND
        totalDeposits -= amount;
    }

    // BUG 2: No collateral check — anyone can borrow
    function borrow(uint256 amount) external {
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

    // BUG 3: Donation attack — balanceOf for accounting
    function sync() external {
        uint256 balance = token.balanceOf(address(this));
        if (balance > totalDeposits - totalBorrows) {
            uint256 excess = balance - (totalDeposits - totalBorrows);
            totalDeposits += excess;
            // deposits[] NOT updated → inconsistency
        }
    }
}
