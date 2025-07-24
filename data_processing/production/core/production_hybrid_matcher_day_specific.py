#!/usr/bin/env python3
"""
Production Hybrid Citation Schedule Matcher - Day Specific Version
Matches citations to day-specific schedule rows for accurate timing estimates
"""

import pandas as pd
import json
from typing import Dict, List, Tuple, Optional
from geopy.distance import geodesic
import time
from collections import defaultdict
import re
import argparse
import logging
from datetime import datetime
from pathlib import Path

class DaySpecificHybridMatcher:
    def __init__(self, max_distance_meters: float = 200, grid_size_meters: float = 100, grid_search_radius: int = 1, output_dir: str = None):
        self.max_distance_meters = max_distance_meters
        self.grid_size_meters = grid_size_meters
        self.grid_search_radius = grid_search_radius
        self.output_dir = Path(output_dir) if output_dir else Path('.')
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.schedules = None
        self.spatial_grid = defaultdict(list)
        self.setup_logging()
        
    def setup_logging(self):
        """Set up logging"""
        log_format = '%(asctime)s - %(levelname)s - %(message)s'
        log_file = self.output_dir / 'production_day_specific_matching.log'
        logging.basicConfig(
            level=logging.INFO,
            format=log_format,
            handlers=[
                logging.FileHandler(log_file),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
        
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

    def extract_street_from_address(self, address: str) -> str:
        """Extract base street name from address, removing number, directional, and type suffix"""
        if not address:
            return ""
        
        # Remove street number from beginning
        match = re.match(r'^\\d+\\s+(.+)', str(address).strip())
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

    def normalize_street_name(self, street_name: str) -> str:
        """Normalize street name for fuzzy matching"""
        if not street_name:
            return ""
        return str(street_name).upper().replace(' ', '')

    def lat_lon_to_grid(self, lat: float, lon: float) -> Tuple[int, int]:
        """Convert lat/lon to grid coordinates"""
        lat_meters = lat * 111000
        lon_meters = lon * 111000 * 0.794
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
        self.logger.info("Building day-specific hybrid index...")
        
        # Parse coordinates and normalize street names
        self.logger.info("Parsing coordinates and normalizing street names...")
        schedule_df['parsed_coords'] = schedule_df['line'].apply(self.parse_linestring_coordinates)
        schedule_df['base_corridor'] = schedule_df['corridor'].apply(self.extract_street_from_address)
        schedule_df['normalized_corridor'] = schedule_df['base_corridor'].apply(self.normalize_street_name)
        
        # Filter valid schedules
        valid_schedules = schedule_df[schedule_df['parsed_coords'].notna()].copy()
        self.schedules = valid_schedules.reset_index(drop=True)
        
        # Build spatial grid
        self.logger.info("Building spatial grid index...")
        for idx, row in self.schedules.iterrows():
            coords = row['parsed_coords']
            if coords:
                lat, lon = coords[0]
                grid_x, grid_y = self.lat_lon_to_grid(lat, lon)
                self.spatial_grid[(grid_x, grid_y)].append(idx)
        
        grid_cells = len(self.spatial_grid)
        avg_schedules_per_cell = len(self.schedules) / grid_cells if grid_cells > 0 else 0
        max_schedules_per_cell = max(len(indices) for indices in self.spatial_grid.values()) if self.spatial_grid else 0
        
        self.logger.info(f"Day-specific hybrid index built:")
        self.logger.info(f"  - {len(self.schedules)} day-specific schedules with coordinates")
        self.logger.info(f"  - {grid_cells} grid cells")
        self.logger.info(f"  - Avg {avg_schedules_per_cell:.1f} schedules/cell")
        self.logger.info(f"  - Max {max_schedules_per_cell} schedules/cell")

    def hybrid_match_citation(self, citation_row: pd.Series) -> List[Dict]:
        """Match citation using hybrid approach with simplified day matching"""
        citation_lat = citation_row['latitude']
        citation_lon = citation_row['longitude']
        citation_address = citation_row.get('address', '')
        
        # Extract and normalize citation street name
        citation_street = self.extract_street_from_address(citation_address)
        citation_street_norm = self.normalize_street_name(citation_street)
        
        # Step 1: Spatial filtering using grid
        grid_x, grid_y = self.lat_lon_to_grid(citation_lat, citation_lon)
        
        spatial_candidates = set()
        for dx in range(-self.grid_search_radius, self.grid_search_radius + 1):
            for dy in range(-self.grid_search_radius, self.grid_search_radius + 1):
                cell = (grid_x + dx, grid_y + dy)
                schedule_indices = self.spatial_grid.get(cell, [])
                spatial_candidates.update(schedule_indices)
        
        if not spatial_candidates:
            return []
        
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
        
        if not street_candidates:
            return []
        
        # Step 3: SIMPLIFIED Day and time validation
        citation_datetime = citation_row.get('datetime', '2025-06-27T10:00:00')
        try:
            dt = datetime.fromisoformat(citation_datetime.replace('T', ' ').replace('.000', ''))
            citation_time_decimal = dt.hour + dt.minute / 60.0
            citation_weekday = dt.strftime('%A')  # Monday, Tuesday, etc.
        except:
            citation_weekday = 'Tuesday'
            citation_time_decimal = 10.0  # Fallback
        
        day_and_time_candidates = []
        for idx in street_candidates:
            schedule = self.schedules.iloc[idx]
            
            # SIMPLIFIED: Direct string comparison instead of boolean columns
            if schedule['weekday'] == citation_weekday:
                # Check time window match
                from_hour = schedule['scheduled_from_hour']
                to_hour = schedule['scheduled_to_hour']
                if from_hour <= citation_time_decimal <= to_hour:
                    day_and_time_candidates.append(idx)
        
        if not day_and_time_candidates:
            return []
        
        # Step 4: Distance calculation and ranking
        matches = []
        for idx in day_and_time_candidates:
            schedule = self.schedules.iloc[idx]
            distance = self.calculate_distance_to_schedule(
                citation_lat, citation_lon, schedule['parsed_coords']
            )
            
            if distance <= self.max_distance_meters:
                match = {
                    'citation_id': citation_row.get('citation_id', 'unknown'),
                    'schedule_id': schedule['schedule_id'],
                    'cnn': schedule['cnn'],
                    'corridor': schedule['corridor'],
                    'limits': schedule['limits'],
                    'cnn_right_left': schedule['cnn_right_left'],
                    'block_side': schedule['block_side'],
                    'distance_meters': distance,
                    'weekday': citation_weekday,
                    'scheduled_from_hour': schedule['scheduled_from_hour'],
                    'scheduled_to_hour': schedule['scheduled_to_hour'],
                    'citation_time': citation_time_decimal
                }
                matches.append(match)
        
        # Sort by distance (closest first)
        matches.sort(key=lambda x: x['distance_meters'])
        
        return matches

    def process_all_citations(self, citation_df: pd.DataFrame) -> pd.DataFrame:
        """Process all citations and return matches DataFrame"""
        self.logger.info(f"Processing {len(citation_df)} citations with day-specific hybrid matching...")
        
        all_matches = []
        total_citations = len(citation_df)
        start_time = time.time()
        
        for idx, (_, citation_row) in enumerate(citation_df.iterrows()):
            if idx % 25000 == 0:  # Log every 25K citations
                elapsed = time.time() - start_time
                rate = idx / elapsed if elapsed > 0 else 0
                remaining = (total_citations - idx) / rate if rate > 0 else 0
                self.logger.info(f"Processing citation {idx:,}/{total_citations:,} ({rate:.1f}/sec, {remaining/60:.1f}min remaining)")
                
                # Memory optimization: force garbage collection every 25K
                import gc
                gc.collect()
                
            matches = self.hybrid_match_citation(citation_row)
            all_matches.extend(matches)
        
        if not all_matches:
            self.logger.warning("No matches found!")
            return pd.DataFrame()
        
        self.logger.info(f"Found {len(all_matches):,} citation-schedule matches")
        return pd.DataFrame(all_matches)

    def generate_day_specific_estimates(self, matches_df: pd.DataFrame) -> pd.DataFrame:
        """Generate day-specific schedule estimates (LEFT JOIN - all schedules included)"""
        self.logger.info("Generating day-specific schedule estimates...")
        
        # Start with ALL schedules (LEFT JOIN approach)
        schedule_stats = []
        
        # Create a lookup of matches grouped by schedule_id
        matches_lookup = {}
        if not matches_df.empty:
            for schedule_id, group in matches_df.groupby('schedule_id'):
                matches_lookup[schedule_id] = group
        
        # Iterate through ALL schedules in self.schedules
        for idx, schedule_row in self.schedules.iterrows():
            schedule_id = schedule_row['schedule_id']
            
            # Base schedule info (always included)
            stats = {
                'schedule_id': schedule_id,
                'cnn': schedule_row['cnn'],
                'corridor': schedule_row['corridor'],
                'limits': schedule_row['limits'],
                'cnn_right_left': schedule_row['cnn_right_left'],
                'block_side': schedule_row['block_side'],
                'weekday': schedule_row['weekday'],
                'scheduled_from_hour': schedule_row['scheduled_from_hour'],
                'scheduled_to_hour': schedule_row['scheduled_to_hour'],
                'week1': schedule_row['week1'],
                'week2': schedule_row['week2'],
                'week3': schedule_row['week3'],
                'week4': schedule_row['week4'],
                'week5': schedule_row['week5']
            }
            
            # Add citation statistics if matches exist
            if schedule_id in matches_lookup:
                group = matches_lookup[schedule_id]
                stats.update({
                    'citation_count': len(group),
                    'avg_citation_time': group['citation_time'].mean(),
                    'min_citation_time': group['citation_time'].min(),
                    'max_citation_time': group['citation_time'].max()
                })
            else:
                # No matches found - set citation stats to null/zero
                stats.update({
                    'citation_count': 0,
                    'avg_citation_time': None,
                    'min_citation_time': None,
                    'max_citation_time': None
                })
            
            schedule_stats.append(stats)
        
        if not schedule_stats:
            self.logger.warning("No schedules with sufficient citation data!")
            return pd.DataFrame()
        
        self.logger.info(f"Generated {len(schedule_stats)} day-specific schedule estimates")
        return pd.DataFrame(schedule_stats)

    def export_results(self, matches_df: pd.DataFrame, schedules_df: pd.DataFrame, output_prefix: str):
        """Export results to CSV files"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        # Export matches
        matches_file = f"{output_prefix}_matches_{timestamp}.csv"
        matches_df.to_csv(matches_file, index=False)
        self.logger.info(f"Exported {len(matches_df):,} matches to {matches_file}")
        
        # Export schedules
        schedules_file = f"{output_prefix}_schedules_{timestamp}.csv"
        schedules_df.to_csv(schedules_file, index=False)
        self.logger.info(f"Exported {len(schedules_df)} day-specific schedule estimates to {schedules_file}")
        
        return matches_file, schedules_file

def main():
    parser = argparse.ArgumentParser(description='Day-Specific Production Hybrid Citation-Schedule Matcher')
    parser.add_argument('--citation-file', required=True, help='Input citation CSV file')
    parser.add_argument('--schedule-file', required=True, help='Input day-specific schedule CSV file')
    parser.add_argument('--output-prefix', default='day_specific_results', help='Output file prefix')
    parser.add_argument('--max-distance', type=int, default=200, help='Maximum matching distance in meters')
    parser.add_argument('--output-dir', help='Output directory for generated files (logs, etc.)')
    
    args = parser.parse_args()
    
    # Initialize matcher
    matcher = DaySpecificHybridMatcher(max_distance_meters=args.max_distance, output_dir=args.output_dir)
    
    matcher.logger.info("🚀 Starting Day-Specific Production Citation-Schedule Matching")
    matcher.logger.info("=" * 70)
    
    start_time = time.time()
    
    # Load data
    matcher.logger.info(f"Loading citation data from {args.citation_file}")
    citation_df = pd.read_csv(args.citation_file)
    matcher.logger.info(f"Loaded {len(citation_df):,} citations")
    
    matcher.logger.info(f"Loading day-specific schedule data from {args.schedule_file}")
    schedule_df = pd.read_csv(args.schedule_file)
    matcher.logger.info(f"Loaded {len(schedule_df):,} day-specific schedules")
    
    # Build index
    matcher.build_hybrid_index(schedule_df)
    
    # Process citations
    matches_df = matcher.process_all_citations(citation_df)
    
    if matches_df.empty:
        matcher.logger.error("No matches found - analysis cannot continue")
        return
    
    # Generate day-specific estimates
    schedules_df = matcher.generate_day_specific_estimates(matches_df)
    
    # Export results
    matches_file, schedules_file = matcher.export_results(matches_df, schedules_df, args.output_prefix)
    
    # Final summary
    processing_time = time.time() - start_time
    unique_citations = matches_df['citation_id'].nunique()
    
    matcher.logger.info("🎉 Day-specific production processing completed!")
    matcher.logger.info(f"⏱️  Total processing time: {processing_time/60:.1f} minutes")
    matcher.logger.info(f"📊 Citations processed: {len(citation_df):,}")
    matcher.logger.info(f"🎯 Valid matches found: {len(matches_df):,} from {unique_citations:,} citations")
    matcher.logger.info(f"📈 Day-specific schedule estimates: {len(schedules_df):,}")
    matcher.logger.info(f"📁 Results: {matches_file}, {schedules_file}")

if __name__ == "__main__":
    main()