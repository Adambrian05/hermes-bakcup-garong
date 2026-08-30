"""
Custom Slither Detector #3: Division Before Multiplication (Precision Loss)
Pattern: (a / b) * c instead of (a * c) / b → truncation error accumulates
         → last user can't withdraw, interest miscalculated, fees wrong
Source: Halborn-Biconomy HAL-01, ToB-Fraxlend, SP-Term, C4-Revert-Lend
Frequency: ~10% of Halborn, ~12% of C4 findings
"""
from slither.detectors.abstract_detector import AbstractDetector, DetectorClassification
from slither.slithir.operations import Binary
from slither.core.declarations import Function
from slither.core.variables.state_variable import StateVariable


class DivBeforeMulDetector(AbstractDetector):
    ARGUMENT = "div-before-mul"
    HELP = "Division before multiplication causes precision loss"
    IMPACT = DetectorClassification.MEDIUM
    CONFIDENCE = DetectorClassification.MEDIUM

    WIKI = "https://github.com/crytic/slither/wiki/Detector-Documentation"
    WIKI_TITLE = "Division Before Multiplication"
    WIKI_DESCRIPTION = (
        "Performing division before multiplication causes integer truncation. "
        "In DeFi, this leads to: interest miscalculation, fee loss, last-user withdrawal failure."
    )
    WIKI_RECOMMENDATION = "Reorder: (a * c) / b instead of (a / b) * c. Use mulDiv() for overflow safety."
    WIKI_EXPLOIT_SCENARIO = """
```solidity
uint256 dailyRate = annualRate / 365; // truncation
uint256 interest = principal * dailyRate * days;
// interest is systematically understated
```"""

    def _detect(self):
        results = []

        for contract in self.compilation_unit.contracts_derived:
            for func in contract.functions:
                if func.visibility not in ["public", "external", "internal", "private"]:
                    continue
                if func.is_constructor:
                    continue

                for node in func.nodes:
                    for ir in node.irs:
                        if not isinstance(ir, Binary):
                            continue
                        if ir.type_str != "*":
                            continue

                        # Check if left operand is result of division
                        left = ir.variable_left
                        right = ir.variable_right

                        for operand in [left, right]:
                            if operand is None:
                                continue
                            # Trace back: is this variable assigned from a division?
                            for prev_ir in node.irs:
                                if not isinstance(prev_ir, Binary):
                                    continue
                                if prev_ir.type_str != "/":
                                    continue
                                if prev_ir.lvalue == operand:
                                    # Found: (x / y) * z pattern
                                    # Skip if divisor is constant 1e18/1e27 (fixed-point)
                                    divisor_str = str(prev_ir.variable_right)
                                    if divisor_str in ["1000000000000000000", "1000000000000000000000000000"]:
                                        continue  # Fixed-point math, likely intentional

                                    info = [
                                        func,
                                        " performs division before multiplication at: ",
                                        node,
                                        "\n\tPattern: (a / b) * c → truncation error.\n",
                                        "\tIn DeFi: interest/fee/reward miscalculation, ",
                                        "last-user withdrawal failure.\n",
                                        "\tFix: (a * c) / b or use mulDiv(a, c, b).\n",
                                    ]
                                    results.append(self.generate_result(info))
                                    break

        return results
