#!/usr/bin/env python3
"""
Match Pattern Analysis
Sample 1K citations and analyze which ones match/don't match with schedules
"""

import pandas as pd
import json
from typing import Dict, List, Tuple, Optional
from geopy.distance import geodesic
import time
from collections import defaultdict, Counter
import re

class MatchAnalyzer:
    def __init__(self, max_distance_meters: float = 50, grid_size_meters: float = 100):
        self.max_distance_meters = max_distance_meters
        self.grid_size_meters = grid_size_meters
        self.schedules = None
        self.spatial_grid = defaultdict(list)
        
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
        """Extract base street name from address, removing number and type suffix"""
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
            'WAY', 'PLAZA', 'PLZ', 'SQUARE', 'SQ', 'HIGHWAY', 'HWY'
        ]
        
        street_upper = street_with_type.upper().strip()
        
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

    def build_index(self, schedule_df: pd.DataFrame):
        """Build spatial grid index and normalize street names"""
        print("Building analysis index...")
        
        # Parse coordinates and normalize street names
        schedule_df['parsed_coords'] = schedule_df['Line'].apply(self.parse_linestring_coordinates)
        schedule_df['base_corridor'] = schedule_df['Corridor'].apply(self.extract_street_from_address)
        schedule_df['normalized_corridor'] = schedule_df['base_corridor'].apply(self.normalize_street_name)
        
        # Filter valid schedules
        valid_schedules = schedule_df[schedule_df['parsed_coords'].notna()].copy()
        self.schedules = valid_schedules.reset_index(drop=True)
        
        # Build spatial grid
        for idx, row in self.schedules.iterrows():
            coords = row['parsed_coords']
            if coords:
                lat, lon = coords[0]
                grid_x, grid_y = self.lat_lon_to_grid(lat, lon)
                self.spatial_grid[(grid_x, grid_y)].append(idx)
        
        print(f"Built index for {len(self.schedules)} schedules")

    def analyze_citation(self, citation_row: pd.Series) -> Dict:
        """Analyze a single citation's matching potential"""
        citation_lat = citation_row['latitude']
        citation_lon = citation_row['longitude']
        citation_address = citation_row.get('address', '')
        citation_id = citation_row.get('citation_id', 'unknown')
        
        # Extract street information
        citation_street = self.extract_street_from_address(citation_address)
        citation_street_norm = self.normalize_street_name(citation_street)
        
        analysis = {
            'citation_id': citation_id,
            'address': citation_address,
            'extracted_street': citation_street,
            'normalized_street': citation_street_norm,
            'lat': citation_lat,
            'lon': citation_lon,
            'spatial_candidates': 0,
            'street_candidates': 0,
            'day_candidates': 0,
            'final_matches': 0,
            'closest_distance': float('inf'),
            'match_found': False,
            'failure_reason': '',
            'nearby_streets': [],
            'schedule_matches': []
        }
        
        # Step 1: Spatial filtering
        grid_x, grid_y = self.lat_lon_to_grid(citation_lat, citation_lon)
        spatial_candidates = set()
        
        for dx in range(-1, 2):
            for dy in range(-1, 2):
                cell = (grid_x + dx, grid_y + dy)
                spatial_candidates.update(self.spatial_grid.get(cell, []))
        
        analysis['spatial_candidates'] = len(spatial_candidates)
        
        if not spatial_candidates:
            analysis['failure_reason'] = 'no_spatial_candidates'
            return analysis
        
        # Collect nearby street names for analysis
        nearby_streets = set()
        street_candidates = []
        
        for idx in spatial_candidates:
            schedule = self.schedules.iloc[idx]
            schedule_street_norm = schedule['normalized_corridor']
            nearby_streets.add((schedule['base_corridor'], schedule_street_norm))
            
            # Check street name match
            if citation_street_norm and (
                citation_street_norm in schedule_street_norm or 
                schedule_street_norm in citation_street_norm or
                citation_street_norm == schedule_street_norm
            ):
                street_candidates.append(idx)
        
        analysis['nearby_streets'] = sorted(list(nearby_streets))
        analysis['street_candidates'] = len(street_candidates)
        
        if not street_candidates:
            analysis['failure_reason'] = 'no_street_match'
            return analysis
        
        # Step 3: Day filtering (mock Tuesday for consistency)
        weekday = 'Tuesday'
        day_candidates = []
        for idx in street_candidates:
            schedule = self.schedules.iloc[idx]
            if schedule.get(weekday, 0) == 1:
                day_candidates.append(idx)
        
        analysis['day_candidates'] = len(day_candidates)
        
        if not day_candidates:
            analysis['failure_reason'] = 'no_day_match'
            return analysis
        
        # Step 4: Distance filtering
        matches = []
        for idx in day_candidates:
            schedule = self.schedules.iloc[idx]
            distance = self.calculate_distance_to_schedule(
                citation_lat, citation_lon, schedule['parsed_coords']
            )
            
            analysis['closest_distance'] = min(analysis['closest_distance'], distance)
            
            if distance <= self.max_distance_meters:
                match_info = {
                    'schedule_id': schedule['CleanBlockSweepID'],
                    'cnn': schedule['CNN'],
                    'corridor': schedule['Corridor'],
                    'distance': distance
                }
                matches.append(match_info)
        
        analysis['final_matches'] = len(matches)
        analysis['schedule_matches'] = matches
        
        if matches:
            analysis['match_found'] = True
        else:
            analysis['failure_reason'] = 'distance_too_far'
        
        return analysis

    def run_sample_analysis(self, sample_size: int = 1000):
        """Run comprehensive analysis on citation sample"""
        print("Loading data for sample analysis...")
        
        # Load data
        citations = pd.read_csv('test_citations_small.csv')
        schedules = pd.read_csv('../output/pipeline_results/20250721_223722/schedule_cleaned_20250721_223722.csv')
        
        # Sample citations
        if len(citations) > sample_size:
            citations = citations.sample(n=sample_size, random_state=42)
        
        print(f"Analyzing {len(citations)} citations against {len(schedules)} schedules")
        
        # Build index
        self.build_index(schedules)
        
        # Analyze each citation
        results = []
        for _, citation in citations.iterrows():
            analysis = self.analyze_citation(citation)
            results.append(analysis)
        
        # Generate comprehensive report
        self.generate_analysis_report(results)
        
        return results

    def generate_analysis_report(self, results: List[Dict]):
        """Generate detailed analysis report"""
        total_citations = len(results)
        
        # Basic statistics
        matches_found = sum(1 for r in results if r['match_found'])
        no_matches = total_citations - matches_found
        
        print(f"\n{'='*80}")
        print(f"COMPREHENSIVE MATCH ANALYSIS - {total_citations} CITATIONS")
        print(f"{'='*80}")
        
        print(f"\n📊 OVERALL STATISTICS:")
        print(f"Total citations analyzed: {total_citations:,}")
        print(f"Citations with matches: {matches_found:,} ({matches_found/total_citations*100:.1f}%)")
        print(f"Citations without matches: {no_matches:,} ({no_matches/total_citations*100:.1f}%)")
        
        # Failure reason analysis
        failure_reasons = Counter(r['failure_reason'] for r in results if not r['match_found'])
        
        print(f"\n❌ FAILURE ANALYSIS ({no_matches} citations):")
        for reason, count in failure_reasons.most_common():
            percentage = count / no_matches * 100
            print(f"  {reason.replace('_', ' ').title():20}: {count:4} ({percentage:.1f}%)")
        
        # Distance analysis
        matched_distances = [r['closest_distance'] for r in results if r['match_found']]
        unmatched_distances = [r['closest_distance'] for r in results if not r['match_found'] and r['closest_distance'] != float('inf')]
        
        if matched_distances:
            print(f"\n📏 DISTANCE ANALYSIS (MATCHED):")
            print(f"  Average distance: {sum(matched_distances)/len(matched_distances):.1f}m")
            print(f"  Median distance: {sorted(matched_distances)[len(matched_distances)//2]:.1f}m")
            print(f"  Max distance: {max(matched_distances):.1f}m")
        
        if unmatched_distances:
            print(f"\n📏 DISTANCE ANALYSIS (UNMATCHED WITH CANDIDATES):")
            print(f"  Average closest distance: {sum(unmatched_distances)/len(unmatched_distances):.1f}m")
            print(f"  Median closest distance: {sorted(unmatched_distances)[len(unmatched_distances)//2]:.1f}m")
            print(f"  Min closest distance: {min(unmatched_distances):.1f}m")
        
        # Street name pattern analysis
        unmatched_no_street = [r for r in results if r['failure_reason'] == 'no_street_match']
        
        if unmatched_no_street:
            print(f"\n🛣️  STREET NAME MISMATCH ANALYSIS ({len(unmatched_no_street)} citations):")
            
            # Most common citation streets that don't match
            citation_streets = Counter(r['normalized_street'] for r in unmatched_no_street if r['normalized_street'])
            print(f"\n  Most common unmatched citation streets:")
            for street, count in citation_streets.most_common(10):
                print(f"    {street:30}: {count} citations")
            
            # Sample nearby streets for manual inspection
            print(f"\n  Sample nearby streets (first 10 cases):")
            for i, r in enumerate(unmatched_no_street[:10]):
                if r['nearby_streets']:
                    nearby = [street[0] for street in r['nearby_streets'][:5]]  # First 5 nearby streets
                    print(f"    Citation '{r['extracted_street']}' near: {', '.join(nearby)}")
        
        # Pipeline efficiency analysis
        spatial_candidates = [r['spatial_candidates'] for r in results if r['spatial_candidates'] > 0]
        street_candidates = [r['street_candidates'] for r in results if r['street_candidates'] > 0]
        
        if spatial_candidates:
            print(f"\n⚡ PIPELINE EFFICIENCY:")
            avg_spatial = sum(spatial_candidates) / len(spatial_candidates)
            print(f"  Average spatial candidates: {avg_spatial:.1f}")
            print(f"  Spatial filtering efficiency: {(1 - avg_spatial/len(self.schedules))*100:.1f}%")
        
        if street_candidates:
            avg_street = sum(street_candidates) / len(street_candidates)
            print(f"  Average street candidates: {avg_street:.1f}")
            if spatial_candidates:
                print(f"  Street filtering efficiency: {(1 - avg_street/avg_spatial)*100:.1f}%")
        
        # Detailed failure case examples
        print(f"\n🔍 DETAILED FAILURE EXAMPLES:")
        
        failure_examples = {
            'no_spatial_candidates': 3,
            'no_street_match': 5,
            'no_day_match': 3,
            'distance_too_far': 3
        }
        
        for reason, max_examples in failure_examples.items():
            examples = [r for r in results if r['failure_reason'] == reason][:max_examples]
            if examples:
                print(f"\n  {reason.replace('_', ' ').title()} Examples:")
                for r in examples:
                    print(f"    📍 {r['address']} (Street: '{r['extracted_street']}')")
                    if r['nearby_streets'] and reason == 'no_street_match':
                        nearby = [s[0] for s in r['nearby_streets'][:3]]
                        print(f"       Nearby: {', '.join(nearby)}")
                    if r['closest_distance'] != float('inf'):
                        print(f"       Closest distance: {r['closest_distance']:.1f}m")

def main():
    analyzer = MatchAnalyzer(max_distance_meters=50)
    results = analyzer.run_sample_analysis(sample_size=1000)
    
    # Save detailed results for further analysis
    import json
    with open('match_analysis_results.json', 'w') as f:
        json.dump(results, f, indent=2, default=str)
    print(f"\n💾 Detailed results saved to: match_analysis_results.json")

if __name__ == "__main__":
    main()