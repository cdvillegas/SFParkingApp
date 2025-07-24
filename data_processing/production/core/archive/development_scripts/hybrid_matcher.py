#!/usr/bin/env python3
"""
Hybrid Citation Schedule Matcher
Combines CNN grid spatial lookup with street name validation for speed + accuracy
"""

import pandas as pd
import json
from typing import Dict, List, Tuple, Optional
from geopy.distance import geodesic
import time
from collections import defaultdict
import re

class HybridMatcher:
    def __init__(self, max_distance_meters: float = 200, grid_size_meters: float = 100, grid_search_radius: int = 1):
        self.max_distance_meters = max_distance_meters
        self.grid_size_meters = grid_size_meters
        self.grid_search_radius = grid_search_radius
        self.schedules = None
        self.spatial_grid = defaultdict(list)  # (grid_x, grid_y) -> [schedule_indices]
        
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
        """Extract base street name from address, removing number and type suffix"""
        if not address:
            return ""
        
        # Remove street number from beginning
        match = re.match(r'^\d+\s+(.+)', str(address).strip())
        if match:
            street_with_type = match.group(1)
        else:
            street_with_type = str(address).strip()
        
        street_upper = street_with_type.upper().strip()
        
        # Remove common prefixes (THE, OLD, NEW, etc.)
        prefixes = ['THE ', 'OLD ', 'NEW ']
        for prefix in prefixes:
            if street_upper.startswith(prefix):
                street_upper = street_upper[len(prefix):].strip()
                break
        
        # Remove directional suffixes and prefixes (NORTH, SOUTH, EAST, WEST, etc.)
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
        
        # Remove common street type suffixes
        street_types = [
            'STREET', 'ST', 'AVENUE', 'AVE', 'BOULEVARD', 'BLVD',
            'DRIVE', 'DR', 'COURT', 'CT', 'PLACE', 'PL', 'LANE', 'LN',
            'ROAD', 'RD', 'PARKWAY', 'PKWY', 'CIRCLE', 'CIR', 'TERRACE', 'TER',
            'WAY', 'PLAZA', 'PLZ', 'SQUARE', 'SQ'
        ]
        
        # Try to remove suffix
        for suffix in street_types:
            if street_upper.endswith(' ' + suffix):
                return street_upper[:-len(' ' + suffix)].strip()
            elif street_upper.endswith(suffix) and len(street_upper) > len(suffix):
                return street_upper[:-len(suffix)].strip()
        
        return street_upper

    def lat_lon_to_grid(self, lat: float, lon: float) -> Tuple[int, int]:
        """Convert lat/lon to grid coordinates"""
        lat_meters = lat * 111000
        lon_meters = lon * 111000 * 0.794  # SF longitude adjustment
        grid_x = int(lat_meters / self.grid_size_meters)
        grid_y = int(lon_meters / self.grid_size_meters)
        return grid_x, grid_y

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

    def build_hybrid_index(self, schedule_df: pd.DataFrame):
        """Build spatial grid index and normalize street names"""
        print("Building hybrid spatial grid + street name index...")
        
        # Parse coordinates and normalize street names  
        schedule_df['parsed_coords'] = schedule_df['Line'].apply(self.parse_linestring_coordinates)
        schedule_df['base_corridor'] = schedule_df['Corridor'].apply(self.extract_street_from_address)  # Extract base name
        schedule_df['normalized_corridor'] = schedule_df['base_corridor'].apply(self.normalize_street_name)
        
        # Filter valid schedules
        valid_schedules = schedule_df[schedule_df['parsed_coords'].notna()].copy()
        self.schedules = valid_schedules.reset_index(drop=True)
        
        # Build spatial grid index
        for idx, row in self.schedules.iterrows():
            coords = row['parsed_coords']
            if coords:
                # Use first coordinate as representative point
                lat, lon = coords[0]
                grid_x, grid_y = self.lat_lon_to_grid(lat, lon)
                self.spatial_grid[(grid_x, grid_y)].append(idx)
        
        grid_cells = len(self.spatial_grid)
        avg_schedules_per_cell = len(self.schedules) / grid_cells if grid_cells > 0 else 0
        max_schedules_per_cell = max(len(indices) for indices in self.spatial_grid.values()) if self.spatial_grid else 0
        
        print(f"Built hybrid index:")
        print(f"  - {len(self.schedules)} schedules with coordinates")
        print(f"  - {grid_cells} grid cells")
        print(f"  - Avg {avg_schedules_per_cell:.1f} schedules/cell")
        print(f"  - Max {max_schedules_per_cell} schedules/cell")

    def hybrid_match_citation(self, citation_row: pd.Series) -> List[Dict]:
        """Match citation using hybrid approach: spatial + street name validation"""
        citation_lat = citation_row['latitude']
        citation_lon = citation_row['longitude']
        citation_address = citation_row.get('address', '')
        
        # Extract and normalize citation street name
        citation_street = self.extract_street_from_address(citation_address)
        citation_street_norm = self.normalize_street_name(citation_street)
        
        # Step 1: Spatial filtering using grid
        grid_x, grid_y = self.lat_lon_to_grid(citation_lat, citation_lon)
        
        spatial_candidates = set()
        cells_checked = 0
        
        for dx in range(-self.grid_search_radius, self.grid_search_radius + 1):
            for dy in range(-self.grid_search_radius, self.grid_search_radius + 1):
                cell = (grid_x + dx, grid_y + dy)
                schedule_indices = self.spatial_grid.get(cell, [])
                spatial_candidates.update(schedule_indices)
                if schedule_indices:
                    cells_checked += 1
        
        # Step 2: Street name validation
        street_candidates = []
        if citation_street_norm:
            for idx in spatial_candidates:
                schedule = self.schedules.iloc[idx]
                schedule_street_norm = schedule['normalized_corridor']
                
                # Check if street names match (contains check for flexibility)
                if (citation_street_norm in schedule_street_norm or 
                    schedule_street_norm in citation_street_norm or
                    citation_street_norm == schedule_street_norm):
                    street_candidates.append(idx)
        else:
            # If no street name, use all spatial candidates
            street_candidates = list(spatial_candidates)
        
        # Step 3: Day filtering (extract actual day from citation)
        citation_datetime = citation_row.get('datetime', '2025-06-27T10:00:00')
        try:
            from datetime import datetime
            dt = datetime.fromisoformat(citation_datetime.replace('T', ' '))
            weekday = dt.strftime('%A')
        except:
            weekday = 'Tuesday'  # Fallback
        
        day_candidates = []
        for idx in street_candidates:
            schedule = self.schedules.iloc[idx]
            if schedule.get(weekday, 0) == 1:
                day_candidates.append(idx)
        
        # Step 4: Distance calculation and ranking
        matches = []
        for idx in day_candidates:
            schedule = self.schedules.iloc[idx]
            distance = self.calculate_distance_to_schedule(
                citation_lat, citation_lon, schedule['parsed_coords']
            )
            
            if distance <= self.max_distance_meters:
                match = {
                    'method': 'hybrid',
                    'schedule_id': schedule['CleanBlockSweepID'],
                    'cnn': schedule['CNN'],
                    'corridor': schedule['Corridor'],
                    'distance_meters': distance,
                    'limits': schedule['Limits'],
                    'spatial_candidates': len(spatial_candidates),
                    'street_candidates': len(street_candidates),
                    'day_candidates': len(day_candidates)
                }
                matches.append(match)
        
        # Sort by distance (closest first)
        matches.sort(key=lambda x: x['distance_meters'])
        
        return matches

def test_hybrid_matcher():
    """Test hybrid matching approach"""
    print("Loading test data...")
    
    citations = pd.read_csv('test_citations_small.csv').head(20)
    schedules = pd.read_csv('../output/pipeline_results/20250721_223722/schedule_cleaned_20250721_223722.csv')
    
    print(f"Testing with {len(citations)} citations and {len(schedules)} schedules")
    
    # Build hybrid matcher
    matcher = HybridMatcher(max_distance_meters=200, grid_size_meters=100)
    
    start_time = time.time()
    matcher.build_hybrid_index(schedules)
    build_time = time.time() - start_time
    print(f"Hybrid index build time: {build_time:.2f} seconds")
    
    # Test matching
    print(f"\n{'='*80}")
    print("HYBRID MATCHING RESULTS")
    print(f"{'='*80}")
    
    start_time = time.time()
    total_matches = 0
    total_spatial_candidates = 0
    total_street_candidates = 0
    
    for i, (_, citation) in enumerate(citations.iterrows()):
        matches = matcher.hybrid_match_citation(citation)
        total_matches += len(matches)
        
        address = citation['address']
        
        if matches:
            match = matches[0]  # Best match
            total_spatial_candidates += match['spatial_candidates']
            total_street_candidates += match['street_candidates']
            
            print(f"Citation {i+1}: {address}")
            print(f"  ✅ {len(matches)} matches - Best: {match['corridor']} (CNN {match['cnn']}, {match['distance_meters']:.1f}m)")
            print(f"     Pipeline: {match['spatial_candidates']} spatial → {match['street_candidates']} street → {match['day_candidates']} day → {len(matches)} final")
        else:
            print(f"Citation {i+1}: {address}")
            print(f"  ❌ No matches found")
    
    match_time = time.time() - start_time
    
    print(f"\n{'='*80}")
    print("HYBRID PERFORMANCE SUMMARY")
    print(f"{'='*80}")
    print(f"Matching time: {match_time:.2f} seconds for {len(citations)} citations")
    print(f"Average time per citation: {match_time/len(citations)*1000:.2f}ms")
    print(f"Total matches found: {total_matches}")
    
    if total_matches > 0:
        avg_spatial = total_spatial_candidates / total_matches
        avg_street = total_street_candidates / total_matches
        print(f"Average spatial candidates per match: {avg_spatial:.1f}")
        print(f"Average street candidates per match: {avg_street:.1f}")
        print(f"Spatial filtering efficiency: {(1-avg_spatial/len(schedules))*100:.1f}%")
        print(f"Street filtering efficiency: {(1-avg_street/avg_spatial)*100:.1f}%")
    
    print(f"Projected time for 468K citations: {match_time/len(citations)*468000/60:.1f} minutes")

if __name__ == "__main__":
    test_hybrid_matcher()