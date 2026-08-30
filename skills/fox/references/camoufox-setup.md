# CamouFox Setup & Usage

## Installation

```bash
# Install Python package
pip3 install camoufox

# Install browser binary
python3 -m camoufox fetch

# Install system dependencies (Ubuntu/Debian)
apt-get install -y libgtk-3-0 libdbus-glib-1-2 libxt6 libasound2t64
```

## Basic Usage

```python
from camoufox.sync_api import Camoufox

with Camoufox(headless=True) as browser:
    page = browser.new_page()
    response = page.goto('https://target.com', wait_until='domcontentloaded', timeout=30000)
    print(f'Status: {response.status}')
    print(f'Content: {page.content()[:500]}')
    browser.close()
```

## CamouFox Research (MCP Integration)

```bash
# Install from repo
git clone https://github.com/aidvizhhub/camoufox-research.git
cd camoufox-research
pip3 install -e .

# Usage
python3 -m camoufox_research.camoufox_research  # MCP server mode
```

Available tools: research, fetch_page, batch_fetch, extract_links, browser_click, browser_type, web_search, monitor_page

## Proxy Support

### Format
```python
proxy = {
    "server": "socks5://IP:PORT",
    "username": "user",
    "password": "pass"
}

with Camoufox(proxy=proxy) as browser:
    # ...
```

### Common Issues
- **407 Proxy Authentication Required**: Credentials wrong OR IP not whitelisted at proxy provider
- **Connection Refused**: Proxy server down or wrong port
- **Timeout**: Network issue or proxy blocking target

## Headless Mode

```python
# Headless (no GUI)
with Camoufox(headless=True) as browser:
    pass

# With GUI (requires display)
with Camoufox(headless=False) as browser:
    pass
```

## Anti-Detection Features

- Randomized fingerprint per session
- WebGL noise injection
- Canvas fingerprint randomization
- Audio context noise
- Timezone/locale spoofing
- Screen resolution randomization

## Pitfalls

1. **System deps missing**: Must install libgtk-3-0, libasound2t64 etc. on Linux
2. **Binary not fetched**: Run `python3 -m camoufox fetch` after pip install
3. **Timeouts**: Some targets block by IP range — proxy required
4. **RAR files**: Downloaded files from Google Drive may be RAR despite .zip extension — verify with `file` command
