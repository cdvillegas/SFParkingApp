import pandas as pd
import requests
from datetime import datetime

# Simple function to get recent street cleaning citations
def get_sfmta_data(limit=5000):
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
        
        # Add hour with AM/PM
        df['hour_ampm'] = df['citation_issued_datetime'].dt.strftime('%I:%M %p')
        
        # Split citation_location into street number and street name
        df['street_number'] = pd.to_numeric(df['citation_location'].str.extract(r'^(\d+)', expand=False), errors='coerce')
        df['street_name'] = df['citation_location'].str.replace(r'^\d+\s*', '', regex=True)
    
    return df

# Usage - let's try 1 million citations for maximum coverage
street_sweeping_tickets = get_sfmta_data(limit=1000000)  # Increased to 1,000,000
print(f"Got {len(street_sweeping_tickets)} street cleaning citations")

# Find citations between 1600-1700 McAllister St
target_street = "MCALLISTER ST"
target_block_start = 1600
target_block_end = 1700

# Filter for McAllister St citations in the 1600-1700 range
mcallister_citations = street_sweeping_tickets[
    (street_sweeping_tickets['street_name'].str.upper() == target_street) &
    (street_sweeping_tickets['street_number'] >= target_block_start) &
    (street_sweeping_tickets['street_number'] <= target_block_end)
]

print(f"\nFound {len(mcallister_citations)} citations between 1600-1700 McAllister St:")
if len(mcallister_citations) > 0:
    # Show all citations without truncation
    pd.set_option('display.max_rows', None)
    pd.set_option('display.width', None)
    pd.set_option('display.max_columns', None)
    print(mcallister_citations[['citation_location', 'day_of_week', 'hour_ampm', 'citation_issued_datetime']].sort_values('citation_issued_datetime', ascending=False))
else:
    # Let's check what street names we have that contain "MCALLISTER"
    mcallister_all = street_sweeping_tickets[street_sweeping_tickets['street_name'].str.contains('MCALLISTER', case=False, na=False)]
    print(f"All McAllister citations found: {len(mcallister_all)}")
    if len(mcallister_all) > 0:
        print("Sample McAllister citations:")
        print(mcallister_all[['citation_location', 'street_name']].head(10))