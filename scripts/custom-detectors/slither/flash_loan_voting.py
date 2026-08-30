"""
Custom Slither Detector #4: Flash Loan Voting Manipulation
Pattern: Voting power read from current balance (not snapshot) → flash loan → vote → repay
         → governance captured in single transaction
Source: Halborn-EsLode, Halborn-DAO, SP-Symbiotic, C4-Wildcat
Frequency: ~5% of Halborn, ~8% of Sigma Prime governance findings
"""
from slither.detectors.abstract_detector import AbstractDetector, DetectorClassification
from slither.slithir.operations import HighLevelCall
from slither.core.declarations import Function


class FlashLoanVotingDetector(AbstractDetector):
    ARGUMENT = "flash-loan-voting"
    HELP = "Voting power based on current balance, vulnerable to flash loan manipulation"
    IMPACT = DetectorClassification.HIGH
    CONFIDENCE = DetectorClassification.MEDIUM

    WIKI = "https://docs.openzeppelin.com/contracts/4.x/governance"
    WIKI_TITLE = "Flash Loan Voting Manipulation"
    WIKI_DESCRIPTION = (
        "If voting power = token.balanceOf(voter) at vote time, an attacker can "
        "flash loan tokens, vote, and repay in one transaction."
    )
    WIKI_RECOMMENDATION = "Use snapshot-based voting (ERC20Votes) or time-delayed voting power."
    WIKI_EXPLOIT_SCENARIO = """
```solidity
// Attacker flash loans 1M tokens
aave.flashLoan(token, 1_000_000e18);
// Votes on malicious proposal
governor.castVote(proposalId, true);
// Repays flash loan
// Governance captured in 1 transaction
```"""

    def _detect(self):
        results = []

        for contract in self.compilation_unit.contracts_derived:
            func_names = {f.name for f in contract.functions}

            # Check if this is a governance/voting contract
            is_governance = any(
                kw in " ".join(func_names).lower()
                for kw in ["vote", "proposal", "governor", "castvote", "propose"]
            )
            if not is_governance:
                continue

            for func in contract.functions:
                fname_lower = func.name.lower()
                if not any(kw in fname_lower for kw in ["vote", "cast", "propose"]):
                    continue

                uses_balance_of = False
                uses_snapshot = False
                uses_getvotes = False
                balance_node = None

                for node in func.nodes:
                    if node.expression is None:
                        continue
                    expr_str = str(node.expression)

                    # Direct balanceOf call = vulnerable
                    if "balanceOf" in expr_str and "getVotes" not in expr_str:
                        uses_balance_of = True
                        balance_node = node

                    # Snapshot patterns = safe
                    if any(kw in expr_str for kw in [
                        "getVotes", "getPastVotes", "getPriorVotes",
                        "snapshots", "checkpoint", "ERC20Votes",
                        "block.number - 1", "block.number-1",
                    ]):
                        uses_snapshot = True

                if uses_balance_of and not uses_snapshot:
                    info = [
                        func,
                        " reads voting power from balanceOf() without snapshot.\n",
                        "\tAt: ",
                        balance_node,
                        "\n\tAttack: flash loan tokens → vote → repay in 1 tx.\n",
                        "\tFix: Use ERC20Votes.getPastVotes(account, block.number - 1) ",
                        "or equivalent snapshot mechanism.\n",
                    ]
                    results.append(self.generate_result(info))

        return results
