#!/usr/bin/env python3
"""
Street Sweeping Schedule Data Cleaning Script - DAY SPECIFIC APPROACH
Creates separate rows for each active day instead of aggregating across days

Input: Street_Sweeping_Schedule_20250709.csv
Output: Street_Sweeping_Schedule_Day_Specific.csv
"""

import pandas as pd
import numpy as np
import argparse
from datetime import datetime
from pathlib import Path

class DaySpecificScheduleDataCleaner:
    def __init__(self, input_file_path, output_dir=None):
        self.input_file = input_file_path
        self.output_dir = Path(output_dir) if output_dir else Path('.')
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.df = None
        self.cleaned_df = None
        
    def load_data(self):
        """Load the original schedule data"""
        print("📂 Loading schedule data...")
        self.df = pd.read_csv(self.input_file)
        print(f"✅ Loaded {len(self.df):,} records")
        
    def clean_schedule_data_day_specific(self):
        """Clean data creating separate rows for each active day"""
        print("\n🧹 Starting DAY-SPECIFIC data cleaning process...")
        
        # Step 1: Normalize each row to standard structure
        normalized_rows = []
        
        print("📋 Step 1: Normalizing all rows...")
        for _, row in self.df.iterrows():
            normalized = self._normalize_row(row)
            normalized_rows.append(normalized)
        
        # Step 2: Group by location to combine duplicates BEFORE day expansion
        print("📋 Step 2: Grouping and combining duplicates...")
        normalized_df = pd.DataFrame(normalized_rows)
        
        # Group by location characteristics and combine using max (0+1=1, 1+1=1)
        location_columns = ['Corridor', 'Limits', 'CNNRightLeft', 'BlockSide', 'FromHour', 'ToHour']
        
        # Columns to combine using max
        combine_columns = [
            'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
            'Week1', 'Week2', 'Week3', 'Week4', 'Week5', 'Holidays'
        ]
        
        # Columns to take first value
        first_columns = ['CNN', 'Line']
        
        # Group and aggregate
        agg_dict = {}
        
        # Use max for boolean/combineable columns
        for col in combine_columns:
            agg_dict[col] = 'max'
        
        # Use first for identifier columns
        for col in first_columns:
            agg_dict[col] = 'first'
        
        # Group and aggregate
        combined_df = normalized_df.groupby(location_columns).agg(agg_dict).reset_index()
        
        # Add record count based on group size
        combined_df['RecordCount'] = normalized_df.groupby(location_columns).size().values
        
        # Step 3: Expand into day-specific rows
        print("📋 Step 3: Expanding into day-specific rows...")
        day_specific_rows = []
        
        for _, schedule in combined_df.iterrows():
            # Create a row for each active day
            for day in ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']:
                if schedule[day] == 1:  # This day is active
                    day_row = {
                        'original_schedule_id': len(day_specific_rows) + 1,  # Temporary, will be replaced
                        'weekday': day,
                        'cnn': schedule['CNN'],
                        'corridor': schedule['Corridor'], 
                        'limits': schedule['Limits'],
                        'cnn_right_left': schedule['CNNRightLeft'],
                        'block_side': schedule['BlockSide'],
                        'scheduled_from_hour': schedule['FromHour'],
                        'scheduled_to_hour': schedule['ToHour'],
                        'week1': schedule['Week1'],
                        'week2': schedule['Week2'],
                        'week3': schedule['Week3'],
                        'week4': schedule['Week4'],
                        'week5': schedule['Week5'],
                        'holidays': schedule['Holidays'],
                        'line': schedule['Line'],
                        'record_count': schedule['RecordCount']
                    }
                    day_specific_rows.append(day_row)
        
        # Step 4: Create final DataFrame and generate clean IDs
        print("📋 Step 4: Generating clean identifiers...")
        self.cleaned_df = pd.DataFrame(day_specific_rows)
        
        # Generate clean schedule IDs
        self.cleaned_df['schedule_id'] = range(2000000, 2000000 + len(self.cleaned_df))
        
        # Create full name for reference
        full_names = []
        for _, row in self.cleaned_df.iterrows():
            # Build day string
            day = row['weekday']
            
            # Build week string
            weeks = []
            for w in [1, 2, 3, 4, 5]:
                if row[f'week{w}'] == 1:
                    weeks.append(str(w))
            week_str = '/'.join(weeks) if weeks else 'None'
            
            full_name = f"{day} (Weeks {week_str})"
            full_names.append(full_name)
        
        self.cleaned_df['full_name'] = full_names
        
        # Reorder columns to match expected output format
        column_order = [
            'schedule_id', 'cnn', 'corridor', 'limits', 'cnn_right_left', 'block_side',
            'full_name', 'weekday', 'scheduled_from_hour', 'scheduled_to_hour',
            'week1', 'week2', 'week3', 'week4', 'week5', 'holidays',
            'record_count', 'line'
        ]
        
        self.cleaned_df = self.cleaned_df[column_order]
        
        print(f"\n✅ Day-specific cleaning complete!")
        print(f"📊 Original records: {len(self.df):,}")
        print(f"📊 After grouping: {len(combined_df):,}")
        print(f"📊 After day expansion: {len(self.cleaned_df):,}")
        print(f"📈 Expansion factor: {len(self.cleaned_df) / len(combined_df):.1f}x")
        
    def _normalize_row(self, row):
        """Convert a single row to normalized structure"""
        
        # Parse days from weekday string (handle various column name formats)
        weekday_str = ''
        for col_name in ['WeekDay', 'weekday', 'fullname']:
            if col_name in row and pd.notna(row[col_name]):
                weekday_str = str(row[col_name]).upper()
                break
        
        # Handle Holiday as a special case - treat as Sunday for grouping purposes
        if 'HOLIDAY' in weekday_str:
            weekday_str = 'SUN/HOLIDAY'
        
        day_mappings = {
            'Monday': any(day in weekday_str for day in ['MON']),
            'Tuesday': any(day in weekday_str for day in ['TUES', 'TUE']),
            'Wednesday': any(day in weekday_str for day in ['WED']),
            'Thursday': any(day in weekday_str for day in ['THU']),
            'Friday': any(day in weekday_str for day in ['FRI']),
            'Saturday': any(day in weekday_str for day in ['SAT']),
            'Sunday': any(day in weekday_str for day in ['SUN', 'HOLIDAY'])
        }
        
        # Parse weeks directly from individual week columns (handle various column name formats)
        week_mappings = {
            'Week1': bool(int(row.get('week1', row.get('Week1', 0)))),
            'Week2': bool(int(row.get('week2', row.get('Week2', 0)))),
            'Week3': bool(int(row.get('week3', row.get('Week3', 0)))),
            'Week4': bool(int(row.get('week4', row.get('Week4', 0)))),
            'Week5': bool(int(row.get('week5', row.get('Week5', 0))))
        }
        
        # Handle holidays
        holidays = 1 if 'HOLIDAY' in weekday_str else 0
        
        # Build normalized row - handle case variations in column names
        normalized = {
            'CNN': row.get('cnn', row.get('CNN', 0)),
            'Corridor': str(row.get('corridor', row.get('Corridor', ''))).strip(),
            'Limits': str(row.get('limits', row.get('Limits', ''))).strip(),
            'CNNRightLeft': str(row.get('cnnrightleft', row.get('CNNRightLeft', ''))).strip(),
            'BlockSide': str(row.get('blockside', row.get('BlockSide', ''))).strip(),
            'FromHour': self._parse_hour(row.get('fromhour', row.get('FromHour', 0))),
            'ToHour': self._parse_hour(row.get('tohour', row.get('ToHour', 24))),
            'Line': str(row.get('line', row.get('Line', ''))),
            'Holidays': holidays,
            **{f'{day}': 1 if active else 0 for day, active in day_mappings.items()},
            **{f'{week}': 1 if active else 0 for week, active in week_mappings.items()}
        }
        
        return normalized
    
    def _parse_hour(self, hour_value):
        """Parse hour value to integer"""
        try:
            if pd.isna(hour_value):
                return 0
            return int(float(hour_value))
        except (ValueError, TypeError):
            return 0
    
    def save_cleaned_data(self, output_file):
        """Save cleaned data to CSV"""
        if self.cleaned_df is None:
            raise ValueError("No cleaned data available. Run clean_schedule_data_day_specific() first.")
        
        print(f"\n💾 Saving cleaned data to {output_file}...")
        self.cleaned_df.to_csv(output_file, index=False)
        print(f"✅ Saved {len(self.cleaned_df):,} day-specific schedule records")
        
    def generate_report(self, output_file=None):
        """Generate cleaning report"""
        if self.cleaned_df is None:
            raise ValueError("No cleaned data available. Run clean_schedule_data_day_specific() first.")
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        if output_file:
            report_file = output_file
        else:
            report_file = self.output_dir / f"day_specific_cleaning_report_{timestamp}.txt"
        
        report = []
        report.append("=" * 60)
        report.append("DAY-SPECIFIC SCHEDULE DATA CLEANING REPORT")
        report.append("=" * 60)
        report.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        report.append("")
        
        # Basic statistics
        report.append("PROCESSING SUMMARY:")
        report.append(f"  Original records: {len(self.df):,}")
        report.append(f"  Day-specific records: {len(self.cleaned_df):,}")
        report.append("")
        
        # Day distribution
        report.append("DAY DISTRIBUTION:")
        day_counts = self.cleaned_df['weekday'].value_counts()
        for day in ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']:
            count = day_counts.get(day, 0)
            pct = count / len(self.cleaned_df) * 100
            report.append(f"  {day:>9}: {count:,} schedules ({pct:.1f}%)")
        report.append("")
        
        # Week distribution
        report.append("WEEK DISTRIBUTION:")
        for week in [1, 2, 3, 4, 5]:
            count = self.cleaned_df[f'week{week}'].sum()
            pct = count / len(self.cleaned_df) * 100
            report.append(f"  Week {week}: {count:,} schedules ({pct:.1f}%)")
        report.append("")
        
        # Time distribution
        report.append("TIME DISTRIBUTION:")
        time_counts = self.cleaned_df.groupby(['scheduled_from_hour', 'scheduled_to_hour']).size().sort_values(ascending=False)
        report.append("  Top 10 time windows:")
        for (from_h, to_h), count in time_counts.head(10).items():
            pct = count / len(self.cleaned_df) * 100
            report.append(f"    {from_h:02d}:00-{to_h:02d}:00: {count:,} schedules ({pct:.1f}%)")
        
        report_text = "\n".join(report)
        
        with open(report_file, 'w') as f:
            f.write(report_text)
        
        print(f"📄 Report saved to {report_file}")
        return report_text

def main():
    parser = argparse.ArgumentParser(description='Clean street sweeping schedule data with day-specific rows')
    parser.add_argument('--input', required=True, help='Input CSV file path')
    parser.add_argument('--output', required=True, help='Output CSV file path')
    parser.add_argument('--report', help='Report file path (optional)')
    parser.add_argument('--output-dir', help='Output directory for generated files (reports, etc.)')
    
    args = parser.parse_args()
    
    # Initialize cleaner and process
    cleaner = DaySpecificScheduleDataCleaner(args.input, args.output_dir)
    
    # Process data
    cleaner.load_data()
    cleaner.clean_schedule_data_day_specific()
    
    # Save results
    cleaner.save_cleaned_data(args.output)
    
    # Generate report
    report = cleaner.generate_report(args.report)
    print("\n" + "="*60)
    print("CLEANING SUMMARY")
    print("="*60)
    print(report.split("PROCESSING SUMMARY:")[1].split("DAY DISTRIBUTION:")[0])

if __name__ == "__main__":
    main()