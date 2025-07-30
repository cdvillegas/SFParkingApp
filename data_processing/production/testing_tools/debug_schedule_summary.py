#!/usr/bin/env python3
"""
Debug script to test the schedule summary logic for specific CNN
"""

def generate_schedule_summary(hour_arrays: dict) -> str:
    """
    Generate a human-readable schedule summary from hour arrays
    """
    # Get active days and their hours
    active_days = []
    day_hour_patterns = {}
    
    day_order = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday']
    
    for day in day_order:
        hours = hour_arrays.get(day, [])
        if hours:
            active_days.append(day)
            # Store the actual hour pattern for comparison
            hour_pattern = ','.join(map(str, sorted(hours)))
            day_hour_patterns[day] = hour_pattern
    
    print(f"CNN 185202 Debug:")
    print(f"  Active days: {active_days}")
    print(f"  Hour patterns: {day_hour_patterns}")
    print(f"  Unique patterns: {set(day_hour_patterns.values())}")
    print(f"  Pattern count: {len(set(day_hour_patterns.values()))}")
    
    # Check if all active days have the same hour pattern
    if len(set(day_hour_patterns.values())) > 1:
        print("  -> Multiple schedules")
        return "Multiple schedules"
    
    print("  -> Single schedule detected")
    # Continue with normal logic...
    return "Single schedule (should not reach here for 185202)"

# Test with CNN 185202 data from CSV
hour_arrays_185202 = {
    'monday': [0, 1],         # 0,1 from CSV
    'tuesday': [],            # empty from CSV  
    'wednesday': [],          # empty from CSV
    'thursday': [],           # empty from CSV
    'friday': [0,1,2,3,4,5],  # 0,1,2,3,4,5 from CSV
    'saturday': [2,3,4,5],    # 2,3,4,5 from CSV
    'sunday': [2,3,4,5]       # 2,3,4,5 from CSV
}

result = generate_schedule_summary(hour_arrays_185202)
print(f"Final result: {result}")