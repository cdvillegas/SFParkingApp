#!/usr/bin/env python3
"""
Simple demo: Show 10 citations with GPS coordinates and validation
"""

import requests
import pandas as pd
from geopy.geocoders import Nominatim
import time
import re
import csv

def extract_street_number(address):
    """Extract street number from address"""
    match = re.match(r'^(\d+)', address.strip())
    return int(match.group(1)) if match else None

def normalize_street_suffix(street_name):
    """Normalize street suffixes for fuzzy matching"""
    # Common SF street suffix mappings
    suffix_map = {
        ' ST': [' STREET', ' ST'],
        ' AVE': [' AVENUE', ' AVE'], 
        ' BLVD': [' BOULEVARD', ' BLVD'],
        ' DR': [' DRIVE', ' DR'],
        ' CT': [' COURT', ' CT'],
        ' PL': [' PLACE', ' PL'],
        ' WAY': [' WAY'],
        ' LN': [' LANE', ' LN'],
        ' RD': [' ROAD', ' RD'],
        ' PKWY': [' PARKWAY', ' PKWY']
    }
    
    # Create reverse mapping for lookup
    reverse_map = {}
    for short, variations in suffix_map.items():
        for variation in variations:
            reverse_map[variation] = short
    
    # Normalize the street name
    street_upper = street_name.upper()
    for full_suffix, short_suffix in reverse_map.items():
        if street_upper.endswith(full_suffix):
            return street_upper.replace(full_suffix, short_suffix)
    
    return street_upper

def extract_street_name(address):
    """Extract and normalize street name from address"""
    street_name = re.sub(r'^\d+\s*', '', address.strip())
    return normalize_street_suffix(street_name)

def fuzzy_street_match(orig_street, returned_address):
    """Check if street name matches with fuzzy suffix matching"""
    ret_street_upper = returned_address.upper()
    
    # Get the core street name (without suffix)
    orig_core = orig_street
    for suffix in [' ST', ' AVE', ' BLVD', ' DR', ' CT', ' PL', ' WAY', ' LN', ' RD', ' PKWY']:
        orig_core = orig_core.replace(suffix, '')
    
    print(f"       Street core: '{orig_core}'")
    
    # Check if core name appears in returned address
    core_match = orig_core.strip() in ret_street_upper
    
    if core_match:
        print(f"       Core match: ✅ ('{orig_core}' found)")
        
        # Check for suffix variations
        suffix_variations = [
            'STREET', 'ST', 'AVENUE', 'AVE', 'BOULEVARD', 'BLVD',
            'DRIVE', 'DR', 'COURT', 'CT', 'PLACE', 'PL', 'WAY',
            'LANE', 'LN', 'ROAD', 'RD', 'PARKWAY', 'PKWY'
        ]
        
        suffix_found = any(f"{orig_core} {suffix}" in ret_street_upper or 
                          f"{orig_core}, {suffix}" in ret_street_upper for suffix in suffix_variations)
        
        if suffix_found:
            print(f"       Suffix match: ✅ (found suffix variation)")
        else:
            print(f"       Suffix match: ⚠️ (core found but no suffix)")
            
        return True
    else:
        print(f"       Core match: ❌ ('{orig_core}' not found)")
        return False

def validate_geocoding_result(original_address, returned_address):
    """Check if geocoding result matches the original address with fuzzy matching"""
    
    # Extract components from original address
    orig_number = extract_street_number(original_address)
    orig_street = extract_street_name(original_address)
    
    print(f"    🔍 Validation:")
    print(f"       Original: {orig_number} {orig_street}")
    print(f"       Returned: {returned_address}")
    
    # Check 1: Fuzzy street name matching
    street_in_result = fuzzy_street_match(orig_street, returned_address)
    
    print(f"       Street match: {'✅' if street_in_result else '❌'}")
    
    # Check 2: Does the street number appear in the returned address?
    number_in_result = str(orig_number) in returned_address if orig_number else False
    
    print(f"       Number match: {'✅' if number_in_result else '❌'} ({orig_number} in result)")
    
    # Check 3: Is it a general street reference (bad)?
    ret_street_upper = returned_address.upper()
    is_general = any(phrase in ret_street_upper for phrase in [
        'AVENUE,', 'STREET,', 'BOULEVARD,', 'DISTRICT,', 'NEIGHBORHOOD'
    ])
    
    print(f"       Specific addr: {'❌' if is_general else '✅'} (not general street reference)")
    
    # Overall confidence
    confidence_score = 0
    if street_in_result: confidence_score += 40
    if number_in_result: confidence_score += 50
    if not is_general: confidence_score += 10
    
    if confidence_score >= 80:
        confidence = "HIGH"
        status = "✅"
    elif confidence_score >= 50:
        confidence = "MEDIUM" 
        status = "⚠️"
    else:
        confidence = "LOW"
        status = "❌"
    
    print(f"       Confidence: {status} {confidence} ({confidence_score}/100)")
    
    return confidence_score, confidence

def demo_citation_gps():
    """Get 10 citations and show their GPS coordinates with validation"""
    
    print("🚗 Street Cleaning Citations with GPS Coordinates & Validation")
    print("=" * 70)
    
    # Get 100 random street cleaning citations from last 90 days
    from datetime import datetime, timedelta
    import random
    
    # Calculate date 90 days ago
    ninety_days_ago = (datetime.now() - timedelta(days=90)).strftime('%Y-%m-%d')
    
    url = "https://data.sfgov.org/resource/ab4h-6ztd.json"
    params = {
        '$limit': 200,  # Get more to randomize from
        '$where': f"violation_desc = 'STR CLEAN' AND citation_issued_datetime > '{ninety_days_ago}'",
        '$order': 'citation_issued_datetime DESC'
    }
    
    response = requests.get(url, params=params)
    all_citations = response.json()
    
    # Randomly sample 100 citations for testing
    if len(all_citations) > 100:
        citations = random.sample(all_citations, 100)
    else:
        citations = all_citations
    
    # Set up geocoder
    geolocator = Nominatim(user_agent="validation_demo")
    
    print(f"Found {len(all_citations)} citations from last 90 days")
    print(f"Testing random sample of {len(citations)} citations:\n")
    
    high_confidence = 0
    medium_confidence = 0
    low_confidence = 0
    
    # Store results for CSV export
    csv_results = []
    
    for i, citation in enumerate(citations, 1):
        address = citation['citation_location']
        date_time = citation['citation_issued_datetime']
        
        print(f"{i:2d}. Address: {address}")
        print(f"    Time: {date_time}")
        
        # Get GPS coordinates for this address
        try:
            full_address = f"{address}, San Francisco, CA"
            location = geolocator.geocode(full_address, timeout=10)
            
            if location:
                lat = location.latitude
                lon = location.longitude
                print(f"    GPS: ({lat:.6f}, {lon:.6f})")
                
                # Validate the result
                score, confidence = validate_geocoding_result(address, location.address)
                
                # Store result for CSV
                csv_results.append({
                    'address': address,
                    'datetime': date_time,
                    'latitude': lat,
                    'longitude': lon,
                    'returned_address': location.address,
                    'confidence': confidence,
                    'confidence_score': score,
                    'geocoding_status': 'SUCCESS'
                })
                
                if confidence == "HIGH":
                    high_confidence += 1
                elif confidence == "MEDIUM":
                    medium_confidence += 1
                else:
                    low_confidence += 1
                    
            else:
                print(f"    GPS: Could not geocode")
                print(f"    🔍 Validation: ❌ No result found")
                
                # Store failed result for CSV
                csv_results.append({
                    'address': address,
                    'datetime': date_time,
                    'latitude': None,
                    'longitude': None,
                    'returned_address': None,
                    'confidence': 'FAILED',
                    'confidence_score': 0,
                    'geocoding_status': 'NO_RESULT'
                })
                
                low_confidence += 1
                
        except Exception as e:
            print(f"    GPS: Error - {e}")
            print(f"    🔍 Validation: ❌ Geocoding error")
            
            # Store error result for CSV
            csv_results.append({
                'address': address,
                'datetime': date_time,
                'latitude': None,
                'longitude': None,
                'returned_address': None,
                'confidence': 'ERROR',
                'confidence_score': 0,
                'geocoding_status': f'ERROR: {str(e)}'
            })
            
            low_confidence += 1
        
        print()  # Blank line
        time.sleep(0.5)  # Rate limiting
    
    # Summary
    print("=" * 70)
    print("📊 VALIDATION SUMMARY")
    print("=" * 70)
    total_tested = len(citations)
    print(f"High confidence: {high_confidence}/{total_tested} ✅")
    print(f"Medium confidence: {medium_confidence}/{total_tested} ⚠️") 
    print(f"Low confidence: {low_confidence}/{total_tested} ❌")
    
    total_usable = high_confidence + medium_confidence
    usable_percent = (total_usable / total_tested * 100) if total_tested > 0 else 0
    print(f"\nUsable results: {total_usable}/{total_tested} ({usable_percent:.1f}%)")
    
    if usable_percent >= 80:
        print("✅ Good geocoding quality - proceed with implementation")
    elif usable_percent >= 60:
        print("⚠️ Moderate quality - consider additional validation")
    else:
        print("❌ Poor quality - need better geocoding strategy")
    
    # Export results to CSV
    csv_filename = f"citation_gps_results_{len(citations)}_samples.csv"
    print(f"\n💾 Exporting results to {csv_filename}...")
    
    with open(csv_filename, 'w', newline='', encoding='utf-8') as csvfile:
        fieldnames = ['address', 'datetime', 'latitude', 'longitude', 'returned_address', 
                     'confidence', 'confidence_score', 'geocoding_status']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        
        writer.writeheader()
        for result in csv_results:
            writer.writerow(result)
    
    print(f"✅ Exported {len(csv_results)} results to {csv_filename}")
    print(f"📊 File contains: {high_confidence} HIGH, {medium_confidence} MEDIUM, {low_confidence} LOW confidence results")

if __name__ == "__main__":
    demo_citation_gps()