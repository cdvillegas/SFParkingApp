#!/usr/bin/env python3
"""
CNN-based Citation Schedule Matcher
Much faster approach using CNN (Centerline Network Number) spatial lookup
"""

import pandas as pd
import numpy as np
import json
from typing import Dict, List, Tuple, Optional
from geopy.distance import geodesic
import time

class CNNBasedMatcher:
    def __init__(self, max_distance_meters: float = 100):
        self.max_distance_meters = max_distance_meters
        self.cnn_lookup = {}  # CNN -> [schedules]
        self.cnn_coordinates = {}  # CNN -> [(lat, lon), ...]
        
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

    def build_cnn_lookup(self, schedule_df: pd.DataFrame):
        """Build CNN -> schedules and CNN -> coordinates lookup tables"""
        print("Building CNN lookup tables...")
        
        # Parse coordinates for all schedules
        schedule_df['parsed_coords'] = schedule_df['Line'].apply(self.parse_linestring_coordinates)
        valid_schedules = schedule_df[schedule_df['parsed_coords'].notna()].copy()
        
        # Group schedules by CNN
        for _, row in valid_schedules.iterrows():
            cnn = row['CNN']
            coords = row['parsed_coords']
            
            # Add schedule to CNN lookup
            if cnn not in self.cnn_lookup:
                self.cnn_lookup[cnn] = []
            self.cnn_lookup[cnn].append(row.to_dict())
            
            # Add coordinates to CNN spatial lookup
            if cnn not in self.cnn_coordinates:
                self.cnn_coordinates[cnn] = []
            self.cnn_coordinates[cnn].extend(coords)
        
        # Calculate centroid for each CNN for faster spatial lookup
        self.cnn_centroids = {}
        for cnn, coords_list in self.cnn_coordinates.items():
            if coords_list:
                avg_lat = sum(coord[0] for coord in coords_list) / len(coords_list)
                avg_lon = sum(coord[1] for coord in coords_list) / len(coords_list)
                self.cnn_centroids[cnn] = (avg_lat, avg_lon)
        
        print(f"Built lookup for {len(self.cnn_lookup)} CNNs with {len(valid_schedules)} schedules")
        
    def find_nearest_cnn(self, citation_lat: float, citation_lon: float) -> Optional[int]:
        """Find the nearest CNN to a citation using centroid-based spatial lookup"""
        citation_point = (citation_lat, citation_lon)
        
        min_distance = float('inf')
        nearest_cnn = None
        
        # First pass: check centroids for rough proximity
        candidate_cnns = []
        for cnn, centroid in self.cnn_centroids.items():
            distance = geodesic(citation_point, centroid).meters
            if distance <= self.max_distance_meters * 2:  # Broader search first
                candidate_cnns.append((cnn, distance))
        
        # Sort by centroid distance and check detailed coordinates for top candidates
        candidate_cnns.sort(key=lambda x: x[1])
        
        for cnn, _ in candidate_cnns[:10]:  # Check top 10 closest CNNs
            coords_list = self.cnn_coordinates.get(cnn, [])
            for coord in coords_list:
                distance = geodesic(citation_point, coord).meters
                if distance < min_distance:
                    min_distance = distance
                    nearest_cnn = cnn
                    
        return nearest_cnn if min_distance <= self.max_distance_meters else None
    
    def match_citation_to_schedules_cnn(self, citation_row: pd.Series) -> List[Dict]:
        """Match citation to schedules using CNN lookup"""
        citation_lat = citation_row['latitude']
        citation_lon = citation_row['longitude']
        
        # Find nearest CNN
        nearest_cnn = self.find_nearest_cnn(citation_lat, citation_lon)
        if not nearest_cnn:
            return []
        
        # Get all schedules for this CNN
        cnn_schedules = self.cnn_lookup.get(nearest_cnn, [])
        
        # Filter by day (same as before)
        citation_weekday = 'Tuesday'  # Mock for now - extract from citation datetime
        matches = []
        
        for schedule in cnn_schedules:
            # Check if schedule is active on citation day
            day_column = citation_weekday
            if schedule.get(day_column, 0) == 1:
                match = {
                    'citation_id': citation_row.get('citation_id', 'unknown'),
                    'schedule_id': schedule['CleanBlockSweepID'],
                    'cnn': nearest_cnn,
                    'distance_meters': 0,  # Exact CNN match
                    'corridor': schedule['Corridor'],
                    'limits': schedule['Limits']
                }
                matches.append(match)
        
        return matches

def test_cnn_matcher():
    """Test CNN-based matching performance"""
    print("Loading test data...")
    
    # Load small test datasets
    citations = pd.read_csv('test_citations_small.csv').head(100)
    schedules = pd.read_csv('../output/pipeline_results/20250721_223722/schedule_cleaned_20250721_223722.csv')
    
    print(f"Testing with {len(citations)} citations and {len(schedules)} schedules")
    
    # Build CNN matcher
    matcher = CNNBasedMatcher(max_distance_meters=50)
    
    start_time = time.time()
    matcher.build_cnn_lookup(schedules)
    build_time = time.time() - start_time
    print(f"CNN lookup build time: {build_time:.2f} seconds")
    
    # Test matching performance
    start_time = time.time()
    total_matches = 0
    
    for i, (_, citation) in enumerate(citations.iterrows()):
        matches = matcher.match_citation_to_schedules_cnn(citation)
        total_matches += len(matches)
        
        if i < 10:  # Show first 10
            print(f"Citation {i+1} ({citation['address']}): {len(matches)} matches")
    
    match_time = time.time() - start_time
    print(f"\nMatching time: {match_time:.2f} seconds for {len(citations)} citations")
    print(f"Average time per citation: {match_time/len(citations)*1000:.2f}ms")
    print(f"Total matches found: {total_matches}")
    print(f"Projected time for 468K citations: {match_time/len(citations)*468000/60:.1f} minutes")

if __name__ == "__main__":
    test_cnn_matcher()