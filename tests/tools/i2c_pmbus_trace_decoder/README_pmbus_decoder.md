# PMBUS I2C Trace Dump Decoder

A comprehensive Python tool for decoding Linux I2C trace dumps containing PMBUS protocol transactions. This decoder supports all standard PMBUS commands defined in the PMBUS specification.

## Features

- **Complete PMBUS Command Support**: All standard PMBUS commands (0x00-0xFF) including:
  - Configuration commands (PAGE, OPERATION, VOUT_COMMAND, etc.)
  - Telemetry commands (READ_VIN, READ_VOUT, READ_TEMPERATURE, etc.)
  - Status registers (STATUS_BYTE, STATUS_WORD, STATUS_VOUT, etc.)
  - Fault limit commands
  - Manufacturer-specific commands
  - User data commands

- **Multiple Data Format Decoders**:
  - LINEAR11 format (5-bit exponent, 11-bit mantissa)
  - LINEAR16 format (configurable exponent, 16-bit mantissa)
  - Direct format
  - Unsigned/Signed integers
  - Block data
  - String data

- **Multiple Trace Format Support**:
  - `i2ctransfer` format: `w2@0x50 0x8d 0x00 r2@0x50`
  - `i2cdump` format: `00: 01 02 03 04 05 06 07 08`
  - Kernel ftrace format (modern): `i2c_write: i2c-15 #0 a=061 f=0004 l=1 [88]` / `i2c_reply: i2c-15 #1 a=061 f=0005 l=3 [f9-d2-b3]`
  - Kernel trace format (old): `addr=0x50 flags=0x0 len=2 buf=8d 00`
  - Busybox format: `0x50: 8d 00 -> 12 34`

- **Smart Decoding**:
  - Automatically tracks VOUT_MODE for proper voltage decoding
  - Decodes status register bits into human-readable flags:
    - STATUS_BYTE (0x78)
    - STATUS_WORD (0x79)
    - STATUS_VOUT (0x7A)
    - STATUS_IOUT (0x7B)
    - STATUS_INPUT (0x7C)
    - STATUS_TEMPERATURE (0x7D)
    - STATUS_CML (0x7E)
  - Handles block reads with automatic ASCII string detection
  - Provides detailed descriptions for each command

## Installation

The decoder is a standalone Python script with no external dependencies (uses only standard library).

```bash
chmod +x pmbus_decoder.py
```

## Usage

### Basic Usage

Decode a trace file:
```bash
./pmbus_decoder.py trace.log
```

Decode from stdin:
```bash
cat trace.log | ./pmbus_decoder.py -
```

### Options

List all supported PMBUS commands:
```bash
./pmbus_decoder.py --list-commands
```

Show raw trace lines alongside decoded output:
```bash
./pmbus_decoder.py --show-raw trace.log
```

Filter by I2C address:
```bash
# Filter by address (hex format)
./pmbus_decoder.py trace.log --addr 0x50

# Also supports: 50, 061 (hex without 0x prefix)
./pmbus_decoder.py trace.log --addr 61
```

Filter by I2C bus:
```bash
# Filter by bus name
./pmbus_decoder.py trace.log --bus i2c-15
```

Combined filtering:
```bash
# Show only transactions for specific address on specific bus
./pmbus_decoder.py trace.log --addr 0x61 --bus i2c-1
```

Verbose output (show unparseable lines):
```bash
./pmbus_decoder.py -v trace.log
```

### Example with Sample Trace

```bash
./pmbus_decoder.py example_pmbus_trace.txt
```

## Trace Format Examples

### i2ctransfer Format

```
w1@0x50 0x9a r1@0x50 - 0x22
w1@0x50 0x8d r2@0x50 - 0x00 0x0c
w2@0x50 0x21 0x00 0x0c
```

### Kernel Trace Format (ftrace - modern)

```
sensors-16426   [005] ..... 22100.535879: i2c_write: i2c-15 #0 a=061 f=0004 l=1 [88]
sensors-16426   [005] ..... 22100.535881: i2c_read: i2c-15 #1 a=061 f=0005 l=3
sensors-16426   [005] ..... 22100.536529: i2c_reply: i2c-15 #1 a=061 f=0005 l=3 [f9-d2-b3]
sensors-16426   [005] ..... 22100.536530: i2c_result: i2c-15 n=2 ret=2
```

### Kernel Trace Format (old)

```
i2c-1: master_xfer[0]: addr=0x50 flags=0x0 len=2 buf=8d 00
i2c-1: master_xfer[1]: addr=0x50 flags=0x1 len=2
```

### Busybox Format

```
0x50: 8d 00 -> 00 0c
0x50: 78 -> 00
```

### i2cdump Format

```
00: 00 80 1a 00 00 00 00 00 00 00 00 00 00 00 00 00
10: 00 00 00 00 00 00 00 00 00 b0 00 00 00 00 00 00
```

## Output Format

The decoder provides detailed output for each transaction:

```
[READ]  Addr: 0x61 | Bus: i2c-15 | Time: 22100.536529 | Cmd: READ_VIN (0x8a) | Data: 48.000000
        Description: Read Vin

[READ]  Addr: 0x61 | Bus: i2c-1 | Time: 22100.540600 | Cmd: READ_TEMPERATURE_1 (0x8f) | Data: 45.000000
        Description: Read Temperature 1

[WRITE] Addr: 0x61 | Bus: i2c-1 | Time: 22100.543000 | Cmd: VOUT_COMMAND (0x21) | Data: 1.000000
        Description: Vout Command

[READ]  Addr: 0x61 | Bus: i2c-15 | Time: 22100.544600 | Cmd: STATUS_BYTE (0x78) | Data: 0x20 (32)
        Description: Status Byte
        Status Flags: VOUT_OV_FAULT

[READ]  Addr: 0x61 | Bus: i2c-15 | Time: 22100.537256 | Cmd: STATUS_INPUT (0x7c) | Data: 0x88 (136)
        Description: Status Input
        Status Flags: VIN_OV_FAULT, IIN_OC_FAULT

[READ]  Addr: 0x61 | Bus: i2c-1 | Time: 22100.540600 | Cmd: STATUS_TEMPERATURE (0x7d) | Data: 0xc0 (192)
        Description: Status Temperature
        Status Flags: OT_FAULT, OT_WARNING
```

**Status Register Decoders:**
The decoder automatically decodes bit flags for all standard PMBUS status registers:

- **STATUS_BYTE (0x78)**: BUSY, OFF, VOUT_OV_FAULT, IOUT_OC_FAULT, VIN_UV_FAULT, TEMPERATURE, CML, NONE_OF_ABOVE
- **STATUS_WORD (0x79)**: Combination of high and low byte flags
- **STATUS_VOUT (0x7A)**: VOUT_OV_FAULT, VOUT_OV_WARNING, VOUT_UV_WARNING, VOUT_UV_FAULT, VOUT_MAX_WARNING, TON_MAX_FAULT, TOFF_MAX_WARNING, VOUT_TRACKING_ERROR
- **STATUS_IOUT (0x7B)**: IOUT_OC_FAULT, IOUT_OC_LV_FAULT, IOUT_OC_WARNING, IOUT_UC_FAULT, CURRENT_SHARE_FAULT, POUT_OP_FAULT, POUT_OP_WARNING, POWER_LIMIT_MODE
- **STATUS_INPUT (0x7C)**: VIN_OV_FAULT, VIN_UV_FAULT, VIN_OV_WARNING, VIN_UV_WARNING, IIN_OC_FAULT, IIN_OC_WARNING, PIN_OP_WARNING, UNIT_OFF_FOR_LOW_INPUT
- **STATUS_TEMPERATURE (0x7D)**: OT_FAULT, OT_WARNING, UT_WARNING, UT_FAULT
- **STATUS_CML (0x7E)**: INVALID_COMMAND, INVALID_DATA, PEC_FAILED, MEMORY_FAULT, PROCESSOR_FAULT, COMM_FAULT_OTHER, COMM_FAULT

```

**Output fields:**
- **Type**: READ or WRITE operation
- **Addr**: I2C device address (7-bit)
- **Bus**: I2C bus name (from kernel trace only)
- **Time**: Timestamp (from kernel trace only)
- **Cmd**: PMBUS command name and code
- **Data**: Decoded data value
- **Description**: Command description
- **Status Flags**: Decoded status bits (for status registers)

## PMBUS Data Formats

### LINEAR11 Format

Used for most telemetry readings (voltage, current, temperature, power):
- 5-bit signed exponent (bits 15:11)
- 11-bit signed mantissa (bits 10:0)
- Value = mantissa × 2^exponent

### LINEAR16 Format

Used for VOUT commands and readings:
- Exponent comes from VOUT_MODE register
- 16-bit signed mantissa
- Value = mantissa × 2^exponent

### Block Format

Used for strings and complex data:
- First byte is the byte count
- Remaining bytes are the data
- Automatically detects ASCII strings

## Supported Commands

The decoder supports 150+ standard PMBUS commands including:

| Code | Command | Description |
|------|---------|-------------|
| 0x00 | PAGE | Page selection |
| 0x01 | OPERATION | Operation mode |
| 0x03 | CLEAR_FAULTS | Clear all faults |
| 0x21 | VOUT_COMMAND | Set output voltage |
| 0x78 | STATUS_BYTE | Status byte register |
| 0x79 | STATUS_WORD | Status word register |
| 0x8A | READ_VIN | Read input voltage |
| 0x8D | READ_VOUT | Read output voltage |
| 0x8E | READ_IOUT | Read output current |
| 0x8F | READ_TEMPERATURE_1 | Read temperature 1 |
| 0x98 | READ_POUT | Read output power |
| 0x99 | READ_PIN | Read input power |
| 0x9A | PMBUS_REVISION | PMBUS revision |
| 0x9B | MFR_ID | Manufacturer ID |
| 0x9C | MFR_MODEL | Manufacturer model |
| ... | ... | ... |

Run `./pmbus_decoder.py --list-commands` for the complete list.

## Capturing I2C Traces

### Using i2ctransfer

```bash
# Read a register
i2ctransfer -y 1 w1@0x50 0x8d r2@0x50

# Write and read
i2ctransfer -y 1 w2@0x50 0x21 0x00 r2@0x50
```

### Using i2cdump

```bash
i2cdump -y 1 0x50
```

### Using Kernel ftrace (Recommended for Production Debugging)

```bash
# Enable i2c tracing
echo 1 > /sys/kernel/debug/tracing/events/i2c/enable

# Or enable specific events only
echo 1 > /sys/kernel/debug/tracing/events/i2c/i2c_write/enable
echo 1 > /sys/kernel/debug/tracing/events/i2c/i2c_read/enable
echo 1 > /sys/kernel/debug/tracing/events/i2c/i2c_reply/enable
echo 1 > /sys/kernel/debug/tracing/events/i2c/i2c_result/enable

# View the trace
cat /sys/kernel/debug/tracing/trace

# Save to file
cat /sys/kernel/debug/tracing/trace > i2c_trace.txt

# Decode the trace
./pmbus_decoder.py i2c_trace.txt

# Disable tracing when done
echo 0 > /sys/kernel/debug/tracing/events/i2c/enable

# Clear the trace buffer
echo > /sys/kernel/debug/tracing/trace
```

**Advantages of ftrace format:**
- Includes timestamps for timing analysis
- Shows bus number and CPU
- Minimal performance impact
- Can filter by specific I2C bus or address
- Automatically matches write commands with read replies

## Practical Examples

### Decode Kernel ftrace Output

```bash
# Enable tracing for specific I2C bus
echo 1 > /sys/kernel/debug/tracing/events/i2c/enable

# Run your application or wait for activity
# sensors, lm-sensors, or other PMBUS-aware applications

# Capture and decode
cat /sys/kernel/debug/tracing/trace | ./pmbus_decoder.py -

# Or save and decode later
cat /sys/kernel/debug/tracing/trace > pmbus_trace.txt
./pmbus_decoder.py pmbus_trace.txt

# Disable tracing
echo 0 > /sys/kernel/debug/tracing/events/i2c/enable
```

### Monitor Power Supply Telemetry

```bash
# Script to continuously read and decode power supply data
while true; do
    echo "=== $(date) ==="
    i2ctransfer -y 1 w1@0x50 0x8a r2@0x50  # VIN
    i2ctransfer -y 1 w1@0x50 0x8d r2@0x50  # VOUT
    i2ctransfer -y 1 w1@0x50 0x8e r2@0x50  # IOUT
    i2ctransfer -y 1 w1@0x50 0x98 r2@0x50  # POUT
    i2ctransfer -y 1 w1@0x50 0x8f r2@0x50  # TEMP
    sleep 1
done | ./pmbus_decoder.py -
```

### Debug Fault Conditions

```bash
# Read all status registers
i2ctransfer -y 1 w1@0x50 0x78 r1@0x50  # STATUS_BYTE
i2ctransfer -y 1 w1@0x50 0x79 r2@0x50  # STATUS_WORD
i2ctransfer -y 1 w1@0x50 0x7a r1@0x50  # STATUS_VOUT
i2ctransfer -y 1 w1@0x50 0x7b r1@0x50  # STATUS_IOUT
i2ctransfer -y 1 w1@0x50 0x7c r1@0x50  # STATUS_INPUT
i2ctransfer -y 1 w1@0x50 0x7d r1@0x50  # STATUS_TEMPERATURE
i2ctransfer -y 1 w1@0x50 0x7e r1@0x50  # STATUS_CML
```

### Read Device Information

```bash
# Get device identification
i2ctransfer -y 1 w1@0x50 0x9a r1@0x50   # PMBUS_REVISION
i2ctransfer -y 1 w1@0x50 0x9b r32@0x50  # MFR_ID
i2ctransfer -y 1 w1@0x50 0x9c r32@0x50  # MFR_MODEL
i2ctransfer -y 1 w1@0x50 0x9d r32@0x50  # MFR_REVISION
i2ctransfer -y 1 w1@0x50 0xa0 r32@0x50  # MFR_SERIAL
```

## Troubleshooting

### Command Not Recognized

If a command is not in the standard PMBUS specification, it will show as "UNKNOWN". This is normal for manufacturer-specific commands beyond the standard range.

### Incorrect Data Decoding

- **VOUT readings incorrect**: Ensure VOUT_MODE (0x20) is read first. The decoder tracks this automatically.
- **LINEAR11 values seem wrong**: Verify the device uses standard LINEAR11 format. Some manufacturers use custom formats.
- **Block data shows hex instead of text**: This is normal if the data is not ASCII-printable.

### Trace Not Parsing

- Ensure the trace format matches one of the supported formats
- Use `--verbose` to see which lines fail to parse
- Check that hex values are properly formatted (e.g., `0x8d` not just `8d`)

## References

- PMBUS Specification: https://pmbus.org/
- Linux I2C Tools: https://i2c.wiki.kernel.org/index.php/I2C_Tools
- SMBus Specification: http://smbus.org/

## License

MIT License

## Author

Generated for hardware management debugging purposes.

