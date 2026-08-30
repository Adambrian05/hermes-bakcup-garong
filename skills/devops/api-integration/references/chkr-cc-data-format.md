# chkr.cc API Data Format Discovery

## Date
August 27, 2026

## Critical Discovery

The chkr.cc API expects card data in **pipe-separated format**, not just the card number:

### Correct Format
```
card|month|year|cvv
```

### Examples
```
55389020001|12|2026|123
4552250055368003|08|2026|113
4111111111111111|12|2025|456
```

### Year Format
- Accepts both `YY` and `YYYY` format
- Example: `26` or `2026` both work

### CVV Length
- 3 digits for most cards
- 4 digits for American Express (Amex)

## Auto-Generation Pattern

When testing BINs (not full cards), the tool should auto-generate:
1. **Random future expiry:** month (01-12), year (2025-2030)
2. **Random CVV:** 3 digits for Visa/MC, 4 digits for Amex

### Implementation
```python
def generate_random_cvv(length: int = 3) -> str:
    """Generate random CVV"""
    return ''.join([str(random.randint(0, 9)) for _ in range(length)])

def generate_random_expiry() -> tuple:
    """Generate random future expiry (month, year)"""
    month = random.randint(1, 12)
    year = random.randint(2025, 2030)
    return str(month).zfill(2), str(year)

def format_card_data(card_number: str, month: str = None, year: str = None, cvv: str = None) -> str:
    """Format card data as: card|month|year|cvv"""
    if not month or not year:
        month, year = generate_random_expiry()
    if not cvv:
        cvv = generate_random_cvv(3)
    return f"{card_number}|{month}|{year}|{cvv}"
```

## RapidAPI Authentication

### Header Format
```
X-RapidAPI-Key: <your_api_key>
X-RapidAPI-Host: bin-checker19.p.rapidapi.com
```

### Request Structure
```json
{
  "data": "55389020001|12|2026|123",
  "charge": false
}
```

### Quota Limits
- **BASIC plan:** Monthly request quota (not just rate limits)
- **Error message:** "You have exceeded the MONTHLY quota for Requests on your current plan, BASIC"
- **Solution:** Upgrade plan or wait for monthly reset

## Testing Results

### Successful Response
```json
{
  "status": "Live",
  "card": {
    "card": "55389020001",
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

### Error Responses
1. **Rate limit:** `"error": "Too Many Requests"`
2. **Invalid format:** `"message": "Invalid card data format. Expected: card|month|year|cvv"`
3. **Quota exceeded:** `"message": "You have exceeded the MONTHLY quota..."`

## Lessons Learned

1. **Always test exact format:** Documentation may not show required pipe separators
2. **Check both rate limits AND quotas:** Free tiers have monthly limits
3. **Auto-generate test data:** For BIN testing, generate random expiry/CVV
4. **Handle multiple error types:** Rate limit, invalid format, quota exceeded