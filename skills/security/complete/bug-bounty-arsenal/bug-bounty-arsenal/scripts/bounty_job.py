#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
bounty_job.py — Feeder script untuk cron job bug bounty (stdlib-only)
Dijalankan tiap tick oleh cron; output = JSON hasil scan target list.

Usage:
  python bounty_job.py                # scan semua target dari targets.json
  python bounty_job.py --add URL      # tambah target ke list
  python bounty_job.py --list         # tampilkan target list
  python bounty_job.py --reset        # hapus semua state hasil
No-arg = scan & print ringkasan (untuk cron output).
"""
import os, sys, json, time, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL_SCRIPTS = os.path.join(HERE)
TARGETS_FILE = os.path.join(HERE, "targets.json")
STATE_FILE = os.path.join(HERE, "bounty_state.json")

DEFAULT_TARGETS = [
    # Public practice targets — aman buat latihan, diganti dengan program bounty
    "testphp.vulnweb.com",
    "juice-shop.herokuapp.com",
]

def load_targets():
    if os.path.exists(TARGETS_FILE):
        with open(TARGETS_FILE, "r") as f:
            return json.load(f)
    return {"targets": DEFAULT_TARGETS, "updated": time.time()}

def save_targets(data):
    with open(TARGETS_FILE, "w") as f:
        json.dump(data, f, indent=2)

def load_state():
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE, "r") as f:
            return json.load(f)
    return {"scans": {}, "findings_total": 0, "last_run": None}

def save_state(state):
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)

def run_scan(target, timeout=180):
    """Run hunter.py buat satu target, return hasil JSON."""
    script = os.path.join(SKILL_SCRIPTS, "hunter.py")
    cmd = [sys.executable, script, f"https://{target}",
           "--modules", "headers,exposed,cors,xss,sqli,ssrf,idor,redirect",
           "--timeout", "10", "--out", os.path.join(SKILL_SCRIPTS, f"scan_{target}.json")]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        out_path = os.path.join(SKILL_SCRIPTS, f"scan_{target}.json")
        if os.path.exists(out_path):
            with open(out_path, "r") as f:
                return json.load(f)
        return {"target": target, "error": "no output", "stderr": r.stderr[:200]}
    except subprocess.TimeoutExpired:
        return {"target": target, "error": "timeout"}
    except Exception as e:
        return {"target": target, "error": str(e)}

def main():
    args = sys.argv[1:]
    if "--add" in args:
        url = args[args.index("--add") + 1]
        data = load_targets()
        if url not in data["targets"]:
            data["targets"].append(url)
            save_targets(data)
            print(f"[+] target ditambah: {url}")
        else:
            print(f"[i] target udah ada: {url}")
        return
    if "--list" in args:
        data = load_targets()
        print(f"[*] {len(data['targets'])} target:")
        for t in data["targets"]:
            print(f"  - {t}")
        return
    if "--reset" in args:
        for f in os.listdir(SKILL_SCRIPTS):
            if f.startswith("scan_") and f.endswith(".json"):
                os.remove(os.path.join(SKILL_SCRIPTS, f))
        if os.path.exists(STATE_FILE):
            os.remove(STATE_FILE)
        print("[+] state direset")
        return

    # Default: scan semua target
    data = load_targets()
    state = load_state()
    new_findings = 0

    print(f"[*] bug bounty scan — {len(data['targets'])} target")
    for target in data["targets"]:
        print(f"  scanning {target}...")
        result = run_scan(target)
        if "findings" in result:
            n = len(result["findings"])
            state["scans"][target] = {
                "time": time.strftime("%Y-%m-%d %H:%M:%S"),
                "findings": n,
                "severity": {
                    "CRIT": sum(1 for f in result["findings"] if f.get("severity") == "CRIT"),
                    "HIGH": sum(1 for f in result["findings"] if f.get("severity") == "HIGH"),
                    "MED": sum(1 for f in result["findings"] if f.get("severity") == "MED"),
                    "LOW": sum(1 for f in result["findings"] if f.get("severity") == "LOW"),
                }
            }
            new_findings += n
            print(f"    {n} temuan")
        else:
            print(f"    error: {result.get('error', 'unknown')}")

    state["last_run"] = time.strftime("%Y-%m-%d %H:%M:%S")
    state["findings_total"] += new_findings
    save_state(state)

    print(f"\n[*] total temuan baru: {new_findings}")
    print(f"[*] total kumulatif: {state['findings_total']}")
    print(f"[*] next step: review scan_*.json & buktikan manual")

if __name__ == "__main__":
    main()
