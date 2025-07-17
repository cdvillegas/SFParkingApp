#!/usr/bin/env python3
"""
Test geocoding success rate on SF citation data
"""

import pandas as pd
import requests
from geopy.geocoders import Nominatim
import time

def test_geocoding_rate():
    """Test how many citation addresses successfully geocode"""
    
    print("Fetching 1000 recent street sweeping citations...")
    url = "https://data.sfgov.org/resource/ab4h-6ztd.json"
    params = {
        '$limit': 1000,
        '$where': "violation_desc = 'STR CLEAN'",
        '$order': 'citation_issued_datetime DESC'
    }
    
    response = requests.get(url, params=params)
    df = pd.DataFrame(response.json())
    
    print(f"✅ Loaded {len(df)} citations")
    
    # Get unique addresses to avoid duplicates
    unique_addresses = df['citation_location'].unique()
    print(f"📍 Found {len(unique_addresses)} unique addresses")
    
    # Test geocoding on first 50 unique addresses
    test_sample = unique_addresses[:50]
    print(f"🧪 Testing geocoding on first {len(test_sample)} addresses...")
    
    geolocator = Nominatim(user_agent="sf_geocoding_test")
    successful = 0
    failed = 0
    
    for i, address in enumerate(test_sample):
        print(f"{i+1:2d}. {address:30s} ", end="")
        
        try:
            full_address = f"{address}, San Francisco, CA"
            location = geolocator.geocode(full_address, timeout=10)
            
            if location:
                coords = (location.latitude, location.longitude)
                print(f"✅ ({coords[0]:.6f}, {coords[1]:.6f})")
                successful += 1
            else:
                print("❌ No location found")
                failed += 1
                
        except Exception as e:
            print(f"❌ Error: {str(e)[:30]}")
            failed += 1
        
        # Rate limiting
        time.sleep(0.2)
    
    # Results
    success_rate = (successful / len(test_sample)) * 100
    print(f"\n{'='*60}")
    print(f"📊 GEOCODING RESULTS")
    print(f"{'='*60}")
    print(f"Addresses tested: {len(test_sample)}")
    print(f"Successful: {successful}")
    print(f"Failed: {failed}")
    print(f"Success rate: {success_rate:.1f}%")
    
    if success_rate > 80:
        print("✅ Good success rate - proceed with full implementation")
    elif success_rate > 50:
        print("⚠️ Moderate success rate - may need address cleaning")
    else:
        print("❌ Low success rate - need to improve address formatting")

if __name__ == "__main__":
    test_geocoding_rate()