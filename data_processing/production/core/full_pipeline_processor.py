#!/usr/bin/env python3
"""
SF Parking Citation Analysis - Complete Production Pipeline

Orchestrates the full end-to-end processing pipeline:
1. Fetch street sweeping schedule data from SF Open Data API
2. Clean and consolidate schedule data
3. Store cleaned schedule data
4. Fetch 365 days of street sweeping citations from SF Open Data API
5. Geocode all citations with parallel processing
6. Store geocoded citation data
7. Join citations with schedules and calculate estimated sweeper times
8. Store final analysis results

This is designed for weekly/monthly refresh of the complete dataset.

Usage:
python3 full_pipeline_processor.py --workers 6 --days 365 --output-dir ../output/pipeline_results/
"""

import requests
import pandas as pd
import argparse
import logging
import json
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List
import subprocess
import sys
import os

class FullPipelineProcessor:
    def __init__(self, 
                 days_back: int = 365,
                 workers: int = 6,
                 output_dir: str = "../output/pipeline_results",
                 rate_limit: float = 0.3,
                 batch_size: int = 200):
        
        self.days_back = days_back
        self.workers = workers
        self.output_dir = Path(output_dir)
        self.rate_limit = rate_limit
        self.batch_size = batch_size
        
        # File paths for pipeline stages
        self.timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        
        # Create output directory
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        # Set up logging
        self.setup_logging()
        self.schedule_raw_file = self.output_dir / f"schedule_raw_{self.timestamp}.csv"
        self.schedule_clean_file = self.output_dir / f"schedule_cleaned_{self.timestamp}.csv"
        self.citations_raw_file = self.output_dir / f"citations_raw_{self.timestamp}.csv"
        self.citations_geocoded_file = self.output_dir / f"citations_geocoded_{self.timestamp}.csv"
        self.final_estimates_file = self.output_dir / f"sweeper_time_estimates_{self.timestamp}.csv"
        self.pipeline_report_file = self.output_dir / f"pipeline_report_{self.timestamp}.json"
        
    def setup_logging(self):
        """Set up comprehensive logging for the full pipeline"""
        log_file = self.output_dir / f"pipeline_processing_{self.timestamp}.log"
        
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_file),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
        
    def fetch_schedule_data(self) -> pd.DataFrame:
        """Step 1: Fetch street sweeping schedule data from SF Open Data API"""
        self.logger.info("📅 Step 1: Fetching street sweeping schedule data from SF Open Data API")
        
        url = "https://data.sfgov.org/resource/yhqp-riqs.json"
        
        all_schedules = []
        limit = 50000  # API limit per request
        offset = 0
        
        while True:
            params = {
                '$limit': limit,
                '$offset': offset,
                '$order': 'cnn ASC'
            }
            
            try:
                self.logger.info(f"   Fetching schedule batch at offset {offset}...")
                response = requests.get(url, params=params, timeout=60)
                response.raise_for_status()
                
                batch_schedules = response.json()
                if not batch_schedules:
                    break
                    
                all_schedules.extend(batch_schedules)
                self.logger.info(f"   Fetched {len(batch_schedules)} schedules (total: {len(all_schedules)})")
                
                if len(batch_schedules) < limit:
                    break
                    
                offset += limit
                time.sleep(1)  # Rate limit API requests
                
            except Exception as e:
                self.logger.error(f"Error fetching schedule data: {e}")
                raise
                
        self.logger.info(f"✅ Fetched {len(all_schedules)} schedule records from API")
        
        # Convert to DataFrame and save raw data
        df = pd.DataFrame(all_schedules)
        df.to_csv(self.schedule_raw_file, index=False)
        self.logger.info(f"💾 Saved raw schedule data to {self.schedule_raw_file}")
        
        return df
        
    def clean_schedule_data(self, schedule_df: pd.DataFrame) -> pd.DataFrame:
        """Step 2: Clean and consolidate schedule data"""
        self.logger.info("🧹 Step 2: Cleaning and consolidating schedule data")
        
        # Use the simple cleaning logic from clean_schedule_data_simple.py
        # We'll call it as a subprocess to leverage existing code
        
        # First save the raw data in the expected location
        temp_raw_file = "temp_schedule_raw.csv"
        schedule_df.to_csv(temp_raw_file, index=False)
        
        try:
            # Create a temporary cleaning script that works with our data
            temp_script = self._create_temp_cleaning_script(temp_raw_file, str(self.schedule_clean_file))
            
            # Run the cleaning process
            result = subprocess.run([sys.executable, temp_script], 
                                  capture_output=True, text=True, timeout=300)
            
            if result.returncode != 0:
                self.logger.error(f"Schedule cleaning failed: {result.stderr}")
                raise RuntimeError("Schedule cleaning failed")
                
            self.logger.info("✅ Schedule cleaning completed successfully")
            
            # Load cleaned data
            cleaned_df = pd.read_csv(self.schedule_clean_file)
            self.logger.info(f"📊 Cleaned schedule: {len(schedule_df):,} → {len(cleaned_df):,} records")
            
            # Cleanup temporary files
            os.remove(temp_raw_file)
            os.remove(temp_script)
            
            return cleaned_df
            
        except Exception as e:
            self.logger.error(f"Error in schedule cleaning: {e}")
            # Cleanup on error
            if os.path.exists(temp_raw_file):
                os.remove(temp_raw_file)
            raise
            
    def _create_temp_cleaning_script(self, input_file: str, output_file: str) -> str:
        """Create a temporary cleaning script for the current data"""
        script_content = f'''
import pandas as pd
import numpy as np

# Load data
df = pd.read_csv("{input_file}")

# Simple groupby cleaning logic (same as clean_schedule_data_simple.py)
def normalize_row(row):
    weekday_str = str(row['weekday']).upper() if 'weekday' in row else str(row.get('WeekDay', '')).upper()
    
    # Handle Holiday as special case
    if 'HOLIDAY' in weekday_str:
        weekday_str = 'SUN/HOLIDAY'
    
    day_mappings = {{
        'Monday': any(day in weekday_str for day in ['MON']),
        'Tuesday': any(day in weekday_str for day in ['TUES', 'TUE']),
        'Wednesday': any(day in weekday_str for day in ['WED']),
        'Thursday': any(day in weekday_str for day in ['THU']),
        'Friday': any(day in weekday_str for day in ['FRI']),
        'Saturday': any(day in weekday_str for day in ['SAT']),
        'Sunday': any(day in weekday_str for day in ['SUN', 'HOLIDAY'])
    }}
    
    # Map API field names to our expected format
    normalized = {{
        'CNN': row.get('cnn', row.get('CNN', '')),
        'Corridor': row.get('streetname', row.get('Corridor', '')),
        'Limits': row.get('limits', row.get('Limits', '')),
        'CNNRightLeft': row.get('cnnrightleft', row.get('CNNRightLeft', '')),
        'BlockSide': row.get('blockside', row.get('BlockSide', '')),
        'FromHour': int(row.get('fromhour', row.get('FromHour', 0))),
        'ToHour': int(row.get('tohour', row.get('ToHour', 0))),
        'Line': row.get('the_geom', row.get('Line', '')),
        
        'Monday': 1 if day_mappings['Monday'] else 0,
        'Tuesday': 1 if day_mappings['Tuesday'] else 0,
        'Wednesday': 1 if day_mappings['Wednesday'] else 0,
        'Thursday': 1 if day_mappings['Thursday'] else 0,
        'Friday': 1 if day_mappings['Friday'] else 0,
        'Saturday': 1 if day_mappings['Saturday'] else 0,
        'Sunday': 1 if day_mappings['Sunday'] else 0,
        
        'Week1': int(row.get('week1', row.get('Week1', 1))),
        'Week2': int(row.get('week2', row.get('Week2', 1))),
        'Week3': int(row.get('week3', row.get('Week3', 1))),
        'Week4': int(row.get('week4', row.get('Week4', 1))),
        'Week5': int(row.get('week5', row.get('Week5', 0))),
        'Holidays': int(row.get('holidays', row.get('Holidays', 0)))
    }}
    
    return normalized

# Normalize all rows
print("Normalizing schedule data...")
normalized_rows = [normalize_row(row) for _, row in df.iterrows()]
normalized_df = pd.DataFrame(normalized_rows)

# Group by location and combine
location_columns = ['Corridor', 'Limits', 'CNNRightLeft', 'BlockSide', 'FromHour', 'ToHour']
combine_columns = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
                   'Week1', 'Week2', 'Week3', 'Week4', 'Week5', 'Holidays']
first_columns = ['CNN', 'Line']

agg_dict = {{col: 'max' for col in combine_columns}}
agg_dict.update({{col: 'first' for col in first_columns}})

combined_df = normalized_df.groupby(location_columns).agg(agg_dict).reset_index()
combined_df['RecordCount'] = normalized_df.groupby(location_columns).size().values

# Generate clean IDs and descriptions
combined_df['CleanBlockSweepID'] = range(2000000, 2000000 + len(combined_df))

# Generate WeekDay descriptions
day_columns = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
day_abbrev = ['Mon', 'Tues', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

weekday_codes = []
for _, row in combined_df.iterrows():
    active_days = [day_abbrev[i] for i, day in enumerate(day_columns) if row[day] == 1]
    weekday_codes.append('/'.join(active_days) if active_days else 'None')

combined_df['WeekDay'] = weekday_codes
combined_df['FullName'] = weekday_codes

# Add data quality notes
combined_df['DataQualityNotes'] = combined_df['RecordCount'].apply(
    lambda x: f"Combined {{x}} duplicate records using groupby method" if x > 1 else ""
)

# Final column order
column_order = [
    'CleanBlockSweepID', 'CNN', 'Corridor', 'Limits', 'CNNRightLeft', 'BlockSide',
    'FullName', 'WeekDay', 'FromHour', 'ToHour',
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
    'Week1', 'Week2', 'Week3', 'Week4', 'Week5', 'Holidays',
    'RecordCount', 'Line', 'DataQualityNotes'
]

result_df = combined_df[column_order]
result_df.to_csv("{output_file}", index=False)
print(f"Saved cleaned schedule data: {{len(df)}} -> {{len(result_df)}} records")
'''
        
        script_file = "temp_cleaning_script.py"
        with open(script_file, 'w') as f:
            f.write(script_content)
        return script_file
        
    def fetch_citation_data(self) -> pd.DataFrame:
        """Step 3: Fetch street sweeping citations from SF Open Data API"""
        self.logger.info(f"🚗 Step 3: Fetching {self.days_back} days of street sweeping citations")
        
        # Calculate date range
        end_date = datetime.now()
        start_date = end_date - timedelta(days=self.days_back)
        start_date_str = start_date.strftime('%Y-%m-%d')
        
        self.logger.info(f"   Date range: {start_date_str} to {end_date.strftime('%Y-%m-%d')}")
        
        url = "https://data.sfgov.org/resource/ab4h-6ztd.json"
        
        all_citations = []
        limit = 50000  # API limit per request
        offset = 0
        
        while True:
            params = {
                '$limit': limit,
                '$offset': offset,
                '$where': f"violation_desc = 'STR CLEAN' AND citation_issued_datetime > '{start_date_str}'",
                '$order': 'citation_issued_datetime DESC'
            }
            
            try:
                self.logger.info(f"   Fetching citation batch at offset {offset}...")
                response = requests.get(url, params=params, timeout=60)
                response.raise_for_status()
                
                batch_citations = response.json()
                if not batch_citations:
                    break
                    
                all_citations.extend(batch_citations)
                self.logger.info(f"   Fetched {len(batch_citations)} citations (total: {len(all_citations)})")
                
                if len(batch_citations) < limit:
                    break
                    
                offset += limit
                time.sleep(1.5)  # Rate limit API requests
                
            except Exception as e:
                self.logger.error(f"Error fetching citation data: {e}")
                raise
                
        self.logger.info(f"✅ Fetched {len(all_citations)} street sweeping citations from API")
        
        # Convert to DataFrame and save raw data
        df = pd.DataFrame(all_citations)
        df.to_csv(self.citations_raw_file, index=False)
        self.logger.info(f"💾 Saved raw citation data to {self.citations_raw_file}")
        
        return df
        
    def geocode_citations(self, citations_df: pd.DataFrame) -> pd.DataFrame:
        """Step 4: Geocode all citations using the production citation processor"""
        self.logger.info("📍 Step 4: Geocoding all citations with parallel processing")
        
        # Check if we have citations to process
        if len(citations_df) == 0:
            self.logger.warning("No citations to geocode - creating empty result dataset")
            empty_result = pd.DataFrame(columns=[
                'citation_id', 'address', 'datetime', 'latitude', 'longitude',
                'returned_address', 'confidence', 'confidence_score', 'geocoding_status'
            ])
            empty_result.to_csv(self.citations_geocoded_file, index=False)
            return empty_result
        
        # Prepare the citation data in the format expected by the production processor
        temp_citations_file = "temp_citations_for_geocoding.csv"
        
        # Format the data for the geocoding processor - handle different possible column names from API
        geocoding_input = pd.DataFrame()
        
        # Map SF Open Data API column names to our expected format
        if 'citation_location' in citations_df.columns:
            geocoding_input['citation_location'] = citations_df['citation_location']
        elif 'address' in citations_df.columns:
            geocoding_input['citation_location'] = citations_df['address']
        else:
            raise ValueError("No location column found in citation data")
            
        if 'citation_issued_datetime' in citations_df.columns:
            geocoding_input['citation_issued_datetime'] = citations_df['citation_issued_datetime']
        elif 'issued_date' in citations_df.columns:
            geocoding_input['citation_issued_datetime'] = citations_df['issued_date']
        else:
            raise ValueError("No datetime column found in citation data")
            
        # Add citation number
        if 'citation_number' in citations_df.columns:
            geocoding_input['citation_number'] = citations_df['citation_number']
        else:
            geocoding_input['citation_number'] = range(len(citations_df))
            
        geocoding_input.to_csv(temp_citations_file, index=False)
        
        try:
            # Run the production citation processor
            cmd = [
                sys.executable, 'production_citation_processor.py',
                '--input-file', temp_citations_file,
                '--workers', str(self.workers),
                '--batch-size', str(self.batch_size),
                '--rate-limit', str(self.rate_limit),
                '--min-confidence', 'MEDIUM',
                '--output', str(self.citations_geocoded_file),
                '--no-resume'
            ]
            
            self.logger.info(f"   Running: {' '.join(cmd)}")
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=14400)  # 4 hour timeout
            
            if result.returncode != 0:
                self.logger.error(f"Citation geocoding failed: {result.stderr}")
                raise RuntimeError("Citation geocoding failed")
                
            self.logger.info("✅ Citation geocoding completed successfully")
            
            # Load geocoded results
            geocoded_df = pd.read_csv(self.citations_geocoded_file)
            self.logger.info(f"📊 Geocoded citations: {len(geocoded_df):,} with confidence filtering")
            
            # Cleanup temporary file
            os.remove(temp_citations_file)
            
            return geocoded_df
            
        except Exception as e:
            self.logger.error(f"Error in citation geocoding: {e}")
            if os.path.exists(temp_citations_file):
                os.remove(temp_citations_file)
            raise
            
    def calculate_sweeper_estimates(self, citations_df: pd.DataFrame, schedule_df: pd.DataFrame) -> pd.DataFrame:
        """Step 5: Join citations with schedules and calculate estimated sweeper times"""
        self.logger.info("🔄 Step 5: Calculating estimated sweeper arrival times")
        
        # Check if we have citations to analyze
        if len(citations_df) == 0:
            self.logger.warning("No citations available for matching - creating empty estimates dataset")
            empty_estimates = pd.DataFrame(columns=[
                'schedule_id', 'corridor', 'limits', 'schedule_from_hour', 'schedule_to_hour',
                'total_citations', 'relevant_citations', 'avg_citation_hour', 'median_citation_hour',
                'estimated_sweeper_arrival_hour', 'confidence_level'
            ])
            empty_estimates.to_csv(self.final_estimates_file, index=False)
            return empty_estimates
        
        try:
            # Use the citation_schedule_matcher.py script
            cmd = [
                sys.executable, 'citation_schedule_matcher.py',
                '--citation-file', str(self.citations_geocoded_file),
                '--schedule-file', str(self.schedule_clean_file),
                '--max-distance', '50',
                '--output-prefix', str(self.output_dir / f"final_analysis_{self.timestamp}")
            ]
            
            self.logger.info(f"   Running: {' '.join(cmd)}")
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)  # 30 minute timeout
            
            if result.returncode != 0:
                self.logger.error(f"Schedule matching failed: {result.stderr}")
                raise RuntimeError("Schedule matching failed")
                
            self.logger.info("✅ Schedule matching and analysis completed successfully")
            
            # Find the estimates file
            estimates_files = list(self.output_dir.glob(f"final_analysis_{self.timestamp}_estimates_*.csv"))
            if not estimates_files:
                raise RuntimeError("Estimates file not found")
                
            estimates_df = pd.read_csv(estimates_files[0])
            
            # Copy to our standardized filename
            estimates_df.to_csv(self.final_estimates_file, index=False)
            
            self.logger.info(f"📊 Generated estimates for {len(estimates_df):,} schedule blocks")
            
            return estimates_df
            
        except Exception as e:
            self.logger.error(f"Error in schedule matching: {e}")
            raise
            
    def generate_pipeline_report(self, 
                                schedule_raw_count: int,
                                schedule_clean_count: int,
                                citations_raw_count: int,
                                citations_geocoded_count: int,
                                estimates_count: int,
                                start_time: datetime,
                                end_time: datetime) -> Dict:
        """Generate comprehensive pipeline report"""
        
        processing_time = end_time - start_time
        
        report = {
            'pipeline_execution': {
                'timestamp': self.timestamp,
                'start_time': start_time.isoformat(),
                'end_time': end_time.isoformat(),
                'total_processing_time': str(processing_time),
                'days_processed': self.days_back,
                'workers_used': self.workers
            },
            'data_processing_summary': {
                'schedule_data': {
                    'raw_records': schedule_raw_count,
                    'cleaned_records': schedule_clean_count,
                    'reduction_count': schedule_raw_count - schedule_clean_count,
                    'reduction_percentage': round((schedule_raw_count - schedule_clean_count) / schedule_raw_count * 100, 1)
                },
                'citation_data': {
                    'raw_citations': citations_raw_count,
                    'geocoded_citations': citations_geocoded_count,
                    'geocoding_success_rate': round(citations_geocoded_count / citations_raw_count * 100, 1) if citations_raw_count > 0 else 0
                },
                'final_estimates': {
                    'schedules_with_estimates': estimates_count,
                    'coverage_percentage': round(estimates_count / schedule_clean_count * 100, 1) if schedule_clean_count > 0 else 0
                }
            },
            'output_files': {
                'raw_schedule_data': str(self.schedule_raw_file),
                'cleaned_schedule_data': str(self.schedule_clean_file),
                'raw_citation_data': str(self.citations_raw_file),
                'geocoded_citation_data': str(self.citations_geocoded_file),
                'final_estimates': str(self.final_estimates_file),
                'pipeline_report': str(self.pipeline_report_file)
            },
            'performance_metrics': {
                'citations_per_minute': round(citations_raw_count / (processing_time.total_seconds() / 60), 1),
                'total_api_calls': schedule_raw_count + citations_raw_count + citations_geocoded_count,
                'estimated_cost_savings': f"${citations_geocoded_count * 0.01:.2f} vs manual processing"
            }
        }
        
        # Save report
        with open(self.pipeline_report_file, 'w') as f:
            json.dump(report, f, indent=2, default=str)
            
        return report
        
    def run_full_pipeline(self) -> Dict:
        """Execute the complete production pipeline"""
        self.logger.info("🚀 Starting Full SF Parking Citation Analysis Pipeline")
        self.logger.info("=" * 80)
        self.logger.info(f"   Processing {self.days_back} days of data with {self.workers} workers")
        self.logger.info(f"   Output directory: {self.output_dir}")
        self.logger.info("=" * 80)
        
        start_time = datetime.now()
        
        try:
            # Step 1: Fetch schedule data
            schedule_raw_df = self.fetch_schedule_data()
            schedule_raw_count = len(schedule_raw_df)
            
            # Step 2: Clean schedule data
            schedule_clean_df = self.clean_schedule_data(schedule_raw_df)
            schedule_clean_count = len(schedule_clean_df)
            
            # Step 3: Fetch citation data
            citations_raw_df = self.fetch_citation_data()
            citations_raw_count = len(citations_raw_df)
            
            # Step 4: Geocode citations
            citations_geocoded_df = self.geocode_citations(citations_raw_df)
            citations_geocoded_count = len(citations_geocoded_df)
            
            # Step 5: Calculate estimates
            estimates_df = self.calculate_sweeper_estimates(citations_geocoded_df, schedule_clean_df)
            estimates_count = len(estimates_df)
            
            end_time = datetime.now()
            
            # Step 6: Generate report
            report = self.generate_pipeline_report(
                schedule_raw_count, schedule_clean_count,
                citations_raw_count, citations_geocoded_count,
                estimates_count, start_time, end_time
            )
            
            self.logger.info("🎉 Full pipeline completed successfully!")
            self.logger.info("=" * 80)
            self.logger.info(f"📊 FINAL RESULTS:")
            self.logger.info(f"   Schedule data: {schedule_raw_count:,} → {schedule_clean_count:,} records")
            self.logger.info(f"   Citation data: {citations_raw_count:,} → {citations_geocoded_count:,} geocoded")
            self.logger.info(f"   Estimates: {estimates_count:,} schedule blocks with predicted times")
            self.logger.info(f"   Processing time: {end_time - start_time}")
            self.logger.info(f"📁 All output saved to: {self.output_dir}")
            
            return report
            
        except Exception as e:
            self.logger.error(f"❌ Pipeline failed: {e}")
            raise

def main():
    parser = argparse.ArgumentParser(description='SF Parking Citation Analysis - Full Production Pipeline')
    parser.add_argument('--days', type=int, default=365,
                       help='Number of days back to process citations (default: 365)')
    parser.add_argument('--workers', type=int, default=6,
                       help='Number of parallel workers for geocoding (default: 6)')
    parser.add_argument('--output-dir', default='../output/pipeline_results',
                       help='Output directory for all pipeline results')
    parser.add_argument('--rate-limit', type=float, default=0.3,
                       help='Rate limit for API calls in seconds (default: 0.3)')
    parser.add_argument('--batch-size', type=int, default=200,
                       help='Batch size for geocoding (default: 200)')
    
    args = parser.parse_args()
    
    # Initialize pipeline processor
    processor = FullPipelineProcessor(
        days_back=args.days,
        workers=args.workers,
        output_dir=args.output_dir,
        rate_limit=args.rate_limit,
        batch_size=args.batch_size
    )
    
    try:
        # Run the complete pipeline
        report = processor.run_full_pipeline()
        
        print(f"\n🎯 PIPELINE COMPLETE!")
        print(f"📁 Results saved to: {processor.output_dir}")
        print(f"📊 Report: {processor.pipeline_report_file}")
        print(f"🎯 Final estimates: {processor.final_estimates_file}")
        
    except KeyboardInterrupt:
        print("\n⚠️ Pipeline interrupted by user. Partial results may be available.")
    except Exception as e:
        print(f"\n❌ Pipeline failed: {e}")
        raise

if __name__ == "__main__":
    main()