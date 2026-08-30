#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
scanner-nuclei.py — Nuclei Vulnerability Scanner Integration (stdlib-only)
Run nuclei scanner on target using external nuclei binary or bundled template library.

Usage:
  python scanner-nuclei.py <url/domain> [--template <templates>] [--tags <tag-list>] [--output nuclei_results.json]
  python scanner-nuclei.py --help      (show usage)
  python scanner-nuclei.py --list-templates   (list available templates)
  
External dependencies:
- nuclei (binary): download from https://github.com/projectdiscovery/nuclei/releases
- Template library: nuclei-templates repo
  
Options:
--template   Comma-separated list of template names (default: all web templates)
--tags       Filter by tags: critical, high, medium, low, info, sqli,xss,ssrf,jwt,idor
--timeout    Request timeout (default: 10s)
--concurrency Thread count (default: 10)
--no-auth    Disable auth detection from cookies/headers
"""
import sys, os, json, re, subprocess, urllib.request
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "nuclei_results.json")
NUCLEI_BIN = os.path.expanduser("~/.hermes/security-tools/bin/nuclei")
TEMPLATES_DIR = os.path.expanduser("~/.hermes/security-tools/nuclei-templates")


def check_nuclei():
    """Check if nuclei binary exists."""
    if os.path.exists(NUCLEI_BIN):
        return True
    # Fallback to PATH
    r = subprocess.run(["nuclei", "-version"], capture_output=True, text=True)
    return r.returncode == 0


def get_templates(template_filter=None):
    """Load nuclei templates, optionally filter by tag/category."""
    if not TEMPLATES_DIR.exists():
        print(f"[!] Templates directory not found: {TEMPLATES_DIR}")
        print("[!] Install nuclei-templates first:")
        print("    git clone https://github.com/projectdiscovery/nuclei-templates.git ~/.hermes/security-tools/")
        return []
    
    templates = []
    for root, dirs, files in os.walk(TEMPLATES_DIR):
        for f in files:
            if f.endswith(".yaml") or f.endswith(".yml"):
                filepath = os.path.join(root, f)
                try:
                    with open(filepath, "r", encoding="utf-8") as tf:
                        content = tf.read()[:2000]  # read first 2KB for metadata
                        # Parse simple YAML fields
                        template_info = {
                            "path": filepath.replace("\\", "/"),
                            "name": os.path.basename(filepath)[:-5],
                            "id": None,
                            "severity": None,
                            "tags": [],
                        }
                        
                        # Extract ID
                        m = re.search(r"id:\s*([a-zA-Z0-9_-]+)", content)
                        if m:
                            template_info["id"] = m.group(1)
                        
                        # Extract severity
                        m = re.search(r"info:\s*\{[^}]*severity:\s*([a-z]+)", content, re.S)
                        if m:
                            template_info["severity"] = m.group(1).lower()
                        
                        # Extract tags
                        m = re.search(r"tags:\s*(\[.*?\]|(?:[a-z,\s]+))", content)
                        if m:
                            tag_str = m.group(1).strip()
                            if tag_str.startswith("["):
                                tags = re.findall(r'[a-zA-Z0-9_-]+', tag_str)
                            else:
                                tags = [t.strip() for t in tag_str.split(",")]
                            template_info["tags"] = tags
                        
                        # Apply filters
                        ok = True
                        if template_filter:
                            if template_filter.get("id") and template_info["id"] != template_filter["id"]:
                                ok = False
                            if template_filter.get("severity") and template_info["severity"] != template_filter["severity"]:
                                ok = False
                            if template_filter.get("tags"):
                                if not any(t in template_info["tags"] for t in template_filter["tags"]):
                                    ok = False
                        
                        if ok:
                            templates.append(template_info)
                except Exception as e:
                    continue
    
    return templates


def run_nuclei(url, templates, tags=None, timeout=10, concurrency=10, out_path=None):
    """Execute nuclei scan on target."""
    if not check_nuclei():
        print("[!] Nuclei binary not found!")
        print("\nInstallation options:")
        print("1. Download from releases:")
        print("   curl -L https://github.com/projectdiscovery/nuclei/releases/latest/download/nuclei-windows-amd64.exe -o bin/nuclei.exe")
        print("2. Use go build:")
        print("   cd ~/.hermes/security-tools/nuclei && go build -o bin/nuclei")
        print("3. Skip this step, use hunter.py builtin scanner instead")
        return None
    
    cmd_parts = ["nuclei", "-jsonl"]  # JSON Lines output
    if out_path:
        cmd_parts.extend(["-o", str(out_path)])
    if timeout > 0:
        cmd_parts.extend(["-timeout", str(timeout)])
    cmd_parts.extend(["-headless", "-rate-limit", "50", "-c", str(concurrency)])
    cmd_parts.append("-target")
    
    if templates:
        # Specific templates
        cmd_parts.extend(["-t", ",".join([t["path"].replace("\\", "/") for t in templates])])
    elif tags:
        # Tag filtering
        cmd_parts.extend(["-tags", ",".join(tags)])
    else:
        # All web templates
        web_template = TEMPLATES_DIR / "web-crawler" / "http" / "selfies.yml"
        if web_template.exists():
            cmd_parts.extend(["-t", str(web_template).replace("\\", "/")])
        else:
            print("[!] No templates found, skipping scan")
            return None
    
    cmd_parts.extend(["-v"])
    cmd_parts.append(url)
    
    print(f"\n[*] Running nuclei scan on {url}")
    print(f"[*] Command: {' '.join(cmd_parts[:20])}...")
    
    try:
        result = subprocess.run(cmd_parts, capture_output=True, text=True, timeout=600)
        
        # Parse JSON Lines output
        findings = []
        if result.stdout:
            for line in result.stdout.strip().split("\n"):
                if line.strip():
                    try:
                        data = json.loads(line)
                        finding = {
                            "template_id": data.get("template-id", ""),
                            "template_path": data.get("template-path", ""),
                            "host": data.get("host", ""),
                            "info": data.get("info", {}),
                            "extracted_results": data.get("extracted-results", []),
                            "matcher-name": data.get("matcher-name", ""),
                            "request": data.get("request", {}),
                            "response": data.get("response", {}),
                        }
                        findings.append(finding)
                    except json.JSONDecodeError:
                        continue
        
        return {"url": url, "findings": findings, "total": len(findings)}
    except subprocess.TimeoutExpired:
        print("[!] Scan timed out after 10 minutes")
        return None
    except Exception as e:
        print(f"[!] Scan failed: {e}")
        return None


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(0)
    
    url = args[0]
    opts = {
        "templates": None,
        "tags": None,
        "timeout": 10,
        "concurrency": 10,
        "out_path": OUT,
        "list_templates": False,
    }
    
    i = 1
    while i < len(args):
        if args[i] == "--template":
            tmpl_names = args[i + 1].split(",")
            opts["templates"] = tmpl_names
            i += 2
        elif args[i] == "--tags":
            opts["tags"] = args[i + 1].split(",")
            i += 2
        elif args[i] == "--timeout":
            opts["timeout"] = int(args[i + 1])
            i += 2
        elif args[i] == "--concurrency":
            opts["concurrency"] = int(args[i + 1])
            i += 2
        elif args[i] == "--output":
            opts["out_path"] = args[i + 1]
            i += 2
        elif args[i] == "--list-templates":
            opts["list_templates"] = True
            i += 1
        elif args[i] == "--help":
            print(__doc__)
            sys.exit(0)
        else:
            i += 1
    
    if opts["list_templates"]:
        all_tmpls = get_templates()
        print(f"\nTotal {len(all_tmpls)} templates found:")
        # Group by severity
        by_sev = {}
        for t in all_tmpls:
            sev = t.get("severity", "unknown").upper()
            if sev not in by_sev:
                by_sev[sev] = []
            by_sev[sev].append(t)
        
        for sev in sorted(by_sev.keys(), reverse=True):
            tmpls = by_sev[sev]
            print(f"\n[{sev}] {len(tmpls)} templates:")
            for t in tmpls[:20]:
                print(f"  - {t['id'] or 'unnamed'} ({t['path'].split('/')[-1][:50]})")
            if len(tmpls) > 20:
                print(f"  ... and {len(tmpls)-20} more")
        return
    
    # Run scan
    results = run_nuclei(url, None, opts["tags"], opts["timeout"], opts["concurrency"], opts["out_path"])
    if results:
        with open(opts["out_path"], "w") as f:
            json.dump(results, f, indent=2)
        print(f"\n[+] Scan complete: {results['total']} findings -> {opts['out_path']}")


if __name__ == "__main__":
    main()
