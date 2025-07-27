#!/usr/bin/env python3
"""
Test Production Citation Processing System

Tests the production system with a small sample to validate functionality
before processing the full dataset.
"""

import subprocess
import sys
import pandas as pd
import json
from pathlib import Path
import time

def test_citation_processor():
    """Test the citation processor with a small sample"""
    print("🧪 Testing Citation GPS Processor")
    print("=" * 50)
    
    # Test with 25 citations from last 30 days
    cmd = [
        sys.executable, 'production_citation_processor.py',
        '--days', '30',
        '--limit', '25',
        '--workers', '2',
        '--batch-size', '10',
        '--rate-limit', '0.3',
        '--min-confidence', 'MEDIUM',
        '--output', 'test_citations.csv',
        '--no-resume'  # Start fresh for test
    ]
    
    print(f"Running: {' '.join(cmd)}")
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        
        if result.returncode == 0:
            print("✅ Citation processor completed successfully")
            
            # Check output file
            if Path('test_citations.csv').exists():
                df = pd.read_csv('test_citations.csv')
                print(f"📊 Processed {len(df)} citations")
                
                # Show confidence distribution
                confidence_dist = df['confidence'].value_counts()
                print("🎯 Confidence distribution:")
                for conf, count in confidence_dist.items():
                    print(f"   {conf}: {count}")
                    
                return True
            else:
                print("❌ Output file not created")
                return False
                
        else:
            print(f"❌ Citation processor failed: {result.stderr}")
            return False
            
    except subprocess.TimeoutExpired:
        print("❌ Citation processor timed out")
        return False
    except Exception as e:
        print(f"❌ Error running citation processor: {e}")
        return False

def test_schedule_matcher():
    """Test the citation-schedule matcher"""
    print("\n🧪 Testing Citation-Schedule Matcher")
    print("=" * 50)
    
    # Check if required files exist
    citation_file = 'test_citations.csv'
    schedule_file = 'Street_Sweeping_Schedule_Cleaned_Simple.csv'
    
    if not Path(citation_file).exists():
        print(f"❌ Citation file not found: {citation_file}")
        return False
        
    if not Path(schedule_file).exists():
        print(f"❌ Schedule file not found: {schedule_file}")
        return False
        
    cmd = [
        sys.executable, 'citation_schedule_matcher.py',
        '--citation-file', citation_file,
        '--schedule-file', schedule_file,
        '--max-distance', '100',  # Larger distance for testing
        '--output-prefix', 'test_analysis'
    ]
    
    print(f"Running: {' '.join(cmd)}")
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        
        if result.returncode == 0:
            print("✅ Citation-schedule matcher completed successfully")
            
            # Find output files
            test_files = list(Path('.').glob('test_analysis_*.csv'))
            report_files = list(Path('.').glob('test_analysis_*.json'))
            
            if test_files and report_files:
                print(f"📁 Generated {len(test_files)} data files and {len(report_files)} report files")
                
                # Load and display basic stats
                matches_file = [f for f in test_files if 'matches' in f.name]
                if matches_file:
                    matches_df = pd.read_csv(matches_file[0])
                    print(f"📊 Found {len(matches_df)} citation-schedule matches")
                    
                    # Show time relevance distribution
                    time_relevance = matches_df['time_relevance'].value_counts()
                    print("⏰ Time relevance distribution:")
                    for relevance, count in time_relevance.items():
                        print(f"   {relevance}: {count}")
                
                # Load report
                if report_files:
                    with open(report_files[0]) as f:
                        report = json.load(f)
                    
                    if 'dataset_summary' in report:
                        summary = report['dataset_summary']
                        print(f"🎯 Analysis summary:")
                        print(f"   Total matches: {summary.get('total_matches', 0)}")
                        print(f"   Schedules matched: {summary.get('unique_schedules_matched', 0)}")
                        print(f"   Schedules with estimates: {summary.get('schedules_with_estimates', 0)}")
                        
                return True
            else:
                print("❌ Output files not created")
                return False
                
        else:
            print(f"❌ Citation-schedule matcher failed: {result.stderr}")
            return False
            
    except subprocess.TimeoutExpired:
        print("❌ Citation-schedule matcher timed out")
        return False
    except Exception as e:
        print(f"❌ Error running citation-schedule matcher: {e}")
        return False

def cleanup_test_files():
    """Clean up test files"""
    print("\n🧹 Cleaning up test files...")
    
    test_files = [
        'test_citations.csv',
        'citation_processing_progress.db',
        'citation_processing.log',
        'citation_schedule_matching.log'
    ] + list(Path('.').glob('test_analysis_*')) + list(Path('.').glob('processing_report_*'))
    
    for file_path in test_files:
        try:
            if isinstance(file_path, str):
                file_path = Path(file_path)
            if file_path.exists():
                file_path.unlink()
                print(f"   Removed {file_path}")
        except Exception as e:
            print(f"   Failed to remove {file_path}: {e}")

def main():
    print("🚀 Testing Production Citation Processing System")
    print("=" * 60)
    
    start_time = time.time()
    
    # Test 1: Citation GPS Processor
    processor_success = test_citation_processor()
    
    if not processor_success:
        print("\n❌ Citation processor test failed - stopping")
        return False
        
    # Small delay between tests
    time.sleep(2)
    
    # Test 2: Citation-Schedule Matcher
    matcher_success = test_schedule_matcher()
    
    # Final results
    end_time = time.time()
    total_time = end_time - start_time
    
    print("\n" + "=" * 60)
    print("📋 TEST RESULTS SUMMARY")
    print("=" * 60)
    print(f"Citation GPS Processor: {'✅ PASS' if processor_success else '❌ FAIL'}")
    print(f"Citation-Schedule Matcher: {'✅ PASS' if matcher_success else '❌ FAIL'}")
    print(f"Total test time: {total_time:.1f} seconds")
    
    if processor_success and matcher_success:
        print("\n🎉 All tests passed! The production system is ready for full processing.")
        print("\n📋 Next steps:")
        print("1. Run full citation processing: python3 production_citation_processor.py --days 90")
        print("2. Match with schedules: python3 citation_schedule_matcher.py --citation-file processed_citations_*.csv --schedule-file Street_Sweeping_Schedule_Cleaned_Simple.csv")
        print("3. Set up weekly refresh cron job")
        
        cleanup_response = input("\n🧹 Clean up test files? (y/N): ")
        if cleanup_response.lower() == 'y':
            cleanup_test_files()
        
        return True
    else:
        print("\n❌ Some tests failed. Check the error messages above.")
        return False

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)