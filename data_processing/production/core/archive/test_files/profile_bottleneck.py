#!/usr/bin/env python3
"""
Profile the citation-schedule matcher to find bottlenecks
"""

import pandas as pd
import time
import cProfile
import pstats
from io import StringIO
import json
import re
from geopy.distance import geodesic
from typing import List, Tuple, Optional

class ProfileMatcher:
    def __init__(self):
        pass

    def normalize_street_name(self, street_name: str) -> str:
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

    def extract_street_from_address(self, address: str) -> str:
        if not address:
            return ""
        match = re.match(r'^\d+\s+(.+)', str(address).strip())
        if match:
            return match.group(1)
        return str(address).strip()

    def parse_linestring_coordinates(self, linestring: str) -> Optional[List[Tuple[float, float]]]:
        if pd.isna(linestring) or not linestring.strip():
            return None
        try:
            if linestring.startswith("{'type':") or linestring.startswith('{"type":'):
                geojson_data = eval(linestring) if linestring.startswith("{'") else json.loads(linestring)
                if geojson_data.get('type') == 'LineString':
                    coordinates = []
                    for coord in geojson_data.get('coordinates', []):
                        lon, lat = coord[0], coord[1]
                        coordinates.append((lat, lon))
                    return coordinates if coordinates else None
            else:
                coords_str = linestring.replace('LINESTRING', '').strip('() ')
                coord_pairs = coords_str.split(', ')
                coordinates = []
                for pair in coord_pairs:
                    lon, lat = map(float, pair.split())
                    coordinates.append((lat, lon))
                return coordinates if coordinates else None
        except Exception as e:
            return None

    def calculate_distance_to_schedule(self, citation_lat: float, citation_lon: float, 
                                     schedule_coordinates: List[Tuple[float, float]]) -> float:
        if not schedule_coordinates:
            return float('inf')
            
        min_distance = float('inf')
        citation_point = (citation_lat, citation_lon)
        
        for coord in schedule_coordinates:
            distance = geodesic(citation_point, coord).meters
            min_distance = min(min_distance, distance)
        
        return min_distance

    def time_function(self, func, *args, **kwargs):
        start = time.time()
        result = func(*args, **kwargs)
        end = time.time()
        return result, (end - start) * 1000  # milliseconds

    def profile_single_citation(self, citation_row, schedule_df):
        print(f"\nProfiling citation: {citation_row['address']}")
        
        # Time each step
        citation_address = citation_row['address']
        
        # Step 1: Extract and normalize street name
        citation_street, t1 = self.time_function(self.extract_street_from_address, citation_address)
        citation_street_norm, t2 = self.time_function(self.normalize_street_name, citation_street)
        print(f"  Street extraction + normalization: {t1+t2:.2f}ms")
        
        # Step 2: Street name filtering
        def street_filter():
            if citation_street_norm:
                return schedule_df[
                    schedule_df['normalized_corridor'].str.contains(citation_street_norm, na=False) |
                    (citation_street_norm in schedule_df['normalized_corridor'].astype(str))
                ].copy()
            else:
                return schedule_df.copy()
        
        street_matches, t3 = self.time_function(street_filter)
        print(f"  Street filtering ({len(street_matches)} matches): {t3:.2f}ms")
        
        if street_matches.empty:
            print("  No street matches - stopping")
            return
        
        # Step 3: Day filtering
        def day_filter():
            citation_weekday = 'Tuesday'  # Mock weekday
            if citation_weekday == 'Tuesday':
                return street_matches[street_matches['Tuesday'] == 1].copy()
            return street_matches.head(0)
        
        day_matches, t4 = self.time_function(day_filter)
        print(f"  Day filtering ({len(day_matches)} matches): {t4:.2f}ms")
        
        if day_matches.empty:
            print("  No day matches - stopping")
            return
        
        # Step 4: Parse coordinates for all matches
        def parse_all_coords():
            day_matches['parsed_coords'] = day_matches['Line'].apply(self.parse_linestring_coordinates)
            return day_matches[day_matches['parsed_coords'].notna()].copy()
        
        coord_matches, t5 = self.time_function(parse_all_coords)
        print(f"  Coordinate parsing ({len(coord_matches)} matches): {t5:.2f}ms")
        
        # Step 5: Distance calculations
        citation_lat = citation_row['latitude']
        citation_lon = citation_row['longitude']
        
        distances = []
        total_distance_time = 0
        
        for _, schedule_row in coord_matches.head(10).iterrows():  # Test first 10 only
            coords = schedule_row['parsed_coords']
            dist, dt = self.time_function(self.calculate_distance_to_schedule, citation_lat, citation_lon, coords)
            distances.append(dist)
            total_distance_time += dt
        
        print(f"  Distance calculations (10 samples): {total_distance_time:.2f}ms")
        print(f"  Average per distance calc: {total_distance_time/10:.3f}ms")
        
        # Total time
        total_time = t1 + t2 + t3 + t4 + t5 + total_distance_time
        print(f"  TOTAL TIME: {total_time:.2f}ms")
        
        return {
            'street_norm_time': t1 + t2,
            'street_filter_time': t3,
            'day_filter_time': t4,
            'coord_parse_time': t5,
            'distance_calc_time': total_distance_time,
            'total_time': total_time,
            'street_matches': len(street_matches),
            'day_matches': len(day_matches),
            'coord_matches': len(coord_matches)
        }

def main():
    print("Loading test data...")
    citations = pd.read_csv('test_citations_small.csv').head(5)
    schedules = pd.read_csv('../output/pipeline_results/20250721_223722/schedule_cleaned_20250721_223722.csv')
    
    # Pre-compute normalized schedule names
    print("Pre-computing schedule normalizations...")
    start = time.time()
    matcher = ProfileMatcher()
    schedules['normalized_corridor'] = schedules['Corridor'].apply(matcher.normalize_street_name)
    precompute_time = (time.time() - start) * 1000
    print(f"Schedule normalization precomputation: {precompute_time:.2f}ms for {len(schedules)} schedules")
    
    print(f"\nTesting with {len(citations)} citations and {len(schedules)} schedules")
    
    results = []
    for i, citation in citations.iterrows():
        result = matcher.profile_single_citation(citation, schedules)
        if result:
            results.append(result)
    
    if results:
        print(f"\n=== SUMMARY ACROSS {len(results)} CITATIONS ===")
        avg_street_norm = sum(r['street_norm_time'] for r in results) / len(results)
        avg_street_filter = sum(r['street_filter_time'] for r in results) / len(results)
        avg_day_filter = sum(r['day_filter_time'] for r in results) / len(results)
        avg_coord_parse = sum(r['coord_parse_time'] for r in results) / len(results)
        avg_distance_calc = sum(r['distance_calc_time'] for r in results) / len(results)
        avg_total = sum(r['total_time'] for r in results) / len(results)
        
        print(f"Average street normalization: {avg_street_norm:.2f}ms")
        print(f"Average street filtering: {avg_street_filter:.2f}ms")
        print(f"Average day filtering: {avg_day_filter:.2f}ms")
        print(f"Average coordinate parsing: {avg_coord_parse:.2f}ms")
        print(f"Average distance calculations: {avg_distance_calc:.2f}ms")
        print(f"AVERAGE TOTAL PER CITATION: {avg_total:.2f}ms")
        
        print(f"\nProjected time for 468K citations: {avg_total * 468000 / 1000 / 60:.1f} minutes")

if __name__ == "__main__":
    main()