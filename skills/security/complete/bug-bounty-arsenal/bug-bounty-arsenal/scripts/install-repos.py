#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
install-repos.py — Install Security Toolset from GitHub
Download & setup official resources: PayloadsAllTheThings, SecLists, ProjectDiscovery tools.

Usage:
  python install-repos.py [--all] [--payloads] [--seclists] [--tools] [--audit] [--mobile]
No-arg = show options and ask which to install.

Repos yang didownload:
WEB2:
- PayloadsAllTheThings (swisskyrepo) - payload banks XSS/SQLi/SSRF/SSTI/XXE/JWT/GraQL/OAuth/bypass
- SecLists (danielmiessler) - wordlists subdomain/directory/parameter/fuzzing/payloads
- ffuf (web fuzzer), nuclei (vulnerability scanner), subfinder/httpx (recon suite)
WEB3:
- Slither (Solidity static analyzer), Echidna (fuzzer), Medusa (fuzzer)
- Awesome Web3 Security resources
MOBILE:
- MobSF (setup instructions), Frida (setup instructions)
CLOUD:
- Gitleaks (secret scanner), TruffleHog (secret scanner)
TRAINING:
- Damn Vulnerable DeFi, Ethernaut, OWASP GenAI/LLM Top 10

Output: Semua repositori di ~/.hermes/security-tools/ dengan symlink di PATH.
"""
import sys, os, json, re, subprocess, platform
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = Path(os.path.expanduser("~/.hermes/security-tools"))
INSTALLS = []


def repo_info(name, url, desc):
    return {"name": name, "url": url, "desc": desc}


REPOS = {
    # WEB2
    "payloads-all-the-things": repo_info(
        "PayloadsAllTheThings",
        "https://github.com/swisskyrepo/PayloadsAllTheThings.git",
        "Kumpulan payload XSS/SQLi/SSRF/SSTI/XXE/LFI/RCE/JWT/OAuth/GraphQL/bypass/WAF"
    ),
    "seclists": repo_info(
        "SecLists",
        "https://github.com/danielmiessler/SecLists.git",
        "Wordlists untuk subdomain enumeration, directory brute force, parameter fuzzing, payloads, usernames, passwords"
    ),
    "tbhm": repo_info(
        "The Bug Hunter's Methodology",
        "https://github.com/jhaddix/tbhm.git",
        "Complete methodology dari reconnaissance sampai exploitation dan reporting"
    ),
    
    # PROJECTDISCOVERY ECOSYSTEM
    "subfinder": repo_info(
        "Subfinder",
        "https://github.com/projectdiscovery/subfinder.git",
        "Subdomain enumeration via passive DNS sources"
    ),
    "httpx": repo_info(
        "httpx",
        "https://github.com/projectdiscovery/httpx.git",
        "HTTP probing tool untuk scan alive hosts dari subdomain list"
    ),
    "nuclei": repo_info(
        "Nuclei",
        "https://github.com/projectdiscovery/nuclei.git",
        "Vulnerability scanner berbasis template CVE/misconfiguration/exposure/takeover"
    ),
    
    # WEB3 SMART CONTRACT
    "slither": repo_info(
        "Slither",
        "https://github.com/crytic/slither.git",
        "Static analyzer Solidity/Vyper untuk detect vulnerability patterns"
    ),
    "echidna": repo_info(
        "Echidna",
        "https://github.com/crytic/echidna.git",
        "Property-based smart-contract fuzzer untuk find edge-case bugs"
    ),
    "medusa": repo_info(
        "Medusa",
        "https://github.com/crytic/medusa.git",
        "Smart-contract fuzzing campaign tool automated vulnerability discovery"
    ),
    "awesome-web3-security": repo_info(
        "Awesome Web3 Security",
        "https://github.com/rootkit-io/awesome-web3-security.git",
        "Web3 security resources: audit reports, tools, CTF challenges, exploit research"
    ),
    "damnm-vulnerable-defi": repo_info(
        "Damn Vulnerable DeFi",
        "https://github.com/theredguild/damn-vulnerable-defi.git",
        "CTF lab untuk practice DeFi exploits dan smart contract auditing"
    ),
    "ethernaut": repo_info(
        "Ethernaut",
        "https://github.com/OpenZeppelin/ethernaut.git",
        "Game-based learning Ethereum smart contract vulnerabilities"
    ),
    
    # AI / LLM SECURITY
    "owasp-genai": repo_info(
        "OWASP GenAI Security Project",
        "https://github.com/OWASP/GenAI-Security-Project.git",
        "Generative AI security guidelines, threat models, testing methodologies"
    ),
    "owasp-llm-top10": repo_info(
        "OWASP LLM Top 10",
        "https://github.com/OWASP/www-project-top-10-for-large-language-model-applications.git",
        "Top 10 LLM vulnerabilities: prompt injection, data leakage, insecure output handling"
    ),
    
    # MOBILE SECURITY (resources only, binaries manual)
    "mobsec-resources": repo_info(
        "MobSF Resources",
        "https://github.com/MobSF/Mobile-Security-Framework-MobSF.git",
        "Documentation dan workflow untuk static/dynamic mobile app analysis"
    ),
    
    # CLOUD / SECRETS
    "gitleaks": repo_info(
        "Gitleaks",
        "https://github.com/gitleaks/gitleaks.git",
        "Secrets detection tool untuk git repositories dan file systems"
    ),
    "trufflehog": repo_info(
        "TruffleHog",
        "https://github.com/trufflesecurity/trufflehog.git",
        "Deep credential scanning untuk discover exposed API keys, tokens, passwords"
    ),
}


def checkout_repo(name, url, dest):
    """Clone or update repository."""
    print(f"\n{'='*60}")
    print(f"[{name}] {url}")
    print(f"{'='*60}")
    
    if dest.exists():
        print("[+] Repository already exists, updating...")
        r = subprocess.run(["git", "-C", str(dest), "pull"], capture_output=True, text=True)
        print(r.stdout[-500:] if len(r.stdout) > 500 else r.stdout)
    else:
        print(f"[*] Cloning from {url}...")
        r = subprocess.run(["git", "clone", "--depth=1", url, str(dest)], 
                          capture_output=True, text=True, timeout=300)
        if r.returncode != 0:
            print(f"[!] Clone failed: {r.stderr[-500:]}")
            return False
        print(f"[✓] Cloned successfully")
    INSTALLS.append(name)
    return True


def run_cmd(cmd, cwd=None):
    """Run shell command, return success status."""
    r = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True, timeout=180)
    if r.returncode == 0:
        print(f"[✓] {cmd[:80]}")
        return True
    else:
        print(f"[!] Command failed: {cmd[:80]}")
        print(f"STDERR: {r.stderr[-300:]}")
        return False


def setup_symlinks():
    """Create symlinks to executables in PATH."""
    bin_dir = Path(os.path.expanduser("~/.hermes/node/bin"))
    bin_dir.mkdir(parents=True, exist_ok=True)
    
    tools_bin = BASE / "bin"
    tools_bin.mkdir(parents=True, exist_ok=True)
    
    # Map tool_name -> (source_binary, link_name)
    links = [
        ("ffuf", "ffuf"),
        ("nuclei", "nuclei"),
        ("subfinder", "subfinder"),
        ("httpx", "httpx"),
        ("gitleaks", "gitleaks"),
        ("trufflehog", "trufflehog"),
    ]
    
    for src, dst in links:
        src_path = BASE / src / src
        if src_path.exists():
            link_path = tools_bin / dst
            try:
                if link_path.exists() or link_path.is_symlink():
                    link_path.unlink()
                link_path.symlink_to(src_path)
                print(f"[+] Symlink: {link_path.name} -> {src_path.absolute()}")
            except Exception as e:
                print(f"[!] Symlink failed ({dst}): {e}")


def check_golang():
    """Check if Go is installed."""
    r = subprocess.run(["go", "version"], capture_output=True, text=True)
    return r.returncode == 0


def main():
    args = sys.argv[1:]
    
    # Categorize by group
    groups = {
        "all": list(REPOS.keys()),
        "payloads": ["payloads-all-the-things", "seclists"],
        "tools": ["subfinder", "httpx", "nuclei", "tbhm"],
        "audit": ["slither", "echidna", "medusa", "awesome-web3-security", "damnm-vulnerable-defi", "ethernaut"],
        "ai": ["owasp-genai", "owasp-llm-top10"],
        "mobile": ["mobsec-resources"],
        "cloud": ["gitleaks", "trufflehog"],
    }
    
    # Default selection logic
    if not any(a.startswith("--") for a in args):
        choice = input("Pilih kategori yang mau diinstall:\n" +
                      "1) all         — semua repository + tools\n" +
                      "2) payloads    — PayloadsAllTheThings + SecLists\n" +
                      "3) tools       — ffuf, nuclei, subfinder, httpx (need Go)\n" +
                      "4) audit       — Slither, Echidna, Medusa, DeFi labs (need Go)\n" +
                      "5) cloud       — Gitleaks, TruffleHog secret scanners\n" +
                      "6) ai          — OWASP LLM security resources\n" +
                      "7) mobile      — MobSF workflow docs\n" +
                      "Choice: ").strip().lower()
        categories = {
            "1": "all", "all": "all",
            "2": "payloads", "payloads": "payloads",
            "3": "tools", "tools": "tools",
            "4": "audit", "audit": "audit",
            "5": "cloud", "cloud": "cloud",
            "6": "ai", "ai": "ai",
            "7": "mobile", "mobile": "mobile",
        }.get(choice, "payloads")
        selected = groups[categories]
    else:
        selected = []
        for a in args:
            if a.startswith("--"):
                cat = a[2:]
                if cat in groups:
                    selected.extend(groups[cat])
                elif a == "--all":
                    selected = groups["all"]
        
        if not selected:
            print("Nothing selected, defaulting to payloads+tools")
            selected = groups["payloads"] + groups["tools"]
    
    print(f"\n[*] Installing {len(selected)} repositories...")
    print(f"Base directory: {BASE}")
    
    # Create base directories
    BASE.mkdir(parents=True, exist_ok=True)
    
    # Clone repos
    for name in selected:
        if name not in REPOS:
            continue
        info = REPOS[name]
        dest = BASE / info["name"].lower().replace("-", "_").replace(".", "")
        checkout_repo(info["name"], info["url"], dest)
    
    # Special setup for Go-based tools
    if any(n in ["subfinder", "httpx", "nuclei", "slither", "echidna", "medusa", "gitleaks", "trufflehog"] for n in selected):
        print("\n" + "="*60)
        print("GO-BASED TOOLS SETUP")
        print("="*60)
        if not check_golang():
            print("[!] Go not found! Install Go first:")
            print("    Windows: https://go.dev/doc/install")
            print("    Or use Docker images instead")
            print("\nSkipping compilation step. Tools will be downloaded via 'install-tools' script.")
        else:
            go_tools = ["subfinder", "httpx", "nuclei", "slither", "gitleaks", "trufflehog"]
            for tool in go_tools:
                if tool in selected or (tool + "-compiled" not in str(INSTALLS)):
                    tool_base = BASE / tool
                    if tool_base.exists():
                        print(f"\n[*] Compiling {tool}...")
                        r = subprocess.run(["go", "build", "-o", "bin/" + tool], 
                                          cwd=str(tool_base), capture_output=True, text=True, timeout=600)
                        if r.returncode == 0:
                            INSTALLS.append(f"{tool}-compiled")
                        else:
                            print(f"[!] Build failed: {r.stderr[-200:]}")
    
    # Setup symlinks
    setup_symlinks()
    
    # Print summary
    print("\n" + "="*60)
    print("✅ INSTALLATION COMPLETE")
    print("="*60)
    print(f"Installed: {', '.join(INSTALLS)}")
    print(f"\nLocation: {BASE}")
    print("\nNext steps:")
    print("1. Verify tools: ffuf --version, nuclei -version")
    print("2. Run arsenal integrations:")
    print(f"   cd {HERE}")
    print(f"   python huntall.py target.com --full --use-nuclei")
    print(f"   python har2scan.py capture.har --deep-scanner nuclei")
    
    if "payloads-all-the-things" in INSTALLS or "seclists" in INSTALLS:
        print("\n💡 Payload banks ready at:")
        pats = BASE / "payloads_all_the_things" / "references"
        sec = BASE / "seclists" / "Discovery"
        print(f"   Payloads: {pats}")
        print(f"   Wordlists: {sec}")
    
    if any(n in INSTALLS for n in ["slither", "echidna", "medusa"]):
        print("\n🔥 Smart contract auditing:")
        print("   slither <contract.sol>", "echidna-test <contract.sol>", "medusa -t <project>")


if __name__ == "__main__":
    main()
