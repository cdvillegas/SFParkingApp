#!/usr/bin/env python3
"""
Add missing fields (CNNRightLeft, BlockSide) to existing results
"""

import pandas as pd
from datetime import datetime
import argparse

def add_missing_fields(matches_file, estimates_file, schedule_file, citation_file, output_prefix):
    print("Loading data...")
    
    # Load all data
    matches_df = pd.read_csv(matches_file)
    estimates_df = pd.read_csv(estimates_file)
    schedule_df = pd.read_csv(schedule_file)
    citations_df = pd.read_csv(citation_file)
    
    print(f"Loaded {len(matches_df):,} matches, {len(estimates_df)} estimates, {len(schedule_df):,} schedules")
    
    # Create schedule lookup for additional fields
    schedule_lookup = schedule_df.set_index('CleanBlockSweepID')[['CNNRightLeft', 'BlockSide']].to_dict('index')
    
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
    
    print("Adding citation times and missing fields to matches...")
    
    # Add citation times and missing fields to matches
    citation_times = []
    cnn_right_left_list = []
    block_side_list = []
    
    for _, row in matches_df.iterrows():
        # Add citation time
        citation_id = row['citation_id']
        citation_time = citation_lookup.get(citation_id, 10.0)
        citation_times.append(citation_time)
        
        # Add schedule fields
        schedule_id = row['schedule_id']
        schedule_info = schedule_lookup.get(schedule_id, {})
        cnn_right_left_list.append(schedule_info.get('CNNRightLeft', ''))
        block_side_list.append(schedule_info.get('BlockSide', ''))
    
    matches_df['citation_time'] = citation_times
    matches_df['cnn_right_left'] = cnn_right_left_list
    matches_df['block_side'] = block_side_list
    
    print("Filtering citations to enforce time windows...")
    
    # Filter matches to only include citations within time windows
    valid_matches = []
    for _, row in matches_df.iterrows():
        citation_time = row['citation_time']
        from_hour = row['from_hour']
        to_hour = row['to_hour']
        
        if from_hour <= citation_time <= to_hour:
            valid_matches.append(row)
    
    valid_matches_df = pd.DataFrame(valid_matches)
    print(f"Kept {len(valid_matches_df):,}/{len(matches_df):,} matches within time windows ({len(valid_matches_df)/len(matches_df)*100:.1f}%)")
    
    print("Recalculating schedule estimates with all fields...")
    
    # Recalculate estimates with all fields
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
    
    final_estimates_df = pd.DataFrame(schedule_stats)
    
    # Export final results
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    matches_file_out = f"{output_prefix}_matches_{timestamp}.csv"
    estimates_file_out = f"{output_prefix}_estimates_{timestamp}.csv"
    
    valid_matches_df.to_csv(matches_file_out, index=False)
    final_estimates_df.to_csv(estimates_file_out, index=False)
    
    print(f"✅ Exported final results with all fields:")
    print(f"   Matches: {matches_file_out} ({len(valid_matches_df):,} rows)")
    print(f"   Estimates: {estimates_file_out} ({len(final_estimates_df)} rows)")
    
    # Show sample of final estimates
    print(f"\n📊 Sample final estimates with all fields:")
    for _, row in final_estimates_df.head(3).iterrows():
        hours = int(row['avg_citation_time'])
        minutes = int((row['avg_citation_time'] - hours) * 60)
        print(f"   {row['corridor']} ({row['cnn_right_left']}, {row['block_side']}): avg {hours:02d}:{minutes:02d}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Add missing fields to existing results')
    parser.add_argument('--matches-file', required=True, help='Input matches CSV file')
    parser.add_argument('--estimates-file', required=True, help='Input estimates CSV file')
    parser.add_argument('--schedule-file', required=True, help='Schedule CSV file with all fields')
    parser.add_argument('--citation-file', required=True, help='Citation CSV file with datetime data')
    parser.add_argument('--output-prefix', default='final_complete_results', help='Output file prefix')
    
    args = parser.parse_args()
    
    add_missing_fields(args.matches_file, args.estimates_file, args.schedule_file, args.citation_file, args.output_prefix)