// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * DRILL 14: THE UPGRADE TRAP
 * Difficulty: EXPERT
 * Focus: Proxy storage collision, fee-on-transfer accounting, re-initialization
 *
 * THREE BUGS. ALL REAL. ALL FOUND IN PRODUCTION PROTOCOLS.
 *
 * Bug #1: Storage collision between proxy and implementation
 * Bug #2: Fee-on-transfer token breaks deposit/withdraw accounting
 * Bug #3: Initializer can be called again (re-initialization)
 *
 * REAL-WORLD:
 * - Storage collision: Parity multisig ($150M frozen, 2017)
 * - Fee-on-transfer: dozens of C4/Sherlock findings every year
 * - Re-initialization: multiple protocols, often CRITICAL
 */

// ============================================================
// CONTRACT 1: Proxy (minimal transparent proxy)
// ============================================================
contract Proxy {
    // Storage slot 0: admin
    address public admin;
    // Storage slot 1: implementation
    address public implementation;
    // Storage slot 2: pendingAdmin
    address public pendingAdmin;

    constructor(address _implementation) {
        admin = msg.sender;
        implementation = _implementation;
    }

    function upgradeTo(address newImpl) external {
        require(msg.sender == admin, "not admin");
        implementation = newImpl;
    }

    function changeAdmin(address newAdmin) external {
        require(msg.sender == admin, "not admin");
        pendingAdmin = newAdmin;
    }

    function acceptAdmin() external {
        require(msg.sender == pendingAdmin, "not pending");
        admin = pendingAdmin;
        pendingAdmin = address(0);
    }

    fallback() external payable {
        address impl = implementation;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}

// ============================================================
// CONTRACT 2: VaultV1 (first implementation)
// ============================================================
contract VaultV1 {
    // BUG #1: Storage layout COLLIDES with Proxy
    // Proxy uses slots 0,1,2 for admin, implementation, pendingAdmin
    // VaultV1 starts at slot 0 → OVERWRITES proxy admin!

    // Slot 0: totalDeposits (COLLIDES with Proxy.admin!)
    uint256 public totalDeposits;
    // Slot 1: totalShares (COLLIDES with Proxy.implementation!)
    uint256 public totalShares;
    // Slot 2: owner (COLLIDES with Proxy.pendingAdmin!)
    address public owner;
    // Slot 3: paused
    bool public paused;
    // Slot 4: token
    address public token;

    mapping(address => uint256) public balances;
    mapping(address => uint256) public shareBalances;

    bool private _initialized;

    function initialize(address _token, address _owner) external {
        // BUG #3: No proper re-initialization guard
        // _initialized check exists BUT...
        require(!_initialized, "already initialized");
        _initialized = true;

        token = _token;
        owner = _owner;
        totalDeposits = 0;
        totalShares = 0;
    }

    function deposit(uint256 amount) external {
        require(!paused, "paused");
        require(amount > 0, "zero");

        // BUG #2: Assumes transferFrom transfers EXACTLY `amount`
        // Fee-on-transfer tokens send LESS than `amount`
        IERC20Like(token).transferFrom(msg.sender, address(this), amount);

        uint256 shares;
        if (totalShares == 0) {
            shares = amount;
        } else {
            shares = amount * totalShares / totalDeposits;
        }

        totalDeposits += amount;  // ← Records FULL amount
        totalShares += shares;
        balances[msg.sender] += amount;
        shareBalances[msg.sender] += shares;
    }

    function withdraw(uint256 shares) external {
        require(shares > 0 && shares <= shareBalances[msg.sender], "bad");

        uint256 assets = shares * totalDeposits / totalShares;

        shareBalances[msg.sender] -= shares;
        totalShares -= shares;
        totalDeposits -= assets;
        balances[msg.sender] -= assets;

        IERC20Like(token).transfer(msg.sender, assets);
    }

    function emergencyWithdraw() external {
        require(msg.sender == owner, "not owner");
        // Drain all tokens to owner
        uint256 bal = IERC20Like(token).balanceOf(address(this));
        IERC20Like(token).transfer(owner, bal);
    }

    function pause() external {
        require(msg.sender == owner, "not owner");
        paused = true;
    }

    function unpause() external {
        require(msg.sender == owner, "not owner");
        paused = false;
    }
}

// ============================================================
// CONTRACT 3: VaultV2 (upgraded implementation — "fixes" V1)
// ============================================================
contract VaultV2 {
    // "Fixed" storage layout — but is it?
    // Slot 0: totalDeposits
    uint256 public totalDeposits;
    // Slot 1: totalShares
    uint256 public totalShares;
    // Slot 2: owner
    address public owner;
    // Slot 3: paused
    bool public paused;
    // Slot 4: token
    address public token;
    // Slot 5: NEW — feeNumerator
    uint256 public feeNumerator;
    // Slot 6: NEW — feeDenominator
    uint256 public feeDenominator;
    // Slot 7: NEW — guardian
    address public guardian;

    mapping(address => uint256) public balances;
    mapping(address => uint256) public shareBalances;

    bool private _initialized;
    uint256 private _initializedVersion;

    function initializeV2(address _guardian, uint256 _feeNum, uint256 _feeDenom) external {
        // BUG #3 CONTINUES: This is a NEW function name
        // The _initialized flag from V1 is at a DIFFERENT storage slot
        // because V2 has different layout → _initialized reads garbage
        // OR: if layout is same, _initialized is already true from V1
        // BUT: what if the proxy was deployed fresh and V2 is the first impl?
        // Then _initialized = false → can initialize!
        // And if someone calls initialize() from V1 via delegatecall...

        require(!_initialized, "already initialized");
        _initialized = true;

        guardian = _guardian;
        feeNumerator = _feeNum;
        feeDenominator = _feeDenom;
    }

    function deposit(uint256 amount) external {
        require(!paused, "paused");
        require(amount > 0, "zero");

        uint256 balBefore = IERC20Like(token).balanceOf(address(this));
        IERC20Like(token).transferFrom(msg.sender, address(this), amount);
        uint256 received = IERC20Like(token).balanceOf(address(this)) - balBefore;

        // V2 "fixes" fee-on-transfer by measuring actual received
        uint256 shares;
        if (totalShares == 0) {
            shares = received;
        } else {
            shares = received * totalShares / totalDeposits;
        }

        totalDeposits += received;
        totalShares += shares;
        balances[msg.sender] += received;
        shareBalances[msg.sender] += shares;
    }

    function withdraw(uint256 shares) external {
        require(shares > 0 && shares <= shareBalances[msg.sender], "bad");

        uint256 assets = shares * totalDeposits / totalShares;

        // V2 adds a withdrawal fee
        uint256 fee = assets * feeNumerator / feeDenominator;
        uint256 netAssets = assets - fee;

        shareBalances[msg.sender] -= shares;
        totalShares -= shares;
        totalDeposits -= assets;
        balances[msg.sender] -= assets;

        IERC20Like(token).transfer(msg.sender, netAssets);
        // Fee stays in vault (benefits remaining shareholders)
    }

    function emergencyWithdraw() external {
        require(msg.sender == owner || msg.sender == guardian, "not authorized");
        uint256 bal = IERC20Like(token).balanceOf(address(this));
        IERC20Like(token).transfer(msg.sender, bal);
    }

    function pause() external {
        require(msg.sender == owner || msg.sender == guardian, "not authorized");
        paused = true;
    }

    function unpause() external {
        require(msg.sender == owner || msg.sender == guardian, "not authorized");
        paused = false;
    }
}

// ============================================================
// CONTRACT 4: FeeToken (fee-on-transfer ERC20)
// ============================================================
contract FeeToken {
    string public name = "Fee Token";
    string public symbol = "FEE";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    uint256 public feeBps = 100; // 1% fee on every transfer

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "not approved");
        allowance[from][msg.sender] -= amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "insufficient");

        uint256 fee = amount * feeBps / 10000;
        uint256 netAmount = amount - fee;

        balanceOf[from] -= amount;
        balanceOf[to] += netAmount;
        // fee is burned (goes nowhere)
        totalSupply -= fee;
    }
}

interface IERC20Like {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

/**
 * THREE BUGS. FIND ALL THREE. PROVE WITH NUMBERS.
 *
 * BUG #1 HINTS (Storage Collision):
 * - Proxy stores admin at slot 0, implementation at slot 1
 * - VaultV1 stores totalDeposits at slot 0, totalShares at slot 1
 * - When VaultV1 runs via delegatecall, it READS/WRITES proxy's slots!
 * - totalDeposits = admin address (interpreted as uint256)
 * - totalShares = implementation address
 * - What happens when you call deposit()?
 * - What happens when you call upgradeTo()?
 * - Can a user become admin by depositing the right amount?
 *
 * BUG #2 HINTS (Fee-on-Transfer):
 * - VaultV1.deposit() records `amount` but receives `amount - 1%`
 * - totalDeposits is INFLATED by the fee
 * - Over many deposits, totalDeposits >> actual token balance
 * - Last withdrawer gets LESS than they should
 * - Or: totalDeposits > balance → withdraw REVERTS → funds stuck
 * - Calculate: 100 users deposit 1000 tokens each. What's the shortfall?
 *
 * BUG #3 HINTS (Re-initialization):
 * - VaultV1.initialize() sets _initialized = true
 * - Upgrade to VaultV2
 * - VaultV2.initializeV2() checks _initialized
 * - But WHERE is _initialized stored?
 * - V1: slot 8 (after mappings)
 * - V2: slot 8 (after mappings) — SAME if layout matches
 * - BUT: what if V2 is deployed as a FRESH proxy?
 * - Or: what if the storage layout shifted?
 * - Can an attacker call initializeV2() on an already-initialized proxy?
 * - What if they can set guardian = attacker?
 *
 * COMPOSITION:
 * - Bug #1: Become admin via storage collision
 * - Bug #3: Re-initialize to set yourself as guardian
 * - Bug #2: Drain via inflated accounting
 * - OR: Bug #1 → upgradeTo(malicious impl) → full drain
 *
 * SHOW EXACT NUMBERS.
 */
