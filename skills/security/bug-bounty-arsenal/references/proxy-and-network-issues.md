# Proxy Authentication Issues — Common Pitfalls

## 407 Proxy Authentication Required

**Symptom:** `407 Proxy Authentication Required` with message "Invalid proxy credentials or missing IP Authorization"

**Root Causes:**
1. **Wrong credentials** — username/password mismatch
2. **IP not authorized** — server IP not whitelisted in proxy provider dashboard
3. **Wrong protocol** — proxy expects SOCKS5 but using HTTP, or vice versa

**Debug Steps:**
```bash
# Test if proxy port is open
timeout 5 bash -c "echo > /dev/tcp/IP/PORT" && echo "OPEN" || echo "CLOSED"

# Test with curl (HTTP proxy)
curl -v -x http://user:pass@ip:port --connect-timeout 10 https://httpbin.org/ip

# Test with curl (SOCKS5 proxy)
curl -v --socks5 user:pass@ip:port --connect-timeout 10 https://httpbin.org/ip
```

**Common Proxy Formats:**
- HTTP: `http://user:pass@ip:port`
- SOCKS5: `socks5://user:pass@ip:port`
- Bare: `ip:port` (no auth)

**Fix:**
1. Verify credentials in proxy provider dashboard
2. Add server IP to whitelist (if required)
3. Try different protocol (HTTP vs SOCKS5)

---

## GitHub Repository Installation Pattern

When installing security tools from GitHub:

```bash
# 1. Clone repository
git clone https://github.com/user/repo.git
cd repo

# 2. Check requirements
cat README.md | head -50

# 3. Install dependencies
# For Python projects:
pip3 install -e .

# For TypeScript/Node.js projects:
npm install

# 4. Fix build issues (if any)
# Common TypeScript fixes:
# - Add "ignoreDeprecations": "5.0" to tsconfig.json
# - Change target from es5 to es6
# - Add "lib": ["es2016"] for Array.includes support
# - Add "rootDir": "./src"

# 5. Verify installation
python3 -c "import module_name; print('OK')"
# or
node -e "const m = require('./lib'); console.log(m)"
```

**Pitfalls:**
- Python projects may install to system Python, not Hermes venv
- TypeScript projects may have deprecated compiler options
- Some repos require specific Node.js versions

**Symptom:** Connection timeout, 100% packet loss, HTTP 000

**Root Cause:** WAF/Firewall blocking server IP range

**Workaround:**
1. Use proxy with different IP
2. Use Camoufox (anti-detection browser)
3. Run from local machine instead of server

**Test:**
```bash
# Check if port is open
nc -zv IP 443

# Check DNS resolution
nslookup target.com

# Check HTTP response
curl -sI --connect-timeout 10 https://target.com
```

---

## Camoufox Dependencies (Headless Linux)

**Symptom:** `libgtk-3.so.0: cannot open shared object file` or `libasound.so.2: cannot open shared object file`

**Fix:**
```bash
apt-get install -y libgtk-3-0 libasound2 libasound2t64
```

---

## RAR Archive Extraction

**Symptom:** `unzip: cannot find zipfile directory` for .rar files

**Fix:**
```bash
apt-get install -y unrar
unrar x archive.rar /destination/
```

---

## Google Drive Downloads

**Tool:** `gdown` for downloading from Google Drive

```bash
pip3 install gdown

# Download by file ID
gdown "https://drive.google.com/uc?id=FILE_ID" -O output.zip

# Or with Python
python3 -c "
import gdown
gdown.download('https://drive.google.com/uc?id=FILE_ID', 'output.zip')
"
```

---

## BIN Lookup APIs (Rate Limited)

**Free APIs:**
- `https://lookup.binlist.net/{BIN}` — 10 requests/minute
- No auth required

**Rate Limit Handling:**
- Add delays between requests (6+ seconds)
- Use local database fallback for common BINs
- Cache results to avoid repeated lookups
