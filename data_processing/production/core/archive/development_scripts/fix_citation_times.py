#!/usr/bin/env python3
"""
Fix citation times in existing results to use minute-level precision
"""

import pandas as pd
from datetime import datetime
import argparse

def fix_citation_times(matches_file, estimates_file, citation_file, output_prefix):
    print("Loading data...")
    
    # Load existing results
    matches_df = pd.read_csv(matches_file)
    estimates_df = pd.read_csv(estimates_file)
    citations_df = pd.read_csv(citation_file)
    
    print(f"Loaded {len(matches_df):,} matches and {len(estimates_df)} estimates")
    
    # Create citation time lookup
    citation_lookup = {}
    for _, row in citations_df.iterrows():
        citation_id = row['citation_id']
        datetime_str = row['datetime']
        
        try:
            dt = datetime.fromisoformat(datetime_str.replace('T', ' ').replace('.000', ''))
            time_decimal = dt.hour + dt.minute / 60.0
            citation_lookup[citation_id] = time_decimal
        except:
            citation_lookup[citation_id] = 10.0
    
    print("Fixing citation times in matches...")
    
    # Fix citation times in matches
    citation_times = []
    for _, row in matches_df.iterrows():
        citation_id = row['citation_id']
        citation_time = citation_lookup.get(citation_id, 10.0)
        citation_times.append(citation_time)
    
    matches_df['citation_time'] = citation_times
    
    print("Recalculating schedule estimates with correct times...")
    
    # Filter matches to only include citations within time windows
    print("Filtering citations to enforce time windows...")
    
    valid_matches = []
    for _, row in matches_df.iterrows():
        citation_time = row['citation_time']
        from_hour = row['from_hour']
        to_hour = row['to_hour']
        
        if from_hour <= citation_time <= to_hour:
            valid_matches.append(row)
    
    valid_matches_df = pd.DataFrame(valid_matches)
    print(f"Kept {len(valid_matches_df):,}/{len(matches_df):,} matches within time windows ({len(valid_matches_df)/len(matches_df)*100:.1f}%)")
    
    # Recalculate estimates with correct times and time window enforcement
    schedule_stats = []
    for schedule_id, group in valid_matches_df.groupby('schedule_id'):
        if len(group) >= 3:  # Minimum 3 citations for reliable estimate
            stats = {
                'schedule_id': schedule_id,
                'cnn': group.iloc[0]['cnn'],
                'corridor': group.iloc[0]['corridor'],
                'limits': group.iloc[0]['limits'],
                'cnn_right_left': group.iloc[0]['cnn_right_left'],
                'block_side': group.iloc[0]['block_side'],
                'weekday': group.iloc[0]['weekday'],
                'scheduled_from_hour': group.iloc[0]['from_hour'],
                'scheduled_to_hour': group.iloc[0]['to_hour'],
                'citation_count': len(group),
                'avg_citation_time': group['citation_time'].mean(),
                'min_citation_time': group['citation_time'].min(),
                'max_citation_time': group['citation_time'].max()
            }
            schedule_stats.append(stats)
    
    corrected_estimates_df = pd.DataFrame(schedule_stats)
    
    # Export corrected results
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    matches_file_out = f"{output_prefix}_matches_{timestamp}.csv"
    estimates_file_out = f"{output_prefix}_estimates_{timestamp}.csv"
    
    matches_df.to_csv(matches_file_out, index=False)
    corrected_estimates_df.to_csv(estimates_file_out, index=False)
    
    print(f"✅ Exported corrected results:")
    print(f"   Matches: {matches_file_out} ({len(matches_df):,} rows)")
    print(f"   Estimates: {estimates_file_out} ({len(corrected_estimates_df)} rows)")
    
    # Show sample of corrected times
    print(f"\n📊 Sample corrected citation times:")
    sample_times = matches_df['citation_time'].head(10).tolist()
    for i, time_val in enumerate(sample_times):
        hours = int(time_val)
        minutes = int((time_val - hours) * 60)
        print(f"   Citation {i+1}: {hours:02d}:{minutes:02d} ({time_val:.2f})")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Fix citation times in existing results')
    parser.add_argument('--matches-file', required=True, help='Input matches CSV file')
    parser.add_argument('--estimates-file', required=True, help='Input estimates CSV file')
    parser.add_argument('--citation-file', required=True, help='Citation CSV file with datetime data')
    parser.add_argument('--output-prefix', default='corrected_hybrid_results', help='Output file prefix')
    
    args = parser.parse_args()
    
    fix_citation_times(args.matches_file, args.estimates_file, args.citation_file, args.output_prefix)