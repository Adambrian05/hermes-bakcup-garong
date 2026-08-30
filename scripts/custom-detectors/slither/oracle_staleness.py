"""
Custom Slither Detector #2: Oracle Staleness / Missing Staleness Check
Pattern: Chainlink latestRoundData() called without checking updatedAt timestamp
         → stale/manipulated price used for critical operations
Source: Halborn-OmniPool, Halborn-Commodity, Halborn-Lybra, ToB-Fraxlend, SP-Interest
Frequency: ~8% of Halborn, ~15% of Sigma Prime DeFi findings
"""
from slither.detectors.abstract_detector import AbstractDetector, DetectorClassification
from slither.slithir.operations import HighLevelCall
from slither.core.declarations import Function


class OracleStalenessDetector(AbstractDetector):
    ARGUMENT = "oracle-staleness-check"
    HELP = "Chainlink oracle used without staleness validation"
    IMPACT = DetectorClassification.HIGH
    CONFIDENCE = DetectorClassification.MEDIUM

    WIKI = "https://docs.chain.link/docs/historical-price-data/"
    WIKI_TITLE = "Oracle Staleness Check Missing"
    WIKI_DESCRIPTION = (
        "Chainlink latestRoundData() returns (roundId, answer, startedAt, updatedAt, answeredInRound). "
        "If updatedAt is not checked against block.timestamp, stale prices can be used."
    )
    WIKI_RECOMMENDATION = "Always check: require(updatedAt > block.timestamp - MAX_AGE)"
    WIKI_EXPLOIT_SCENARIO = """
```solidity
// Oracle stopped updating 24h ago
(, int256 price,,,) = feed.latestRoundData();
// price is stale but used for liquidation
liquidate(user, price); // wrong price -> unfair liquidation
```"""

    def _detect(self):
        results = []

        for contract in self.compilation_unit.contracts_derived:
            for func in contract.functions:
                if func.visibility not in ["public", "external", "internal", "private"]:
                    continue

                calls_latest_round = False
                checks_updated_at = False
                checks_block_timestamp = False
                oracle_node = None

                for node in func.nodes:
                    if node.expression is None:
                        continue
                    expr_str = str(node.expression)

                    # Detect latestRoundData() or latestAnswer() call
                    if "latestRoundData" in expr_str or "latestAnswer" in expr_str:
                        calls_latest_round = True
                        oracle_node = node

                    # Detect staleness check patterns
                    if "updatedAt" in expr_str or "updatedat" in expr_str.lower():
                        checks_updated_at = True
                    if "block.timestamp" in expr_str:
                        checks_block_timestamp = True

                    # Also check for roundId validation
                    if "answeredInRound" in expr_str and ">" in expr_str:
                        checks_updated_at = True  # roundId check is alternative

                if calls_latest_round and not (checks_updated_at and checks_block_timestamp):
                    missing = []
                    if not checks_updated_at:
                        missing.append("updatedAt")
                    if not checks_block_timestamp:
                        missing.append("block.timestamp comparison")

                    info = [
                        func,
                        " calls Chainlink oracle without checking ",
                        f"{' and '.join(missing)}.\n",
                        "\tStale or manipulated prices could be used for ",
                        "critical operations (liquidation, pricing, borrowing).\n",
                        "\tRecommendation: require(updatedAt >= block.timestamp - MAX_ORACLE_AGE)\n",
                    ]
                    results.append(self.generate_result(info))

        return results
