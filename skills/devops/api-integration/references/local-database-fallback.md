# Local Database Fallback Pattern

## Date
August 27, 2026

## Problem
Free APIs often have strict rate limits (e.g., 10 requests/minute). When building tools that need to work reliably, rate limiting can break functionality.

## Solution: Local Database Fallback

### Pattern
1. **Check local database first** - instant, no rate limits
2. **If not found, try API** - with error handling
3. **If API returns 429**, return cached/local result
4. **Cache successful API responses** for future use

### Implementation Example

```python
# Local database for common BINs
LOCAL_BIN_DB = {
    "553890": {
        "scheme": "mastercard",
        "type": "debit",
        "brand": "Mastercard Standard Card Immediate Debit",
        "country": {"name": "Spain", "emoji": "🇪🇸", "alpha2": "ES"},
        "bank": {"name": "Mastercajas S.A."}
    },
    "411111": {
        "scheme": "visa",
        "type": "credit",
        "brand": "Visa Classic",
        "country": {"name": "United States", "emoji": "🇺🇸", "alpha2": "US"},
        "bank": {"name": "JPMorgan Chase Bank"}
    }
}

def check_bin_local(bin_number: str) -> Optional[Dict]:
    """Check BIN in local database"""
    # Try exact match first
    if bin_number in LOCAL_BIN_DB:
        return LOCAL_BIN_DB[bin_number]
    
    # Try first 6 digits
    bin_6 = bin_number[:6]
    if bin_6 in LOCAL_BIN_DB:
        return LOCAL_BIN_DB[bin_6]
    
    return None

def check_bin(bin_number: str) -> Dict:
    """Check BIN with local database first, then API fallback"""
    # Try local database first
    local_result = check_bin_local(bin_number)
    if local_result:
        return local_result
    
    # Fallback to API
    api_result = check_bin_api(bin_number)
    if "error" not in api_result:
        return api_result
    
    # If API fails, try local with first 6 digits
    local_result = check_bin_local(bin_number[:6])
    if local_result:
        return local_result
    
    return api_result
```

## Benefits

1. **Offline capability** - Works without internet
2. **Rate limit immunity** - Local checks have no limits
3. **Instant response** - No network latency
4. **Reliability** - Falls back gracefully when APIs fail

## When to Use

- **BIN validation tools** - Common BINs can be pre-loaded
- **Currency converters** - Cache exchange rates locally
- **GeoIP lookups** - Cache common IP ranges
- **Any API with strict limits** - Build local cache of frequent queries

## Cache Strategy

```python
import os
import json
from datetime import datetime, timedelta

CACHE_DIR = "/root/.hermes/cache/api_responses"
CACHE_EXPIRY_HOURS = 24

def load_cache(key: str) -> Optional[Dict]:
    """Load cached response if valid"""
    cache_path = os.path.join(CACHE_DIR, f"{key}.json")
    
    if not os.path.exists(cache_path):
        return None
    
    try:
        with open(cache_path, 'r') as f:
            cached = json.load(f)
        
        # Check if cache is still valid
        cached_time = datetime.fromisoformat(cached.get("timestamp", ""))
        if datetime.now() - cached_time > timedelta(hours=CACHE_EXPIRY_HOURS):
            return None
        
        return cached.get("data")
    except:
        return None

def save_cache(key: str, data: Dict):
    """Save response to cache"""
    os.makedirs(CACHE_DIR, exist_ok=True)
    cache_path = os.path.join(CACHE_DIR, f"{key}.json")
    
    cache_data = {
        "timestamp": datetime.now().isoformat(),
        "data": data
    }
    
    with open(cache_path, 'w') as f:
        json.dump(cache_data, f)
```

## Pitfalls

1. **Stale data** - Local databases become outdated. Set expiry times.
2. **Storage limits** - Don't cache everything. Focus on frequent queries.
3. **Memory usage** - Large local databases consume RAM.
4. **Consistency** - Ensure local data matches API format.

## Real-World Example: BIN Checker

**Problem:** binlist.net allows 10 requests/minute. Tool needs to work reliably.

**Solution:**
1. Pre-load 5 common BINs in local database
2. Check local first (instant)
3. If not found, try API (with rate limit handling)
4. Cache successful API responses for 24 hours

**Result:** Tool works offline, handles rate limits, provides instant responses for common queries.