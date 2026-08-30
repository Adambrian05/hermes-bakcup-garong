#!/usr/bin/env python3
# -*- coding: utf-8 -*-
""" 
huntall.py — Bug Bounty All-in-One Orchestrator
Usage:
  python huntall.py <url/domain> --recon [--scan] [--report] [--tracker] [--har <file.har>]
No-arg = help. Flow otomatis: recon → scan → PoC generation → tracker, full pipeline one command.
--har: parse HAR capture dulu, endpoint API-nya langsung ke scan.
"""
import sys, os, json, re, time, subprocess, shutil

HERE = os.path.dirname(os.path.abspath(__file__))


def run_cmd(cmd):
    print(f"\n>>> {cmd}\n")
    return subprocess.run(cmd, shell=True, capture_output=True, text=True)


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(0)
    target = args[0].lower().strip()
    target = re.sub(r"^https?://", "", target)
    target = target.split("/")[0].split(":")[0]
    do_recon = True
    do_scan = "--scan" in args or "--hunter" in args
    do_nuclei = "--nuclei" in args
    do_ffuf = "--ffuf" in args
    do_report = "--report" in args or do_scan
    do_tracker = "--tracker" in args or do_report
    do_full = "full" in args

    # HAR integration
    har_file = None
    for idx, a in enumerate(args):
        if a == "--har" and idx + 1 < len(args):
            har_file = args[idx + 1]
            break

    opts = ["--recon"] if do_full else []
    if "--no-recon" in args:
        opts.append("--skip-recon")
    if "--no-scan" in args:
        opts.append("--skip-scan")

    t0 = time.time()
    print("=" * 60)
    print("🔥 BUG BOUNTY ARSENAL — Full Pipeline (stdlib-only)")
    print(f"Target: https://{target}")
    print("=" * 60)

    # 1. HAR (kalau ada)
    if har_file:
        print("\n=== [1] HAR CAPTURE PARSING ===")
        cmd_har = f'python "{os.path.join(HERE, "har2scan.py")}" "{har_file}" --print'
        r = run_cmd(cmd_har)
        print("[*] HAR parsed, endpoints siap di-scan")

    # 2. Recon
    print("\n=== [2] RECON ===")
    recon_out = os.path.join(HERE, "recon_results.json")
    cmd_recon = f'python "{os.path.join(HERE, "recon.py")}" {target}'
    r = run_cmd(cmd_recon)
    with open(recon_out, "r", encoding="utf-8") as f:
        rec_data = json.load(f)
    subs = len(rec_data.get("subdomains_crtsh", []))
    js_secrets = len(rec_data.get("js", {}).get("secrets", []))
    js_eps = len(rec_data.get("js", {}).get("endpoints", []))
    print(f"[*] {subs} subdomain | {js_secrets} secrets | {js_eps} endpoints API")
    if js_secrets > 0:
        for s in rec_data.get("js", {}).get("secrets", [])[:5]:
            print(f"[!!] {s['type']}: {s['value'][:60]}... ({s['file']})")

    # 3. Scan dengan hunter.py + nuclei (optional)
    if do_full or do_scan:
        print("\n=== [3] HUNTER SCANNER (35 modul) ===")
        hunter_out = os.path.join(HERE, "hunter_results.json")
        cmd_hunter = f'python "{os.path.join(HERE, "hunter.py")}" https://{target}'
        r = run_cmd(cmd_hunter)
        with open(hunter_out, "r", encoding="utf-8") as f:
            hunt_data = json.load(f)
        crit = sum(1 for x in hunt_data.get("findings", []) if x["severity"] == "CRIT")
        high = sum(1 for x in hunt_data.get("findings", []) if x["severity"] == "HIGH")
        print(f"[*] CRIT: {crit} | HIGH: {high} (verify manual sebelum submit)")
        # print top 5 findings
        for f in hunt_data.get("findings", [])[:5]:
            sev = f.get("severity", "LOW").upper()
            if sev in ("CRIT", "HIGH"):
                title = f.get("title", "")[:60]
                print(f"[!] [{sev}] {title}")

    # Scan dengan nuclei (optional, requires external tool)
    if do_nuclei:
        print("\n=== [4] NUCLEI SCANNER (vulnerability templates) ===")
        cmd_nuclei = f'python "{os.path.join(HERE, "scanner-nuclei.py")}" {target} --tags critical,high --output nuclei_results.json'
        r = run_cmd(cmd_nuclei)
        # Merge results jika ada
    
    # FFUF directory bruteforce (optional)
    if do_ffuf:
        print("\n=== [5] FFUF DIRECTORY BRUTEFORCE ===")
        cmd_ffuf = f'python "{os.path.join(HERE, "ffuf-wrapper.py")}" {target}'
        r = run_cmd(cmd_ffuf)

    print("\n" + "=" * 60)
    print(f"✅ Selesai {time.time()-t0:.1f}s")
    print("=" * 60)
    print("[+] Next steps:")
    print("1. Review hasil scan (hunter_results.json, nuclei_results.json)")
    print("2. Verifikasi temuan secara manual sebelum submit")
    print("3. Generate laporan: python pocgen.py hunter_results.json")
    print("4. Track di tracker: python tracker.py stats")
    print("\nAdvanced options:")
    print("- --nuclei: scan dengan vulnerability templates ProjectDiscovery")
    print("- --ffuf: directory bruteforce dengan ffuf")
    print("- --har <file>: parse HAR capture untuk endpoint API scanning")
    print("- --audit-smart-contract: smart contract security audit")


if __name__ == "__main__":
    main()
