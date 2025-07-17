#!/usr/bin/env python3
"""
Citation Coordinate Matching - GPS-based approach for street sweeping predictions
Uses geocoding to convert citation addresses to coordinates and spatial matching
to find citations within 50 meters of user location.
"""

import pandas as pd
import requests
from datetime import datetime
import numpy as np
from geopy.geocoders import Nominatim
from geopy.distance import distance
import time
from functools import lru_cache
import json

class CitationCoordinateMatcher:
    def __init__(self):
        self.geolocator = Nominatim(user_agent="sf_parking_app_v1")
        self.citations_cache = None
        self.cache_timestamp = None
        self.CACHE_DURATION = 3600  # 1 hour
        
    def get_all_citations(self, limit=100000):
        """Get all street cleaning citations from SF Open Data"""
        print("Fetching citation data...")
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
            
            # Add age weighting (more recent = higher weight)
            max_date = df['citation_issued_datetime'].max()
            df['days_ago'] = (max_date - df['citation_issued_datetime']).dt.days
            df['weight'] = np.exp(-df['days_ago'] / 365)
            
        print(f"Loaded {len(df)} citations")
        return df
    
    def load_citations_cache(self):
        """Load citations data into cache if not already loaded or expired"""
        current_time = time.time()
        
        if (self.citations_cache is None or 
            self.cache_timestamp is None or 
            (current_time - self.cache_timestamp) > self.CACHE_DURATION):
            
            print("Loading/refreshing citations cache...")
            self.citations_cache = self.get_all_citations()
            self.cache_timestamp = current_time
            print("Cache loaded successfully")
        
        return self.citations_cache
    
    @lru_cache(maxsize=1000)
    def geocode_address(self, address):
        """
        Convert citation address to GPS coordinates with caching
        Returns (lat, lon) tuple or None if geocoding fails
        """
        try:
            # Add San Francisco context to improve accuracy
            full_address = f"{address}, San Francisco, CA"
            location = self.geolocator.geocode(full_address, timeout=10)
            
            if location:
                return (location.latitude, location.longitude)
            else:
                print(f"⚠️ Geocoding failed for: {address}")
                return None
                
        except Exception as e:
            print(f"❌ Geocoding error for {address}: {e}")
            return None
    
    def find_citations_within_radius(self, user_lat, user_lon, radius_meters=50, days_filter=None):
        """
        Find all citations within specified radius of user location
        
        Args:
            user_lat: User's latitude
            user_lon: User's longitude  
            radius_meters: Search radius in meters (default 50 to match iOS app)
            days_filter: List of days to filter (e.g., ['Monday', 'Tuesday'])
        
        Returns:
            List of citation records within radius
        """
        citations_df = self.load_citations_cache()
        
        if citations_df.empty:
            return []
        
        user_point = (user_lat, user_lon)
        nearby_citations = []
        
        print(f"🔍 Searching {len(citations_df)} citations within {radius_meters}m of ({user_lat:.6f}, {user_lon:.6f})")
        
        # Filter by days if specified
        if days_filter:
            citations_df = citations_df[citations_df['day_of_week'].isin(days_filter)]
            print(f"📅 Filtered to {len(citations_df)} citations for days: {days_filter}")
        
        geocoding_success = 0
        within_radius = 0
        
        for idx, citation in citations_df.iterrows():
            # Rate limiting for geocoding API
            if idx % 100 == 0 and idx > 0:
                print(f"Processed {idx}/{len(citations_df)} citations...")
                time.sleep(0.1)  # Small delay to avoid rate limits
            
            citation_coords = self.geocode_address(citation['citation_location'])
            
            if citation_coords:
                geocoding_success += 1
                citation_distance = distance(user_point, citation_coords).meters
                
                if citation_distance <= radius_meters:
                    within_radius += 1
                    citation_data = citation.to_dict()
                    citation_data['coordinates'] = citation_coords
                    citation_data['distance_meters'] = citation_distance
                    nearby_citations.append(citation_data)
        
        print(f"✅ Geocoding success: {geocoding_success}/{len(citations_df)}")
        print(f"📍 Found {within_radius} citations within {radius_meters}m")
        
        # Sort by distance (closest first)
        nearby_citations.sort(key=lambda x: x['distance_meters'])
        
        return nearby_citations
    
    def predict_sweeping_times(self, user_lat, user_lon, radius_meters=50, days_filter=None):
        """
        Predict street sweeping times based on nearby citations
        
        Returns:
            Dictionary with predicted times by day of week
        """
        nearby_citations = self.find_citations_within_radius(
            user_lat, user_lon, radius_meters, days_filter
        )
        
        if not nearby_citations:
            return {
                "location": f"({user_lat:.6f}, {user_lon:.6f})",
                "radius_meters": radius_meters,
                "message": "No citations found within radius",
                "citation_count": 0
            }
        
        # Convert to DataFrame for analysis
        citations_df = pd.DataFrame(nearby_citations)
        
        # Group by day of week and calculate weighted averages
        results_by_day = {}
        
        for day in citations_df['day_of_week'].unique():
            day_citations = citations_df[citations_df['day_of_week'] == day].copy()
            
            if len(day_citations) == 0:
                continue
            
            # Calculate weighted average time (closer citations get higher weight)
            # Combine age weight with distance weight
            day_citations['distance_weight'] = 1 / (1 + day_citations['distance_meters'] / 10)  # Closer = higher weight
            day_citations['combined_weight'] = day_citations['weight'] * day_citations['distance_weight']
            
            total_weight = day_citations['combined_weight'].sum()
            if total_weight == 0:
                continue
            
            # Convert times to minutes since midnight for averaging
            day_citations['minutes'] = day_citations['hour_time'].apply(
                lambda t: t.hour * 60 + t.minute
            )
            
            weighted_avg_minutes = (day_citations['minutes'] * day_citations['combined_weight']).sum() / total_weight
            
            # Convert back to time
            avg_hour = int(weighted_avg_minutes // 60)
            avg_minute = int(weighted_avg_minutes % 60)
            estimated_time = f"{avg_hour:02d}:{avg_minute:02d}"
            
            # Get time range and statistics
            earliest_time = day_citations['hour_time'].min()
            latest_time = day_citations['hour_time'].max()
            avg_distance = day_citations['distance_meters'].mean()
            
            # Get recent citation examples
            recent_citations = day_citations.nlargest(3, 'citation_issued_datetime')
            examples = []
            for _, citation in recent_citations.iterrows():
                examples.append({
                    "location": citation['citation_location'],
                    "coordinates": citation['coordinates'],
                    "date": citation['citation_issued_datetime'].strftime('%Y-%m-%d'),
                    "time": citation['citation_issued_datetime'].strftime('%H:%M'),
                    "distance_meters": round(citation['distance_meters'], 1)
                })
            
            results_by_day[day] = {
                "estimated_time": estimated_time,
                "time_range": f"{earliest_time.strftime('%H:%M')} - {latest_time.strftime('%H:%M')}",
                "citation_count": len(day_citations),
                "total_weight": round(total_weight, 2),
                "avg_distance_meters": round(avg_distance, 1),
                "confidence": "high" if total_weight > 10 else "medium" if total_weight > 3 else "low",
                "recent_examples": examples
            }
        
        return {
            "location": f"({user_lat:.6f}, {user_lon:.6f})",
            "radius_meters": radius_meters,
            "total_citations": len(nearby_citations),
            "days_with_data": len(results_by_day),
            "sweeping_predictions": results_by_day
        }

def test_coordinate_matching():
    """Test the coordinate-based matching approach"""
    matcher = CitationCoordinateMatcher()
    
    # Test locations in SF
    test_locations = [
        {
            "name": "Broderick & McAllister (Panhandle area)",
            "lat": 37.775021,
            "lon": -122.438892,
            "days": ["Tuesday", "Thursday"]  # Common sweeping days
        },
        {
            "name": "Irving & 9th Ave (Inner Sunset)",
            "lat": 37.763626,
            "lon": -122.466689,
            "days": ["Wednesday"]
        },
        {
            "name": "Valencia & 24th St (Mission)",
            "lat": 37.752701,
            "lon": -122.420671,
            "days": ["Monday", "Friday"]
        }
    ]
    
    for location in test_locations:
        print(f"\n{'='*80}")
        print(f"TESTING: {location['name']}")
        print(f"Coordinates: ({location['lat']:.6f}, {location['lon']:.6f})")
        print(f"Filtering for days: {location['days']}")
        print(f"{'='*80}")
        
        result = matcher.predict_sweeping_times(
            location['lat'], 
            location['lon'], 
            radius_meters=50,
            days_filter=location['days']
        )
        
        print(json.dumps(result, indent=2, default=str))

if __name__ == "__main__":
    test_coordinate_matching()