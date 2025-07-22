# SF Parking Citation Processing - Core Production Scripts

This folder contains **ONLY the core production scripts** needed for the SF parking citation processing system.

## 🚀 Core Production Scripts

### ⭐ **Primary Production Scripts (Use These)**

1. **`full_pipeline_processor.py`** ⭐ **MAIN SCRIPT**
   - **Purpose**: Complete end-to-end automated pipeline
   - **What it does**: Fetches fresh data → cleans → geocodes → matches → generates estimates
   - **Usage**: `python3 full_pipeline_processor.py --days 365 --workers 6`
   - **Runtime**: 12-24 hours for full year

2. **`run_full_pipeline.sh`** ⭐ **EASIEST TO USE**
   - **Purpose**: One-command launcher with dependency checking
   - **What it does**: Runs the full pipeline with progress monitoring
   - **Usage**: `./run_full_pipeline.sh 365 6`
   - **Best for**: Production deployment

### 🔧 **Individual Component Scripts**

3. **`production_citation_processor.py`**
   - **Purpose**: Geocodes citations with parallel processing
   - **When to use**: When you only need citation geocoding
   - **Features**: Resume capability, confidence filtering, rate limiting

4. **`citation_schedule_matcher.py`**
   - **Purpose**: Matches citations to schedules and calculates estimates
   - **When to use**: When you have geocoded citations and cleaned schedules
   - **Features**: Strict temporal filtering, spatial matching

5. **`clean_schedule_data_simple.py`**
   - **Purpose**: Cleans and consolidates schedule data
   - **When to use**: When you need to process raw schedule data
   - **Output**: Reduces ~37K → ~23K records

### 🧪 **Testing & Validation**

6. **`test_production_system.py`**
   - **Purpose**: End-to-end testing with small sample
   - **When to use**: Before running full production pipeline
   - **Runtime**: ~1 minute

## 🎯 **Quick Start Commands**

### For Full Production Processing:
```bash
# Option 1: Shell script (recommended for first-time users)
./run_full_pipeline.sh 365 6

# Option 2: Python direct (for advanced users)
python3 full_pipeline_processor.py --days 365 --workers 6 --output-dir ../../output/production_run/
```

### For Testing First:
```bash
# Always test before running full pipeline
python3 test_production_system.py
```

### For Weekly Updates:
```bash
# Process only recent data for weekly refresh
./run_full_pipeline.sh 14 6
```

## ⏱️ **Expected Runtimes**

- **Testing**: ~1 minute (25 citations)
- **Weekly refresh**: 2-4 hours (14 days, ~5-10K citations)
- **Full processing**: 12-24 hours (365 days, ~400K citations)

## 📊 **Expected Outputs**

After successful run, you'll have:
- **`sweeper_time_estimates_*.csv`** - Final predicted arrival times for iOS integration
- **`citations_geocoded_*.csv`** - All processed citation data
- **`schedule_cleaned_*.csv`** - Clean schedule data
- **`pipeline_report_*.json`** - Complete processing report

## 🚨 **Important Notes**

- **These are the ONLY files you need** for production processing
- **All temporary files and logs** are created in `../../output/` during processing
- **No need to modify these scripts** - they're production-ready
- **For debugging or analysis**, see `../analysis_tools/`

## 🔄 **Dependencies**

Required Python packages:
```bash
pip3 install requests pandas geopy sqlite3
```

## 💡 **Usage Tips**

1. **Start with testing**: Always run `test_production_system.py` first
2. **Use shell script**: `run_full_pipeline.sh` handles dependency checking
3. **Monitor progress**: Check logs in `../../output/logs/` during processing
4. **Weekly refresh**: Use `--days 14` instead of 365 for regular updates