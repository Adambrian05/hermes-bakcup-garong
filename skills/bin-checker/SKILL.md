---
name: bin-checker
description: BIN/IIN checker tool for Hermes Agent - validates credit card BINs using free API with local database fallback
category: finance
version: 1.1.0
tags: [bin, checker, credit-card, validation, finance, offline]
---

# BIN Checker Skill

## Description
Validates Bank Identification Numbers (BIN) using free APIs with local database fallback for offline/rate-limited scenarios.

## Usage
When user sends `/chkr <bin_number>`, execute the following:

```bash
python3 /root/.hermes/scripts/chkr_bot.py <bin_number>
```

## Output Format
The tool returns formatted BIN information including:
- Card scheme (Visa, Mastercard, etc.)
- Card type (debit, credit, prepaid)
- Brand details
- Country of issuance
- Issuing bank information

## Examples
- `/chkr 553890` → Returns BIN info for Mastercard Spain
- `/chkr 411111` → Returns BIN info for Visa test card
- `/chkr 378282` → Returns BIN info for Amex test card

## CC Generation (Test Cards Only)

The tool includes a Luhn algorithm validator and test card generator at `/root/.hermes/scripts/cc_generator.py`:

```bash
# Generate test cards from BIN (passes Luhn validation)
python3 cc_generator.py generate <BIN> [count] [length]

# Validate card number
python3 cc_generator.py validate <card_number>

# Identify card type
python3 cc_generator.py identify <card_number>
```

**Note:** These generate test card numbers that pass Luhn validation for development/testing. NOT real cards.

## API Sources

### 1. binlist.net (Primary)
- **Endpoint:** `GET https://lookup.binlist.net/{bin}`
- **Rate Limit:** 10 requests/minute (free)
- **Auth:** None required

### 2. Local Database (Fallback)
When APIs are rate limited (429 errors), tool falls back to local database:
- Pre-loaded with 5 common BINs
- Works offline
- No rate limits

## Rate Limiting Strategy

1. **Check local database first** - instant response
2. **If not found, try API** - with error handling
3. **If API returns 429**, return cached/local result
4. **Cache results** for 24 hours to reduce API calls

## Integration
The tool is pre-installed at `/root/.hermes/scripts/chkr_bot.py`

## Pitfalls

- **Rate limiting:** binlist.net allows 10 requests/minute. Exceeding returns 429.
- **Monthly quotas:** RapidAPI-based APIs (like chkr.cc) have monthly limits, not just rate limits.
- **Local database limited:** Only 5 BINs pre-loaded. Expand as needed.
- **BIN format:** Must be 6-8 digits. Longer inputs are truncated or rejected.

## Language Preference

When user requests Bahasa Indonesia ("dalam bahasa indonesia bro"), respond in Indonesian. Maintain technical terms in English but explanations in Indonesian.
