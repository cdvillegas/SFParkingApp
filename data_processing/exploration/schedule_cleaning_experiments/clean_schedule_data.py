#!/usr/bin/env python3
"""
Street Sweeping Schedule Data Cleaning Script
Consolidates duplicate records and creates clean dataset

Input: Street_Sweeping_Schedule_20250709.csv
Output: Street_Sweeping_Schedule_Cleaned.csv

Data Quality Fixes:
1. Combine same block/time with different days
2. Merge complementary week patterns (1st&3rd + 2nd&4th)
3. Handle missing coordinates
4. Generate consolidated schedule records
"""

import pandas as pd
import numpy as np
from collections import defaultdict
import re

class ScheduleDataCleaner:
    def __init__(self, input_file_path):
        self.input_file = input_file_path
        self.df = None
        self.cleaned_df = None
        
    def load_data(self):
        """Load the original schedule data"""
        print("📂 Loading schedule data...")
        self.df = pd.read_csv(self.input_file)
        print(f"✅ Loaded {len(self.df):,} records")
        print(f"📊 Original data: {self.df['BlockSweepID'].nunique():,} unique BlockSweepIDs")
        
    def clean_schedule_data(self):
        """Main cleaning process"""
        print("\n🧹 Starting data cleaning process...")
        
        # Step 1: Combine same block/time with different days
        step1_df = self._combine_same_block_different_days(self.df.copy())
        
        # Step 2: Merge complementary week patterns  
        step2_df = self._merge_complementary_week_patterns(step1_df)
        
        # Step 3: Handle missing coordinates
        step3_df = self._handle_missing_coordinates(step2_df)
        
        # Step 4: Generate new BlockSweepIDs and clean up
        self.cleaned_df = self._finalize_clean_data(step3_df)
        
        print(f"\n✅ Cleaning complete!")
        print(f"📊 Before: {len(self.df):,} records")
        print(f"📊 After:  {len(self.cleaned_df):,} records")
        print(f"📉 Reduction: {len(self.df) - len(self.cleaned_df):,} duplicate records removed")
        
    def _combine_same_block_different_days(self, df):
        """Combine records with same block/time but different days"""
        print("\n🔄 Step 1: Combining same block/time with different days...")
        
        # Group by location and time characteristics
        group_columns = ['Corridor', 'Limits', 'CNNRightLeft', 'BlockSide', 'FromHour', 'ToHour', 
                        'Week1', 'Week2', 'Week3', 'Week4', 'Week5', 'Holidays']
        
        grouped = df.groupby(group_columns)
        combined_records = []
        
        for group_key, group_df in grouped:
            if len(group_df) == 1:
                # Single record - keep as is
                combined_records.append(group_df.iloc[0].to_dict())
            else:
                # Multiple records - combine days
                combined_record = self._merge_multiple_day_records(group_df)
                combined_records.append(combined_record)
        
        result_df = pd.DataFrame(combined_records)
        print(f"   Reduced from {len(df)} to {len(result_df)} records")
        return result_df
    
    def _merge_multiple_day_records(self, group_df):
        """Merge multiple records for the same block/time"""
        # Take the first record as base
        base_record = group_df.iloc[0].to_dict()
        
        # Collect all days and create combined description
        days = group_df['WeekDay'].unique()
        weekday_codes = group_df['WeekDay'].unique()
        
        # Create combined FullName
        if len(days) == 1:
            combined_fullname = days[0]
            combined_weekday = weekday_codes[0]
        else:
            # Sort days in logical order
            day_order = {'Mon': 1, 'Tues': 2, 'Wed': 3, 'Thu': 4, 'Fri': 5, 'Sat': 6, 'Sun': 7}
            sorted_days = sorted(days, key=lambda x: day_order.get(x, 8))
            sorted_codes = sorted(weekday_codes, key=lambda x: day_order.get(x, 8))
            
            combined_fullname = '/'.join(sorted_days)
            combined_weekday = '/'.join(sorted_codes)
        
        # Use the first CNN and create combined BlockSweepID
        cnns = group_df['CNN'].tolist()
        combined_cnn = cnns[0] if len(cnns) == 1 else f"COMBINED_{cnns[0]}"
        
        # Combine line geometries if different (take the longest one)
        lines = group_df['Line'].dropna().unique()
        combined_line = lines[0] if len(lines) > 0 else base_record['Line']
        if len(lines) > 1:
            # Take the longest line (most coordinates)
            longest_line = max(lines, key=lambda x: len(str(x)) if pd.notna(x) else 0)
            combined_line = longest_line
        
        # Update the base record
        base_record.update({
            'CNN': combined_cnn,
            'FullName': combined_fullname,
            'WeekDay': combined_weekday,
            'BlockSweepID': f"{base_record['BlockSweepID']}_COMBINED",
            'Line': combined_line,
            'DataQualityNotes': f"Combined {len(group_df)} records with different days"
        })
        
        return base_record
    
    def _merge_complementary_week_patterns(self, df):
        """Merge records with complementary week patterns (1st&3rd + 2nd&4th)"""
        print("\n🔄 Step 2: Merging complementary week patterns...")
        
        # Group by location, day, and time
        group_columns = ['Corridor', 'Limits', 'CNNRightLeft', 'BlockSide', 'WeekDay', 'FromHour', 'ToHour', 'Holidays']
        grouped = df.groupby(group_columns)
        
        merged_records = []
        
        for group_key, group_df in grouped:
            if len(group_df) == 1:
                # Single record - keep as is
                merged_records.append(group_df.iloc[0].to_dict())
            elif len(group_df) == 2:
                # Check if patterns are complementary
                patterns = []
                for _, row in group_df.iterrows():
                    pattern = (row['Week1'], row['Week2'], row['Week3'], row['Week4'], row['Week5'])
                    patterns.append(pattern)
                
                # Check if they combine to every week or every-except-5th
                combined_pattern = tuple(max(a, b) for a, b in zip(patterns[0], patterns[1]))
                
                if combined_pattern in [(1,1,1,1,1), (1,1,1,1,0)]:
                    # Complementary patterns - merge them
                    merged_record = self._merge_complementary_records(group_df, combined_pattern)
                    merged_records.append(merged_record)
                else:
                    # Not complementary - keep separate
                    for _, row in group_df.iterrows():
                        merged_records.append(row.to_dict())
            else:
                # More than 2 records - keep separate for now
                for _, row in group_df.iterrows():
                    merged_records.append(row.to_dict())
        
        result_df = pd.DataFrame(merged_records)
        print(f"   Reduced from {len(df)} to {len(result_df)} records")
        return result_df
    
    def _merge_complementary_records(self, group_df, combined_pattern):
        """Merge two complementary week pattern records"""
        # Take the first record as base
        base_record = group_df.iloc[0].to_dict()
        
        # Update week pattern
        base_record['Week1'] = combined_pattern[0]
        base_record['Week2'] = combined_pattern[1] 
        base_record['Week3'] = combined_pattern[2]
        base_record['Week4'] = combined_pattern[3]
        base_record['Week5'] = combined_pattern[4]
        
        # Update FullName to reflect weekly schedule
        if combined_pattern == (1,1,1,1,1):
            # Every week including 5th
            base_record['FullName'] = base_record['WeekDay']
        elif combined_pattern == (1,1,1,1,0):
            # Every week except 5th
            base_record['FullName'] = f"{base_record['WeekDay']} (except 5th week)"
        
        # Combine CNNs and BlockSweepIDs
        cnns = group_df['CNN'].tolist()
        block_ids = group_df['BlockSweepID'].tolist()
        
        base_record['CNN'] = cnns[0]  # Use first CNN
        base_record['BlockSweepID'] = f"{block_ids[0]}_MERGED"
        
        # Add data quality note
        base_record['DataQualityNotes'] = f"Merged complementary week patterns: {len(group_df)} records"
        
        return base_record
    
    def _handle_missing_coordinates(self, df):
        """Handle records with missing coordinate data"""
        print("\n🔄 Step 3: Handling missing coordinates...")
        
        missing_coords = df[df['Line'].isna() | (df['Line'] == '')]
        print(f"   Found {len(missing_coords)} records with missing coordinates")
        
        if len(missing_coords) > 0:
            # Flag missing coordinates for manual review
            df.loc[df['Line'].isna() | (df['Line'] == ''), 'DataQualityNotes'] = 'Missing GPS coordinates - needs manual review'
            print(f"   Flagged {len(missing_coords)} records for coordinate review")
        
        return df
    
    def _finalize_clean_data(self, df):
        """Generate final clean dataset with new IDs"""
        print("\n🔄 Step 4: Finalizing clean dataset...")
        
        # Generate new sequential BlockSweepIDs for clean data
        df = df.reset_index(drop=True)
        df['CleanBlockSweepID'] = range(1000000, 1000000 + len(df))
        
        # Add data quality notes column if not exists
        if 'DataQualityNotes' not in df.columns:
            df['DataQualityNotes'] = ''
        
        # Add day-of-week boolean columns
        df = self._add_day_of_week_columns(df)
        
        # Reorder columns for better readability
        column_order = [
            'CleanBlockSweepID', 'CNN', 'Corridor', 'Limits', 'CNNRightLeft', 'BlockSide',
            'FullName', 'WeekDay', 'FromHour', 'ToHour',
            'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
            'Week1', 'Week2', 'Week3', 'Week4', 'Week5', 'Holidays',
            'BlockSweepID', 'Line', 'DataQualityNotes'
        ]
        
        # Ensure all columns exist
        for col in column_order:
            if col not in df.columns:
                df[col] = 0 if col in ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'] else ''
        
        cleaned_df = df[column_order]
        
        return cleaned_df
    
    def _add_day_of_week_columns(self, df):
        """Add boolean columns for each day of the week"""
        print("   Adding day-of-week boolean columns...")
        
        # Initialize all day columns to 0
        day_columns = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
        for day in day_columns:
            df[day] = 0
        
        # Parse WeekDay string and set appropriate columns to 1
        for idx, row in df.iterrows():
            weekday_str = str(row['WeekDay']).upper()
            
            # Handle various day formats
            day_mappings = {
                'MON': 'Monday',
                'MONDAY': 'Monday',
                'TUES': 'Tuesday', 
                'TUE': 'Tuesday',
                'TUESDAY': 'Tuesday',
                'WED': 'Wednesday',
                'WEDNESDAY': 'Wednesday',
                'THU': 'Thursday',
                'THUR': 'Thursday', 
                'THURSDAY': 'Thursday',
                'FRI': 'Friday',
                'FRIDAY': 'Friday',
                'SAT': 'Saturday',
                'SATURDAY': 'Saturday',
                'SUN': 'Sunday',
                'SUNDAY': 'Sunday'
            }
            
            # Check each day mapping
            for day_code, day_name in day_mappings.items():
                if day_code in weekday_str:
                    df.at[idx, day_name] = 1
        
        return df
    
    def save_cleaned_data(self, output_file):
        """Save the cleaned dataset"""
        print(f"\n💾 Saving cleaned data to {output_file}...")
        self.cleaned_df.to_csv(output_file, index=False)
        print(f"✅ Saved {len(self.cleaned_df):,} cleaned records")
        
    def generate_cleaning_report(self, report_file):
        """Generate a report of cleaning actions"""
        print(f"\n📊 Generating cleaning report...")
        
        # Calculate statistics
        original_count = len(self.df)
        cleaned_count = len(self.cleaned_df)
        reduction = original_count - cleaned_count
        reduction_pct = (reduction / original_count) * 100
        
        # Count different types of cleaning actions
        combined_records = len(self.cleaned_df[self.cleaned_df['DataQualityNotes'].str.contains('Combined', na=False)])
        merged_records = len(self.cleaned_df[self.cleaned_df['DataQualityNotes'].str.contains('Merged', na=False)])
        missing_coords = len(self.cleaned_df[self.cleaned_df['DataQualityNotes'].str.contains('Missing GPS', na=False)])
        
        report = f"""
STREET SWEEPING SCHEDULE DATA CLEANING REPORT
Generated: {pd.Timestamp.now().strftime('%Y-%m-%d %H:%M:%S')}

ORIGINAL DATA:
- Total records: {original_count:,}
- Unique BlockSweepIDs: {self.df['BlockSweepID'].nunique():,}
- Unique street corridors: {self.df['Corridor'].nunique():,}

CLEANED DATA:
- Total records: {cleaned_count:,}
- Reduction: {reduction:,} records ({reduction_pct:.1f}%)
- New CleanBlockSweepIDs: {cleaned_count:,}

CLEANING ACTIONS:
- Combined same block/different days: {combined_records:,} records
- Merged complementary week patterns: {merged_records:,} records  
- Missing coordinates flagged: {missing_coords:,} records

DATA QUALITY IMPROVEMENTS:
✅ Eliminated duplicate schedules for same block/time
✅ Consolidated partial week patterns into complete schedules
✅ Flagged missing coordinate data for review
✅ Generated clean sequential IDs
✅ Added data quality tracking

NEXT STEPS:
1. Review flagged records with missing coordinates
2. Validate cleaned schedules against original data
3. Use cleaned data for citation matching analysis
4. Update iOS app to use CleanBlockSweepID
"""
        
        with open(report_file, 'w') as f:
            f.write(report)
        
        print(f"✅ Report saved to {report_file}")
        print(report)

def main():
    """Main cleaning process"""
    
    # File paths
    input_file = '/Users/zshor/Desktop/SFParkingApp/SF Parking App/Street_Sweeping_Schedule_20250709.csv'
    output_file = '/Users/zshor/Desktop/SFParkingApp/data_processing/Street_Sweeping_Schedule_Cleaned.csv'
    report_file = '/Users/zshor/Desktop/SFParkingApp/data_processing/cleaning_report.txt'
    
    print("🧹 STREET SWEEPING SCHEDULE DATA CLEANING")
    print("=" * 60)
    
    # Initialize cleaner
    cleaner = ScheduleDataCleaner(input_file)
    
    # Run cleaning process
    cleaner.load_data()
    cleaner.clean_schedule_data()
    cleaner.save_cleaned_data(output_file)
    cleaner.generate_cleaning_report(report_file)
    
    print(f"\n🎉 Data cleaning complete!")
    print(f"📁 Cleaned data: {output_file}")
    print(f"📊 Report: {report_file}")

if __name__ == "__main__":
    main()