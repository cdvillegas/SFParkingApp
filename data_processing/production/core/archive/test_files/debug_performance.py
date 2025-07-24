#!/usr/bin/env python3

import pandas as pd
import time
import re

def normalize_street_name(street_name):
    if not street_name:
        return ""
    normalized = str(street_name).upper().replace(' ', '')
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

print("Loading data...")
citations = pd.read_csv('test_citations_small.csv').head(10)  # Just 10 for speed
schedules = pd.read_csv('../output/pipeline_results/20250721_223722/schedule_cleaned_20250721_223722.csv')

print(f"Testing with {len(citations)} citations and {len(schedules)} schedules")

# Pre-compute normalized schedule names
schedules['normalized_corridor'] = schedules['Corridor'].apply(normalize_street_name)

total_comparisons = 0
filtered_comparisons = 0

for i, row in citations.iterrows():
    citation_address = row['address']
    citation_street = extract_street_from_address(citation_address)
    citation_street_norm = normalize_street_name(citation_street)
    
    print(f"\nCitation: {citation_address}")
    print(f"Normalized: {citation_street_norm}")
    
    # Without filtering: 22K comparisons
    total_comparisons += len(schedules)
    
    # With filtering
    if citation_street_norm:
        street_matches = schedules[
            schedules['normalized_corridor'].str.contains(citation_street_norm, na=False) |
            (citation_street_norm in schedules['normalized_corridor'].astype(str))
        ]
        filtered_count = len(street_matches)
        filtered_comparisons += filtered_count
        print(f"Street matches: {filtered_count}")
    else:
        filtered_comparisons += len(schedules)
        print("No street name - no filtering")

print(f"\nSummary:")
print(f"Total comparisons without filtering: {total_comparisons:,}")
print(f"Total comparisons with filtering: {filtered_comparisons:,}")
print(f"Reduction factor: {total_comparisons/filtered_comparisons:.1f}x")
print(f"Filtering effectiveness: {(1 - filtered_comparisons/total_comparisons)*100:.1f}%")