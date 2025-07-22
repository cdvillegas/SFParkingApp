#!/usr/bin/env python3
"""
Spot Check Cleaning Differences

Examines specific records that differ between manual and automated cleaning
to validate whether they should be separate or consolidated.
"""

import pandas as pd
import numpy as np

class SpotCheckAnalyzer:
    def __init__(self, 
                 manual_file: str = "../testing/test_runs/manual_cleaning.csv",
                 automated_file: str = "../testing/sample_data/Street_Sweeping_Schedule_Cleaned_Simple.csv",
                 original_file: str = "../../SF Parking App/Street_Sweeping_Schedule_20250709.csv"):
        
        self.manual_file = manual_file
        self.automated_file = automated_file
        self.original_file = original_file
        
    def load_datasets(self):
        """Load all three datasets for comparison"""
        print("📂 Loading datasets...")
        
        self.manual_df = pd.read_csv(self.manual_file)
        self.automated_df = pd.read_csv(self.automated_file)
        self.original_df = pd.read_csv(self.original_file)
        
        print(f"   Original: {len(self.original_df):,} records")
        print(f"   Manual: {len(self.manual_df):,} records")
        print(f"   Automated: {len(self.automated_df):,} records")
        
    def create_location_keys(self):
        """Create comparable location keys for all datasets"""
        
        # Manual dataset keys
        self.manual_df['location_key'] = (
            self.manual_df['Corridor'].astype(str) + "|" +
            self.manual_df['Limits'].astype(str) + "|" +
            self.manual_df['CNNRightLeft'].astype(str) + "|" +
            self.manual_df['BlockSide'].astype(str)
        )
        
        # Automated dataset keys
        self.automated_df['location_key'] = (
            self.automated_df['Corridor'].astype(str) + "|" +
            self.automated_df['Limits'].astype(str) + "|" +
            self.automated_df['CNNRightLeft'].astype(str) + "|" +
            self.automated_df['BlockSide'].astype(str)
        )
        
        # Original dataset keys
        self.original_df['location_key'] = (
            self.original_df['Corridor'].astype(str) + "|" +
            self.original_df['Limits'].astype(str) + "|" +
            self.original_df['CNNRightLeft'].astype(str) + "|" +
            self.original_df['BlockSide'].astype(str)
        )
        
    def spot_check_aggregation_differences(self):
        """Examine specific cases where automated has more records than manual"""
        print("\n🔍 SPOT CHECKING AGGREGATION DIFFERENCES")
        print("=" * 60)
        
        # Find cases where automated has more records for same location
        manual_counts = self.manual_df['location_key'].value_counts()
        automated_counts = self.automated_df['location_key'].value_counts()
        
        differences = []
        for location in manual_counts.index:
            manual_count = manual_counts.get(location, 0)
            automated_count = automated_counts.get(location, 0)
            if automated_count > manual_count:
                differences.append({
                    'location': location,
                    'manual_count': manual_count, 
                    'automated_count': automated_count,
                    'difference': automated_count - manual_count
                })
        
        # Sort by biggest differences
        differences.sort(key=lambda x: x['difference'], reverse=True)
        
        print(f"Found {len(differences)} locations where automated has more records")
        print(f"\nAnalyzing top cases...\n")
        
        # Examine top 5 cases in detail
        for i, case in enumerate(differences[:5]):
            location = case['location']
            parts = location.split("|")
            
            print(f"📍 CASE {i+1}: {parts[0]} | {parts[1]}")
            print(f"   Manual: {case['manual_count']} record(s)")
            print(f"   Automated: {case['automated_count']} record(s)")
            print(f"   Difference: +{case['difference']} records")
            
            # Get original records for this location
            original_records = self.original_df[self.original_df['location_key'] == location]
            manual_records = self.manual_df[self.manual_df['location_key'] == location]
            automated_records = self.automated_df[self.automated_df['location_key'] == location]
            
            print(f"\n   📋 ORIGINAL DATA ({len(original_records)} records):")
            for _, record in original_records.iterrows():
                print(f"      WeekDay: {record['WeekDay']:15} | FromHour: {record['FromHour']:2} | ToHour: {record['ToHour']:2} | Weeks: {record.get('Week1', '?')}{record.get('Week2', '?')}{record.get('Week3', '?')}{record.get('Week4', '?')}{record.get('Week5', '?')}")
            
            print(f"\n   🔸 MANUAL RESULT ({len(manual_records)} record(s)):")
            for _, record in manual_records.iterrows():
                day_pattern = self.get_manual_day_pattern(record)
                week_pattern = f"{record.get('1', '?')}{record.get('2', '?')}{record.get('3', '?')}{record.get('4', '?')}{record.get('5', '?')}"
                print(f"      Days: {day_pattern:30} | Weeks: {week_pattern}")
            
            print(f"\n   🔹 AUTOMATED RESULT ({len(automated_records)} record(s)):")
            for _, record in automated_records.iterrows():
                day_pattern = record.get('WeekDay', 'N/A')
                week_pattern = f"{record.get('Week1', '?')}{record.get('Week2', '?')}{record.get('Week3', '?')}{record.get('Week4', '?')}{record.get('Week5', '?')}"
                time_range = f"{record.get('FromHour', '?'):2}-{record.get('ToHour', '?'):2}"
                notes_raw = record.get('DataQualityNotes', '')
                notes = str(notes_raw)[:50] + ("..." if len(str(notes_raw)) > 50 else '') if pd.notna(notes_raw) else ''
                print(f"      Days: {day_pattern:30} | Time: {time_range} | Weeks: {week_pattern} | {notes}")
            
            print(f"\n   ❓ ANALYSIS:")
            self.analyze_case(original_records, manual_records, automated_records)
            print(f"\n" + "─" * 60 + "\n")
    
    def get_manual_day_pattern(self, record):
        """Extract day pattern from manual cleaning record"""
        days = []
        day_mapping = {'Sun': 'Sunday', 'Mon': 'Monday', 'Tues': 'Tuesday', 
                      'Wed': 'Wednesday', 'Thu': 'Thursday', 'Fri': 'Friday', 'Sat': 'Saturday'}
        
        for manual_day, standard_day in day_mapping.items():
            if record.get(manual_day, 0) == 1:
                days.append(standard_day)
        
        return '/'.join(days) if days else 'None'
    
    def analyze_case(self, original_records, manual_records, automated_records):
        """Analyze whether automated or manual approach is more correct for this case"""
        
        # Check if original records have different time windows
        time_windows = original_records[['FromHour', 'ToHour']].drop_duplicates()
        unique_times = len(time_windows)
        
        # Check if original records have different week patterns
        week_patterns = original_records[['Week1', 'Week2', 'Week3', 'Week4', 'Week5']].drop_duplicates()
        unique_weeks = len(week_patterns)
        
        # Check if original records have different days
        unique_days = original_records['WeekDay'].nunique()
        
        print(f"      • Original has {unique_times} unique time window(s)")
        print(f"      • Original has {unique_weeks} unique week pattern(s)")
        print(f"      • Original has {unique_days} unique day pattern(s)")
        
        if unique_times > 1:
            print(f"      ⚠️  Multiple time windows - should likely keep separate!")
            print(f"         Time windows: {list(time_windows.itertuples(index=False, name=None))}")
            
        if unique_weeks > 1 and not self.are_complementary_weeks(week_patterns):
            print(f"      ⚠️  Non-complementary week patterns - should likely keep separate!")
            
        # Determine verdict
        if unique_times > 1:
            verdict = "🔹 AUTOMATED appears more correct (preserves time differences)"
        elif unique_weeks > 1 and not self.are_complementary_weeks(week_patterns):
            verdict = "🔹 AUTOMATED appears more correct (preserves week differences)"
        elif len(manual_records) == 1 and len(automated_records) > 1:
            verdict = "🔸 MANUAL may be correct (could consolidate)"
        else:
            verdict = "❓ Unclear - needs human judgment"
            
        print(f"      {verdict}")
    
    def are_complementary_weeks(self, week_patterns_df):
        """Check if week patterns are complementary (e.g., 1st&3rd + 2nd&4th)"""
        if len(week_patterns_df) != 2:
            return False
            
        patterns = week_patterns_df.values
        pattern1 = patterns[0]
        pattern2 = patterns[1]
        
        # Check if they combine to every week (11111) or every-except-5th (11110)
        combined = [max(a, b) for a, b in zip(pattern1, pattern2)]
        return combined in [[1,1,1,1,1], [1,1,1,1,0]]
    
    def spot_check_missing_records(self):
        """Check some records that exist in automated but not in manual"""
        print("\n🔍 SPOT CHECKING MISSING RECORDS")
        print("=" * 60)
        
        manual_keys = set(self.manual_df['location_key'])
        automated_keys = set(self.automated_df['location_key'])
        automated_only = automated_keys - manual_keys
        
        print(f"Found {len(automated_only)} location keys only in automated dataset")
        print(f"Checking first 5 cases...\n")
        
        for i, location in enumerate(list(automated_only)[:5]):
            parts = location.split("|")
            
            print(f"📍 MISSING CASE {i+1}: {parts[0]} | {parts[1]}")
            
            # Get records for this location
            original_records = self.original_df[self.original_df['location_key'] == location]
            automated_records = self.automated_df[self.automated_df['location_key'] == location]
            
            print(f"   📋 ORIGINAL DATA ({len(original_records)} records):")
            if len(original_records) > 0:
                for _, record in original_records.iterrows():
                    print(f"      WeekDay: {record['WeekDay']:15} | Time: {record['FromHour']:2}-{record['ToHour']:2} | Weeks: {record.get('Week1', '?')}{record.get('Week2', '?')}{record.get('Week3', '?')}{record.get('Week4', '?')}{record.get('Week5', '?')}")
            else:
                print(f"      ❌ Not found in original data! This is concerning.")
                
            print(f"\n   🔹 AUTOMATED RESULT ({len(automated_records)} record(s)):")
            for _, record in automated_records.iterrows():
                day_pattern = record.get('WeekDay', 'N/A')
                time_range = f"{record.get('FromHour', '?'):2}-{record.get('ToHour', '?'):2}"
                notes = record.get('DataQualityNotes', '')
                print(f"      Days: {day_pattern:30} | Time: {time_range} | Notes: {notes}")
            
            print(f"\n   ❓ ANALYSIS:")
            if len(original_records) == 0:
                print(f"      ❌ This record doesn't exist in original data - possible bug in automated script")
            else:
                print(f"      ✅ Valid record that was missed in manual cleaning")
            
            print(f"\n" + "─" * 60 + "\n")
    
    def run_spot_check_analysis(self):
        """Run the complete spot check analysis"""
        print("🔍 SPOT CHECK ANALYSIS - VALIDATING CLEANING DIFFERENCES")
        print("=" * 80)
        
        self.load_datasets()
        self.create_location_keys()
        
        # Check aggregation differences
        self.spot_check_aggregation_differences()
        
        # Check missing records
        self.spot_check_missing_records()
        
        print("🎉 Spot check analysis complete!")

def main():
    analyzer = SpotCheckAnalyzer()
    analyzer.run_spot_check_analysis()

if __name__ == "__main__":
    main()