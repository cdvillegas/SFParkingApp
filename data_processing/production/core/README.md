# SF Parking Citation-Schedule Matching System - Production

## 🚀 Production Pipeline Files

### Core Production Scripts
- **`production_citation_processor.py`** - Geocodes citations using Census API with parallel processing
- **`clean_schedule_data_day_specific.py`** - Creates day-specific schedule rows with correct week patterns  
- **`production_hybrid_matcher_day_specific.py`** - Day-specific citation-schedule matcher with left join
- **`full_pipeline_processor.py`** - Complete pipeline orchestrator (runs all steps end-to-end)

### Configuration & Support
- **`run_full_pipeline.sh`** - Shell script for complete pipeline execution

## 📋 Usage

### Complete Pipeline (Recommended)
```bash
# Full production pipeline (~25-30 minutes optimized)
python3 full_pipeline_processor.py --days 365

# Quick testing with existing geocoded data (~15 minutes)
python3 full_pipeline_processor.py --days 365 --skip-geocoding
```

### Command Line Options
```bash
python3 full_pipeline_processor.py [OPTIONS]

Options:
  --days DAYS           Number of days back to process citations (default: 365)
  --workers WORKERS     Number of parallel workers for geocoding (default: 50)
  --output-dir DIR      Output directory for all pipeline results
  --rate-limit RATE     Rate limit for API calls in seconds (default: 0.01)
  --batch-size SIZE     Batch size for geocoding (default: 5000)
  --skip-geocoding      Skip geocoding and use existing data for testing

Note: The pipeline automatically uses --no-resume mode for maximum performance,
storing results in memory instead of SQLite database to avoid concurrency issues.
```

### Individual Steps (Advanced)
```bash
# Step 1: Clean schedules (creates day-specific rows)
python3 clean_schedule_data_day_specific.py --input raw_schedules.csv --output cleaned_schedules.csv

# Step 2: Geocode citations
python3 production_citation_processor.py --input raw_citations.csv --output geocoded_citations.csv

# Step 3: Match citations to schedules (day-specific with left join)
python3 production_hybrid_matcher_day_specific.py \
  --citation-file geocoded_citations.csv \
  --schedule-file cleaned_schedules.csv \
  --output-prefix final_results
```

## 📊 Output Files

The pipeline creates timestamped output directories: `../output/pipeline_results/YYYYMMDD_HHMMSS/`

### Key Output Files
- **`day_specific_sweeper_estimates_TIMESTAMP.csv`** - Final schedule estimates (primary output)
- **`final_analysis_TIMESTAMP_schedules_TIMESTAMP.csv`** - Detailed schedule data
- **`final_analysis_TIMESTAMP_matches_TIMESTAMP.csv`** - Individual citation matches
- **`pipeline_report_TIMESTAMP.json`** - Complete processing report

### Schedule Estimates CSV Structure
**Location Fields:**
- `schedule_id`, `cnn`, `corridor`, `limits`, `cnn_right_left`, `block_side`

**Day-Specific Fields:**  
- `weekday` - Single day (Monday, Tuesday, etc.)
- `scheduled_from_hour`, `scheduled_to_hour` - Legal sweeping hours

**Week Pattern Fields:**
- `week1`, `week2`, `week3`, `week4`, `week5` - Binary flags (0/1) for month weeks

**Citation Statistics (when available):**
- `citation_count` - Number of citations matched to this schedule
- `avg_citation_time`, `min_citation_time`, `max_citation_time` - Estimated sweeper times

## 🔧 Key Features

### Day-Specific Architecture
- **34,284 day-specific schedule rows** (vs 23K aggregated)
- **Separate estimates per day** (Tuesday vs Wednesday may differ)
- **Left join approach** - ALL schedules included (even without citation data)

### Accurate Week Patterns
- **Correct bi-weekly schedules** (e.g., weeks 1&3: `1,0,1,0,0`)
- **Weekly schedules** (weeks 1-5: `1,1,1,1,1`)
- **Custom patterns** (e.g., weeks 1-4 only: `1,1,1,1,0`)

### Performance & Quality
- **468K+ citations processed** in ~10 minutes (after geocoding)
- **1.13M citation-schedule matches** with hybrid spatial indexing
- **200m matching radius** with street name validation
- **Time window enforcement** - only legal citation times included

### Geocoding & Data Pipeline
- **Census API geocoding** with parallel processing and in-memory storage
- **Optimized rate limiting** for maximum throughput (50 workers, 0.01s delay)
- **Memory-only mode** by default (--no-resume) to eliminate database locks
- **Massive batch processing** (5,000 citations per batch vs 200 previously)
- **Complete error handling** and logging

## 📈 Pipeline Performance

### Processing Times
- **Schedule cleaning**: ~5 seconds (37K → 34K day-specific records)
- **Citation geocoding**: ~10-15 minutes (468K citations, optimized)
- **Citation matching**: ~10 minutes (day-specific hybrid matching)
- **Total**: ~25-30 minutes for complete pipeline

### Data Quality Results
- **34,284 total schedules** (100% coverage with left join)
- **28,432 schedules with citation data** (83% have real timing estimates)
- **5,852 schedules without citations** (17% use schedule data only)
- **Week pattern accuracy**: 71% weekly, 13% bi-weekly 2&4, 10% bi-weekly 1&3

## 📁 Output Directory Structure

```
../output/pipeline_results/
├── 20250722_225343/                    # Timestamped run directory
│   ├── day_specific_sweeper_estimates_20250722_225343.csv  # 📋 PRIMARY OUTPUT
│   ├── final_analysis_20250722_225343_schedules_*.csv      # Detailed schedules
│   ├── final_analysis_20250722_225343_matches_*.csv        # Citation matches
│   ├── pipeline_report_20250722_225343.json               # Processing report
│   ├── citations_geocoded_20250722_225343.csv             # Geocoded citations
│   ├── schedule_cleaned_20250722_225343.csv               # Day-specific schedules
│   └── schedule_raw_20250722_225343.csv                   # Raw schedule data
└── [other timestamped runs...]
```

---

**Status**: ✅ Production Ready - Day-Specific System  
**Next**: iOS app integration using `day_specific_sweeper_estimates_*.csv`