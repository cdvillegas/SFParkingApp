#!/usr/bin/env python3
"""
Accuracy Comparison: Grid CNN vs String Matching
Test both approaches on the same citations to validate accuracy
"""

import pandas as pd
import json
from typing import Dict, List, Tuple, Optional
from geopy.distance import geodesic
import time
from collections import defaultdict
import re

class AccuracyTester:
    def __init__(self):
        self.schedules = None
        
    def load_data(self):
        """Load test data"""
        print("Loading data for accuracy testing...")
        citations = pd.read_csv('test_citations_small.csv').head(20)  # Small sample for detailed analysis
        schedules = pd.read_csv('../output/pipeline_results/20250721_223722/schedule_cleaned_20250721_223722.csv')
        
        # Add parsed coordinates
        schedules['parsed_coords'] = schedules['Line'].apply(self.parse_linestring_coordinates)
        self.schedules = schedules[schedules['parsed_coords'].notna()].copy()
        
        print(f"Testing with {len(citations)} citations and {len(self.schedules)} valid schedules")
        return citations, self.schedules

    def parse_linestring_coordinates(self, linestring: str) -> Optional[List[Tuple[float, float]]]:
        """Parse GeoJSON LineString to coordinates"""
        if pd.isna(linestring) or not linestring.strip():
            return None
        try:
            if linestring.startswith("{'type':"):
                geojson_data = eval(linestring)
                if geojson_data.get('type') == 'LineString':
                    coordinates = []
                    for coord in geojson_data.get('coordinates', []):
                        lon, lat = coord[0], coord[1]
                        coordinates.append((lat, lon))
                    return coordinates if coordinates else None
            return None
        except Exception:
            return None

    # ============ STRING MATCHING APPROACH ============
    
    def normalize_street_name(self, street_name: str) -> str:
        """Normalize street name for fuzzy matching"""
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
        """Extract street name from full address"""
        if not address:
            return ""
        match = re.match(r'^\d+\s+(.+)', str(address).strip())
        if match:
            return match.group(1)
        return str(address).strip()

    def calculate_distance_to_schedule(self, citation_lat: float, citation_lon: float, 
                                     schedule_coordinates: List[Tuple[float, float]]) -> float:
        """Calculate distance from citation to schedule line"""
        if not schedule_coordinates:
            return float('inf')
        
        citation_point = (citation_lat, citation_lon)
        min_distance = float('inf')
        
        for coord in schedule_coordinates:
            distance = geodesic(citation_point, coord).meters
            min_distance = min(min_distance, distance)
        
        return min_distance

    def string_match_citation(self, citation_row: pd.Series) -> List[Dict]:
        """Match citation using original string-based approach"""
        citation_address = citation_row['address']
        citation_street = self.extract_street_from_address(citation_address)
        citation_street_norm = self.normalize_street_name(citation_street)
        citation_lat = citation_row['latitude']
        citation_lon = citation_row['longitude']
        
        if not citation_street_norm:
            return []
        
        # Pre-compute normalized schedule names (should be done once in practice)
        if 'normalized_corridor' not in self.schedules.columns:
            self.schedules['normalized_corridor'] = self.schedules['Corridor'].apply(self.normalize_street_name)
        
        # Street name filtering
        street_matches = self.schedules[
            self.schedules['normalized_corridor'].str.contains(citation_street_norm, na=False)
        ].copy()
        
        # Day filtering (mock Tuesday)
        day_matches = street_matches[street_matches['Tuesday'] == 1].copy()
        
        # Distance filtering
        matches = []
        for _, schedule in day_matches.iterrows():
            distance = self.calculate_distance_to_schedule(citation_lat, citation_lon, schedule['parsed_coords'])
            if distance <= 50:  # 50m threshold
                match = {
                    'method': 'string',
                    'schedule_id': schedule['CleanBlockSweepID'],
                    'cnn': schedule['CNN'],
                    'corridor': schedule['Corridor'],
                    'distance_meters': distance,
                    'limits': schedule['Limits']
                }
                matches.append(match)
        
        return matches

    # ============ CNN GRID APPROACH ============
    
    def build_cnn_grid(self):
        """Build CNN grid index"""
        self.cnn_lookup = {}
        self.cnn_centroids = {}
        self.spatial_grid = defaultdict(list)
        
        # Group by CNN
        cnn_coords = defaultdict(list)
        for _, row in self.schedules.iterrows():
            cnn = row['CNN']
            if cnn not in self.cnn_lookup:
                self.cnn_lookup[cnn] = []
            self.cnn_lookup[cnn].append(row.to_dict())
            cnn_coords[cnn].extend(row['parsed_coords'])
        
        # Calculate centroids
        for cnn, coords_list in cnn_coords.items():
            if coords_list:
                avg_lat = sum(coord[0] for coord in coords_list) / len(coords_list)
                avg_lon = sum(coord[1] for coord in coords_list) / len(coords_list)
                self.cnn_centroids[cnn] = (avg_lat, avg_lon)
        
        # Build grid
        for cnn, (lat, lon) in self.cnn_centroids.items():
            grid_x, grid_y = self.lat_lon_to_grid(lat, lon)
            self.spatial_grid[(grid_x, grid_y)].append(cnn)

    def lat_lon_to_grid(self, lat: float, lon: float) -> Tuple[int, int]:
        """Convert lat/lon to grid coordinates"""
        lat_meters = lat * 111000
        lon_meters = lon * 111000 * 0.794
        grid_x = int(lat_meters / 100)  # 100m grid
        grid_y = int(lon_meters / 100)
        return grid_x, grid_y

    def cnn_match_citation(self, citation_row: pd.Series) -> List[Dict]:
        """Match citation using CNN grid approach"""
        citation_lat = citation_row['latitude']
        citation_lon = citation_row['longitude']
        citation_point = (citation_lat, citation_lon)
        
        # Find nearest CNN
        grid_x, grid_y = self.lat_lon_to_grid(citation_lat, citation_lon)
        
        min_distance = float('inf')
        nearest_cnn = None
        
        for dx in range(-1, 2):
            for dy in range(-1, 2):
                cell = (grid_x + dx, grid_y + dy)
                for cnn in self.spatial_grid.get(cell, []):
                    centroid = self.cnn_centroids[cnn]
                    distance = geodesic(citation_point, centroid).meters
                    if distance < min_distance:
                        min_distance = distance
                        nearest_cnn = cnn
        
        if not nearest_cnn or min_distance > 50:
            return []
        
        # Get schedules for CNN and filter by day
        matches = []
        for schedule in self.cnn_lookup.get(nearest_cnn, []):
            if schedule.get('Tuesday', 0) == 1:
                match = {
                    'method': 'cnn_grid',
                    'schedule_id': schedule['CleanBlockSweepID'],
                    'cnn': schedule['CNN'],
                    'corridor': schedule['Corridor'],
                    'distance_meters': min_distance,
                    'limits': schedule['Limits']
                }
                matches.append(match)
        
        return matches

    def compare_approaches(self):
        """Compare both approaches for accuracy"""
        citations, schedules = self.load_data()
        
        # Build CNN grid
        print("Building CNN grid...")
        self.build_cnn_grid()
        
        print("\n" + "="*80)
        print("ACCURACY COMPARISON")
        print("="*80)
        
        total_citations = 0
        string_matches = 0
        cnn_matches = 0
        both_match = 0
        different_results = 0
        
        for i, (_, citation) in enumerate(citations.iterrows()):
            total_citations += 1
            address = citation['address']
            
            # Get matches from both methods
            string_results = self.string_match_citation(citation)
            cnn_results = self.cnn_match_citation(citation)
            
            string_count = len(string_results)
            cnn_count = len(cnn_results)
            
            if string_count > 0:
                string_matches += 1
            if cnn_count > 0:
                cnn_matches += 1
            if string_count > 0 and cnn_count > 0:
                both_match += 1
            
            # Check if results are different
            string_cnns = {r['cnn'] for r in string_results}
            cnn_cnns = {r['cnn'] for r in cnn_results}
            
            if string_cnns != cnn_cnns:
                different_results += 1
                
                print(f"\nCitation {i+1}: {address}")
                print(f"  String approach: {string_count} matches, CNNs: {sorted(string_cnns)}")
                if string_results:
                    for r in string_results[:2]:  # Show first 2
                        print(f"    - {r['corridor']} (CNN {r['cnn']}, {r['distance_meters']:.1f}m)")
                
                print(f"  CNN Grid approach: {cnn_count} matches, CNNs: {sorted(cnn_cnns)}")
                if cnn_results:
                    for r in cnn_results[:2]:  # Show first 2
                        print(f"    - {r['corridor']} (CNN {r['cnn']}, {r['distance_meters']:.1f}m)")
            else:
                print(f"Citation {i+1}: {address} - Both methods agree ({string_count} matches)")
        
        print(f"\n" + "="*80)
        print("SUMMARY")
        print("="*80)
        print(f"Total citations tested: {total_citations}")
        print(f"String method found matches: {string_matches} ({string_matches/total_citations*100:.1f}%)")
        print(f"CNN Grid method found matches: {cnn_matches} ({cnn_matches/total_citations*100:.1f}%)")
        print(f"Both methods found matches: {both_match} ({both_match/total_citations*100:.1f}%)")
        print(f"Methods gave different results: {different_results} ({different_results/total_citations*100:.1f}%)")
        
        if different_results == 0:
            print("✅ PERFECT AGREEMENT - Both methods are equivalent!")
        elif different_results <= total_citations * 0.1:
            print("✅ GOOD AGREEMENT - Minor differences acceptable")
        else:
            print("⚠️  SIGNIFICANT DIFFERENCES - Need investigation")

def main():
    tester = AccuracyTester()
    tester.compare_approaches()

if __name__ == "__main__":
    main()