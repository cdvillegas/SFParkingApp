from flask import Flask, request, jsonify
import pandas as pd
import requests
from datetime import datetime, timedelta
import numpy as np
import re
from functools import lru_cache
import threading
import time

app = Flask(__name__)

# Global variables for cached data
citations_cache = None
cache_timestamp = None
CACHE_DURATION = 3600  # 1 hour in seconds

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

def load_citations_cache():
    """Load citations data into cache if not already loaded or if cache is expired"""
    global citations_cache, cache_timestamp
    
    current_time = time.time()
    
    # Check if cache needs refresh
    if (citations_cache is None or 
        cache_timestamp is None or 
        (current_time - cache_timestamp) > CACHE_DURATION):
        
        print("Loading/refreshing citations cache...")
        citations_cache = get_all_citations()
        cache_timestamp = current_time
        print("Cache loaded successfully")
    
    return citations_cache

def parse_address(address_input):
    """Parse an address like '1530 Broderick St' into number and street name"""
    try:
        # Clean up the input
        address_clean = address_input.strip().upper()
        
        # Extract street number
        number_match = re.match(r'^(\d+)', address_clean)
        if not number_match:
            return None, None
        
        street_number = int(number_match.group(1))
        
        # Extract street name (everything after the number)
        street_name = re.sub(r'^\d+\s*', '', address_clean).strip()
        
        return street_number, street_name
    except:
        return None, None

def get_block_range(street_number, block_size=100):
    """Get the block range for a given street number (e.g., 1530 -> 1500-1599)"""
    block_start = (street_number // block_size) * block_size
    block_end = block_start + block_size - 1
    return block_start, block_end

def find_street_sweeping_times(address, citations_df, days_filter=None, block_size=100):
    """Find estimated street sweeping times for a given address"""
    
    # Parse the address
    street_number, street_name = parse_address(address)
    if not street_number or not street_name:
        return {"error": "Could not parse address. Please use format like '1530 Broderick St'"}
    
    # Get block range
    block_start, block_end = get_block_range(street_number, block_size)
    
    # Create variations of street name for fuzzy matching
    possible_street_matches = [
        street_name,
        street_name.replace(' ST', ''),
        street_name.replace(' AVE', ''),
        street_name.replace(' BLVD', ''),
        street_name.replace(' STREET', ' ST'),
        street_name.replace(' AVENUE', ' AVE'),
        street_name.replace(' BOULEVARD', ' BLVD'),
        street_name + ' ST' if not any(suffix in street_name for suffix in [' ST', ' AVE', ' BLVD']) else street_name,
    ]
    
    # Remove duplicates while preserving order
    seen = set()
    possible_street_matches = [x for x in possible_street_matches if not (x in seen or seen.add(x))]
    
    # Filter citations for this block
    street_mask = citations_df['street_name'].isin(possible_street_matches)
    
    block_citations = citations_df[
        street_mask &
        (citations_df['street_number'] >= block_start) &
        (citations_df['street_number'] <= block_end)
    ].copy()
    
    if len(block_citations) == 0:
        return {
            "address": address,
            "parsed_address": f"{street_number} {street_name}",
            "block_range": f"{block_start}-{block_end}",
            "message": "No street sweeping citations found for this block",
            "tried_street_names": possible_street_matches
        }
    
    # Group by day of week and calculate weighted averages
    results_by_day = {}
    
    # Filter by specific days if requested
    if days_filter:
        day_names = [day.title() for day in days_filter]
        block_citations = block_citations[block_citations['day_of_week'].isin(day_names)]
    
    for day in block_citations['day_of_week'].unique():
        day_citations = block_citations[block_citations['day_of_week'] == day].copy()
        
        if len(day_citations) == 0:
            continue
        
        # Calculate weighted average time
        total_weight = day_citations['weight'].sum()
        if total_weight == 0:
            continue
        
        # Convert times to minutes since midnight for averaging
        day_citations['minutes'] = day_citations['hour_time'].apply(
            lambda t: t.hour * 60 + t.minute
        )
        
        weighted_avg_minutes = (day_citations['minutes'] * day_citations['weight']).sum() / total_weight
        
        # Convert back to time
        avg_hour = int(weighted_avg_minutes // 60)
        avg_minute = int(weighted_avg_minutes % 60)
        estimated_time = f"{avg_hour:02d}:{avg_minute:02d}"
        
        # Get time range (earliest and latest citations)
        earliest_time = day_citations['hour_time'].min()
        latest_time = day_citations['hour_time'].max()
        
        # Get recent citation examples
        recent_citations = day_citations.nlargest(5, 'citation_issued_datetime')
        examples = []
        for _, citation in recent_citations.iterrows():
            examples.append({
                "location": citation['citation_location'],
                "date": citation['citation_issued_datetime'].strftime('%Y-%m-%d'),
                "time": citation['citation_issued_datetime'].strftime('%H:%M')
            })
        
        results_by_day[day] = {
            "estimated_time": estimated_time,
            "time_range": f"{earliest_time.strftime('%H:%M')} - {latest_time.strftime('%H:%M')}",
            "citation_count": len(day_citations),
            "total_weight": round(total_weight, 2),
            "confidence": "high" if total_weight > 50 else "medium" if total_weight > 10 else "low",
            "recent_examples": examples
        }
    
    return {
        "address": address,
        "parsed_address": f"{street_number} {street_name}",
        "block_range": f"{block_start}-{block_end}",
        "street_names_matched": list(set(block_citations['street_name'].unique())),
        "total_citations": len(block_citations),
        "date_range": f"{block_citations['citation_issued_datetime'].min().strftime('%Y-%m-%d')} to {block_citations['citation_issued_datetime'].max().strftime('%Y-%m-%d')}",
        "sweeping_schedule": results_by_day
    }

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({"status": "healthy", "timestamp": datetime.now().isoformat()})

@app.route('/sweeping-times', methods=['GET'])
def get_sweeping_times():
    """
    Get estimated street sweeping times for an address
    
    Query parameters:
    - address (required): Address like "1530 Broderick St"
    - days (optional): Comma-separated list of days to filter (e.g., "monday,tuesday")
    - block_size (optional): Block size for range calculation (default: 100)
    """
    
    # Get query parameters
    address = request.args.get('address')
    days_filter = request.args.get('days')
    block_size = int(request.args.get('block_size', 100))
    
    if not address:
        return jsonify({"error": "Address parameter is required"}), 400
    
    # Parse days filter
    if days_filter:
        days_filter = [day.strip().lower() for day in days_filter.split(',')]
    
    try:
        # Load citations data
        citations_df = load_citations_cache()
        
        # Find sweeping times
        result = find_street_sweeping_times(address, citations_df, days_filter, block_size)
        
        return jsonify(result)
        
    except Exception as e:
        return jsonify({"error": f"Internal server error: {str(e)}"}), 500

@app.route('/cache/refresh', methods=['POST'])
def refresh_cache():
    """Manually refresh the citations cache"""
    global citations_cache, cache_timestamp
    
    try:
        print("Manually refreshing cache...")
        citations_cache = get_all_citations()
        cache_timestamp = time.time()
        
        return jsonify({
            "message": "Cache refreshed successfully",
            "citation_count": len(citations_cache),
            "timestamp": datetime.now().isoformat()
        })
    except Exception as e:
        return jsonify({"error": f"Failed to refresh cache: {str(e)}"}), 500

@app.route('/cache/status', methods=['GET'])
def cache_status():
    """Get cache status information"""
    global citations_cache, cache_timestamp
    
    if citations_cache is None:
        return jsonify({
            "status": "not_loaded",
            "citation_count": 0,
            "last_updated": None
        })
    
    return jsonify({
        "status": "loaded",
        "citation_count": len(citations_cache),
        "last_updated": datetime.fromtimestamp(cache_timestamp).isoformat() if cache_timestamp else None,
        "cache_age_seconds": time.time() - cache_timestamp if cache_timestamp else None
    })

@app.route('/', methods=['GET'])
def home():
    """API documentation"""
    return jsonify({
        "name": "Street Sweeping Prediction API",
        "version": "1.0.0",
        "description": "Predict street sweeping times based on historical citation data",
        "endpoints": {
            "/sweeping-times": {
                "method": "GET",
                "description": "Get estimated street sweeping times for an address",
                "parameters": {
                    "address": "Required. Address like '1530 Broderick St'",
                    "days": "Optional. Comma-separated days to filter (e.g., 'monday,tuesday')",
                    "block_size": "Optional. Block size for range calculation (default: 100)"
                },
                "example": "/sweeping-times?address=1530 Broderick St&days=tuesday,thursday"
            },
            "/cache/refresh": {
                "method": "POST",
                "description": "Manually refresh the citations cache"
            },
            "/cache/status": {
                "method": "GET", 
                "description": "Get cache status information"
            },
            "/health": {
                "method": "GET",
                "description": "Health check endpoint"
            }
        }
    })

if __name__ == '__main__':
    # Pre-load cache on startup
    print("Starting Street Sweeping Prediction API...")
    load_citations_cache()
    
    # Run the Flask app
    app.run(host='0.0.0.0', port=5000, debug=True)