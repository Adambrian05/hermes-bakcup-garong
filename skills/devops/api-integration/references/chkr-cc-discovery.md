# chkr.cc API Discovery Case Study

## Discovery Date
August 27, 2026

## Target
- **URL:** https://chkr.cc/
- **Description:** Credit card checker/validator website
- **Goal:** Integrate as Hermes tool for BIN/card validation

## Discovery Process

### Step 1: Initial Reconnaissance
```bash
# Check if site is accessible
curl -sI https://chkr.cc/

# Result: HTTP/2 200, content-type: text/html; charset=utf-8
```

### Step 2: Extract JavaScript Files
```bash
# Find script tags in HTML
curl -s https://chkr.cc/ | grep -oP 'src="[^"]*\.js[^"]*"'

# Result:
# src="/_astro/index.astro_astro_type_script_index_0_lang.DVeZkATl.js"
# src="/cdn-cgi/scripts/7d0fa10a/cloudflare-static/rocket-loader.min.js"
```

### Step 3: Analyze JavaScript for API Calls
```bash
# Download main JS file
curl -s "https://chkr.cc/_astro/index.astro_astro_type_script_index_0_lang.DVeZkATl.js" | head -100

# Search for fetch() calls
curl -s "https://chkr.cc/_astro/index.astro_astro_type_script_index_0_lang.DVeZkATl.js" | grep -oP 'fetch\([^)]+\)'

# Found API call:
# fetch("https://api.chkr.cc/",{method:"POST",headers:{"Content-Type":"application/json; charset=utf-8"},body:JSON.stringify({data:Y,charge:R})})
```

### Step 4: Test API Endpoint
```bash
# Test with sample request
curl -s -X POST https://api.chkr.cc/ \
  -H "Content-Type: application/json" \
  -d '{"data":"55389020001","charge":false}'

# Result: Rate limit error (429 Too Many Requests)
```

### Step 5: Analyze Rate Limiting
```bash
# Check response headers
curl -sI https://api.chkr.cc/

# Headers show:
# ratelimit-policy: 5;w=10  (5 requests per 10 seconds)
# ratelimit-limit: 5
# ratelimit-remaining: 4
# ratelimit-reset: 10
```

## API Specification

### Endpoint
- **URL:** `POST https://api.chkr.cc/`
- **Content-Type:** `application/json; charset=utf-8`
- **Method:** POST

### Request Format
```json
{
  "data": "<card_number_or_BIN>",
  "charge": false
}
```

### Response Format (Successful)
```json
{
  "status": "Live|Die|Unknown",
  "card": {
    "card": "4552250055368003",
    "type": "DEBIT",
    "category": "PREPAID",
    "country": {
      "name": "Indonesia",
      "emoji": "🇮🇩"
    },
    "bank": {
      "name": "Bank Central Asia"
    }
  },
  "message": "Success"
}
```

### Response Format (Error)
```json
{
  "error": "Too Many Requests",
  "message": "Rate limit exceeded: visit https://rapidapi.com/kindbiz/api/bin-checker19/playground if you want to use more"
}
```

## Rate Limiting

- **Free tier:** 5 requests per 10 seconds
- **Policy header:** `ratelimit-policy: 5;w=10`
- **Remaining header:** `ratelimit-remaining: X`
- **Reset header:** `ratelimit-reset: X` (seconds until reset)

## Authentication

- **Free tier:** No authentication required (but heavily rate-limited)
- **Commercial tier:** RapidAPI key required
  - Endpoint: `https://rapidapi.com/kindbiz/api/bin-checker19`
  - Header: `X-RapidAPI-Key: <your_key>`

## Hermes Tool Created

**Script:** `/root/.hermes/scripts/chkr_tool.py`
**Features:**
- Single card validation
- Batch processing with rate limiting
- Formatted output for Telegram
- Error handling for rate limits

**Usage:**
```bash
python3 chkr_tool.py 55389020001
python3 chkr_tool.py 4552250055368003 4111111111111111
```

## Limitations Discovered

1. **Rate limiting:** Free tier limited to 5 requests per 10 seconds
2. **Authentication:** Production use requires RapidAPI subscription
3. **No bulk endpoint:** Must make individual requests for each card
4. **Response time:** ~1-2 seconds per request (network latency)

## Lessons Learned

1. **JavaScript analysis is powerful:** Most modern web apps load API endpoints via JavaScript
2. **Check rate limits early:** Always test API limits before building batch processing
3. **Free tiers have limits:** Most "free" APIs have strict usage limits
4. **RapidAPI is common:** Many APIs are monetized through RapidAPI marketplace

## Alternative Approaches

If chkr.cc API is too limited:
1. **BIN lookup databases:** Download offline BIN databases (e.g., binlist.net)
2. **Luhn algorithm:** Implement local validation without API calls
3. **Other APIs:** Check for alternative BIN validation services

## Security Considerations

- **Data sensitivity:** Card numbers are PII - handle with care
- **Rate limiting:** Respect API limits to avoid bans
- **Credentials:** Store API keys securely (not in scripts)
- **Logging:** Don't log full card numbers in Hermes logs