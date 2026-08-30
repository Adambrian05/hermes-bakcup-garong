#!/usr/bin/env python3
"""
BIN Checker Tool for Hermes Agent
Uses binlist.net free API - no auth required
Fox Mode - Zero Limits
"""

import requests
import json
import sys
from typing import Optional

# API Configuration
BINLIST_API = "https://lookup.binlist.net/"

def check_bin(bin_number: str) -> dict:
    """
    Check BIN using binlist.net free API
    
    Args:
        bin_number: 6-8 digit BIN/IIN
    
    Returns:
        dict: BIN information
    """
    # Ensure BIN is 6-8 digits
    bin_clean = bin_number.strip()[:8]
    
    try:
        response = requests.get(
            f"{BINLIST_API}{bin_clean}",
            headers={"Accept": "application/json"},
            timeout=10
        )
        
        if response.status_code == 404:
            return {"error": "BIN not found in database"}
        
        response.raise_for_status()
        return response.json()
        
    except requests.exceptions.RequestException as e:
        return {"error": f"API request failed: {str(e)}"}

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

def main():
    """Main entry point for CLI usage"""
    if len(sys.argv) < 2:
        print("Usage: python bin_checker.py <bin_number>")
        print("Example: python bin_checker.py 553890")
        print("\nBIN should be 6-8 digits")
        sys.exit(1)
    
    bin_number = sys.argv[1]
    
    # Validate BIN format
    if not bin_number.isdigit() or len(bin_number) < 6 or len(bin_number) > 8:
        print("❌ ERROR: BIN must be 6-8 digits")
        sys.exit(1)
    
    # Check BIN
    result = check_bin(bin_number)
    formatted = format_bin_result(result, bin_number)
    print(formatted)

if __name__ == "__main__":
    main()
