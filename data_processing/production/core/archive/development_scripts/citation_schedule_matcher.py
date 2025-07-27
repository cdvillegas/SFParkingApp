#!/usr/bin/env python3
"""
Citation Schedule Matcher

Joins processed citation GPS data with cleaned schedule data to calculate
estimated citation times (when sweepers arrive) for each block schedule.

This creates a comprehensive dataset for predicting actual sweeper arrival times
based on historical citation patterns.

Usage:
python3 citation_schedule_matcher.py --citation-file processed_citations.csv --schedule-file Street_Sweeping_Schedule_Cleaned_Simple.csv
"""

import pandas as pd
import numpy as np
import sqlite3
import argparse
import logging
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import re
from geopy.distance import geodesic
import json

class CitationScheduleMatcher:
    def __init__(self, max_distance_meters: int = 50):
        """
        Initialize the matcher
        
        Args:
            max_distance_meters: Maximum distance to match citations to schedules
        """
        self.max_distance_meters = max_distance_meters
        self.setup_logging()
        
    def setup_logging(self):
        """Set up logging"""
        log_format = '%(asctime)s - %(levelname)s - %(message)s'
        logging.basicConfig(
            level=logging.INFO,
            format=log_format,
            handlers=[
                logging.FileHandler('citation_schedule_matching.log'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
        
    def load_citation_data(self, citation_file: str) -> pd.DataFrame:
        """Load processed citation data"""
        self.logger.info(f"Loading citation data from {citation_file}")
        
        df = pd.read_csv(citation_file)
        
        # Filter for high/medium confidence only
        df = df[df['confidence'].isin(['HIGH', 'MEDIUM'])].copy()
        
        # Parse datetime
        df['citation_datetime'] = pd.to_datetime(df['datetime'])
        df['citation_date'] = df['citation_datetime'].dt.date
        df['citation_hour'] = df['citation_datetime'].dt.hour
        df['citation_minute'] = df['citation_datetime'].dt.minute
        df['citation_weekday'] = df['citation_datetime'].dt.day_name()
        
        self.logger.info(f"Loaded {len(df)} high/medium confidence citations")
        return df
        
    def load_schedule_data(self, schedule_file: str) -> pd.DataFrame:
        """Load cleaned schedule data"""
        self.logger.info(f"Loading schedule data from {schedule_file}")
        
        df = pd.read_csv(schedule_file)
        
        # Parse GPS coordinates from LINESTRING
        df['schedule_coordinates'] = df['Line'].apply(self.parse_linestring_coordinates)
        
        # Filter out schedules without coordinates
        df = df[df['schedule_coordinates'].notna()].copy()
        
        # Pre-compute normalized street names for faster matching
        df['normalized_corridor'] = df['Corridor'].apply(self.normalize_street_name)
        
        self.logger.info(f"Loaded {len(df)} schedules with GPS coordinates")
        return df
        
    def parse_linestring_coordinates(self, linestring: str) -> Optional[List[Tuple[float, float]]]:
        """Parse LINESTRING (WKT or GeoJSON format) to extract GPS coordinates"""
        if pd.isna(linestring) or not linestring.strip():
            return None
            
        try:
            # First try GeoJSON format (our current data format)
            if linestring.startswith("{'type':") or linestring.startswith('{"type":'):
                # Parse GeoJSON
                geojson_data = eval(linestring) if linestring.startswith("{'") else json.loads(linestring)
                if geojson_data.get('type') == 'LineString':
                    coordinates = []
                    for coord in geojson_data.get('coordinates', []):
                        lon, lat = coord[0], coord[1]  # GeoJSON is [lon, lat]
                        coordinates.append((lat, lon))  # Return as (lat, lon) for consistency
                    return coordinates if coordinates else None
            
            # Fallback to WKT format
            else:
                # Remove LINESTRING wrapper and parentheses
                coords_str = linestring.replace('LINESTRING', '').strip('() ')
                
                # Split coordinate pairs
                coord_pairs = coords_str.split(', ')
                
                coordinates = []
                for pair in coord_pairs:
                    lon, lat = map(float, pair.split())
                    coordinates.append((lat, lon))  # Return as (lat, lon) for consistency
                    
                return coordinates if coordinates else None
                
        except Exception as e:
            return None
            
    def calculate_distance_to_schedule(self, citation_lat: float, citation_lon: float, 
                                     schedule_coordinates: List[Tuple[float, float]]) -> float:
        """Calculate minimum distance from citation point to schedule line segments"""
        if not schedule_coordinates:
            return float('inf')
            
        min_distance = float('inf')
        citation_point = (citation_lat, citation_lon)
        
        # Calculate distance to each line segment
        for i in range(len(schedule_coordinates) - 1):
            p1 = schedule_coordinates[i]
            p2 = schedule_coordinates[i + 1]
            
            # Calculate distance from point to line segment
            segment_distance = self._point_to_line_segment_distance(citation_point, p1, p2)
            min_distance = min(min_distance, segment_distance)
        
        # Also check distance to endpoints (in case of single point)
        if len(schedule_coordinates) == 1:
            distance = geodesic(citation_point, schedule_coordinates[0]).meters
            min_distance = min(min_distance, distance)
            
        return min_distance
    
    def _point_to_line_segment_distance(self, point: Tuple[float, float], 
                                      line_start: Tuple[float, float], 
                                      line_end: Tuple[float, float]) -> float:
        """Calculate shortest distance from point to line segment using proper geometry"""
        # Convert to radians for calculation
        import math
        
        # If line segment is actually a point
        if line_start == line_end:
            return geodesic(point, line_start).meters
        
        # Calculate the perpendicular distance to the infinite line
        # Then check if the perpendicular point lies on the segment
        
        # Use simple approach: distance to line endpoints and interpolated points
        # This is more accurate than just endpoint distance
        distances = []
        
        # Distance to endpoints
        distances.append(geodesic(point, line_start).meters)
        distances.append(geodesic(point, line_end).meters)
        
        # Check several points along the line segment
        for t in [0.25, 0.5, 0.75]:  # 25%, 50%, 75% along the segment
            interp_lat = line_start[0] + t * (line_end[0] - line_start[0])
            interp_lon = line_start[1] + t * (line_end[1] - line_start[1])
            interp_point = (interp_lat, interp_lon)
            distances.append(geodesic(point, interp_point).meters)
        
        return min(distances)
        
    def normalize_street_name(self, street_name: str) -> str:
        """Normalize street name for fuzzy matching"""
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

    def extract_street_from_address(self, address: str) -> str:
        """Extract street name from full address"""
        if not address:
            return ""
        
        # Remove street number from beginning
        import re
        # Match pattern like "123 MAIN ST" -> "MAIN ST"
        match = re.match(r'^\d+\s+(.+)', str(address).strip())
        if match:
            return match.group(1)
        return str(address).strip()

    def match_citation_to_schedules(self, citation_row: pd.Series, 
                                  schedule_df: pd.DataFrame, 
                                  strict_timing: bool = True) -> List[Dict]:
        """Match a single citation to relevant schedules with pre-filtering"""
        citation_lat = citation_row['latitude']
        citation_lon = citation_row['longitude']
        citation_weekday = citation_row['citation_weekday']
        citation_hour = citation_row['citation_hour']
        
        # Extract and normalize citation street name
        citation_address = citation_row.get('citation_location', '')
        citation_street = self.extract_street_from_address(citation_address)
        citation_street_norm = self.normalize_street_name(citation_street)
        
        matches = []
        
        # Pre-filter 1: Street name fuzzy matching (using pre-computed normalized names)
        if citation_street_norm:
            # Find schedules with matching street names (exact or partial)
            street_matches = schedule_df[
                schedule_df['normalized_corridor'].str.contains(citation_street_norm, na=False) |
                (citation_street_norm in schedule_df['normalized_corridor'].astype(str))
            ].copy()
            
            # If no street matches, return empty
            if street_matches.empty:
                return matches
        else:
            street_matches = schedule_df.copy()
        
        # Pre-filter 2: schedules active on the citation day  
        day_column_map = {
            'Monday': 'Monday', 'Tuesday': 'Tuesday', 'Wednesday': 'Wednesday',
            'Thursday': 'Thursday', 'Friday': 'Friday', 'Saturday': 'Saturday', 'Sunday': 'Sunday'
        }
        
        if citation_weekday in day_column_map:
            day_schedules = street_matches[street_matches[day_column_map[citation_weekday]] == 1].copy()
        else:
            return matches
            
        if day_schedules.empty:
            return matches
            
        # Second filter: temporal matching (if strict_timing enabled)
        if strict_timing:
            # Only include schedules where citation occurs during scheduled sweeping hours
            day_schedules = day_schedules[
                (day_schedules['FromHour'] <= citation_hour) & 
                (citation_hour <= day_schedules['ToHour'])
            ].copy()
            
            if day_schedules.empty:
                return matches
            
        # Calculate distances to all day+time matching schedules
        day_schedules['distance_meters'] = day_schedules['schedule_coordinates'].apply(
            lambda coords: self.calculate_distance_to_schedule(citation_lat, citation_lon, coords)
        )
        
        # Third filter: distance threshold
        nearby_schedules = day_schedules[day_schedules['distance_meters'] <= self.max_distance_meters]
        
        # Create match records
        for _, schedule_row in nearby_schedules.iterrows():
            from_hour = schedule_row['FromHour']
            to_hour = schedule_row['ToHour']
            
            # Calculate time relevance (for analysis purposes)
            time_relevance = self.calculate_time_relevance(citation_hour, from_hour, to_hour)
            
            match = {
                'citation_id': citation_row['citation_id'],
                'schedule_id': schedule_row['CleanBlockSweepID'],
                'distance_meters': schedule_row['distance_meters'],
                'citation_hour': citation_hour,
                'schedule_from_hour': from_hour,
                'schedule_to_hour': to_hour,
                'time_relevance': time_relevance,
                'corridor': schedule_row['Corridor'],
                'limits': schedule_row['Limits'],
                'citation_confidence': citation_row['confidence'],
                'citation_datetime': citation_row['citation_datetime'],
                'citation_date': citation_row['citation_date']
            }
            
            matches.append(match)
            
        return matches
        
    def calculate_time_relevance(self, citation_hour: int, from_hour: int, to_hour: int) -> str:
        """Determine temporal relevance of citation to schedule"""
        if from_hour <= citation_hour <= to_hour:
            return "DURING_SCHEDULE"
        elif citation_hour > to_hour and citation_hour <= to_hour + 2:
            return "AFTER_SCHEDULE"  # Within 2 hours after - likely enforcement
        elif citation_hour < from_hour and citation_hour >= from_hour - 1:
            return "BEFORE_SCHEDULE"  # Up to 1 hour before - early enforcement
        else:
            return "OUTSIDE_SCHEDULE"
            
    def process_all_matches(self, citation_df: pd.DataFrame, 
                           schedule_df: pd.DataFrame, 
                           strict_timing: bool = True) -> pd.DataFrame:
        """Process all citations and find matches with schedules"""
        timing_mode = "strict timing" if strict_timing else "flexible timing"
        self.logger.info(f"Processing citation-schedule matches with {timing_mode}...")
        
        all_matches = []
        total_citations = len(citation_df)
        
        for idx, (_, citation_row) in enumerate(citation_df.iterrows()):
            if idx % 10000 == 0:
                self.logger.info(f"Processing citation {idx}/{total_citations}")
                
            matches = self.match_citation_to_schedules(citation_row, schedule_df, strict_timing)
            all_matches.extend(matches)
            
        if not all_matches:
            self.logger.warning("No matches found!")
            return pd.DataFrame()
            
        matches_df = pd.DataFrame(all_matches)
        self.logger.info(f"Found {len(matches_df)} citation-schedule matches")
        
        return matches_df
        
    def calculate_estimated_citation_times(self, matches_df: pd.DataFrame) -> pd.DataFrame:
        """Calculate estimated citation times for each schedule based on historical data"""
        self.logger.info("Calculating estimated citation times per schedule...")
        
        # Group by schedule and analyze citation patterns
        schedule_stats = []
        
        for schedule_id, group in matches_df.groupby('schedule_id'):
            # With strict timing, we prioritize DURING_SCHEDULE citations
            during_schedule_matches = group[group['time_relevance'] == 'DURING_SCHEDULE']
            
            # Use DURING_SCHEDULE if available, otherwise fall back to broader relevance
            if len(during_schedule_matches) >= 3:
                relevant_matches = during_schedule_matches
            else:
                # Fall back to including AFTER_SCHEDULE for more data
                relevant_matches = group[group['time_relevance'].isin(['DURING_SCHEDULE', 'AFTER_SCHEDULE'])]
                
            if len(relevant_matches) < 3:  # Need at least 3 citations for statistics
                continue
                
            citation_hours = relevant_matches['citation_hour'].values
            
            # Calculate statistics
            stats = {
                'schedule_id': schedule_id,
                'corridor': group['corridor'].iloc[0],
                'limits': group['limits'].iloc[0],
                'schedule_from_hour': group['schedule_from_hour'].iloc[0],
                'schedule_to_hour': group['schedule_to_hour'].iloc[0],
                'total_citations': len(group),
                'citation_count': len(relevant_matches),
                'min_citation_time': np.min(citation_hours),
                'max_citation_time': np.max(citation_hours),
                'avg_citation_time': np.mean(citation_hours),
                'median_citation_time': np.median(citation_hours),
                'citation_dates': list(relevant_matches['citation_date'].unique()),
                'avg_distance_meters': np.mean(relevant_matches['distance_meters'])
            }
            
            schedule_stats.append(stats)
            
        if not schedule_stats:
            self.logger.warning("No schedules with sufficient citation data!")
            return pd.DataFrame()
            
        stats_df = pd.DataFrame(schedule_stats)
        self.logger.info(f"Generated estimates for {len(stats_df)} schedules")
        
        return stats_df
        
    def export_comprehensive_dataset(self, matches_df: pd.DataFrame, 
                                   estimates_df: pd.DataFrame,
                                   output_prefix: str):
        """Export comprehensive datasets for analysis"""
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        
        # 1. Raw matches
        matches_file = f"{output_prefix}_matches_{timestamp}.csv"
        matches_df.to_csv(matches_file, index=False)
        self.logger.info(f"Exported {len(matches_df)} matches to {matches_file}")
        
        # 2. Estimated sweeper times
        estimates_file = f"{output_prefix}_estimates_{timestamp}.csv"
        estimates_df.to_csv(estimates_file, index=False)
        self.logger.info(f"Exported {len(estimates_df)} estimates to {estimates_file}")
        
        # 3. Summary report
        report = self.generate_analysis_report(matches_df, estimates_df)
        report_file = f"{output_prefix}_analysis_report_{timestamp}.json"
        with open(report_file, 'w') as f:
            json.dump(report, f, indent=2, default=str)
        self.logger.info(f"Exported analysis report to {report_file}")
        
        return {
            'matches_file': matches_file,
            'estimates_file': estimates_file,
            'report_file': report_file
        }
        
    def generate_analysis_report(self, matches_df: pd.DataFrame, 
                               estimates_df: pd.DataFrame) -> Dict:
        """Generate comprehensive analysis report"""
        
        if matches_df.empty or estimates_df.empty:
            return {
                'error': 'Insufficient data for analysis',
                'matches_count': len(matches_df),
                'estimates_count': len(estimates_df)
            }
            
        # Citation pattern analysis
        time_relevance_counts = matches_df['time_relevance'].value_counts().to_dict()
        
        # Distance analysis
        distance_stats = {
            'avg_match_distance_meters': matches_df['distance_meters'].mean(),
            'median_match_distance_meters': matches_df['distance_meters'].median(),
            'max_match_distance_meters': matches_df['distance_meters'].max(),
            'within_25m_percent': (matches_df['distance_meters'] <= 25).mean() * 100,
            'within_50m_percent': (matches_df['distance_meters'] <= 50).mean() * 100
        }
        
        # Schedule coverage analysis
        unique_schedules_with_citations = matches_df['schedule_id'].nunique()
        schedules_with_estimates = len(estimates_df)
        
        # Confidence analysis
        confidence_dist = estimates_df['confidence_level'].value_counts().to_dict()
        
        # Temporal analysis
        hour_analysis = {
            'avg_estimated_sweeper_hour': estimates_df['estimated_sweeper_arrival_hour'].mean(),
            'earliest_sweeper_estimate': estimates_df['estimated_sweeper_arrival_hour'].min(),
            'latest_sweeper_estimate': estimates_df['estimated_sweeper_arrival_hour'].max(),
            'citation_hour_range': {
                'earliest': matches_df['citation_hour'].min(),
                'latest': matches_df['citation_hour'].max(),
                'most_common': matches_df['citation_hour'].mode().iloc[0] if not matches_df.empty else None
            }
        }
        
        report = {
            'analysis_timestamp': datetime.now().isoformat(),
            'dataset_summary': {
                'total_matches': len(matches_df),
                'unique_schedules_matched': unique_schedules_with_citations,
                'schedules_with_estimates': schedules_with_estimates,
                'unique_citations': matches_df['citation_id'].nunique()
            },
            'matching_quality': {
                'time_relevance_distribution': time_relevance_counts,
                'distance_analysis': distance_stats
            },
            'estimation_quality': {
                'confidence_distribution': confidence_dist,
                'temporal_analysis': hour_analysis
            },
            'coverage_analysis': {
                'schedules_with_sufficient_data_pct': (schedules_with_estimates / unique_schedules_with_citations * 100) if unique_schedules_with_citations > 0 else 0,
                'avg_citations_per_schedule': len(matches_df) / unique_schedules_with_citations if unique_schedules_with_citations > 0 else 0
            }
        }
        
        return report
        
    def run_complete_analysis(self, citation_file: str, schedule_file: str, 
                            output_prefix: str = "citation_analysis",
                            strict_timing: bool = True) -> Dict:
        """Run the complete citation-schedule matching and analysis"""
        timing_mode = "STRICT TIMING" if strict_timing else "FLEXIBLE TIMING" 
        self.logger.info(f"🔍 Starting Citation-Schedule Matching Analysis ({timing_mode})")
        self.logger.info("=" * 60)
        
        start_time = datetime.now()
        
        # Load data
        citation_df = self.load_citation_data(citation_file)
        schedule_df = self.load_schedule_data(schedule_file)
        
        if citation_df.empty or schedule_df.empty:
            raise ValueError("Insufficient data for analysis")
            
        # Process matches
        matches_df = self.process_all_matches(citation_df, schedule_df, strict_timing)
        
        if matches_df.empty:
            self.logger.warning("No matches found - check distance threshold and data quality")
            return {'error': 'No matches found'}
            
        # Calculate estimates
        estimates_df = self.calculate_estimated_citation_times(matches_df)
        
        # Export results
        files = self.export_comprehensive_dataset(matches_df, estimates_df, output_prefix)
        
        # Final report
        end_time = datetime.now()
        processing_time = end_time - start_time
        
        self.logger.info(f"🎉 Analysis completed in {processing_time}")
        self.logger.info(f"📊 Found {len(matches_df)} matches for {matches_df['schedule_id'].nunique()} schedules")
        self.logger.info(f"🎯 Generated estimates for {len(estimates_df)} schedules")
        
        result = {
            'processing_time': str(processing_time),
            'matches_count': len(matches_df),
            'estimates_count': len(estimates_df),
            'files': files,
            'strict_timing': strict_timing
        }
        
        return result

def main():
    parser = argparse.ArgumentParser(description='Citation Schedule Matching and Analysis')
    parser.add_argument('--citation-file', required=True,
                       help='Path to processed citation CSV file')
    parser.add_argument('--schedule-file', required=True, 
                       help='Path to cleaned schedule CSV file')
    parser.add_argument('--max-distance', type=int, default=50,
                       help='Maximum matching distance in meters (default: 50)')
    parser.add_argument('--output-prefix', default='citation_analysis',
                       help='Prefix for output files')
    parser.add_argument('--flexible-timing', action='store_true',
                       help='Allow citations outside scheduled hours (default: strict timing only)')
    
    args = parser.parse_args()
    
    # Validate input files
    if not Path(args.citation_file).exists():
        raise FileNotFoundError(f"Citation file not found: {args.citation_file}")
    if not Path(args.schedule_file).exists():
        raise FileNotFoundError(f"Schedule file not found: {args.schedule_file}")
        
    # Initialize matcher
    matcher = CitationScheduleMatcher(max_distance_meters=args.max_distance)
    
    # Determine timing mode (default is strict)
    strict_timing = not args.flexible_timing
    
    try:
        # Run analysis
        result = matcher.run_complete_analysis(
            citation_file=args.citation_file,
            schedule_file=args.schedule_file,
            output_prefix=args.output_prefix,
            strict_timing=strict_timing
        )
        
        timing_mode = "STRICT" if strict_timing else "FLEXIBLE"
        print(f"\n🎯 ANALYSIS COMPLETE ({timing_mode} TIMING):")
        print(f"📁 Matches file: {result['files']['matches_file']}")
        print(f"📊 Estimates file: {result['files']['estimates_file']}")
        print(f"📋 Report file: {result['files']['report_file']}")
        print(f"⏱️  Processing time: {result['processing_time']}")
        
    except Exception as e:
        print(f"❌ Analysis failed: {e}")
        raise

if __name__ == "__main__":
    main()