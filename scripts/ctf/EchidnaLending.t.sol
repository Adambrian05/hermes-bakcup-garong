// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VulnerableLending} from "../src/VulnerableLending.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract MockToken3 is ERC20 {
    constructor() ERC20("Mock3", "MK3") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract EchidnaLending {
    VulnerableLending pool;
    MockToken3 token;
    uint256 public borrowCount;

    constructor() {
        token = new MockToken3();
        pool = new VulnerableLending(address(token));
        token.mint(address(this), 10000e18);
        token.approve(address(pool), 10000e18);
        pool.deposit(10000e18);
    }

    function doBorrow(uint256 amount) external {
        if (amount == 0) amount = 1;
        if (amount > 5000e18) amount = 5000e18;
        try pool.borrow(amount) {
            borrowCount++;
        } catch {}
    }

    // INVARIANT: If ANY borrow succeeded, the bug exists
    // (because this contract has NO collateral, yet can borrow)
    function echidna_no_uncollateralized_borrow() external view returns (bool) {
        // If borrowCount > 0, we borrowed without collateral = BUG
        return borrowCount == 0;
    }

    // INVARIANT: Solvency (passes — liquidity check works)
    function echidna_solvency() external view returns (bool) {
        return pool.totalBorrows() <= pool.totalDeposits();
    }
}
