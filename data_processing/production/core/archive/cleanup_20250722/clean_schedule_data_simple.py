#!/usr/bin/env python3
"""
Street Sweeping Schedule Data Cleaning Script - SIMPLE APPROACH
Uses groupby + sum approach instead of complex merging logic

Input: Street_Sweeping_Schedule_20250709.csv
Output: Street_Sweeping_Schedule_Cleaned_Simple.csv
"""

import pandas as pd
import numpy as np

class SimpleScheduleDataCleaner:
    def __init__(self, input_file_path):
        self.input_file = input_file_path
        self.df = None
        self.cleaned_df = None
        
    def load_data(self):
        """Load the original schedule data"""
        print("📂 Loading schedule data...")
        self.df = pd.read_csv(self.input_file)
        print(f"✅ Loaded {len(self.df):,} records")
        
    def clean_schedule_data_simple(self):
        """Simple cleaning using groupby + sum approach"""
        print("\n🧹 Starting SIMPLE data cleaning process...")
        
        # Step 1: Normalize each row to standard structure
        normalized_rows = []
        
        print("📋 Step 1: Normalizing all rows...")
        for _, row in self.df.iterrows():
            normalized = self._normalize_row(row)
            normalized_rows.append(normalized)
        
        # Step 2: Create DataFrame and group by location
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
        
        # Step 3: Generate clean identifiers and descriptions
        print("📋 Step 3: Generating clean identifiers...")
        self.cleaned_df = self._finalize_simple_data(combined_df)
        
        print(f"\n✅ Simple cleaning complete!")
        print(f"📊 Before: {len(self.df):,} records")
        print(f"📊 After:  {len(self.cleaned_df):,} records")
        print(f"📉 Reduction: {len(self.df) - len(self.cleaned_df):,} duplicate records removed")
        
    def _normalize_row(self, row):
        """Convert a single row to normalized structure"""
        
        # Parse days from weekday string (handle both 'WeekDay' and 'weekday' columns)
        if 'WeekDay' in row:
            weekday_str = str(row['WeekDay']).upper()
        elif 'weekday' in row:
            weekday_str = str(row['weekday']).upper()
        else:
            weekday_str = ''
        
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
        
        # Create normalized row - handle both API (lowercase) and local file (CamelCase) columns
        def get_column_value(row, api_name, local_name):
            """Get value from either API column name (lowercase) or local file name (CamelCase)"""
            if api_name in row:
                return row[api_name]
            elif local_name in row:
                return row[local_name]
            else:
                return None
                
        normalized = {
            # Location identifiers
            'CNN': get_column_value(row, 'cnn', 'CNN'),
            'Corridor': get_column_value(row, 'corridor', 'Corridor'),
            'Limits': get_column_value(row, 'limits', 'Limits'),
            'CNNRightLeft': get_column_value(row, 'cnnrightleft', 'CNNRightLeft'),
            'BlockSide': get_column_value(row, 'blockside', 'BlockSide'),
            'FromHour': get_column_value(row, 'fromhour', 'FromHour'),
            'ToHour': get_column_value(row, 'tohour', 'ToHour'),
            'Line': get_column_value(row, 'line', 'Line'),
            
            # Day of week flags (0 or 1)
            'Monday': 1 if day_mappings['Monday'] else 0,
            'Tuesday': 1 if day_mappings['Tuesday'] else 0,
            'Wednesday': 1 if day_mappings['Wednesday'] else 0,
            'Thursday': 1 if day_mappings['Thursday'] else 0,
            'Friday': 1 if day_mappings['Friday'] else 0,
            'Saturday': 1 if day_mappings['Saturday'] else 0,
            'Sunday': 1 if day_mappings['Sunday'] else 0,
            
            # Week pattern flags
            'Week1': get_column_value(row, 'week1', 'Week1'),
            'Week2': get_column_value(row, 'week2', 'Week2'),
            'Week3': get_column_value(row, 'week3', 'Week3'),
            'Week4': get_column_value(row, 'week4', 'Week4'),
            'Week5': get_column_value(row, 'week5', 'Week5'),
            'Holidays': get_column_value(row, 'holidays', 'Holidays'),
            
            # Original identifier for tracking
            'OriginalBlockSweepID': get_column_value(row, 'blocksweepid', 'BlockSweepID')
        }
        
        return normalized
    
    def _finalize_simple_data(self, combined_df):
        """Generate final clean dataset with descriptions"""
        
        # Generate new sequential IDs
        combined_df['CleanBlockSweepID'] = range(2000000, 2000000 + len(combined_df))
        
        # Generate WeekDay description from boolean flags
        day_columns = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
        day_abbrev = ['Mon', 'Tues', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        
        weekday_descriptions = []
        weekday_codes = []
        fullname_descriptions = []
        
        for _, row in combined_df.iterrows():
            # Get active days
            active_days = [day_abbrev[i] for i, day in enumerate(day_columns) if row[day] == 1]
            active_day_names = [day_columns[i] for i, day in enumerate(day_columns) if row[day] == 1]
            
            if len(active_days) == 1:
                weekday_desc = active_days[0]
                weekday_code = active_days[0] 
                fullname = active_day_names[0]
            else:
                weekday_desc = '/'.join(active_days)
                weekday_code = '/'.join(active_days)
                fullname = '/'.join(active_day_names)
            
            weekday_descriptions.append(weekday_desc)
            weekday_codes.append(weekday_code)
            fullname_descriptions.append(fullname)
        
        combined_df['WeekDay'] = weekday_codes
        combined_df['FullName'] = fullname_descriptions
        
        # Generate data quality notes
        data_quality_notes = []
        for _, row in combined_df.iterrows():
            record_count = row['RecordCount']
            if record_count > 1:
                note = f"Combined {record_count} duplicate records using groupby method"
            else:
                note = ""
            data_quality_notes.append(note)
        
        combined_df['DataQualityNotes'] = data_quality_notes
        
        # Handle missing coordinates
        missing_coords_mask = combined_df['Line'].isna() | (combined_df['Line'] == '')
        combined_df.loc[missing_coords_mask, 'DataQualityNotes'] = combined_df.loc[missing_coords_mask, 'DataQualityNotes'] + " Missing GPS coordinates"
        
        # Final column order
        column_order = [
            'CleanBlockSweepID', 'CNN', 'Corridor', 'Limits', 'CNNRightLeft', 'BlockSide',
            'FullName', 'WeekDay', 'FromHour', 'ToHour',
            'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
            'Week1', 'Week2', 'Week3', 'Week4', 'Week5', 'Holidays',
            'RecordCount', 'Line', 'DataQualityNotes'
        ]
        
        return combined_df[column_order]
    
    def save_cleaned_data(self, output_file):
        """Save the cleaned dataset"""
        print(f"\n💾 Saving cleaned data to {output_file}...")
        self.cleaned_df.to_csv(output_file, index=False)
        print(f"✅ Saved {len(self.cleaned_df):,} cleaned records")
        
    def generate_cleaning_report(self, report_file):
        """Generate a report of cleaning actions"""
        print(f"\n📊 Generating cleaning report...")
        
        original_count = len(self.df)
        cleaned_count = len(self.cleaned_df)
        reduction = original_count - cleaned_count
        reduction_pct = (reduction / original_count) * 100
        
        # Count different types of records
        combined_records = len(self.cleaned_df[self.cleaned_df['RecordCount'] > 1])
        single_records = len(self.cleaned_df[self.cleaned_df['RecordCount'] == 1])
        missing_coords = len(self.cleaned_df[self.cleaned_df['DataQualityNotes'].str.contains('Missing GPS', na=False)])
        
        # Get original unique identifiers (handle both API and local columns)
        if 'BlockSweepID' in self.df.columns:
            unique_original = self.df['BlockSweepID'].nunique()
        elif 'blocksweepid' in self.df.columns:
            unique_original = self.df['blocksweepid'].nunique()
        else:
            unique_original = len(self.df)
        
        report = f"""
STREET SWEEPING SCHEDULE DATA CLEANING REPORT - SIMPLE METHOD
Generated: {pd.Timestamp.now().strftime('%Y-%m-%d %H:%M:%S')}

ORIGINAL DATA:
- Total records: {original_count:,}
- Unique BlockSweepIDs: {unique_original:,}

CLEANED DATA (SIMPLE METHOD):
- Total records: {cleaned_count:,}
- Reduction: {reduction:,} records ({reduction_pct:.1f}%)
- New CleanBlockSweepIDs: {cleaned_count:,}

CLEANING ACTIONS:
- Records requiring combination: {combined_records:,}
- Records kept as-is: {single_records:,}
- Missing coordinates flagged: {missing_coords:,}

METHOD USED:
✅ Simple groupby + max aggregation approach
✅ Automatic handling of all duplicate patterns
✅ Mathematical combination instead of complex logic
✅ More reliable and maintainable code

NEXT STEPS:
1. Compare with complex method results
2. Validate identical outcomes
3. Use simple method going forward
"""
        
        with open(report_file, 'w') as f:
            f.write(report)
        
        print(f"✅ Report saved to {report_file}")
        print(report)

def main():
    """Main cleaning process using simple method"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Clean SF street sweeping schedule data')
    parser.add_argument('--input', required=False, 
                       default='/Users/zshor/Desktop/SFParkingApp/SF Parking App/Street_Sweeping_Schedule_20250709.csv',
                       help='Input CSV file path')
    parser.add_argument('--output', required=False, 
                       default='/Users/zshor/Desktop/SFParkingApp/data_processing/Street_Sweeping_Schedule_Cleaned_Simple.csv',
                       help='Output CSV file path')
    
    args = parser.parse_args()
    
    # File paths
    input_file = args.input
    output_file = args.output
    report_file = output_file.replace('.csv', '_report.txt')
    
    print("🧹 STREET SWEEPING SCHEDULE DATA CLEANING - SIMPLE METHOD")
    print("=" * 70)
    
    # Initialize cleaner
    cleaner = SimpleScheduleDataCleaner(input_file)
    
    # Run cleaning process
    cleaner.load_data()
    cleaner.clean_schedule_data_simple()
    cleaner.save_cleaned_data(output_file)
    cleaner.generate_cleaning_report(report_file)
    
    print(f"\n🎉 Simple data cleaning complete!")
    print(f"📁 Cleaned data: {output_file}")
    print(f"📊 Report: {report_file}")

if __name__ == "__main__":
    main()