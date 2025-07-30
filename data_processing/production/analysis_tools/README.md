# SF Parking Citation Processing - Analysis Tools

This folder contains **development and analysis tools** used for validation and debugging.

## 🔬 Analysis & Validation Scripts

### **Data Quality Analysis**

1. **`compare_cleaning_methods.py`**
   - **Purpose**: Compares manual vs automated schedule cleaning results
   - **Usage**: `python3 compare_cleaning_methods.py`
   - **Output**: Detailed comparison of record counts, aggregation differences
   - **When to use**: When validating cleaning approaches

2. **`spot_check_differences.py`**
   - **Purpose**: Deep-dive analysis of specific cleaning discrepancies
   - **Usage**: `python3 spot_check_differences.py`
   - **Output**: Detailed examination of individual record differences
   - **When to use**: When investigating why cleaning methods differ

3. **`accuracy_comparison.py`** 
   - **Purpose**: Compares accuracy of different matching methods
   - **Usage**: `python3 accuracy_comparison.py`
   - **Output**: Statistical comparison of matching algorithms
   - **When to use**: When validating citation-schedule matching approaches

4. **`match_analysis.py`**
   - **Purpose**: Analyzes citation-schedule matching results  
   - **Usage**: `python3 match_analysis.py`
   - **Output**: Detailed analysis of matching patterns and quality
   - **When to use**: When evaluating matching performance

5. **`debug_performance.py`**
   - **Purpose**: Performance debugging and profiling tools
   - **Usage**: `python3 debug_performance.py` 
   - **Output**: Performance metrics and bottleneck analysis
   - **When to use**: When optimizing pipeline performance

## 📊 **Analysis Results Summary**

Based on our analysis:

### **Cleaning Method Comparison**
- **Manual cleaning**: 22,573 records
- **Automated cleaning**: 22,909 records  
- **Verdict**: ✅ **Automated script is more accurate**

### **Key Findings**
- **336 additional records** in automated version are valid
- **Multiple time windows preserved** correctly by automated script
- **Manual process over-consolidated** records that should remain separate
- **No missing records** - automated found valid schedules manual missed

### **Validation Results**
All spot-checked cases confirmed the automated script correctly:
- Preserves different sweeping time windows (e.g., 0-2 AM vs 8-10 AM)
- Maintains separate schedules for different day patterns
- Handles holiday schedules vs regular schedules properly

## ⚠️ **These are NOT Production Scripts**

**Important**: These scripts are for analysis and validation only. 

**For actual data processing**, use the scripts in `../core/`:
- `full_pipeline_processor.py`
- `run_full_pipeline.sh`  
- `test_production_system.py`

## 🎯 **When to Use These Tools**

### **During Development**
- Validating new cleaning algorithms
- Comparing different processing approaches
- Debugging data quality issues

### **During Validation**
- Spot-checking processing results
- Investigating discrepancies
- Generating analysis reports

### **NOT for Production**
- These scripts analyze existing data
- They don't generate production outputs
- Use `../core/` scripts for actual processing

## 📈 **Analysis Capabilities**

### **Column Structure Analysis**
- Compare schemas between datasets
- Identify missing or extra columns
- Validate data type consistency

### **Record-Level Comparison**
- Find records in one dataset but not another
- Compare aggregation logic differences
- Analyze day pattern variations

### **Spot Check Validation**
- Examine specific problematic records
- Trace back to original data sources
- Validate cleaning decisions

## 🚀 **Quick Usage Examples**

```bash
# Compare manual vs automated cleaning
python3 compare_cleaning_methods.py

# Deep-dive into specific differences
python3 spot_check_differences.py

# Note: These require the following files to exist:
# - ../testing/test_runs/manual_cleaning.csv (your manual cleaning)
# - ../testing/sample_data/Street_Sweeping_Schedule_Cleaned_Simple.csv (automated)
# - ../../SF Parking App/Street_Sweeping_Schedule_20250709.csv (original)
```