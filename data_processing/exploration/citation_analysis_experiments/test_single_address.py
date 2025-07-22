#!/usr/bin/env python3
"""
Test script for a single address: 1525 Broderick St
"""

import sys
import os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from street_sweeping_api import find_street_sweeping_times, load_citations_cache
import json

def main():
    """Test 1525 Broderick St"""
    
    address = "1525 Broderick St"
    
    print(f"Street Sweeping Prediction for: {address}")
    print("="*60)
    print("Loading citation data...")
    
    # Load data
    citations_df = load_citations_cache()
    
    # Get results
    result = find_street_sweeping_times(address, citations_df)
    
    # Pretty print results
    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()