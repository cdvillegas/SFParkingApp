#!/usr/bin/env python3
"""
Street Sweeping Schedule Data Quality Analysis
Identifies issues and suggests consolidations
"""

import pandas as pd
import numpy as np
from collections import defaultdict

def analyze_schedule_quality():
    """Analyze the schedule dataset for data quality issues"""
    
    # Read the dataset
    df = pd.read_csv('/Users/zshor/Desktop/SFParkingApp/SF Parking App/Street_Sweeping_Schedule_20250709.csv')
    
    print(f"📊 Dataset Overview:")
    print(f"Total records: {len(df):,}")
    print(f"Unique BlockSweepIDs: {df['BlockSweepID'].nunique():,}")
    print(f"Unique street corridors: {df['Corridor'].nunique():,}")
    
    # Issue 1: Same block, same time, different days (should be combined)
    print(f"\n🔍 ISSUE 1: Same Block, Same Time, Different Days")
    same_block_different_days = find_same_block_different_days(df)
    
    # Issue 2: Partial week patterns that could be combined
    print(f"\n🔍 ISSUE 2: Partial Week Patterns (1st&3rd + 2nd&4th)")
    partial_week_patterns = find_combineable_week_patterns(df)
    
    # Issue 3: FullName vs WeekDay inconsistencies  
    print(f"\n🔍 ISSUE 3: FullName vs WeekDay Inconsistencies")
    fullname_weekday_issues = find_fullname_weekday_mismatches(df)
    
    # Issue 4: Unusual time ranges
    print(f"\n🔍 ISSUE 4: Unusual Time Ranges")
    unusual_times = find_unusual_time_ranges(df)
    
    # Issue 5: Missing or malformed data
    print(f"\n🔍 ISSUE 5: Missing or Malformed Data")
    missing_data_issues = find_missing_data_issues(df)
    
    return {
        'same_block_different_days': same_block_different_days,
        'partial_week_patterns': partial_week_patterns,
        'fullname_weekday_issues': fullname_weekday_issues,
        'unusual_times': unusual_times,
        'missing_data_issues': missing_data_issues
    }

def find_same_block_different_days(df):
    """Find blocks with same location, side, time but different days"""
    
    # Group by street location and time characteristics
    grouped = df.groupby(['Corridor', 'Limits', 'BlockSide', 'FromHour', 'ToHour'])
    
    same_block_issues = []
    
    for (corridor, limits, side, from_hour, to_hour), group in grouped:
        if len(group) > 1:
            # Check if these could be combined
            days = group['WeekDay'].unique()
            if len(days) > 1:
                same_block_issues.append({
                    'location': f"{corridor}, {limits}, {side}",
                    'time': f"{from_hour}-{to_hour}",
                    'current_days': list(days),
                    'records': len(group),
                    'block_sweep_ids': list(group['BlockSweepID'].unique())
                })
    
    print(f"Found {len(same_block_issues)} blocks with multiple day schedules")
    
    # Show examples
    for issue in same_block_issues[:5]:
        print(f"  📍 {issue['location']}")
        print(f"     Time: {issue['time']}, Days: {issue['current_days']}")
        print(f"     Records: {issue['records']}, IDs: {issue['block_sweep_ids']}")
    
    return same_block_issues

def find_combineable_week_patterns(df):
    """Find schedules with partial week patterns that could be combined"""
    
    # Group by street location, day, and time
    grouped = df.groupby(['Corridor', 'Limits', 'BlockSide', 'WeekDay', 'FromHour', 'ToHour'])
    
    combineable_patterns = []
    
    for (corridor, limits, side, weekday, from_hour, to_hour), group in grouped:
        if len(group) > 1:
            # Check week patterns
            patterns = []
            for _, row in group.iterrows():
                pattern = (row['Week1'], row['Week2'], row['Week3'], row['Week4'], row['Week5'])
                patterns.append(pattern)
            
            # Check if patterns are complementary (1st&3rd + 2nd&4th = every week)
            if len(patterns) == 2:
                p1, p2 = patterns
                # Check if they sum to (1,1,1,1,1) or (1,1,1,1,0)
                combined = tuple(max(a, b) for a, b in zip(p1, p2))
                if combined in [(1,1,1,1,1), (1,1,1,1,0)]:
                    combineable_patterns.append({
                        'location': f"{corridor}, {limits}, {side}",
                        'day_time': f"{weekday} {from_hour}-{to_hour}",
                        'pattern1': p1,
                        'pattern2': p2,
                        'combined': combined,
                        'block_sweep_ids': list(group['BlockSweepID'])
                    })
    
    print(f"Found {len(combineable_patterns)} combineable week patterns")
    
    # Show examples
    for pattern in combineable_patterns[:5]:
        print(f"  📍 {pattern['location']}")
        print(f"     {pattern['day_time']}")
        print(f"     Pattern 1: {pattern['pattern1']}")
        print(f"     Pattern 2: {pattern['pattern2']}")
        print(f"     Combined: {pattern['combined']}")
    
    return combineable_patterns

def find_fullname_weekday_mismatches(df):
    """Find inconsistencies between FullName description and WeekDay/Week pattern"""
    
    mismatches = []
    
    for _, row in df.iterrows():
        fullname = str(row['FullName']).lower()
        weekday = row['WeekDay']
        pattern = (row['Week1'], row['Week2'], row['Week3'], row['Week4'], row['Week5'])
        
        # Check for pattern mismatches
        is_every_week = pattern == (1,1,1,1,1) or pattern == (1,1,1,1,0)
        has_partial_description = any(x in fullname for x in ['1st', '2nd', '3rd', '4th', '5th', '&'])
        
        if is_every_week and has_partial_description:
            mismatches.append({
                'block_sweep_id': row['BlockSweepID'],
                'location': f"{row['Corridor']}, {row['Limits']}, {row['BlockSide']}",
                'fullname': row['FullName'],
                'weekday': weekday,
                'pattern': pattern,
                'issue': 'FullName suggests partial but pattern is every week'
            })
        elif not is_every_week and not has_partial_description:
            mismatches.append({
                'block_sweep_id': row['BlockSweepID'],
                'location': f"{row['Corridor']}, {row['Limits']}, {row['BlockSide']}",
                'fullname': row['FullName'],
                'weekday': weekday,
                'pattern': pattern,
                'issue': 'FullName suggests every week but pattern is partial'
            })
    
    print(f"Found {len(mismatches)} FullName/WeekDay mismatches")
    
    # Show examples
    for mismatch in mismatches[:5]:
        print(f"  📍 {mismatch['location']}")
        print(f"     FullName: {mismatch['fullname']}")
        print(f"     Pattern: {mismatch['pattern']}")
        print(f"     Issue: {mismatch['issue']}")
    
    return mismatches

def find_unusual_time_ranges(df):
    """Find unusual or suspicious time ranges"""
    
    unusual_times = []
    
    # Check for unusual patterns
    for _, row in df.iterrows():
        from_hour = row['FromHour']
        to_hour = row['ToHour']
        
        # Overnight sweeping (crosses midnight)
        if from_hour > to_hour:
            unusual_times.append({
                'block_sweep_id': row['BlockSweepID'],
                'location': f"{row['Corridor']}, {row['Limits']}, {row['BlockSide']}",
                'time_range': f"{from_hour}-{to_hour}",
                'issue': 'Crosses midnight'
            })
        
        # Very long sweeping periods (>6 hours)
        duration = to_hour - from_hour if to_hour > from_hour else (24 - from_hour) + to_hour
        if duration > 6:
            unusual_times.append({
                'block_sweep_id': row['BlockSweepID'],
                'location': f"{row['Corridor']}, {row['Limits']}, {row['BlockSide']}",
                'time_range': f"{from_hour}-{to_hour}",
                'issue': f'Very long duration: {duration} hours'
            })
    
    print(f"Found {len(unusual_times)} unusual time ranges")
    
    # Show examples
    for time_issue in unusual_times[:5]:
        print(f"  📍 {time_issue['location']}")
        print(f"     Time: {time_issue['time_range']}")
        print(f"     Issue: {time_issue['issue']}")
    
    return unusual_times

def find_missing_data_issues(df):
    """Find missing or malformed data"""
    
    issues = []
    
    # Check for missing coordinates
    missing_coordinates = df[df['Line'].isna() | (df['Line'] == '')]
    if len(missing_coordinates) > 0:
        issues.append({
            'type': 'missing_coordinates',
            'count': len(missing_coordinates),
            'records': list(missing_coordinates['BlockSweepID'])[:10]
        })
    
    # Check for missing time data
    missing_time = df[df['FromHour'].isna() | df['ToHour'].isna()]
    if len(missing_time) > 0:
        issues.append({
            'type': 'missing_time',
            'count': len(missing_time),
            'records': list(missing_time['BlockSweepID'])[:10]
        })
    
    # Check for missing street info
    missing_street = df[df['Corridor'].isna() | (df['Corridor'] == '')]
    if len(missing_street) > 0:
        issues.append({
            'type': 'missing_street',
            'count': len(missing_street),
            'records': list(missing_street['BlockSweepID'])[:10]
        })
    
    print(f"Found {len(issues)} types of missing data issues")
    for issue in issues:
        print(f"  📍 {issue['type']}: {issue['count']} records")
        print(f"     Examples: {issue['records']}")
    
    return issues

if __name__ == "__main__":
    issues = analyze_schedule_quality()
    
    print(f"\n📋 SUMMARY OF DATA QUALITY ISSUES:")
    print(f"1. Same block, different days: {len(issues['same_block_different_days'])} cases")
    print(f"2. Combineable week patterns: {len(issues['partial_week_patterns'])} cases") 
    print(f"3. FullName/WeekDay mismatches: {len(issues['fullname_weekday_issues'])} cases")
    print(f"4. Unusual time ranges: {len(issues['unusual_times'])} cases")
    print(f"5. Missing data issues: {len(issues['missing_data_issues'])} types")