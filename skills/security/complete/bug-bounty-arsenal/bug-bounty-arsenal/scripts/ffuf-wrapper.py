#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ffuf-wrapper.py — FFUF Directory Bruteforce Integration (stdlib-only)
Run ffuf directory/file discovery from arsenal, with built-in wordlists.

Usage:
  python ffuf-wrapper.py <url/domain> [--wordlist <path>] [--extensions html,txt,json]
                               [--mc <status-codes>] [--mc 200,301,302,403]
                               [--t 50 --threads 50] [--recursion --recursion-depth 3]
No-arg = help.
"""
import sys, os, json, re, subprocess
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))


def get_wordlists():
    """Get list of available wordlists."""
    base = os.path.expanduser("~/.hermes/security-tools/seclists/Discovery")
    if not os.path.exists(base):
        print("[i] No SecLists found. Skip building wordlists.")
        return []
    
    words = []
    for subdir in ["webservices", "cms", "curl", "directory-list"]:
        path = os.path.join(base, subdir)
        if os.path.isdir(path):
            for f in os.listdir(path):
                if f.endswith(".txt") or f.endswith(".lst"):
                    words.append(os.path.join(path, f))
    return words[:10]  # first 10


def run_ffuf(url, options):
    """Execute ffuf command via shell."""
    url = url.strip("/")
    cmd = [os.path.expanduser("~/.hermes/security-tools/bin/ffuf"), "-u", f"https://{url}/FUZZ"]
    
    # Default options
    cmd.extend(["-w", "default.txt"])  # fallback
    cmd.extend(["-r", "10", "-t", "40"])  # retry 10x, threads 40
    
    # Add custom options
    for key, value in options.items():
        prefix = "-" + (key[0] if len(key) == 1 else "--")
        cmd.append(prefix + key)
        if value is not True:
            cmd.append(str(value))
    
    print(f"\n[*] Running ffuf on {url}")
    print(f"[*] Command: {' '.join(cmd[:30])}...")
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
        
        # Parse output
        findings = []
        for line in result.stdout.split("\n"):
            m = re.match(r"# (URL|CODE|SIZE):\s*(.+)\|\s*(\d+)", line)
            if m:
                url_f, code, size = m.groups()
                findings.append({
                    "url": url_f,
                    "status_code": int(code),
                    "size": int(size),
                })
        
        return {"target": url, "findings": findings, "total": len(findings)}
    except subprocess.TimeoutExpired:
        print("[!] ffuf timed out")
        return None
    except Exception as e:
        print(f"[!] ffuf error: {e}")
        return None


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(0)
    
    url = args[0]
    opts = {
        "wordlist": None,
        "extensions": None,
        "mc": "200,301,302,403",
        "t": "40",
        "re": False,
        "rd": "3",
        "exclude_status": None,
        "timeout": "30",
    }
    
    i = 1
    while i < len(args):
        arg = args[i]
        next_val = args[i+1] if i+1 < len(args) else None
        
        if arg == "--wordlist":
            opts["wordlist"] = next_val
            i += 2
        elif arg == "--extensions":
            opts["extensions"] = next_val
            i += 2
        elif arg == "-S" or "--silent":
            i += 1
        elif arg == "-X" or "--exclude-status":
            opts["exclude_status"] = next_val
            i += 2
        elif arg == "-H" and ":" in (next_val or ""):
            pass  # header syntax handled separately
        elif arg == "-r" or "--recursion":
            opts["re"] = True
            i += 1
        elif arg == "-R" or "--recursion-depth":
            opts["rd"] = next_val or "3"
            i += 2
        elif arg == "-p" or "--pauses" or "-t" or "--threads":
            if arg == "-t" and i+1 < len(args):
                opts["t"] = next_val
                i += 2
            else:
                i += 1
        elif arg == "-o" or "--output" or "-f" or "--format":
            i += 1  # skip format output, use JSON parsing instead
            i += 1
        else:
            i += 1
    
    # Run
    results = run_ffuf(url, opts)
    
    if results:
        out_path = os.path.join(HERE, "ffuf_results.json")
        with open(out_path, "w") as f:
            json.dump(results, f, indent=2)
        print(f"\n[+] Found {results['total']} paths -> {out_path}")


if __name__ == "__main__":
    main()
