#!/bin/bash
# Comprehensive Test Runner for Ghostty
# This script runs all unit tests for the Ghostty terminal emulator

set -e

echo "=========================================="
echo "Ghostty Unit Test Runner"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to run a test file
run_test() {
    local test_file=$1
    local test_name=$(basename "$test_file" .zig)

    echo -e "${BLUE}Running tests for: ${test_name}${NC}"

    if zig test "$test_file" --libc glibc 2>&1; then
        echo -e "${GREEN}✓ ${test_name} passed${NC}"
        return 0
    else
        echo -e "${RED}✗ ${test_name} failed${NC}"
        return 1
    fi
}

# Count total tests
total_tests=0
passed_tests=0
failed_tests=0

echo "Test Files (25 total):"
echo "------------------------------------------"
echo "Unit Tests (20 files):"

# Array of test files in logical order
test_files=(
    "test/src_ai_test.zig"
    "test/src_config_test.zig"
    "test/src_terminal_test.zig"
    "test/src_main_test.zig"
    "test/src_utility_test.zig"
    "test/src_terminal_extended_test.zig"
    "test/src_surface_test.zig"
    "test/src_apprt_test.zig"
    "test/src_datastruct_test.zig"
    "test/src_benchmark_test.zig"
    "test/src_font_test.zig"
    "test/src_unicode_test.zig"
    "test/src_os_simd_test.zig"
    "test/src_cli_input_test.zig"
    "test/src_crash_test.zig"
    "test/src_extra_renderer_test.zig"
    "test/src_stb_synthetic_test.zig"
    "test/src_termio_test.zig"
    "test/src_inspector_test.zig"
    "test/src_terminfo_test.zig"
    "test/integration_test.zig"
    "test/property_based_test.zig"
    "test/fuzz_test.zig"
    "test/performance_benchmark_test.zig"
)

# Run each test file
for test_file in "${test_files[@]}"; do
    if [ -f "$test_file" ]; then
        total_tests=$((total_tests + 1))
        if run_test "$test_file"; then
            passed_tests=$((passed_tests + 1))
        else
            failed_tests=$((failed_tests + 1))
        fi
        echo ""
    else
        echo -e "${YELLOW}⚠ Test file not found: ${test_file}${NC}"
        echo ""
    fi
done

echo ""
echo "Advanced Tests (5 files):"
for test_file in "${test_files[@]:20}"; do
    if [ -f "$test_file" ]; then
        total_tests=$((total_tests + 1))
        if run_test "$test_file"; then
            passed_tests=$((passed_tests + 1))
        else
            failed_tests=$((failed_tests + 1))
        fi
        echo ""
    fi
done

# Print summary
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "Total test files: ${total_tests}"
echo -e "${GREEN}Passed: ${passed_tests}${NC}"
echo -e "${RED}Failed: ${failed_tests}${NC}"
echo ""
echo "Test Categories:"
echo "  • Unit Tests: 20 files (~13,000+ lines)"
echo "  • Integration Tests: 1 file"
echo "  • Property-Based Tests: 1 file"
echo "  • Fuzz Tests: 1 file"
echo "  • Performance Tests: 1 file"
echo ""
echo "Newly Added:"
echo "  • AI Module Tests (src_ai_test.zig)"
echo "  • Inspector Module Tests (src_inspector_test.zig)"
echo "  • Terminfo Module Tests (src_terminfo_test.zig)"
echo ""

if [ $failed_tests -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Please review the output above.${NC}"
    exit 1
fi
