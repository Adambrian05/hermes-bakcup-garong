---
name: bug-bounty-arsenal
description: "Toolset lengkap buat hunting bug bounty ($20k-$30k+). Recon, scanner 35 modul, PoC generator, tracking."
version: 2.5.0
author: IKONA + Qoder
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [security, bug-bounty, pentest, exploitation, recon]
    related_skills: [har-capture, advanced-bug-hunting, web-exploit-test]
prerequisites:
  commands: [python]
---

# Bug Bounty Arsenal — Toolkit Praktis

Sekarang kita punya senjata lengkap buat hunt bug yang beneran dibayar mahal. Ini dia hasil build bareng — tools apa aja yang bisa dipake langsung.

| Fitur | web-exploit-test | bug-bounty-arsenal |
|-------|------------------|--------------------|
| Scope | test web sendiri | full workflow bounty |
| Recon | basic | crt.sh + wayback + DNS brute + JS secret scanning |
| Scanner | 14 modul | **35+ modul** (IDOR, GraphQL, JWT, race condition, cache poisoning...) |
| Report | JSON mentah | CVSS score, remediation steps, PoC langkah reproduksi |
| Tracker | ❌ | SQLite tracking submission + dollar ($) |
| Programs | ❌ | Scraper HackerOne/Bugcrowd/YesWeHack |
| Orchestrator | ❌ | `huntall.py` = satu command done |

## When to Use

Pakai tool ini kalau:
- Mau hunt bug di program bounty (HackerOne, Bugcrowd, dll) yang bayarnya gede
- Butuh recon lengkap sebelum scan — cari subdomain, API endpoint, secrets yang kebocor
- Perlu bukti PoC format submit ke program (langkah jelas + screenshot)
- Mau track submission dan duit yang diterima per bug

Gw build ini buat lu karena gw tau lu ga mau ribet install dependencies satu-satu. Semua script gw bikin stdlib-only — tinggal jalankan, langsung jalan tanpa报错.

## Installation

Gw udah include semua yang perlu di skill ini. Tinggal:

```bash
cd C:\Users\SERVER\AppData\Local\hermes\skills\security\bug-bounty-arsenal\scripts

# Full automation — langsung scan target
python huntall.py example.com --full

# Atau step-by-step kalau mau lebih kontrol:
python recon.py example.com --wayback --js --tech   # Recon dalem-dalem
python hunter.py https://example.com --slow        # Scan with time-based tests
python pocgen.py hunter_results.json               # Generate laporan
python tracker.py report hunter_results.json       # Masukin ke tracker
```

Kalau mau install external tools (ffuf, nuclei, slither, dll) buat capabilities tambahan:

```bash
python install-repos.py --all
```

**Note:** Core functions jalan tanpa tool tambahan. Nuclei/ffuf itu optional aja buat yang mau extra firepower.

## Quickstart

### Install Tools Tambahan (Optional)

```bash
cd C:\Users\SERVER\AppData\Local\hermes\skills\security\bug-bounty-arsenal\scripts
python install-repos.py --all
```

### Full Pipeline (Recon + Scan + Report + Tracker)

```bash
cd C:\Users\SERVER\AppData\Local\hermes\skills\security\bug-bounty-arsenal\scripts

# Auto-full: recon → scan → PoC generate → tracker
python huntall.py example.com --full

# Manual step-by-step:
python recon.py example.com --wayback --js --tech
python hunter.py https://example.com --slow   # --slow = time-based SQLi check
python pocgen.py hunter_results.json --outdir ./reports
python tracker.py report hunter_results.json
python tracker.py stats                       # liat total bounty potential
```

### Program Discovery (cari yang bayar paling gede)

```bash
# Scrap semua program public dari 3 platform besar
python programs.py --hackerone --bugcrowd --yeswehack --out top_programs.json

# Mau fokus ke payment processor? Cari aja keyword itu
python programs.py --search "payment"

# Sort by max payout — liat mana yang bayarnya paling gila
cat top_programs.json | python -c "import json,sys;progs=json.load(sys.stdin);print('\n'.join(f'{p['name']}: ${p['payout_max']}' for p in sorted(progs,key=lambda x:x['payout_max'],reverse=True)[:20]))"
```

### Advanced Recon (Cari subdomain yang orang biasanya skip)

```bash
# Complete recon — DNS brute + Wayback URL historis + JS secrets scan
python recon.py target.com --dns --js --tech

# Kalau target nge-rate-limit, reduce threads aja
python recon.py target.com --threads 5
```

### Advanced Scan (Pakai auth token buat test authenticated endpoints)

```bash
# Kalau butuh login dulu buat akses API:
python hunter.py https://target.com \
  --cookie "session=abc123" \
  --modules idor,jwt,graphql,massassign

# Mode lambat — time-based SQLi check (butuh waktu lebih lama)
python hunter.py https://target.com --slow --timeout 15

# Pakai proxy (Burp Suite di localhost:8080 biasanya)
python hunter.py https://target.com --proxy http://127.0.0.1:8080
```

## Tool Overview

### install-repos.py — Install tools external (ffuf, nuclei, slither, dll)

```bash
python install-repos.py --all              # Install semua
python install-repos.py --payloads         # Payload banks + wordlists
python install-repos.py --tools            # ffuf, nuclei, subfinder, httpx
python install-repos.py --audit            # Slither, Echidna, Medusa (smart contract)
python install-repos.py --cloud            # Gitleaks, TruffleHog secret scanner
python install-repos.py --ai               # OWASP LLM security resources
```

### har2scan.py — HAR Capture Integration

**HAR file → API endpoints → auto-scan.** Integrasi dengan skill `har-capture`.

Kalau website target SPA (React/Next/Vue) dan endpoint API-nya tersembunyi di balik JS, jangan nebak-nebak curl. Capture traffic dulu, terus feed ke hunter:

```bash
# 1. Capture traffic HAR (dari skill har-capture)
harcapture 'https://target.com' --headless --wait 15 -o capture.har

# 2. Parse + auto-scan endpoint API yang ketemu
cd C:\Users\SERVER\AppData\Local\hermes\skills\security\bug-bounty-arsenal\scripts
python har2scan.py capture.har --print      # liat endpoint apa aja
python har2scan.py capture.har --scan       # langsung scan pakai hunter.py

# 3. Output endpoint tersimpan di har_endpoints.json
```

**Yang diekstrak dari HAR:**
- Method + URL + path + query params
- Post data body (buat replay / test mass assignment)
- Auth headers (Authorization, X-API-Key, CSRF token, cookie)
- Status code + content type per endpoint
- Filter otomatis: skip static assets (css/js/png), skip host sampah (analytics, CDN)

**Kenapa penting buat bounty:**
- SPA menyembunyikan API — HAR capture = cara tercepat nemu endpoint
- Auth header yang ke-capture bisa langsung dipakai hunter.py (--bearer)
- Post data dari HAR = template buat test mass assignment/IDOR

### recon.py — Reconnaissance Engine

**Deteksi attack surface tersembunyi.** Subdomain mati-matian, JS leaks, endpoints hidden.

#### Modules:

1. **CRT.sh** — subdomain dari certificate transparency logs
2. **Wayback Machine** — URL historis (archive.org)
3. **DNS Brute Force** — 120+ kata wordlist built-in, resolve live
4. **Tech Fingerprint** — deteksi stack (PHP, Laravel, WordPress, Next.js, dll)
5. **JS Analysis** — extract semua .js files, scan **API keys, tokens, secrets**:
   - AWS Access Key / Secret
   - GitHub/GitLab token
   - Slack token
   - Stripe API keys
   - Google API key
   - Firebase DB endpoint
   - Discord webhook
   - Telegram bot token
   - MongoDB/Postgres/Redis URIs
   - Private keys PEM
   - Basic auth URLs
6. **Port Scan** — top 36 ports (80, 443, 22, 3306, 6379, 9200, dst)

#### Output:

File `recon_results.json`:
```json
{
  "domain": "example.com",
  "subdomains_crtsh": ["api.example.com", "dev.example.com"],
  "wayback_urls": [...],
  "subdomains_dns": {"sub1.example.com": ["1.2.3.4"]},
  "tech": [{"url": "...", "status": 200, "tech": ["next.js", "react", "node.js"]}],
  "js": {
    "secrets": [
      {"type": "Stripe Secret", "value": "sk_live_...", "file": "https://.../app.js"}
    ],
    "endpoints": ["/api/v1/users", "/oauth/token"]
  }
}
```

#### Pitfall:

- 200 OK ≠ exploitable — verifikasi manual
- Rate limit dari scraper: pakai --threads 10 kalau target nge-block
- Wayback: tidak lengkap (hanya archived pages)

---

### hunter.py — 35 Modul Vulnerability Scanner

**Comprehensive detection engine.** Tidak cuma XSS/SQLi, tapi juga: IDOR, JWT, GraphQL, mass assignment, rate limit bypass, OAuth redirect, cache poisoning, etc.

#### Module List (35+):

| Module | Severity | What it checks |
|--------|----------|----------------|
| `headers` | LOW | Security headers missing (HSTS, CSP, XFO) |
| `exposed` | CRIT | Dotfiles exposure (.git, .env, backup.sql) |
| `cors` | HIGH | Wildcard/CORS origin reflection |
| `methods` | MED | TRACE/PUT enabled (XST/file write) |
| `admin` | MED/HIGH | Admin panels, actuator, graphql console |
| `dirfuzz` | INFO | Common directories/files |
| `https` | LOW | HTTP→HTTPS not forced |
| `info` | HIGH | Stack trace/version leak |
| `xss` | HIGH | Reflected XSS in params |
| `sqli` | HIGH | Error-based + blind time-based SQLi |
| `nosqli` | MED | NoSQL injection ($ne,$where operators) |
| `ssti` | HIGH | Server-side template injection {{7*7}} |
| `ssrf` | CRIT | Cloud metadata access (AWS,GCP,AliCloud), internal network |
| `traversal` | CRIT | Path traversal ../../../etc/passwd |
| `redirect` | MED | Open redirect (//evil.com, javascript:) |
| `crlf` | HIGH | Header injection/set-cookie poisoning |
| `xxe` | CRIT | XML external entity file read |
| `ldap` | MED | LDAP injection (*) syntax |
| `jwt` | CRIT/HIGH | alg:none accepted, weak secret, expired but valid |
| `idor` | HIGH | Insecure direct object reference (can read user B's data) |
| `graphql` | MED | Introspection enabled + schema dump |
| `massassign` | MED | Role escalation via POST username=admin,role=admin |
| `proto` | MED | Prototype pollution (__proto__) |
| `hpp` | INFO | HTTP parameter pollution (dup param behavior) |
| `hostheader` | HIGH | Host header injection (password reset email hijack) |
| `clickjack` | LOW | Missing frame-ancestors/xfo |
| `rate` | MED | No rate limit (brute force possible) |
| `2fa` | - | Manual: skip/bypass/reuse 2FA codes |
| `oauth` | CRIT | Redirect_uri tampering (steal access token) |
| `deser` | - | Manual: Java serialized object deserialization |
| `subtakeover` | - | Manual: CNAME subdomain dead service takeover |
| `http2` | INFO | H2 server support (smuggling attacks) |
| `websocket` | - | Manual: ws:// handshake authentication bypass |
| `cachepoison` | MED | Cache poisoning via X-Forwarded-* header abuse |
| `timing` | MED | Timing side-channel (username enumeration) |

#### Authentication Testing:

Gunakan salah satu:
- `--cookie "sid=abc123"` — session cookie
- `--jwt eyJhbGc...` — JWT token
- `--bearer TOKEN` — bearer token

Dibutuhkan untuk tests: IDOR, GraphQL, JWT, rate limit, 2fa, oauth.

#### Time-Based Tests (Slow Mode):

Flag `--slow` mengaktifkan:
- Time-based SQLi (SLEEP/WAITFOR DELAY)
- Rate limit check (spam login)
- Username timing enumeration

Peringatan: lambat (30s per endpoint!), jangan dipakai di production besar!

#### Output:

File `hunter_results.json`:
```json
{
  "target": "https://example.com",
  "findings": [
    {
      "module": "idor",
      "severity": "HIGH",
      "title": "IDOR candidate: /api/user/0 returns data",
      "detail": "...data sensitive...",
      "poc": "curl https://example.com/api/user/0"
    },
    ...
  ]
}
```

Sortir otomatis berdasarkan severity (CRIT → LOW).

---

### pocgen.py — Professional PoC Report Generator

**Generate laporan siap submit ke program bounty** (HackerOne/Bugcrowd format).

#### Output Features:

- CVSS v3.1 score & vector
- CWE mapping per kategori bug
- Estimasi bounty range (berdasarkan severity)
- Impact assessment (business impact: data breach, financial loss)
- Step-by-step reproduction (copy-paste curl command)
- Remediation steps (code-level fix suggestion)
- References (OWASP, vendor docs)

#### Usage:

```bash
# Generate report dari hasil hunter.py
python pocgen.py hunter_results.json --outdir ./poc_reports --program "Example Company BH"

# Bulk: setiap CRIT/HIGH/MED jadi 1 markdown file
# Example output:
# poc_reports/02-critical-jwt-alg-none-accepted.md
# poc_reports/05-high-idor-account-data-exposure.md
```

#### Example Report Structure:

```markdown
# Account Takeover via CSRF + IDOR Chain

| Field | Value |
|---|---|
| Program | Example Company BH |
| Target | https://example.com |
| Severity | High (8.5/10) |
| CVSS v3.1 | CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:C/C:H/I:L/A:N |
| Estimated Bounty | $1,000 - $10,000 |
| Category | CSRF (CWE-352) |

## Summary

[Business impact explanation: attacker can transfer money, change ownership...]

## Steps to Reproduce

1. Attacker creates malicious page evil.html
2. Victim visits evil.html (via phishing or ads)
3. CSRF triggers: POST /api/transfer with amount=10000
4. Victim loses money from account

PoC:
curl -X POST https://example.com/api/transfer \
  -H "Cookie: session=victim_session" \
  -d '{"amount":10000,"to":"attacker_account"}'

## Impact

[Detailed breakdown of consequences: financial loss for victim, reputational damage...]

## Remediation

1. Implement CSRF token validation per request
2. Add re-authentication for sensitive actions (require password)
3. Monitor unusual transactions (large transfers, new payee)

## References

- OWASP Top 10: https://owasp.org/www-project-top-ten/
- CWE-352: https://cwe.mitre.org/data/definitions/352.html
```

---

### tracker.py — Submission & Bounty Tracker

**Track seluruh proses submission → triaged → awarded → rewarded**, catat berapa dolar yang didapat tiap bug.

#### Commands:

```bash
# Add new submission manually
python tracker.py add \
  --target example.com \
  --title "Account takeover via JWT forge" \
  --severity CRIT \
  --program "HackerOne: Example Co" \
  --bounty 15000

# Bulk import dari hunter results
python tracker.py report hunter_results.json

# List all submissions
python tracker.py list

# Update status after reply from program
python tracker.py update 5 --status triaged
python tracker.py update 5 --status accepted --bounty 15000

# Stats dashboard
python tracker.py stats

# Export to CSV (for personal finance tracking)
python tracker.py export --out bounties.csv
```

#### Stats Example:

```
=== Bounty Stats ===
Total submission : 25
Accepted/triaged : 18
Rewarded         : 5 ($52,500)
Duplicate        : 3
Total bounty     : $52,500
Per severity     : HIGH=12, MED=8, CRIT=5
```

---

### programs.py — Bounty Programs Scraper

**Find high-paying programs** yang open untuk public vulnerability reports.

```bash
# Fetch all public programs (3 platforms)
python programs.py --hackerone --bugcrowd --yeswehack --out programs_all.json

# Search payment-focused programs (high payout!)
python programs.py --search "payment"

# Show top 10 highest max payout
cat programs_all.json | python -c "import json,sys;p=json.load(sys.stdin);print('\n'.join(f'{p[\"name\"]}: ${p[\"payout_max\"]}' for p in sorted(p,key=lambda x:x['payout_max'],reverse=True)[:10]))"
```

#### Why Important:

Fokus di **yang bayar mahal** (not all programs equal!). Beberapa contoh:
- Payment processors: $20k-30k critical bugs
- Web3/blockchain: smart contract bugs worth millions
- Identity/auth providers: critical bugs $10k-20k
- E-commerce: cart manipulation bugs $2k-5k

---

### huntall.py — Orchestrator (All-in-One)

**Satu command full pipeline!** Mulai dari recon sampai tracker.

```bash
# Full automation
python huntall.py target.com --full

# Only specific stages
python huntall.py target.com --recon --scan
python huntall.py target.com --tracker  # (assume previous results exist)

# Dry run tanpa side effects
python huntall.py target.com --no-scan --recon  # only recon, no scan
```

Flow otomatis:
1. Recon → `recon_results.json` (subdomain, secrets, endpoints, tech stack)
2. Hunter scan → `hunter_results.json` (35 vuln modules)
3. PoC report generation → `./poc_reports/*.md` (professional format)
4. Tracker bulk import + stats

Output summary:
```
=== [1] RECON ===
[*] 45 subdomain | 12 secrets | 128 endpoints API

=== [2] SCANNER HUNTER (35 modul) ===
[*] CRIT: 2 | HIGH: 5

=== [3] GENERATE REPORTS ===
[*] 5 laporan PoC ready di ./poc_reports/

=== [4] TRACKER ===
[*] 5 temuan dari target masuk tracker
```

## Workflow Wajib

**Professional bug hunter bukan cuma run tool doang:**

```
Phase 1: Reconnaissance (2-4 jam)
├─ python programs.py --search "target"     (if known program)
├─ python recon.py domain.com --dns --js    (deep recon)
└─ Document: subdomains, APIs, tech stack, secrets

Phase 2: Target Selection (1-2 jam)
├─ Pick 1-2 most promising targets
├─ Read program scope (in-scope domains, excluded)
├─ Check rules of engagement (allowed techniques)
└─ Set expectations: time budget, depth

Phase 3: Automated Scan (1-3 jam)
├─ python huntall.py domain.com --full
├─ Review findings: filter false positives
└─ Note top candidates for manual verification

Phase 4: Manual Verification (CRITICAL) ⭐
├─ Replay each finding manually (browser/curl)
├─ Prove real impact (not just reflected!)
├─ Capture screenshots/video
└─ Chain related bugs (CSRF + IDOR = take-over)

Phase 5: Reporting (2-4 jam)
├─ python pocgen.py hunter_results.json --outdir ./reports
├─ Review & polish reports (clear English, reproducible)
├─ Estimate realistic bounty (don't overclaim)
└─ Submit via program platform

Phase 6: Tracking (ongoing)
├─ python tracker.py list (check status)
├─ Respond to triage questions promptly
├─ Update bounty when awarded
└─ Analyze rejected/duplicate for lessons
```

## Best Practices

### Legal & Ethical ⚖️

1. ✅ **Only authorized targets** — public bug bounty programs only (HackerOne, Bugcrowd, YesWeHack)
2. ✅ **Respect program rules** — no DoS (rate limiting), no social engineering, no attacking third-party services
3. ✅ **Responsible disclosure** — don't publish before vendor fixes
4. ✅ **Rate limiting** — don't hammer servers, respect politeness settings
5. ✅ **Minimal footprint** — avoid breaking functionality during testing

### Technical 🛠️

1. ✅ **Verify findings** — automated detector ≠ real exploit
2. ✅ **Demonstrate real impact** — show data exfiltration, not just alert() box
3. ✅ **Document everything** — screenshot, video, curl commands that reproduce
4. ✅ **Chain bugs wisely** — prove how low-severity bugs compound to critical
5. ✅ **Stay updated** — CVE feeds, technique updates (new bypass methods appear monthly)

### Business 💰

1. ✅ **Focus high-value targets** — payment systems > info sites
2. ✅ **Build reputation** — accept small bugs first (gain trust)
3. ✅ **Write clear reports** — good English = higher chance of acceptance
4. ✅ **Realistic expectations** — 20% success rate at beginner, 50%+ at pro
5. ✅ **Track earnings** — know which types of bugs pay best for you

## Monetization Reality Check

Realistic earnings curve (solo solo researcher):

**Month 1 (Learning):**
- Focus: learn tools, understand web security
- Expected: 0-1 accepted bugs
- Income: $0-200

**Month 2-3 (Beginner):**
- Focus: consistent scanning, manual verification
- Expected: 2-5 accepted bugs/month
- Income: $500-2k/month

**Month 4-6 (Intermediate):**
- Focus: business logic bugs, chaining
- Expected: 1-2 high/severe bugs/month
- Income: $3k-8k/month

**Month 6+ (Pro):**
- Focus: complex chains, zero-days
- Expected: 1-2 critical/high bugs/quarter
- Income: $10k-30k+/month (varies widely)

Key factors:
- Skill > luck (tools help, manual expertise wins)
- Persistence > intensity (consistency matters more than marathon scans)
- Quality > quantity (1 critical bug > 20 medium ones)
- Reputation > volume (private invites > public programs eventually)

## Related Skills

- `har-capture` — capture traffic HAR dari SPA (pair sama har2scan.py)
- `advanced-bug-hunting` — manual exploitation techniques (Burp, chaining)
- `web-exploit-test` — exploit battery versi lama (14 modul)
- `business-logic-hunter` — focus ke economic bugs (biasanya yang paling bayar)

## Pitfalls (Beberapa hal yang sering salah)

1. **Scanner nemu ≠ beneran exploit** — verification manual wajib, ga boleh percaya 100%
2. **False positive banyak** — jangan spam submit yang belum diverifikasi
3. **Overclaim severity** — low bug ya jangan dipaksa jadi critical tanpa proof cukup
4. **Documentation buruk** — report harus jelas step reproduksinya
5. **Attacking out-of-scope** — bisa banned permanen dari program

## Troubleshooting

### Recon timeout

```bash
python recon.py domain.com --threads 5
```

### Hunter hasilnya empty

Bisa karena:
- Targetnya emang secure (good job!)
- Butuh authentication (--cookie/--jwt)
- Ada WAF yang block request kita

Coba: `python hunter.py https://target.com --slow --cookie "auth=..."`

### No programs found di scraper

Platform API lagi rate limit — tunggu 1 jam dan retry. Atau browsing manual ke HackerOne/Bugcrowd homepage.

## Roadmap (Yang akan gw tambah nanti)

- Integration dengan Burp Suite Pro
- Browser extension buat automatic PoC recording
- Mobile app testing hooks
- GraphQL mutation fuzzing
- CI/CD hook (auto-run pada PR)

Gw bakal continue develop ini karena gw tau lu mau tool yang selalu update. Any suggestions?