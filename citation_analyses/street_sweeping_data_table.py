import pandas as pd
import requests
from datetime import datetime, timedelta
import numpy as np

def get_all_citations(limit=1000000):
    """Get all street cleaning citations and store as temp table"""
    print("Fetching all citation data...")
    url = "https://data.sfgov.org/resource/ab4h-6ztd.json"
    params = {
        '$limit': limit,
        '$where': "violation_desc = 'STR CLEAN'",
        '$order': 'citation_issued_datetime DESC'
    }
    response = requests.get(url, params=params)
    df = pd.DataFrame(response.json())
    
    if not df.empty:
        # Convert datetime and add day of week
        df['citation_issued_datetime'] = pd.to_datetime(df['citation_issued_datetime'])
        df['day_of_week'] = df['citation_issued_datetime'].dt.strftime('%A')
        df['hour_time'] = df['citation_issued_datetime'].dt.time
        
        # Split citation_location into street number and street name
        df['street_number'] = pd.to_numeric(df['citation_location'].str.extract(r'^(\d+)', expand=False), errors='coerce')
        df['street_name'] = df['citation_location'].str.replace(r'^\d+\s*', '', regex=True).str.upper()
        
        # Add age weighting (more recent = higher weight)
        max_date = df['citation_issued_datetime'].max()
        df['days_ago'] = (max_date - df['citation_issued_datetime']).dt.days
        # Exponential decay: weight = e^(-days_ago/365) so 1 year ago = ~0.37 weight
        df['weight'] = np.exp(-df['days_ago'] / 365)
    
    print(f"Loaded {len(df)} citations")
    return df

def get_street_sweeping_schedule(limit=10):
    """Get street sweeping schedule data"""
    print("Fetching street sweeping schedule...")
    url = "https://data.sfgov.org/resource/yhqp-riqs.json"
    params = {'$limit': limit}
    response = requests.get(url, params=params)
    df = pd.DataFrame(response.json())
    print(f"Loaded {len(df)} schedule entries")
    return df

def parse_time_range(time_str):
    """Parse time range like '8AM-10AM' into start and end times"""
    if not time_str or pd.isna(time_str):
        return None, None
    
    try:
        # Handle formats like "8AM-10AM", "8:30AM-10:30AM", etc.
        time_str = time_str.replace(' ', '').upper()
        start_str, end_str = time_str.split('-')
        
        # Parse start time
        if 'AM' in start_str or 'PM' in start_str:
            start_time = datetime.strptime(start_str, '%I%p' if ':' not in start_str else '%I:%M%p').time()
        else:
            start_time = datetime.strptime(start_str + 'AM', '%I%p').time()
            
        # Parse end time  
        if 'AM' in end_str or 'PM' in end_str:
            end_time = datetime.strptime(end_str, '%I%p' if ':' not in end_str else '%I:%M%p').time()
        else:
            end_time = datetime.strptime(end_str + 'AM', '%I%p').time()
            
        return start_time, end_time
    except:
        return None, None

def calculate_estimated_arrival(schedule_row, citations_df):
    """Calculate estimated sweeper arrival time for a scheduled block"""
    
    # Extract block info - use corridor as street name, not fullname
    street_name = schedule_row.get('corridor', '').upper()
    limits = schedule_row.get('limits', '')
    day_of_week = schedule_row.get('weekday', '').title()
    from_hour = schedule_row.get('fromhour')
    to_hour = schedule_row.get('tohour')
    
    print(f"\nAnalyzing: {street_name} ({limits}) on {day_of_week} from {from_hour} to {to_hour}")
    
    # Parse scheduled time window from hour numbers
    try:
        if from_hour and to_hour:
            from_hour_int = int(from_hour)
            to_hour_int = int(to_hour)
            start_time = datetime.strptime(f"{from_hour_int:02d}:00", "%H:%M").time()
            end_time = datetime.strptime(f"{to_hour_int:02d}:00", "%H:%M").time()
        else:
            print(f"Missing hour data: from={from_hour}, to={to_hour}")
            return None
    except:
        print(f"Could not parse hours: from={from_hour}, to={to_hour}")
        return None
    
    print(f"Scheduled window: {start_time} - {end_time}")
    
    # Parse address range from limits (e.g., "500 TO 599")
    from_addr, to_addr = 0, 9999
    if limits:
        try:
            # Extract numbers from limits string
            import re
            numbers = re.findall(r'\d+', limits)
            if len(numbers) >= 2:
                from_addr = int(numbers[0])
                to_addr = int(numbers[1])
            print(f"Address range: {from_addr} - {to_addr}")
        except:
            print(f"Could not parse limits: {limits}")
    
    # Find matching citations
    
    # Filter citations for this block - use fuzzy matching for street names
    # Try exact match first, then variations
    possible_street_matches = [
        street_name,
        street_name.replace(' ST', ''),  # Remove " ST" suffix
        street_name.replace(' AVE', ''), # Remove " AVE" suffix
        street_name.replace(' BLVD', ''), # Remove " BLVD" suffix
        street_name + ' ST' if not street_name.endswith(' ST') else street_name,
        street_name + ' AVE' if not street_name.endswith(' AVE') else street_name,
    ]
    
    # Find citations matching any of these street name variations
    street_mask = citations_df['street_name'].isin(possible_street_matches)
    
    # Handle day format mismatch - schedule uses 'Thu' but citations use 'Thursday'
    day_mask = citations_df['day_of_week'].str.startswith(day_of_week[:3])
    
    block_citations = citations_df[
        street_mask &
        day_mask &
        (citations_df['street_number'] >= from_addr) &
        (citations_df['street_number'] <= to_addr) &
        (citations_df['hour_time'] >= start_time) &
        (citations_df['hour_time'] <= end_time)
    ]
    
    # Debug: show which street variations we found
    if len(block_citations) > 0:
        found_streets = block_citations['street_name'].unique()
        print(f"Matched street names: {found_streets}")
    else:
        # More detailed debugging for why no matches
        street_citations = citations_df[street_mask]
        print(f"No matches found. Tried: {possible_street_matches}")
        print(f"Found {len(street_citations)} citations for this street name:")
        if len(street_citations) > 0:
            print(f"  - Days found: {street_citations['day_of_week'].unique()}")
            print(f"  - Hours found: {street_citations['hour_time'].min()} to {street_citations['hour_time'].max()}")
            print(f"  - Address range found: {street_citations['street_number'].min()} to {street_citations['street_number'].max()}")
            
            # Check specific filtering steps - debug day matching
            print(f"  - Filtering for day: '{day_of_week}' (schedule format)")
            print(f"  - Available days in citations: {street_citations['day_of_week'].unique()}")
            
            # Try both formats
            day_match_exact = street_citations[street_citations['day_of_week'] == day_of_week]
            day_match_full = street_citations[street_citations['day_of_week'].str.startswith(day_of_week[:3])]
            
            print(f"  - After exact day filter ({day_of_week}): {len(day_match_exact)} citations")
            print(f"  - After partial day filter ({day_of_week[:3]}*): {len(day_match_full)} citations")
            
            day_match = day_match_full if len(day_match_full) > 0 else day_match_exact
            
            if len(day_match) > 0:
                addr_match = day_match[
                    (day_match['street_number'] >= from_addr) & 
                    (day_match['street_number'] <= to_addr)
                ]
                print(f"  - After address filter ({from_addr}-{to_addr}): {len(addr_match)} citations")
                
                if len(addr_match) > 0:
                    time_match = addr_match[
                        (addr_match['hour_time'] >= start_time) & 
                        (addr_match['hour_time'] <= end_time)
                    ]
                    print(f"  - After time filter ({start_time}-{end_time}): {len(time_match)} citations")
                    if len(time_match) > 0:
                        print(f"    Sample times: {time_match['hour_time'].head().tolist()}")
    
    print(f"Found {len(block_citations)} matching citations in time window")
    
    if len(block_citations) == 0:
        return None
    
    # Calculate weighted average time
    total_weight = block_citations['weight'].sum()
    if total_weight == 0:
        return None
        
    # Convert times to minutes since midnight for averaging
    block_citations = block_citations.copy()
    block_citations['minutes'] = block_citations['hour_time'].apply(
        lambda t: t.hour * 60 + t.minute
    )
    
    weighted_avg_minutes = (block_citations['minutes'] * block_citations['weight']).sum() / total_weight
    
    # Convert back to time
    avg_hour = int(weighted_avg_minutes // 60)
    avg_minute = int(weighted_avg_minutes % 60)
    estimated_time = f"{avg_hour:02d}:{avg_minute:02d}"
    
    print(f"Estimated arrival time: {estimated_time}")
    print(f"Based on {len(block_citations)} citations with total weight: {total_weight:.2f}")
    
    return {
        'street_name': street_name,
        'limits': limits,
        'from_address': from_addr,
        'to_address': to_addr,
        'day_of_week': day_of_week,
        'scheduled_start': str(start_time),
        'scheduled_end': str(end_time),
        'estimated_arrival': estimated_time,
        'citation_count': len(block_citations),
        'total_weight': total_weight
    }

# Main execution
if __name__ == "__main__":
    # Load all data
    citations_df = get_all_citations()
    schedule_df = get_street_sweeping_schedule(limit=1000)  # Get many more rows to find McAllister
    
    print("\nSchedule DataFrame columns:")
    print(schedule_df.columns.tolist())
    print("\nSample schedule entries:")
    print(schedule_df[['fullname', 'limits', 'weekday', 'fromhour', 'tohour', 'corridor']].head(10))
    
    # Let's also check what the corridor field contains
    print("\nLooking at corridor field which might contain street names:")
    print(schedule_df[['corridor', 'limits']].head(10))
    
    # Let's look for McAllister St specifically since we know it has citations
    mcallister_schedules = schedule_df[schedule_df['corridor'].str.contains('MCALLISTER', case=False, na=False)]
    print(f"\nFound {len(mcallister_schedules)} McAllister St schedule entries:")
    if len(mcallister_schedules) > 0:
        print(mcallister_schedules[['corridor', 'limits', 'weekday', 'fromhour', 'tohour']].head())
    
    # Filter to entries more likely to have data - reasonable hours and common days
    filtered_df = schedule_df[
        (schedule_df['fromhour'].astype('int', errors='ignore') >= 7) &  # After 7 AM
        (schedule_df['fromhour'].astype('int', errors='ignore') <= 12) &  # Before noon
        (schedule_df['weekday'].isin(['Mon', 'Tues', 'Wed', 'Thu', 'Fri']))  # Weekdays only
    ]
    print(f"\nFiltered to {len(filtered_df)} entries with reasonable hours (7AM-12PM) on weekdays")
    
    # Debug: Let's see what street names we have in citations vs schedule
    citation_streets = set(citations_df['street_name'].dropna().unique())
    schedule_streets = set(schedule_df['corridor'].dropna().unique())
    
    print(f"\nUnique streets in citations: {len(citation_streets)}")
    print(f"Unique streets in schedule: {len(schedule_streets)}")
    
    # Find some overlaps
    overlaps = citation_streets.intersection(schedule_streets)
    print(f"Direct matches: {len(overlaps)}")
    if len(overlaps) > 0:
        print("Sample overlaps:", list(overlaps)[:10])
    
    # Check if we have McAllister in citations
    mcallister_citations = [s for s in citation_streets if 'MCALLISTER' in s]
    print(f"McAllister variations in citations: {mcallister_citations}")
    
    # Check if we have Laguna in citations  
    laguna_citations = [s for s in citation_streets if 'LAGUNA' in s]
    print(f"Laguna variations in citations: {laguna_citations}")
    
    # Initialize results list
    results = []
    
    # Let's specifically test the McAllister St entries we found
    print(f"\n{'='*60}")
    print("TESTING MCALLISTER ST ENTRIES:")
    print(f"{'='*60}")
    
    for idx, row in mcallister_schedules.iterrows():
        result = calculate_estimated_arrival(row, citations_df)
        if result:
            results.append(result)
    
    # Let's analyze 10 entries and show detailed citation data
    print(f"\n{'='*80}")
    print("DETAILED ANALYSIS FOR 10 SCHEDULE ENTRIES:")
    print(f"{'='*80}")
    
    # Take first 10 filtered entries
    for idx, row in filtered_df.head(10).iterrows():
        corridor = row.get('corridor', '')
        limits = row.get('limits', '')
        cnnrightleft = row.get('cnnrightleft', '')
        fullname = row.get('fullname', '')
        fromhour = row.get('fromhour', '')
        tohour = row.get('tohour', '')
        day_of_week = row.get('weekday', '').title()
        
        print(f"\n{'-'*80}")
        print(f"ENTRY {idx + 1}:")
        print(f"(1) Corridor: {corridor}")
        print(f"(2) Limits: {limits}")
        print(f"(3) CNNRightLeft: {cnnrightleft}")
        print(f"(4) FullName: {fullname}")
        print(f"(5) FromHour: {fromhour}")
        print(f"(6) ToHour: {tohour}")
        print(f"(7) Citations within block and time:")
        
        # Get the matching citations for this block
        street_name = corridor.upper()
        from_addr, to_addr = 0, 9999
        if limits:
            try:
                import re
                numbers = re.findall(r'\d+', limits)
                if len(numbers) >= 2:
                    from_addr = int(numbers[0])
                    to_addr = int(numbers[1])
            except:
                pass
        
        try:
            from_hour_int = int(fromhour)
            to_hour_int = int(tohour)
            start_time = datetime.strptime(f"{from_hour_int:02d}:00", "%H:%M").time()
            end_time = datetime.strptime(f"{to_hour_int:02d}:00", "%H:%M").time()
        except:
            print("    Could not parse hours")
            continue
        
        # Get matching citations
        possible_street_matches = [
            street_name,
            street_name.replace(' ST', ''),
            street_name.replace(' AVE', ''),
            street_name.replace(' BLVD', ''),
            street_name + ' ST' if not street_name.endswith(' ST') else street_name,
            street_name + ' AVE' if not street_name.endswith(' AVE') else street_name,
        ]
        
        street_mask = citations_df['street_name'].isin(possible_street_matches)
        day_mask = citations_df['day_of_week'].str.startswith(day_of_week[:3])
        
        block_citations = citations_df[
            street_mask &
            day_mask &
            (citations_df['street_number'] >= from_addr) &
            (citations_df['street_number'] <= to_addr) &
            (citations_df['hour_time'] >= start_time) &
            (citations_df['hour_time'] <= end_time)
        ].copy()
        
        if len(block_citations) > 0:
            # Sort by citation time and show details
            block_citations = block_citations.sort_values('citation_issued_datetime', ascending=False)
            print(f"    Found {len(block_citations)} citations:")
            
            # Show first 20 citations with details
            for i, (_, citation) in enumerate(block_citations.head(20).iterrows()):
                cite_time = citation['citation_issued_datetime'].strftime('%Y-%m-%d %H:%M')
                cite_location = citation['citation_location']
                cite_day = citation['day_of_week']
                print(f"      {i+1:2d}. {cite_location} on {cite_day} at {cite_time}")
            
            if len(block_citations) > 20:
                print(f"      ... and {len(block_citations) - 20} more citations")
        else:
            print("    No citations found in this time window")
        
        # Still calculate result for summary
        result = calculate_estimated_arrival(row, citations_df)
        if result:
            results.append(result)
    
    # Display results
    if results:
        results_df = pd.DataFrame(results)
        print(f"\n{'='*80}")
        print("ESTIMATED ARRIVAL TIMES:")
        print(f"{'='*80}")
        print(results_df.to_string(index=False))
    else:
        print("No results found")