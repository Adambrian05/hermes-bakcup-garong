#!/usr/bin/env python3
"""
BIN Checker Tool for Hermes Agent
Local database + API fallback
Fox Mode - Zero Limits
"""

import requests
import json
import sys
import os
from typing import Optional, Dict

# Local BIN Database (common BINs)
LOCAL_BIN_DB = {
    "553890": {
        "scheme": "mastercard",
        "type": "debit",
        "brand": "Mastercard Standard Card Immediate Debit",
        "country": {
            "name": "Spain",
            "emoji": "🇪🇸",
            "alpha2": "ES",
            "currency": "EUR"
        },
        "bank": {
            "name": "Mastercajas S.A."
        }
    },
    "411111": {
        "scheme": "visa",
        "type": "credit",
        "brand": "Visa Classic",
        "country": {
            "name": "United States",
            "emoji": "🇺🇸",
            "alpha2": "US",
            "currency": "USD"
        },
        "bank": {
            "name": "JPMorgan Chase Bank"
        }
    },
    "378282": {
        "scheme": "americanexpress",
        "type": "credit",
        "brand": "American Express Green Card",
        "country": {
            "name": "United States",
            "emoji": "🇺🇸",
            "alpha2": "US",
            "currency": "USD"
        },
        "bank": {
            "name": "American Express Travel Related Services"
        }
    },
    "555555": {
        "scheme": "mastercard",
        "type": "credit",
        "brand": "Mastercard World Elite",
        "country": {
            "name": "United States",
            "emoji": "🇺🇸",
            "alpha2": "US",
            "currency": "USD"
        },
        "bank": {
            "name": "Citibank"
        }
    },
    "422222": {
        "scheme": "visa",
        "type": "credit",
        "brand": "Visa Signature",
        "country": {
            "name": "United States",
            "emoji": "🇺🇸",
            "alpha2": "US",
            "currency": "USD"
        },
        "bank": {
            "name": "Bank of America"
        }
    }
}

# API Configuration (fallback)
BINLIST_API = "https://lookup.binlist.net/"

def check_bin_local(bin_number: str) -> Optional[Dict]:
    """
    Check BIN in local database
    
    Args:
        bin_number: 6-8 digit BIN
    
    Returns:
        dict: BIN information or None if not found
    """
    # Try exact match first
    if bin_number in LOCAL_BIN_DB:
        return LOCAL_BIN_DB[bin_number]
    
    # Try first 6 digits
    bin_6 = bin_number[:6]
    if bin_6 in LOCAL_BIN_DB:
        return LOCAL_BIN_DB[bin_6]
    
    return None

def check_bin_api(bin_number: str) -> Dict:
    """
    Check BIN using binlist.net API
    
    Args:
        bin_number: 6-8 digit BIN
    
    Returns:
        dict: API response
    """
    try:
        response = requests.get(
            f"{BINLIST_API}{bin_number[:6]}",
            headers={"Accept": "application/json"},
            timeout=10
        )
        
        if response.status_code == 404:
            return {"error": "BIN not found"}
        
        if response.status_code == 429:
            return {"error": "Rate limited - using local database"}
        
        response.raise_for_status()
        return response.json()
        
    except requests.exceptions.RequestException as e:
        return {"error": f"API error: {str(e)}"}

def check_bin(bin_number: str) -> Dict:
    """
    Check BIN with local database first, then API fallback
    
    Args:
        bin_number: 6-8 digit BIN
    
    Returns:
        dict: BIN information
    """
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

def format_bin_result(data: dict, bin_input: str) -> str:
    """
    Format BIN result for Telegram display
    
    Args:
        data: API response dict
        bin_input: Original BIN input
    
    Returns:
        str: Formatted result string
    """
    if "error" in data:
        return f"❌ ERROR: {data['error']}"
    
    # Extract fields
    scheme = data.get("scheme", "Unknown")
    card_type = data.get("type", "Unknown")
    brand = data.get("brand", "Unknown")
    prepaid = data.get("prepaid", "Unknown")
    
    country = data.get("country", {})
    country_name = country.get("name", "Unknown")
    country_emoji = country.get("emoji", "🌍")
    country_code = country.get("alpha2", "??")
    currency = country.get("currency", "Unknown")
    
    bank = data.get("bank", {})
    bank_name = bank.get("name", "Unknown")
    bank_url = bank.get("url", "")
    bank_phone = bank.get("phone", "")
    
    # Format output
    result = f"""
🔍 **BIN CHECK RESULT**

💳 **BIN:** `{bin_input}`
🏷️ **SCHEME:** {scheme.upper()}
📦 **TYPE:** {card_type}
🎨 **BRAND:** {brand}
💰 **PREPAID:** {prepaid}

🌍 **COUNTRY:** {country_emoji} {country_name} ({country_code})
💵 **CURRENCY:** {currency}

🏦 **BANK:** {bank_name}
🌐 **BANK URL:** {bank_url if bank_url else "N/A"}
📞 **BANK PHONE:** {bank_phone if bank_phone else "N/A"}
"""
    
    return result.strip()

def handle_chkr_command(args: list) -> str:
    """
    Handle /chkr command
    
    Args:
        args: Command arguments [bin_number]
    
    Returns:
        str: Formatted response
    """
    if not args:
        return """
🔍 **BIN CHECKER COMMAND**

**Usage:** `/chkr <bin_number>`

**Examples:**
- `/chkr 553890`
- `/chkr 411111`
- `/chkr 378282`

BIN should be 6-8 digits
"""
    
    bin_number = args[0]
    
    # Validate BIN format
    if not bin_number.isdigit() or len(bin_number) < 6 or len(bin_number) > 8:
        return "❌ ERROR: BIN must be 6-8 digits"
    
    # Check BIN
    result = check_bin(bin_number)
    return format_bin_result(result, bin_number)

if __name__ == "__main__":
    # Test mode
    if len(sys.argv) > 1:
        response = handle_chkr_command(sys.argv[1:])
        print(response)
    else:
        print("Usage: python chkr_bot.py <bin_number>")
