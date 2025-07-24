#!/usr/bin/env python3
"""
Test the improved matcher with 200m distance and directional removal
"""

import re

def extract_improved_street_name(address: str) -> str:
    """Test the improved street name extraction"""
    if not address:
        return ""
    
    # Remove street number from beginning
    match = re.match(r'^\d+\s+(.+)', str(address).strip())
    if match:
        street_with_type = match.group(1)
    else:
        street_with_type = str(address).strip()
    
    street_upper = street_with_type.upper().strip()
    
    # Remove directional suffixes first
    directional_suffixes = [
        'NORTH', 'SOUTH', 'EAST', 'WEST', 'NE', 'NW', 'SE', 'SW',
        'NORTHEAST', 'NORTHWEST', 'SOUTHEAST', 'SOUTHWEST'
    ]
    
    for direction in directional_suffixes:
        if street_upper.endswith(' ' + direction):
            street_upper = street_upper[:-len(' ' + direction)].strip()
            break
        elif street_upper.startswith(direction + ' '):
            street_upper = street_upper[len(direction + ' '):].strip()
            break
    
    # Remove street type suffixes
    street_types = [
        'STREET', 'ST', 'AVENUE', 'AVE', 'BOULEVARD', 'BLVD',
        'DRIVE', 'DR', 'COURT', 'CT', 'PLACE', 'PL', 'LANE', 'LN',
        'ROAD', 'RD', 'PARKWAY', 'PKWY', 'CIRCLE', 'CIR', 'TERRACE', 'TER',
        'WAY', 'PLAZA', 'PLZ', 'SQUARE', 'SQ'
    ]
    
    for suffix in street_types:
        if street_upper.endswith(' ' + suffix):
            return street_upper[:-len(' ' + suffix)].strip()
        elif street_upper.endswith(suffix) and len(street_upper) > len(suffix):
            return street_upper[:-len(suffix)].strip()
    
    return street_upper

def normalize_street(name):
    return str(name).upper().replace(' ', '')

# Test the problematic cases from the analysis
test_cases = [
    # Directional issues
    ("278 WILLARD NORTH ST", "Willard St"),
    ("200 EMBARCADERO SOUTH", "The Embarcadero"),
    ("401 BUENA VISTA AVE WEST", "Buena Vista Ave East"),
    ("29 EMBARCADERO NORTH", "The Embarcadero"),
    
    # Type variations
    ("30 BAYVIEW CIR", "Bay View St"),
    ("320 SAINT JOSEPHS AVE", "Saint Josephs Ave"),
    
    # Should still work
    ("380 O'FARRELL ST", "O'Farrell St"),
    ("1410 SOUTH VAN NESS AVE", "South Van Ness Ave")
]

print("IMPROVED STREET NAME MATCHING TEST")
print("=" * 60)

matches = 0
total = len(test_cases)

for citation_address, schedule_name in test_cases:
    citation_base = extract_improved_street_name(citation_address)
    citation_norm = normalize_street(citation_base)
    
    schedule_base = extract_improved_street_name(schedule_name)  # Remove type from schedule too
    schedule_norm = normalize_street(schedule_base)
    
    # Test matching
    is_match = (citation_norm == schedule_norm or 
                citation_norm in schedule_norm or 
                schedule_norm in citation_norm)
    
    if is_match:
        matches += 1
        status = "✅ MATCH"
    else:
        status = "❌ NO MATCH"
    
    print(f"{status}")
    print(f"  Citation: '{citation_address}' → '{citation_base}' → '{citation_norm}'")
    print(f"  Schedule: '{schedule_name}' → '{schedule_base}' → '{schedule_norm}'")
    print()

print(f"RESULTS: {matches}/{total} matches ({matches/total*100:.1f}%)")

# Special test for "The Embarcadero" case
print("\nSPECIAL EMBARCADERO TEST:")
embarcadero_cases = [
    "EMBARCADERO SOUTH",
    "EMBARCADERO NORTH", 
    "THE EMBARCADERO"
]

embarcadero_normalized = [normalize_street(extract_improved_street_name(case)) for case in embarcadero_cases]
print(f"All normalize to: {embarcadero_normalized}")
print(f"Match? {len(set(embarcadero_normalized)) == 1}")