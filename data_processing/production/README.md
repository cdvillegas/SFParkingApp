# SF Parking Citation Processing - Production Scripts

This folder contains the **production-ready** scripts for the SF parking citation processing system.

## 🚀 Production Scripts (Use These)

### 🎯 **Complete End-to-End Pipeline**

1. **`full_pipeline_processor.py`** ⭐ **RECOMMENDED**
   - **Purpose**: Complete automated pipeline from SF Open Data APIs to final estimates
   - **Features**: Fetches fresh schedule data, processes 365 days of citations, generates estimates
   - **Output**: All intermediate and final datasets with comprehensive reporting
   - **Usage**: `python3 full_pipeline_processor.py --days 365 --workers 6`

2. **`run_full_pipeline.sh`** ⭐ **EASIEST**
   - **Purpose**: One-command launcher for the complete pipeline
   - **Features**: Dependency checking, progress monitoring, result summary
   - **Usage**: `./run_full_pipeline.sh 365 6`

### 🔧 **Individual Processing Components**

3. **`clean_schedule_data_simple.py`**
   - **Purpose**: Cleans and consolidates street sweeping schedule data
   - **Input**: `Street_Sweeping_Schedule_20250709.csv` (37,878 records)
   - **Output**: `Street_Sweeping_Schedule_Cleaned_Simple.csv` (22,909 records)
   - **Usage**: `python3 clean_schedule_data_simple.py`

4. **`production_citation_processor.py`** 
   - **Purpose**: Fetches and geocodes historical citations with parallel processing
   - **Features**: Rate limiting, retry logic, resumption, confidence filtering
   - **Output**: `processed_citations_YYYYMMDD_HHMMSS.csv`
   - **Usage**: `python3 production_citation_processor.py --days 90 --workers 4`

5. **`citation_schedule_matcher.py`**
   - **Purpose**: Matches citations to schedules and calculates estimated sweeper times
   - **Features**: Strict temporal filtering, spatial matching, statistical analysis
   - **Output**: `*_matches_*.csv`, `*_estimates_*.csv`, `*_report_*.json`
   - **Usage**: `python3 citation_schedule_matcher.py --citation-file processed_citations.csv --schedule-file Street_Sweeping_Schedule_Cleaned_Simple.csv`

### 🧪 **Testing & Validation**

6. **`test_production_system.py`**
   - **Purpose**: End-to-end testing with small sample data
   - **Usage**: `python3 test_production_system.py`

## 🔄 Production Workflows

### ⭐ **Option 1: Full Automated Pipeline (RECOMMENDED)**

```bash
# One command runs everything: schedule fetch → clean → citation fetch → geocode → match → estimates
./run_full_pipeline.sh 365 6

# Or use Python directly
python3 full_pipeline_processor.py --days 365 --workers 6 --output-dir ../output/pipeline_results/
```

### 🔧 **Option 2: Step-by-Step Manual Process**

```bash
# 1. Clean schedule data (run once or when schedule updates)
python3 clean_schedule_data_simple.py

# 2. Process citations (weekly or as needed)
python3 production_citation_processor.py --days 90 --workers 4

# 3. Match citations to schedules and generate estimates
python3 citation_schedule_matcher.py \
  --citation-file processed_citations_20250721_123456.csv \
  --schedule-file ../testing/sample_data/Street_Sweeping_Schedule_Cleaned_Simple.csv
```

### 🧪 **Option 3: Test First (RECOMMENDED for first-time users)**

```bash
# Test with small sample before running full dataset
python3 test_production_system.py
```

## 📊 Expected Processing Times

### Full Pipeline (365 days)
- **Complete Pipeline**: 8-24 hours (50K-200K citations)
- **Schedule Data Fetch**: ~2-5 minutes (fresh from SF API)
- **Schedule Cleaning**: ~30 seconds (reduces ~37K → ~23K records)
- **Citation Data Fetch**: ~10-30 minutes (365 days from SF API)
- **Citation Geocoding**: 6-20 hours (depends on citation volume and workers)
- **Citation Matching**: 10-60 minutes (spatial + temporal matching)

### Individual Components
- **90-day Citation Processing**: 2-6 hours (~20K-40K citations)
- **Citation Matching**: 5-30 minutes depending on dataset size  
- **Testing**: ~1 minute for 25 sample citations

## 🎯 Key Features

### Scalability
- **Parallel processing** with configurable worker threads
- **Batch processing** to handle large datasets
- **Rate limiting** to respect API usage policies
- **Resume capability** for interrupted processing

### Quality Control
- **Confidence filtering** (HIGH/MEDIUM geocoding only)
- **Strict temporal matching** (citations during scheduled sweeping hours)
- **Spatial validation** (≤50m distance threshold)
- **Comprehensive logging** and error handling

### Production Ready
- **SQLite progress tracking** for resumption
- **Comprehensive reporting** and analytics
- **Configurable parameters** via command line
- **Error recovery** and retry logic

## 📁 File Dependencies

These scripts expect to find:
- **Schedule data**: `SF Parking App/Street_Sweeping_Schedule_20250709.csv`
- **Sample cleaned data**: `../testing/sample_data/Street_Sweeping_Schedule_Cleaned_Simple.csv` (for testing)

## 🔧 Configuration Options

### Citation Processing
```bash
--days 90              # Days back to fetch (default: 90)
--workers 4            # Parallel workers (default: 4)  
--batch-size 100       # Processing batch size (default: 100)
--rate-limit 0.5       # Delay between API calls (default: 0.5s)
--min-confidence MEDIUM # Confidence threshold (default: MEDIUM)
```

### Citation-Schedule Matching
```bash
--max-distance 50      # Max matching distance in meters (default: 50)
--flexible-timing      # Allow citations outside scheduled hours
```

## 📈 Monitoring

Check these outputs for system health:
- **Logs**: `../output/logs/` - Processing and error logs
- **Databases**: `../output/databases/` - Resume and progress tracking
- **Reports**: `../output/` - Analysis and performance reports

## 🚨 Troubleshooting

**API Timeouts**: Increase `--rate-limit` or reduce `--workers`
**Low Success Rates**: Check internet connectivity and API availability
**Memory Issues**: Reduce `--batch-size` or process smaller date ranges
**No Matches**: Increase `--max-distance` or use `--flexible-timing`