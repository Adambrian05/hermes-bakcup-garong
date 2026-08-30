#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
har2scan.py — HAR to Scan Target Converter (stdlib-only)
Parse HAR 1.2 file → ekstrak API endpoints → output siap di-scan hunter.py.

Usage:
  python har2scan.py <capture.har> [--out endpoints.json] [--include-static]
  python har2scan.py <capture.har> --scan       (langsung scan pakai hunter.py)
  python har2scan.py <capture.har> --print      (tampilkan daftar endpoints)
No-arg = help.
"""
import sys, os, json, re, urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "har_endpoints.json")

# resource type yang menarik buat bug bounty (skip static assets)
API_TYPES = {"xhr", "fetch", "document", "websocket", "other", "ping"}
SKIP_EXT = {".css", ".js", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".ico",
            ".woff", ".woff2", ".ttf", ".eot", ".mp4", ".mp3", ".webm",
            ".wasm", ".map", ".pdf"}

SKIP_HOSTS = {"fonts.googleapis.com", "fonts.gstatic.com", "cdn.jsdelivr.net",
              "unpkg.com", "ajax.googleapis.com", "code.jquery.com",
              "www.google-analytics.com", "google-analytics.com",
              "www.googletagmanager.com", "stats.g.doubleclick.net",
              "cdnjs.cloudflare.com", "connect.facebook.net", "analytics.tiktok.com"}


def parse_har(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def extract_endpoints(har, include_static=False):
    """Ekstrak endpoint API unik dari HAR."""
    endpoints = []
    seen = set()
    entries = har.get("log", {}).get("entries", [])

    for e in entries:
        req = e.get("request", {})
        resp = e.get("response", {})
        url = req.get("url", "")
        if not url:
            continue
        parsed = urllib.parse.urlparse(url)
        host = parsed.netloc.lower()

        # skip host sampah
        if host in SKIP_HOSTS:
            continue
        # skip static assets
        if not include_static:
            path = parsed.path.lower()
            if any(path.endswith(ext) for ext in SKIP_EXT):
                continue
            rt = e.get("_resourceType", "").lower()
            if rt and rt not in API_TYPES:
                continue

        method = req.get("method", "GET")
        key = f"{method} {parsed.scheme}://{host}{parsed.path}"
        if key in seen:
            continue
        seen.add(key)

        # params + data body
        query_params = {p.get("name"): p.get("value", "") for p in req.get("queryString", [])}
        post_data = ""
        pd = req.get("postData", {})
        if pd:
            post_data = pd.get("text", "")[:2000]

        # headers penting
        headers = {}
        for h in req.get("headers", []):
            hn = h.get("name", "").lower()
            if hn in ("authorization", "x-api-key", "x-auth-token", "x-csrf-token", "cookie", "content-type", "x-requested-with"):
                headers[h.get("name")] = h.get("value", "")[:200]

        endpoints.append({
            "method": method,
            "url": url.split("?")[0],
            "host": host,
            "path": parsed.path,
            "query": query_params,
            "post_data": post_data,
            "status": resp.get("status"),
            "content_type": (resp.get("content", {}) or {}).get("mimeType", ""),
            "headers": headers,
            "_resourceType": e.get("_resourceType", ""),
        })
    return endpoints


def print_endpoints(endpoints):
    if not endpoints:
        print("[i] tidak ada endpoint ditemukan (coba --include-static)")
        return
    print(f"{'METHOD':<8} {'STATUS':<7} PATH")
    for e in endpoints:
        print(f"{e['method']:<8} {e.get('status', '-'):<7} {e['host']}{e['path']}")


def save_endpoints(endpoints, out_path):
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({"endpoints": endpoints, "total": len(endpoints)}, f, indent=2)
    return out_path


def generate_scan_commands(endpoints):
    """Generate daftar perintah hunter.py per host unik."""
    hosts = sorted({e["host"] for e in endpoints})
    cmds = []
    for h in hosts:
        paths = [e["path"] for e in endpoints if e["host"] == h]
        auth = None
        for e in endpoints:
            if e["host"] == h and e.get("headers", {}).get("Authorization"):
                auth = e["headers"]["Authorization"]
                break
        cmd = f'python "{os.path.join(HERE, "hunter.py")}" https://{h}'
        if auth:
            cmd += f' --bearer "{auth[:80]}"'
        cmd += f" --modules idor,jwt,graphql,massassign,rate"
        cmds.append({"host": h, "paths": paths[:20], "cmd": cmd, "auth": auth})
    return cmds


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(0)
    har_path = args[0]
    if not os.path.exists(har_path):
        print(f"[x] file tidak ada: {har_path}")
        sys.exit(1)

    out_path = OUT
    do_scan = "--scan" in args
    do_print = "--print" in args
    include_static = "--include-static" in args
    i = 1
    while i < len(args):
        if args[i] == "--out":
            out_path = args[i + 1]; i += 2
        else:
            i += 1

    print(f"[*] parse HAR: {har_path}")
    har = parse_har(har_path)
    endpoints = extract_endpoints(har, include_static)
    print(f"[*] {len(endpoints)} endpoint API unik ditemukan\n")

    if do_print or not do_scan:
        print_endpoints(endpoints)

    save_endpoints(endpoints, out_path)
    print(f"\n[*] tersimpan: {out_path}")

    cmds = generate_scan_commands(endpoints)
    if cmds:
        print("\n[*] scan command per host:")
        for c in cmds:
            print(f"  {c['cmd']}")

    if do_scan:
        print("\n=== AUTO-SCAN pakai hunter.py ===")
        import subprocess
        for c in cmds:
            print(f"\n>>> {c['cmd']}")
            subprocess.run(c["cmd"], shell=True)


if __name__ == "__main__":
    main()
