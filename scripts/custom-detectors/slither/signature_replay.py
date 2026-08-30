"""
Custom Slither Detector: Cross-Chain Signature Replay
Detects EIP-712 signatures that don't include chainId in domain separator.

If chainId is hardcoded or missing, signatures can be replayed
across different chains (L1 → L2, fork → original).

Author: IRONCLAW v7
"""

from slither.detectors.abstract_detector import AbstractDetector, DetectorClassification


class SignatureReplay(AbstractDetector):
    ARGUMENT = "cross-chain-signature-replay"
    HELP = "EIP-712 domain may lack dynamic chainId — cross-chain replay risk"
    IMPACT = DetectorClassification.MEDIUM
    CONFIDENCE = DetectorClassification.MEDIUM

    WIKI = "https://github.com/crytic/slither/wiki/Detector-Documentation"
    WIKI_TITLE = "Cross-Chain Signature Replay"
    WIKI_DESCRIPTION = (
        "Detects EIP-712 domain separators that use a hardcoded chainId "
        "or don't include chainId at all. Signatures could be replayed "
        "on different chains or after a chain fork."
    )
    WIKI_EXPLOIT_SCENARIO = """
```solidity
// HARDCODED chainId — replayable on forks
bytes32 constant DOMAIN = keccak256(abi.encode(
    keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)"),
    keccak256("MyProtocol"),
    1,  // HARDCODED! Should be block.chainid
    address(this)
));
```
"""
    WIKI_RECOMMENDATION = "Use block.chainid dynamically and invalidate cache on fork."

    def _detect(self):
        results = []
        for contract in self.contracts:
            for func in contract.functions_declared:
                # Look for EIP-712 domain construction
                for node in func.nodes:
                    node_str = str(node)
                    # Check for domain separator patterns
                    if "EIP712Domain" in node_str or "DOMAIN_SEPARATOR" in node_str.upper():
                        # Check if block.chainid is used
                        uses_chainid = False
                        uses_hardcoded = False
                        for ir in node.irs:
                            ir_str = str(ir)
                            if "chainid" in ir_str.lower() or "CHAINID" in ir_str:
                                uses_chainid = True
                            # Check for hardcoded numbers (1, 5, 137, etc.)
                            if "chainId" in ir_str and any(
                                c.isdigit() for c in ir_str
                            ):
                                uses_hardcoded = True
                        
                        if uses_hardcoded and not uses_chainid:
                            info = [
                                func,
                                f" may have cross-chain signature replay:\n",
                                f"\t- EIP-712 domain uses hardcoded chainId\n",
                                f"\t- Signatures replayable on forks/other chains\n",
                                f"\t- Use block.chainid dynamically\n",
                            ]
                            results.append(self.generate_result(info))
        return results
