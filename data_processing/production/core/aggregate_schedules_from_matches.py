#!/usr/bin/env python3
"""
Aggregate schedule data using raw citation matches for accurate statistics

This script uses the raw citation-to-schedule matches to calculate proper
averages and medians, then creates the matrix representation for the app.

Input: 
- final_analysis_*_matches_*.csv (raw citation matches)
- day_specific_sweeper_estimates_*.csv (schedule definitions)
Output: app_ready_aggregated_*.csv with proper statistics
"""

import pandas as pd
import numpy as np
import argparse
import logging
from pathlib import Path
from datetime import datetime
from collections import defaultdict

class MatchBasedAggregator:
    def __init__(self, matches_file: str, schedules_file: str, output_file: str = None):
        self.matches_file = Path(matches_file)
        self.schedules_file = Path(schedules_file)
        self.output_file = output_file or self.matches_file.parent / f"app_ready_aggregated_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
        
        # Set up logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s'
        )
        self.logger = logging.getLogger(__name__)
        
    def create_week_pattern_string(self, row: pd.Series) -> str:
        """Create a string representation of the week pattern"""
        return f"{int(row['week1'])}{int(row['week2'])}{int(row['week3'])}{int(row['week4'])}{int(row.get('week5', 0))}"
    
    def generate_schedule_summary(self, hour_arrays: dict) -> str:
        """
        Generate a human-readable schedule summary from hour arrays
        """
        # Get active days and their hours
        active_days = []
        day_hour_patterns = {}
        
        day_order = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday']
        
        for day in day_order:
            hours = hour_arrays.get(day, [])
            if hours:
                active_days.append(day)
                # Store the actual hour pattern for comparison
                hour_pattern = ','.join(map(str, sorted(hours)))
                day_hour_patterns[day] = hour_pattern
        
        # Check if all active days have the same hour pattern
        if len(set(day_hour_patterns.values())) > 1:
            return "Multiple schedules"
        
        # If we get here, all active days have the same schedule
        # Get the common time range
        if active_days and day_hour_patterns:
            sample_hours = hour_arrays[active_days[0]]
            min_hour = min(sample_hours)
            max_hour = max(sample_hours) + 1
            time_range = f"{min_hour}-{max_hour}"
        else:
            time_range = ""
        
        if not active_days:
            return "No cleaning"
            
        # Format time range
        time_str = ""
        if time_range:
            hours = time_range.split('-')
            start_hour = int(hours[0])
            end_hour = int(hours[1])
            
            # Convert to 12-hour format
            start_period = "am" if start_hour < 12 else "pm"
            end_period = "am" if end_hour <= 12 else "pm"
            start_display = start_hour if start_hour <= 12 else start_hour - 12
            end_display = end_hour if end_hour <= 12 else end_hour - 12
            
            if start_display == 0:
                start_display = 12
                start_period = "am"
            
            time_str = f" {start_display}-{end_display}{end_period}"
        
        # Check for common patterns
        weekdays = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday']
        weekends = ['saturday', 'sunday']
        
        if set(active_days) == set(day_order):
            return f"Daily{time_str}"
        elif set(active_days) == set(weekdays):
            return f"Weekdays{time_str}"
        elif set(active_days) == set(weekends):
            return f"Weekends{time_str}"
        elif len(active_days) == 1:
            day_name = active_days[0].capitalize()
            return f"{day_name}s{time_str}"
        else:
            # Abbreviate day names
            day_abbrev = {
                'monday': 'Mon',
                'tuesday': 'Tue', 
                'wednesday': 'Wed',
                'thursday': 'Thu',
                'friday': 'Fri',
                'saturday': 'Sat',
                'sunday': 'Sun'
            }
            abbreviated = [day_abbrev.get(day, day[:3]) for day in active_days]
            return f"{'/'.join(abbreviated)}{time_str}"
    
    def aggregate_from_matches(self):
        """
        Main aggregation function using raw match data
        """
        self.logger.info(f"Loading citation matches from: {self.matches_file}")
        self.logger.info(f"Loading schedule definitions from: {self.schedules_file}")
        
        # Load the data
        matches_df = pd.read_csv(self.matches_file)
        schedules_df = pd.read_csv(self.schedules_file)
        
        self.logger.info(f"Loaded {len(matches_df):,} citation matches")
        self.logger.info(f"Loaded {len(schedules_df):,} schedule definitions")
        
        # Add week pattern to schedules
        schedules_df['week_pattern'] = schedules_df.apply(self.create_week_pattern_string, axis=1)
        
        # Create schedule lookup dictionary
        schedule_lookup = {}
        for _, row in schedules_df.iterrows():
            schedule_lookup[row['schedule_id']] = {
                'cnn': row['cnn'],
                'corridor': row['corridor'],
                'limits': row['limits'],
                'cnn_right_left': row['cnn_right_left'],
                'block_side': row.get('block_side', ''),
                'weekday': row['weekday'],
                'scheduled_from_hour': row['scheduled_from_hour'],
                'scheduled_to_hour': row['scheduled_to_hour'],
                'week_pattern': row['week_pattern'],
                'week1': row['week1'],
                'week2': row['week2'],
                'week3': row['week3'],
                'week4': row['week4'],
                'week5': row.get('week5', 0),
                'line': row['line']
            }
        
        # Group matches by CNN + Side + Week Pattern
        aggregation_groups = defaultdict(lambda: {
            'citation_times': [],
            'schedule_ids': set(),
            'schedule_info': None,
            'hour_arrays': defaultdict(set)
        })
        
        # Process each match
        for _, match in matches_df.iterrows():
            schedule_id = match['schedule_id']
            if schedule_id not in schedule_lookup:
                continue
                
            schedule = schedule_lookup[schedule_id]
            key = f"{schedule['cnn']}_{schedule['cnn_right_left']}_{schedule['week_pattern']}"
            
            # Store citation time
            aggregation_groups[key]['citation_times'].append(match['citation_time'])
            aggregation_groups[key]['schedule_ids'].add(schedule_id)
            
            # Store schedule info (will be same for all in group)
            if not aggregation_groups[key]['schedule_info']:
                aggregation_groups[key]['schedule_info'] = schedule
            
            # Build hour arrays
            day = schedule['weekday'].lower()
            from_hour = int(schedule['scheduled_from_hour'])
            to_hour = int(schedule['scheduled_to_hour'])
            
            # Handle edge cases
            if to_hour <= from_hour:
                if to_hour == 0:
                    to_hour = 24
                else:
                    continue
            
            # Add hours for this day
            for hour in range(from_hour, to_hour):
                aggregation_groups[key]['hour_arrays'][day].add(hour)
        
        # Now create aggregated rows
        aggregated_rows = []
        
        for key, group_data in aggregation_groups.items():
            schedule_info = group_data['schedule_info']
            if not schedule_info:
                continue
            
            # Calculate citation statistics
            citation_times = group_data['citation_times']
            if citation_times:
                citation_count = len(citation_times)
                avg_time = np.mean(citation_times)
                median_time = np.median(citation_times)
            else:
                citation_count = 0
                avg_time = ''
                median_time = ''
            
            # Convert hour sets to comma-separated strings
            hour_arrays = {
                'monday_hours': '',
                'tuesday_hours': '',
                'wednesday_hours': '',
                'thursday_hours': '',
                'friday_hours': '',
                'saturday_hours': '',
                'sunday_hours': ''
            }
            
            summary_dict = {}
            for day, hours in group_data['hour_arrays'].items():
                if hours:
                    sorted_hours = sorted(list(hours))
                    hour_arrays[f"{day}_hours"] = ','.join(map(str, sorted_hours))
                    summary_dict[day] = sorted_hours
                else:
                    summary_dict[day] = []
            
            # Generate schedule summary
            schedule_summary = self.generate_schedule_summary(summary_dict)
            
            # Calculate total weekly hours
            total_hours = sum(len(hours) for hours in group_data['hour_arrays'].values())
            
            # Check for multiple time windows
            time_windows = set()
            for hours in group_data['hour_arrays'].values():
                if hours:
                    sorted_hours = sorted(list(hours))
                    time_windows.add(f"{min(sorted_hours)}-{max(sorted_hours)+1}")
            
            has_multiple_windows = len(time_windows) > 1
            
            # Create row
            row = {
                'clean_id': key,
                'cnn': schedule_info['cnn'],
                'corridor': schedule_info['corridor'],
                'limits': schedule_info['limits'],
                'cnn_right_left': schedule_info['cnn_right_left'],
                'block_side': schedule_info['block_side'],
                **hour_arrays,
                'schedule_summary': schedule_summary,
                'total_weekly_hours': total_hours,
                'has_multiple_windows': has_multiple_windows,
                'week1': int(schedule_info['week1']),
                'week2': int(schedule_info['week2']),
                'week3': int(schedule_info['week3']),
                'week4': int(schedule_info['week4']),
                'week5': int(schedule_info.get('week5', 0)),
                'citation_count': citation_count,
                'avg_citation_time': f"{avg_time:.2f}" if avg_time else '',
                'median_citation_time': f"{median_time:.2f}" if median_time else '',
                'line': schedule_info['line']
            }
            
            aggregated_rows.append(row)
        
        # Also add schedules that have no citations
        # Get all schedule combinations from schedule file
        all_schedule_keys = set()
        for _, row in schedules_df.iterrows():
            key = f"{row['cnn']}_{row['cnn_right_left']}_{row['week_pattern']}"
            all_schedule_keys.add(key)
        
        # Find keys with no citations
        keys_with_citations = set(aggregation_groups.keys())
        keys_without_citations = all_schedule_keys - keys_with_citations
        
        self.logger.info(f"Found {len(keys_without_citations):,} schedule groups without citations")
        
        # Add schedules without citations
        for _, row in schedules_df.iterrows():
            key = f"{row['cnn']}_{row['cnn_right_left']}_{row['week_pattern']}"
            if key in keys_without_citations:
                # Build hour array for this specific schedule
                day = row['weekday'].lower()
                from_hour = int(row['scheduled_from_hour'])
                to_hour = int(row['scheduled_to_hour'])
                
                if to_hour <= from_hour and to_hour == 0:
                    to_hour = 24
                
                hour_arrays = {f"{d}_hours": '' for d in ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday']}
                
                if to_hour > from_hour:
                    hour_arrays[f"{day}_hours"] = ','.join(map(str, range(from_hour, to_hour)))
                
                # Check if we already have this key (from another day)
                existing_row = next((r for r in aggregated_rows if r['clean_id'] == key), None)
                
                if existing_row:
                    # Update existing row with this day's hours
                    if hour_arrays[f"{day}_hours"]:
                        if existing_row[f"{day}_hours"]:
                            # Merge hours
                            existing_hours = set(map(int, existing_row[f"{day}_hours"].split(',')))
                            new_hours = set(map(int, hour_arrays[f"{day}_hours"].split(',')))
                            all_hours = sorted(list(existing_hours.union(new_hours)))
                            existing_row[f"{day}_hours"] = ','.join(map(str, all_hours))
                        else:
                            existing_row[f"{day}_hours"] = hour_arrays[f"{day}_hours"]
                    
                    # Regenerate schedule summary after merging
                    updated_summary_dict = {}
                    for d in ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday']:
                        if existing_row[f"{d}_hours"]:
                            updated_summary_dict[d] = [int(h) for h in existing_row[f"{d}_hours"].split(',')]
                        else:
                            updated_summary_dict[d] = []
                    
                    existing_row['schedule_summary'] = self.generate_schedule_summary(updated_summary_dict)
                    existing_row['total_weekly_hours'] = sum(len(hours.split(',')) if hours else 0 
                                                           for hours in [existing_row[f"{d}_hours"] for d in ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday']])
                else:
                    # Create new row
                    summary_dict = {}
                    for d in ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday']:
                        if hour_arrays[f"{d}_hours"]:
                            summary_dict[d] = [int(h) for h in hour_arrays[f"{d}_hours"].split(',')]
                        else:
                            summary_dict[d] = []
                    
                    schedule_summary = self.generate_schedule_summary(summary_dict)
                    total_hours = sum(len(hours.split(',')) if hours else 0 for hours in hour_arrays.values())
                    
                    new_row = {
                        'clean_id': key,
                        'cnn': row['cnn'],
                        'corridor': row['corridor'],
                        'limits': row['limits'],
                        'cnn_right_left': row['cnn_right_left'],
                        'block_side': row.get('block_side', ''),
                        **hour_arrays,
                        'schedule_summary': schedule_summary,
                        'total_weekly_hours': total_hours,
                        'has_multiple_windows': False,
                        'week1': int(row['week1']),
                        'week2': int(row['week2']),
                        'week3': int(row['week3']),
                        'week4': int(row['week4']),
                        'week5': int(row.get('week5', 0)),
                        'citation_count': 0,
                        'avg_citation_time': '',
                        'median_citation_time': '',
                        'line': row['line']
                    }
                    aggregated_rows.append(new_row)
        
        # Create final DataFrame
        result_df = pd.DataFrame(aggregated_rows)
        
        # Order columns
        column_order = [
            'clean_id', 'cnn', 'corridor', 'limits', 'cnn_right_left', 'block_side',
            'monday_hours', 'tuesday_hours', 'wednesday_hours', 'thursday_hours', 
            'friday_hours', 'saturday_hours', 'sunday_hours',
            'schedule_summary', 'total_weekly_hours', 'has_multiple_windows',
            'week1', 'week2', 'week3', 'week4', 'week5',
            'citation_count', 'avg_citation_time', 'median_citation_time', 'line'
        ]
        
        result_df = result_df[column_order]
        
        # Sort by CNN, side, and week pattern
        result_df = result_df.sort_values(['cnn', 'cnn_right_left', 'clean_id'])
        
        # Save results
        result_df.to_csv(self.output_file, index=False)
        
        self.logger.info(f"\n✅ Match-based aggregation complete!")
        self.logger.info(f"   Citation matches: {len(matches_df):,}")
        self.logger.info(f"   Output rows: {len(result_df):,} (CNN + Side + Week Pattern)")
        self.logger.info(f"   Saved to: {self.output_file}")
        
        # Generate summary statistics
        self.generate_summary_stats(result_df)
        
        return result_df
    
    def generate_summary_stats(self, result_df: pd.DataFrame):
        """Generate summary statistics"""
        self.logger.info("\n📊 Aggregation Summary:")
        
        # Citation coverage
        with_citations = result_df[result_df['citation_count'] > 0]
        self.logger.info(f"\n🎯 Citation Coverage:")
        self.logger.info(f"   Locations with citations: {len(with_citations):,} ({len(with_citations)/len(result_df)*100:.1f}%)")
        self.logger.info(f"   Locations without citations: {len(result_df) - len(with_citations):,}")
        
        if len(with_citations) > 0:
            # Citation time statistics
            valid_avg_times = with_citations[with_citations['avg_citation_time'] != '']['avg_citation_time'].astype(float)
            self.logger.info(f"\n⏰ Citation Time Statistics:")
            self.logger.info(f"   Unique average times: {valid_avg_times.nunique():,}")
            self.logger.info(f"   Time range: {valid_avg_times.min():.2f} - {valid_avg_times.max():.2f} hours")
            self.logger.info(f"   Overall average: {valid_avg_times.mean():.2f} hours")

def main():
    parser = argparse.ArgumentParser(description='Aggregate schedules using raw match data')
    parser.add_argument('--matches', required=True, help='Input matches CSV file')
    parser.add_argument('--schedules', required=True, help='Input schedules CSV file')
    parser.add_argument('--output', help='Output aggregated CSV file')
    
    args = parser.parse_args()
    
    # Run aggregation
    aggregator = MatchBasedAggregator(args.matches, args.schedules, args.output)
    aggregator.aggregate_from_matches()

if __name__ == "__main__":
    main()