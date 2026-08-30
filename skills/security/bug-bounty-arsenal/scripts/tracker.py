#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
tracker.py — Bug Bounty Submission & Bounty Tracker (SQLite)
Usage:
  python tracker.py add --target target.com --title "IDOR account takeover" --severity HIGH --program "HackerOne: Shopify" [--bounty 1500]
  python tracker.py list
  python tracker.py stats
  python tracker.py update <id> --status triaged [--bounty 2000]
  python tracker.py report <hunter_results.json>   (bulk add dari hasil hunter.py)
  python tracker.py export --out bounties.csv
No-arg = help. DB: bb_tracker.sqlite di sebelah script ini.
"""
import sys, os, json, sqlite3, time, csv

HERE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(HERE, "bb_tracker.sqlite")

STATUS_FLOW = ["submitted", "triaged", "accepted", "rewarded", "duplicate", "N/A", "resolved", "dismissed"]


def db():
    conn = sqlite3.connect(DB)
    conn.execute("""CREATE TABLE IF NOT EXISTS submissions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        target TEXT NOT NULL,
        title TEXT NOT NULL,
        severity TEXT NOT NULL,
        program TEXT,
        status TEXT DEFAULT 'submitted',
        bounty_usd REAL DEFAULT 0,
        submitted_at TEXT DEFAULT (datetime('now')),
        updated_at TEXT DEFAULT (datetime('now')),
        notes TEXT DEFAULT ''
    )""")
    conn.commit()
    return conn


def parse_kv(args, i):
    """parsing sederhana --key value"""
    opts = {}
    while i < len(args):
        if args[i].startswith("--") and i + 1 < len(args):
            opts[args[i][2:]] = args[i + 1]
            i += 2
        else:
            i += 1
    return opts


def cmd_add(args):
    opts = parse_kv(args, 0)
    if not opts.get("target") or not opts.get("title"):
        print("[x] wajib: --target --title. Opsional: --severity --program --bounty")
        return
    sev = opts.get("severity", "MED").upper()
    conn = db()
    cur = conn.execute(
        "INSERT INTO submissions (target,title,severity,program,bounty_usd) VALUES (?,?,?,?,?)",
        (opts["target"], opts["title"], sev, opts.get("program", ""), float(opts.get("bounty", 0))))
    conn.commit()
    print(f"[+] id={cur.lastrowid} — {opts['title']} ({sev})")


def cmd_list(args):
    conn = db()
    rows = conn.execute("SELECT * FROM submissions ORDER BY id DESC").fetchall()
    if not rows:
        print("[i] belum ada submission. Tambah: python tracker.py add --target X --title Y")
        return
    print(f"{'ID':<4} {'SEV':<5} {'STATUS':<11} {'BOUNTY':>8}  TARGET — TITLE")
    for r in rows:
        bounty = f"${r[6]:,.0f}" if r[6] else "-"
        print(f"{r[0]:<4} {r[3]:<5} {r[5]:<11} {bounty:>8}  {r[1]} — {r[2][:50]}")


def cmd_stats(args):
    conn = db()
    total = conn.execute("SELECT COUNT(*) FROM submissions").fetchone()[0]
    rewarded = conn.execute("SELECT COUNT(*), SUM(bounty_usd) FROM submissions WHERE status='rewarded'").fetchone()
    paid = conn.execute("SELECT COUNT(*) FROM submissions WHERE bounty_usd > 0").fetchone()[0]
    accepted = conn.execute("SELECT COUNT(*) FROM submissions WHERE status IN ('accepted','triaged','rewarded','resolved')").fetchone()[0]
    dup = conn.execute("SELECT COUNT(*) FROM submissions WHERE status='duplicate'").fetchone()[0]
    total_bounty = conn.execute("SELECT SUM(bounty_usd) FROM submissions").fetchone()[0] or 0
    by_sev = conn.execute("SELECT severity, COUNT(*) FROM submissions GROUP BY severity ORDER BY 2 DESC").fetchall()
    print(f"=== Bounty Stats ===")
    print(f"Total submission : {total}")
    print(f"Accepted/triaged : {accepted}")
    print(f"Rewarded         : {rewarded[0]} (${rewarded[1] or 0:,.0f})")
    print(f"Duplicate        : {dup}")
    print(f"Total bounty     : ${total_bounty:,.0f}")
    if by_sev:
        print("Per severity     : " + ", ".join(f"{s}={c}" for s, c in by_sev))


def cmd_update(args):
    if not args:
        print("[x] usage: python tracker.py update <id> --status triaged [--bounty 2000] [--notes ...]")
        return
    sid = int(args[0])
    opts = parse_kv(args, 1)
    conn = db()
    sets, vals = [], []
    if opts.get("status"):
        if opts["status"] not in STATUS_FLOW:
            print(f"[x] status harus: {STATUS_FLOW}")
            return
        sets.append("status=?"); vals.append(opts["status"])
    if opts.get("bounty"):
        sets.append("bounty_usd=?"); vals.append(float(opts["bounty"]))
    if opts.get("notes"):
        sets.append("notes=?"); vals.append(opts["notes"])
    if not sets:
        print("[x] ga ada yang di-update")
        return
    sets.append("updated_at=datetime('now')")
    vals.append(sid)
    conn.execute(f"UPDATE submissions SET {', '.join(sets)} WHERE id=?", vals)
    conn.commit()
    print(f"[+] id={sid} updated")


def cmd_report(args):
    if not args:
        print("[x] usage: python tracker.py report hunter_results.json")
        return
    with open(args[0], "r", encoding="utf-8") as f:
        data = json.load(f)
    target = data.get("target", "unknown")
    findings = data.get("findings", [])
    conn = db()
    n = 0
    for f in findings:
        sev = f.get("severity", "LOW").upper()
        if sev == "INFO":
            continue
        conn.execute(
            "INSERT INTO submissions (target,title,severity,notes) VALUES (?,?,?,?)",
            (target, f.get("title", "finding"), sev, f.get("poc", "")))
        n += 1
    conn.commit()
    print(f"[+] {n} temuan dari {target} masuk tracker")


def cmd_export(args):
    opts = parse_kv(args, 0)
    out = opts.get("out", "bounties.csv")
    conn = db()
    rows = conn.execute("SELECT * FROM submissions ORDER BY id").fetchall()
    with open(out, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["id", "target", "title", "severity", "program", "status", "bounty_usd", "submitted_at", "updated_at", "notes"])
        w.writerows(rows)
    print(f"[+] {len(rows)} baris → {out}")


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(0)
    cmd = args[0]
    rest = args[1:]
    if cmd == "add":
        cmd_add(rest)
    elif cmd == "list":
        cmd_list(rest)
    elif cmd == "stats":
        cmd_stats(rest)
    elif cmd == "update":
        cmd_update(rest)
    elif cmd == "report":
        cmd_report(rest)
    elif cmd == "export":
        cmd_export(rest)
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
