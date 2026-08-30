#!/usr/bin/env python3
"""
Credit Card Generator & Validator
Luhn Algorithm Implementation
For testing purposes only
"""

import sys
import random
from typing import List, Tuple


def luhn_check(card_number: str) -> bool:
    """Validate card number using Luhn algorithm"""
    digits = [int(d) for d in card_number]
    odd_digits = digits[-1::-2]
    even_digits = digits[-2::-2]
    
    checksum = sum(odd_digits)
    for d in even_digits:
        checksum += sum(divmod(d * 2, 10))
    
    return checksum % 10 == 0


def generate_check_digit(partial: str) -> int:
    """Generate check digit for partial card number"""
    for digit in range(10):
        if luhn_check(partial + str(digit)):
            return digit
    return 0


def generate_card_number(bin_number: str, length: int = 16) -> str:
    """Generate valid card number from BIN"""
    # Ensure BIN is the right length
    bin_len = len(bin_number)
    remaining = length - bin_len - 1  # -1 for check digit
    
    if remaining < 0:
        raise ValueError(f"BIN too long for {length}-digit card")
    
    # Generate random digits
    partial = bin_number + ''.join([str(random.randint(0, 9)) for _ in range(remaining)])
    
    # Calculate check digit
    check_digit = generate_check_digit(partial)
    
    return partial + str(check_digit)


def generate_test_cards(bin_number: str, count: int = 5, length: int = 16) -> List[str]:
    """Generate multiple test card numbers"""
    cards = []
    for _ in range(count):
        card = generate_card_number(bin_number, length)
        if luhn_check(card):
            cards.append(card)
    return cards


def identify_card_type(card_number: str) -> str:
    """Identify card type from number"""
    patterns = {
        'Visa': r'^4[0-9]{12}(?:[0-9]{3})?$',
        'Mastercard': r'^5[1-5][0-9]{14}$|^2(?:2[2-9][1-9]|2[3-9][0-9]{2}|[3-6][0-9]{3}|7[01][0-9]{2}|720)[0-9]{12}$',
        'American Express': r'^3[47][0-9]{13}$',
        'Discover': r'^6(?:011|5[0-9]{2})[0-9]{12}$',
        'Diners Club': r'^3(?:0[0-5]|[68][0-9])[0-9]{11}$',
        'JCB': r'^(?:2131|1800|35\d{3})\d{11}$',
    }
    
    import re
    for card_type, pattern in patterns.items():
        if re.match(pattern, card_number):
            return card_type
    
    return 'Unknown'


def main():
    if len(sys.argv) < 2:
        print("Usage:")
        print("  Validate:  python3 cc_generator.py validate <card_number>")
        print("  Generate:  python3 cc_generator.py generate <bin> [count] [length]")
        print("  Identify:  python3 cc_generator.py identify <card_number>")
        print("\nExamples:")
        print("  python3 cc_generator.py validate 4111111111111111")
        print("  python3 cc_generator.py generate 377481018 5 15")
        print("  python3 cc_generator.py identify 4111111111111111")
        sys.exit(1)
    
    command = sys.argv[1].lower()
    
    if command == 'validate':
        if len(sys.argv) < 3:
            print("Error: Provide card number to validate")
            sys.exit(1)
        
        card_number = sys.argv[2]
        is_valid = luhn_check(card_number)
        card_type = identify_card_type(card_number)
        
        print(f"Card Number: {card_number}")
        print(f"Card Type:   {card_type}")
        print(f"Valid:       {'✅ YES' if is_valid else '❌ NO'}")
        
    elif command == 'generate':
        if len(sys.argv) < 3:
            print("Error: Provide BIN number")
            sys.exit(1)
        
        bin_number = sys.argv[2]
        count = int(sys.argv[3]) if len(sys.argv) > 3 else 5
        length = int(sys.argv[4]) if len(sys.argv) > 4 else 16
        
        print(f"Generating {count} cards from BIN: {bin_number}")
        print(f"Card length: {length} digits\n")
        
        cards = generate_test_cards(bin_number, count, length)
        for i, card in enumerate(cards, 1):
            card_type = identify_card_type(card)
            print(f"{i}. {card} ({card_type})")
        
    elif command == 'identify':
        if len(sys.argv) < 3:
            print("Error: Provide card number to identify")
            sys.exit(1)
        
        card_number = sys.argv[2]
        card_type = identify_card_type(card_number)
        is_valid = luhn_check(card_number)
        
        print(f"Card Number: {card_number}")
        print(f"Card Type:   {card_type}")
        print(f"Luhn Valid:  {'✅ YES' if is_valid else '❌ NO'}")
        
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == '__main__':
    main()