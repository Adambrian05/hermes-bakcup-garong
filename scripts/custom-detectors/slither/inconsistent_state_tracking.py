"""
Custom Slither Detector: Inconsistent State Tracking v4 (FIXED)
Detects: var = fieldA (unconditional) then var += fieldB (conditional only)

Bug found in CashbackRewards._validatePaymentReward:
  previouslyRewardedAmount = distributed          (always)
  if (op == ALLOCATE):
      previouslyRewardedAmount += allocated       (only ALLOCATE!)
  require(prev + amount <= cap)                   (SEND ignores allocated)

Author: IRONCLAW v7
"""

from slither.detectors.abstract_detector import AbstractDetector, DetectorClassification
from slither.slithir.operations import Assignment, Binary


class InconsistentStateTracking(AbstractDetector):
    ARGUMENT = "inconsistent-state-tracking"
    HELP = "Variable accumulated from different sources conditionally — cap bypass risk"
    IMPACT = DetectorClassification.MEDIUM
    CONFIDENCE = DetectorClassification.MEDIUM

    WIKI = "https://github.com/crytic/slither/wiki/Detector-Documentation"
    WIKI_TITLE = "Inconsistent State Tracking"
    WIKI_DESCRIPTION = (
        "Detects when a local variable is assigned from one source unconditionally, "
        "then accumulated (+=) from a DIFFERENT source only inside a conditional branch. "
        "Other code paths skip the second source, potentially bypassing a cap/limit."
    )
    WIKI_EXPLOIT_SCENARIO = """
```solidity
uint120 prev = rewards[hash].distributed;       // always
if (operation == ALLOCATE) {
    prev += rewards[hash].allocated;             // only ALLOCATE!
}
require(prev + amount <= maxAllowed);            // SEND ignores allocated!
```
"""
    WIKI_RECOMMENDATION = "Count ALL relevant fields unconditionally before the cap check."

    def _detect(self):
        results = []
        for contract in self.contracts:
            for function in contract.functions_declared:
                findings = self._analyze_function(function)
                for f in findings:
                    info = [
                        function,
                        f" has inconsistent accumulation:\n",
                        f"\t- '{f['var']}' = {f['uncond_source']} (unconditional, node {f['uncond_node']})\n",
                        f"\t- '{f['var']}' += {f['cond_source']} (ONLY inside if-branch, node {f['cond_node']})\n",
                        f"\t- Other operation paths skip '{f['cond_source']}' → potential cap/limit bypass\n",
                    ]
                    results.append(self.generate_result(info))
        return results

    def _analyze_function(self, function):
        findings = []
        if not function.nodes:
            return findings

        # Step 1: Collect node IDs inside conditional branches
        conditional_node_ids = set()
        for node in function.nodes:
            if node.contains_if() and node.sons:
                # Traverse the TRUE branch (sons[0])
                stack = [node.sons[0]]
                while stack:
                    n = stack.pop()
                    if n.node_id in conditional_node_ids:
                        continue
                    conditional_node_ids.add(n.node_id)
                    for son in n.sons:
                        stack.append(son)

        # Step 2: Track assignments and additions
        uncond_assigns = {}   # var -> (node_id, source)
        cond_adds = {}        # var -> [(node_id, source)]

        for node in function.nodes:
            for ir in node.irs:
                if not hasattr(ir, 'lvalue') or ir.lvalue is None:
                    continue
                var_name = str(ir.lvalue)

                if isinstance(ir, Assignment):
                    # var = source
                    source = str(ir.read[0]) if hasattr(ir, 'read') and ir.read else None
                    if source and node.node_id not in conditional_node_ids:
                        uncond_assigns[var_name] = (node.node_id, source)

                elif isinstance(ir, Binary):
                    # Check ADDITION: var = var + other (self-accumulation)
                    if "ADDITION" in str(ir.type):
                        reads = [str(r) for r in ir.read] if hasattr(ir, 'read') else []
                        if len(reads) >= 2 and reads[0] == var_name:
                            other_source = reads[1]
                            if node.node_id in conditional_node_ids:
                                cond_adds.setdefault(var_name, []).append(
                                    (node.node_id, other_source)
                                )

        # Step 3: Match — var assigned unconditionally from A,
        #          accumulated conditionally from B (B != A)
        for var_name, (uncond_node, uncond_source) in uncond_assigns.items():
            if var_name in cond_adds:
                for (cond_node, cond_source) in cond_adds[var_name]:
                    # Filter out loop counters (i += 1, i += constant)
                    if cond_source.isdigit() or cond_source.startswith("Constant"):
                        continue
                    if cond_source != uncond_source:
                        findings.append({
                            'var': var_name,
                            'uncond_source': uncond_source,
                            'uncond_node': uncond_node,
                            'cond_source': cond_source,
                            'cond_node': cond_node,
                        })
        return findings
