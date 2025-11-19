# ASIC Temperature Populate Test Suite

This directory contains comprehensive unit tests for the `asic_temp_populate` function from `hw_management_sync.py`, covering all major functionality, error conditions, and edge cases.

## Features

- **Beautiful colored output** with ASCII icons for terminal compatibility
- **Configurable test iterations** - ALL tests repeat N iterations with random parameter generation
- **Detailed comprehensive reporting** enabled by default
- **🧠 Enhanced intelligent error reporting** with smart analysis, severity classification, and actionable recommendations
- **Sensor read error cleanup** before each test iteration
- **Comprehensive test coverage** of all major scenarios (17+ test scenarios)
- **Hardware-aware testing** with actual ASIC constants (retry counts, temperature limits)
- **Standalone executable** test file
- **Advanced performance metrics and analysis**

## Reporting Features

### Detailed Comprehensive Reporting (Default)
- **Execution Statistics**: Complete breakdown of test results
- **Performance Metrics**: Timing analysis including average, slowest, and fastest tests
- **Test Categories**: Results grouped by test type (normal_operation, error_handling, etc.)
- **Test Coverage**: Statistics on ASIC configurations, temperature ranges, and error conditions tested
- **Input Parameter Analysis**: Detailed analysis of test parameters and their success rates
- **Failure Analysis**: Categorized error patterns and detailed failure information
- **Recommendations**: Intelligent suggestions for test improvements

### Basic Reporting (`--simple` flag)
- Test pass/fail counts
- Overall success rate
- Failed test details with input parameters
- Basic execution time

### Sample Detailed Report Output (Default)
```
================================================================================
[GEAR] COMPREHENSIVE TEST RESULTS REPORT [GEAR]
================================================================================

[STATS] EXECUTION STATISTICS:
  Total Tests Run:     33
  [+] Passed:          33
  [-] Failed:          0
  Success Rate:        100.0%

[PERF] PERFORMANCE METRICS:
  Average Test Time:   0.021s
  Slowest Test:        0.032s
  Fastest Test:        0.009s

[COV] TEST COVERAGE:
  ASIC Configurations: 1
  Temperature Ranges:  2
  Error Conditions:    1
  File Operations:     2

[REC] RECOMMENDATIONS:
  [+] All tests passed! Great job!

================================================================================
```

## Usage

### Basic Execution (Detailed Reporting - Default)
```bash
python3 test_asic_temp_populate.py
```

### With Custom Iterations
```bash
python3 test_asic_temp_populate.py -i 10  # Run 10 iterations per test
```

### With Verbose Output
```bash
python3 test_asic_temp_populate.py -v
```

### With Simple Basic Reporting
```bash
python3 test_asic_temp_populate.py --simple
```

### Combined Options
```bash
python3 test_asic_temp_populate.py -i 10 -v      # 10 iterations, verbose, detailed
python3 test_asic_temp_populate.py -i 5 --simple # 5 iterations, simple reporting
```

### Help
```bash
python3 test_asic_temp_populate.py --help
```

## Test Scenarios

### Core Functionality Tests
1. **Normal Condition Testing** - Tests normal operation when all temperature attribute files are present and readable
2. **Input Read Error Default Values** - Tests behavior when the main temperature input file cannot be read
3. **Input Read Error Retry Logic** - Tests the 3-retry error handling mechanism
4. **Other Attributes Read Error** - Tests behavior when threshold or cooling level files cannot be read
5. **Random ASIC Configuration** - Tests all ASICs with randomized configurations (temperature range 0-800)
6. **SDK Temperature Conversion** - Tests the `sdk_temp2degree()` function
7. **Argument Validation** - Tests that function arguments are properly validated

### Advanced Error Handling Tests
8. **Error Handling No Crash** - Tests that the function doesn't crash under various error conditions
9. **ASIC Not Ready Conditions** - Tests behavior when ASIC is not ready (SDK not started)
10. **Invalid Temperature Values** - Tests handling of invalid, non-numeric, or extreme temperature values
11. **Temperature File Write Errors** - Tests behavior when writing output files fails (permissions, disk full, etc.)

### System Integration Tests  
12. **Symbolic Link Existing Files** - Tests behavior when thermal output files already exist as symbolic links
13. **ASIC Chipup Completion Logic** - Tests chipup completion counting and asics_init_done logic
14. **ASIC Temperature Reset Functionality** - Tests the asic_temp_reset function behavior
15. **Counter and Logging Mechanisms** - Tests counter increments and logging ID mechanisms
16. **File System Permission Scenarios** - Tests various file system permission and access scenarios
    - **Note**: `/var/run/hw-management/` directory always maintains r/w access (production requirement)
    - Mixed permission errors only affect source files, ready files, and config files

## Test Configuration

- **ASIC Count**: 2 ASICs (asic and asic1 are the same asic === asic1)
- **Input Path Template**: `/sys/module/sx_core/asic0/`
- **Output Path**: `/var/run/hw-management/thermal/`
- **Temperature Range**: 0-800 for random testing

## Output Files Generated

Each ASIC generates the following output files:
- `asic{N}` - Processed temperature value
- `asic{N}_temp_norm` - Constant value
- `asic{N}_temp_crit` - Constant value  
- `asic{N}_temp_emergency` - Constant value
- `asic{N}_temp_trip_crit` - Constant value

## Error Handling

The test suite includes **enhanced intelligent error reporting** with:

### 🧠 **Smart Error Analysis**
- **Error Classification**: Automatic categorization (Temperature Processing, File System, ASIC Readiness, etc.)
- **Severity Assessment**: CRITICAL, HIGH, MEDIUM severity levels with priority recommendations
- **Root Cause Analysis**: Intelligent identification of potential causes based on error patterns

### 🔧 **Actionable Solutions**  
- **Fix Recommendations**: Specific, actionable suggestions based on error type and context
- **Hardware Constants Context**: Relevant ASIC constants (75000mC temp limits, 3-retry counts, etc.)
- **Environmental Context**: Temperature ranges, ASIC configs, and test scenarios when errors occur

### 📊 **Comprehensive Details**
- **Critical Stack Traces**: Highlights the most relevant error lines from full stack traces  
- **Input Parameters**: Complete context of parameters that caused the error
- **Performance Impact**: Execution time analysis for failed operations
- **Smart Recommendations**: Pattern-based suggestions for preventing similar errors
- **Crash Recovery**: Automatic continuation after failures with detailed logging
- **Success Rate Calculation**: Statistical analysis of test reliability

## Notes

- **Comprehensive Coverage**: Tests all major code paths, error conditions, and edge cases in `asic_temp_populate`
- **Non-Destructive Testing**: All tests use extensive mocking and don't affect the actual file system
- **Random Parameter Generation**: Each iteration uses different random parameters for thorough testing
- **Error Condition Testing**: Covers all error scenarios including file permissions, invalid data, and system failures
- **Reset Functionality**: Tests ASIC temperature reset logic and counter mechanisms
- **File System Integration**: Tests symbolic links, file permissions, and directory access scenarios
- **Logging and Counters**: Validates logging mechanisms and error counter logic
- **Sensor Cleanup**: Cleans sensor_read_error before each test iteration
- **All tests repeat N iterations**: Each test scenario runs multiple times with different parameters
- **Enterprise Grade**: Comprehensive error reporting and detailed analysis suitable for production use
