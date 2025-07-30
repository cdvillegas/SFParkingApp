#!/usr/bin/env python3
"""
Aggregate day-specific schedule data using a matrix representation

This script consolidates multiple day-specific rows into one row per CNN + Side + Week Pattern,
using hour arrays for each day of the week to clearly represent when cleaning occurs.

Input: day_specific_sweeper_estimates_*.csv with one row per weekday
Output: app_matrix_schedules_*.csv with hour arrays for each day
"""

import pandas as pd
import numpy as np
import argparse
import logging
from pathlib import Path
from datetime import datetime
import json
from collections import defaultdict

class MatrixScheduleAggregator:
    def __init__(self, input_file: str, output_file: str = None):
        self.input_file = Path(input_file)
        self.output_file = output_file or self.input_file.parent / f"app_matrix_schedules_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
        
        # Set up logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s'
        )
        self.logger = logging.getLogger(__name__)
        
    def create_week_pattern_string(self, row: pd.Series) -> str:
        """Create a string representation of the week pattern"""
        return f"{int(row['week1'])}{int(row['week2'])}{int(row['week3'])}{int(row['week4'])}{int(row['week5'])}"
    
    def generate_schedule_summary(self, hour_arrays: dict) -> str:
        """
        Generate a human-readable schedule summary from hour arrays
        
        Examples:
        - "Monday 7-9am"
        - "Weekdays 8-10am"  
        - "Mon/Wed/Fri 7-9am"
        - "Multiple schedules" (different times)
        """
        # Get active days and their hours
        active_days = []
        time_ranges = set()
        
        day_order = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday']
        
        for day in day_order:
            hours = hour_arrays.get(day, [])
            if hours:
                active_days.append(day)
                if hours:
                    # Convert hours to time range string
                    min_hour = min(hours)
                    max_hour = max(hours) + 1  # +1 because we want end of hour
                    time_range = f"{min_hour}-{max_hour}"
                    time_ranges.add(time_range)
        
        # If different time ranges, it's complex
        if len(time_ranges) > 1:
            return "Multiple schedules"
        
        if not active_days:
            return "No cleaning"
            
        # Format time range
        time_str = ""
        if time_ranges:
            time_range = list(time_ranges)[0]
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
    
    def aggregate_citation_stats(self, group_df: pd.DataFrame) -> dict:
        """
        Aggregate citation statistics across all days for a location
        """
        # Filter rows that have citation data
        citation_rows = group_df[group_df['citation_count'] > 0]
        
        if len(citation_rows) == 0:
            return {
                'citation_count': 0,
                'avg_citation_time': '',
                'median_citation_time': ''
            }
        
        # Sum total citations
        total_citations = citation_rows['citation_count'].sum()
        
        # Calculate weighted average time
        weights = citation_rows['citation_count']
        avg_times = citation_rows['avg_citation_time']
        
        # Filter out any NaN values
        valid_mask = ~(avg_times.isna() | weights.isna())
        if valid_mask.sum() == 0:
            return {
                'citation_count': int(total_citations),
                'avg_citation_time': '',
                'median_citation_time': ''
            }
        
        weights = weights[valid_mask]
        avg_times = avg_times[valid_mask]
        
        weighted_avg = np.average(avg_times, weights=weights)
        
        # For median, approximate from day-specific medians
        median_time = np.median(citation_rows['avg_citation_time'].dropna())
        
        return {
            'citation_count': int(total_citations),
            'avg_citation_time': f"{weighted_avg:.2f}",
            'median_citation_time': f"{median_time:.2f}"
        }
    
    def aggregate_schedules(self):
        """
        Main aggregation function using matrix representation
        """
        self.logger.info(f"Loading day-specific schedule data from: {self.input_file}")
        
        # Load the data
        df = pd.read_csv(self.input_file)
        self.logger.info(f"Loaded {len(df):,} day-specific schedule rows")
        
        # Add week pattern string to each row
        df['week_pattern'] = df.apply(self.create_week_pattern_string, axis=1)
        
        # Group by CNN + Side + Week Pattern
        grouped = df.groupby(['cnn', 'cnn_right_left', 'week_pattern'])
        
        aggregated_rows = []
        
        for (cnn, side, week_pattern), group_df in grouped:
            # Create clean ID
            clean_id = f"{cnn}_{side}_{week_pattern}"
            
            # Get static fields (same for all days in this group)
            static_fields = {
                'clean_id': clean_id,
                'cnn': cnn,
                'corridor': group_df['corridor'].iloc[0],
                'limits': group_df['limits'].iloc[0],
                'cnn_right_left': side,
                'block_side': group_df['block_side'].iloc[0] if pd.notna(group_df['block_side'].iloc[0]) else '',
                'line': group_df['line'].iloc[0]
            }
            
            # Create hour arrays for each day
            hour_arrays = {
                'monday_hours': '',
                'tuesday_hours': '',
                'wednesday_hours': '',
                'thursday_hours': '',
                'friday_hours': '',
                'saturday_hours': '',
                'sunday_hours': ''
            }
            
            # Process each day's schedule
            for _, row in group_df.iterrows():
                day = row['weekday'].lower()
                day_key = f"{day}_hours"
                
                # Create list of active hours
                from_hour = int(row['scheduled_from_hour'])
                to_hour = int(row['scheduled_to_hour'])
                
                # Handle edge cases
                if to_hour <= from_hour:
                    # Probably means until end of day
                    if to_hour == 0:
                        to_hour = 24
                    else:
                        # Skip invalid ranges
                        continue
                
                # Generate hour list
                hours = list(range(from_hour, to_hour))
                hour_arrays[day_key] = ','.join(map(str, hours))
            
            # Generate schedule summary
            # Convert hour arrays to dict format for summary generation
            summary_dict = {}
            for day in ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday']:
                hours_str = hour_arrays[f"{day}_hours"]
                if hours_str:
                    summary_dict[day] = [int(h) for h in hours_str.split(',')]
                else:
                    summary_dict[day] = []
            
            schedule_summary = self.generate_schedule_summary(summary_dict)
            
            # Calculate total weekly hours
            total_hours = sum(len(hours.split(',')) if hours else 0 
                            for hours in hour_arrays.values())
            
            # Check for multiple time windows
            time_windows = set()
            for hours_str in hour_arrays.values():
                if hours_str:
                    hours = [int(h) for h in hours_str.split(',')]
                    if hours:
                        time_windows.add(f"{min(hours)}-{max(hours)+1}")
            
            has_multiple_windows = len(time_windows) > 1
            
            # Aggregate citation statistics
            citation_stats = self.aggregate_citation_stats(group_df)
            
            # Add week pattern as individual columns
            week_cols = {
                'week1': int(week_pattern[0]),
                'week2': int(week_pattern[1]), 
                'week3': int(week_pattern[2]),
                'week4': int(week_pattern[3]),
                'week5': int(week_pattern[4]) if len(week_pattern) > 4 else 0
            }
            
            # Combine all fields
            row = {
                **static_fields,
                **hour_arrays,
                'schedule_summary': schedule_summary,
                'total_weekly_hours': total_hours,
                'has_multiple_windows': has_multiple_windows,
                **week_cols,
                **citation_stats
            }
            
            aggregated_rows.append(row)
        
        # Create final DataFrame
        result_df = pd.DataFrame(aggregated_rows)
        
        # Order columns as specified
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
        
        # Save the results
        result_df.to_csv(self.output_file, index=False)
        
        self.logger.info(f"\n✅ Matrix aggregation complete!")
        self.logger.info(f"   Input: {len(df):,} day-specific rows")
        self.logger.info(f"   Output: {len(result_df):,} aggregated rows (CNN + Side + Week Pattern)")
        self.logger.info(f"   Saved to: {self.output_file}")
        
        # Generate summary statistics
        self.generate_summary_stats(df, result_df)
        
        return result_df
    
    def generate_summary_stats(self, original_df: pd.DataFrame, aggregated_df: pd.DataFrame):
        """
        Generate summary statistics about the aggregation
        """
        self.logger.info("\n📊 Aggregation Summary:")
        
        # Schedule pattern distribution
        schedule_counts = aggregated_df['schedule_summary'].value_counts()
        self.logger.info("\n📅 Top Schedule Patterns:")
        for pattern, count in schedule_counts.head(10).items():
            self.logger.info(f"   {pattern}: {count:,} locations ({count/len(aggregated_df)*100:.1f}%)")
        
        # Citation coverage
        with_citations = aggregated_df[aggregated_df['citation_count'] > 0]
        self.logger.info(f"\n🎯 Citation Coverage:")
        self.logger.info(f"   Locations with citations: {len(with_citations):,} ({len(with_citations)/len(aggregated_df)*100:.1f}%)")
        self.logger.info(f"   Locations without citations: {len(aggregated_df) - len(with_citations):,} ({(len(aggregated_df) - len(with_citations))/len(aggregated_df)*100:.1f}%)")
        
        # Week pattern distribution  
        week_patterns = aggregated_df['clean_id'].str.split('_').str[-1].value_counts()
        self.logger.info("\n📆 Week Patterns:")
        pattern_names = {
            '11111': 'Weekly (all weeks)',
            '10101': 'Bi-weekly (weeks 1,3,5)',
            '01010': 'Bi-weekly (weeks 2,4)',
            '11110': 'Weeks 1-4 only',
            '10100': 'Bi-weekly (weeks 1,3 only)',
            '10000': 'Week 1 only',
            '01000': 'Week 2 only'
        }
        
        for pattern, count in week_patterns.head(10).items():
            pattern_desc = pattern_names.get(pattern, f"Custom ({pattern})")
            self.logger.info(f"   {pattern_desc}: {count:,} locations ({count/len(aggregated_df)*100:.1f}%)")
        
        # Multiple time windows
        multi_window = aggregated_df[aggregated_df['has_multiple_windows']]
        self.logger.info(f"\n⏰ Time Windows:")
        self.logger.info(f"   Single time window: {len(aggregated_df) - len(multi_window):,} ({(len(aggregated_df) - len(multi_window))/len(aggregated_df)*100:.1f}%)")
        self.logger.info(f"   Multiple time windows: {len(multi_window):,} ({len(multi_window)/len(aggregated_df)*100:.1f}%)")

def main():
    parser = argparse.ArgumentParser(description='Aggregate schedules using matrix representation')
    parser.add_argument('--input', required=True, help='Input day-specific CSV file')
    parser.add_argument('--output', help='Output aggregated CSV file')
    
    args = parser.parse_args()
    
    # Run aggregation
    aggregator = MatrixScheduleAggregator(args.input, args.output)
    aggregator.aggregate_schedules()

if __name__ == "__main__":
    main()