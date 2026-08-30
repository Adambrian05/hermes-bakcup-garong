"""
Custom Slither Detector: Unlimited Admin Drain
Detects admin functions that can drain all funds without limits.

Pattern:
  function withdraw(address token, uint256 amount) onlyOwner {
      IERC20(token).transfer(msg.sender, amount);
      // No limit, no timelock, no multisig
  }

Author: IRONCLAW v7
"""

from slither.detectors.abstract_detector import AbstractDetector, DetectorClassification


class AdminDrain(AbstractDetector):
    ARGUMENT = "unlimited-admin-drain"
    HELP = "Admin can drain all funds without limit or timelock"
    IMPACT = DetectorClassification.MEDIUM
    CONFIDENCE = DetectorClassification.LOW

    WIKI = "https://github.com/crytic/slither/wiki/Detector-Documentation"
    WIKI_TITLE = "Unlimited Admin Drain"
    WIKI_DESCRIPTION = (
        "Detects functions with admin-only access that can transfer "
        "arbitrary amounts of tokens without limits, timelocks, or "
        "multi-approval requirements. A compromised admin key could "
        "drain all protocol funds."
    )
    WIKI_EXPLOIT_SCENARIO = """
```solidity
function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
    IERC20(token).transfer(msg.sender, amount); // No limit!
}
```
"""
    WIKI_RECOMMENDATION = "Add withdrawal limits, timelocks, or multi-sig for large amounts."

    def _detect(self):
        results = []
        for contract in self.contracts:
            for func in contract.functions_declared:
                # Check for admin modifiers
                is_admin = False
                for mod in func.modifiers:
                    mod_name = str(mod).lower()
                    if any(x in mod_name for x in ["onlyowner", "onlyadmin", "onlyrole", "onlymanager"]):
                        is_admin = True
                
                if not is_admin:
                    continue
                
                # Check for token transfers
                has_transfer = False
                has_limit = False
                for node in func.nodes:
                    for ir in node.irs:
                        ir_str = str(ir)
                        if "transfer" in ir_str.lower() or "safetransfer" in ir_str.lower():
                            has_transfer = True
                        if "require" in ir_str.lower() and ("amount" in ir_str.lower() or "limit" in ir_str.lower()):
                            has_limit = True
                
                if has_transfer and not has_limit:
                    info = [
                        func,
                        f" allows admin to drain funds without limit:\n",
                        f"\t- Has admin-only modifier\n",
                        f"\t- Contains token transfer\n",
                        f"\t- No amount limit or timelock detected\n",
                        f"\t- Compromised admin key → total drain\n",
                    ]
                    results.append(self.generate_result(info))
        return results
