"""
Custom Slither Detector: ERC4626 Inflation Attack
Detects vaults where share price can be manipulated via donation.

Pattern:
  - totalAssets() uses balanceOf(this)
  - No virtual shares/offset
  - Public deposit/withdraw

If attacker donates 1 wei + mints 1 share → share price inflated
→ next depositor's shares round to 0 → funds stolen

Author: IRONCLAW v7
"""

from slither.detectors.abstract_detector import AbstractDetector, DetectorClassification


class ERC4626Inflation(AbstractDetector):
    ARGUMENT = "erc4626-inflation-attack"
    HELP = "Vault share price manipulable via donation (inflation attack)"
    IMPACT = DetectorClassification.HIGH
    CONFIDENCE = DetectorClassification.MEDIUM

    WIKI = "https://github.com/crytic/slither/wiki/Detector-Documentation"
    WIKI_TITLE = "ERC4626 Inflation Attack"
    WIKI_DESCRIPTION = (
        "Detects ERC4626-like vaults where totalAssets() reads balanceOf(this) "
        "without virtual share offset. First depositor can be front-run: "
        "attacker deposits 1 wei, donates large amount, inflating share price. "
        "Victim's deposit rounds to 0 shares → funds locked."
    )
    WIKI_EXPLOIT_SCENARIO = """
```solidity
function totalAssets() public view returns (uint256) {
    return IERC20(asset).balanceOf(address(this)); // manipulable!
}
// No virtual offset → first depositor vulnerable
```
"""
    WIKI_RECOMMENDATION = "Add virtual shares: totalAssets() + 1, totalSupply() + 1"

    def _detect(self):
        results = []
        for contract in self.contracts:
            # Look for balanceOf in totalAssets-like functions
            has_balance_of_in_assets = False
            has_virtual_offset = False
            has_deposit = False
            
            for func in contract.functions_declared:
                fname = func.name.lower()
                
                # Check for deposit function
                if "deposit" in fname or "mint" in fname:
                    has_deposit = True
                
                # Check for totalAssets / totalSupply with balanceOf
                if "total" in fname or "asset" in fname or "convert" in fname:
                    for node in func.nodes:
                        for ir in node.irs:
                            ir_str = str(ir)
                            if "balanceOf" in ir_str or "balance" in ir_str.lower():
                                has_balance_of_in_assets = True
                            # Check for +1 offset (virtual shares)
                            if "+ 1" in ir_str or "+1" in ir_str:
                                has_virtual_offset = True
                
                # Also check all functions for balanceOf pattern
                for node in func.nodes:
                    for ir in node.irs:
                        ir_str = str(ir)
                        if "balanceOf" in ir_str and ("asset" in fname or "total" in fname):
                            has_balance_of_in_assets = True
            
            if has_balance_of_in_assets and has_deposit and not has_virtual_offset:
                info = [
                    contract,
                    f" may be vulnerable to ERC4626 inflation attack:\n",
                    f"\t- Uses balanceOf for asset accounting\n",
                    f"\t- Has deposit/mint function\n",
                    f"\t- No virtual share offset detected (+1)\n",
                    f"\t- First depositor can be front-run → shares round to 0\n",
                ]
                results.append(self.generate_result(info))
        
        return results
