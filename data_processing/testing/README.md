# SF Parking Citation Processing - Testing & Sample Data

This folder contains **test files**, **sample data**, and **test outputs** used to validate the production system.

## 📁 Folder Structure

### `test_runs/`
Outputs from test runs and validation:
- **`test_*.csv`** - Sample citation processing results
- **`test_*.json`** - Test analysis reports  
- **`strict_timing_*.csv`** - Results from strict timing validation
- **`strict_timing_*.json`** - Timing comparison reports

### `sample_data/`
Clean reference datasets for testing:
- **`Street_Sweeping_Schedule_Cleaned_Simple.csv`** - Cleaned schedule data (22,909 records)
  - Used by production scripts and testing
  - Result of 39.5% duplicate reduction from original 37,878 records

## 🧪 Test Results Summary

### End-to-End System Test
- **Citation Processing**: ✅ 22 citations processed with 100% HIGH confidence
- **Schedule Matching**: ✅ 65 matches found with strict temporal filtering
- **Processing Time**: 37.6 seconds for complete pipeline
- **Success Rate**: 100% for sample dataset

### Timing Comparison Results
| Method | Matches | Schedules | Processing Time |
|--------|---------|-----------|----------------|
| Flexible Timing | 84 matches | 77 schedules | 21.0 seconds |
| Strict Timing | 65 matches | 58 schedules | 3.8 seconds |

### Quality Metrics
- **Temporal Relevance**: 100% DURING_SCHEDULE (with strict timing)
- **Spatial Accuracy**: Average 61m distance (within GPS accuracy)
- **Confidence Distribution**: 100% HIGH confidence citations
- **Coverage**: 3 schedules with sufficient data for time estimates

## 📊 Sample Test Data Analysis

### Citation Processing Results (`test_citations.csv`)
- **Total Records**: 22 high-confidence geocoded citations
- **Time Range**: June 27, 2025 (Friday) citations
- **Confidence**: 100% HIGH (90+ confidence score)
- **Geographic Distribution**: Various SF neighborhoods

### Schedule Matching Results (`strict_timing_test_matches_*.csv`)
- **Matches Found**: 65 citation-schedule pairs
- **Unique Schedules**: 58 different schedule blocks
- **Distance Range**: 31-99 meters from schedule coordinates
- **Time Alignment**: All citations occur during scheduled sweeping hours

### Estimated Sweeper Times (`strict_timing_test_estimates_*.csv`)
Generated time estimates for schedules with sufficient citation data:
- **22nd St (Noe-Castro)**: Estimated arrival 11:30 AM (schedule 12:00-2:00 PM)
- **Alvarado St**: Multiple blocks with consistent 11:30 AM estimates
- **Confidence Level**: MEDIUM (3-4 citations per schedule)

## ✅ Validation Checklist

### System Integration
- [x] Citation processor handles API calls and rate limiting
- [x] Geocoding validation works with confidence scoring  
- [x] Schedule data loading and GPS coordinate parsing
- [x] Spatial matching within distance threshold
- [x] Temporal filtering for strict timing mode
- [x] Statistical analysis and time estimation
- [x] CSV export and JSON reporting

### Performance
- [x] Processing speed acceptable for production use
- [x] Memory usage reasonable for large datasets
- [x] Error handling and recovery mechanisms
- [x] Resume capability for interrupted processing

### Data Quality
- [x] High geocoding accuracy (90%+ confidence)
- [x] Proper temporal alignment (citations during sweeping)
- [x] Reasonable spatial matching (within GPS accuracy)
- [x] Sufficient statistical rigor (3+ citations for estimates)

## 🎯 Test Data Usage

### For Development
```bash
# Use sample data for development testing
python3 production_citation_processor.py --limit 25 --output test_output.csv

# Test matching with sample schedule data  
python3 citation_schedule_matcher.py \
  --citation-file test_output.csv \
  --schedule-file testing/sample_data/Street_Sweeping_Schedule_Cleaned_Simple.csv
```

### For Validation
```bash
# Run complete end-to-end test
python3 test_production_system.py
```

## 📈 Performance Benchmarks

Based on test results, expected full production performance:

- **25 citations**: 37.6 seconds (100% success)
- **Projected 10,000 citations**: ~4 hours processing time  
- **Projected 40,000 citations**: ~16 hours processing time
- **Matching analysis**: 5-30 minutes depending on dataset size

## ⚠️ Test Limitations

- **Small sample size**: Only 22 citations for testing
- **Single day coverage**: June 27, 2025 data only
- **Geographic concentration**: Not representative of full SF distribution
- **Limited temporal range**: Morning citations only

For full validation, run production system with 90-day dataset.