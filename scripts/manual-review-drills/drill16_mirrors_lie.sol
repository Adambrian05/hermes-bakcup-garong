// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * DRILL 16: THE MIRROR'S LIE
 * Difficulty: EXPERT
 * Focus: Read-Only Reentrancy via ERC777/ERC721 callbacks
 *
 * THREE BUGS. ALL REAL PATTERNS FROM PRODUCTION EXPLOITS.
 *
 * Bug #1: View function reads state that can be stale during reentrancy
 * Bug #2: Protocol trusts oracle price from view function without lock check
 * Bug #3: Token callback fires BEFORE state update (balance decremented AFTER transfer)
 *
 * REAL-WORLD:
 * - Curve Vyper pools $73M (July 2023): get_virtual_price() stale during callback
 * - Euler Finance: read-only reentrancy via flash loan callback
 * - Balancer/Aura: getRate() stale during vault reentrancy
 * - Multiple C4/Sherlock HIGH findings every cycle
 */

// ============================================================
// CONTRACT 1: ReentrantToken (ERC777-like with hooks)
// ============================================================
interface ITokenReceiver {
    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata data
    ) external;
}

contract ReentrantToken {
    string public name = "HookToken";
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // BUG #3: transfer fires callback BEFORE updating sender's balance
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");

        // Callback FIRST — sender's balance NOT yet decremented
        if (_hasHook(to)) {
            ITokenReceiver(to).tokensReceived(
                msg.sender, msg.sender, to, amount, ""
            );
        }

        // State update AFTER callback
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
        require(allowance[from][msg.sender] >= amount, "not approved");

        if (_hasHook(to)) {
            ITokenReceiver(to).tokensReceived(
                msg.sender, from, to, amount, ""
            );
        }

        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function _hasHook(address addr) internal view returns (bool) {
        uint256 size;
        assembly { size := extcodesize(addr) }
        return size > 0;
    }
}

// ============================================================
// CONTRACT 2: LendingPool (borrow against collateral)
// ============================================================
contract LendingPool {
    ReentrantToken public collateralToken;
    ReentrantToken public borrowToken;

    mapping(address => uint256) public collateral;
    mapping(address => uint256) public debt;
    uint256 public totalCollateral;
    uint256 public totalBorrowed;

    bool public locked; // reentrancy guard

    constructor(address _collateral, address _borrow) {
        collateralToken = ReentrantToken(_collateral);
        borrowToken = ReentrantToken(_borrow);
    }

    modifier nonReentrant() {
        require(!locked, "reentrancy");
        locked = true;
        _;
        locked = false;
    }

    function deposit(uint256 amount) external nonReentrant {
        collateralToken.transferFrom(msg.sender, address(this), amount);
        collateral[msg.sender] += amount;
        totalCollateral += amount;
    }

    function borrow(uint256 amount) external nonReentrant {
        // BUG #2: uses getVirtualPrice() which is a VIEW but reads mutable state
        uint256 collateralValue = collateral[msg.sender] * getVirtualPrice() / 1e18;
        uint256 newDebt = debt[msg.sender] + amount;

        require(collateralValue >= newDebt * 150 / 100, "undercollateralized"); // 150% CR

        debt[msg.sender] = newDebt;
        totalBorrowed += amount;
        borrowToken.transfer(msg.sender, amount);
    }

    // BUG #1: View function reads state that CAN be stale during reentrancy
    // The nonReentrant guard blocks STATE-CHANGING functions but NOT views.
    // An attacker inside a token callback can call this view and get
    // a price that doesn't reflect the in-flight transfer.
    function getVirtualPrice() public view returns (uint256) {
        if (totalCollateral == 0) return 1e18;
        // Price = total collateral value / total supply
        // During reentrancy, totalCollateral is STILL the old value
        // because the state update hasn't happened yet.
        return collateralToken.balanceOf(address(this)) * 1e18 / totalCollateral;
    }

    function liquidate(address borrower) external nonReentrant {
        // Liquidation check also uses getVirtualPrice()
        uint256 collateralValue = collateral[borrower] * getVirtualPrice() / 1e18;
        uint256 borrowerDebt = debt[borrower];

        require(collateralValue < borrowerDebt * 150 / 100, "healthy");

        // Liquidator pays debt, gets collateral at 10% bonus
        uint256 liquidationBonus = borrowerDebt * 110 / 100;
        uint256 collateralReceived = liquidationBonus * 1e18 / getVirtualPrice();

        require(collateral[borrower] >= collateralReceived, "insufficient collateral");

        // Transfer debt from liquidator
        borrowToken.transferFrom(msg.sender, address(this), borrowerDebt);

        debt[borrower] = 0;
        collateral[borrower] -= collateralReceived;
        totalCollateral -= collateralReceived;
        totalBorrowed -= borrowerDebt;

        collateralToken.transfer(msg.sender, collateralReceived);
    }

    function repay(uint256 amount) external nonReentrant {
        borrowToken.transferFrom(msg.sender, address(this), amount);
        debt[msg.sender] -= amount;
        totalBorrowed -= amount;
    }

    function withdraw(uint256 amount) external nonReentrant {
        require(collateral[msg.sender] >= amount, "insufficient");

        uint256 remainingCollateral = collateral[msg.sender] - amount;
        uint256 remainingValue = remainingCollateral * getVirtualPrice() / 1e18;
        require(remainingValue >= debt[msg.sender] * 150 / 100, "undercollateralized");

        collateral[msg.sender] -= amount;
        totalCollateral -= amount;
        collateralToken.transfer(msg.sender, amount);
    }
}

/**
 * THREE BUGS. PROVE ALL THREE WITH EXACT NUMBERS.
 *
 * SCENARIO:
 * - Collateral token is ReentrantToken (has hooks on transfer)
 * - Borrow token is a normal token
 * - Attacker has 1000 collateral deposited
 * - Pool has 5000 collateral total, 2000 borrowed
 * - getVirtualPrice() = 5000 / 5000 = 1.0 (1:1)
 *
 * BUG #1 HINTS (Stale View):
 * - getVirtualPrice() reads collateralToken.balanceOf(pool) / totalCollateral
 * - During reentrancy (inside tokensReceived callback):
 *   → collateral token balance of pool has NOT been updated yet
 *     (transfer updates AFTER callback)
 *   → BUT totalCollateral IS still the old value
 *   → So getVirtualPrice() returns STALE data
 *
 * BUG #3 HINTS (Callback Before State):
 * - ReentrantToken.transfer() fires tokensReceived BEFORE decrementing balanceOf
 * - Inside callback, balanceOf[pool] shows the OLD balance (before transfer)
 * - totalCollateral also shows the OLD value
 * - Both are stale, but in DIFFERENT ways — think about which is bigger
 *
 * BUG #2 HINTS (Trusts Stale Price):
 * - borrow() uses getVirtualPrice() to check collateral ratio
 * - liquidate() uses getVirtualPrice() to calculate collateral received
 * - If getVirtualPrice() is INFLATED during reentrancy:
 *   → borrow() thinks you have MORE collateral → borrow more than allowed
 *   → liquidate() gives liquidator LESS collateral per unit of debt
 *
 * THE ATTACK:
 * 1. Attacker deposits 1000 collateral → has position
 * 2. Attacker creates a hook contract (implements ITokenReceiver)
 * 3. Attacker calls pool.withdraw(500)
 * 4. Inside withdraw, collateralToken.transfer(attacker_hook, 500) is called
 * 5. Hook fires BEFORE pool's state update
 * 6. Inside callback, attacker calls pool.borrow(X)
 *    → nonReentrant blocks it! So...
 * 7. WAIT — nonReentrant blocks state-changing calls too.
 *    → But what about LIQUIDATE? Same guard.
 *    → So the attack must be different...
 *
 * REAL ATTACK VECTOR:
 * - Attacker sends collateral token DIRECTLY to pool (not via deposit)
 *   → balanceOf[pool] increases but totalCollateral stays same
 *   → getVirtualPrice() inflates
 * - Then attacker (or victim) calls borrow/liquidate using inflated price
 *
 * WAIT — that's a donation attack, not read-only reentrancy.
 *
 * ACTUAL READ-ONLY REENTRANCY:
 * - Pool uses an EXTERNAL price oracle that ITSELF has reentrancy
 * - Or: there's a SECOND protocol that reads LendingPool.getVirtualPrice()
 *   without checking the lock
 * - Attacker reenters the pool during a callback
 * - While locked, calls a VIEW function on the pool
 * - Passes the stale price to the SECOND protocol
 * - Second protocol acts on stale price
 *
 * YOUR TASK:
 * 1. Identify ALL THREE bugs precisely
 * 2. Show why Bug #2 + Bug #1 + Bug #3 compose into an exploit
 * 3. The nonReentrant guard blocks direct reentrancy on pool functions
 *    → Show how the attacker bypasses this using a THIRD PARTY protocol
 * 4. Calculate EXACT profit with numbers
 *
 * HINT: Create a "PriceConsumer" contract that reads getVirtualPrice()
 * and uses it for pricing. The attacker's hook contract calls PriceConsumer
 * during the callback, gets stale price, and exploits it.
 *
 * SHOW EXACT NUMBERS FOR EACH STEP.
 */
