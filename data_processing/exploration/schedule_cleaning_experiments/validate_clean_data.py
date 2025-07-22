#!/usr/bin/env python3
"""
Validate the cleaned schedule data and demonstrate new structure
"""

import pandas as pd

def validate_cleaned_data():
    """Validate and demonstrate the cleaned dataset structure"""
    
    # Load the cleaned data
    df = pd.read_csv('/Users/zshor/Desktop/SFParkingApp/data_processing/Street_Sweeping_Schedule_Cleaned.csv')
    
    print("🔍 CLEANED SCHEDULE DATA VALIDATION")
    print("=" * 60)
    print(f"📊 Total records: {len(df):,}")
    
    # Validate day-of-week columns
    print(f"\n📅 DAY-OF-WEEK COLUMN VALIDATION:")
    day_columns = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
    
    for day in day_columns:
        count = df[df[day] == 1].shape[0]
        percentage = (count / len(df)) * 100
        print(f"   {day}: {count:,} schedules ({percentage:.1f}%)")
    
    # Show examples of different schedule types
    print(f"\n📋 SCHEDULE TYPE EXAMPLES:")
    
    # Single day schedules
    single_day_mask = df[day_columns].sum(axis=1) == 1
    single_day_count = single_day_mask.sum()
    print(f"   Single day schedules: {single_day_count:,}")
    
    # Multiple day schedules  
    multi_day_mask = df[day_columns].sum(axis=1) > 1
    multi_day_count = multi_day_mask.sum()
    print(f"   Multiple day schedules: {multi_day_count:,}")
    
    # Show some examples
    print(f"\n📖 EXAMPLES:")
    
    # Example 1: Single day
    single_day_example = df[single_day_mask].iloc[0]
    active_days = [day for day in day_columns if single_day_example[day] == 1]
    print(f"   Single Day Example:")
    print(f"     Location: {single_day_example['Corridor']}, {single_day_example['Limits']}")
    print(f"     Days: {active_days}")
    print(f"     Time: {single_day_example['FromHour']}-{single_day_example['ToHour']}")
    
    # Example 2: Multiple days
    multi_day_example = df[multi_day_mask].iloc[0]
    active_days = [day for day in day_columns if multi_day_example[day] == 1]
    print(f"   Multiple Day Example:")
    print(f"     Location: {multi_day_example['Corridor']}, {multi_day_example['Limits']}")
    print(f"     Days: {active_days}")
    print(f"     Time: {multi_day_example['FromHour']}-{multi_day_example['ToHour']}")
    print(f"     Note: {multi_day_example['DataQualityNotes']}")
    
    # Demonstrate easy querying
    print(f"\n🔎 EASY QUERYING EXAMPLES:")
    
    # Tuesday schedules
    tuesday_schedules = df[df['Tuesday'] == 1]
    print(f"   Tuesday schedules: {len(tuesday_schedules):,}")
    
    # Morning schedules (before 8 AM)
    morning_schedules = df[df['FromHour'] < 8]
    print(f"   Morning schedules (before 8 AM): {len(morning_schedules):,}")
    
    # Weekend schedules
    weekend_schedules = df[(df['Saturday'] == 1) | (df['Sunday'] == 1)]
    print(f"   Weekend schedules: {len(weekend_schedules):,}")
    
    # Tuesday morning schedules
    tuesday_morning = df[(df['Tuesday'] == 1) & (df['FromHour'] < 8)]
    print(f"   Tuesday morning schedules: {len(tuesday_morning):,}")
    
    # Validate week pattern consistency
    print(f"\n🔧 WEEK PATTERN VALIDATION:")
    week_columns = ['Week1', 'Week2', 'Week3', 'Week4', 'Week5']
    
    # Every week schedules
    every_week = df[df[week_columns].sum(axis=1) == 5]
    print(f"   Every week (including 5th): {len(every_week):,}")
    
    # Every week except 5th
    except_5th = df[(df[week_columns[:4]].sum(axis=1) == 4) & (df['Week5'] == 0)]
    print(f"   Every week except 5th: {len(except_5th):,}")
    
    # Partial weeks
    partial_weeks = df[(df[week_columns].sum(axis=1) > 0) & (df[week_columns].sum(axis=1) < 4)]
    print(f"   Partial week patterns: {len(partial_weeks):,}")
    
    # Data quality breakdown
    print(f"\n📈 DATA QUALITY BREAKDOWN:")
    
    combined_records = df[df['DataQualityNotes'].str.contains('Combined', na=False)]
    merged_records = df[df['DataQualityNotes'].str.contains('Merged', na=False)]
    missing_coords = df[df['DataQualityNotes'].str.contains('Missing GPS', na=False)]
    clean_records = df[df['DataQualityNotes'] == '']
    
    print(f"   Clean original records: {len(clean_records):,}")
    print(f"   Combined multi-day records: {len(combined_records):,}")
    print(f"   Merged week patterns: {len(merged_records):,}")
    print(f"   Missing coordinates: {len(missing_coords):,}")
    
    print(f"\n✅ Data structure is ready for citation matching!")

def demonstrate_usage():
    """Show how to use the new structure programmatically"""
    
    df = pd.read_csv('/Users/zshor/Desktop/SFParkingApp/data_processing/Street_Sweeping_Schedule_Cleaned.csv')
    
    print(f"\n💻 PROGRAMMATIC USAGE EXAMPLES:")
    print("=" * 60)
    
    # Example 1: Find all Tuesday schedules for a specific street
    print(f"# Find all Tuesday schedules on Market St")
    market_tuesday = df[(df['Corridor'] == 'Market St') & (df['Tuesday'] == 1)]
    print(f"market_tuesday = df[(df['Corridor'] == 'Market St') & (df['Tuesday'] == 1)]")
    print(f"# Result: {len(market_tuesday)} schedules")
    
    # Example 2: Check if a specific time conflicts
    print(f"\n# Check if 7 AM Tuesday has conflicts on Castro St")
    castro_7am_tuesday = df[
        (df['Corridor'] == 'Castro St') & 
        (df['Tuesday'] == 1) & 
        (df['FromHour'] <= 7) & 
        (df['ToHour'] > 7)
    ]
    print(f"conflicts = df[(corridor=='Castro St') & (Tuesday==1) & (FromHour<=7) & (ToHour>7)]")
    print(f"# Result: {len(castro_7am_tuesday)} potential conflicts")
    
    # Example 3: Get all schedules for a specific day of week
    print(f"\n# Get all Friday schedules")
    print(f"friday_schedules = df[df['Friday'] == 1]")
    print(f"# Result: {len(df[df['Friday'] == 1]):,} schedules")
    
    print(f"\n🎯 Much easier than parsing 'Mon/Wed/Thu/Fri' strings!")

if __name__ == "__main__":
    validate_cleaned_data()
    demonstrate_usage()