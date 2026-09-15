# Shell Script Testing

This directory contains tests for shell scripts using **ShellSpec** framework with **kcov** code coverage.

## Quick Start

### 1. Install Testing Tools

```bash
cd tests
./install-shell-test-tools.sh
```

Or for user-local installation (no sudo required):

```bash
./install-shell-test-tools.sh --user
```

### 2. Run Tests

Using the main test runner:

```bash
./test.py --shell
```

Run with coverage:

```bash
./test.py --shell --shell-coverage
```

Run shellspec directly:

```bash
cd tests/shell
shellspec
```

### 3. Run Specific Tests

```bash
cd tests/shell
shellspec spec/helpers_spec.sh
```

## Test Structure

```
tests/shell/
├── .shellspec          # ShellSpec configuration
├── README.md           # This file
└── spec/               # Test specifications
    ├── helpers_spec.sh
    ├── parse_eeprom_spec.sh
    └── ...
```

## Writing Tests

ShellSpec uses a BDD (Behavior-Driven Development) style syntax. Here's an example:

```bash
#!/bin/bash

Describe 'my-script.sh'
    Include path/to/my-script.sh
    
    Describe 'my_function()'
        It 'returns success with valid input'
            When call my_function "test"
            The status should equal 0
            The output should equal "expected output"
        End
        
        It 'handles errors gracefully'
            When call my_function ""
            The status should not equal 0
            The error should include "Error:"
        End
    End
End
```

## Testing Guidelines

1. **Test files**: Named `*_spec.sh` in the `spec/` directory
2. **Describe blocks**: Group related tests
3. **It blocks**: Individual test cases
4. **Assertions**:
   - `The status should equal 0`
   - `The output should include "text"`
   - `The error should match pattern "regex"`
   - `The variable var should equal "value"`

## Code Coverage

ShellSpec integrates with **kcov** for code coverage:

```bash
shellspec --kcov
```

Coverage reports are generated in `coverage/` directory.

### Coverage Integration in test.py

```bash
# Run shell tests with coverage
./test.py --shell --shell-coverage

# Set minimum coverage threshold
./test.py --shell --shell-coverage --shell-coverage-min 80
```

## Tools Documentation

- **ShellSpec**: https://github.com/shellspec/shellspec
- **kcov**: https://github.com/SimonKagstrom/kcov
- **ShellCheck**: https://www.shellcheck.net/

## CI/CD Integration

The shell tests are integrated into the main test suite and can be run as part of CI/CD:

```bash
# Run all tests (Python + Shell)
./test.py --offline --shell

# Run with coverage
./test.py --offline --coverage --shell --shell-coverage

# Skip certain test types
./test.py --shell --skip-ngci
```

## Examples

See `spec/helpers_spec.sh` for a starter example.

Additional examples can be found in ShellSpec documentation:
https://github.com/shellspec/shellspec/blob/master/docs/examples.md

