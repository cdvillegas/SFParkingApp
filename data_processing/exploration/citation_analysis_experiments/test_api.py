#!/usr/bin/env python3
"""
Test script to demonstrate the Street Sweeping API functionality
"""

import sys
import os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from street_sweeping_api import find_street_sweeping_times, load_citations_cache
import json

def test_address(address, days_filter=None):
    """Test the API for a specific address"""
    print(f"\n{'='*80}")
    print(f"TESTING ADDRESS: {address}")
    if days_filter:
        print(f"FILTERING FOR DAYS: {', '.join(days_filter)}")
    print(f"{'='*80}")
    
    # Load data
    citations_df = load_citations_cache()
    
    # Get results
    result = find_street_sweeping_times(address, citations_df, days_filter)
    
    # Pretty print results
    print(json.dumps(result, indent=2))
    
    return result

def main():
    """Run tests for various addresses"""
    
    print("Street Sweeping Prediction API - Test Suite")
    print("Loading citation data...")
    
    # Test cases
    test_cases = [
        {"address": "1530 Broderick St", "days": None},
        {"address": "1650 McAllister St", "days": ["tuesday", "thursday"]},
        {"address": "100 08th Ave", "days": ["wednesday"]},
        {"address": "2800 Laguna St", "days": ["thursday"]},
        {"address": "1000 Gilman Ave", "days": ["monday"]},
        {"address": "123 Nonexistent St", "days": None},  # Test error case
    ]
    
    results = []
    for test_case in test_cases:
        try:
            result = test_address(test_case["address"], test_case["days"])
            results.append(result)
        except Exception as e:
            print(f"ERROR testing {test_case['address']}: {e}")
    
    print(f"\n{'='*80}")
    print("SUMMARY")
    print(f"{'='*80}")
    
    for i, result in enumerate(results):
        if "error" in result:
            print(f"{i+1}. {result['address']}: ERROR - {result['error']}")
        elif "message" in result:
            print(f"{i+1}. {result['address']}: No data - {result['message']}")
        else:
            sweeping_days = list(result['sweeping_schedule'].keys())
            print(f"{i+1}. {result['address']}: Found data for {len(sweeping_days)} days ({', '.join(sweeping_days)})")
            
            # Show estimated times
            for day, info in result['sweeping_schedule'].items():
                confidence = info['confidence']
                est_time = info['estimated_time']
                citations = info['citation_count']
                print(f"   - {day}: {est_time} ({confidence} confidence, {citations} citations)")

if __name__ == "__main__":
    main()