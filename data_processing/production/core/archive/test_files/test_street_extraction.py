#!/usr/bin/env python3
"""
Test improved street name extraction - base name only
"""

import re

def extract_base_street_name(address: str) -> str:
    """Extract just the base street name, removing number and type suffix"""
    if not address:
        return ""
    
    # Remove street number from beginning
    match = re.match(r'^\d+\s+(.+)', str(address).strip())
    if match:
        street_with_type = match.group(1)
    else:
        street_with_type = str(address).strip()
    
    # Remove common street type suffixes
    street_types = [
        'STREET', 'ST', 'AVENUE', 'AVE', 'BOULEVARD', 'BLVD',
        'DRIVE', 'DR', 'COURT', 'CT', 'PLACE', 'PL', 'LANE', 'LN',
        'ROAD', 'RD', 'PARKWAY', 'PKWY', 'CIRCLE', 'CIR', 'TERRACE', 'TER',
        'WAY', 'PLAZA', 'PLZ', 'SQUARE', 'SQ'
    ]
    
    street_upper = street_with_type.upper().strip()
    
    # Try to remove suffix
    for suffix in street_types:
        if street_upper.endswith(' ' + suffix):
            return street_upper[:-len(' ' + suffix)].strip()
        elif street_upper.endswith(suffix) and len(street_upper) > len(suffix):
            # Handle cases without space before suffix
            return street_upper[:-len(suffix)].strip()
    
    # If no suffix found, return as-is
    return street_upper

def normalize_base_street(street_name: str) -> str:
    """Normalize base street name for matching"""
    if not street_name:
        return ""
    # Remove spaces and convert to uppercase
    return str(street_name).upper().replace(' ', '')

def test_street_extraction():
    """Test the improved street extraction"""
    
    # Test cases from our data
    test_citations = [
        "35 COSO AVE",
        "1410 SOUTH VAN NESS AVE", 
        "380 O'FARRELL ST",
        "30 BAYVIEW CIR",
        "85 BAY VIEW ST"
    ]
    
    test_schedules = [
        "Coso Ave",
        "South Van Ness Ave", 
        "O'Farrell St",
        "Bay View St",
        "Bay View Cir"
    ]
    
    print("CITATION EXTRACTION:")
    print("-" * 50)
    citation_base_names = {}
    for citation in test_citations:
        base = extract_base_street_name(citation)
        normalized = normalize_base_street(base)
        citation_base_names[citation] = normalized
        print(f"{citation:25} → {base:20} → {normalized}")
    
    print(f"\nSCHEDULE EXTRACTION:")
    print("-" * 50) 
    schedule_base_names = {}
    for schedule in test_schedules:
        base = extract_base_street_name(schedule)  # No number to remove
        normalized = normalize_base_street(base)
        schedule_base_names[schedule] = normalized
        print(f"{schedule:25} → {base:20} → {normalized}")
    
    print(f"\nMATCHING TEST:")
    print("-" * 50)
    for citation in test_citations:
        citation_norm = citation_base_names[citation]
        print(f"\nCitation: {citation} → {citation_norm}")
        matches = []
        for schedule in test_schedules:
            schedule_norm = schedule_base_names[schedule]
            if citation_norm == schedule_norm:
                matches.append(schedule)
            elif citation_norm in schedule_norm or schedule_norm in citation_norm:
                matches.append(f"{schedule} (partial)")
        
        if matches:
            print(f"  ✅ Matches: {', '.join(matches)}")
        else:
            print(f"  ❌ No matches found")

if __name__ == "__main__":
    test_street_extraction()