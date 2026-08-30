"""
Custom Slither Detector: Uncollateralized Borrow
Detects borrow functions that transfer tokens without checking collateral.
"""
from slither.detectors.abstract_detector import AbstractDetector, DetectorClassification
from slither.slithir.operations import HighLevelCall


class UncollateralizedBorrow(AbstractDetector):
    ARGUMENT = "uncollateralized-borrow"
    HELP = "Borrow function without collateral check"
    IMPACT = DetectorClassification.HIGH
    CONFIDENCE = DetectorClassification.MEDIUM

    WIKI = "https://example.com/uncollateralized-borrow"
    WIKI_TITLE = "Uncollateralized Borrow"
    WIKI_DESCRIPTION = "Borrow function without collateral check"
    WIKI_EXPLOIT_SCENARIO = "Attacker calls borrow() without collateral and drains liquidity"
    WIKI_RECOMMENDATION = "Add collateral requirement before allowing borrows"

    # Words that indicate collateral backing (not just liquidity)
    COLLATERAL_KEYWORDS = ("collateral", "stake", "locked", "backing", "margin")
    # Words that are NOT collateral (just liquidity tracking)
    NON_COLLATERAL = ("totaldeposit", "totalborrow", "totalsupply", "liquidity", "balance")

    def _detect(self):
        results = []
        for contract in self.contracts:
            for function in contract.functions_declared:
                if function.is_constructor or function.visibility not in ("public", "external"):
                    continue

                func_name = function.name.lower()
                if not any(kw in func_name for kw in ("borrow", "lend", "loan", "credit")):
                    continue

                writes_debt = False
                reads_collateral = False
                has_transfer = False

                for node in function.nodes:
                    for ir in node.irs:
                        # Check lvalue for debt writes
                        if hasattr(ir, 'lvalue') and ir.lvalue:
                            lv = str(ir.lvalue).lower()
                            if 'borrow' in lv or 'debt' in lv:
                                writes_debt = True

                        # Check reads for collateral (exclude liquidity vars)
                        if hasattr(ir, 'read'):
                            for r in ir.read:
                                rn = str(r).lower()
                                is_collateral = any(kw in rn for kw in self.COLLATERAL_KEYWORDS)
                                is_non_collateral = any(kw in rn for kw in self.NON_COLLATERAL)
                                if is_collateral and not is_non_collateral:
                                    reads_collateral = True

                        # Check for external token transfers
                        if isinstance(ir, HighLevelCall):
                            fn = str(ir.function_name) if hasattr(ir, 'function_name') else ""
                            if 'transfer' in fn.lower():
                                has_transfer = True

                if writes_debt and has_transfer and not reads_collateral:
                    info = [
                        function,
                        " borrows tokens without checking collateral.\n",
                        "\tDebt is recorded and tokens transferred, but no collateral ",
                        "mapping is read. Anyone can borrow without backing.\n"
                    ]
                    results.append(self.generate_result(info))

        return results
