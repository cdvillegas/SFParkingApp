#!/bin/bash
#
# SF Parking Citation Analysis - Full Pipeline Launcher
#
# This script runs the complete end-to-end processing pipeline for SF parking citations.
# It will process a full year of citation data and generate estimated sweeper arrival times.
#
# Usage:
#   ./run_full_pipeline.sh [days] [workers]
#
# Examples:
#   ./run_full_pipeline.sh                  # Process 365 days with 6 workers
#   ./run_full_pipeline.sh 180 4           # Process 180 days with 4 workers
#   ./run_full_pipeline.sh 30 2            # Process 30 days with 2 workers (testing)
#

set -e  # Exit on any error

# Default parameters
DAYS=${1:-365}
WORKERS=${2:-6}
OUTPUT_DIR="../output/pipeline_results/$(date +%Y%m%d_%H%M%S)"

echo "🚀 SF Parking Citation Analysis - Full Production Pipeline"
echo "=========================================================="
echo "📅 Processing: $DAYS days of data"
echo "⚙️  Workers: $WORKERS parallel geocoding threads"
echo "📁 Output: $OUTPUT_DIR"
echo "=========================================================="

# Confirmation for large datasets
if [ "$DAYS" -gt 180 ]; then
    echo "⚠️  WARNING: Processing $DAYS days may take 8-24 hours and process 50K-200K citations"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Cancelled by user"
        exit 1
    fi
fi

# Check dependencies
echo "🔍 Checking dependencies..."

if ! command -v python3 &> /dev/null; then
    echo "❌ python3 is required but not installed"
    exit 1
fi

if ! python3 -c "import requests, pandas, geopy" &> /dev/null; then
    echo "❌ Required Python packages missing. Install with:"
    echo "   pip3 install requests pandas geopy"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Start timing
START_TIME=$(date +%s)

echo "✅ Dependencies check passed"
echo ""

# Run the full pipeline
echo "🏃 Starting pipeline execution..."
python3 full_pipeline_processor.py \
    --days "$DAYS" \
    --workers "$WORKERS" \
    --output-dir "$OUTPUT_DIR" \
    --rate-limit 0.3 \
    --batch-size 200

# Calculate total time
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
HOURS=$((DURATION / 3600))
MINUTES=$(((DURATION % 3600) / 60))
SECONDS=$((DURATION % 60))

echo ""
echo "🎉 Pipeline execution completed!"
echo "=========================================================="
echo "⏱️  Total time: ${HOURS}h ${MINUTES}m ${SECONDS}s"
echo "📁 Results saved to: $OUTPUT_DIR"
echo ""
echo "📊 Generated files:"
find "$OUTPUT_DIR" -name "*.csv" -o -name "*.json" | sort | while read file; do
    SIZE=$(ls -lh "$file" | awk '{print $5}')
    BASENAME=$(basename "$file")
    echo "   $BASENAME ($SIZE)"
done
echo ""
echo "🎯 Key output files:"
echo "   📈 sweeper_time_estimates_*.csv  - Final predicted arrival times"
echo "   📋 pipeline_report_*.json        - Complete processing report"
echo "   📍 citations_geocoded_*.csv      - Processed citation data"
echo "   🗓️  schedule_cleaned_*.csv       - Cleaned schedule data"
echo ""
echo "🔗 Next steps:"
echo "   1. Review the pipeline report for data quality metrics"
echo "   2. Integrate sweeper_time_estimates_*.csv into your iOS app"
echo "   3. Set up weekly refresh using this script with --days 14"
echo ""
echo "✅ Full SF citation analysis pipeline complete!"