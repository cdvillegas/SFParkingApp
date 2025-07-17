#!/usr/bin/env python3
"""
Test full coordinate matching with 1000 citations
"""

import pandas as pd
import requests
from geopy.geocoders import Nominatim
from geopy.distance import distance
import time
import json

def test_full_coordinate_matching():
    """Test with 1000 citations around a known sweeping area"""
    
    # Use Baker St coordinates (we know citations exist there)
    test_lat = 37.773985  # 333 Baker St area
    test_lon = -122.441286
    test_radius = 100  # 100m radius (realistic for street sweeping)
    
    print(f"🔍 Testing coordinate matching")
    print(f"📍 Location: ({test_lat:.6f}, {test_lon:.6f})")
    print(f"📏 Radius: {test_radius}m")
    
    # Get 1000 recent citations
    print(f"\n📋 Fetching 1000 street sweeping citations...")
    url = "https://data.sfgov.org/resource/ab4h-6ztd.json"
    params = {
        '$limit': 1000,
        '$where': "violation_desc = 'STR CLEAN'",
        '$order': 'citation_issued_datetime DESC'
    }
    
    response = requests.get(url, params=params)
    df = pd.DataFrame(response.json())
    
    if df.empty:
        print("❌ No citation data")
        return
    
    # Add datetime processing
    df['citation_issued_datetime'] = pd.to_datetime(df['citation_issued_datetime'])
    df['day_of_week'] = df['citation_issued_datetime'].dt.strftime('%A')
    df['hour_time'] = df['citation_issued_datetime'].dt.time
    
    print(f"✅ Loaded {len(df)} citations")
    print(f"📅 Date range: {df['citation_issued_datetime'].min().strftime('%Y-%m-%d')} to {df['citation_issued_datetime'].max().strftime('%Y-%m-%d')}")
    
    # Get unique addresses for efficiency
    unique_addresses = df['citation_location'].unique()
    print(f"📍 Unique addresses: {len(unique_addresses)}")
    
    # Geocode and find nearby
    geolocator = Nominatim(user_agent="sf_full_test")
    user_point = (test_lat, test_lon)
    address_coords = {}  # Cache coordinates
    nearby_citations = []
    
    print(f"\n🌍 Geocoding and checking distances...")
    
    # First pass: geocode unique addresses
    for i, address in enumerate(unique_addresses):
        if i % 100 == 0:
            print(f"  Geocoded {i}/{len(unique_addresses)} addresses...")
        
        try:
            full_address = f"{address}, San Francisco, CA"
            location = geolocator.geocode(full_address, timeout=10)
            
            if location:
                coords = (location.latitude, location.longitude)
                dist = distance(user_point, coords).meters
                address_coords[address] = {'coords': coords, 'distance': dist}
                
                if dist <= test_radius:
                    print(f"  🎯 {address} - {dist:.1f}m")
            
            # Rate limiting
            time.sleep(0.1)
            
        except Exception as e:
            print(f"  ❌ Error geocoding {address}: {e}")
            continue
    
    # Second pass: collect all citations for nearby addresses
    print(f"\n📊 Collecting citations for nearby addresses...")
    
    for _, citation in df.iterrows():
        address = citation['citation_location']
        
        if address in address_coords:
            addr_data = address_coords[address]
            
            if addr_data['distance'] <= test_radius:
                nearby_citations.append({
                    'address': address,
                    'coordinates': addr_data['coords'],
                    'distance_meters': addr_data['distance'],
                    'day_of_week': citation['day_of_week'],
                    'time': citation['hour_time'],
                    'date': citation['citation_issued_datetime']
                })
    
    # Results and analysis
    print(f"\n{'='*60}")
    print(f"🎯 RESULTS")
    print(f"{'='*60}")
    print(f"Total citations processed: {len(df)}")
    print(f"Unique addresses geocoded: {len([a for a in address_coords.values() if a])}")
    print(f"Citations within {test_radius}m: {len(nearby_citations)}")
    
    if nearby_citations:
        print(f"\n📍 Nearby citations summary:")
        
        # Group by day
        by_day = {}
        for citation in nearby_citations:
            day = citation['day_of_week']
            if day not in by_day:
                by_day[day] = []
            by_day[day].append(citation)
        
        for day, citations in by_day.items():
            times = [c['time'] for c in citations]
            avg_dist = sum(c['distance_meters'] for c in citations) / len(citations)
            print(f"  {day}: {len(citations)} citations, avg distance {avg_dist:.1f}m")
            print(f"    Time range: {min(times)} - {max(times)}")
        
        # Show closest citations
        print(f"\n🏆 5 closest citations:")
        sorted_citations = sorted(nearby_citations, key=lambda x: x['distance_meters'])
        for i, citation in enumerate(sorted_citations[:5], 1):
            print(f"  {i}. {citation['address']} - {citation['distance_meters']:.1f}m")
            print(f"     {citation['day_of_week']} {citation['time']} on {citation['date'].strftime('%Y-%m-%d')}")
    
    else:
        print(f"\n❌ No citations found within {test_radius}m")
        
        # Show closest ones
        if address_coords:
            closest = min(address_coords.items(), key=lambda x: x[1]['distance'] if x[1] else float('inf'))
            print(f"💡 Closest address: {closest[0]} at {closest[1]['distance']:.1f}m")

if __name__ == "__main__":
    test_full_coordinate_matching()