#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
audit-smart-contract.py — Web3 Smart Contract Audit Framework (stdlib-only)
Run static analysis using Slither, Echidna, or Medusa for Solidity/Vyper contracts.

Usage:
  python audit-smart-contract.py <contract.sol|folder> --slither [--output audit.json]
  python audit-smart-contract.py <contract.sol> --echidna [--tests 100]
  python audit-smart-contract.py <contract.sol> --medusa [--parallelism 4]
No-arg = help.

External dependencies:
- slither: https://github.com/crytic/slither
- echidna: https://github.com/crytic/echidna
- medusa: https://github.com/crytic/medusa
- solc compiler (for compilation): `solc --version`
"""
import sys, os, json, re, subprocess
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))


def check_tool(name):
    """Check if tool is available."""
    r = subprocess.run([name, "--version"], capture_output=True, text=True)
    return r.returncode == 0


def compile_solc(contract_path):
    """Compile contract with solc."""
    print(f"[*] Compiling {contract_path}...")
    r = subprocess.run(["solc", "--overwrite", "--bin", "--abi", "--ast-json", 
                       f"--include-paths={os.path.dirname(contract_path)}", str(contract_path)],
                      capture_output=True, text=True, timeout=60)
    
    if r.returncode != 0:
        print(f"[!] Compilation failed: {r.stderr[:500]}")
        return None
    
    # Parse output for artifacts
    artifacts = {}
    for line in r.stdout.split("\n"):
        m = re.match(r"(?:Binary hash of|Bytecode of)\s+([A-Za-z0-9_]+):\s+([0-9a-fA-F]+)", line)
        if m:
            name, bytecode = m.groups()
            artifacts[name] = {"bytecode": bytecode}
    
    return artifacts


def run_slither(contract_path, out_path=None):
    """Run Slither static analyzer."""
    if not check_tool("slither"):
        print("[!] Slither not found!")
        print("Install via:")
        print("  pip install slither-analyzer")
        print("Or from source:")
        print("  cd ~/.hermes/security-tools/slither && go build -o bin/slither")
        return None
    
    cmd = ["slither", contract_path, "--json"]
    if out_path:
        cmd.extend(["--json", out_path])
    
    print(f"\n[*] Running Slither on {contract_path}")
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        
        if result.returncode != 0 and result.stderr:
            print(f"[!] Slither warning: {result.stderr[:500]}")
        
        if result.stdout:
            data = json.loads(result.stdout)
            findings = []
            
            for issue in data.get("issues", []):
                finding = {
                    "severity": issue.get("highlights_out", [{}])[0].get("highlight", "Unknown"),
                    "issue_type": issue.get("type"),
                    "description": issue.get("description"),
                    "contracts": [a.get("source_mapping", {}).get("filename") for a in issue.get("sources", [])],
                    "locations": [loc.get("start", {}).get("line") for loc in issue.get("locations", [])],
                    "pdf_url": issue.get("pdf_url"),
                    "explanations": issue.get("explanation", ""),
                }
                findings.append(finding)
            
            return {
                "tool": "slither",
                "target": contract_path,
                "findings": findings,
                "total": len(findings),
                "by_severity": {},
            }
    except Exception as e:
        print(f"[!] Slither error: {e}")
        return None


def run_echidna(contract_path, tests=100):
    """Run Echidna property-based fuzzer."""
    if not check_tool("echidna-test"):
        print("[!] Echidna not found!")
        print("Download from: https://github.com/crytic/echidna/releases")
        return None
    
    cmd = ["echidna-test", contract_path, "--config", "-"]
    config = {
        "verbosity": 0,
        "testAllContracts": True,
        "coverageReporting": False,
        "corpusDir": corpus_cache_path(),
    }
    
    print(f"\n[*] Running Echidna on {contract_path} ({tests} tests)...")
    try:
        result = subprocess.run(cmd, input=json.dumps(config), capture_output=True, 
                              text=True, timeout=600)
        
        findings = parse_echidna_output(result.stdout + result.stderr)
        return {"tool": "echidna", "target": contract_path, "findings": findings, "total": len(findings)}
    except Exception as e:
        print(f"[!] Echidna error: {e}")
        return None


def parse_echidna_output(output):
    """Parse Echidna JSON output into structured findings."""
    findings = []
    for line in output.strip().split("\n"):
        if line.startswith("{"):
            try:
                data = json.loads(line)
                if isinstance(data, dict):
                    findings.append({
                        "status": data.get("status", ""),
                        "error": data.get("error", None),
                        "assertions": data.get("assertions", []),
                        "timestamp": data.get("timeStamp", ""),
                    })
            except json.JSONDecodeError:
                pass
    return findings


def corpus_cache_path():
    """Get path to Echidna corpus cache directory."""
    return os.path.join(HERE, "echidna_corpus")


def run_medusa(contract_path, parallelism=4):
    """Run Medusa fuzzing campaign."""
    if not check_tool("medusa"):
        print("[!] Medusa not found!")
        print("Install via Go: go install github.com/crytic/medusa/cmd/medusa@latest")
        return None
    
    # Medusa requires setup phase first
    cmd_setup = ["medusa", "setup", "-t", contract_path]
    print(f"\n[*] Setting up Medusa for {contract_path}...")
    try:
        subprocess.run(cmd_setup, capture_output=True, text=True, timeout=300)
    except Exception:
        pass
    
    # Run fuzzing
    cmd_fuzz = ["medusa", "-t", contract_path, "-r", "--parallelism", str(parallelism)]
    print(f"[*] Fuzzing campaign started (parallelism={parallelism})...")
    
    try:
        result = subprocess.run(cmd_fuzz, capture_output=True, text=True, timeout=3600)
        
        findings = []
        for line in result.stderr.split("\n"):
            if "Panic" in line or "Revert" in line or "Error" in line:
                m = re.search(r"panic|revert|error[:\s]+(.+)", line, re.I)
                if m:
                    findings.append({
                        "trigger": m.group(1)[:200],
                        "context": line[:500],
                    })
        
        return {"tool": "medusa", "target": contract_path, "findings": findings, "total": len(findings)}
    except Exception as e:
        print(f"[!] Medusa error: {e}")
        return None


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(0)
    
    contract_path = args[0]
    mode = "slither"
    extra = {}
    
    i = 1
    while i < len(args):
        if args[i] == "--echidna":
            mode = "echidna"
            i += 1
        elif args[i] == "--medusa":
            mode = "medusa"
            i += 1
        elif args[i] == "--slither":
            mode = "slither"
            i += 1
        elif args[i] == "--output":
            extra["out_path"] = args[i + 1]
            i += 2
        elif args[i] == "--tests":
            extra["tests"] = int(args[i + 1])
            i += 2
        elif args[i] == "--parallelism":
            extra["parallelism"] = int(args[i + 1])
            i += 2
        else:
            i += 1
    
    out_path = extra.get("out_path")
    results = []
    
    if mode == "slither":
        results.append(run_slither(contract_path, out_path))
    elif mode == "echidna":
        results.append(run_echidna(contract_path, extra.get("tests", 100)))
    elif mode == "medusa":
        results.append(run_medusa(contract_path, extra.get("parallelism", 4)))
    
    # Summary
    print("\n" + "="*60)
    print("✅ SMART CONTRACT AUDIT RESULTS")
    print("="*60)
    
    for r in results:
        if r:
            print(f"\n[{r['tool'].upper()}] {r['target']}")
            print(f"   Total findings: {r['total']}")
            for f in r.get("findings", [])[:5]:
                sev = f.get("severity", "unknown")
                desc = f.get("description", "")[:100]
                print(f"   [{sev}] {desc}...")
            
            # Save results
            out = extra.get("out_path", os.path.join(HERE, f"{mode}_audit_results.json"))
            if out:
                with open(out, "w") as f:
                    json.dump(r, f, indent=2)
                print(f"\n[+] Results saved to {out}")


if __name__ == "__main__":
    main()
