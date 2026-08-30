"""
Custom Slither Detector #1: ERC4626 Inflation Attack on Empty Vaults
Pattern: First depositor mints 1 share → donates huge amount → share price inflated
         → next depositor gets 0 shares → funds permanently stuck
Source: Halborn-Ploopy, Halborn-Strike, Halborn-Compound, OZ-ERC4626 H-01
Frequency: ~8% of all Halborn reports
"""
from slither.detectors.abstract_detector import AbstractDetector, DetectorClassification
from slither.slithir.operations import HighLevelCall, Binary
from slither.core.declarations import Function


class InflationAttackDetector(AbstractDetector):
    ARGUMENT = "erc4626-inflation-attack"
    HELP = "ERC4626 vault vulnerable to first-depositor inflation attack"
    IMPACT = DetectorClassification.HIGH
    CONFIDENCE = DetectorClassification.MEDIUM

    WIKI = "https://github.com/OpenZeppelin/openzeppelin-contracts/security/advisories/GHSA-w4v4-7h26-8f8m"
    WIKI_TITLE = "ERC4626 Inflation Attack"
    WIKI_DESCRIPTION = (
        "First depositor can manipulate share price by donating assets after "
        "minting minimal shares, causing subsequent depositors to receive 0 shares."
    )
    WIKI_RECOMMENDATION = "Use virtual shares/assets offset (OZ v4.9+ pattern) or minimum deposit."
    WIKI_EXPLOIT_SCENARIO = """
```solidity
// Attacker deposits 1 wei -> mints 1 share
vault.deposit(1, attacker);
// Attacker donates 100 ETH directly
token.transfer(address(vault), 100 ether);
// Victim deposits 1 ETH -> gets 0 shares (rounding)
vault.deposit(1 ether, victim); // shares = 0!
// Victim funds permanently stuck
```"""

    def _detect(self):
        results = []

        for contract in self.compilation_unit.contracts_derived:
            # Check if contract implements ERC4626-like interface
            func_names = {f.name for f in contract.functions}
            has_deposit = "deposit" in func_names
            has_withdraw = "withdraw" in func_names or "redeem" in func_names
            has_convert = any(
                n in func_names
                for n in ["convertToShares", "convertToAssets", "_convertToShares", "_convertToAssets"]
            )

            if not (has_deposit and has_withdraw and has_convert):
                continue

            # Check for virtual shares/assets offset protection
            has_virtual_offset = False
            has_min_deposit = False

            for func in contract.functions:
                if func.is_constructor or func.visibility not in ["public", "external", "internal"]:
                    continue

                for node in func.nodes:
                    # Look for virtual offset pattern: totalSupply() + 1 or + 1e1
                    if node.expression:
                        expr_str = str(node.expression).lower()
                        if ("totalSupply" in str(node.expression) or "totalsupply" in expr_str):
                            if "+ 1" in expr_str or "+1" in expr_str or "1e1" in expr_str or "10 **" in expr_str:
                                has_virtual_offset = True

                        # Look for minimum deposit check
                        if "require" in expr_str or "revert" in expr_str:
                            if "shares" in expr_str and (">" in expr_str or ">=" in expr_str):
                                has_min_deposit = True

            if not has_virtual_offset and not has_min_deposit:
                info = [
                    contract,
                    " implements ERC4626-like interface but lacks protection against ",
                    "first-depositor inflation attack.\n",
                    "\tNo virtual shares/assets offset (OZ v4.9+ pattern) detected.\n",
                    "\tNo minimum deposit amount check detected.\n",
                    "\tAn attacker can: (1) deposit 1 wei → mint 1 share, ",
                    "(2) donate large amount directly, ",
                    "(3) next depositor gets 0 shares → funds stuck.\n",
                    "\tRecommendation: Add virtual offset (totalSupply + 1, totalAssets + 1) ",
                    "or enforce minimum initial deposit.\n",
                ]
                results.append(self.generate_result(info))

        return results
