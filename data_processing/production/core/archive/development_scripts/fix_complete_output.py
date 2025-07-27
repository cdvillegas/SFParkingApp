#!/usr/bin/env python3
"""
Generate correct final output preserving week information and schedule structure
"""

import pandas as pd
from datetime import datetime
import argparse

def generate_correct_output(matches_file, schedule_file, citation_file, output_prefix):
    print("Loading data...")
    
    # Load data
    matches_df = pd.read_csv(matches_file)
    schedule_df = pd.read_csv(schedule_file)
    citations_df = pd.read_csv(citation_file)
    
    print(f"Loaded {len(matches_df):,} matches, {len(schedule_df):,} schedules")
    
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
    
    print("Adding citation times to matches...")
    
    # Add citation times to matches
    citation_times = []
    for _, row in matches_df.iterrows():
        citation_id = row['citation_id']
        citation_time = citation_lookup.get(citation_id, 10.0)
        citation_times.append(citation_time)
    
    matches_df['citation_time'] = citation_times
    
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
    
    print("Creating final schedule estimates with complete information...")
    
    # Create complete schedule output - one row per schedule_id with all original fields
    final_schedules = []
    processed_schedule_ids = set()
    
    for _, row in valid_matches_df.iterrows():
        schedule_id = row['schedule_id']
        
        # Only process each schedule once
        if schedule_id in processed_schedule_ids:
            continue
        processed_schedule_ids.add(schedule_id)
        
        # Get all matches for this schedule
        schedule_matches = valid_matches_df[valid_matches_df['schedule_id'] == schedule_id]
        
        if len(schedule_matches) >= 3:  # Minimum 3 citations for reliable estimate
            # Get original schedule data
            schedule_info = schedule_df[schedule_df['CleanBlockSweepID'] == schedule_id].iloc[0]
            
            # Calculate citation statistics
            citation_stats = {
                'citation_count': len(schedule_matches),
                'avg_citation_time': schedule_matches['citation_time'].mean(),
                'min_citation_time': schedule_matches['citation_time'].min(),
                'max_citation_time': schedule_matches['citation_time'].max()
            }
            
            # Create complete schedule record
            final_schedule = {
                'schedule_id': schedule_id,
                'cnn': schedule_info['CNN'],
                'corridor': schedule_info['Corridor'],
                'limits': schedule_info['Limits'],
                'cnn_right_left': schedule_info['CNNRightLeft'],
                'block_side': schedule_info['BlockSide'],
                'full_name': schedule_info['FullName'],
                'week_day': schedule_info['WeekDay'],
                'scheduled_from_hour': schedule_info['FromHour'],
                'scheduled_to_hour': schedule_info['ToHour'],
                'monday': schedule_info['Monday'],
                'tuesday': schedule_info['Tuesday'],
                'wednesday': schedule_info['Wednesday'],
                'thursday': schedule_info['Thursday'],
                'friday': schedule_info['Friday'],
                'saturday': schedule_info['Saturday'],
                'sunday': schedule_info['Sunday'],
                'week1': schedule_info['Week1'],
                'week2': schedule_info['Week2'],
                'week3': schedule_info['Week3'],
                'week4': schedule_info['Week4'],
                'week5': schedule_info['Week5'],
                'holidays': schedule_info['Holidays'],
                **citation_stats
            }
            
            final_schedules.append(final_schedule)
    
    final_df = pd.DataFrame(final_schedules)
    
    # Export results
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    matches_file_out = f"{output_prefix}_matches_{timestamp}.csv"
    schedules_file_out = f"{output_prefix}_schedules_{timestamp}.csv"
    
    valid_matches_df.to_csv(matches_file_out, index=False)
    final_df.to_csv(schedules_file_out, index=False)
    
    print(f"✅ Exported corrected final results:")
    print(f"   Matches: {matches_file_out} ({len(valid_matches_df):,} rows)")
    print(f"   Schedules: {schedules_file_out} ({len(final_df)} rows)")
    
    # Show sample
    print(f"\n📊 Sample schedule with complete info:")
    sample = final_df.head(2)
    for _, row in sample.iterrows():
        hours = int(row['avg_citation_time'])
        minutes = int((row['avg_citation_time'] - hours) * 60)
        weeks = [f"Week{i}" for i in range(1,6) if row[f'week{i}'] == 1]
        days = [day for day in ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'] if row[day.lower()] == 1]
        print(f"   {row['corridor']} {row['limits']}")
        print(f"     Side: {row['cnn_right_left']}, {row['block_side']}")
        print(f"     Schedule: {', '.join(days)} {row['scheduled_from_hour']}-{row['scheduled_to_hour']}h, {', '.join(weeks)}")
        print(f"     Citations: {row['citation_count']} avg {hours:02d}:{minutes:02d}")
        print()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Generate correct final output with week information')
    parser.add_argument('--matches-file', required=True, help='Input matches CSV file')
    parser.add_argument('--schedule-file', required=True, help='Schedule CSV file with all fields')
    parser.add_argument('--citation-file', required=True, help='Citation CSV file with datetime data')
    parser.add_argument('--output-prefix', default='final_corrected_results', help='Output file prefix')
    
    args = parser.parse_args()
    
    generate_correct_output(args.matches_file, args.schedule_file, args.citation_file, args.output_prefix)