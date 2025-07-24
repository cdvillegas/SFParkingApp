#!/usr/bin/env python3

import pandas as pd
import re

def normalize_street_name(street_name):
    if not street_name:
        return ""
    
    # Convert to uppercase and remove spaces for better matching
    normalized = str(street_name).upper().replace(' ', '')
    
    # Remove common prefixes
    for prefix in ['THE', 'OLD', 'NEW']:
        if normalized.startswith(prefix):
            normalized = normalized[len(prefix):]
    
    # Normalize suffixes (without spaces now)
    suffix_map = {
        'STREET': 'ST', 'AVENUE': 'AVE', 'BOULEVARD': 'BLVD',
        'DRIVE': 'DR', 'COURT': 'CT', 'PLACE': 'PL',
        'LANE': 'LN', 'ROAD': 'RD', 'PARKWAY': 'PKWY',
        'CIRCLE': 'CIR', 'TERRACE': 'TER'
    }
    
    for full_suffix, short_suffix in suffix_map.items():
        if normalized.endswith(full_suffix):
            normalized = normalized[:-len(full_suffix)] + short_suffix
            break
            
    return normalized.strip()

def extract_street_from_address(address):
    if not address:
        return ""
    
    match = re.match(r'^\d+\s+(.+)', str(address).strip())
    if match:
        return match.group(1)
    return str(address).strip()

# Load sample data
print("Loading sample citation data...")
citations = pd.read_csv('test_citations_small.csv').head(100)  # Just first 100
schedules = pd.read_csv('../output/pipeline_results/20250721_223722/schedule_cleaned_20250721_223722.csv')

# Pre-compute normalized schedule names
schedules['normalized_corridor'] = schedules['Corridor'].apply(normalize_street_name)

print(f"Testing with {len(citations)} citations and {len(schedules)} schedules")

matches_found = 0
no_matches = 0

print("\nSample pre-filtering results:")
print("Citation Address -> Normalized -> Matching Schedules")
print("-" * 60)

for i, row in citations.head(20).iterrows():
    citation_address = row['address']
    citation_street = extract_street_from_address(citation_address)
    citation_street_norm = normalize_street_name(citation_street)
    
    if citation_street_norm:
        # Find matching schedules
        street_matches = schedules[
            schedules['normalized_corridor'].str.contains(citation_street_norm, na=False) |
            (citation_street_norm in schedules['normalized_corridor'].astype(str))
        ]
        
        match_count = len(street_matches)
        if match_count > 0:
            matches_found += 1
        else:
            no_matches += 1
            
        print(f"{citation_address[:30]:30} -> {citation_street_norm[:20]:20} -> {match_count:3} schedules")
    else:
        no_matches += 1
        print(f"{citation_address[:30]:30} -> {'(no street)':20} -> {0:3} schedules")

print(f"\nSummary for first 20 citations:")
print(f"Citations with street matches: {matches_found}")
print(f"Citations with no matches: {no_matches}")
print(f"Match rate: {matches_found/(matches_found + no_matches)*100:.1f}%")