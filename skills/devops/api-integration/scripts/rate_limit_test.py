#!/usr/bin/env python3
"""
API Rate Limit Tester
Tests API endpoints with rate limiting awareness
"""

import requests
import time
import json
import sys
from typing import Dict, Any, Optional

def test_api_rate_limit(
    url: str,
    method: str = "GET",
    headers: Optional[Dict[str, str]] = None,
    data: Optional[Dict[str, Any]] = None,
    max_requests: int = 10,
    delay: float = 1.0
) -> Dict[str, Any]:
    """
    Test API rate limiting behavior
    
    Args:
        url: API endpoint URL
        method: HTTP method (GET, POST, etc.)
        headers: Request headers
        data: Request body (for POST)
        max_requests: Maximum number of requests to test
        delay: Delay between requests (seconds)
    
    Returns:
        dict: Rate limit analysis
    """
    if headers is None:
        headers = {"Content-Type": "application/json"}
    
    results = {
        "url": url,
        "method": method,
        "requests_made": 0,
        "successful": 0,
        "rate_limited": 0,
        "errors": 0,
        "rate_limit_headers": {},
        "details": []
    }
    
    for i in range(max_requests):
        try:
            start_time = time.time()
            
            if method.upper() == "POST":
                response = requests.post(url, headers=headers, json=data, timeout=10)
            else:
                response = requests.get(url, headers=headers, timeout=10)
            
            elapsed = time.time() - start_time
            
            result = {
                "request_num": i + 1,
                "status_code": response.status_code,
                "elapsed": round(elapsed, 3),
                "headers": {}
            }
            
            # Extract rate limit headers
            for header in ["X-RateLimit-Limit", "X-RateLimit-Remaining", 
                          "X-RateLimit-Reset", "Retry-After", "ratelimit-limit",
                          "ratelimit-remaining", "ratelimit-reset", "ratelimit-policy"]:
                if header in response.headers:
                    result["headers"][header] = response.headers[header]
                    results["rate_limit_headers"][header] = response.headers[header]
            
            if response.status_code == 429:
                results["rate_limited"] += 1
                result["rate_limited"] = True
            elif response.status_code == 200:
                results["successful"] += 1
                result["rate_limited"] = False
            else:
                result["rate_limited"] = False
            
            results["requests_made"] += 1
            results["details"].append(result)
            
            # Print progress
            status = "✅" if response.status_code == 200 else "⚠️" if response.status_code == 429 else "❌"
            print(f"{status} Request {i+1}/{max_requests}: {response.status_code} ({elapsed:.3f}s)")
            
            # Stop if rate limited
            if response.status_code == 429:
                print(f"\n⚠️  Rate limited after {i+1} requests")
                break
            
            # Delay between requests
            if i < max_requests - 1:
                time.sleep(delay)
                
        except requests.exceptions.RequestException as e:
            results["errors"] += 1
            results["details"].append({
                "request_num": i + 1,
                "error": str(e)
            })
            print(f"❌ Request {i+1}/{max_requests}: Error - {e}")
    
    # Calculate rate limit
    if results["rate_limited"] > 0:
        first_rate_limited = next(
            (d for d in results["details"] if d.get("rate_limited")),
            None
        )
        if first_rate_limited:
            results["effective_rate"] = f"{first_rate_limited['request_num']-1} requests per {(first_rate_limited['request_num']-1) * delay:.0f} seconds"
    
    return results

def print_analysis(results: Dict[str, Any]):
    """Print rate limit analysis"""
    print("\n" + "="*60)
    print("📊 RATE LIMIT ANALYSIS")
    print("="*60)
    print(f"URL: {results['url']}")
    print(f"Method: {results['method']}")
    print(f"Requests made: {results['requests_made']}")
    print(f"Successful: {results['successful']}")
    print(f"Rate limited: {results['rate_limited']}")
    print(f"Errors: {results['errors']}")
    
    if results.get("effective_rate"):
        print(f"Effective rate: {results['effective_rate']}")
    
    if results["rate_limit_headers"]:
        print("\n📋 Rate Limit Headers:")
        for header, value in results["rate_limit_headers"].items():
            print(f"  {header}: {value}")
    
    print("\n📝 Request Details:")
    for detail in results["details"]:
        if "error" in detail:
            print(f"  #{detail['request_num']}: ERROR - {detail['error']}")
        else:
            status = "✅" if detail["status_code"] == 200 else "⚠️" if detail["status_code"] == 429 else "❌"
            print(f"  #{detail['request_num']}: {status} {detail['status_code']} ({detail['elapsed']}s)")

def main():
    """CLI entry point"""
    if len(sys.argv) < 2:
        print("Usage: python rate_limit_test.py <url> [method] [delay] [max_requests]")
        print("Example: python rate_limit_test.py https://api.example.com/endpoint POST 1.0 10")
        sys.exit(1)
    
    url = sys.argv[1]
    method = sys.argv[2] if len(sys.argv) > 2 else "GET"
    delay = float(sys.argv[3]) if len(sys.argv) > 3 else 1.0
    max_requests = int(sys.argv[4]) if len(sys.argv) > 4 else 10
    
    print(f"🔍 Testing rate limits for: {url}")
    print(f"   Method: {method}, Delay: {delay}s, Max requests: {max_requests}")
    print()
    
    results = test_api_rate_limit(url, method, delay=delay, max_requests=max_requests)
    print_analysis(results)

if __name__ == "__main__":
    main()
