#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
recon.py — Bug Bounty Recon Engine (stdlib-only)
Usage:
  python recon.py <domain> [--dns] [--wayback] [--js] [--ports] [--tech]
                            [--threads 10] [--out recon_results.json]
Default: crt.sh + wayback + tech + js (modul lambat --dns/--ports optional).
No-arg = help. Hasil tersimpan ke recon_results.json di sebelah script ini.
"""
import sys, os, json, re, ssl, socket, time
import urllib.request, urllib.parse, urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "recon_results.json")

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) bb-recon/1.0"

SUBDOMAIN_WORDS = [
    "www","api","api1","api2","api3","api-dev","api-staging","dev-api","admin","admin1",
    "dev","dev1","dev2","staging","staging1","staging2","test","test1","test2","qa","qa1","uat",
    "beta","alpha","demo","sandbox","preprod","pre","old","new","legacy","backup",
    "internal","intranet","private","portal","dashboard","panel","cp","control",
    "mail","mail1","mail2","smtp","webmail","imap","pop3","mx","ns1","ns2","dns",
    "ftp","sftp","ssh","vpn","remote","rdp","gateway","proxy","cache","cdn","cdn1","cdn2",
    "static","assets","img","images","media","files","file","upload","uploads","dl","download",
    "app","apps","m","mobile","mweb","touch","web","web1","web2","www2","www3","srv1","node1",
    "shop","store","pay","payment","billing","checkout","cart","order","orders",
    "login","signin","signup","account","accounts","auth","sso","id","oauth","keycloak",
    "help","support","status","docs","doc","wiki","kb","forum","community","blog","news",
    "git","gitlab","ci","jenkins","build","deploy","monitor","monitoring","metrics","grafana",
    "kibana","log","logs","analytics","stats","tracker","tracking","pixel","tag",
    "ws","websocket","socket","rtmp","stream","video","live","vod",
    "db","database","mysql","sql","redis","mongo","elastic","es","search","solr",
    "vault","secrets","key","keys","cert","ssl","secure","security",
    "k8s","kubernetes","docker","swarm","registry","harbor",
    "jira","confluence","wiki2","chat","slack","matrix","jitsi",
    "firewall","fw","waf","lb","loadbalancer","edge","origin","origin2",
    "intra","hr","finance","sales","crm","erp","pos","bi","report","reports",
    "site","sites","home","corp","corporate","edu","learn","lms","academy","training",
]

SECRET_PATTERNS = {
    "AWS Access Key":       r"AKIA[0-9A-Z]{16}",
    "AWS Secret Key":       r"(?i)aws.{0,25}secret.{0,25}['\"][0-9a-zA-Z/+=]{40}['\"]",
    "GitHub Token":         r"(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{36,255}",
    "GitLab Token":         r"glpat-[A-Za-z0-9\-]{20,}",
    "Slack Token":          r"xox[baprs]-[0-9A-Za-z-]{10,72}",
    "Stripe Secret":        r"sk_live_[0-9a-zA-Z]{24,99}",
    "Stripe Publishable":   r"pk_live_[0-9a-zA-Z]{24,99}",
    "Google API Key":       r"AIza[0-9A-Za-z\-_]{35}",
    "Google OAuth Client":  r"[0-9]+-[0-9A-Za-z_]{32}\.apps\.googleusercontent\.com",
    "Private Key PEM":      r"-----BEGIN (RSA|EC|DSA|OPENSSH|PRIVATE) ?[A-Z ]*KEY-----",
    "Heroku Key":           r"(?i)heroku.{0,30}[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
    "Twilio API Key":       r"SK[0-9a-fA-F]{32}",
    "SendGrid Key":         r"SG\.[0-9A-Za-z\-_]{22}\.[0-9A-Za-z\-_]{43}",
    "Mailgun Key":          r"key-[0-9a-zA-Z]{32}",
    "OpenAI Key":           r"sk-[A-Za-z0-9]{20,48}",
    "Mongo URI":            r"mongodb(\+srv)?://[^\s\"'<>]+",
    "MySQL URI":            r"mysql://[^\s\"'<>]+",
    "Postgres URI":         r"postgres(ql)?://[^\s\"'<>]+",
    "Redis URI":            r"redis://[^\s\"'<>]+",
    "AMQP URI":             r"amqps?://[^\s\"'<>]+",
    "JWT Token":            r"eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}",
    "Firebase DB":          r"[a-z0-9-]{4,63}\.firebaseio\.com",
    "Discord Webhook":      r"https://discord(app)?\.com/api/webhooks/[0-9]+/[A-Za-z0-9_\-]+",
    "Telegram Bot Token":   r"\d{8,10}:AA[A-Za-z0-9_-]{33}",
    "Shopify Token":        r"shpat_[0-9a-fA-F]{32}",
    "Shopify Shared":       r"shpss_[0-9a-fA-F]{32}",
    "Square Token":         r"sq0atp-[0-9A-Za-z\-_]{22}",
    "Braintree Token":      r"access_token\$production\$[0-9a-z]{16}\$[0-9a-f]{32}",
    "Mapbox Token":         r"pk\.eyJ[A-Za-z0-9\-_]{20,}\.[A-Za-z0-9\-_]{20,}",
    "Cloudflare API Key":   r"(?i)cloudflare.{0,40}(api.?key|api.?token).{0,10}['\"][0-9A-Za-z_-]{30,}['\"]",
    "Basic Auth URL":       r"https?://[^:@/\s]{2,40}:[^@/\s]{4,80}@[^\s\"'<>]+",
    "NPM Auth Token":       r"//registry\.npmjs\.org/:_authToken=([A-Za-z0-9-]+)",
    "PyPI Token":           r"pypi-[A-Za-z0-9_-]{50,}",
    "New Relic Key":        r"NRAK-[A-Z0-9]{27}",
    "Algolia Key":          r"ALGOLIA_[A-Z0-9]{32}",
    "Mailchimp Key":        r"[0-9a-f]{32}-us[0-9]{1,2}",
}

TOP_PORTS = [21, 22, 23, 25, 53, 80, 110, 135, 139, 143, 443, 445, 993, 995,
             1433, 1521, 1723, 2375, 3306, 3389, 5432, 5672, 6379, 8000, 8008,
             8080, 8081, 8443, 8888, 9000, 9200, 9300, 11211, 15672, 27017]

TECH_SIGS = [
    ("PHP", [r"X-Powered-By: PHP", r"PHPSESSID", r"\.php(?:$|\?)"]),
    ("WordPress", [r"wp-content/", r"wp-includes/", r"wp-json/"]),
    ("Drupal", [r"Drupal", r"drupal\.settings"]),
    ("Joomla", [r"Joomla", r"option=com_"]),
    ("Laravel", [r"laravel_session", r"XSRF-TOKEN"]),
    ("Django", [r"csrftoken", r"django"]),
    ("Ruby on Rails", [r"_session_id=", r"rails"]),
    ("ASP.NET", [r"ASP\.NET", r"__VIEWSTATE", r"ASPSESSIONID"]),
    ("Java", [r"JSESSIONID"]),
    ("Node.js", [r"express", r"nodejs"]),
    ("Next.js", [r"__NEXT_DATA__"]),
    ("Nuxt.js", [r"__NUXT__"]),
    ("React", [r"react(\.min)?\.js", r"__react"]),
    ("Vue.js", [r"vue(\.min)?\.js", r"data-v-[0-9a-f]"]),
    ("Angular", [r"ng-version", r"angular(\.min)?\.js"]),
    ("Shopify", [r"cdn\.shopify\.com", r"Shopify\.theme"]),
    ("Cloudflare", [r"__cfduid", r"cf-ray", r"CF-Cache-Status"]),
    ("Vercel", [r"x-vercel", r"vercel"]),
    ("Netlify", [r"netlify", r"__netlify"]),
    ("nginx", [r"server: nginx", r"nginx"]),
    ("Apache", [r"server: apache", r"apache"]),
    ("IIS", [r"server: microsoft-iis", r"iis"]),
    ("Firebase", [r"firebase", r"firestore"]),
    ("Supabase", [r"supabase"]),
    ("GraphQL", [r"graphql"]),
    ("jQuery", [r"jquery(?:-[0-9.]+)?(?:\.min)?\.js"]),
    ("Bootstrap", [r"bootstrap(?:\.min)?\.(css|js)"]),
]


def http_get(url, timeout=20, headers=None, max_bytes=2000000):
    h = {"User-Agent": UA, "Accept": "*/*"}
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, headers=h)
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    try:
        resp = urllib.request.urlopen(req, timeout=timeout, context=ctx)
        body = resp.read(max_bytes)
        return resp.status, dict(resp.headers), body
    except urllib.error.HTTPError as e:
        try:
            return e.code, dict(e.headers), e.read(max_bytes)
        except Exception:
            return e.code, {}, b""
    except Exception:
        return None, {}, b""


def crt_sh(domain):
    """Subdomain enum via certificate transparency (crt.sh)."""
    subs = set()
    url = "https://crt.sh/?q=%25." + domain + "&output=json"
    st, hd, body = http_get(url, timeout=30)
    if not st or st != 200:
        print(f"  [x] crt.sh gagal (HTTP {st})")
        return subs
    try:
        data = json.loads(body.decode(errors="replace"))
        for entry in data:
            for name in entry.get("name_value", "").split("\n"):
                name = name.strip().lower().lstrip("*.")
                if name.endswith("." + domain):
                    subs.add(name)
    except Exception as e:
        print(f"  [x] parse crt.sh gagal: {e}")
    return subs


def wayback(domain):
    """Ambil URL historis dari Wayback Machine."""
    urls = set()
    api = f"http://web.archive.org/cdx/search/cdx?url=*.{domain}/*&output=json&fl=original&collapse=urlkey&limit=2000"
    st, hd, body = http_get(api, timeout=40)
    if not st or st != 200:
        print(f"  [x] wayback gagal (HTTP {st})")
        return urls
    try:
        rows = json.loads(body.decode(errors="replace"))
        for row in rows[1:]:
            if row and isinstance(row, list) and row[0]:
                urls.add(row[0])
    except Exception as e:
        print(f"  [x] parse wayback gagal: {e}")
    return urls


def dns_brute(domain, threads=20):
    """Brute subdomain pakai wordlist built-in + resolusi DNS."""
    found = {}
    words = SUBDOMAIN_WORDS

    def resolve(word):
        host = f"{word}.{domain}"
        try:
            infos = socket.getaddrinfo(host, None, socket.AF_INET)
            ips = sorted({i[4][0] for i in infos})
            return host, ips
        except socket.gaierror:
            return None

    with ThreadPoolExecutor(max_workers=threads) as ex:
        futs = {ex.submit(resolve, w): w for w in words}
        done = 0
        for f in as_completed(futs):
            done += 1
            r = f.result()
            if r:
                found[r[0]] = r[1]
            if done % 50 == 0:
                print(f"    ... {done}/{len(words)}")
    return found


def tech_fingerprint(url):
    """Deteksi teknologi dari headers + body."""
    st, hd, body = http_get(url)
    tech = []
    if st is None:
        return {"url": url, "reachable": False, "tech": tech}
    text = ""
    try:
        text = body.decode(errors="replace")
    except Exception:
        pass
    haystack = text[:300000] + "\n" + "\n".join(f"{k}: {v}" for k, v in hd.items())
    for name, pats in TECH_SIGS:
        for p in pats:
            if re.search(p, haystack, re.I):
                tech.append(name)
                break
    # versi software
    versions = {}
    m = re.search(r"server:\s*([^\r\n]+)", haystack, re.I)
    if m:
        versions["Server"] = m.group(1).strip()
    m = re.search(r"x-powered-by:\s*([^\r\n]+)", haystack, re.I)
    if m:
        versions["X-Powered-By"] = m.group(1).strip()
    m = re.search(r'<meta[^>]+name=["\']generator["\'][^>]+content=["\']([^"\']+)', text, re.I)
    if m:
        versions["Generator"] = m.group(1).strip()
    m = re.search(r"jquery(?:-|/)([0-9]+\.[0-9.]+)", haystack, re.I)
    if m:
        versions["jQuery"] = m.group(1)
    return {"url": url, "status": st, "tech": sorted(set(tech)), "versions": versions}


def js_analysis(url):
    """Ambil halaman, temukan .js, scan secrets + endpoint."""
    result = {"scripts": [], "secrets": [], "endpoints": []}
    st, hd, body = http_get(url)
    if st is None:
        return result
    text = body.decode(errors="replace")
    base = urllib.parse.urljoin(url, "/")
    # temukan script src
    scripts = re.findall(r'<script[^>]+src=["\']([^"\']+)["\']', text, re.I)
    seen = set()
    for s in scripts:
        js_url = urllib.parse.urljoin(url, s)
        if js_url in seen:
            continue
        seen.add(js_url)
        if len(result["scripts"]) >= 40:
            break
        st2, hd2, body2 = http_get(js_url, max_bytes=5000000)
        if st2 and st2 == 200:
            result["scripts"].append(js_url)
            js = body2.decode(errors="replace")
            for name, pat in SECRET_PATTERNS.items():
                for m in re.finditer(pat, js):
                    val = m.group(0)
                    if len(val) > 200:
                        val = val[:200] + "..."
                    result["secrets"].append({"type": name, "value": val, "file": js_url})
            # endpoint extraction
            eps = set(re.findall(r'["\'`](/(?:api|v[0-9]|graphql|internal|admin|user|auth|account|upload|files?)/[A-Za-z0-9_\-/.{}:$]*)[\'"`]', js))
            eps |= set(re.findall(r'["\'`](?:https?://[^"\'`]{5,200})["\'`]', js))
            for e in sorted(eps):
                if len(result["endpoints"]) < 200:
                    result["endpoints"].append(e)
    # cari di inline script juga
    inline = "\n".join(re.findall(r"<script[^>]*>(.*?)</script>", text, re.S))
    for name, pat in SECRET_PATTERNS.items():
        for m in re.finditer(pat, inline):
            val = m.group(0)
            if len(val) > 200:
                val = val[:200] + "..."
            result["secrets"].append({"type": name, "value": val, "file": "(inline)"})
    return result


def port_scan(host, ports=None, threads=30):
    ports = ports or TOP_PORTS
    open_ports = []

    def check(p):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(2)
        try:
            if s.connect_ex((host, p)) == 0:
                return p
        except Exception:
            pass
        finally:
            s.close()
        return None

    with ThreadPoolExecutor(max_workers=threads) as ex:
        futs = [ex.submit(check, p) for p in ports]
        for f in as_completed(futs):
            r = f.result()
            if r:
                open_ports.append(r)
    return sorted(open_ports)


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(0)
    domain = args[0].lower().strip()
    domain = re.sub(r"^https?://", "", domain)
    domain = domain.split("/")[0].split(":")[0]
    flags = set(a for a in args[1:] if a.startswith("--"))
    do_dns = "--dns" in flags
    do_wb = "--wayback" in flags
    do_js = "--js" in flags
    do_ports = "--ports" in flags
    do_tech = "--tech" in flags
    # default: semua kecuali dns/ports (lambat)
    if not flags:
        do_wb = do_js = do_tech = True
    threads = 20
    for i, a in enumerate(args):
        if a == "--threads" and i + 1 < len(args):
            threads = int(args[i + 1])

    result = {"domain": domain, "generated": time.strftime("%Y-%m-%dT%H:%M:%S")}
    t0 = time.time()

    print(f"[*] recon: {domain}\n")

    print("=== crt.sh (subdomain via cert transparency) ===")
    subs = crt_sh(domain)
    result["subdomains_crtsh"] = sorted(subs)
    print(f"  [i] {len(subs)} subdomain ditemukan")

    if do_wb:
        print("\n=== Wayback Machine (URL historis) ===")
        urls = wayback(domain)
        result["wayback_urls"] = sorted(urls)[:500]
        print(f"  [i] {len(urls)} URL historis")

    if do_dns:
        print(f"\n=== DNS brute ({len(SUBDOMAIN_WORDS)} kata, {threads} threads) ===")
        found = dns_brute(domain, threads)
        result["subdomains_dns"] = {k: v for k, v in sorted(found.items())}
        print(f"  [i] {len(found)} subdomain resolve")

    all_subs = set(subs)
    if "subdomains_dns" in result:
        all_subs |= set(result["subdomains_dns"].keys())

    if do_tech:
        print("\n=== Tech fingerprint ===")
        tech_main = tech_fingerprint("https://" + domain)
        print(f"  [i] {tech_main.get('status')} {' '.join(tech_main.get('tech', [])) or 'unknown'}")
        if tech_main.get("versions"):
            print(f"      versions: {tech_main['versions']}")
        result["tech"] = [tech_main]
        if all_subs:
            alive = []
            with ThreadPoolExecutor(max_workers=10) as ex:
                futs = {}
                for s in sorted(all_subs)[:60]:
                    futs[ex.submit(tech_fingerprint, "https://" + s)] = s
                for f in as_completed(futs):
                    r = f.result()
                    if r.get("reachable", True) and r.get("status") and r["status"] < 500:
                        alive.append(r)
            result["tech_subs"] = alive
            print(f"  [i] {len(alive)} subdomain hidup (dari {min(60, len(all_subs))} dicek)")

    if do_js:
        print("\n=== JS analysis (secrets + endpoints) ===")
        js = js_analysis("https://" + domain)
        result["js"] = js
        print(f"  [i] {len(js['scripts'])} script JS dianalisis")
        if js["secrets"]:
            for s in js["secrets"]:
                print(f"  [!!] {s['type']}: {s['value'][:80]}  ({s['file']})")
        else:
            print("  [-] tidak ada secret terdeteksi")
        print(f"  [i] {len(js['endpoints'])} endpoint ditemukan")

    if do_ports:
        print("\n=== Port scan (top " + str(len(TOP_PORTS)) + " ports) ===")
        try:
            host_ip = socket.gethostbyname(domain)
        except socket.gaierror:
            host_ip = domain
        ports = port_scan(host_ip)
        result["ports"] = ports
        print(f"  [i] open: {ports or 'tidak ada'}")

    with open(OUT, "w") as f:
        json.dump(result, f, indent=2, default=str)
    print(f"\n[*] selesai dalam {time.time()-t0:.1f}s -> {OUT}")


if __name__ == "__main__":
    main()
