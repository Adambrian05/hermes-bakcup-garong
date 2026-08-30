#!/usr/bin/env python3
"""
CamouFox + HTTP Proxy Scanner for lenoraconsulting.com
Testing different proxy formats
Fox Mode - Zero Limits
"""

import json
import sys
from camoufox.sync_api import Camoufox

# Proxy list: IP:PORT:USER:PASS
proxies = [
    "31.59.20.176:6754:gtqruvcn:udb13ioy9tdp",
    "31.56.127.193:7684:gtqruvcn:udb13ioy9tdp",
    "45.38.107.97:6014:gtqruvcn:udb13ioy9tdp",
]

target = 'https://www.lenoraconsulting.com/'

print(f'[*] Target: {target}')
print('='*60)

def try_proxy_http(proxy_str):
    """Try with HTTP proxy format"""
    parts = proxy_str.split(':')
    ip, port, user, pwd = parts[0], parts[1], parts[2], parts[3]
    
    # Try HTTP proxy
    proxy_url = f"http://{user}:{pwd}@{ip}:{port}"
    
    print(f'\n[*] Trying HTTP proxy: {ip}:{port}')
    
    try:
        with Camoufox(headless=True, proxy={"server": proxy_url}) as browser:
            page = browser.new_page()
            
            print(f'[*] Navigating to {target}...')
            response = page.goto(target, wait_until='domcontentloaded', timeout=30000)
            
            if response:
                print(f'[*] Status: {response.status}')
                if response.status == 200:
                    print(f'[*] Title: {page.title()}')
                    content = page.content()
                    print(f'[*] Content length: {len(content)} chars')
                    return True, content
                else:
                    print(f'[-] Non-200 status: {response.status}')
            else:
                print('[-] No response')
            
            browser.close()
            return False, None
            
    except Exception as e:
        print(f'[-] Error: {str(e)[:100]}')
        return False, None

def try_socks5(proxy_str):
    """Try with SOCKS5 proxy format"""
    parts = proxy_str.split(':')
    ip, port, user, pwd = parts[0], parts[1], parts[2], parts[3]
    
    proxy_url = f"socks5://{user}:{pwd}@{ip}:{port}"
    
    print(f'\n[*] Trying SOCKS5 proxy: {ip}:{port}')
    
    try:
        with Camoufox(headless=True, proxy={"server": proxy_url}) as browser:
            page = browser.new_page()
            
            print(f'[*] Navigating to {target}...')
            response = page.goto(target, wait_until='domcontentloaded', timeout=30000)
            
            if response:
                print(f'[*] Status: {response.status}')
                if response.status == 200:
                    print(f'[*] Title: {page.title()}')
                    content = page.content()
                    print(f'[*] Content length: {len(content)} chars')
                    return True, content
            else:
                print('[-] No response')
            
            browser.close()
            return False, None
            
    except Exception as e:
        print(f'[-] Error: {str(e)[:100]}')
        return False, None

# Try each proxy with both formats
success = False
for proxy in proxies:
    # Try HTTP first
    success, content = try_proxy_http(proxy)
    if success:
        break
    
    # Try SOCKS5
    success, content = try_socks5(proxy)
    if success:
        break

if success:
    print('\n' + '='*60)
    print('[+] SUCCESS! Connected via proxy')
    print('='*60)
else:
    print('\n' + '='*60)
    print('[-] All proxies failed')
    print('='*60)
