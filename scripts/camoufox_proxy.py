#!/usr/bin/env python3
"""
CamouFox + Proxy Scanner for lenoraconsulting.com
Anti-detection browser with proxy rotation
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
    "198.105.121.200:6462:gtqruvcn:udb13ioy9tdp",
    "64.137.96.74:6641:gtqruvcn:udb13ioy9tdp",
    "198.23.243.226:6361:gtqruvcn:udb13ioy9tdp",
    "38.154.185.97:6370:gtqruvcn:udb13ioy9tdp",
    "84.247.60.125:6095:gtqruvcn:udb13ioy9tdp",
    "142.111.67.146:5611:gtqruvcn:udb13ioy9tdp",
    "191.96.254.138:6185:gtqruvcn:udb13ioy9tdp",
]

target = 'https://www.lenoraconsulting.com/'

print(f'[*] Target: {target}')
print(f'[*] Proxies available: {len(proxies)}')
print('='*60)

def try_proxy(proxy_str):
    """Try accessing target with a specific proxy"""
    parts = proxy_str.split(':')
    ip, port, user, pwd = parts[0], parts[1], parts[2], parts[3]
    
    proxy_url = f"socks5://{user}:{pwd}@{ip}:{port}"
    
    print(f'\n[*] Trying proxy: {ip}:{port}')
    
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

# Try each proxy
success = False
for proxy in proxies:
    success, content = try_proxy(proxy)
    if success:
        print('\n' + '='*60)
        print('[+] SUCCESS! Connected via proxy')
        print('='*60)
        
        # Analyze the page
        print('\n=== PAGE ANALYSIS ===')
        
        # Extract links
        links = []
        try:
            with Camoufox(headless=True, proxy={"server": f"socks5://{proxy.split(':')[2]}:{proxy.split(':')[3]}@{proxy.split(':')[0]}:{proxy.split(':')[1]}"}) as browser:
                page = browser.new_page()
                page.goto(target, wait_until='domcontentloaded', timeout=30000)
                
                links = page.eval_on_selector_all('a[href]', 'els => els.map(e => ({text: e.textContent.trim(), href: e.href}))')
                print(f'\nLinks found: {len(links)}')
                for i, link in enumerate(links[:20]):
                    text = link.get('text', '')[:50]
                    href = link.get('href', '')
                    if text or href:
                        print(f'  {i+1}. {text}: {href}')
                
                # Check for file manager
                print('\n=== FILE MANAGER CHECK ===')
                keywords = ['file', 'manager', 'upload', 'directory', 'folder', 'admin', 'panel', 'dashboard']
                for keyword in keywords:
                    elements = page.query_selector_all(f'[id*="{keyword}" i], [class*="{keyword}" i]')
                    if elements:
                        print(f'  [FOUND] {keyword}: {len(elements)} elements')
                
                browser.close()
        except Exception as e:
            print(f'[-] Analysis error: {e}')
        
        break

if not success:
    print('\n' + '='*60)
    print('[-] All proxies failed or timed out')
    print('='*60)
