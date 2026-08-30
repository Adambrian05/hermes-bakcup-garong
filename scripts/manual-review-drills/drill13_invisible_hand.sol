// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * DRILL 13: THE INVISIBLE HAND
 * Difficulty: EXPERT
 * Focus: ERC-4626 inflation attack + permit signature replay + access control
 * 
 * THREE BUGS. THEY COMPOSE INTO ONE CRITICAL EXPLOIT.
 * 
 * Bug #1: ERC-4626 first depositor inflation (classic, still found in 2026)
 * Bug #2: EIP-2612 permit signature replay across vaults
 * Bug #3: Admin function missing access control
 * 
 * REAL-WORLD: This exact combo pattern appeared in multiple C4/Sherlock findings.
 * The inflation attack alone has been found in 50+ protocols.
 */

// ============================================================
// CONTRACT 1: TokenA (ERC20 with EIP-2612 permit)
// ============================================================
contract TokenA {
    string public name = "Token A";
    string public symbol = "TKA";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    // EIP-2612
    mapping(address => uint256) public nonces;
    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH = 
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    
    constructor() {
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(name)),
            keccak256(bytes("1")),
            block.chainid,
            address(this)
        ));
    }
    
    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
        require(allowance[from][msg.sender] >= amount, "not approved");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    // EIP-2612 permit
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, "expired");
        
        bytes32 structHash = keccak256(abi.encode(
            PERMIT_TYPEHASH,
            owner,
            spender,
            value,
            nonces[owner]++,
            deadline
        ));
        
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address recovered = ecrecover(digest, v, r, s);
        require(recovered == owner, "invalid signature");
        
        allowance[owner][spender] = value;
    }
}

// ============================================================
// CONTRACT 2: YieldVault (ERC-4626-like)
// ============================================================
contract YieldVault {
    string public name = "Yield Vault";
    string public symbol = "yvTKA";
    uint8 public decimals = 18;
    
    TokenA public immutable asset;
    
    uint256 public totalShares;
    mapping(address => uint256) public shares;
    mapping(address => mapping(address => uint256)) public shareAllowance;
    
    // EIP-2612 for vault shares (BUG: uses SAME domain separator pattern)
    mapping(address => uint256) public nonces;
    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH = 
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    
    constructor(address _asset) {
        asset = TokenA(_asset);
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(name)),
            keccak256(bytes("1")),
            block.chainid,
            address(this)
        ));
    }
    
    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }
    
    function convertToShares(uint256 assets) public view returns (uint256) {
        if (totalShares == 0) return assets;
        return assets * totalShares / totalAssets();
    }
    
    function convertToAssets(uint256 sharesAmount) public view returns (uint256) {
        if (totalShares == 0) return sharesAmount;
        return sharesAmount * totalAssets() / totalShares;
    }
    
    // Deposit assets, receive shares
    function deposit(uint256 assets, address receiver) external returns (uint256 sharesOut) {
        require(assets > 0, "zero");
        
        sharesOut = convertToShares(assets);
        require(sharesOut > 0, "zero shares"); // ← BUG #1: this check is NOT enough
        
        asset.transferFrom(msg.sender, address(this), assets);
        
        totalShares += sharesOut;
        shares[receiver] += sharesOut;
    }
    
    // Withdraw assets by burning shares
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 sharesIn) {
        sharesIn = convertToShares(assets);
        
        if (msg.sender != owner) {
            require(shareAllowance[owner][msg.sender] >= sharesIn, "not approved");
            shareAllowance[owner][msg.sender] -= sharesIn;
        }
        
        shares[owner] -= sharesIn;
        totalShares -= sharesIn;
        
        asset.transfer(receiver, assets);
    }
    
    // Redeem shares for assets
    function redeem(uint256 sharesAmount, address receiver, address owner) external returns (uint256 assetsOut) {
        if (msg.sender != owner) {
            require(shareAllowance[owner][msg.sender] >= sharesAmount, "not approved");
            shareAllowance[owner][msg.sender] -= sharesAmount;
        }
        
        assetsOut = convertToAssets(sharesAmount);
        
        shares[owner] -= sharesAmount;
        totalShares -= sharesAmount;
        
        asset.transfer(receiver, assetsOut);
    }
    
    // Permit for vault shares
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, "expired");
        
        bytes32 structHash = keccak256(abi.encode(
            PERMIT_TYPEHASH,
            owner,
            spender,
            value,
            nonces[owner]++,
            deadline
        ));
        
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address recovered = ecrecover(digest, v, r, s);
        require(recovered == owner, "invalid signature");
        
        shareAllowance[owner][spender] = value;
    }
    
    function approveShares(address spender, uint256 amount) external returns (bool) {
        shareAllowance[msg.sender][spender] = amount;
        return true;
    }
}

// ============================================================
// CONTRACT 3: VaultFactory (deploys + manages vaults)
// ============================================================
contract VaultFactory {
    address public admin;
    address[] public vaults;
    mapping(address => bool) public isVault;
    
    // BUG #3: no access control on this
    uint256 public performanceFee = 1000; // 10% in bps
    address public feeRecipient;
    
    constructor() {
        admin = msg.sender;
        feeRecipient = msg.sender;
    }
    
    function createVault(address asset) external returns (address) {
        YieldVault vault = new YieldVault(asset);
        vaults.push(address(vault));
        isVault[address(vault)] = true;
        return address(vault);
    }
    
    // BUG #3: ANYONE can call this
    function setPerformanceFee(uint256 newFee) external {
        // Missing: require(msg.sender == admin)
        performanceFee = newFee;
    }
    
    // BUG #3: ANYONE can redirect fees
    function setFeeRecipient(address newRecipient) external {
        // Missing: require(msg.sender == admin)
        feeRecipient = newRecipient;
    }
    
    // Collect fees from a vault (called by anyone, but should be admin-only)
    function collectFees(address vault) external {
        require(isVault[vault], "not a vault");
        YieldVault v = YieldVault(vault);
        
        uint256 totalAssetsVal = v.totalAssets();
        uint256 fee = totalAssetsVal * performanceFee / 10000;
        
        if (fee > 0) {
            // Transfer fee from vault to feeRecipient
            // In real code: vault.transferAssets(feeRecipient, fee)
            // Simplified: direct token transfer
            v.asset().transfer(feeRecipient, fee);
        }
    }
}

// ============================================================
// CONTRACT 4: VaultMigrator (migrates between vault versions)
// ============================================================
contract VaultMigrator {
    VaultFactory public factory;
    
    constructor(address _factory) {
        factory = VaultFactory(_factory);
    }
    
    // Migrate from old vault to new vault
    // Uses permit to pull shares from user
    function migrate(
        address oldVault,
        address newVault,
        uint256 sharesAmount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        YieldVault old = YieldVault(oldVault);
        YieldVault neu = YieldVault(newVault);
        
        // Use permit to get approval
        old.permit(msg.sender, address(this), sharesAmount, deadline, v, r, s);
        
        // Redeem from old vault
        uint256 assets = old.redeem(sharesAmount, address(this), msg.sender);
        
        // Deposit into new vault
        old.asset().approve(address(neu), assets);
        neu.deposit(assets, msg.sender);
    }
    
    // Batch migrate across multiple vaults
    function batchMigrate(
        address[] calldata oldVaults,
        address[] calldata newVaults,
        uint256[] calldata amounts,
        uint256[] calldata deadlines,
        uint8[] calldata vs,
        bytes32[] calldata rs,
        bytes32[] calldata ss
    ) external {
        for (uint256 i = 0; i < oldVaults.length; i++) {
            migrate(oldVaults[i], newVaults[i], amounts[i], deadlines[i], vs[i], rs[i], ss[i]);
        }
    }
}

/**
 * THREE BUGS. FIND ALL THREE. SHOW HOW THEY COMPOSE.
 * 
 * BUG #1 HINTS (ERC-4626 Inflation Attack):
 * - Attacker is the FIRST depositor
 * - deposit 1 wei → get 1 share
 * - directly transfer 10,000 ETH worth of tokens to vault
 * - now totalAssets = 10,000e18, totalShares = 1
 * - victim deposits 10,000e18 → shares = 10,000e18 * 1 / 10,000e18 = 1 share
 * - wait... that's not right. Let me think...
 * - Actually: shares = assets * totalShares / totalAssets
 *   = 10,000e18 * 1 / 10,001e18 = 0 (ROUNDS TO ZERO!)
 * - Victim gets 0 shares but loses 10,000 tokens!
 * - Attacker redeems 1 share = 20,001e18 / 1 = ALL tokens
 * 
 * BUG #2 HINTS (Permit Replay):
 * - User signs a permit for VaultMigrator on Vault A
 * - Can the SAME signature be replayed on Vault B?
 * - Look at DOMAIN_SEPARATOR: it includes address(this)
 * - So each vault has a DIFFERENT domain separator
 * - BUT: what if VaultFactory deploys vaults with CREATE2?
 * - Or: what if the permit is for the TOKEN, not the vault?
 * - Look at TokenA.permit() — it's the ASSET token's permit
 * - The vault calls asset.transferFrom() which needs asset approval
 * - If user signs asset.permit() for the vault...
 * - And there are MULTIPLE vaults for the SAME asset...
 * - The TOKEN's DOMAIN_SEPARATOR is the SAME for all vaults!
 * - So a permit signed for Vault A's deposit can be replayed for Vault B!
 * 
 * BUG #3 HINTS (Access Control):
 * - VaultFactory.setPerformanceFee() — no access control
 * - VaultFactory.setFeeRecipient() — no access control
 * - Attacker sets fee to 100% and recipient to themselves
 * - Then calls collectFees() on every vault
 * 
 * COMPOSITION:
 * - Bug #1: Inflate vault, steal victim's deposit
 * - Bug #2: Replay permit to drain from multiple vaults
 * - Bug #3: Set 100% fee, drain all vaults via collectFees
 * 
 * SHOW THE FULL ATTACK WITH EXACT NUMBERS.
 */
