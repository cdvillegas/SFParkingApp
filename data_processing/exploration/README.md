# SF Parking Citation Processing - Exploration & Development

This folder contains **experimental scripts** and **early development work** used to build the production system.

## 📁 Folder Structure

### `early_demos/`
Early proof-of-concept and demo scripts:
- **`simple_citation_gps_demo.py`** - Original demo script for citation geocoding validation
  - Used to test geocoding accuracy with small samples
  - Developed the validation logic later used in production
  - **Status**: Superseded by `production_citation_processor.py`

### `citation_analysis_experiments/`
Various experiments with citation data analysis:
- **`citation_coordinate_matching.py`** - Early spatial matching experiments
- **`street_sweeping_*.py`** - API testing and data exploration scripts
- **`test_*.py`** - Various small tests and experiments
- **`citation_gps_results_*.csv`** - Sample outputs from early testing
- **`citation_results_100.log`** - Log files from early experiments

### `schedule_cleaning_experiments/`
Development of schedule data cleaning approaches:
- **`clean_schedule_data.py`** - Complex 2-step cleaning approach (superseded)
- **`validate_clean_data.py`** - Data quality validation scripts
- **`Street_Sweeping_Schedule_Cleaned.csv`** - Output from complex method
- **`cleaning_report.txt`** - Analysis comparing cleaning methods

## 🔬 Key Discoveries from Exploration

### Citation Geocoding
- **Success Rate**: ~85-90% for HIGH/MEDIUM confidence geocoding
- **Validation**: Street name + number matching crucial for accuracy
- **API Limits**: Rate limiting and retry logic essential for large datasets
- **Confidence Scoring**: 3-tier system (HIGH/MEDIUM/LOW) works well

### Schedule Data Cleaning
- **Simple vs Complex**: Simple groupby method more effective (39.5% vs 37.3% reduction)
- **Day Parsing**: Boolean columns much easier than string parsing
- **Data Quality**: ~17 records missing GPS coordinates need manual review

### Citation-Schedule Matching
- **Distance Threshold**: 50m works well given GPS accuracy
- **Temporal Matching**: Strict timing (during scheduled hours) produces cleaner results
- **Statistical Requirements**: Need 3+ citations per schedule for reliable estimates

## 📊 Evolution of Approaches

### Citation Processing
1. **Demo Script** → Manual 10-citation validation
2. **Parallel Processing** → 4 worker threads for scalability  
3. **Resume Capability** → SQLite database for progress tracking
4. **Quality Control** → Confidence filtering and validation logic

### Schedule Cleaning
1. **Complex Method** → 2-step process (combine days, then merge weeks)
2. **Simple Method** → Single groupby with max aggregation ✅ **Winner**

### Citation-Schedule Matching
1. **Flexible Timing** → Include citations before/during/after schedules
2. **Strict Timing** → Only citations during scheduled hours ✅ **Better Results**

## ⚠️ Important Notes

- **These scripts are for reference only** - use production scripts for actual processing
- **Some paths may be broken** - files have been moved around during development
- **Data files included** - for testing and comparison purposes
- **Logs preserved** - show performance and quality metrics from development

## 🔄 How This Led to Production System

The exploration work directly informed the production system design:

1. **Early demos** → Validated approach and identified challenges
2. **Multiple experiments** → Tested different approaches and parameters  
3. **Performance testing** → Identified bottlenecks and optimization opportunities
4. **Quality analysis** → Developed validation and confidence scoring systems
5. **Comparison studies** → Selected best approaches for production

## 📈 Key Metrics Discovered

- **Processing Speed**: ~35 citations/minute with parallel processing
- **Geocoding Quality**: 90%+ accuracy with proper validation
- **Data Reduction**: 39.5% reduction in duplicate schedule records
- **Matching Effectiveness**: 77% temporal relevance with strict timing