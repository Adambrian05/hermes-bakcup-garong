"""
Custom Slither Detector: Donation Attack via balanceOf Accounting
Detects functions that use balanceOf(address(this)) to update internal accounting.
"""
from slither.detectors.abstract_detector import AbstractDetector, DetectorClassification
from slither.slithir.operations import HighLevelCall, TypeConversion
from slither.core.variables.state_variable import StateVariable


class DonationAttack(AbstractDetector):
    ARGUMENT = "donation-attack"
    HELP = "balanceOf used for internal accounting (donation attack)"
    IMPACT = DetectorClassification.MEDIUM
    CONFIDENCE = DetectorClassification.MEDIUM

    WIKI = "https://example.com/donation-attack"
    WIKI_TITLE = "Donation Attack via balanceOf Accounting"
    WIKI_DESCRIPTION = "Using balanceOf(this) for internal accounting allows donation attacks"
    WIKI_EXPLOIT_SCENARIO = "Attacker donates tokens, then calls sync/update to inflate accounting"
    WIKI_RECOMMENDATION = "Use internal accounting variables, not balanceOf, for state tracking"

    def _detect(self):
        results = []
        for contract in self.contracts:
            for function in contract.functions_declared:
                if function.is_constructor or function.visibility not in ("public", "external"):
                    continue

                # Track variables that hold address(this)
                this_vars = set()
                uses_balanceof_self = False
                updates_state = False

                for node in function.nodes:
                    for ir in node.irs:
                        # Track: TMP = CONVERT this to address
                        if isinstance(ir, TypeConversion):
                            if hasattr(ir, 'variable') and ir.variable:
                                var_str = str(ir.variable).lower()
                                if 'this' in var_str:
                                    this_vars.add(str(ir.lvalue))

                        # Check for balanceOf call with address(this) arg
                        if isinstance(ir, HighLevelCall):
                            fn = str(ir.function_name) if hasattr(ir, 'function_name') else ""
                            if 'balanceof' in fn.lower():
                                if hasattr(ir, 'arguments') and ir.arguments:
                                    for arg in ir.arguments:
                                        arg_str = str(arg)
                                        # Direct: address(this)
                                        if 'this' in arg_str.lower():
                                            uses_balanceof_self = True
                                        # Indirect: TMP variable from CONVERT this
                                        if arg_str in this_vars:
                                            uses_balanceof_self = True

                        # Check for state variable writes
                        if hasattr(ir, 'lvalue') and ir.lvalue:
                            if isinstance(ir.lvalue, StateVariable):
                                updates_state = True

                if uses_balanceof_self and updates_state:
                    info = [
                        function,
                        " uses balanceOf(address(this)) to update state.\n",
                        "\tAn attacker can donate tokens to inflate accounting.\n",
                        "\tUse internal tracking variables instead of balanceOf.\n"
                    ]
                    results.append(self.generate_result(info))

        return results
