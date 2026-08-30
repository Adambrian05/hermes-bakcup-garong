"""
Custom Slither Detector #5: Cross-Chain Signature Replay
Pattern: EIP-712 signature without chainId in domain separator → replay across chains
         OR: signature nonce not checked → replay on same chain
Source: Halborn-Bridge, Halborn-xERC20, SP-EigenLayer, ToB-FraxGov
Frequency: ~5% of bridge-related findings
"""
from slither.detectors.abstract_detector import AbstractDetector, DetectorClassification
from slither.slithir.operations import HighLevelCall
from slither.core.declarations import Function


class CrossChainReplayDetector(AbstractDetector):
    ARGUMENT = "cross-chain-replay"
    HELP = "Signature scheme may be vulnerable to cross-chain or same-chain replay"
    IMPACT = DetectorClassification.HIGH
    CONFIDENCE = DetectorClassification.MEDIUM

    WIKI = "https://eips.ethereum.org/EIPS/eip-712"
    WIKI_TITLE = "Cross-Chain Signature Replay"
    WIKI_DESCRIPTION = (
        "If EIP-712 domain separator doesn't include chainId, or if nonces aren't "
        "checked, signatures can be replayed across chains or on the same chain."
    )
    WIKI_RECOMMENDATION = "Include chainId in domain separator. Use and increment nonces."
    WIKI_EXPLOIT_SCENARIO = """
```solidity
// Signature valid on Ethereum mainnet
// Attacker replays same signature on Arbitrum
// No chainId in domain -> signature accepted
bridge.relay(token, amount, recipient, v, r, s);
```"""

    def _detect(self):
        results = []

        for contract in self.compilation_unit.contracts_derived:
            # Check for signature verification functions
            has_ecrecover = False
            has_domain_separator = False
            has_chain_id = False
            has_nonce_check = False
            sig_func = None

            for func in contract.functions:
                for node in func.nodes:
                    if node.expression is None:
                        continue
                    expr_str = str(node.expression)

                    if "ecrecover" in expr_str or "recover" in expr_str:
                        has_ecrecover = True
                        sig_func = func

                    if "DOMAIN_SEPARATOR" in expr_str or "domainSeparator" in expr_str:
                        has_domain_separator = True

                    if "chainid" in expr_str.lower() or "block.chainid" in expr_str:
                        has_chain_id = True

                    if "nonce" in expr_str.lower():
                        has_nonce_check = True

            if not has_ecrecover:
                continue

            issues = []
            if has_domain_separator and not has_chain_id:
                issues.append(
                    "Domain separator exists but chainId not detected — "
                    "signatures may be replayable across chains.\n"
                )
            if not has_nonce_check:
                issues.append(
                    "No nonce mechanism detected — "
                    "signatures may be replayable on the same chain.\n"
                )
            if not has_domain_separator:
                issues.append(
                    "No EIP-712 domain separator detected — "
                    "signatures lack structured replay protection.\n"
                )

            if issues and sig_func:
                info = [sig_func, " uses signature verification with potential replay risk:\n"]
                for issue in issues:
                    info.append(f"\t{issue}")
                info.append(
                    "\tFix: Include block.chainid in DOMAIN_SEPARATOR. "
                    "Use mapping(address => uint256) nonces, increment after use.\n"
                )
                results.append(self.generate_result(info))

        return results
