#!/usr/bin/env python3
"""
chkr.cc API Tool for Hermes Agent
BIN/Card Validation Tool - Fox Mode
Integrated with RapidAPI authentication
"""

import requests
import json
import sys
import time
import random
from typing import Optional

# API Configuration
API_HOST = "bin-checker19.p.rapidapi.com"
API_URL = f"https://{API_HOST}/"
API_KEY = "71a3a53610msh01bcbb814299473p1e64f7jsnfa4ef8ae018a"
API_HEADERS = {
    "X-RapidAPI-Key": API_KEY,
    "X-RapidAPI-Host": API_HOST,
    "Content-Type": "application/json",
    "Accept": "application/json"
}

RATE_LIMIT_DELAY = 2.5  # Delay between requests (seconds)

def generate_random_cvv(length: int = 3) -> str:
    """Generate random CVV"""
    return ''.join([str(random.randint(0, 9)) for _ in range(length)])

def generate_random_expiry() -> tuple:
    """Generate random future expiry (month, year)"""
    month = random.randint(1, 12)
    year = random.randint(2025, 2030)
    return str(month).zfill(2), str(year)

def format_card_data(card_number: str, month: str = None, year: str = None, cvv: str = None) -> str:
    """
    Format card data as: card|month|year|cvv
    
    Args:
        card_number: Card number or BIN
        month: Expiry month (MM)
        year: Expiry year (YYYY)
        cvv: CVV code
    
    Returns:
        str: Formatted card data
    """
    # Auto-generate missing fields
    if not month or not year:
        month, year = generate_random_expiry()
    if not cvv:
        cvv = generate_random_cvv(3)
    
    return f"{card_number}|{month}|{year}|{cvv}"

def validate_card(card_data: str, charge: bool = False) -> dict:
    """
    Validate a credit card via chkr.cc API
    
    Args:
        card_data: Card data in format card|month|year|cvv
        charge: Whether to simulate charge (False = validation only)
    
    Returns:
        dict: API response with validation results
    """
    payload = {
        "data": card_data,
        "charge": charge
    }
    
    try:
        response = requests.post(
            API_URL,
            headers=API_HEADERS,
            json=payload,
            timeout=15
        )
        
        if response.status_code == 429:
            return {
                "status": "error",
                "message": "Rate limit exceeded. Wait 10 seconds.",
                "code": -1
            }
        
        response.raise_for_status()
        return response.json()
        
    except requests.exceptions.RequestException as e:
        return {
            "status": "error",
            "message": f"API request failed: {str(e)}",
            "code": -2
        }

def format_result(data: dict, card_input: str) -> str:
    """
    Format API result for Telegram display
    
    Args:
        data: API response dict
        card_input: Original card/BIN input
    
    Returns:
        str: Formatted result string
    """
    if data.get("status") == "error":
        return f"❌ ERROR: {data.get('message', 'Unknown error')}"
    
    status = data.get("status", "Unknown")
    card = data.get("card", {})
    message = data.get("message", "No message")
    
    # Status emoji
    if status == "Live":
        status_emoji = "✅"
    elif status == "Die":
        status_emoji = "❌"
    else:
        status_emoji = "⚠️"
    
    # Card details
    card_number = card.get("card", card_input)
    card_type = card.get("type", "Unknown")
    card_category = card.get("category", "Unknown")
    country = card.get("country", {})
    country_name = country.get("name", "Unknown")
    country_emoji = country.get("emoji", "🌍")
    bank = card.get("bank", {})
    bank_name = bank.get("name", "Unknown")
    
    # Format output
    result = f"""
{status_emoji} **STATUS:** {status}
💳 **CARD:** `{card_number}`
🏷️ **TYPE:** {card_type}
📦 **CATEGORY:** {card_category}
🌍 **COUNTRY:** {country_emoji} {country_name}
🏦 **BANK:** {bank_name}
💬 **MESSAGE:** {message}
"""
    
    return result.strip()

def process_batch(cards: list, delay: float = RATE_LIMIT_DELAY) -> list:
    """
    Process multiple cards with rate limiting
    
    Args:
        cards: List of card numbers/BINs
        delay: Delay between requests (seconds)
    
    Returns:
        list: List of (card, result) tuples
    """
    results = []
    
    for i, card in enumerate(cards):
        if i > 0:
            time.sleep(delay)
        
        # Auto-format card data if needed
        if "|" not in card:
            card = format_card_data(card)
        
        result = validate_card(card)
        formatted = format_result(result, card)
        results.append((card, formatted))
    
    return results

def main():
    """Main entry point for CLI usage"""
    if len(sys.argv) < 2:
        print("Usage: python chkr_tool.py <card_or_bin> [card2] [card3] ...")
        print("Examples:")
        print("  python chkr_tool.py 55389020001")
        print("  python chkr_tool.py 4552250055368003|12|2026|123")
        print("  python chkr_tool.py 55389020001 4111111111111111")
        sys.exit(1)
    
    cards = sys.argv[1:]
    
    if len(cards) == 1:
        # Single card - immediate response
        card = cards[0]
        if "|" not in card:
            card = format_card_data(card)
        result = validate_card(card)
        formatted = format_result(result, card)
        print(formatted)
    else:
        # Multiple cards - with rate limiting
        print(f"🔍 Processing {len(cards)} cards...\n")
        results = process_batch(cards)
        
        for card, formatted in results:
            print(formatted)
            print("-" * 40)

if __name__ == "__main__":
    main()
