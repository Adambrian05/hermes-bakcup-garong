// SPDX-License-Identifier: MIT
// =============================================================================
// DRILL 20 — Cross-Chain Replay — Missing Chain ID in Domain Separator
// =============================================================================
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

library ECDSA {
    function recover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        require(uint256(s) <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0, "ECDSA: invalid signature s value");
        require(v == 27 || v == 28, "ECDSA: invalid signature v value");
        address signer = ecrecover(hash, v, r, s);
        require(signer != address(0), "ECDSA: invalid signature");
        return signer;
    }
}

contract OmniBridge {
    using ECDSA for bytes32;

    bytes32 private constant EIP712_DOMAIN =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 private constant WITHDRAW_TYPE =
        keccak256("Withdraw(address user,uint256 amount,uint256 nonce,uint256 deadline)");

    // BUG 20-A: This immutable is never assigned. It stays bytes32(0).
    // In Solidity 0.8.x, an unassigned immutable defaults to 0.
    bytes32 public immutable DOMAIN_SEPARATOR;

    IERC20 public immutable token;
    address public immutable relayer;

    mapping(address => uint256) public nonces;
    mapping(bytes32 => bool) public usedDigests;

    event Withdrawal(address indexed user, uint256 amount, uint256 nonce);

    constructor(address _token) {
        token = IERC20(_token);
        relayer = msg.sender;

        // BUG 20-A: Computes to LOCAL variable. Should assign DOMAIN_SEPARATOR.
        bytes32 _ds = keccak256(
            abi.encode(
                EIP712_DOMAIN,
                keccak256(bytes("OmniBridge")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
        // MISSING: DOMAIN_SEPARATOR = _ds;
        // For this drill, we intentionally omit this assignment to
        // simulate the bug.
    }

    function withdraw(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(block.timestamp <= deadline, "expired");

        bytes32 structHash = keccak256(
            abi.encode(WITHDRAW_TYPE, msg.sender, amount, nonces[msg.sender], deadline)
        );

        // Uses DOMAIN_SEPARATOR which is bytes32(0)
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );

        address signer = digest.recover(v, r, s);
        require(signer == relayer, "bad signer");

        require(!usedDigests[digest], "replay");
        usedDigests[digest] = true;

        // BUG 20-B: Nonce is NEVER incremented
        // nonces[msg.sender]++  <-- missing

        require(token.transfer(msg.sender, amount), "transfer fail");

        emit Withdrawal(msg.sender, amount, nonces[msg.sender]);
    }

    // BUG 20-C: drain has no access control — anyone can drain
    function drain(address rescue) external {
        require(token.transfer(rescue, token.balanceOf(address(this))), "transfer fail");
    }

    // BUG 20-D: isValidSignature always returns success for any non-empty sig
    function isValidSignature(bytes32, bytes calldata _signature)
        external
        pure
        returns (bytes4)
    {
        if (_signature.length == 0) return 0x00000000;
        return 0x1626ba7e;
    }
}

contract MockERC20 is IERC20 {
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insuf");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }
}

/*
=== HINTS ===
Hint 1: Check the constructor. DOMAIN_SEPARATOR is declared immutable
        but is it ever assigned? What value does an unassigned immutable hold?

Hint 2: drain(address) — who can call it? Look for any access control.

Hint 3: Inside withdraw(), after success — does nonces[user] change?
        What happens on the user's next withdrawal attempt?

Hint 4: isValidSignature returns 0x1626ba7e for any non-empty signature.
        What does this mean for external validators?

=== ANSWER KEY ===

BUG 20-A (CRITICAL): DOMAIN_SEPARATOR is bytes32(0)
  Constructor computes _ds (local) but never assigns DOMAIN_SEPARATOR.
  Since DOMAIN_SEPARATOR is immutable and unassigned, it stays 0x0.
  Every digest = keccak256(0x1901 || 0x0 || structHash).
  No chainId in digest → same signature works on every chain.
  Replay across all chains = trivial.

BUG 20-B (HIGH): Nonce never incremented
  After successful withdraw, nonces[msg.sender] stays the same.
  Next signature includes "nonce+1" per EIP-712 spec, but digest
  uses stale nonce → mismatch → user's next withdrawal reverts.
  Permanent DoS after first withdrawal.

BUG 20-C (CRITICAL): drain() has no access control
  Anyone can call drain(address) and steal all tokens in the contract.
  Full loss of all locked tokens.

BUG 20-D (MEDIUM): isValidSignature always returns valid
  Returns 0x1626ba7e (magic value) for any non-empty signature.
  External integrators that trust this contract's validation will
  accept any signer as valid. Enables social engineering / phishing
  vectors where attacker appears authorized.
*/
