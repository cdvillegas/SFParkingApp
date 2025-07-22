#!/usr/bin/env python3
"""
Compare Manual vs Automated Schedule Cleaning Results

Analyzes the differences between manual cleaning and automated script results
to identify discrepancies and understand why row counts differ.
"""

import pandas as pd
import numpy as np
from typing import Dict, List, Set

class CleaningComparisonAnalyzer:
    def __init__(self, 
                 manual_file: str = "../testing/test_runs/manual_cleaning.csv",
                 automated_file: str = "../testing/sample_data/Street_Sweeping_Schedule_Cleaned_Simple.csv"):
        
        self.manual_file = manual_file
        self.automated_file = automated_file
        
    def load_datasets(self):
        """Load both datasets and normalize column structures for comparison"""
        print("📂 Loading datasets...")
        
        # Load manual cleaning
        self.manual_df = pd.read_csv(self.manual_file)
        print(f"   Manual cleaning: {len(self.manual_df):,} records")
        
        # Load automated cleaning  
        self.automated_df = pd.read_csv(self.automated_file)
        print(f"   Automated cleaning: {len(self.automated_df):,} records")
        print(f"   Difference: {len(self.automated_df) - len(self.manual_df):,} records")
        
    def analyze_column_structures(self):
        """Compare column structures between datasets"""
        print("\n📋 COLUMN STRUCTURE ANALYSIS")
        print("=" * 50)
        
        manual_cols = set(self.manual_df.columns)
        automated_cols = set(self.automated_df.columns)
        
        print(f"Manual columns ({len(manual_cols)}): {sorted(manual_cols)}")
        print(f"Automated columns ({len(automated_cols)}): {sorted(automated_cols)}")
        
        common_cols = manual_cols & automated_cols
        manual_only = manual_cols - automated_cols
        automated_only = automated_cols - manual_cols
        
        print(f"\n✅ Common columns ({len(common_cols)}): {sorted(common_cols)}")
        if manual_only:
            print(f"🔸 Manual only ({len(manual_only)}): {sorted(manual_only)}")
        if automated_only:
            print(f"🔹 Automated only ({len(automated_only)}): {sorted(automated_only)}")
            
        return common_cols
        
    def normalize_for_comparison(self, common_cols: Set[str]):
        """Create comparable datasets using common columns and structure"""
        print("\n🔄 NORMALIZING DATASETS FOR COMPARISON")
        print("=" * 50)
        
        # Create normalized comparison keys
        # For manual: use available columns
        manual_key_cols = ['CNN', 'Corridor', 'CNNRightLeft', 'Limits', 'BlockSide']
        manual_day_cols = ['Sun', 'Mon', 'Tues', 'Wed', 'Thu', 'Fri', 'Sat'] 
        manual_week_cols = ['1', '2', '3', '4', '5']  # Week columns in manual
        
        # For automated: use corresponding columns
        auto_key_cols = ['CNN', 'Corridor', 'CNNRightLeft', 'Limits', 'BlockSide']
        auto_day_cols = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
        auto_week_cols = ['Week1', 'Week2', 'Week3', 'Week4', 'Week5']
        
        # Create comparison keys for manual dataset
        self.manual_df['comparison_key'] = (
            self.manual_df['CNN'].astype(str) + "|" +
            self.manual_df['Corridor'].astype(str) + "|" + 
            self.manual_df['CNNRightLeft'].astype(str) + "|" +
            self.manual_df['Limits'].astype(str) + "|" +
            self.manual_df['BlockSide'].astype(str)
        )
        
        # Create day pattern for manual (convert column names to match)
        manual_day_pattern = []
        day_mapping = {'Sun': 'Sunday', 'Mon': 'Monday', 'Tues': 'Tuesday', 'Wed': 'Wednesday', 
                      'Thu': 'Thursday', 'Fri': 'Friday', 'Sat': 'Saturday'}
        
        for _, row in self.manual_df.iterrows():
            active_days = []
            for manual_day, standard_day in day_mapping.items():
                if row[manual_day] == 1:
                    active_days.append(standard_day)
            manual_day_pattern.append('/'.join(sorted(active_days)))
            
        self.manual_df['day_pattern'] = manual_day_pattern
        
        # Create comparison keys for automated dataset
        self.automated_df['comparison_key'] = (
            self.automated_df['CNN'].astype(str) + "|" +
            self.automated_df['Corridor'].astype(str) + "|" +
            self.automated_df['CNNRightLeft'].astype(str) + "|" +
            self.automated_df['Limits'].astype(str) + "|" +
            self.automated_df['BlockSide'].astype(str)
        )
        
        # Create day pattern for automated
        auto_day_pattern = []
        for _, row in self.automated_df.iterrows():
            active_days = []
            for day in auto_day_cols:
                if row[day] == 1:
                    active_days.append(day)
            auto_day_pattern.append('/'.join(sorted(active_days)))
            
        self.automated_df['day_pattern'] = auto_day_pattern
        
        print(f"✅ Created comparison keys for both datasets")
        
    def find_key_differences(self):
        """Identify records that exist in one dataset but not the other"""
        print("\n🔍 KEY DIFFERENCES ANALYSIS")
        print("=" * 50)
        
        manual_keys = set(self.manual_df['comparison_key'])
        automated_keys = set(self.automated_df['comparison_key'])
        
        common_keys = manual_keys & automated_keys
        manual_only_keys = manual_keys - automated_keys
        automated_only_keys = automated_keys - manual_keys
        
        print(f"✅ Common location keys: {len(common_keys):,}")
        print(f"🔸 Manual only keys: {len(manual_only_keys):,}")
        print(f"🔹 Automated only keys: {len(automated_only_keys):,}")
        
        # Show examples of differences
        if manual_only_keys:
            print(f"\n📋 SAMPLE MANUAL-ONLY RECORDS:")
            manual_only_sample = self.manual_df[self.manual_df['comparison_key'].isin(list(manual_only_keys)[:5])]
            for _, row in manual_only_sample.iterrows():
                print(f"   {row['Corridor']} | {row['Limits']} | {row['CNNRightLeft']} | {row['day_pattern']}")
                
        if automated_only_keys:
            print(f"\n📋 SAMPLE AUTOMATED-ONLY RECORDS:")
            auto_only_sample = self.automated_df[self.automated_df['comparison_key'].isin(list(automated_only_keys)[:5])]
            for _, row in auto_only_sample.iterrows():
                print(f"   {row['Corridor']} | {row['Limits']} | {row['CNNRightLeft']} | {row['day_pattern']} | RecordCount: {row.get('RecordCount', 'N/A')}")
                
        return common_keys, manual_only_keys, automated_only_keys
        
    def analyze_aggregation_differences(self, common_keys: Set[str]):
        """Analyze differences in how records were aggregated"""
        print("\n🔄 AGGREGATION DIFFERENCES ANALYSIS")
        print("=" * 50)
        
        # For common keys, compare how many records exist in each dataset
        manual_key_counts = self.manual_df['comparison_key'].value_counts()
        automated_key_counts = self.automated_df['comparison_key'].value_counts()
        
        aggregation_diffs = []
        
        for key in common_keys:
            manual_count = manual_key_counts.get(key, 0)
            automated_count = automated_key_counts.get(key, 0)
            
            if manual_count != automated_count:
                aggregation_diffs.append({
                    'key': key,
                    'manual_records': manual_count,
                    'automated_records': automated_count,
                    'difference': automated_count - manual_count
                })
        
        if aggregation_diffs:
            print(f"Found {len(aggregation_diffs)} keys with different aggregation")
            
            # Show top differences
            aggregation_diffs.sort(key=lambda x: abs(x['difference']), reverse=True)
            print(f"\n📋 TOP AGGREGATION DIFFERENCES:")
            for diff in aggregation_diffs[:10]:
                key_parts = diff['key'].split('|')
                print(f"   {key_parts[1]} | {key_parts[3]} | Manual: {diff['manual_records']} | Automated: {diff['automated_records']}")
        else:
            print("✅ No aggregation differences found for common keys")
            
        return aggregation_diffs
        
    def analyze_day_pattern_differences(self, common_keys: Set[str]):
        """Compare day patterns for common keys"""
        print("\n📅 DAY PATTERN DIFFERENCES ANALYSIS")
        print("=" * 50)
        
        pattern_diffs = []
        
        for key in list(common_keys)[:100]:  # Sample first 100 for performance
            manual_patterns = self.manual_df[self.manual_df['comparison_key'] == key]['day_pattern'].unique()
            automated_patterns = self.automated_df[self.automated_df['comparison_key'] == key]['day_pattern'].unique()
            
            if len(manual_patterns) > 0 and len(automated_patterns) > 0:
                manual_pattern = manual_patterns[0]
                automated_pattern = automated_patterns[0]
                
                if manual_pattern != automated_pattern:
                    pattern_diffs.append({
                        'key': key,
                        'manual_pattern': manual_pattern,
                        'automated_pattern': automated_pattern
                    })
        
        if pattern_diffs:
            print(f"Found {len(pattern_diffs)} day pattern differences (from sample of 100)")
            print(f"\n📋 SAMPLE DAY PATTERN DIFFERENCES:")
            for diff in pattern_diffs[:5]:
                key_parts = diff['key'].split('|')
                print(f"   {key_parts[1]} | {key_parts[3]}")
                print(f"     Manual: {diff['manual_pattern']}")
                print(f"     Automated: {diff['automated_pattern']}")
        else:
            print("✅ No day pattern differences found in sample")
            
    def generate_discrepancy_summary(self):
        """Generate final summary of discrepancies"""
        print("\n📊 DISCREPANCY SUMMARY")
        print("=" * 50)
        
        print(f"📈 Record Count Difference: {len(self.automated_df) - len(self.manual_df):,} records")
        print(f"   - Manual cleaning: {len(self.manual_df):,} records")  
        print(f"   - Automated cleaning: {len(self.automated_df):,} records")
        
        # Check for potential causes
        automated_combined = len(self.automated_df[self.automated_df.get('RecordCount', 1) > 1]) if 'RecordCount' in self.automated_df.columns else 0
        
        print(f"\n🔍 Potential Causes:")
        if automated_combined > 0:
            print(f"   - Automated script combined {automated_combined} record groups")
            print(f"   - Manual process may have used different aggregation logic")
        
        print(f"\n💡 Recommendations:")
        print(f"   1. Check if manual process missed some combinations")
        print(f"   2. Verify week pattern handling (1st&3rd + 2nd&4th = every week)")
        print(f"   3. Compare holiday record handling")
        print(f"   4. Check for edge cases in day parsing (Tues vs Tuesday)")
        
    def run_complete_analysis(self):
        """Run the complete comparison analysis"""
        print("🔍 CLEANING METHOD COMPARISON ANALYSIS")
        print("=" * 60)
        
        # Load datasets
        self.load_datasets()
        
        # Analyze structures
        common_cols = self.analyze_column_structures()
        
        # Normalize for comparison
        self.normalize_for_comparison(common_cols)
        
        # Find key differences
        common_keys, manual_only, automated_only = self.find_key_differences()
        
        # Analyze aggregation differences
        self.analyze_aggregation_differences(common_keys)
        
        # Analyze day pattern differences
        self.analyze_day_pattern_differences(common_keys)
        
        # Generate summary
        self.generate_discrepancy_summary()
        
        print(f"\n🎉 Analysis complete!")

def main():
    analyzer = CleaningComparisonAnalyzer()
    analyzer.run_complete_analysis()

if __name__ == "__main__":
    main()