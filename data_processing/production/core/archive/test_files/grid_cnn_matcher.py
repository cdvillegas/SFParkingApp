#!/usr/bin/env python3
"""
Grid-Based CNN Citation Schedule Matcher
Uses spatial grid index for ultra-fast CNN lookup
"""

import pandas as pd
import numpy as np
import json
from typing import Dict, List, Tuple, Optional
from geopy.distance import geodesic
import time
from collections import defaultdict

class GridCNNMatcher:
    def __init__(self, max_distance_meters: float = 50, grid_size_meters: float = 100):
        self.max_distance_meters = max_distance_meters
        self.grid_size_meters = grid_size_meters
        self.cnn_lookup = {}  # CNN -> [schedules]
        self.cnn_centroids = {}  # CNN -> (lat, lon)
        self.spatial_grid = defaultdict(list)  # (grid_x, grid_y) -> [cnn_list]
        
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

    def lat_lon_to_grid(self, lat: float, lon: float) -> Tuple[int, int]:
        """Convert lat/lon to grid cell coordinates"""
        # Convert to approximate meters (rough conversion for SF)
        # SF is around 37.77°N, 122.42°W
        lat_meters = lat * 111000  # 1 degree lat ≈ 111km
        lon_meters = lon * 111000 * 0.794  # Adjust for SF longitude (cos(37.77°) ≈ 0.794)
        
        grid_x = int(lat_meters / self.grid_size_meters)
        grid_y = int(lon_meters / self.grid_size_meters)
        
        return grid_x, grid_y

    def build_cnn_lookup_and_grid(self, schedule_df: pd.DataFrame):
        """Build CNN lookup and spatial grid index"""
        print("Building CNN lookup and spatial grid...")
        
        # Parse coordinates for all schedules
        schedule_df['parsed_coords'] = schedule_df['Line'].apply(self.parse_linestring_coordinates)
        valid_schedules = schedule_df[schedule_df['parsed_coords'].notna()].copy()
        
        # Group schedules by CNN and calculate centroids
        cnn_coords = defaultdict(list)
        
        for _, row in valid_schedules.iterrows():
            cnn = row['CNN']
            coords = row['parsed_coords']
            
            # Add schedule to CNN lookup
            if cnn not in self.cnn_lookup:
                self.cnn_lookup[cnn] = []
            self.cnn_lookup[cnn].append(row.to_dict())
            
            # Collect all coordinates for this CNN
            cnn_coords[cnn].extend(coords)
        
        # Calculate centroid for each CNN
        for cnn, coords_list in cnn_coords.items():
            if coords_list:
                avg_lat = sum(coord[0] for coord in coords_list) / len(coords_list)
                avg_lon = sum(coord[1] for coord in coords_list) / len(coords_list)
                self.cnn_centroids[cnn] = (avg_lat, avg_lon)
        
        # Build spatial grid index
        for cnn, (lat, lon) in self.cnn_centroids.items():
            grid_x, grid_y = self.lat_lon_to_grid(lat, lon)
            self.spatial_grid[(grid_x, grid_y)].append(cnn)
        
        # Print statistics
        total_cells = len(self.spatial_grid)
        avg_cnns_per_cell = sum(len(cnns) for cnns in self.spatial_grid.values()) / total_cells
        max_cnns_per_cell = max(len(cnns) for cnns in self.spatial_grid.values())
        
        print(f"Built lookup for {len(self.cnn_lookup)} CNNs with {len(valid_schedules)} schedules")
        print(f"Created spatial grid: {total_cells} cells, avg {avg_cnns_per_cell:.1f} CNNs/cell, max {max_cnns_per_cell} CNNs/cell")
        
    def find_nearest_cnn_grid(self, citation_lat: float, citation_lon: float) -> Optional[int]:
        """Find nearest CNN using grid-based spatial lookup"""
        citation_point = (citation_lat, citation_lon)
        grid_x, grid_y = self.lat_lon_to_grid(citation_lat, citation_lon)
        
        min_distance = float('inf')
        nearest_cnn = None
        
        # Check primary cell and adjacent cells (3x3 grid around citation)
        search_radius = 1  # Check adjacent cells
        cells_checked = 0
        cnns_checked = 0
        
        for dx in range(-search_radius, search_radius + 1):
            for dy in range(-search_radius, search_radius + 1):
                cell = (grid_x + dx, grid_y + dy)
                candidate_cnns = self.spatial_grid.get(cell, [])
                cells_checked += 1
                cnns_checked += len(candidate_cnns)
                
                for cnn in candidate_cnns:
                    centroid = self.cnn_centroids[cnn]
                    distance = geodesic(citation_point, centroid).meters
                    if distance < min_distance:
                        min_distance = distance
                        nearest_cnn = cnn
        
        # Debug info for first few lookups
        if hasattr(self, 'lookup_count'):
            self.lookup_count += 1
        else:
            self.lookup_count = 1
            
        if self.lookup_count <= 5:
            print(f"  Lookup {self.lookup_count}: Checked {cells_checked} cells, {cnns_checked} CNNs, found CNN {nearest_cnn} at {min_distance:.1f}m")
                    
        return nearest_cnn if min_distance <= self.max_distance_meters else None
    
    def match_citation_to_schedules_grid(self, citation_row: pd.Series) -> List[Dict]:
        """Match citation to schedules using grid-based CNN lookup"""
        citation_lat = citation_row['latitude']
        citation_lon = citation_row['longitude']
        
        # Find nearest CNN using grid
        nearest_cnn = self.find_nearest_cnn_grid(citation_lat, citation_lon)
        if not nearest_cnn:
            return []
        
        # Get all schedules for this CNN
        cnn_schedules = self.cnn_lookup.get(nearest_cnn, [])
        
        # Extract day from citation datetime (mock for now)
        # citation_datetime = citation_row.get('datetime', '2025-06-27T10:00:00')
        # weekday = datetime.fromisoformat(citation_datetime.replace('T', ' ')).strftime('%A')
        weekday = 'Tuesday'  # Mock for testing
        
        matches = []
        for schedule in cnn_schedules:
            # Check if schedule is active on citation day
            if schedule.get(weekday, 0) == 1:
                match = {
                    'citation_id': citation_row.get('citation_id', 'unknown'),
                    'schedule_id': schedule['CleanBlockSweepID'],
                    'cnn': nearest_cnn,
                    'distance_meters': 0,  # Exact CNN match
                    'corridor': schedule['Corridor'],
                    'limits': schedule['Limits'],
                    'weekday': weekday
                }
                matches.append(match)
        
        return matches

def test_grid_cnn_matcher():
    """Test grid-based CNN matching performance"""
    print("Loading test data...")
    
    # Load test datasets
    citations = pd.read_csv('test_citations_small.csv').head(50)  # Smaller test for speed
    schedules = pd.read_csv('../output/pipeline_results/20250721_223722/schedule_cleaned_20250721_223722.csv')
    
    print(f"Testing with {len(citations)} citations and {len(schedules)} schedules")
    
    # Build grid-based CNN matcher
    matcher = GridCNNMatcher(max_distance_meters=50, grid_size_meters=100)
    
    start_time = time.time()
    matcher.build_cnn_lookup_and_grid(schedules)
    build_time = time.time() - start_time
    print(f"Grid build time: {build_time:.2f} seconds")
    
    # Test matching performance
    start_time = time.time()
    total_matches = 0
    
    for i, (_, citation) in enumerate(citations.iterrows()):
        matches = matcher.match_citation_to_schedules_grid(citation)
        total_matches += len(matches)
        
        if i < 10:  # Show first 10
            print(f"Citation {i+1} ({citation['address']}): {len(matches)} matches")
    
    match_time = time.time() - start_time
    citations_processed = len(citations)
    
    print(f"\nGrid-based matching results:")
    print(f"Matching time: {match_time:.2f} seconds for {citations_processed} citations")
    print(f"Average time per citation: {match_time/citations_processed*1000:.2f}ms")
    print(f"Total matches found: {total_matches}")
    print(f"Projected time for 468K citations: {match_time/citations_processed*468000/60:.1f} minutes")
    
    # Compare with theoretical performance
    print(f"\nPerformance analysis:")
    print(f"Average CNNs checked per lookup: ~9 (3x3 grid)")
    print(f"Speedup vs full CNN search: {11965/9:.0f}x")

if __name__ == "__main__":
    test_grid_cnn_matcher()