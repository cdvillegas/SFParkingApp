#!/usr/bin/env python3
"""
Production Citation GPS Processing System

Processes all historical street sweeping citations to get GPS coordinates
with confidence filtering, parallel processing, and resumption capability.

Features:
- Parallel geocoding with worker threads
- Retry logic for API timeouts
- Progress tracking and resumption
- Confidence filtering (HIGH/MEDIUM only)
- Rate limiting to prevent API throttling
- Comprehensive logging and error handling
- Weekly refresh optimization

Usage:
python3 production_citation_processor.py --days 30 --workers 4 --batch-size 100
"""

import requests
import pandas as pd
from geopy.geocoders import Nominatim
import time
import re
import csv
import json
import threading
import queue
import argparse
from datetime import datetime, timedelta
from pathlib import Path
import logging
from typing import Dict, List, Optional, Tuple
from concurrent.futures import ThreadPoolExecutor, as_completed
import sqlite3
import os

class CitationGeocodingProcessor:
    def __init__(self, 
                 max_workers: int = 4,
                 batch_size: int = 100,
                 rate_limit_delay: float = 0.5,
                 max_retries: int = 3,
                 timeout: int = 10,
                 min_confidence: str = "MEDIUM"):
        
        self.max_workers = max_workers
        self.batch_size = batch_size
        self.rate_limit_delay = rate_limit_delay
        self.max_retries = max_retries
        self.timeout = timeout
        self.min_confidence = min_confidence
        
        # Set up logging
        self.setup_logging()
        
        # Initialize geocoder with custom user agent
        self.geolocator = Nominatim(user_agent="sf_parking_citation_processor_v1.0")
        
        # Progress tracking
        self.processed_count = 0
        self.success_count = 0
        self.high_confidence_count = 0
        self.medium_confidence_count = 0
        self.failed_count = 0
        
        # Thread-safe rate limiting
        self.last_request_time = 0
        self.rate_lock = threading.Lock()
        
        # Resume capability
        self.resume_db = "citation_processing_progress.db"
        self.setup_progress_db()
        
    def setup_logging(self):
        """Set up comprehensive logging"""
        log_format = '%(asctime)s - %(levelname)s - %(message)s'
        logging.basicConfig(
            level=logging.INFO,
            format=log_format,
            handlers=[
                logging.FileHandler('citation_processing.log'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
        
    def setup_progress_db(self):
        """Set up SQLite database for progress tracking and resumption"""
        conn = sqlite3.connect(self.resume_db)
        cursor = conn.cursor()
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS processed_citations (
                citation_id TEXT PRIMARY KEY,
                address TEXT,
                datetime TEXT,
                latitude REAL,
                longitude REAL,
                returned_address TEXT,
                confidence TEXT,
                confidence_score INTEGER,
                geocoding_status TEXT,
                processed_timestamp TEXT
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS processing_session (
                session_id INTEGER PRIMARY KEY,
                start_time TEXT,
                end_time TEXT,
                total_citations INTEGER,
                processed_count INTEGER,
                success_rate REAL,
                parameters TEXT
            )
        ''')
        
        conn.commit()
        conn.close()
        
    def get_processed_citations(self) -> set:
        """Get set of already processed citation IDs for resumption"""
        conn = sqlite3.connect(self.resume_db)
        cursor = conn.cursor()
        cursor.execute("SELECT citation_id FROM processed_citations")
        processed = {row[0] for row in cursor.fetchall()}
        conn.close()
        return processed
        
    def save_citation_result(self, citation_id: str, result: Dict):
        """Save individual citation result to database"""
        conn = sqlite3.connect(self.resume_db)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT OR REPLACE INTO processed_citations 
            (citation_id, address, datetime, latitude, longitude, returned_address, 
             confidence, confidence_score, geocoding_status, processed_timestamp)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            citation_id,
            result.get('address'),
            result.get('datetime'),
            result.get('latitude'),
            result.get('longitude'),
            result.get('returned_address'),
            result.get('confidence'),
            result.get('confidence_score'),
            result.get('geocoding_status'),
            datetime.now().isoformat()
        ))
        
        conn.commit()
        conn.close()
        
    def load_citations_from_file(self, input_file: str) -> List[Dict]:
        """Load citations from CSV file for processing"""
        self.logger.info(f"Loading citations from file: {input_file}")
        
        try:
            df = pd.read_csv(input_file)
            
            # Convert DataFrame to list of dictionaries in expected format
            citations = []
            for _, row in df.iterrows():
                citation = {
                    'citation_number': row.get('citation_number', f"file_{len(citations)}"),
                    'citation_location': row['citation_location'],
                    'citation_issued_datetime': row['citation_issued_datetime']
                }
                citations.append(citation)
                
            self.logger.info(f"✅ Loaded {len(citations)} citations from file")
            return citations
            
        except Exception as e:
            self.logger.error(f"Error loading citations from file: {e}")
            raise
    
    def fetch_citations(self, days_back: int = 90, limit: int = None) -> List[Dict]:
        """Fetch street cleaning citations from SF Open Data API"""
        self.logger.info(f"Fetching citations from last {days_back} days...")
        
        # Calculate date range
        end_date = datetime.now()
        start_date = end_date - timedelta(days=days_back)
        start_date_str = start_date.strftime('%Y-%m-%d')
        
        url = "https://data.sfgov.org/resource/ab4h-6ztd.json"
        
        all_citations = []
        offset = 0
        batch_limit = 50000  # API limit per request
        
        while True:
            params = {
                '$limit': min(batch_limit, limit - len(all_citations)) if limit else batch_limit,
                '$offset': offset,
                '$where': f"violation_desc = 'STR CLEAN' AND citation_issued_datetime > '{start_date_str}'",
                '$order': 'citation_issued_datetime DESC'
            }
            
            try:
                self.logger.info(f"Fetching batch starting at offset {offset}...")
                response = requests.get(url, params=params, timeout=30)
                response.raise_for_status()
                
                batch_citations = response.json()
                if not batch_citations:
                    break
                    
                all_citations.extend(batch_citations)
                self.logger.info(f"Fetched {len(batch_citations)} citations (total: {len(all_citations)})")
                
                # Check if we've reached the limit or got fewer results than requested
                if limit and len(all_citations) >= limit:
                    all_citations = all_citations[:limit]
                    break
                    
                if len(batch_citations) < batch_limit:
                    break
                    
                offset += batch_limit
                time.sleep(1)  # Rate limit API requests
                
            except Exception as e:
                self.logger.error(f"Error fetching citations: {e}")
                raise
                
        self.logger.info(f"Total citations fetched: {len(all_citations)}")
        return all_citations
        
    def extract_street_number(self, address: str) -> Optional[int]:
        """Extract street number from address"""
        match = re.match(r'^(\d+)', address.strip())
        return int(match.group(1)) if match else None
        
    def normalize_street_suffix(self, street_name: str) -> str:
        """Normalize street suffixes for fuzzy matching"""
        suffix_map = {
            ' STREET': ' ST', ' AVENUE': ' AVE', ' BOULEVARD': ' BLVD',
            ' DRIVE': ' DR', ' COURT': ' CT', ' PLACE': ' PL',
            ' LANE': ' LN', ' ROAD': ' RD', ' PARKWAY': ' PKWY'
        }
        
        street_upper = street_name.upper()
        for full_suffix, short_suffix in suffix_map.items():
            if street_upper.endswith(full_suffix):
                return street_upper.replace(full_suffix, short_suffix)
        
        return street_upper
        
    def extract_street_name(self, address: str) -> str:
        """Extract and normalize street name from address"""
        street_name = re.sub(r'^\d+\s*', '', address.strip())
        return self.normalize_street_suffix(street_name)
        
    def validate_geocoding_result(self, original_address: str, returned_address: str) -> Tuple[int, str]:
        """Validate geocoding result and return confidence score and level"""
        
        # Extract components from original address
        orig_number = self.extract_street_number(original_address)
        orig_street = self.extract_street_name(original_address)
        
        ret_street_upper = returned_address.upper()
        
        # Check 1: Street name matching (fuzzy)
        orig_core = orig_street
        for suffix in [' ST', ' AVE', ' BLVD', ' DR', ' CT', ' PL', ' WAY', ' LN', ' RD', ' PKWY']:
            orig_core = orig_core.replace(suffix, '')
            
        street_in_result = orig_core.strip() in ret_street_upper
        
        # Check 2: Street number matching
        number_in_result = str(orig_number) in returned_address if orig_number else False
        
        # Check 3: Not a general reference
        is_general = any(phrase in ret_street_upper for phrase in [
            'AVENUE,', 'STREET,', 'BOULEVARD,', 'DISTRICT,', 'NEIGHBORHOOD,', 'SAN FRANCISCO'
        ])
        
        # Calculate confidence score
        confidence_score = 0
        if street_in_result: confidence_score += 40
        if number_in_result: confidence_score += 50
        if not is_general: confidence_score += 10
        
        if confidence_score >= 80:
            confidence = "HIGH"
        elif confidence_score >= 50:
            confidence = "MEDIUM"
        else:
            confidence = "LOW"
            
        return confidence_score, confidence
        
    def rate_limited_geocode(self, address: str) -> Optional[object]:
        """Perform rate-limited geocoding with retry logic"""
        with self.rate_lock:
            # Ensure we don't exceed rate limits
            elapsed = time.time() - self.last_request_time
            if elapsed < self.rate_limit_delay:
                time.sleep(self.rate_limit_delay - elapsed)
            self.last_request_time = time.time()
            
        full_address = f"{address}, San Francisco, CA"
        
        for attempt in range(self.max_retries):
            try:
                location = self.geolocator.geocode(full_address, timeout=self.timeout)
                return location
                
            except Exception as e:
                self.logger.warning(f"Geocoding attempt {attempt + 1} failed for '{address}': {e}")
                if attempt < self.max_retries - 1:
                    time.sleep(2 ** attempt)  # Exponential backoff
                    
        return None
        
    def process_citation(self, citation: Dict) -> Dict:
        """Process a single citation to get GPS coordinates with validation"""
        citation_id = citation.get('citation_number', f"unknown_{hash(str(citation))}")
        address = citation['citation_location']
        date_time = citation['citation_issued_datetime']
        
        result = {
            'citation_id': citation_id,
            'address': address,
            'datetime': date_time,
            'latitude': None,
            'longitude': None,
            'returned_address': None,
            'confidence': 'FAILED',
            'confidence_score': 0,
            'geocoding_status': 'NOT_PROCESSED'
        }
        
        try:
            location = self.rate_limited_geocode(address)
            
            if location:
                result.update({
                    'latitude': location.latitude,
                    'longitude': location.longitude,
                    'returned_address': location.address,
                    'geocoding_status': 'SUCCESS'
                })
                
                # Validate the result
                score, confidence = self.validate_geocoding_result(address, location.address)
                result.update({
                    'confidence': confidence,
                    'confidence_score': score
                })
                
            else:
                result.update({
                    'geocoding_status': 'NO_RESULT',
                    'confidence': 'FAILED'
                })
                
        except Exception as e:
            result.update({
                'geocoding_status': f'ERROR: {str(e)}',
                'confidence': 'ERROR'
            })
            
        # Save result to database immediately
        self.save_citation_result(citation_id, result)
        
        return result
        
    def process_citations_batch(self, citations: List[Dict]) -> List[Dict]:
        """Process a batch of citations using thread pool"""
        results = []
        
        with ThreadPoolExecutor(max_workers=self.max_workers) as executor:
            # Submit all tasks
            future_to_citation = {
                executor.submit(self.process_citation, citation): citation 
                for citation in citations
            }
            
            # Collect results as they complete
            for future in as_completed(future_to_citation):
                citation = future_to_citation[future]
                try:
                    result = future.result()
                    results.append(result)
                    
                    # Update counters
                    self.processed_count += 1
                    if result['confidence'] in ['HIGH', 'MEDIUM']:
                        self.success_count += 1
                        if result['confidence'] == 'HIGH':
                            self.high_confidence_count += 1
                        else:
                            self.medium_confidence_count += 1
                    else:
                        self.failed_count += 1
                        
                    # Log progress
                    if self.processed_count % 10 == 0:
                        success_rate = (self.success_count / self.processed_count) * 100
                        self.logger.info(f"Processed {self.processed_count} citations. "
                                       f"Success rate: {success_rate:.1f}% "
                                       f"(H:{self.high_confidence_count}, M:{self.medium_confidence_count}, F:{self.failed_count})")
                        
                except Exception as e:
                    self.logger.error(f"Error processing citation {citation.get('citation_location', 'unknown')}: {e}")
                    self.failed_count += 1
                    
        return results
        
    def export_results(self, output_file: str, min_confidence: str = "MEDIUM"):
        """Export processed results to CSV, filtering by confidence level"""
        self.logger.info(f"Exporting results with minimum confidence: {min_confidence}")
        
        confidence_levels = {
            'HIGH': ['HIGH'],
            'MEDIUM': ['HIGH', 'MEDIUM'],
            'LOW': ['HIGH', 'MEDIUM', 'LOW']
        }
        
        allowed_confidence = confidence_levels.get(min_confidence, ['HIGH', 'MEDIUM'])
        
        conn = sqlite3.connect(self.resume_db)
        query = f"""
            SELECT citation_id, address, datetime, latitude, longitude, returned_address, 
                   confidence, confidence_score, geocoding_status
            FROM processed_citations 
            WHERE confidence IN ({','.join(['?' for _ in allowed_confidence])})
            ORDER BY confidence DESC, confidence_score DESC
        """
        
        df = pd.read_sql_query(query, conn, params=allowed_confidence)
        conn.close()
        
        df.to_csv(output_file, index=False)
        self.logger.info(f"Exported {len(df)} results to {output_file}")
        
        return len(df)
        
    def generate_report(self) -> Dict:
        """Generate processing summary report"""
        total_processed = self.processed_count
        success_rate = (self.success_count / total_processed * 100) if total_processed > 0 else 0
        
        report = {
            'processing_summary': {
                'total_processed': total_processed,
                'high_confidence': self.high_confidence_count,
                'medium_confidence': self.medium_confidence_count,
                'low_confidence': self.failed_count,
                'success_rate': f"{success_rate:.1f}%",
                'usable_results': self.success_count
            },
            'configuration': {
                'max_workers': self.max_workers,
                'batch_size': self.batch_size,
                'rate_limit_delay': self.rate_limit_delay,
                'max_retries': self.max_retries,
                'timeout': self.timeout,
                'min_confidence': self.min_confidence
            }
        }
        
        return report
        
    def run_full_processing(self, days_back: int = 90, limit: int = None, 
                          resume: bool = True, input_file: str = None) -> Dict:
        """Run the complete citation processing pipeline"""
        self.logger.info("🚗 Starting Production Citation GPS Processing")
        self.logger.info("=" * 60)
        
        start_time = datetime.now()
        
        # Step 1: Load citations (from file or API)
        if input_file:
            all_citations = self.load_citations_from_file(input_file)
        else:
            all_citations = self.fetch_citations(days_back, limit)
        
        # Step 2: Filter already processed citations if resuming
        if resume:
            processed_ids = self.get_processed_citations()
            remaining_citations = [
                c for c in all_citations 
                if c.get('citation_number', f"unknown_{hash(str(c))}") not in processed_ids
            ]
            self.logger.info(f"Resuming: {len(processed_ids)} already processed, "
                           f"{len(remaining_citations)} remaining")
        else:
            remaining_citations = all_citations
            
        if not remaining_citations:
            self.logger.info("No citations to process!")
            return self.generate_report()
            
        # Step 3: Process in batches
        total_citations = len(remaining_citations)
        self.logger.info(f"Processing {total_citations} citations in batches of {self.batch_size}")
        
        for i in range(0, total_citations, self.batch_size):
            batch_end = min(i + self.batch_size, total_citations)
            batch = remaining_citations[i:batch_end]
            
            self.logger.info(f"Processing batch {i//self.batch_size + 1}: "
                           f"citations {i+1}-{batch_end} of {total_citations}")
            
            batch_results = self.process_citations_batch(batch)
            
            # Log batch completion
            batch_success = sum(1 for r in batch_results if r['confidence'] in ['HIGH', 'MEDIUM'])
            batch_rate = (batch_success / len(batch_results) * 100) if batch_results else 0
            self.logger.info(f"Batch completed: {batch_success}/{len(batch_results)} success ({batch_rate:.1f}%)")
            
        # Step 4: Generate final report
        end_time = datetime.now()
        processing_time = end_time - start_time
        
        report = self.generate_report()
        report['timing'] = {
            'start_time': start_time.isoformat(),
            'end_time': end_time.isoformat(),
            'processing_time': str(processing_time),
            'citations_per_minute': round(total_citations / (processing_time.total_seconds() / 60), 2)
        }
        
        self.logger.info("🎉 Processing completed!")
        self.logger.info(f"⏱️  Total time: {processing_time}")
        self.logger.info(f"📊 Success rate: {report['processing_summary']['success_rate']}")
        self.logger.info(f"✅ Usable results: {report['processing_summary']['usable_results']}")
        
        return report

def main():
    parser = argparse.ArgumentParser(description='Production Citation GPS Processing')
    parser.add_argument('--days', type=int, default=90, 
                       help='Number of days back to fetch citations (default: 90)')
    parser.add_argument('--limit', type=int, default=None,
                       help='Limit number of citations to process (for testing)')
    parser.add_argument('--input-file', type=str, default=None,
                       help='Input CSV file with citation data (alternative to API fetching)')
    parser.add_argument('--workers', type=int, default=4,
                       help='Number of parallel workers (default: 4)')
    parser.add_argument('--batch-size', type=int, default=100,
                       help='Batch size for processing (default: 100)')
    parser.add_argument('--rate-limit', type=float, default=0.5,
                       help='Rate limit delay between requests (default: 0.5s)')
    parser.add_argument('--min-confidence', choices=['HIGH', 'MEDIUM', 'LOW'], 
                       default='MEDIUM', help='Minimum confidence for export (default: MEDIUM)')
    parser.add_argument('--output', type=str, 
                       default=f'processed_citations_{datetime.now().strftime("%Y%m%d_%H%M%S")}.csv',
                       help='Output CSV filename')
    parser.add_argument('--no-resume', action='store_true',
                       help='Start fresh instead of resuming previous processing')
    
    args = parser.parse_args()
    
    # Initialize processor
    processor = CitationGeocodingProcessor(
        max_workers=args.workers,
        batch_size=args.batch_size,
        rate_limit_delay=args.rate_limit,
        min_confidence=args.min_confidence
    )
    
    try:
        # Run processing
        report = processor.run_full_processing(
            days_back=args.days,
            limit=args.limit,
            resume=not args.no_resume,
            input_file=args.input_file
        )
        
        # Export results
        exported_count = processor.export_results(args.output, args.min_confidence)
        
        # Save report
        report_file = f"processing_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(report_file, 'w') as f:
            json.dump(report, f, indent=2)
            
        print(f"\n🎯 FINAL RESULTS:")
        print(f"📁 Citation data: {args.output} ({exported_count} records)")
        print(f"📊 Processing report: {report_file}")
        print(f"💾 Resume database: {processor.resume_db}")
        
    except KeyboardInterrupt:
        print("\n⚠️ Processing interrupted. Progress saved for resumption.")
    except Exception as e:
        processor.logger.error(f"Processing failed: {e}")
        raise

if __name__ == "__main__":
    main()