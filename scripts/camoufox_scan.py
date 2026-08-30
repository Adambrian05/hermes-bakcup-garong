#!/usr/bin/env python3
"""
CamouFox Web Scraper for lenoraconsulting.com
Anti-detection browser for stealth testing
Fox Mode - Zero Limits
"""

import json
import sys
from camoufox.sync_api import Camoufox

target = 'https://www.lenoraconsulting.com/'

print(f'[*] Target: {target}')
print('='*60)

try:
    print('\n[*] Launching CamouFox browser...')
    with Camoufox(headless=True) as browser:
        page = browser.new_page()
        
        print(f'[*] Navigating to {target}...')
        response = page.goto(target, wait_until='domcontentloaded', timeout=90000)
        
        if response:
            print(f'[*] Status: {response.status}')
        else:
            print('[*] Status: No response (timeout or error)')
        
        print(f'[*] Title: {page.title()}')
        print(f'[*] URL: {page.url}')
        
        # Get page content
        content = page.content()
        print(f'[*] Content length: {len(content)} chars')
        
        # Extract all links
        print('\n=== LINKS ===')
        links = page.eval_on_selector_all('a[href]', 'els => els.map(e => ({text: e.textContent.trim(), href: e.href}))')
        print(f'Found {len(links)} links')
        for i, link in enumerate(links[:20]):
            text = link.get('text', '')[:50]
            href = link.get('href', '')
            if text or href:
                print(f'  {i+1}. {text}: {href}')
        
        # Extract forms
        print('\n=== FORMS ===')
        forms = page.eval_on_selector_all('form', '''els => els.map(e => ({
            action: e.action,
            method: e.method,
            id: e.id,
            fields: Array.from(e.querySelectorAll('input,select,textarea')).map(f => ({
                name: f.name,
                type: f.type || f.tagName.toLowerCase(),
                id: f.id,
                placeholder: f.placeholder || ''
            }))
        }))''')
        print(f'Found {len(forms)} forms')
        for i, form in enumerate(forms):
            print(f'  Form {i+1}: action={form.get("action", "")}, method={form.get("method", "")}')
            for field in form.get('fields', [])[:5]:
                print(f'    - {field.get("name", "")}: {field.get("type", "")} (id={field.get("id", "")})')
        
        # Check for file manager indicators
        print('\n=== FILE MANAGER CHECK ===')
        keywords = ['file', 'manager', 'upload', 'directory', 'folder', 'document', 'admin', 'panel', 'dashboard']
        for keyword in keywords:
            elements = page.query_selector_all(f'[id*="{keyword}" i], [class*="{keyword}" i], [name*="{keyword}" i]')
            if elements:
                print(f'  [FOUND] {keyword}: {len(elements)} elements')
        
        # Extract JavaScript files
        print('\n=== JAVASCRIPT FILES ===')
        js_files = page.eval_on_selector_all('script[src]', 'els => els.map(e => e.src)')
        print(f'Found {len(js_files)} JS files')
        for js in js_files[:10]:
            print(f'  - {js}')
        
        # Technology detection
        print('\n=== TECHNOLOGY ===')
        techs = []
        
        # Check for common frameworks
        checks = [
            ('WordPress', 'wp-content'),
            ('Shopify', 'shopify'),
            ('Wix', 'wix.com'),
            ('Squarespace', 'squarespace'),
            ('React', 'react'),
            ('Vue.js', 'vue'),
            ('Angular', 'angular'),
            ('jQuery', 'jquery'),
            ('Bootstrap', 'bootstrap'),
        ]
        
        html = content.lower()
        for name, pattern in checks:
            if pattern in html:
                techs.append(name)
        
        if techs:
            print(f'  Detected: {", ".join(techs)}')
        else:
            print('  No obvious tech signatures')
        
        # Check for exposed files
        print('\n=== EXPOSED FILES ===')
        exposed_paths = ['/.git/HEAD', '/.env', '/robots.txt', '/sitemap.xml', '/wp-config.php']
        for path in exposed_paths:
            try:
                resp = page.goto(target + path, wait_until='domcontentloaded', timeout=15000)
                if resp and resp.status == 200:
                    body = page.content()
                    if len(body) > 10:
                        print(f'  [FOUND] {path} ({len(body)} chars)')
                else:
                    print(f'  [NOT FOUND] {path}')
            except:
                print(f'  [TIMEOUT] {path}')
        
        # Get page source for analysis
        print('\n=== PAGE SOURCE (first 500 chars) ===')
        print(content[:500])
        
        browser.close()
        print('\n[*] Browser closed.')

except Exception as e:
    print(f'[-] Error: {e}')
    import traceback
    traceback.print_exc()

print('\n' + '='*60)
print('[*] Scan complete')
