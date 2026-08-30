// DRILL 19 — Level 8: MEV-Aware Lending (Front-Running Protection Gone Wrong)
// Timer: 45 min | Actors: borrower, liquidator, MEV searcher, admin
// Focus: MEV-resistant design patterns that CREATE new attack surfaces
// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title MevAwareLending — commit-reveal borrow with oracle price
/// @notice Uses commit-reveal pattern to prevent MEV sandwich on borrow,
///         but introduces timing windows, stale price, and stuck collateral.
contract MevAwareLending {
    address public immutable collateral;
    address public oracle;

    mapping(address => uint256) public deposited;
    mapping(address => uint256) public borrowed;
    uint256 public totalDeposited;
    uint256 public totalBorrowed;

    struct Commit {
        uint256 amount;
        uint256 minPrice;
        uint256 deadline;
        bytes32 commitHash;
    }
    mapping(address => Commit) public commits;

    uint256 public constant COLLATERAL_BPS = 150; // 150%
    uint256 public constant LIQUIDATION_BPS = 250; // 250%
    uint256 public constant LIQUIDATION_DISCOUNT_BPS = 120; // 20% discount for liquidator
    uint256 public constant BPS = 100;

    constructor(address _collateral, address _oracle) {
        collateral = _collateral;
        oracle = _oracle;
    }

    /// @notice Depositor locks collateral in system for later borrow
    function deposit(uint256 amount) external {
        require(IERC20(collateral).transferFrom(msg.sender, address(this), amount), "transfer failed");
        deposited[msg.sender] += amount;
        totalDeposited += amount;
    }

    /// @notice Commit to borrow X at minimum price Y
    function commitBorrow(uint256 amount, uint256 minPrice, bytes32 commitHash) external {
        require(deposited[msg.sender] > 0, "no collateral");
        commits[msg.sender] = Commit(amount, minPrice, block.timestamp + 1 hours, commitHash);
    }

    /// @notice Reveal borrow with salt that matches commit hash
    function revealBorrow(uint256 amount, uint256 minPrice, bytes32 salt) external {
        Commit storage c = commits[msg.sender];
        require(c.amount > 0, "no commit");
        require(c.amount == amount, "amount mismatch");
        require(c.minPrice == minPrice, "price mismatch");

        bytes32 expectedHash = keccak256(abi.encodePacked(amount, minPrice, salt));
        require(expectedHash == c.commitHash, "invalid salt");
        require(block.timestamp <= c.deadline, "expired");

        uint256 currentPrice = IOracle(oracle).getPrice();
        uint256 collatRequired = (amount * COLLATERAL_BPS * 1e18) / (currentPrice * BPS);

        if (deposited[msg.sender] < collatRequired) {
            revert("insufficient collateral");
        }

        borrowed[msg.sender] += amount;
        totalBorrowed += amount;
        require(IERC20(collateral).transfer(msg.sender, amount), "transfer failed");
        delete commits[msg.sender];
    }

    /// @notice Liquidator can seize a position if deposit < 2.5x loan value
    function liquidate(address borrower) external {
        uint256 price = IOracle(oracle).getPrice();
        uint256 requiredDeposit = (borrowed[borrower] * LIQUIDATION_BPS * 1e18) / (price * BPS);

        if (deposited[borrower] < requiredDeposit) {
            uint256 liquidatorGets = (deposited[borrower] * LIQUIDATION_DISCOUNT_BPS) / BPS;

            deposited[borrower] = 0;
            borrowed[borrower] = 0;
            require(IERC20(collateral).transfer(msg.sender, liquidatorGets), "transfer failed");

            totalDeposited -= liquidatorGets;
            totalBorrowed -= 0;
        }
    }

    function getHealth(address user) external view returns (uint256) {
        uint256 price = IOracle(oracle).getPrice();
        uint256 needed = (borrowed[user] * COLLATERAL_BPS * 1e18) / (price * BPS);
        if (borrowed[user] == 0) return type(uint256).max;
        return (deposited[user] * 1e18) / needed;
    }
}

interface IOracle {
    function getPrice() external view returns (uint256);
}

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

/*
=== HINTS ===

Hint 1: deposit() locks collateral. Can you get it back?
        Search for a withdraw() function.

Hint 2: commitBorrow() creates a 1-hour reveal window. In that
        window, oracle price updates. What happens to the
        borrower's position if price moves unfavorably?

Hint 3: liquidate() assumes collateral can be seized at a discount.
        Does the borrower repay the loan? What happens to the
        protocol's accounting after liquidation?

Hint 4: oracle.getPrice() returns a single point price with no
        staleness check. What happens if the oracle is manipulated
        within the same block as liquidate()?

Hint 5: totalDeposited and totalBorrowed track the pool's state.
        After liquidate(), verify these counters add up correctly.

=== ANSWER KEY ===

BUG 1 (HIGH): No withdraw function — collateral locked forever
  The contract has deposit() but no withdraw(). Once a user
  deposits, their funds are permanently locked. If the
  commit window expires without reveal, the user cannot
  recover their collateral.

BUG 2 (MEDIUM): MEV protection bypassed via oracle manipulation
  Commit-reveal prevents front-running of the borrow decision,
  but the oracle price is read at revealBorrow() time. A
  searcher can flash-loan manipulate the oracle right before
  revealBorrow() to either:
  (a) Drop price → borrower's position becomes underwater,
      blocking the reveal
  (b) Pump price → borrower can over-borrow past collateral

BUG 3 (MEDIUM): No TWAP or freshness check on oracle
  Oracle provides single-point getPrice() with no age guard.
  A liquidator can flash-loan to poison the price within the
  same block as liquidate(), forcing every borrower into
  liquidation at manipulated prices.

BUG 4 (HIGH): Liquidate accounting error
  After liquidate():
    - deposited[borrower] = 0       (correct, collateral seized)
    - borrowed[borrower] = 0         (loan wiped, but unpaid!)
    - totalDeposited -= liquidatorGets  (decreases by discounted amount)
    - totalBorrowed -= 0              (NO-OP, loan wasn't paid)
  Result: totalBorrowed stays inflated. The protocol believes
  loans are outstanding that don't exist. Future depositors
  earn fees on phantom debt. Also: liquidator only pays
  120% of collateral, but the loan was for borrowed[borrower]
  tokens. If borrowed > 0.83 * deposited, protocol loses money.

BUG 5 (MEDIUM): Liquidator can pick collateral but no debt
  The liquidator receives collateral (deposit) at discount,
  but no debt repayment is enforced. Even if borrowed[borrower]
  > deposit * 1.2, the liquidator only pays 1.2 * deposit and
  walks away with the collateral. The borrower gets their
  remaining collateral wiped without paying back any debt.

LESSONS:
1. MEV protection (commit-reveal) must also secure LOCKED funds.
2. Commit-reveal locks the exchange rate decision, but oracle
   staleness remains an open attack vector.
3. Every borrow mechanism needs a withdraw route.
4. Liquidation must enforce debt repayment, not just collateral
   seizure at a discount.
5. Oracle with no TWAP or staleness check = free liquidation
   manipulation.
6. After liquidation, all accounting counters must reconcile.
*/
