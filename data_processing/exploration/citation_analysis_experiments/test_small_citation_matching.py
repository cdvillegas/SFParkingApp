#!/usr/bin/env python3
"""
Small test for citation coordinate matching - recent street sweeping citations only
"""

import pandas as pd
import requests
from datetime import datetime
import numpy as np
from geopy.geocoders import Nominatim
from geopy.distance import distance
import json
import time

def get_recent_street_sweeping_citations(limit=20):
    """Get most recent street sweeping citations"""
    print(f"Fetching {limit} most recent street sweeping citations...")
    url = "https://data.sfgov.org/resource/ab4h-6ztd.json"
    params = {
        '$limit': limit,
        '$where': "violation_desc = 'STR CLEAN'",
        '$order': 'citation_issued_datetime DESC'
    }
    response = requests.get(url, params=params)
    df = pd.DataFrame(response.json())
    
    if not df.empty:
        df['citation_issued_datetime'] = pd.to_datetime(df['citation_issued_datetime'])
        df['day_of_week'] = df['citation_issued_datetime'].dt.strftime('%A')
        df['hour_time'] = df['citation_issued_datetime'].dt.time
    
    print(f"✅ Loaded {len(df)} street sweeping citations")
    return df

def test_coordinate_matching():
    """Test coordinate matching with small dataset"""
    
    # Test location: Panhandle area (known sweeping area)
    test_lat = 37.7751
    test_lon = -122.4389
    test_radius = 200  # 200m radius for better chance of finding citations
    
    print(f"\n🔍 Testing at coordinates: ({test_lat:.4f}, {test_lon:.4f})")
    print(f"📏 Search radius: {test_radius} meters")
    
    # Get recent citations
    citations_df = get_recent_street_sweeping_citations(20)
    
    if citations_df.empty:
        print("❌ No citation data available")
        return
    
    print(f"\n📋 Sample of recent citations:")
    for i, row in citations_df.head(5).iterrows():
        print(f"  {i+1}. {row['citation_location']} - {row['day_of_week']} {row['hour_time']}")
    
    # Test geocoding
    geolocator = Nominatim(user_agent="sf_parking_test_v1")
    user_point = (test_lat, test_lon)
    nearby_citations = []
    
    print(f"\n🌍 Testing geocoding and distance calculation:")
    
    for idx, citation in citations_df.iterrows():
        address = citation['citation_location']
        print(f"\n{idx+1}. Testing: {address}")
        
        try:
            full_address = f"{address}, San Francisco, CA"
            location = geolocator.geocode(full_address, timeout=10)
            
            if location:
                coords = (location.latitude, location.longitude)
                dist = distance(user_point, coords).meters
                
                print(f"   📍 Coords: ({coords[0]:.6f}, {coords[1]:.6f})")
                print(f"   📏 Distance: {dist:.1f}m")
                
                if dist <= test_radius:
                    nearby_citations.append({
                        'address': address,
                        'coordinates': coords,
                        'distance_meters': dist,
                        'day_of_week': citation['day_of_week'],
                        'time': citation['hour_time'],
                        'date': citation['citation_issued_datetime']
                    })
                    print(f"   ✅ WITHIN RADIUS!")
                else:
                    print(f"   ❌ Outside {test_radius}m radius")
            else:
                print(f"   ❌ Geocoding failed")
                
        except Exception as e:
            print(f"   ❌ Error: {e}")
        
        # Small delay to avoid rate limits
        time.sleep(0.5)
    
    # Results
    print(f"\n{'='*60}")
    print(f"🎯 RESULTS")
    print(f"{'='*60}")
    print(f"Total citations tested: {len(citations_df)}")
    print(f"Citations within {test_radius}m: {len(nearby_citations)}")
    
    if nearby_citations:
        print(f"\n📍 Nearby street sweeping citations:")
        for i, citation in enumerate(nearby_citations, 1):
            print(f"\n{i}. {citation['address']}")
            print(f"   Distance: {citation['distance_meters']:.1f}m")
            print(f"   Day: {citation['day_of_week']}")
            print(f"   Time: {citation['time']}")
            print(f"   Date: {citation['date'].strftime('%Y-%m-%d %H:%M')}")
        
        # Analyze patterns
        print(f"\n📊 ANALYSIS:")
        days = [c['day_of_week'] for c in nearby_citations]
        times = [c['time'] for c in nearby_citations]
        
        print(f"Days found: {set(days)}")
        print(f"Time range: {min(times)} - {max(times)}")
        
    else:
        print(f"\n❌ No citations found within {test_radius}m")
        print("💡 Try increasing radius or testing different coordinates")

if __name__ == "__main__":
    test_coordinate_matching()