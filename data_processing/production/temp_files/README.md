# Temporary Files

This folder contains temporary files generated during processing.

## 📁 Contents

### **Log Files**
- `citation_processing.log` - Processing logs and debug information
- `citation_schedule_matching.log` - Matching analysis logs

### **Progress Databases**
- `citation_processing_progress.db` - SQLite database for resume capability
- Contains processed citations to prevent duplicate work during interruptions

### **Temporary CSV Files**
- `temp_citations_for_geocoding.csv` - Temporary citation data for processing
- Various other `temp_*.csv` files created during pipeline execution

## 🧹 **Cleanup**

These files can be safely deleted:
- **After successful processing** - logs and temp files are no longer needed
- **To start fresh** - delete progress DB to reprocess everything from scratch
- **For disk space** - temp files can accumulate during large processing runs

## 🔄 **Auto-Generated**

All files in this folder are automatically created by the production scripts:
- `full_pipeline_processor.py`
- `production_citation_processor.py`
- `citation_schedule_matcher.py`

**No need to manually manage** - scripts handle creation and cleanup.