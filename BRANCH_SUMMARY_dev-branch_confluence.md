# Hardware Management Service - Refactoring
## Proposal: Split Monolithic Service into Specialized Components


---

## 1. Goal & Motivation

### Current Problem
The existing `hw_management_sync.py` service combines all hardware monitoring into a single monolithic daemon:
- Temperature monitoring (ASIC, optical modules)
- Peripheral monitoring (fans, leakage sensors, power button)
- BMC sensor integration
- ASIC chipup status tracking

**Issues with Current Architecture:**
- Cannot selectively disable thermal monitoring (customer requirement)


### Proposed Solution
Split into two independent, specialized services:
1. **hw_management_peripheral_updater** - Critical peripheral monitoring
2. **hw_management_thermal_updater** - Temperature monitoring (optional)

### Business Value
- **Improved Reliability:** Thermal failures don't impact critical peripherals
- **Customer Flexibility:** Thermal monitoring can be disabled independently

---

## 2. Architecture

### 2.1 Service Structure

**System Boot Flow:**
1. System Boot (multi-user.target)
2. hw-management.service (Main chassis management initialization)
3. Two child services launched in parallel:

**Service 1: hw-management-peripheral-updater**
- **Purpose:** Critical device monitoring
- **Priority:** Must always run
- **Monitors:**
  - Fans (sync_fan)
  - Leakage sensors
  - Power button events
  - BMC sensors (Redfish)
  - ASIC chipup status
- **Behavior:**
  - Change-based triggering
  - Only executes on value changes
  - Efficient resource usage

**Service 2: hw-management-thermal-updater**
- **Purpose:** Temperature monitoring
- **Priority:** Optional (customer choice)
- **Monitors:**
  - ASIC temperatures
  - Optical module temperatures
- **Behavior:**
  - Polls at configured intervals
  - 3s for ASICs, 20s for modules
- **Dependencies:**
  - Uses helper functions from peripheral_updater

### 2.2 Dependency Graph

**Data Layer:**
- `hw_management_platform_config.py` - Centralized hardware definitions
  - Provides: PLATFORM_CONFIG (single source of truth)

**Service Layer:**
- `hw_management_lib.py` - Logging utilities
- `hw_management_peripheral_updater.py` - Core Service
  - Exports: `get_asic_num()`, `update_asic_chipup_status()`
- `hw_management_thermal_updater.py` - Optional Service
  - Imports helper functions from peripheral_updater

**Key Design Principles:**
- **Centralized configuration:** Single source of truth (platform_config)
- **Independent operation:** peripheral_updater works without thermal_updater
- **One-way dependency:** thermal depends on peripheral, not vice versa

### 2.3 Platform Configuration

**New Module:** `hw_management_platform_config.py`

**Purpose:** Single source of truth for all platform hardware definitions

**Structure:**
```python
PLATFORM_CONFIG = {
    "HI162": [
        {"fn": "sync_fan", "arg": {...}, "poll": 5, "ts": 0},
        {"fn": "asic_temp_populate", "arg": {...}, "poll": 3, "ts": 0},
        {"fn": "module_temp_populate", "arg": {...}, "poll": 20, "ts": 0},
        # ... more monitoring entries
    ],
    "HI166|HI167|HI169|HI170": [...],
    # ... more platforms
}
```

**Benefits:**
- Single place to add new platforms
- Consistent data structure
- Reduced duplication
- Easy to maintain and audit

---

## 3. API Reference

### 3.1 hw_management_peripheral_updater.py

**Public Functions (exported for other services):**

```python
def get_asic_num() -> int:
    """
    Get the number of ASICs configured for this platform.
    
    Returns:
        int: Number of ASICs (default: 255 if not configured)
    
    Usage:
        Used by thermal_updater to determine ASIC count
    """

def update_asic_chipup_status(asic_chipup_completed: int) -> None:
    """
    Update ASIC chipup completion status files.
    
    Args:
        asic_chipup_completed: Number of ASICs that completed chipup
    
    Writes:
        /var/run/hw-management/config/asic_chipup_completed
        /var/run/hw-management/config/asics_init_done
    
    Note:
        This function is in peripheral_updater (not thermal_updater) for
        reliability - thermal_updater can be disabled by customers.
    """
```

**Monitoring Functions (internal):**
- `sync_fan(fan_id, val)` - Synchronize fan status
- `run_cmd(cmd_dict, val)` - Execute monitoring commands
- `run_power_button_event(arg, val)` - Handle power button events
- `redfish_get_sensor(arg, val)` - Query BMC sensors via Redfish

### 3.2 hw_management_thermal_updater.py

**Monitoring Functions:**
```python
def asic_temp_populate(arg_list: dict, arg: any) -> None:
    """
    Populate ASIC temperature data from SDK sysfs to hw-management sysfs.
    
    Args:
        arg_list: Dictionary containing ASIC configuration:
                  {"asic": {"fin": path}, "asic1": {"fin": path}, ...}
        arg: Unused (for consistency with function signature)
    
    Reads from:
        /var/run/hw-management/thermal/asicX (SDK paths)
    
    Writes to:
        /var/run/hw-management/thermal/asicX (hw-management paths)
    """

def module_temp_populate(arg_list: dict, _dummy: any) -> None:
    """
    Populate optical module temperature data.
    
    Args:
        arg_list: Dictionary containing module configuration:
                  {"module_count": N, "poll_thermal": interval}
        _dummy: Unused
    
    Reads from:
        /var/run/hw-management/thermal/mlxsw/moduleX_temp_input
    
    Writes to:
        /var/run/hw-management/thermal/moduleX_temp_{input,crit,emergency}
    """
```

### 3.3 hw_management_platform_config.py

**Public API:**
```python
PLATFORM_CONFIG: dict[str, list[dict]]
    # Dictionary mapping platform SKUs to monitoring configurations
    # Key: SKU pattern (e.g., "HI162", "HI166|HI167")
    # Value: List of monitoring entry dictionaries

def get_platform_config(product_sku: str) -> list[dict] | None:
    """Get platform configuration for a given SKU."""

def get_module_count(product_sku: str) -> int:
    """Get number of optical modules for platform."""

def get_all_platform_skus() -> list[str]:
    """Get list of all supported platform SKUs."""
```

---

## 4. Test Plan

### 4.1 Test Coverage

**New Test Suite:** `tests/offline/test_platform_config.py` (18 tests)

#### Test Class 1: Platform Configuration Structure (5 tests)
- Validate PLATFORM_CONFIG is a dictionary
- Verify expected SKUs are present (HI162, def, etc.)
- Confirm each platform entry is a list
- Validate monitoring entries have required fields (fn, arg, poll, ts)
- Check function types are present (thermal + peripheral)

#### Test Class 2: Thermal Config Filtering (5 tests)
- Verify thermal_config contains only thermal functions
- Confirm peripheral functions are excluded
- Validate 'def' key exists for defaults
- Check filtering preserves entry structure
- Verify correct entry counts after filtering

#### Test Class 3: Helper Functions (6 tests)
- Test get_platform_config() with valid SKU
- Test get_platform_config() with invalid SKU (returns None)
- Test get_module_count() with valid SKU
- Test get_module_count() with unknown SKU (returns 0)
- Test get_all_platform_skus() returns all SKUs
- Test edge cases and error conditions

#### Test Class 4: Architecture Independence (2 tests)
- Verify peripheral_updater imports without thermal_updater
- Confirm platform_config has no hw_management imports

### 4.2 Integration Tests

**Existing Test Suites (all passing):**
- ASIC temperature populate tests
- Module temperature populate tests
- Chipup status tracking tests
- Module counter reliability tests
- Thermal config validation tests

**Total Test Results:**
- **259 individual tests**
- **12/12 test suites passing**
- **100% success rate**

### 4.3 Test Execution

```bash
# Run full test suite
python3 tests/test.py --offline

# Run specific test suite
python3 tests/offline/test_platform_config.py

# Run with pytest
pytest tests/offline/test_platform_config.py -v
```

---

## 5. Deployment

### 5.1 Files to Deploy

**Critical (4 files):**
```
/usr/bin/
├── hw_management_peripheral_updater.py  [NEW]
├── hw_management_thermal_updater.py     [NEW]
├── hw_management_platform_config.py     [NEW]
└── hw_management_lib.py                 [MODIFIED]

/lib/systemd/system/
├── hw-management-peripheral-updater.service  [NEW]
└── hw-management-thermal-updater.service     [NEW]
```

### 5.2 Installation Steps

```bash
# 1. Copy Python modules
sudo cp usr/usr/bin/hw_management_*.py /usr/bin/
sudo chmod +x /usr/bin/hw_management_*_updater.py

# 2. Install systemd service files
sudo cp debian/hw-management.hw-management-*-updater.service \
    /lib/systemd/system/

# 3. Reload systemd daemon
sudo systemctl daemon-reload

# 4. Enable new services
sudo systemctl enable hw-management-peripheral-updater
sudo systemctl enable hw-management-thermal-updater

# 5. Stop old service (if migrating)
sudo systemctl stop hw-management-sync
sudo systemctl disable hw-management-sync

# 6. Start new services
sudo systemctl start hw-management-peripheral-updater
sudo systemctl start hw-management-thermal-updater

# 7. Verify services are running
systemctl status hw-management-peripheral-updater
systemctl status hw-management-thermal-updater
```

### 5.3 Service Management

```bash
# Check service status
systemctl status hw-management-peripheral-updater
systemctl status hw-management-thermal-updater

# View logs
journalctl -u hw-management-peripheral-updater -f
journalctl -u hw-management-thermal-updater -f

# Restart services
sudo systemctl restart hw-management-peripheral-updater
sudo systemctl restart hw-management-thermal-updater

# Disable thermal monitoring (customer requirement)
sudo systemctl stop hw-management-thermal-updater
sudo systemctl disable hw-management-thermal-updater
# Note: peripheral monitoring continues unaffected
```

---

## 6. Benefits & Recommendations

### 6.1 Reliability Improvements
- **Fault isolation:** Thermal failure doesn't affect critical peripherals
- **Independent restart:** Services recover independently
- **Better error handling:** Specific exceptions, targeted recovery

### 6.2 Operational Benefits
- **Customer flexibility:** Thermal monitoring can be disabled independently
- **Easier troubleshooting:** Separate logs, clear service boundaries
- **Selective updates:** Services can be updated independently

### 6.3 Development Benefits
- **Better maintainability:** Clear separation of concerns (~290 lines removed)
- **Easier testing:** Services can be tested in isolation
- **Cleaner codebase:** Removed dead code, improved documentation

---

## Appendix: Service Configuration Details

### A.1 Peripheral Updater Service

```ini
[Unit]
Description=Hw-management peripheral updater service (fans, BMC, leakage sensors)
After=hw-management.service
Requires=hw-management.service
PartOf=hw-management.service

[Service]
ExecStart=/bin/sh -c "/usr/bin/hw_management_peripheral_updater.py"
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
```

### A.2 Thermal Updater Service

```ini
[Unit]
Description=Hw-management thermal updater service for ASIC and module temperature monitoring
After=hw-management.service
Requires=hw-management.service
PartOf=hw-management.service

[Service]
ExecStart=/bin/sh -c "/usr/bin/hw_management_thermal_updater.py"
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
```

---

**Last Updated:** November 13, 2025  
**Prepared by:** Abraham Coifman  
**Branch:** dev-branch

