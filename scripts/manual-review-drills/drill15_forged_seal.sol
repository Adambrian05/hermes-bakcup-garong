// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * DRILL 15: THE FORGED SEAL
 * Difficulty: EXPERT
 * Focus: EIP-712 signature replay, signature malleability, timelock bypass
 *
 * THREE BUGS. ALL REAL PATTERNS FROM PRODUCTION EXPLOITS.
 *
 * Bug #1: Incomplete EIP-712 domain → cross-chain + cross-contract replay
 * Bug #2: Signature malleability → one signature = TWO valid signatures
 * Bug #3: Timelock execute() with no access control + no grace period
 *
 * REAL-WORLD:
 * - Cross-chain replay: multiple bridges, Nomad ($190M used wrong root)
 * - Malleability: early OpenSea/Wyvern issues, many C4 findings
 * - Timelock: Compound "Golden Gate" incident, various governance attacks
 */

// ============================================================
// CONTRACT 1: SignatureVault (withdraw via owner signature)
// ============================================================
contract SignatureVault {
    string public constant NAME = "TreasuryVault";
    string public constant VERSION = "1";

    address public owner;
    IERC20Like public token;
    uint256 public totalDeposited;

    mapping(address => uint256) public nonces;
    mapping(bytes32 => bool) public usedSignatures; // ← BUG #2: keyed on sig hash

    bytes32 public constant WITHDRAW_TYPEHASH =
        keccak256("Withdraw(address to,uint256 amount,uint256 nonce,uint256 deadline)");

    constructor(address _token) {
        owner = msg.sender;
        token = IERC20Like(_token);
    }

    function deposit(uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);
        totalDeposited += amount;
    }

    // BUG #1: DOMAIN_SEPARATOR missing chainId AND verifyingContract
    function domainSeparator() public view returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version)"),
            keccak256(bytes(NAME)),
            keccak256(bytes(VERSION))
            // NO chainId → replay across forks
            // NO verifyingContract → replay across contracts with same name/version
        ));
    }

    // Withdraw using owner's signature
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

        // BUG #2: raw ecrecover, no malleability check (s > secp256k1/2)
        address signer = ecrecover(digest, v, r, s);
        require(signer == owner, "bad signature");
        require(signer != address(0), "bad signature");

        // BUG #2: replay protection keyed on keccak(r,s,v)
        // The malleable twin (s' = N - s, v' = 27+28-v) has a DIFFERENT hash
        bytes32 sigHash = keccak256(abi.encodePacked(r, s, v));
        require(!usedSignatures[sigHash], "signature used");
        usedSignatures[sigHash] = true;

        nonces[owner]++;

        totalDeposited -= amount;
        token.transfer(to, amount);
    }
}

// ============================================================
// CONTRACT 2: RelayExecutor (meta-transaction relay)
// ============================================================
contract RelayExecutor {
    // BUG #1 CONTINUES: SAME name/version, same broken domain
    // → a signature valid on SignatureVault is ALSO valid here
    string public constant NAME = "TreasuryVault";
    string public constant VERSION = "1";

    address public owner;
    mapping(address => uint256) public nonces;

    bytes32 public constant EXECUTE_TYPEHASH =
        keccak256("Execute(address target,bytes data,uint256 nonce,uint256 deadline)");

    // This contract holds funds (treasury overflow)
    uint256 public treasuryBalance;

    constructor() {
        owner = msg.sender;
    }

    receive() external payable {
        treasuryBalance += msg.value;
    }

    function domainSeparator() public view returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version)"),
            keccak256(bytes(NAME)),
            keccak256(bytes(VERSION))
        ));
    }

    // Execute arbitrary call with owner's signature
    function executeWithSig(
        address target,
        bytes calldata data,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable returns (bytes memory) {
        require(block.timestamp <= deadline, "expired");

        bytes32 structHash = keccak256(abi.encode(
            EXECUTE_TYPEHASH,
            target,
            keccak256(data),
            nonces[owner],
            deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator(), structHash));

        address signer = ecrecover(digest, v, r, s); // ← no malleability check
        require(signer == owner, "bad signature");

        nonces[owner]++;

        // Relay holds ETH — can send value with the call
        uint256 value = msg.value;
        if (value > 0) treasuryBalance -= value;

        (bool success, bytes memory result) = target.call{value: value}(data);
        require(success, "execution failed");
        return result;
    }

    // Owner-only rescue (or so it seems)
    function rescueETH(address to, uint256 amount) external {
        require(msg.sender == owner, "not owner");
        treasuryBalance -= amount;
        (bool ok,) = to.call{value: amount}("");
        require(ok);
    }
}

// ============================================================
// CONTRACT 3: Timelock (schedule → wait → execute)
// ============================================================
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

    // BUG #3a: NO ACCESS CONTROL — anyone can execute after eta
    // BUG #3b: NO GRACE PERIOD — operation valid FOREVER after eta
    // BUG #3c: Uses DELEGATECALL instead of CALL
    function execute(bytes32 opHash) external payable returns (bytes memory) {
        Operation storage op = operations[opHash];
        require(op.eta != 0, "not scheduled");
        require(block.timestamp >= op.eta, "too early");
        require(!op.executed, "already executed");
        // NO: require(block.timestamp <= op.eta + GRACE_PERIOD)
        // NO: require(msg.sender == admin)

        op.executed = true;

        // BUG #3c: delegatecall runs target code in TIMELOCK's storage context
        (bool success, bytes memory result) = op.target.delegatecall(op.data);
        require(success, "execution failed");
        return result;
    }

    function cancel(bytes32 opHash) external {
        require(msg.sender == admin, "not admin");
        Operation storage op = operations[opHash];
        require(op.eta != 0, "not scheduled");
        require(!op.executed, "already executed");
        delete operations[opHash];
    }
}

interface IERC20Like {
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

/**
 * THREE BUGS. PROVE ALL THREE WITH EXACT NUMBERS.
 *
 * BUG #1 HINTS (Domain Replay):
 * - domainSeparator() has ONLY name + version
 * - No chainId: sign on Ethereum → replay on Arbitrum/Base/fork
 * - No verifyingContract: SignatureVault and RelayExecutor share
 *   the SAME domain separator!
 * - BUT: different TYPEHASH (Withdraw vs Execute) — can a Withdraw
 *   signature be replayed as an Execute? Think about struct hashing.
 * - What CAN be replayed?
 *
 * BUG #2 HINTS (Malleability):
 * - ECDSA: if (r, s, v) is valid, then (r, N-s, v^1) is ALSO valid
 *   where N = secp256k1 curve order
 * - N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
 * - The contract checks usedSignatures[keccak(r,s,v)]
 * - The twin has DIFFERENT r,s,v → different sigHash → NOT blocked
 * - One owner signature = TWO withdrawals
 * - nonces[owner]++ happens... does that block the twin? CHECK CAREFULLY.
 *   (Hint: the nonce is embedded in the digest BEFORE verification.
 *   The twin was signed with the SAME nonce. Does the second call
 *   re-check the nonce against current nonces[owner]?)
 *
 * BUG #3 HINTS (Timelock):
 * - execute() has no msg.sender check → anyone executes after eta
 * - No grace period → a scheduled operation from 2 years ago
 *   is STILL executable today
 * - delegatecall: target code runs with TIMELOCK's storage
 * - If admin schedules: target=SomeContract, data=initialize(attacker)
 *   ...what happens to Timelock's OWN storage (admin, operations)?
 * - Can a scheduled "harmless" operation be used to OVERWRITE
 *   Timelock.admin via storage collision?
 *
 * COMPOSITION (the full heist):
 * - Owner signs ONE legitimate payment: withdrawWithSig(contractor, 100, ...)
 * - Attacker observes the signature in the mempool
 * - Show how the attacker extracts 4x value from ONE signature:
 *   1. Original withdrawal
 *   2. Malleable twin withdrawal (same vault)
 *   3. Cross-chain replay (fork)
 *   4. Cross-contract replay (if applicable)
 * - Then use the timelock to make the damage permanent
 *
 * SHOW EXACT NUMBERS FOR EACH STEP.
 */
