# Strict CI Mode

The hw-mgmt test runner (`test.py`) enforces **strict CI mode** to ensure the highest quality standards.

## Strict Rules

The test runner will **FAIL** on:

1. ✗ **ANY test failure**
2. ✗ **ANY pytest warning** (via `-W error`)
3. ✗ **ANY xfail or skip test**
4. ✗ **Unregistered pytest markers**

## Why Strict Mode?

- Ensures CI only passes when all tests are genuinely clean
- Forces proper handling of warnings (not just suppression)
- Prevents accumulation of "temporarily skipped" tests
- Makes test results unambiguous: pass means pass, fail means fail

## Known Issues Tracking

Known bugs and future enhancements are tracked in **separate files** excluded from CI:

```
tests/offline/known_issues_*.py
```

These files contain:
- `@pytest.mark.xfail` - Known bugs to be fixed
- `@pytest.mark.skip` - Future enhancements to be implemented

### Example: known_issues_redfish_client.py

```python
class TestKnownBugs:
    @pytest.mark.xfail(reason="BUG: Line 532 - Wrong exception type")
    def test_bug_exception_handler(self):
        # Test that exposes the bug
        ...
```

## Workflow

### Adding a New Test

1. Write test in main test file (e.g., `test_hw_management_redfish_client.py`)
2. Test must pass cleanly (no xfail/skip/warnings)
3. Commit and push - CI will verify

### Documenting a Known Bug

1. Write test that exposes the bug
2. Add to `known_issues_*.py` with `@pytest.mark.xfail`
3. Document the bug and expected fix
4. Commit - test will NOT run in CI

### Fixing a Bug

1. Fix the bug in source code
2. Move test from `known_issues_*.py` to main test file
3. Remove `@pytest.mark.xfail` decorator
4. Verify test passes
5. Commit - test now runs in CI

## Running Tests

### CI Mode (strict)
```bash
python3 test.py --offline
# Fails on ANY issue
```

### Check Known Issues
```bash
pytest offline/known_issues_*.py -v
# See what bugs still exist
```

### Development Mode (allow warnings)
```bash
pytest offline/ -v
# Shows warnings but doesn't fail
```

## Test Statistics

**Active Tests (run in CI):** 164
- ✓ Must all pass for CI to succeed
- ✓ No warnings allowed
- ✓ No skip/xfail markers

**Known Issues (excluded from CI):** 6
- 3 xfail: Known bugs to fix
- 3 skip: Future enhancements

## Benefits

✓ **No False Positives** - CI pass means everything actually works  
✓ **Transparent** - Known issues clearly documented  
✓ **Accountable** - Can't hide failures with skip markers  
✓ **Quality Control** - Forces fixing warnings, not ignoring them  
✓ **Regression Protection** - Fixed bugs automatically tested  

## Example CI Output

```
Running: Pytest Tests (offline)
  ============================= 129 passed in 0.75s ==============================
[PASSED] Pytest Tests (offline)

TEST SUMMARY
Test Suites:
  Passed: 7/7
  Failed: 0/7

Total Individual Tests: 164

ALL TESTS PASSED!
```

## Troubleshooting

### Test with xfail fails CI
**Solution:** Move test to `known_issues_*.py`

### Warning causes CI failure
**Solution:** Fix the warning in source code, don't suppress it

### Need to skip a test temporarily
**Solution:** Don't skip - either fix it or move to `known_issues_*.py`

### CI passes but pytest shows warnings
**Solution:** Not possible - `-W error` converts warnings to failures
