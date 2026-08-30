#!/usr/bin/env python3
"""
Passive Web Recon for lenoraconsulting.com
Fox Mode - Zero Limits
"""

import requests
import json
import sys

target = 'https://www.lenoraconsulting.com/'
headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
}

print(f'[*] Target: {target}')
print('='*60)

# Test 1: Basic Headers
print('\n=== HEADERS ===')
try:
    r = requests.get(target, headers=headers, timeout=15, allow_redirects=True)
    print(f'  Status: {r.status_code}')
    print(f'  Server: {r.headers.get("Server", "Not disclosed")}')
    print(f'  X-Powered-By: {r.headers.get("X-Powered-By", "Not disclosed")}')
    
    # Security headers
    security_headers = ['Strict-Transport-Security', 'Content-Security-Policy', 
                       'X-Frame-Options', 'X-Content-Type-Options', 'X-XSS-Protection']
    for h in security_headers:
        val = r.headers.get(h)
        if val:
            print(f'  {h}: {val}')
        else:
            print(f'  {h}: [MISSING]')
except Exception as e:
    print(f'  Error: {e}')

# Test 2: Exposed files
print('\n=== EXPOSED FILES ===')
exposed_paths = ['/.git/HEAD', '/.env', '/robots.txt', '/sitemap.xml', 
                '/.htaccess', '/wp-config.php', '/.git/config']
for path in exposed_paths:
    try:
        r = requests.get(target + path, headers=headers, timeout=10)
        if r.status_code == 200 and len(r.text) > 0:
            print(f'  [FOUND] {path} ({len(r.text)} bytes)')
        else:
            print(f'  [NOT FOUND] {path}')
    except:
        print(f'  [ERROR] {path}')

# Test 3: CORS
print('\n=== CORS ===')
try:
    r = requests.get(target, headers={**headers, 'Origin': 'https://evil.com'}, timeout=10)
    acao = r.headers.get('Access-Control-Allow-Origin')
    if acao:
        print(f'  Access-Control-Allow-Origin: {acao}')
        if acao == '*':
            print('  [WARNING] Wildcard CORS - allows any origin')
        elif acao == 'https://evil.com':
            print('  [WARNING] Origin reflected - CORS misconfiguration')
    else:
        print('  No CORS headers')
except Exception as e:
    print(f'  Error: {e}')

# Test 4: HTTP Methods
print('\n=== HTTP METHODS ===')
for method in ['OPTIONS', 'TRACE', 'PUT', 'DELETE']:
    try:
        r = requests.request(method, target, headers=headers, timeout=10)
        print(f'  {method}: {r.status_code}')
    except:
        print(f'  {method}: Error')

# Test 5: Admin paths
print('\n=== ADMIN PATHS ===')
admin_paths = ['/admin', '/wp-admin', '/administrator', '/phpmyadmin', 
              '/cpanel', '/webmail', '/console']
for path in admin_paths:
    try:
        r = requests.get(target + path, headers=headers, timeout=10, allow_redirects=False)
        if r.status_code in [200, 301, 302, 403]:
            print(f'  [POSSIBLE] {path} ({r.status_code})')
        else:
            print(f'  [NOT FOUND] {path}')
    except:
        print(f'  [ERROR] {path}')

# Test 6: Technology detection
print('\n=== TECHNOLOGY ===')
try:
    r = requests.get(target, headers=headers, timeout=15)
    html = r.text.lower()
    techs = []
    if 'wordpress' in html or 'wp-content' in html:
        techs.append('WordPress')
    if 'shopify' in html:
        techs.append('Shopify')
    if 'wix' in html:
        techs.append('Wix')
    if 'squarespace' in html:
        techs.append('Squarespace')
    if 'drupal' in html:
        techs.append('Drupal')
    if 'joomla' in html:
        techs.append('Joomla')
    if 'react' in html or 'reactjs' in html:
        techs.append('React')
    if 'vue' in html or 'vuejs' in html:
        techs.append('Vue.js')
    if 'angular' in html:
        techs.append('Angular')
    
    if techs:
        print(f'  Detected: {", ".join(techs)}')
    else:
        print('  No obvious tech signatures')
except Exception as e:
    print(f'  Error: {e}')

print('\n' + '='*60)
print('[*] Passive scan complete')
