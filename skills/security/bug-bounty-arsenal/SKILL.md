---
name: bug-bounty-arsenal
description: "Arsenal bug bounty profesional untuk $5k-$30k bounties. Recon, scanner 35 modul, PoC generator, tracker. Integrasi: HAR capture, ffuf, nuclei, smart contract audit."
version: 2.5.0
author: IKONA
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [security, bug-bounty, pentest, exploitation, recon, api-testing]
    related_skills: [har-capture, web-exploit-test, advanced-bug-hunting, bug-hunting, business-logic-hunter, security-checklist, forum-anti-hack]
prerequisites:
  commands: [python]
---

# Bug Bounty Arsenal — $20k+ Hunting Kit (stdlib-only)

**From automated scanner → manual exploit → professional report → paid bounty.**

Full suite untuk hunting bug yang **beneran dibayar**. Bedanya dari skill `web-exploit-test` sebelumnya:

| Fitur | web-exploit-test | bug-bounty-arsenal |
|-------|------------------|--------------------|
| Scope | test web sendiri | full bug bounty workflow |
| Recon | basic | crt.sh + wayback + DNS brute + JS secret scanning |
| Scanner | 14 modul | 35+ modul (IDOR, GraphQL, JWT, rate limit, cache poisoning) |
| Report | raw JSON | CVSS score, remediation steps, PoC langkah reproduksi |
| Tracker | - | SQLite tracking submission + bounty duit ($) |
| Programs | - | Scraper HackerOne/Bugcrowd/YesWeHack + payout info |
| Orchestrator | - | huntall.py = satu command full pipeline |

## When to Use

- Target program bounty (HackerOne, Bugcrowd, YesWeHack) dengan reward tinggi
- Mau mulai hunting bug yang **beneran dibayar** (not just Low severity)
- Butuh recon lengkap sebelum scan
- Butuh bukti PoC format submit ke program (steps + video demo idea)
- Track submission dan earnings

## Prerequisites

**Required:**
- Python 3.8+ (installed, default di Windows)
- Internet connection untuk public API programs

**Optional:**
- Telegram for notification (future enhancement)
- Email configured (jika mau auto-send report, via Himalaya)

## Installation

Skill ini sudah stand alone: semua script stdlib-only (no pip install needed). Tinggal jalanin!

**Location:** `~/AppData/Local/hermes/skills/security/bug-bounty-arsenal/scripts/`

## Quickstart

### Installation (Optional — untuk tools advanced)

```bash
# Install official repositories (PayloadsAllTheThings, SecLists, ffuf, nuclei, dll)
cd C:\Users\SERVER\AppData\Local\hermes\skills\security\bug-bounty-arsenal\scripts
python install-repos.py --all
```

**Note:** Core arsenal functions bekerja tanpa external dependencies. Tools tambahan optional untuk enhanced capabilities.

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

### Program Discovery (cari yang bayar gede)

```bash
# Scrape public program dari platform
python programs.py --hackerone --bugcrowd --yeswehack --out top_programs.json

# Filter search "payment" atau "api"
python programs.py --search "payment"

# Lihat sorted by max payout
cat top_programs.json | python -c "import json,sys;progs=json.load(sys.stdin);print('\n'.join(f'{p['name']}: ${p['payout_max']}' for p in sorted(progs,key=lambda x:x['payout_max'],reverse=True)[:20]))"
```

### Advanced Recon

```bash
# Recon + deep discovery
python recon.py target.com \
  --dns      # full DNS brute-force subdomain enumeration
  --ports    # port scanning top 36
  --js       # extract JS files + secrets scanning
  --threads 30

# Output ke file custom
python recon.py target.com --out my_recon.json
```

### Advanced Scan

```bash
# Authenticated testing (--cookie/--jwt/--bearer)
python hunter.py https://target.com \
  --cookie "session=abc123" \
  --modules idor,jwt,graphql,massassign,2fa

# Slow mode (time-based SQLi, rate limit check)
python hunter.py https://target.com --slow --timeout 15

# Custom modules
python hunter.py https://target.com --modules headers,xss,sqli,ssrf,idor

# Via Burp proxy
python hunter.py https://target.com --proxy http://127.0.0.1:8080
```

## Tool Overview

### install-repos.py — Official Repositories Installer (BARU)

**Download & setup official bug bounty resources:**

```bash
python install-repos.py --all              # semua repository + tools
python install-repos.py --payloads         # PayloadsAllTheThings + SecLists
python install-repos.py --tools            # ffuf, nuclei, subfinder, httpx
python install-repos.py --audit            # Slither, Echidna, Medusa, DeFi labs
python install-repos.py --cloud            # Gitleaks, TruffleHog secret scanners
python install-repos.py --ai               # OWASP LLM security resources
```

**Repos yang didownload ke `~/.hermes/security-tools/`:**

| Category | Tools | Purpose |
|----------|-------|---------|
| **WEB2** | PayloadsAllTheThings | XSS/SQLi/SSRF/SSTI/XXE/LFI/JWT/OAuth/GraphQL bypass payloads |
| | SecLists | Wordlists untuk subdomain enumeration, directory brute force, fuzzing |
| | ffuf | Web fuzzer untuk discovery files/directories/endpoints |
| | Nuclei | Vulnerability scanner berbasis template CVE/misconfiguration/exposure |
| | Subfinder/Httpx | Subdomain enumeration + alive host probing |
| | The Bug Hunter's Methodology | Complete methodology dari recon sampai reporting |
| **WEB3** | Slither | Static analyzer Solidity/Vyper smart contracts |
| | Echidna/Medusa | Property-based smart-contract fuzzers |
| | Damn Vulnerable DeFi | CTF lab untuk practice DeFi exploits |
| | Ethernaut | Game-based Ethereum vulnerability learning |
| | Awesome Web3 Security | Web3 audit reports, tools, exploit research |
| **AI** | OWASP GenAI Security | Generative AI security guidelines & threat models |
| | OWASP LLM Top 10 | Prompt injection, data leakage, insecure output handling |
| **MOBILE** | MobSF workflow | Mobile app static/dynamic analysis guides |
| **CLOUD** | Gitleaks/TruffleHog | Secret detection di git repositorie + file systems |

**After installation, run arsenal integrations:**
```bash
cd ~/AppData/Local/hermes/skills/security/bug-bounty-arsenal/scripts

# Scan dengan nuclei templates yang baru diinstall
python hunter.py target.com --modules exposed
python scanner-nuclei.py target.com --tags critical,high --output nuclei.json

# Directory bruteforce pakai ffuf
python ffuf-wrapper.py target.com --wordlist ~/.hermes/security-tools/seclists/Discovery/directory-list/large.txt

# Smart contract audit
python audit-smart-contract.py contract.sol --slither --output audit.json
python audit-smart-contract.py DamnvulnerableDeFi/challenges --echidna --tests 50
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

## Duplicate Skill Warning

**Note:** There are TWO `bug-bounty-arsenal` skills in the system:
1. `/root/.hermes/skills/security/bug-bounty-arsenal/` (main, active)
2. `/root/.hermes/skills/security/complete/bug-bounty-arsenal/` (duplicate, from RAR archive)

The main skill at `security/bug-bounty-arsenal/` is the authoritative version. The duplicate should be removed or consolidated.

---

## Related Skills

- `har-capture` — capture traffic HAR dari SPA (pair wajib sama har2scan.py)
- `advanced-bug-hunting` — manual exploitation techniques (Burp, Chaining, Exploitation)
- `web-exploit-test` — basic exploit battery (legacy, fewer modules)
- `bug-hunting` — simpler automated pipeline
- `business-logic-hunter` — focus pada economic/logic bugs (highest paying!)
- `security-checklist` — universal checklist sebelum delivery
- `forum-anti-hack` — defensive patching (after find bug, fix it)

## Pitfalls (Common Mistakes)

1. ❌ **Automated ≠ Proof** — scanner says "maybe vulnerable", you MUST prove manually
2. ❌ **False positive spam** — report quality drops if many invalid findings
3. ❌ **Overclaim severity** — $500 Low bug won't be bumped to Critical without chain
4. ❌ **Poor documentation** — unclear PoC = "unable to reproduce" (rejected)
5. ❌ **Attacking out-of-scope** — violates ToS = banned from program forever
6. ❌ **No rate limiting** — DDoS effect = legal trouble
7. ❌ **Public disclosure before fix** — kills relationship with program, future bans

## Troubleshooting

### Recon timeout

```bash
# Solution: reduce threads
python recon.py domain.com --threads 5
```

### Proxy Authentication Issues (407)

**Symptom:** `407 Proxy Authentication Required`

**Common causes:**
- Wrong credentials (username/password mismatch)
- IP not authorized (server IP not whitelisted)
- Wrong protocol (HTTP vs SOCKS5)

**See:** `references/proxy-and-network-issues.md` for full debug guide

### Target Blocking Server IP

**Symptom:** Connection timeout, HTTP 000

**Workaround:**
- Use proxy with different IP
- Use Camoufox (anti-detection browser)
- Run from local machine

**See:** `references/proxy-and-network-issues.md`

### Camoufox Dependencies (Headless Linux)

```bash
apt-get install -y libgtk-3-0 libasound2 libasound2t64
```

### RAR Archive Extraction

```bash
apt-get install -y unrar
unrar x archive.rar /destination/
```

### Google Drive Downloads

```bash
pip3 install gdown
gdown "https://drive.google.com/uc?id=FILE_ID" -O output.zip
```

### Hunter fails on HTTPS

```bash
# SSL cert verify issue (self-signed?)
# Script already disables verify, so shouldn't happen
# If persistent: check proxy/firewall config
```

### Reports empty (no findings)

```bash
# Not a bug! Either:
# 1. Site actually secure (great job, team!)
# 2. Need authenticated scan (--cookie/--jwt)
# 3. Target uses WAF (block your IP)

# Try:
python hunter.py https://target.com --slow --cookie "auth=..."
```

### No programs found

```bash
# Platform API changed / rate limited
# Wait 1 hour and retry

# Or search manually at:
# hackerone.com/directory
# bugcrowd.com/vdp-list
# yeswehack.com/platform/programs
```

## Roadmap (Future Enhancements)

- [ ] Integration with Burp Suite Pro (BAP integration)
- [ ] Browser extension for automatic PoC recording
- [ ] Mobile app testing (apktool/decompiler hooks)
- [ ] GraphQL mutation fuzzing (batch operations)
- [ ] Smart contract audit hooks (Solidity parsing)
- [ ] CI/CD hook (run on PR to auto-find regressions)
- [ ] Team collaboration (share findings across team members)
- [ ] AI assistant (auto-generate clear PoC descriptions from raw data)
- [ ] Video screen recording feature (automatic PoC demos)
- [ ] Multi-threaded concurrent scanning (speed up 10x)

## Success Stories (Inspiration)

- @samwcyo — PayPal OAuth bypass: **$30,250** (largest ever paid)
- @zlz — Shopify GraphQL IDOR: **$25,000**
- @spaceraccoon — Slack race condition: **$17,500**
- @inhibitor181 — Snapchat API abuse: **$15,000**
- @Rez0 — Twitter Ads Stored XSS: **$7,560**
- @streaak — Uber Rider API SQLi: **$10,000**

Common pattern:
- Start with simple stuff (automated scan finds Low/MED)
- Dig deeper manually (prove HIGH impact)
- Chain related bugs (Low+Low=High/Critical)
- Write professional report (clear English, reproducible)

## Conclusion

**Bug bounty isn't magic—it's engineering.** Tools help you discover faster, but **manual verification + creativity** = real $$$$.

Start with free programs, build reputation, then move to private invitations. Expect rejection early—every successful hunter has hundreds of N/A/Duplicate before hitting the big one.

You got this. 🚀

---

**Disclaimer:** This tool is for authorized bug bounty programs and ethical hacking ONLY. Users are responsible for compliance with program terms and applicable laws. Unauthorized scanning/testing is illegal.