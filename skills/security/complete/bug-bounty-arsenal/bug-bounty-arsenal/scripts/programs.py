#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
programs.py — Scrap Program Bounty dari HackerOne/Bugcrowd/YesWeHack (public)
Usage:
  python programs.py --hackerone --bugcrowd --yeswehack [--out programs.json]
  python programs.py --search "web"                (filter keyword di program name)
No-arg = help. Hasil ke programs.json dengan struktur:
[{name,url,payout_min,max,status,platform}]
"""
import sys, os, json, re, urllib.request, ssl

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "programs.json")


def http_get(url, timeout=40):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    try:
        resp = urllib.request.urlopen(f"{url}?q=", timeout=timeout, context=ctx)
        return resp.read().decode(errors="replace")
    except Exception:
        return ""


def hh_programs():
    """Scrape public programs dari HackerOne."""
    url = "https://www.hackerone.com/directory/browse/programs?order=date_updated&sort=desc&q=&platform[]=Web+Application&platform[]=Android&platform[]=iOS&platform[]=Blockchain"
    body = http_get(url)
    if not body or len(body) < 100:
        print("[x] fetch HH gagal"); return []
    results = []
    for m in re.finditer(r'data-hn-program.*?"slug":"([^"]+)".*?"title":"([^"]+?)".*?"payoutRange":\["min":([0-9]+),"max":([0-9]+)\]', body, re.S):
        slug, title, min_p, max_p = m.groups()
        results.append({
            "name": title,
            "url": f"https://hackerone.com/{slug}",
            "payout_min": int(min_p),
            "payout_max": int(max_p),
            "status": "Open",
            "platform": "HackerOne",
        })
    # fallback simple scrape
    if not results:
        for m in re.finditer(r'<a[^>]+href="/([^"]+/program)"[^>]*>([^<]+)', body):
            slug, name = m.groups()
            results.append({"name": name, "url": f"https://hackerone.com/{slug}", "payout_min": 500, "payout_max": 50000, "status": "Open", "platform": "HackerOne"})
    return results[:60]


def bc_programs():
    """Scrape public programs dari Bugcrowd."""
    url = "https://bugcrowd.com/public-platform-list/"
    body = http_get(url)
    if not body or len(body) < 100:
        print("[x] fetch BC gagal"); return []
    results = []
    for m in re.finditer(r'(<div class="program-card"[^>]+?</div>)', body, re.S)[:20]:
        card = m.group(1)
        name = re.search(r'"program-title"([^>]*?)">([^<]+)', card).group(2)
        payouts = re.search(r'(\$[0-9]+,\d+)-(\$[0-9]+,\d+)', card)
        min_b = 500; max_b = 10000
        if payouts:
            min_b = int(payouts.group(1).replace("$,", "").replace(",", ""))
            max_b = int(payouts.group(2).replace("$,", "").replace(",", ""))
        results.append({"name": name, "url": "", "payout_min": min_b, "payout_max": max_b, "status": "Open", "platform": "Bugcrowd"})
    return results


def ywh_programs():
    """Scrape public programs dari YesWeHack."""
    url = "https://www.yeswehack.com/en/platform/programs"
    body = http_get(url)
    if not body or len(body) < 100:
        print("[x] fetch YWH gagal"); return []
    results = []
    for m in re.finditer(r'<article[^>]+class="card"[^>]*>(.*?)</article>', body, re.S)[:10]:
        card = m.group(1)
        name = re.search(r'<h3[^>]*>([^<]+)</h3>', card)
        if name:
            results.append({"name": name.group(1), "url": "", "payout_min": 500, "payout_max": 10000, "status": "Open", "platform": "YesWeHack"})
    return results


def filter_by_keyword(progs, kw):
    if not kw:
        return progs
    kw = kw.lower()
    return [p for p in progs if kw in p.get("name", "").lower()]


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(0)
    platforms = set(a for a in args if a.startswith("--"))
    do_hh = "--hackerone" in platforms
    do_bc = "--bugcrowd" in platforms
    do_ywh = "--yeswehack" in platforms
    out_path = OUT
    search_kw = ""
    i = 1
    while i < len(args):
        if args[i] == "--out":
            out_path = args[i + 1]; i += 2
        elif args[i] == "--search":
            search_kw = args[i + 1]; i += 2
        else:
            i += 1
    if not any([do_hh, do_bc, do_ywh]):
        do_hh = True
        do_bc = True
        do_ywh = True

    all_progs = []
    if do_hh:
        print("[*] hackerone...")
        all_progs.extend(hh_programs())
        print(f"[i] {len(all_progs)} programs")
    if do_bc:
        print("[*] bugcrowd...")
        all_progs.extend(bc_programs())
        print(f"[i] total {len(all_progs)} programs")
    if do_ywh:
        print("[*] yeswehack...")
        all_progs.extend(ywh_programs())
        print(f"[i] total {len(all_progs)} programs")

    if search_kw:
        all_progs = filter_by_keyword(all_progs, search_kw)

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(all_progs, f, indent=2, ensure_ascii=False)
    print(f"\n[*] saved to {out_path}")


if __name__ == "__main__":
    main()
