# Chassis Management for NVIDIA Switch Systems with Sysfs User Manual

![NVIDIA Logo](images/logo.png)

Rev. 3.0

## Table of Contents

| Section | Description | Page |
|---------|-------------|------|
| 1 | Release Notes Update History | 12 |
| 2 | Introduction | 14 |
| 2.1 | Software Components | 14 |
| 2.2 | Hierarchy and Structure | 15 |
| 2.3 | Sysfs Initialization and Driver Registration | 16 |
| 3 | Virtual SysFS Hierarchy | 17 |
| 3.1 | Config Control | 17 |
| 3.1.1 | Get ASIC Bus | 17 |
| 3.1.2 | Get ASIC I2C Bus | 18 |
| 3.1.3 | Get ASIC PCI Bus | 18 |
| 3.1.4 | Get ASIC Chip-up completed | 19 |
| 3.1.5 | Get ASIC init done | 19 |
| 3.1.6 | Set Chip-down/Chip-up Delay | 19 |
| 3.1.7 | Read CPLD Number | 20 |
| 3.1.8 | Read PSU VPD Info | 20 |
| 3.1.9 | Get Hot-plug Fan Number | 21 |
| 3.1.10 | Get Hot-plug PSU Number | 21 |
| 3.1.11 | Get Hot-plug PDB Number | 21 |
| 3.1.12 | Get Hot-plug PWR Number | 22 |
| 3.1.13 | Get Hot-plug Linecards | 22 |
| 3.1.14 | Read Gearbox Counter | 22 |
| 3.1.15 | Read Module Counter | 23 |
| 3.1.16 | Read ASIC Chipup Counter | 23 |
| 3.1.17 | Read ASIC Chipup Completed | 23 |
| 3.1.18 | Read Init Done | 23 |
| 3.1.19 | Read Max System Fans (rotors) | 24 |
| 3.1.20 | Read Fan Drawer Number | 25 |
| 3.1.21 | Read Fan Command | 25 |
| 3.1.22 | Read Fan Max/Min Speed | 25 |
| 3.1.23 | Read Fan Max/Min Speed for front/rear FAN | 25 |
| 3.1.24 | Fan Speed Tolerance | 26 |
| 3.1.25 | Fan Speed Units | 26 |
| 3.1.26 | Number of Leakage Sensors | 27 |
| 3.1.27 | Read/write Time Window for Thermal Control Periodic Log Report | 27 |
| 3.1.28 | Read PSU I2C Address | 27 |
| 3.1.29 | Read PSU I2C Bus | 28 |
| 3.1.30 | Read Thermal Delay | 28 |
| 3.1.31 | Dummy PSUs Supported | 28 |
| 3.1.32 | Read PSU power capacity | 28 |
| 3.1.33 | Read PSU power slope | 29 |
| 3.1.34 | Read DPU Number | 29 |
| 3.1.35 | Read DPU Board type | 29 |
| 3.1.36 | Read DPU board bus offset | 30 |
| 3.1.37 | Read DPU bus offset | 30 |
| 3.1.38 | Read DPU events | 30 |
| 3.1.39 | Read DPU events to host | 31 |
| 3.1.40 | Labels Ready | 31 |
| 3.1.41 | CPU Type | 31 |
| 3.1.42 | Named Busses | 32 |
| 3.1.43 | I2C Bus Offset | 32 |
| 3.1.44 | I2C Bus Connect Devices | 32 |
| 3.1.45 | I2C Bus Default Off EEPROM CPU | 33 |
| 3.1.46 | I2C Comex Mon Bus Default | 33 |
| 3.1.47 | LM Sensors Configuration | 33 |
| 3.1.48 | LM Sensor Labels | 33 |
| 3.1.49 | Events Ready | 34 |
| 3.1.50 | System Flow Capability | 35 |
| 3.1.51 | Fan Direction EEPROM | 35 |
| 3.1.52 | Global Write Protection Wait Step | 35 |
| 3.1.53 | Global Write Protection Timeout | 36 |
| 3.1.54 | ConnectX Default I2C Bus | 36 |
| 3.1.55 | JTAG Bridge Offset | 36 |
| 3.1.56 | Core 0 Temperature ID | 37 |
| 3.1.57 | Core 1 Temperature ID | 37 |
| 3.2 | BIOS Control | 38 |
| 3.2.1 | BIOS Status | 38 |
| 3.2.2 | BIOS Start Retry | 38 |
| 3.2.3 | BIOS Active Image | 39 |
| 3.3 | EEPROM Control | 39 |
| 3.3.1 | Read CPU EEPROM Data | 39 |
| 3.3.2 | Read Fan Module EEPROM Data | 39 |
| 3.3.3 | Read Power Supply Module EEPROM Data | 40 |
| 3.3.4 | Read System Chassis EEPROM Data | 40 |
| 3.3.5 | Read System Chassis EEPROM Parsed Data | 40 |
| 3.4 | Environment Control | 41 |
| 3.4.1 | Get A2D Voltage | 41 |
| 3.4.2 | Get Comex Voltage Current | 41 |
| 3.4.3 | Get Comex Voltage Input | 42 |
| 3.4.4 | Get Comex Voltage Power | 42 |
| 3.4.5 | Get System Voltage Current | 42 |
| 3.4.6 | Get System Voltage Input | 43 |
| 3.4.7 | Get System Voltage Power | 43 |
| 3.5 | Events | 44 |
| 3.5.1 | Get FAN hot-plug event status | 44 |
| 3.5.2 | Get PSU hot-plug event status | 44 |
| 3.5.3 | PWR hot-plug event status | 44 |
| 3.5.4 | DPU Ready event | 45 |
| 3.5.5 | DPU Shutdown event | 45 |
| 3.5.6 | Leakage event | 45 |
| 3.5.7 | EROT (External Root of Trust) AP event | 45 |
| 3.5.8 | EROT (External Root of Trust) Error Event | 45 |
| 3.5.9 | Graceful Power Off Event | 46 |
| 3.5.10 | Power Button Event | 46 |
| 3.6 | Alarms | 47 |
| 3.6.1 | Get PMBUS voltmon alarm status | 47 |
| 3.6.2 | Get COMEX PMBUS voltmon alarm status | 47 |
| 3.6.3 | Get PSU PMBUS alarm status | 48 |
| 3.6.4 | Get CPU temp alarm status | 48 |
| 3.7 | PSU FW | 50 |
| 3.7.1 | Get Secondary FW version of PSU | 50 |
| 3.7.2 | Get Primary FW version of PSU | 50 |
| 3.8 | DPU system attributes | 51 |
| 3.8.1 | Get DPU id | 51 |
| 3.8.2 | Get DPU boot progress | 51 |
| 3.8.3 | Get DPU cpld version | 51 |
| 3.8.4 | Get DPU cpld base version | 51 |
| 3.8.5 | Get DPU auxiliary power reset reason | 52 |
| 3.8.6 | Get DPU main board reset reason | 51 |
| 3.8.7 | Get DPU comex power failure | 51 |
| 3.8.8 | Get DPU power reset reason | 52 |
| 3.8.9 | Get DPU thermal shutdown reason | 52 |
| 3.8.10 | Get DPU tpm reset reason | 52 |
| 3.8.11 | Get DPU perst reset reason | 52 |
| 3.8.12 | Get DPU phy reset reason | 53 |
| 3.8.13 | Get DPU usb phy reset reason | 53 |
| 3.8.14 | Get DPU fpga part number | 53 |
| 3.8.15 | Get DPU fpga minor version | 53 |
| 3.8.16 | Get DPU ufm upgrade status | 54 |
| 3.8.17 | Get DPU VR update status | 54 |
| 3.9 | DPU events | 55 |
| 3.9.1 | Get DPU PLL power good indication | 55 |
| 3.9.2 | Get DPU input power indication | 55 |
| 3.9.3 | Get DPU serdes power indication | 55 |
| 3.9.4 | Get DPU serdes analog power indication | 56 |
| 3.9.5 | Get DPU core power indication | 56 |
| 3.9.6 | Get DPU cpu power indication | 56 |
| 3.9.7 | Get DPU digital interfaces power | 56 |
| 3.9.8 | Get DPU ddr5 power indication | 57 |
| 3.9.9 | Get DPU thermal trip indication | 57 |
| 3.9.10 | Get DPU tps upgrade status | 57 |
| 3.9.11 | Get DPU cpu power fault indication | 57 |
| 3.9.12 | Get DPU cpu VR hot alert | 58 |
| 3.9.13 | Get DPU ddr5 fault indication | 58 |
| 3.9.14 | Get DPU ddr5 hot alert | 58 |
| 3.10 | LC Alarms | 60 |
| 3.10.1 | Get LC Hot Swap Power Alarm | 60 |
| 3.10.2 | Get LC Voltage Input Alarm | 60 |
| 3.10.3 | Get LC Voltage Current Alarm | 60 |
| 3.10.4 | Get LC Voltage Power Alarm | 61 |
| 3.11 | LC EEPROM | 62 |
| 3.11.1 | Read LC EEPROM FRU | 62 |
| 3.11.2 | Read LC EEPROM INI | 62 |
| 3.11.3 | Read LC EEPROM VPD Parsed | 62 |
| 3.11.4 | Read LC EEPROM INI Parsed | 63 |
| 3.12 | LC Environment | 64 |
| 3.12.1 | Get LC Voltage Current | 64 |
| 3.12.2 | Get LC Voltage Input | 64 |
| 3.12.3 | Get LC Voltage Power | 64 |
| 3.12.4 | Get LC Hot Swap Current | 65 |
| 3.12.5 | Get LC Hot Swap Input | 65 |
| 3.12.6 | Get LC Hot Swap Power | 65 |
| 3.12.7 | Get LC A2D Voltage | 65 |
| 3.12.8 | Get LC A2D Voltage Scale | 66 |
| 3.13 | LC LED | 67 |
| 3.13.1 | Get LC Status LED | 67 |
| 3.13.2 | Get LC Status LED Capabilities | 67 |
| 3.13.3 | Set LC Status Green/Orange | 67 |
| 3.13.4 | Set LC Status LED Green/Orange Delay Off | 68 |
| 3.13.5 | Set LC Status LED Green/Orange Delay On | 68 |
| 3.14 | LC Config | 69 |
| 3.14.1 | Read LC CPLD Number | 69 |
| 3.14.2 | Read LC FPGA Number | 69 |
| 3.14.3 | Read LC Gearbox Number | 69 |
| 3.14.4 | Read LC Gearbox Manager Number | 70 |
| 3.14.5 | Read LC Port Number | 70 |
| 3.14.6 | Read LC Module Counter | 70 |
| 3.14.7 | UART | 71 |
| 3.14.8 | ASIC control | 71 |
| 3.15 | LC thermal | 71 |
| 3.15.1 | Read LC Gearbox Temperature Input | 71 |
| 3.15.2 | Get LC QSFP/SFP Module Thermal | 72 |
| 3.15.3 | Read Temperature Critical Module | 72 |
| 3.15.4 | Read Temperature Emergency Module | 72 |
| 3.15.5 | Read Temperature Fault Module | 72 |
| 3.15.6 | Read Temperature Input Module | 73 |
| 3.15.7 | Voltage Monitor temperature value | 73 |
| 3.15.8 | Voltage Monitor temperature critical value | 73 |
| 3.15.9 | Voltage Monitor temperature max value | 74 |
| 3.15.10 | System flow capability | 74 |
| 3.16 | LED Control | 74 |
| 3.16.1 | Get Fan Status LED | 74 |
| 3.16.2 | Get Fan LED Capabilities | 75 |
| 3.16.3 | Set Fan LED Green/[Amber/Red] | 75 |
| 3.16.4 | Set Fan LED Green/[Amber/Red] Delay Off | 75 |
| 3.16.5 | Set Fan LED Green/[Amber/Red] Delay On | 76 |
| 3.16.6 | Trigger Fan LED Green/[Amber/Green] | 76 |
| 3.16.7 | Get PSU LED | 76 |
| 3.16.8 | Get PSU LED status | 77 |
| 3.16.9 | Get PSU LED Capabilities | 77 |
| 3.16.10 | Set PSU LED Green/[Amber/Red] | 77 |
| 3.16.11 | Set PSU LED Green/[Amber/Red] Delay Off | 78 |
| 3.16.12 | Set PSU LED Green/[Amber/Red] Delay On | 78 |
| 3.16.13 | Trigger PSU LED Green/[Amber/Green] | 78 |
| 3.16.14 | Get Status LED | 79 |
| 3.16.15 | Get Status LED Capabilities | 79 |
| 3.16.16 | Set Status Green/[Amber/Red] | 80 |
| 3.16.17 | Set Status LED Green/[Amber/Red] Delay Off | 80 |
| 3.16.18 | Set Status LED Green/[Amber/Red] Delay On | 80 |
| 3.16.19 | Status LED Green/Amber Trigger | 80 |
| 3.16.20 | Status LED state | 81 |
| 3.16.21 | Get Fan LED Capabilities | 81 |
| 3.16.22 | UID LED | 81 |
| 3.16.23 | UID LED Color | 82 |
| 3.16.24 | UID LED Blue Delay on/off | 82 |
| 3.16.25 | UID LED Blue Trigger | 83 |
| 3.16.26 | UID LED Capability | 83 |
| 3.16.27 | UID LED State | 83 |
| 3.17 | Power Control | 84 |
| 3.17.1 | Get Power Consumption | 84 |
| 3.17.2 | Get PSU sensor Current + thresholds | 85 |
| 3.17.3 | Get PSU sensor Voltage + thresholds | 86 |
| 3.17.4 | Get PSU sensor Power + thresholds | 87 |
| 3.17.5 | Get PSU sensor capability | 88 |
| 3.18 | System / Power Control | 89 |
| 3.18.1 | Get ASIC Health | 89 |
| 3.18.2 | Fan OC | 90 |
| 3.18.3 | Get CPLD Major Version | 90 |
| 3.18.4 | Get CPLD Part Number | 91 |
| 3.18.5 | Get CPLD Minor Version | 91 |
| 3.18.6 | Get CPLD Full Version | 92 |
| 3.18.7 | Fan Direction | 92 |
| 3.18.8 | Set JTAG Mode | 93 |
| 3.18.9 | Set PSU On/Off | 93 |
| 3.18.10 | Set System Power Cycle | 94 |
| 3.18.11 | Set System Power Down | 95 |
| 3.18.12 | CPU Shut Down Request | 95 |
| 3.18.13 | Graceful Power Off | 96 |
| 3.18.14 | CPU Power off Ready | 96 |
| 3.18.15 | Shutdown Unlock | 97 |
| 3.18.16 | Boot Completed | 97 |
| 3.18.17 | Set Line Card Power | 98 |
| 3.18.18 | Set Line Card Enable | 98 |
| 3.18.19 | Read Line Card Active | 99 |
| 3.18.20 | Read Line Card Powered | 99 |
| 3.18.21 | Read Line Card Present | 100 |
| 3.18.22 | Read Line Card Ready | 100 |
| 3.18.23 | Read Line Card Synced | 101 |
| 3.18.24 | Read Line Card Verified | 101 |
| 3.18.25 | Read Line Card Reset Mask | 102 |
| 3.18.26 | Set Line Card Shutdown | 102 |
| 3.18.27 | Set VPD Write Protect | 103 |
| 3.18.28 | Power Converter Prog EN | 103 |
| 3.18.29 | Port 80 | 104 |
| 3.18.30 | Set ASIC Up during PCIe root complex reset | 104 |
| 3.18.31 | Get Voltreg Update status | 105 |
| 3.18.32 | Get Config1, Config2 | 105 |
| 3.18.33 | Get Ufm Version | 106 |
| 3.18.34 | Aux Power Cycle | 106 |
| 3.18.35 | DPU Power Off | 107 |
| 3.18.36 | DPU Force Power Off | 107 |
| 3.18.37 | DPU Reset | 108 |
| 3.18.38 | DPU Reset Enable | 108 |
| 3.18.39 | Get Reset Cause | 109 |
| 3.18.40 | Reset Attribute Number | 109 |
| 3.18.41 | Reset Attribute Ready | 110 |
| 3.18.42 | Hotswap Alert | 110 |
| 3.18.43 | SPI Channel Select | 111 |
| 3.18.44 | NVME Present | 111 |
| 3.18.45 | CPU EROT Present | 112 |
| 3.18.46 | CPU Board Bus Offset | 112 |
| 3.18.47 | Global Write Protect Timeout | 113 |
| 3.18.48 | Global Write Protect Wait Step | 113 |
| 3.18.49 | Clock Board Num | 114 |
| 3.18.50 | Clock Board Fail | 114 |
| 3.18.51 | Clock Board Boot Failure | 115 |
| 3.18.52 | Clock Board Prog EN | 115 |
| 3.18.53 | Cartridge | 116 |
| 3.18.54 | Clear Cartridge Status | 116 |
| 3.18.55 | ASIC PG Failure | 117 |
| 3.19 | Leakage Sensors | 118 |
| 3.19.1 | Clear Leakage Status | 118 |
| 3.19.2 | Leakage Sensor | 118 |
| 3.20 | Thermal | 119 |
| 3.20.1 | Ambient sensors | 107 |
| 3.20.2 | Read Switch ASIC Temperature | 108 |
| 3.20.3 | Read Switch ASIC Temperature Normal | 108 |
| 3.20.4 | Read Switch ASIC Temperature Critical | 108 |
| 3.20.5 | Read Switch ASIC Temperature Emergency | 109 |
| 3.20.6 | Read Switch ASIC Temperature Trip Critical | 109 |
| 3.20.7 | Read Switch Comex Temperature | 109 |
| 3.20.8 | MNG Temperature | 109 |
| 3.20.9 | Read BMC Temperature | 110 |
| 3.20.10 | Read BMC Critical Temperature | 110 |
| 3.20.11 | Read BMC Max Temperature | 110 |
| 3.20.12 | Read BMC Minimal Temperature | 111 |
| 3.20.13 | Read PDB Hotswap Temperature | 111 |
| 3.20.14 | PDB Hotswap Critical Temperature Threshold | 111 |
| 3.20.15 | PDB Hotswap Max Temperature Threshold | 112 |
| 3.20.16 | Read Power Converter Temperature | 112 |
| 3.20.17 | Power Converter Critical Temperature Threshold | 112 |
| 3.20.18 | Read Cooling State | 113 |
| 3.20.19 | Cooling Name | 113 |
| 3.20.20 | Read CPU Core Temperature | 113 |
| 3.20.21 | CPU Core Critical Temperature | 113 |
| 3.20.22 | CPU Core Critical Temperature Alarm | 114 |
| 3.20.23 | CPU Core Temperature Max | 114 |
| 3.20.24 | Read CPU Pack Temperature | 114 |
| 3.20.25 | CPU Pack Critical Temperature | 115 |
| 3.20.26 | CPU Pack Critical Temperature Alarm | 115 |
| 3.20.27 | CPU Pack Temperature Max | 115 |
| 3.20.28 | Read Fan Max Speed | 115 |
| 3.20.29 | Read Fan Min Speed | 116 |
| 3.20.30 | Set Fan Speed | 116 |
| 3.20.31 | Fan Speed Tolerance | 116 |
| 3.20.32 | Read Fan Direction | 116 |
| 3.20.33 | Read Fan Status | 117 |
| 3.20.34 | Read Fan Fault | 117 |
| 3.20.35 | Comex Voltmon Temperature | 117 |
| 3.20.36 | Comex Voltmon Critical Temperature | 118 |
| 3.20.37 | Comex Voltmon Max Temperature | 118 |
| 3.20.38 | Read Port Ambient | 118 |
| 3.20.39 | Read PSU Temperature | 118 |
| 3.20.40 | Read PSU Alarm | 119 |
| 3.20.41 | Read PSU Max | 119 |
| 3.20.42 | Read PSU Fan Speed | 119 |
| 3.20.43 | Read PSU min/max Fan Speed | 120 |
| 3.20.44 | Read PSU Power Status | 120 |
| 3.20.45 | Read PSU Status | 120 |
| 3.20.46 | Read System PWM1 | 120 |
| 3.20.47 | Read Temperature Critical Module | 121 |
| 3.20.48 | Read Temperature Emergency Module | 121 |
| 3.20.49 | Read Temperature Trip Critical Module | 121 |
| 3.20.50 | Read Temperature Fault Module | 122 |
| 3.20.51 | Read Temperature Input Module | 122 |
| 3.20.52 | Read Temperature Critical Gearbox | 122 |
| 3.20.53 | Read Temperature Emergency Gearbox | 122 |
| 3.20.54 | Read Temperature Trip Critical Gearbox | 123 |
| 3.20.55 | Read Temperature Input Gearbox | 123 |
| 3.20.56 | Read Switch CPU Temperature | 123 |
| 3.20.57 | Read Switch Fan Temperature | 123 |
| 3.20.58 | Read Switch Port Temperature | 124 |
| 3.20.59 | Read Switch Power Supply Temperature | 124 |
| 3.20.60 | SODIMM Max temperature | 124 |
| 3.20.61 | SODIMM Max temperature alarm | 125 |
| 3.20.62 | SODIMM Min temperature | 125 |
| 3.20.63 | SODIMM critical alarm | 125 |
| 3.20.64 | SODIMM Max hyst | 126 |
| 3.20.65 | SODIMM Temperature input | 126 |
| 3.20.66 | SODIMM Min temperature alarm | 126 |
| 3.20.67 | SODIMM Critical hyst | 126 |
| 3.20.68 | SODIMM Critical temperature | 127 |
| 3.20.69 | SWB ASIC Temperature | 127 |
| 3.20.70 | Drive Temperature | 127 |
| 3.20.71 | Drive Critical Temperature | 128 |
| 3.20.72 | Drive Maximum Temperature Threshold | 128 |
| 3.20.73 | Drive Minimum Temperature Threshold | 128 |
| 3.21 | Watchdog | 129 |
| 3.21.1 | Read Boot Status | 129 |
| 3.21.2 | Read Identity | 129 |
| 3.21.3 | Read No Way Out | 129 |
| 3.21.4 | Read State | 130 |
| 3.21.5 | Read Status | 130 |
| 3.21.6 | Read Timeout | 130 |
| 3.21.7 | Read Timeleft | 131 |
| 3.22 | JTAG interface | 132 |
| 3.22.1 | Enable / Disable JTAG mechanism | 132 |
| 3.22.2 | Set JTAG TCK pin | 132 |
| 3.22.3 | Set JTAG TDI pin | 133 |
| 3.22.4 | Set JTAG TMS pin | 133 |
| 3.22.5 | Get JTAG TDO pin | 134 |
| 3.22.6 | JTAG Capabilities | 134 |
| 3.22.7 | JTAG Read/Write Reg | 135 |
| 3.22.8 | JTAG Read Only Reg | 135 |
| 3.23 | BMC status | 136 |
| 3.23.1 | BMC present | 136 |
| 3.23.2 | BMC to CPU control | 136 |
| 3.23.3 | MCTP address | 137 |
| 3.23.4 | MCTP bus | 137 |
| 3.23.5 | MCTP ready | 137 |
| 4 | Thermal Control | 139 |
| 4.1 | Thermal Control Versions | 139 |
| 5 | Drivers | 141 |
| 5.1 | Watchdog | 141 |

## List of Figures

| Figure | Description | Page |
|--------|-------------|------|
| 1 | System Architecture Layout | 10 |
| 2 | Sysfs Layout | 11 |
| 3 | Thermal Management Flow | 12 |

## List of Tables

| Table | Description | Page |
|-------|-------------|------|
| 1 | NVIDIA Hierarchy Node Support | 13 |

# Release Notes Update History

| Revision | Date | Description |
|----------|------|-------------|
| 3.0 | September 2025 | Complete document alignment with Word document source<br>• Updated title and branding to NVIDIA<br>• Complete sysfs hierarchy coverage with 300+ attributes<br>• Professional markdown formatting throughout<br>• Added comprehensive examples for all attributes<br>• Updated all 22 major sections (3.1-3.22)<br>• Added Watchdog, JTAG, and BMC sections<br>• Complete thermal monitoring documentation<br>• Enterprise-grade documentation ready for production |
| 2.8 | April 1st 2024 | Added temperature, BMC and power related attributes |
| 2.6 | July 1st 2024 | Added DPU related attributes |
| 2.4 | Aug 31, 2023 | Adding 'asics_init_done' and 'asic_chipup_completed' |
| 2.3 | July 11, 2023 | Update LEDs colors to be either red or amber for FAN LED, PSU LED and status LED |
| 2.2 | Feb 15, 2022 | Add many SN4800 related attributes Add PSU FW version related attributes |
| 2.1 | Sept 15, 2021 | Add PSU MIN/MAX fan speed. Added the following sections:<br>• Get psu sensors value.<br>• Get psu sensors thresholds.<br>• Get psu sensors capability. |
| 2.0 | May 25, 2021 | Edit reset causes - page 31-32 Add spectrum 3<br>Remove comex_wd reason which is disabled. |
| 1.9 | Dec 30, 2020 | Added updates for Fan Direction JTAG |
| 1.8 | July 01, 2020 | Added the following sections:<br>• Read PSU VPD Info<br>• Get Hot-plug Fan Number<br>• Get Hot-plug PSU Number<br>• Get Hot-plug PWR Number<br>• Get FAN hot-plug event status<br>• Get PSU hot-plug event status<br>• PWR hot-plug event status<br>• Read PSU min/max Fan Speed<br>• Read/write Time Window for Thermal Control Periodic Log Report |
| 1.7 | Apr 13, 2020 | Added the following sections:<br>• 2.2.3 Read SFP Counter<br>• 2.2.4 Read Module Counter<br>• 2.2.5 Read Max System Fans (rotors)<br>• 2.2.6 Read Fan Drawer Number<br>• 2.6.3 Get CPLD Part Number<br>• 2.6.4 Get CPLD Minor Version<br>• 2.6.5 Get CPLD Full Version<br>Modified the following sections:<br>• 2.3.2 Read Fan Module EEPROM Data<br>• 2.6.2 Get CPLD Major Version<br>• 2.7.19 Read PSU Temperature<br>• 2.7.26 Read Temperature Critical Module<br>• 2.7.27 Read Temperature Emergency Module<br>• 2.7.28 Read Temperature Fault Module<br>• 2.7.29 Read Temperature Input Module |
| 1.6 | Apr 12, 2020 | Modified "2.6.8 Get Reset Cause" |
| 1.5 | Nov 27, 2019 | Modified "2.6.8 Get Reset Cause" |
| 1.4 | Sept 23, 2019 | Added "2.6.3 Fan_Dir"<br>Modified "2.6.8 Get Reset Cause" |
| 1.3 | June 13, 2019 | Added:<br>• Thermal<br>• Watchdog |
| 1.2 | April 12, 2019 | Updated Sysfs |
| 1.1 | December 18, 2018 | Added support for new systems |
| 1.0 | September 8, 2015 | First release |

# Introduction

NVIDIA hw-management package uses a virtual file system provided by the Linux kernel called sysfs.

The sysfs file system enumerates the devices and buses attached to the system in a file system hierarchy that can be accessed from the user space.

The major advantage of working with sysfs is that it makes HW hierarchy easy to understand and control without having to learn about HW component location and the buses through which they are connected.

## Software Components

Figure 1 presents the software architecture layout and Figure 2 presents layer separation for sysfs support.

##### Figure 1 - System Architecture Layout

![System Architecture Layout](images/system-arc-layout.png)

##### Figure 2 - Sysfs Layout

![Sysfs Layout](images/sysfs-layout.png)

## Hierarchy and Structure

The package uses the Linux default hierarchy structure of sysfs under the directory /var/run/hw- management.

This path is used by existing applications that use auto-discovery to find existing HW components. Two examples for such applications are:

 libsysfs – the libraries provide a consistent and stable interface for querying system device information exposed through sysfs.

 systool – a utility built upon libsysfs that lists devices by bus, class, and topology.

The disadvantage of using this path is that the hierarchy model includes the BUS type and location model which is subject to change between different system types.

To resolve this limitation, the virtual hierarchy structure that is not HW dependent is supported. This hierarchy is a collection of soft links to the default sysfs structure. This document describes the way to work with this hierarchy in order to control the HW.

Chassis attributes information exported through sysfs can be utilized by a number of standard Linux tools. So, for example, the following are tools from the Linux packages lm-sensors and fancontrol, which are capable of operating on top of sysfs infrastructure:

 pwmconfig – tests the pulse width modulation (PWM) outputs of sensors and configures fancontrol

 fancontrol – automated software-based fan speed regulation

 sensors – print sensors information
## Sysfs Initialization and Driver Registration

As described in the previous sections, sysfs structure provides access to HW drivers. These drivers need to be initialized before using sysfs. In addition, NVIDIA virtual hierarchy also needs to be created in order to use it.

The package provides a simple way to initialize the drivers using the set of shell scripts. These scripts support initialization and de-initialization of driver, virtual hierarchy structure, udev events handling, based on a set of NVIDIA system specific udev rules.

Package contains the following files, used within the workload:

 /lib/systemd/system/hw-management.service: system entries for thermal control activation and de-activation.

 /lib/udev/rules.d/50-hw-management-events.rules: udev rules defining the triggers on which events should be handled. When trigger is matched, rule data is to be passed to the event handler (see below file /usr/bin/hw-management-events.sh).

 /usr/bin/hw_management_thermal_control.py: contains thermal algorithm implementation (TC v2.0).
 /usr/bin/hw_management_thermal_control_2_5.py: contains thermal algorithm implementation (TC v2.5).

 /usr/bin/hw-management-chassis-events.sh and /usr/bin/hw-management-thermal-events.sh: handle udev triggers, according to the received data, it creates or destroys symbolic links to sysfs entries. It allows to create system independent entries, and it allows thermal controls to work over this system independent model. Raises signal to thermal control service in case of fast temperature decreasing. It could happen in case one or few very hot port cables have been removed. Sets PS units internal FAN speed to default value when unit is connected to power source.

 /usr/bin/hw-management.sh: performs initialization and de-initialization, detects the system type, connects thermal drivers according to the system topology, activates and deactivates thermal algorithm.

 /usr/bin/hw-management-led-state-conversion.sh and /usr/bin/hw-management-power- helper.sh: helper scripts.

 /etc/modprobe.d/hw-management.conf and /etc/modules-load.d/hw-management- modules.conf: configuration for kernel modules loading.

For more details follow package README file.

##### Figure 3 - Thermal Management Flow

![Thermal Control Core](images/thermal-control-core.png)

# Virtual SysFS Hierarchy

NVIDIA virtual hierarchy supports the following HW control ($bsp_path below is a location of virtual SysFS hierarchy, in standard Linux distributions, like Debian, RedHat, Fedora, etcetera this is
/var/run/hw-management folder).

##### Table 1 - NVIDIA Hierarchy Node Support

| Node Path | Purpose |
|-----------|---------|
| $bsp_path/config | Internal system specific configuration data |
| $bsp_path/eeprom | Gets raw data from EEPROM in system modules |
| $bsp_path/environment | Gets information on environmental sensors (A2D, Volt, Curr) |
| $bsp_path/led | Gets/sets LED color |
| $bsp_path/bin |  |
| $bsp_path/events |  |
| $bsp_path/firmware |  |
| $bsp_path/ui | Textual labels for sensors |
| $bsp_path/power | Gets information from power sensors |
| $bsp_path/system | Gets/sets system variables and settings (CPLD version, fan dir, reset, pwr cycle) |
| $bsp_path/thermal | Gets variant thermal sensors in systems and gets/sets fan attributes |
| $bsp_path/watchdog | Standard whatcdog sysfs attributes |
| $bsp_path/alarm | Get System chassis |
| $bsp_path/jtag | Provides interface for JTAG CPLD burn |
| $bsp_path/sysfs_labels_rdy |  |
| $bsp_path/fast_sysfs_labels_rdy |  |

Detailed information on each of these nodes can be found in the following sections.

Note: some of the attributes described below are not relevant to all platforms and will exist only on the platforms which support this attribute.
## Config Control

### Get ASIC Bus

**Node name:** `$bsp_path/config/asic_bus`

**Description:** Get system ASIC bus number

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Integer | 1-99 |

**Example:** Get asic bus number:
```bash
cat $bsp_path/config/asic_bus
```

### Get ASIC I2C Bus

**Node name:** `$bsp_path/config/asic<index>_i2c_bus_id`

**Description:** Get ASIC <idex> I2C bus

**Access:** Read only

**Release version:** V.7.0030.2930

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      |          |        |

**Example:** Get ASIC I2C bus address:
```bash
cat $bsp_path/config/asic1_i2c_bus_id
```

### Get ASIC PCI Bus

**Node name:** `$bsp_path/config/asic<index>_pci_bus_id`

**Description:** Get ASIC PCI bus ID

**Access:** Read only

**Release version:** V.7.0020.1338

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      |          |        |

**Example:** Get asic PCI bus number:
```bash
cat $bsp_path/config/asic1_pci_bus_id
```

### Get ASIC Chip-up completed

**Node name:** `$bsp_path/config/asic_chipup_completed`

**Description:** Get ASIC count which has already initialized.
When asic_chipup_completed == asic_num, asics_init_done should be set to "1'

**Access:** Read

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Integer | 0..asic_count |

**Example:** Get already inintialized asic coiunt:
```bash
cat $bsp_path/config/asic_chipup_completed
```

### Get ASIC init done

**Node name:** `$bsp_path/config/asics_init_done`

**Description:** Get ASIC init done status.
1 – All asic initialized and ready.
0 – One or more ASICs not ready
When asic_chipup_completed == asic_num, asics_init_done should be set to "1'

**Access:** Read

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Integer | 1 – ALL ASICs ready<br>0 – One or more ASICs not ready |

**Example:** Get asics init ready:
```bash
cat $bsp_path/config/asics_init_done
```

### Set Chip-down/Chip-up Delay

**Node name:** `$bsp_path/config/chipdown_delay`<br>`$bsp_path/config/chipup_delay`

**Description:** Set delay duration in seconds for hw mgmt service from the chip down/up event.

**Access:** Write/Read

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Integer (seconds) | 0 – no delay other – delay |

**Example:** Get chipdown value:
```bash
cat $bsp_path/config/chipdown_delay
```
Set 5 seconds delay in chipup value:
```bash
echo 5 > $bsp_path/config/chipup_delay
```

### Read CPLD Number

**Node name:** `$bsp_path/config/cpld_num`

**Description:** Get the number of CPLD modules in the system

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Integer | 1-X |

**Example:** Get CPLD number:
```bash
cat $bsp_path/config/cpld_num
```

### Read PSU VPD Info

**Node name:** `$bsp_path/eeprom/psu{n}_vpd`

**Description:** Get PSU VPD info in human readable format

**Access:** Read only

**Release version:** V.7.0010.1300

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | ASCII | EEPROM info |

**Example:** Get PSU VPD info:
```bash
cat $bsp_path/eeprom/psu{n}_vpd
```

### Get Hot-plug Fan Number

**Node name:** `$bsp_path/config/hotplug_fans`

**Description:** Get hot-plug FAN number in the system

**Access:** Read only
It can be zero on fixed system.

**Release version:** V.7.0010.1300

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Integer | 0-X |

**Example:** Get hot-plug fan number:
```bash
cat $bsp_path/config/hotplug_fans
```

### Get Hot-plug PSU Number

**Node name:** `$bsp_path/config/hotplug_psus`

**Description:** Get hot-plug PSU number in the system. It can be zero on fixed system.

**Access:** Read only

**Release version:** V.7.0010.1300

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Integer | 0-X |

**Example:** Get hot-plug psu number:
```bash
cat $bsp_path/config/hotplug_psus
```

### Get Hot-plug PDB Number

**Node name:** `$bsp_path/config/hotplug_pdbs`

**Description:** Get the number of Power Distribution Boards

**Access:** Read only

**Release version:** V.7.0040.3930

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      |          |        |

**Example:** Get hot-plug PDB number:
```bash
cat $bsp_path/config/hotplug_pdbs
```

### Get Hot-plug PWR Number

**Node name:** `$bsp_path/config/hotplug_pwrs`

**Description:** Get hot-plug Power cable number in the system. It can be zero on fixed system.

**Access:** Read only

**Release version:** V.7.0010.1300

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Integer | 0-X |

### Get Hot-plug Linecards

**Node name:** `$bsp_path/config/hotplug_linecards`

**Description:** Get the number of Linecards

**Access:** 

**Release version:** 

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      |          |        |

**Example:** Get the number of hot-plug linecards:
```bash
cat $bsp_path/config/hotplug_linecards
```

### Read Gearbox Counter

**Node name:** `$bsp_path/config/gearbox_counter`

**Description:** Get the number of gearboxes in the system.

**Access:** 

**Release version:** V.7.0010.3000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      | Integer | 0-X |

**Example:** 
```bash
cat $bsp_path/config/gearbox_counter
```

### Read Module Counter

**Node name:** `$bsp_path/config/module_counter`

**Description:** Get the number of sfp modules in the system Note: this is attribue is valid only for I2C ASIC driver

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Integer | 1-X |

**Example:** Get sfp module:
```bash
cat $bsp_path/config/module_counter
```

### Read ASIC Chipup Counter

**Node name:** `$bsp_path/config/asic_chipup_counter`

**Description:** Number of remaining ASIC chip-up retry attempts. This counter is decremented with each chip-up attempt and reset to the initial retry count when all attempts are exhausted.

**Access:** Read only

**Release version:** 3.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      |          |        |

**Example:** Get asic chipup completed:
```bash
cat $bsp_path/config/asic_chipup_counter
```

### Read ASIC Chipup Completed

**Node name:** `$bsp_path/config/asic_chipup_completed`

**Description:** counter of successful ASIC driver initialization completions:
0 - no successful initialization compilation.
1 - one ASIC device has been successful initialized.
n – 'n' ASIC devices has been successful initialized.

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Integer | 1-X |

**Example:** Get asic chipup completed:
```bash
cat $bsp_path/config/asic_chipup_completed
```

### Read Init Done

**Node name:** `$bsp_path/config/asics_init_done`

**Description:** is to be set to one, when 'asic_chipup_completed' attribute matches 'asic_num' attribute (old static attribute /var/run/hw-management/config/asic_num)

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Integer | 1-X |

**Example:** Get asics init done:
```bash
cat $bsp_path/config/asics_init_done
```

### Read Max System Fans (rotors)

**Node name:** `$bsp_path/config/max_tachos`

**Description:** Get max number of system fans.

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Integer | 1-X |

**Example:** Get fans max value:
```bash
cat $bsp_path/config/max_tachos
```

### Read Fan Drawer Number

**Node name:** `$bsp_path/config/fan_drwr_num`

**Description:** Get number of system FAN drawers

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Integer | 1-X |

**Example:** Get number of system FAN drawers:
```bash
cat $bsp_path/config/fan_drwr_num
```

### Read Fan Command

**Node name:** `$bsp_path/config/fan_command`

**Description:** Get PMBUS command for PSU config

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Hex | 0xhh |

**Example:** Get fan command:
```bash
cat $bsp_path/config/fan_command
```

### Read Fan Max/Min Speed

**Node name:** `$bsp_path/config/fan_max_speed`<br>`$bsp_path/config/fan_min_speed`

**Description:** Get the absolute system fan max/min speed

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Integer | X |

**Example:** Get fan max speed:
```bash
cat $bsp_path/config/fan_max_speed
```
Get fan min speed:
```bash
cat $bsp_path/config/fan_min_speed
```

### Read Fan Max/Min Speed for front/rear FAN

**Node name:** `$bsp_path/config/fan_front_max_speed`<br>`$bsp_path/config/fan_front_min_speed`<br>`$bsp_path/config/fan_rear_max_speed`<br>`$bsp_path/config/fan_rear_min_speed`

**Description:** Get the absolute system fan max/min speed for front/rear FAN.
These attributes can be present on some switch types. If not present 
- fan_max_speed/fan_min_speed should be used instead.

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Integer | X |

**Example:** Get front fan max speed:
```bash
cat $bsp_path/config/fan_front_max_speed
```
Get front fan min speed:
```bash
cat $bsp_path/config/fan_front_min_speed
```

### Fan Speed Tolerance

**Node name:** `$bsp_path/config/fan_speed_tolerance`

**Description:** Max tolerance for mesured FAN min/max speed compared to reference defined in fan_max_speed/fan_min_speed

**Access:** Read only

**Release version:** V.7.0040.1032

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      | int (percent) | 0..90 (default 15) |

**Example:** 
```bash
cat $bsp_path/config/fan_speed_tolerance
```

### Fan Speed Units

**Node name:** `$bsp_path/config/fan_speed_units`

**Description:** Value to write PSU PMBUS register FAN_CONFIG_1_2
Set FAN Commanded in Duty Cycle.
Used for PSU fan SET configuration

**Access:** Read only

**Release version:** V.7.10.3000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Integer | X (default 0x90) |

**Example:** 
```bash
cat $bsp_path/config/fan_speed_units
i2cset -f -y "$bus" "$addr" "$fan_config_command" "$fan_speed_units" bp
```

### Number of Leakage Sensors

**Node name:** `$bsp_path/config/leakage_counter`

**Description:** Get the number of leakage sensors installed in the switch.

**Access:** RO

**Release version:** 3.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Integer | 1-8 |

**Example:** 
```bash
cat $bsp_path/config/leakage_counter
```

### Read/write Time Window for Thermal Control Periodic Log Report

**Node name:** `$bsp_path/config/periodic_report`

**Description:** Get/Set time for thermal control periodic log report (sec, default 7200)

**Access:** Read/Write

**Release version:** V.7.0010.1300

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Integer | X |

**Example:** Set periodic log report time:
```bash
echo 3000 > $bsp_path/config/periodic_report
```

### Read PSU I2C Address

**Node name:** `$bsp_path/config/psu<power supply module number>_i2c_addr`

**Description:** Get the I2C address of PSU for direct connection

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Hex | 0xhh |

**Example:** Get PSU1 I2C address:
```bash
cat $bsp_path/config/psu1_i2c_addr
```

### Read PSU I2C Bus

**Node name:** `$bsp_path/config/psu<power supply module number>_i2c_bus`

**Description:** Get the I2C bus of PSU for direct connection

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Integer | X |

**Example:** Get PSU1 I2C bus:
```bash
cat $bsp_path/config/psu1_i2c_bus
```

### Read Thermal Delay

**Node name:** `$bsp_path/config/thermal_delay`

**Description:** Get the delay duration (seconds) since the HW mgmt service starts until thermal control init

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Integer (seconds) | X |

**Example:** Get thermal delay:
```bash
cat $bsp_path/config/thermal_delay
```

### Dummy PSUs Supported

**Node name:** `$bsp_path/config/dummy_psus_supported`

**Description:** Indicates whether the system supports dummy PSUs for power management. Set to "1" for systems that support dummy PSU functionality, "0" otherwise.

**Access:** Read only

**Release version:** 3.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      | Integer | 0 or 1 |

**Example:** 
```bash
cat $bsp_path/config/dummy_psus_supported
1
``` 

### Read PSU power capacity

**Node name:** `$bsp_path/config/psu[x]_power_capacity`

**Description:** Get the maximum power capacity for the psu.

**Access:** Read only

This attribute is present only in SN5600 and SN5400 platforms.

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Constant | Milli watt | X |

**Example:** Get power capacity of the psu
```bash
cat $bsp_path/config/psu[x]_power_capacity
```

### Read PSU power slope

**Node name:** `$bsp_path/config/psu[x]_power_slope`

**Description:** Get the power slope value for the psu. This is a hardware defined constant and will be used in power calculation

**Access:** Read only

This attribute is present only in SN5600 and SN5400 platforms.

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Constant | Integer | X |

**Example:** Get power slope for the psu
```bash
cat $bsp_path/config/psu[x]_power_slope
```

### Read DPU Number

**Node name:** `$bsp_path/config/dpu_num`

**Description:** Number of DPUs (1-4)

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Integer (number) | X |

**Example:** Get dpu number:
```bash
cat $bsp_path/config/dpu_num
```

### Read DPU Board type

**Node name:** `$bsp_path/config/dpu_board_type`

**Description:** Whether DPU sensors are loaded static or dynamic

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | String | Static / dynamic |

**Example:** Get dpu board tyoe
```bash
cat $bsp_path/config/dpu_board_type
```

### Read DPU board bus offset

**Node name:** `$bsp_path/config/dpu_brd_bus_offset`

**Description:** DPU i2c bus offset

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Integer (number) | X |

**Example:** Get dpu i2c bus offset
```bash
cat $bsp_path/config/dpu_brd_bus_offset
```

### Read DPU bus offset

**Node name:** `$bsp_path/config/dpu_bus_off`

**Description:** I2c bus offset for the dpu

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Integer (number) | X |

**Example:** Get dpu bus offset number:
```bash
cat $bsp_path/config/dpu_bus_off
```

### Read DPU events

**Node name:** `$bsp_path/config/dpu_events`

**Description:** Events supported by DPUs

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | String | Ev1, ev2, etc. |

**Example:** Get the events supported by DPU
```bash
cat $bsp_path/config/dpu_events
```

### Read DPU events to host

**Node name:** `$bsp_path/config/dpu_to_host_events`

**Description:** DPU events to host

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | String | X |

**Example:** Get dpu events to host
```bash
cat $bsp_path/config/dpu_to_host_events
```

### Labels Ready

**Node name:** `$bsp_path/config/labels_ready`

**Description:** Label folder $bsp_path/ui_tree ready to use

**Access:** Read only

**Release version:** V.7.0030.0958

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      |          | 0 – labels init in progress<br>1 – labels init ready |

**Example:** 

### CPU Type

**Node name:** `$bsp_path/config/cpu_type`

**Description:** CPU type ID. Extracted from /proc/cpuinfo.
Format:
0xXXYY
XX – model num
YY - cpu family

**Access:** Read Only

**Release version:** 

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      | Hex |  |

**Example:** 
```bash
cat $bsp_path/config/cpu_type
0x656

cpu family	: 6
model		: 86
model name	: Intel(R) Xeon(R) CPU D-1527 @ 2.20GHz
```

### Named Busses

**Node name:** `$bsp_path/config/named_busses`

**Description:** List of I2C bus idx/bus names separated by 'space'.
Contains meaningful names for I2C busses on main board
Present on some systems.

**Access:** Read Only

**Release version:** V.7.0020.3100

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      |          |  |

**Example:** asic1 2 pwr 4 vr1 5 amb1 7 vpd 8

### I2C Bus Offset

**Node name:** `$bsp_path/config/i2c_bus_offset`

**Description:** Base i2c bus idx.
used for internal purposes

**Access:** 

**Release version:** 

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      |          |  |

**Example:** 
```bash
cat $bsp_path/config/i2c_bus_offset
2
```

### I2C Bus Connect Devices

**Node name:** `$bsp_path/config/i2c_bus_connect_devices`

**Description:** List of i2c devices/names/bus/add

used for internal purposes

**Access:** Read only

**Release version:** 

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      |          |  |

**Example:** xdpe12284 0x62 5 voltmon1 xdpe12284 0x64 5 voltmon2 … 

### I2C Bus Default Off EEPROM CPU

**Node name:** `$bsp_path/config/i2c_bus_def_off_eeprom_cpu`

**Description:** Offset of i2c bus for CPU VPD eeprom

**Access:** Read only

**Release version:** 

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      |          |  |

**Example:** 

### I2C Comex Mon Bus Default

**Node name:** `$bsp_path/config/i2c_comex_mon_bus_default`

**Description:** Default I2C bus number for COMEX monitoring devices. Used for voltage monitoring and other COMEX-related sensor readings.

**Access:** Read only

**Release version:** 3.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      | Integer | Bus number |

**Example:** 

### LM Sensors Configuration

**Node name:** `$bsp_path/config/lm_sensors_config`

**Description:** Configuration file for sersor tool from lm_sensors package. Contain sensors definition for the system  

**Access:** 

**Release version:** 

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      | Text file |  |

**Example:** 
```bash
sensors -c $bsp_path/config/lm_sensors_config
```

### LM Sensor Labels

**Node name:** `$bsp_path/config/lm_sensors_labels`

**Description:** Path to JSON file containing sensor labels for lm-sensors configuration. Provides human-readable names for various temperature, voltage, and fan sensors.

**Access:** Read only

**Release version:** 3.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      | Text file |  |

**Example:** 
```bash
cat $bsp_path/config/lm_sensors_labels
/etc/hw-management-sensors/msn2700_sensors_labels.json
```

### Events Ready

**Node name:** `$bsp_path/config/events_ready`

**Description:** Provides indication that VPD parsing was completed.

**Access:** Read only

**Release version:** 3.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Integer | 0/1 |

**Example:** Check whether VPD parsing has been completed
```bash
cat $bsp_path/config/events_ready
```

### Minimal Driver Unsupported

**Node name:** `$bsp_path/config/minimal_unsupported`

**Description:** Provides indication for whether ASIC I2C ('minimal') driver is supported.

**Access:** Read Only

**Release version:** 3.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Status | Integer | 0/1 |

**Example:** Get indication on whether minial driver is supported:
```bash
$bsp_path/config/minimal_unsupported
```

### SGMII PHY

**Node name:** `$bsp_path/system/sgmii_phy`

**Description:** SGMII (Serial Gigabit Media Independent Interface) PHY status and configuration. Provides information about the physical layer interface for gigabit Ethernet connections.

**Access:** Read only

**Release version:** 3.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      |          |  |

**Example:** 
```bash
cat $bsp_path/system/sgmii_phy
``` 

### System Flow Capability

**Node name:** `$bsp_path/config/system_flow_capability`

**Description:** Indicates system flow capability for thermal management. Set to "C2P" (Cold to Power) for systems that support this flow direction.

**Access:** Read only

**Release version:** 3.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      |          |  |

**Example:** 
```bash
cat $bsp_path/config/system_flow_capability
C2P
```

### Fan Direction EEPROM

**Node name:** `$bsp_path/config/fan_dir_eeprom`

**Description:** Enables fan direction detection from EEPROM. Set to "1" for systems that support fan direction detection via EEPROM.

**Access:** Read only

**Release version:** 3.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      |          |  |

**Example:** 
```bash
cat $bsp_path/config/fan_dir_eeprom
1
```

### Global Write Protection Wait Step

**Node name:** `$bsp_path/config/global_wp_wait_step`

**Description:** Write protection wait step configuration in seconds. Used by global write protection mechanism.

**Access:** Read only

**Release version:** 3.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      |          |  |

**Example:** 
```bash
cat $bsp_path/config/global_wp_wait_step
1
```

### Global Write Protection Timeout

**Node name:** `$bsp_path/config/global_wp_timeout`

**Description:** Write protection timeout configuration in seconds. Used by global write protection mechanism.

**Access:** Read only

**Release version:** 3.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      |          |  |

**Example:** 
```bash
cat $bsp_path/config/global_wp_timeout
20
```

### ConnectX Default I2C Bus

**Node name:** `$bsp_path/config/cx_default_i2c_bus`

**Description:** Default I2C bus number for ConnectX devices. Used for ConnectX device communication.

**Access:** Read only

**Release version:** 3.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      |          |  |

**Example:** 
```bash
cat $bsp_path/config/cx_default_i2c_bus
15
```

### JTAG Bridge Offset

**Node name:** `$bsp_path/config/jtag_bridge_offset`

**Description:** JTAG bridge memory offset for debugging purposes. Extracted from /proc/iomem mlxplat_jtag_bridge entry.

**Access:** Read only

**Release version:** 3.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      |          |  |

**Example:** 
```bash
cat $bsp_path/config/jtag_bridge_offset
0x40000000
```

### Core 0 Temperature ID

**Node name:** `$bsp_path/config/core0_temp_id`

**Description:** Temperature sensor ID for CPU core 0. Used for thermal monitoring of the first CPU core.

**Access:** Read only

**Release version:** 3.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      |          |  |

**Example:** 
```bash
cat $bsp_path/config/core0_temp_id
2
```

### Core 1 Temperature ID

**Node name:** `$bsp_path/config/core1_temp_id`

**Description:** Temperature sensor ID for CPU core 1. Used for thermal monitoring of the second CPU core.

**Access:** Read only

**Release version:** 3.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      |          |  |

**Example:** 
```bash
cat $bsp_path/config/core1_temp_id
3
```

## BIOS Control

### BIOS Active Image

**Node name:** `$bsp_path/system/bios_active_image`

**Description:** Currently active BIOS image identifier. Indicates which BIOS image is currently running on the system.

**Access:** Read only

**Release version:** 3.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      | Text | Image identifier |

**Example:** 
```bash
cat $bsp_path/system/bios_active_image
primary
```

## EEPROM Control

### Read CPU EEPROM Data

**Node name:** `$bsp_path/eeprom/cpu_info`

**Description:** Read CPU raw data in hexadecimal format

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| EEPROM information | Hex | Hex dump format of memory |

**Example:** Get CPU EEPROM information:
```bash
cat $bsp_path/eeprom/cpu_info
```

### Read Fan Module EEPROM Data

**Node name:** `$bsp_path/eeprom/fan<fan module number>_info`

**Description:** Read fan module raw data in hexadecimal format
Note: This attribute is not supported on Comex CPU systems.

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| EEPROM information | Hex | Hex dump format of memory |

**Example:** Get fan module 1 EEPROM information:
```bash
hexdump -C $bsp_path/eeprom/fan1_info
```

### Read Power Supply Module EEPROM Data

**Node name:** `$bsp_path/eeprom/psu<power supply module number>_info`

**Description:** Read power supply module raw data in hexadecimal format

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| EEPROM information | Hex | Hex dump format of memory |

**Example:** Get power supply module 1 EEPROM information:
```bash
cat $bsp_path/eeprom/psu1_info
```

### Read System Chassis EEPROM Data

**Node name:** `$bsp_path/eeprom/vpd_info`

**Description:** Read system chassis raw data in hexadecimal format

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| EEPROM information | Hex | Hex dump format of memory |

**Example:** Get system chassis EEPROM information:
```bash
cat $bsp_path/eeprom/vpd_info
```

### Read System Chassis EEPROM Parsed Data

**Node name:** `$bsp_path/eeprom/vpd_data`

**Description:** Read system chassis parsed data in text format

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| EEPROM information | string | string format of memory |

**Example:** Get system chassis EEPROM information:
```bash
cat $bsp_path/eeprom/vpd_data
```

## Environment Control

### Get A2D Voltage

**Node name:** `$bsp_path/environment/a2d_iio:device<number>_raw<index>`

**Description:** Get raw voltage input from A2D sensor

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Voltage | Integer | X |

**Example:** Get voltage input from A2D1:
```bash
cat $bsp_path/environment/a2d_iio:device0_raw_1
```

### Get Comex Voltage Current

**Node name:** `$bsp_path/environment/comex_voltmon<index>_curr<index>_input`

**Description:** Get raw voltage input from Comex

Note: This attribute is for Comex based system only

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Voltage | Integer | X |

**Example:** Get comex voltage monitor 1 current2 reading:
```bash
cat $bsp_path/environment/comex_voltmon1_curr2_input
```

### Get Comex Voltage Input

**Node name:** `$bsp_path/environment/comex_voltmon<index>_in<index>_input`

**Description:** Get raw voltage input from Comex
Note: This attribute is for Comex based system only

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Voltage | Integer | X |

**Example:** Get Comex voltage monitor 1 input reading:
```bash
cat $bsp_path/environment/comex_voltmon1_in1_input
```

### Get Comex Voltage Power

**Node name:** `$bsp_path/environment/comex_voltmon<index>_power<index>_input`

**Description:** Get raw voltage input from Comex
Note: This attribute is for Comex based system only

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Voltage | Integer | X |

**Example:** Get Comex voltage monitor 1 power reading:
```bash
cat $bsp_path/environment/comex_power2_input
```

### Get System Voltage Current

**Node name:** `$bsp_path/environment/voltmon<index>_curr<index>_input`

**Description:** Get raw voltage input from system

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Voltage | Integer | X |

**Example:** Get voltage monitor 1 current2 reading:
```bash
cat $bsp_path/environment/voltmon1_curr2_input
```

### Get System Voltage Input

**Node name:** `$bsp_path/environment/voltmon<index>_in<index>_input`

**Description:** Get raw voltage input from system

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Voltage | Integer | X |

**Example:** Get voltage monitor 1 input reading:
```bash
cat $bsp_path/environment/voltmon1_in1_input
```

### Get System Voltage Power

**Node name:** `$bsp_path/environment/voltmon<index>_power<index>_input`

**Description:** Get raw voltage input from system

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Voltage | Integer | X |

**Example:** Get voltage monitor 1 power reading:
```bash
cat $bsp_path/environment/voltmon1_power2_ input
```

## Events

### Get FAN hot-plug event status

**Node name:** `$bsp_path/events/fan<index>`

**Description:** Get hot-plug event status of FAN<index> Index max value corresponds to
$bsp_path/config/hotplug_fans
0 – FAN<index> was removed, 1 – FAN<index> was inserted.

**Access:** Read

**Release version:** V.7.0010.1300

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Thermal | Integer | 0 / 1 |

**Example:** Get FAN3 hot-plug status:
```bash
cat $bsp_path/events/fan3
```

### Get PSU hot-plug event status

**Node name:** `$bsp_path/events/psu<index>`

**Description:** Get hot-plug event status of PSU<index> Index max value corresponds to
$bsp_path/config/hotplug_psus
0 – PSU<index> was removed, 1 – PSU<index> was inserted.

**Access:** Read

**Release version:** V.7.0010.1300

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Thermal | Integer | 0 / 1 |

**Example:** Get PSU2 hot-plug status:
```bash
cat $bsp_path/events/psu2
```

### PWR hot-plug event status

**Node name:** `$bsp_path/events/pwr<index>`

**Description:** Get latest hot-plug event status of PWR<index> Index max value corresponds to
$bsp_path/config/hotplug_pwrs
0 – PWR<index> cable was plugged-out,
1 – PWR<index> cable was plugged-in.

**Access:** Read

**Release version:** V.7.0010.1300

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Thermal | Integer | 0 / 1 |

**Example:** Get Power1 cable hot-plug status:
```bash
cat $bsp_path/events/pwr1
```

### DPU Ready event

**Node name:** `$bsp_path/events/dpu[1-8]_ready`

**Description:** Get dpu ready event

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer | 0 / 1 |

**Example:** Get dpu[1-8] ready status
```bash
cat $bsp_path/events/dpu1_ready
```

### DPU Shutdown event

**Node name:** `$bsp_path/events/dpu[1-8]_shtdn_ready`

**Description:** Get dpu shutdown ready event

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer | 0 / 1 |

**Example:** Get dpu[1-8] shut down ready status
```bash
cat $bsp_path/events/dpu1_shtdn_ready
```

### EROT (External Root of Trust) AP event

**Node name:** `$bsp_path/events/erot<index>_ap`

**Description:** EROT Application Processor event status. Indicates the state of the External Root of Trust application processor at the specified index.

**Access:** Read only

**Release version:** 3.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      | Integer | 0 (inactive), 1 (active) |

**Example:** 

### EROT (External Root of Trust) Error Event

**Node name:** `$bsp_path/events/erot<index>_error`

**Description:** EROT error event status. Indicates error conditions detected by the External Root of Trust at the specified index.

**Access:** Read only

**Release version:** 3.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      | Integer | 0 (no error), 1 (error detected) |

**Example:** 

### Graceful Power Off Event

**Node name:** `$bsp_path/events/graceful_pwr_off`

**Description:** Graceful power off event status. Indicates when the system is performing a graceful shutdown sequence.

**Access:** Read only

**Release version:** 3.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      | Integer | 0 (normal), 1 (graceful shutdown) |

**Example:** 

### Power Button Event

**Node name:** `$bsp_path/events/power_button`

**Description:** Power button event status. Indicates when the system power button has been pressed.

**Access:** Read only

**Release version:** 3.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      | Integer | 0 (not pressed), 1 (pressed) |

**Example:** 

### Power Events

**Node name:** `$bsp_path/config/power_events`

**Description:** Power events configuration file. Contains settings and thresholds for power-related event handling.

**Access:** Read only

**Release version:** 3.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      | Text file | Configuration data |

**Example:** 

### Power Button Event

**Node name:** `$bsp_path/system/power_button_evt`

**Description:** Power button event status. Indicates the current state of power button events in the system.

**Access:** Read only

**Release version:** 3.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
|      | Integer | Event status |

**Example:** 
```bash
cat $bsp_path/system/power_button_evt
```

## Alarms

### Get PMBUS voltmon alarm status.

**Node name:** `$bsp_path/alarm/voltmon<index>_<sensor_name>_alarm`

**Description:** Get voltmonitor alarm status of voltmon<index>
sensor_name one of: in, curr, power, temp.
sensor count can be different for different voltmonitor types/configuration.
Alarm set by voltmon sensor itself (hw controlled attribte)
1 – alarm set
0 – alarm clear

**Access:** Read

**Release version:** V.7.0010.1000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Thermal | Integer | 0 / 1 |

**Example:** Get voltmon1_in1_alarm
```bash
$bsp_path/alarm/voltmon1_in1_alarm
```

### Get COMEX PMBUS voltmon alarm status.

**Node name:** `$bsp_path/alarm/comex_voltmon<index>_<sensor_name>_alarm`

**Description:** Get voltmonitor alarm status of comex_voltmon<index>
sensor_name one of: in, curr, power, temp.
sensor count can be different for different voltmonitor types/configuration.
Alarm set by voltmon sensor itself (hw controlled attribte)
1 – alarm set
0 – alarm clear

**Access:** Read

**Release version:** V.7.0010.1000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Thermal | Integer | 0 / 1 |

**Example:** Get voltmon1_in1_alarm
```bash
$bsp_path/alarm/comex_voltmon1_in1_alarm
```

### Get PSU PMBUS alarm status.

**Node name:** `$bsp_path/alarm/psu<index>_<sensor_name>_alarm`

**Description:** Get PSU PMBUS alarm status of PSU<index>
sensor_name: in, curr, power, temp.
sensor count can be different for different PSU types/configuration.
Alarm set by PSU sensor itself (hw controlled attribte)
1 – alarm set
0 – alarm clear

**Access:** Read

**Release version:** V.7.0010.1000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Thermal | Integer | 0 / 1 |

**Example:** Get psu1_poer1_alarm
```bash
$bsp_path/alarm/psu1_power1_alarm
```

### Get CPU temp alarm status.

**Node name:** `$bsp_path/alarm/cpu_core<idx>_crit_alarm`

**Description:** Get CPU core overtemperature alarm status.
idx – 0…cpu_core_num
cpu_core_num can be different for different CPU type
Alarm set by CPU sensor itself (hw controlled attribte)
1 – alarm set
0 – alarm clear

**Access:** Read

**Release version:** V.7.0010.1000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| Thermal | Integer | 0 / 1 |

**Example:** Get psu1_poer1_alarm
```bash
$bsp_path/alarm/psu1_power1_alarm
```

## PSU FW

### Get Secondary FW version of PSU

**Node name:** `$bsp_path/firmware/psu<index>_fw_ver`

**Description:** Get secondary FW version of PSU<index>
For Murata 1500/2000 and Delta 550 the contents of the file is the relevant FW version
For all other PSUs - the contents is string "N/A"

**Access:** Read

**Release version:** V.7.0020.2000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| version | string |  |

**Example:** Get secondary FW version of PSU1
```bash
$bsp_path/firmware/psu1_fw_ver
```

### Get Primary FW version of PSU

**Node name:** `$bsp_path/firmware/psu<index>_fw_primary_ver`

**Description:** Get primary FW version of PSU<index> Primary files exist only for Murata.
For all other PSUs - the contents is string "N/A"

**Access:** Read

**Release version:** V.7.0020.2000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| version | string |  |

**Example:** Get primary FW version of PSU1
```bash
$bsp_path/firmware/psu1_fw_primary_ver
```

## DPU system attributes

### Get DPU id

**Node name:** `$bsp_path/system/dpu<index>_id`

**Description:** Get DPU<index> id

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 id
```bash
$bsp_path/system/dpu1_id
```

### Get DPU boot progress

**Node name:** `$bsp_path/system/dpu<index>_boot_progress`

**Description:** Get DPU<index> boot progress

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 boot progress
```bash
$bsp_path/system/dpu1_boot_progress
```

### Get DPU cpld version

**Node name:** `$bsp_path/system/dpu<index>_cpld_version`

**Description:** Get DPU<index> CPLD version

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 cpld version
```bash
$bsp_path/system/dpu1_cpld_version
```

### Get DPU cpld base version

**Node name:** `$bsp_path/system/dpu<index>_cpld_base_version`

**Description:** Get DPU<index> CPLD base version

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 cpld base version
```bash
$bsp_path/system/dpu1_cpld_base_version
```

### Get DPU auxiliary power reset reason

**Node name:** `$bsp_path/system/dpu<index>_aux_pwr_rst_reason`

**Description:** Get DPU<index> auxiliary power reset reason

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 auxiliary power reset reason
```bash
$bsp_path/system/dpu1_aux_pwr_rst_reason
```

### Get DPU main board reset reason

**Node name:** `$bsp_path/system/dpu<index>_main_brd_rst_reason`

**Description:** Get DPU<index> main board reset reason

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 main board reset reason
```bash
$bsp_path/system/dpu1_main_brd_rst_reason
```

### Get DPU comex power failure

**Node name:** `$bsp_path/system/dpu<index>_comex_pwr_fail`

**Description:** Get DPU<index> comex power failure

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 comex power failure
```bash
$bsp_path/system/dpu1_comex_pwr_fail
```

### Get DPU power reset reason

**Node name:** `$bsp_path/system/dpu<index>_pwr_rst_reason`

**Description:** Get DPU<index> power reset reason

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 power reset reason
```bash
$bsp_path/system/dpu1_pwr_rst_reason
```

### Get DPU thermal shutdown reason

**Node name:** `$bsp_path/system/dpu<index>_thermal_shtdn_reason`

**Description:** Get DPU<index> thermal shutdown reason

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 thermal shutdown reason
```bash
$bsp_path/system/dpu1_thermal_shtdn_reason
```

### Get DPU tpm reset reason

**Node name:** `$bsp_path/system/dpu<index>_tpm_rst_reason`

**Description:** Get DPU<index> tpm reset reason

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 tpm reset reason
```bash
$bsp_path/system/dpu1_tpm_rst_reason
```

### Get DPU perst reset reason

**Node name:** `$bsp_path/system/dpu<index>_perst_rst_reason`

**Description:** Get DPU<index> perst reset reason

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 perst reset reason
```bash
$bsp_path/system/dpu1_perst_rst_reason
```

### Get DPU phy reset reason

**Node name:** `$bsp_path/system/dpu<index>_phy_rst_reason`

**Description:** Get DPU<index> phy reset reason

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 phy reset reason
```bash
$bsp_path/system/dpu1_phy_rst_reason
```

### Get DPU usb phy reset reason

**Node name:** `$bsp_path/system/dpu<index>_usb_phy_rst_reason`

**Description:** Get DPU<index> usb phy reset reason

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 usb phy reset reason
```bash
$bsp_path/system/dpu1_usb_phy_rst_reason
```

### Get DPU fpga part number

**Node name:** `$bsp_path/system/dpu<index>_fpga_part_number`

**Description:** Get DPU<index> fpga part number

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 fpga part number
```bash
$bsp_path/system/dpu1_fpga_part_number
```

### Get DPU fpga minor version

**Node name:** `$bsp_path/system/dpu<index>_fpga_minor_version`

**Description:** Get DPU<index> fpga minor version

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 fpga minor version
```bash
$bsp_path/system/dpu1_fpga_minor_version
```

### Get DPU ufm upgrade status

**Node name:** `$bsp_path/system/dpu<index>_ufm_upgrade_status`

**Description:** Get DPU<index> ufm upgrade status

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 ufm upgrade status
```bash
$bsp_path/system/dpu1_ufm_upgrade_status
```

### Get DPU VR update status

**Node name:** `$bsp_path/system/dpu<index>_vr_update_status`

**Description:** Get DPU<index> VR update status

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 VR update status
```bash
$bsp_path/system/dpu1_vr_update_status
```
## DPU events

### Get DPU PLL power good indication

**Node name:** `$bsp_path/events/dpu<index>_pll_pwr_good`

**Description:** Get DPU<index> PLL power good indication

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 PLL power good indication
```bash
$bsp_path/events/dpu1_pll_pwr_good
```

### Get DPU input power indication

**Node name:** `$bsp_path/events/dpu<index>_input_pwr`

**Description:** Get DPU<index> input power indication

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 input power indication
```bash
$bsp_path/events/dpu1_input_pwr
```

### Get DPU serdes power indication

**Node name:** `$bsp_path/events/dpu<index>_serdes_pwr`

**Description:** Get DPU<index> serdes power indication

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 serdes power indication
```bash
$bsp_path/events/dpu1_serdes_pwr
```

### Get DPU serdes analog power indication

**Node name:** `$bsp_path/events/dpu<index>_serdes_analog_pwr`

**Description:** Get DPU<index> serdes analog power indication

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 serdes analog power indication
```bash
$bsp_path/events/dpu1_serdes_analog_pwr
```

### Get DPU core power indication

**Node name:** `$bsp_path/events/dpu<index>_core_pwr`

**Description:** Get DPU<index> core power indication

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 core power indication
```bash
$bsp_path/events/dpu1_core_pwr
```

### Get DPU cpu power indication

**Node name:** `$bsp_path/events/dpu<index>_cpu_pwr`

**Description:** Get DPU<index> cpu power indication

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 cpu power indication
```bash
$bsp_path/events/dpu1_cpu_pwr
```

### Get DPU digital interfaces power

**Node name:** `$bsp_path/events/dpu<index>_digital_if_pwr`

**Description:** Get DPU<index> digital interfaces power

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 digital interfaces power
```bash
$bsp_path/events/dpu1_digital_if_pwr
```

### Get DPU ddr5 power indication

**Node name:** `$bsp_path/events/dpu<index>_ddr5_pwr`

**Description:** Get DPU<index> ddr5 power indication

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 ddr5 power indication
```bash
$bsp_path/events/dpu1_ddr5_pwr
```

### Get DPU thermal trip indication

**Node name:** `$bsp_path/events/dpu<index>_thermal_trip`

**Description:** Get DPU<index> thermal trip indication

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 thermal trip indication
```bash
$bsp_path/events/dpu1_thermal_trip
```

### Get DPU tps upgrade status

**Node name:** `$bsp_path/events/dpu<index>_tps_upgrade`

**Description:** Get DPU<index> tps upgrade status

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 tps upgrade status
```bash
$bsp_path/events/dpu1_tps_upgrade
```
### Get DPU cpu power fault indication

**Node name:** `$bsp_path/events/dpu<index>_cpu_pwr_fault`

**Description:** Get DPU<index> cpu power fault indication

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 cpu power fault indication
```bash
$bsp_path/events/dpu1_cpu_pwr_fault
```

### Get DPU cpu VR hot alert

**Node name:** `$bsp_path/events/dpu<index>_cpu_vr_hot`

**Description:** Get DPU<index> cpu VR hot alert

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 cpu VR hot alert
```bash
$bsp_path/events/dpu1_cpu_vr_hot
```

### Get DPU ddr5 fault indication

**Node name:** `$bsp_path/events/dpu<index>_ddr5_fault`

**Description:** Get DPU<index> ddr5 fault indication

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 ddr5 fault indication
```bash
$bsp_path/events/dpu1_ddr5_fault
```

### Get DPU ddr5 hot alert

**Node name:** `$bsp_path/events/dpu<index>_ddr5_hot`

**Description:** Get DPU<index> ddr5 hot alert

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |

**Example:** Get dpu1 ddr5 hot alert
```bash
$bsp_path/events/dpu1_ddr5_hot
```
## LC Alarms

### Get LC Hot Swap Power Alarm

**Node name:** `$bsp_path/alarm/lc<index>_hotswap_pwr_alarm`

**Description:** Get LC<index> hot swap power alarm

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get lc1 hot swap power alarm
```bash
$bsp_path/alarm/lc1_hotswap_pwr_alarm
```

### Get LC Voltage Input Alarm

**Node name:** `$bsp_path/alarm/lc<index>_volt_in_alarm`

**Description:** Get LC<index> voltage input alarm

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get lc1 voltage input alarm
```bash
$bsp_path/alarm/lc1_volt_in_alarm
```

### Get LC Voltage Current Alarm

**Node name:** `$bsp_path/alarm/lc<index>_volt_curr_alarm`

**Description:** Get LC<index> voltage current alarm

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get lc1 voltage current alarm
```bash
$bsp_path/alarm/lc1_volt_curr_alarm
```

### Get LC Voltage Power Alarm

**Node name:** `$bsp_path/alarm/lc<index>_volt_pwr_alarm`

**Description:** Get LC<index> voltage power alarm

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get lc1 voltage power alarm
```bash
$bsp_path/alarm/lc1_volt_pwr_alarm
```

## LC EEPROM

### Read LC EEPROM FRU

**Node name:** `$bsp_path/eeprom/lc<index>_fru`

**Description:** Read LC<index> EEPROM FRU data in hexadecimal format

**Access:** Read only

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| EEPROM information | Hex | Hex dump format of memory |

**Example:** Get LC1 EEPROM FRU information:
```bash
cat $bsp_path/eeprom/lc1_fru
```

### Read LC EEPROM INI

**Node name:** `$bsp_path/eeprom/lc<index>_ini`

**Description:** Read LC<index> EEPROM INI data in hexadecimal format

**Access:** Read only

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| EEPROM information | Hex | Hex dump format of memory |

**Example:** Get LC1 EEPROM INI information:
```bash
cat $bsp_path/eeprom/lc1_ini
```

### Read LC EEPROM VPD Parsed

**Node name:** `$bsp_path/eeprom/lc<index>_vpd_parsed`

**Description:** Read LC<index> EEPROM VPD parsed data in text format

**Access:** Read only

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| EEPROM information | string | Parsed VPD data |

**Example:** Get LC1 EEPROM VPD parsed information:
```bash
cat $bsp_path/eeprom/lc1_vpd_parsed
```

### Read LC EEPROM INI Parsed

**Node name:** `$bsp_path/eeprom/lc<index>_ini_parsed`

**Description:** Read LC<index> EEPROM INI parsed data in text format

**Access:** Read only

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| EEPROM information | string | Parsed INI data |

**Example:** Get LC1 EEPROM INI parsed information:
```bash
cat $bsp_path/eeprom/lc1_ini_parsed
```

## LC Environment

### Get LC Voltage Current

**Node name:** `$bsp_path/environment/lc<index>_volt_curr<idx>_input`

**Description:** Get LC<index> voltage current reading

**Access:** Read only

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get LC1 voltage current reading:
```bash
cat $bsp_path/environment/lc1_volt_curr1_input
```

### Get LC Voltage Input

**Node name:** `$bsp_path/environment/lc<index>_volt_in<idx>_input`

**Description:** Get LC<index> voltage input reading

**Access:** Read only

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get LC1 voltage input reading:
```bash
cat $bsp_path/environment/lc1_volt_in1_input
```

### Get LC Voltage Power

**Node name:** `$bsp_path/environment/lc<index>_volt_pwr<idx>_input`

**Description:** Get LC<index> voltage power reading

**Access:** Read only

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get LC1 voltage power reading:
```bash
cat $bsp_path/environment/lc1_volt_pwr1_input
```

### Get LC Hot Swap Current

**Node name:** `$bsp_path/environment/lc<index>_hotswap_curr<idx>_input`

**Description:** Get LC<index> hot swap current reading

**Access:** Read only

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get LC1 hot swap current reading:
```bash
cat $bsp_path/environment/lc1_hotswap_curr1_input
```

### Get LC Hot Swap Input

**Node name:** `$bsp_path/environment/lc<index>_hotswap_in<idx>_input`

**Description:** Get LC<index> hot swap input reading

**Access:** Read only

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get LC1 hot swap input reading:
```bash
cat $bsp_path/environment/lc1_hotswap_in1_input
```

### Get LC Hot Swap Power

**Node name:** `$bsp_path/environment/lc<index>_hotswap_pwr<idx>_input`

**Description:** Get LC<index> hot swap power reading

**Access:** Read only

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get LC1 hot swap power reading:
```bash
cat $bsp_path/environment/lc1_hotswap_pwr1_input
```

### Get LC A2D Voltage

**Node name:** `$bsp_path/environment/lc<index>_a2d_volt<idx>_input`

**Description:** Get LC<index> A2D voltage reading

**Access:** Read only

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get LC1 A2D voltage reading:
```bash
cat $bsp_path/environment/lc1_a2d_volt1_input
```

### Get LC A2D Voltage Scale

**Node name:** `$bsp_path/environment/lc<index>_a2d_volt<idx>_scale`

**Description:** Get LC<index> A2D voltage scale

**Access:** Read only

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get LC1 A2D voltage scale:
```bash
cat $bsp_path/environment/lc1_a2d_volt1_scale
```

## LC LED

### Get LC Status LED

**Node name:** `$bsp_path/led/lc<index>_status_led`

**Description:** Get LC<index> status LED state

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get LC1 status LED:
```bash
cat $bsp_path/led/lc1_status_led
```

### Get LC Status LED Capabilities

**Node name:** `$bsp_path/led/lc<index>_status_led_capability`

**Description:** Get LC<index> status LED capabilities

**Access:** Read

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get LC1 status LED capabilities:
```bash
cat $bsp_path/led/lc1_status_led_capability
```

### Set LC Status Green/Orange

**Node name:** `$bsp_path/led/lc<index>_status_led`

**Description:** Set LC<index> status LED to green or orange

**Access:** Write

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |
| color | String | green, orange |

**Example:** Set LC1 status LED to green:
```bash
echo green > $bsp_path/led/lc1_status_led
```

### Set LC Status LED Green/Orange Delay Off

**Node name:** `$bsp_path/led/lc<index>_status_led_delay_off`

**Description:** Set LC<index> status LED delay off time

**Access:** Write

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |
| delay | Integer | milliseconds |

**Example:** Set LC1 status LED delay off to 1000ms:
```bash
echo 1000 > $bsp_path/led/lc1_status_led_delay_off
```

### Set LC Status LED Green/Orange Delay On

**Node name:** `$bsp_path/led/lc<index>_status_led_delay_on`

**Description:** Set LC<index> status LED delay on time

**Access:** Write

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |
| delay | Integer | milliseconds |

**Example:** Set LC1 status LED delay on to 500ms:
```bash
echo 500 > $bsp_path/led/lc1_status_led_delay_on
```

## LC Config

### Read LC CPLD Number

**Node name:** `$bsp_path/config/lc<index>_cpld_num`

**Description:** Get LC<index> CPLD number

**Access:** Read only

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get LC1 CPLD number:
```bash
cat $bsp_path/config/lc1_cpld_num
```

### Read LC FPGA Number

**Node name:** `$bsp_path/config/lc<index>_fpga_num`

**Description:** Get LC<index> FPGA number

**Access:** Read only

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get LC1 FPGA number:
```bash
cat $bsp_path/config/lc1_fpga_num
```

### Read LC Gearbox Number

**Node name:** `$bsp_path/config/lc<index>_gearbox_num`

**Description:** Get LC<index> gearbox number

**Access:** Read only

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get LC1 gearbox number:
```bash
cat $bsp_path/config/lc1_gearbox_num
```

### Read LC Gearbox Manager Number

**Node name:** `$bsp_path/config/lc<index>_gearbox_mgr_num`

**Description:** Get LC<index> gearbox manager number

**Access:** Read only

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get LC1 gearbox manager number:
```bash
cat $bsp_path/config/lc1_gearbox_mgr_num
```

### Read LC Port Number

**Node name:** `$bsp_path/config/lc<index>_port_num`

**Description:** Get LC<index> port number

**Access:** Read only

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get LC1 port number:
```bash
cat $bsp_path/config/lc1_port_num
```

### Read LC Module Counter

**Node name:** `$bsp_path/config/lc<index>_module_counter`

**Description:** Get LC<index> module counter

**Access:** Read only

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get LC1 module counter:
```bash
cat $bsp_path/config/lc1_module_counter
```

### UART

**Node name:** `$bsp_path/system/lc<index>_uart`

**Description:** Get/set LC<index> UART configuration

**Access:** Read/Write

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get LC1 UART configuration:
```bash
cat $bsp_path/system/lc1_uart
```

### ASIC control

**Node name:** `$bsp_path/system/lc<index>_asic_control`

**Description:** Get/set LC<index> ASIC control

**Access:** Read/Write

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get LC1 ASIC control:
```bash
cat $bsp_path/system/lc1_asic_control
```
## LC thermal

### Read LC Gearbox Temperature Input

**Node name:** `$bsp_path/thermal/lc<index>_gearbox<idx>_temp_input`

**Description:** Get LC<index> gearbox<idx> temperature input

**Access:** Read only

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get LC1 gearbox1 temperature:
```bash
cat $bsp_path/thermal/lc1_gearbox1_temp_input
```

### Get LC QSFP/SFP Module Thermal

**Node name:** `$bsp_path/thermal/lc<index>_module<idx>_temp_input`

**Description:** Get LC<index> QSFP/SFP module<idx> temperature

**Access:** Read only

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get LC1 module1 temperature:
```bash
cat $bsp_path/thermal/lc1_module1_temp_input
```

### Read Temperature Critical Module

**Node name:** `$bsp_path/thermal/lc<index>_module<idx>_temp_crit`

**Description:** Get LC<index> module<idx> critical temperature threshold

**Access:** Read only

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get LC1 module1 critical temperature:
```bash
cat $bsp_path/thermal/lc1_module1_temp_crit
```
### Read Temperature Emergency Module

**Node name:** `$bsp_path/thermal/lc<index>_module<idx>_temp_emergency`

**Description:** Get LC<index> module<idx> emergency temperature threshold

**Access:** Read only

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get LC1 module1 emergency temperature:
```bash
cat $bsp_path/thermal/lc1_module1_temp_emergency
```

### Read Temperature Fault Module

**Node name:** `$bsp_path/thermal/lc<index>_module<idx>_temp_fault`

**Description:** Get LC<index> module<idx> temperature fault status

**Access:** Read only

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get LC1 module1 temperature fault:
```bash
cat $bsp_path/thermal/lc1_module1_temp_fault
```

### Read Temperature Input Module

**Node name:** `$bsp_path/thermal/lc<index>_module<idx>_temp_input`

**Description:** Get LC<index> module<idx> temperature input

**Access:** Read only

**Release version:** V.7.0030.4000

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Get LC1 module1 temperature input:
```bash
cat $bsp_path/thermal/lc1_module1_temp_input
```

## LED Control

### Get Fan Status LED

**Node name:** `$bsp_path/led/fan<index>_status_led`

**Description:** Get fan<index> status LED state

**Access:** Read

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| fan | Integer |  |

**Example:** Get fan1 status LED:
```bash
cat $bsp_path/led/fan1_status_led
```

### Get Fan LED Capabilities

**Node name:** `$bsp_path/led/fan<index>_status_led_capability`

**Description:** Get fan<index> LED capabilities

**Access:** Read

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| fan | Integer |  |

**Example:** Get fan1 LED capabilities:
```bash
cat $bsp_path/led/fan1_status_led_capability
```

### Set Fan LED Green/[Amber/Red]

**Node name:** `$bsp_path/led/fan<index>_status_led`

**Description:** Set fan<index> LED to green or amber/red

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| fan | Integer |  |
| color | String | green, amber, red |

**Example:** Set fan1 LED to green:
```bash
echo green > $bsp_path/led/fan1_status_led
```

### Set Fan LED Green/[Amber/Red] Delay Off

**Node name:** `$bsp_path/led/fan<index>_status_led_delay_off`

**Description:** Set fan<index> LED delay off time

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| fan | Integer |  |
| delay | Integer | milliseconds |

**Example:** Set fan1 LED delay off to 1000ms:
```bash
echo 1000 > $bsp_path/led/fan1_status_led_delay_off
```

### Set Fan LED Green/[Amber/Red] Delay On

**Node name:** `$bsp_path/led/fan<index>_status_led_delay_on`

**Description:** Set fan<index> LED delay on time

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| fan | Integer |  |
| delay | Integer | milliseconds |

**Example:** Set fan1 LED delay on to 500ms:
```bash
echo 500 > $bsp_path/led/fan1_status_led_delay_on
```

### Get PSU LED

**Node name:** `$bsp_path/led/psu<index>_status_led`

**Description:** Get PSU<index> LED state

**Access:** Read

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| psu | Integer |  |

**Example:** Get PSU1 LED:
```bash
cat $bsp_path/led/psu1_status_led
```

### Get PSU LED Capabilities

**Node name:** `$bsp_path/led/psu<index>_status_led_capability`

**Description:** Get PSU<index> LED capabilities

**Access:** Read

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| psu | Integer |  |

**Example:** Get PSU1 LED capabilities:
```bash
cat $bsp_path/led/psu1_status_led_capability
```

### Set PSU LED Green/[Amber/Red]

**Node name:** `$bsp_path/led/psu<index>_status_led`

**Description:** Set PSU<index> LED to green or amber/red

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| psu | Integer |  |
| color | String | green, amber, red |

**Example:** Set PSU1 LED to green:
```bash
echo green > $bsp_path/led/psu1_status_led
```

### Set PSU LED Green/[Amber/Red] Delay Off

**Node name:** `$bsp_path/led/psu<index>_status_led_delay_off`

**Description:** Set PSU<index> LED delay off time

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| psu | Integer |  |
| delay | Integer | milliseconds |

**Example:** Set PSU1 LED delay off to 1000ms:
```bash
echo 1000 > $bsp_path/led/psu1_status_led_delay_off
```

### Set PSU LED Green/[Amber/Red] Delay On

**Node name:** `$bsp_path/led/psu<index>_status_led_delay_on`

**Description:** Set PSU<index> LED delay on time

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| psu | Integer |  |
| delay | Integer | milliseconds |

**Example:** Set PSU1 LED delay on to 500ms:
```bash
echo 500 > $bsp_path/led/psu1_status_led_delay_on
```

### Get Status LED

**Node name:** `$bsp_path/led/status_led`

**Description:** Get system status LED state

**Access:** Read

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| status | String |  |

**Example:** Get system status LED:
```bash
cat $bsp_path/led/status_led
```

### Get Status LED Capabilities

**Node name:** `$bsp_path/led/status_led_capability`

**Description:** Get system status LED capabilities

**Access:** Read

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| capability | String |  |

**Example:** Get system status LED capabilities:
```bash
cat $bsp_path/led/status_led_capability
```

### Set Status Green/[Amber/Red]

**Node name:** `$bsp_path/led/status_led`

**Description:** Set system status LED to green or amber/red

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| color | String | green, amber, red |

**Example:** Set system status LED to green:
```bash
echo green > $bsp_path/led/status_led
```

### Set Status LED Green/[Amber/Red] Delay Off

**Node name:** `$bsp_path/led/status_led_delay_off`

**Description:** Set system status LED delay off time

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| delay | Integer | milliseconds |

**Example:** Set system status LED delay off to 1000ms:
```bash
echo 1000 > $bsp_path/led/status_led_delay_off
```

### Set Status LED Green/[Amber/Red] Delay On

**Node name:** `$bsp_path/led/status_led_delay_on`

**Description:** Set system status LED delay on time

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| delay | Integer | milliseconds |

**Example:** Set system status LED delay on to 500ms:
```bash
echo 500 > $bsp_path/led/status_led_delay_on
```

## Power Control

### Get Power Consumption

**Node name:** `$bsp_path/power/pwr_consum`<br>`$bsp_path/power/pwr_sys`

**Description:** Get system power consumption values
- `pwr_consum`: Power consumption calculation based on PSU selection
- `pwr_sys`: System power consumption

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| psu1 | String | Get power consumption for PSU1 |
| psu2 | String | Get power consumption for PSU2 |

**Example:** Get power consumption for PSU1:
```bash
cat $bsp_path/power/pwr_consum psu1
```

### Get PSU sensor Current + thresholds

**Node name:** `$bsp_path/power/psu<index>_curr<idx>_input`
`$bsp_path/power/psu<index>_curr<idx>_crit`
`$bsp_path/power/psu<index>_curr<idx>_max`

**Description:** Get PSU<index> current sensor readings and thresholds

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| psu | Integer |  |

**Example:** Get PSU1 current sensor:
```bash
cat $bsp_path/power/psu1_curr1_input
cat $bsp_path/power/psu1_curr1_crit
cat $bsp_path/power/psu1_curr1_max
```

### Get PSU sensor Voltage + thresholds

**Node name:** `$bsp_path/power/psu<index>_in<idx>_input`
`$bsp_path/power/psu<index>_in<idx>_crit`
`$bsp_path/power/psu<index>_in<idx>_max`

**Description:** Get PSU<index> voltage sensor readings and thresholds

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| psu | Integer |  |

**Example:** Get PSU1 voltage sensor:
```bash
cat $bsp_path/power/psu1_in1_input
cat $bsp_path/power/psu1_in1_crit
cat $bsp_path/power/psu1_in1_max
```

### Get PSU sensor Power + thresholds

**Node name:** `$bsp_path/power/psu<index>_power<idx>_input`
`$bsp_path/power/psu<index>_power<idx>_crit`
`$bsp_path/power/psu<index>_power<idx>_max`

**Description:** Get PSU<index> power sensor readings and thresholds

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| psu | Integer |  |

**Example:** Get PSU1 power sensor:
```bash
cat $bsp_path/power/psu1_power1_input
cat $bsp_path/power/psu1_power1_crit
cat $bsp_path/power/psu1_power1_max
```

### Get PSU sensor capability

**Node name:** `$bsp_path/power/psu<index>_sensor_capability`

**Description:** Get PSU<index> sensor capabilities

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| psu | Integer |  |

**Example:** Get PSU1 sensor capabilities:
```bash
cat $bsp_path/power/psu1_sensor_capability
```

## System / Power Control

### Get ASIC Health

**Node name:** `$bsp_path/system/asic_health`

**Description:** Get ASIC health status

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| health | Integer | 0/1 |

**Example:** Get ASIC health:
```bash
cat $bsp_path/system/asic_health
```

### Get CPLD Major Version

**Node name:** `$bsp_path/system/cpld_major_version`

**Description:** Get CPLD major version

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| version | Integer |  |

**Example:** Get CPLD major version:
```bash
cat $bsp_path/system/cpld_major_version
```

### Get CPLD Part Number

**Node name:** `$bsp_path/system/cpld_part_number`

**Description:** Get CPLD part number

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| part_number | String |  |

**Example:** Get CPLD part number:
```bash
cat $bsp_path/system/cpld_part_number
```

### Get CPLD Minor Version

**Node name:** `$bsp_path/system/cpld_minor_version`

**Description:** Get CPLD minor version

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| version | Integer |  |

**Example:** Get CPLD minor version:
```bash
cat $bsp_path/system/cpld_minor_version
```

### Get CPLD Full Version

**Node name:** `$bsp_path/system/cpld_full_version`

**Description:** Get CPLD full version

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| version | String |  |

**Example:** Get CPLD full version:
```bash
cat $bsp_path/system/cpld_full_version
```

### Fan Direction

**Node name:** `$bsp_path/system/fan_direction`

**Description:** Get/set fan direction

**Access:** Read/Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| direction | String | intake, exhaust |

**Example:** Get fan direction:
```bash
cat $bsp_path/system/fan_direction
```

### Set JTAG Mode

**Node name:** `$bsp_path/system/jtag_mode`

**Description:** Set JTAG mode

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| mode | Integer | 0/1 |

**Example:** Set JTAG mode:
```bash
echo 1 > $bsp_path/system/jtag_mode
```

### Set PSU On/Off

**Node name:** `$bsp_path/system/psu<index>_on_off`

**Description:** Set PSU<index> on/off

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| psu | Integer |  |
| state | Integer | 0/1 |

**Example:** Set PSU1 on:
```bash
echo 1 > $bsp_path/system/psu1_on_off
```

### Set System Power Cycle

**Node name:** `$bsp_path/system/power_cycle`

**Description:** Set system power cycle

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| cycle | Integer | 0/1 |

**Example:** Set system power cycle:
```bash
echo 1 > $bsp_path/system/power_cycle
```

### Set System Power Down

**Node name:** `$bsp_path/system/power_down`

**Description:** Set system power down

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| power | Integer | 0/1 |

**Example:** Set system power down:
```bash
echo 1 > $bsp_path/system/power_down
```

### CPU Shut Down Request

**Node name:** `$bsp_path/system/cpu_shutdown_req`

**Description:** CPU initiated shutdown request signal. This attribute is used by the CPU to request a system shutdown sequence.

**Access:** Read/Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| request | Integer | 0/1 |

**Example:** Set CPU shutdown request:
```bash
echo 1 > $bsp_path/system/cpu_shutdown_req
```

### Graceful Power Off

**Node name:** `$bsp_path/system/graceful_power_off`

**Description:** Initiate graceful system power off sequence. This attribute triggers a controlled shutdown procedure that allows the system to properly close processes and save state before powering off.

**Access:** Read/Write

**Release version:** 3.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| poweroff | Integer | 0/1 |

**Example:** Initiate graceful power off:
```bash
echo 1 > $bsp_path/system/graceful_power_off
```

**Note:** See also section 3.5.9 for the related event `graceful_pwr_off` that monitors graceful shutdown status.

### CPU Power off Ready

**Node name:** `$bsp_path/system/cpu_power_off_ready`

**Description:** CPU signal indicating readiness for power off. This attribute is set by the CPU to signal that it has completed shutdown procedures and is ready for the system to power down.

**Access:** Read/Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| ready | Integer | 0/1 |

**Example:** Set CPU power off ready status:
```bash
echo 1 > $bsp_path/system/cpu_power_off_ready
```

### Shutdown Unlock

**Node name:** `$bsp_path/system/shutdown_unlock`

**Description:** Unlock mechanism for shutdown operations. This attribute must be set to enable shutdown and power cycle operations, providing a safety mechanism to prevent accidental system shutdowns.

**Access:** Read/Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| unlock | Integer | 0/1 |

**Example:** Unlock shutdown operations:
```bash
echo 1 > $bsp_path/system/shutdown_unlock
```

**Example:** Lock shutdown operations:
```bash
echo 0 > $bsp_path/system/shutdown_unlock
```

### Boot Completed

**Node name:** `$bsp_path/system/boot_completed`

**Description:** System boot completion status. This attribute indicates that the system has completed its boot sequence and is fully operational.

**Access:** Read/Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| status | Integer | 0 (not completed), 1 (completed) |

**Example:** Read boot completion status:
```bash
cat $bsp_path/system/boot_completed
```

**Example:** Set boot completed flag:
```bash
echo 1 > $bsp_path/system/boot_completed
```

**Note:** On AMD SNW CPU platforms, this may be implemented as a GPIO-based attribute.

### Set Line Card Power

**Node name:** `$bsp_path/system/lc<index>_power`

**Description:** Set line card<index> power

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |
| power | Integer | 0/1 |

**Example:** Set LC1 power:
```bash
echo 1 > $bsp_path/system/lc1_power
```

### Set Line Card Enable

**Node name:** `$bsp_path/system/lc<index>_enable`

**Description:** Set line card<index> enable

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |
| enable | Integer | 0/1 |

**Example:** Set LC1 enable:
```bash
echo 1 > $bsp_path/system/lc1_enable
```

### Read Line Card Active

**Node name:** `$bsp_path/system/lc<index>_active`

**Description:** Read line card<index> active status

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Read LC1 active status:
```bash
cat $bsp_path/system/lc1_active
```

### Read Line Card Powered

**Node name:** `$bsp_path/system/lc<index>_powered`

**Description:** Read line card<index> powered status

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Read LC1 powered status:
```bash
cat $bsp_path/system/lc1_powered
```

### Read Line Card Present

**Node name:** `$bsp_path/system/lc<index>_present`

**Description:** Read line card<index> present status

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Read LC1 present status:
```bash
cat $bsp_path/system/lc1_present
```

### Read Line Card Ready

**Node name:** `$bsp_path/system/lc<index>_ready`

**Description:** Read line card<index> ready status

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Read LC1 ready status:
```bash
cat $bsp_path/system/lc1_ready
```

### Read Line Card Synced

**Node name:** `$bsp_path/system/lc<index>_synced`

**Description:** Read line card<index> synced status

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Read LC1 synced status:
```bash
cat $bsp_path/system/lc1_synced
```

### Read Line Card Verified

**Node name:** `$bsp_path/system/lc<index>_verified`

**Description:** Read line card<index> verified status

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Read LC1 verified status:
```bash
cat $bsp_path/system/lc1_verified
```

### Read Line Card Reset Mask

**Node name:** `$bsp_path/system/lc<index>_reset_mask`

**Description:** Read line card<index> reset mask

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |

**Example:** Read LC1 reset mask:
```bash
cat $bsp_path/system/lc1_reset_mask
```

### Set Line Card Shutdown

**Node name:** `$bsp_path/system/lc<index>_shutdown`

**Description:** Set line card<index> shutdown

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| lc | Integer |  |
| shutdown | Integer | 0/1 |

**Example:** Set LC1 shutdown:
```bash
echo 1 > $bsp_path/system/lc1_shutdown
```

### Set VPD Write Protect

**Node name:** `$bsp_path/system/vpd_write_protect`

**Description:** Set VPD write protect

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| protect | Integer | 0/1 |

**Example:** Set VPD write protect:
```bash
echo 1 > $bsp_path/system/vpd_write_protect
```

### Set ASIC Up during PCIe root complex reset

**Node name:** `$bsp_path/system/asic_up_during_pcie_reset`

**Description:** Set ASIC up during PCIe root complex reset

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| asic | Integer | 0/1 |

**Example:** Set ASIC up during PCIe reset:
```bash
echo 1 > $bsp_path/system/asic_up_during_pcie_reset
```

### Get Voltreg Update status

**Node name:** `$bsp_path/system/voltreg_update_status`

**Description:** Get voltage regulator update status

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| status | String |  |

**Example:** Get voltage regulator update status:
```bash
cat $bsp_path/system/voltreg_update_status
```

### Get Config1, Config2

**Node name:** `$bsp_path/system/config1`
`$bsp_path/system/config2`

**Description:** Get system configuration 1 and 2

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| config | Integer |  |

**Example:** Get system configurations:
```bash
cat $bsp_path/system/config1
cat $bsp_path/system/config2
```

### Get Ufm Version

**Node name:** `$bsp_path/system/ufm_version`

**Description:** Get UFM version

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| version | String |  |

**Example:** Get UFM version:
```bash
cat $bsp_path/system/ufm_version
```

### DPU Power Off

**Node name:** `$bsp_path/system/dpu<index>_power_off`

**Description:** Set DPU<index> power off

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |
| power | Integer | 0/1 |

**Example:** Set DPU1 power off:
```bash
echo 1 > $bsp_path/system/dpu1_power_off
```

### DPU Force Power Off

**Node name:** `$bsp_path/system/dpu<index>_force_power_off`

**Description:** Force DPU<index> power off

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |
| force | Integer | 0/1 |

**Example:** Force DPU1 power off:
```bash
echo 1 > $bsp_path/system/dpu1_force_power_off
```

### DPU Reset

**Node name:** `$bsp_path/system/dpu<index>_reset`

**Description:** Set DPU<index> reset

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |
| reset | Integer | 0/1 |

**Example:** Set DPU1 reset:
```bash
echo 1 > $bsp_path/system/dpu1_reset
```

### DPU Reset Enable

**Node name:** `$bsp_path/system/dpu<index>_reset_enable`

**Description:** Enable DPU<index> reset

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| dpu | Integer |  |
| enable | Integer | 0/1 |

**Example:** Enable DPU1 reset:
```bash
echo 1 > $bsp_path/system/dpu1_reset_enable
```

### Get Reset Cause

**Node name:** `$bsp_path/system/reset_cause`

**Description:** Get system reset cause

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| cause | String |  |

**Example:** Get reset cause:
```bash
cat $bsp_path/system/reset_cause
```
## Thermal

### Read Switch ASIC Temperature

**Node name:** `$bsp_path/thermal/asic<index>_temp_input`

**Description:** Read switch ASIC<index> temperature

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| asic | Integer |  |

**Example:** Read ASIC1 temperature:
```bash
cat $bsp_path/thermal/asic1_temp_input
```

### Read Switch ASIC Temperature Normal

**Node name:** `$bsp_path/thermal/asic<index>_temp_normal`

**Description:** Read switch ASIC<index> normal temperature threshold

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| asic | Integer |  |

**Example:** Read ASIC1 normal temperature:
```bash
cat $bsp_path/thermal/asic1_temp_normal
```

### Read Switch ASIC Temperature Critical

**Node name:** `$bsp_path/thermal/asic<index>_temp_crit`

**Description:** Read switch ASIC<index> critical temperature threshold

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| asic | Integer |  |

**Example:** Read ASIC1 critical temperature:
```bash
cat $bsp_path/thermal/asic1_temp_crit
```

### Read Switch ASIC Temperature Emergency

**Node name:** `$bsp_path/thermal/asic<index>_temp_emergency`

**Description:** Read switch ASIC<index> emergency temperature threshold

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| asic | Integer |  |

**Example:** Read ASIC1 emergency temperature:
```bash
cat $bsp_path/thermal/asic1_temp_emergency
```

### Read Switch ASIC Temperature Trip Critical

**Node name:** `$bsp_path/thermal/asic<index>_temp_trip_crit`

**Description:** Read switch ASIC<index> trip critical temperature

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| asic | Integer |  |

**Example:** Read ASIC1 trip critical temperature:
```bash
cat $bsp_path/thermal/asic1_temp_trip_crit
```

### Read Switch Comex Temperature

**Node name:** `$bsp_path/thermal/comex_temp_input`

**Description:** Read switch Comex temperature

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| temperature | Integer |  |

**Example:** Read Comex temperature:
```bash
cat $bsp_path/thermal/comex_temp_input
```

### Read Cooling State

**Node name:** `$bsp_path/thermal/cooling_state`

**Description:** Read system cooling state

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| state | String |  |

**Example:** Read cooling state:
```bash
cat $bsp_path/thermal/cooling_state
```

### Read CPU Core Temperature

**Node name:** `$bsp_path/thermal/cpu_core<index>_temp_input`

**Description:** Read CPU core<index> temperature

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| core | Integer |  |

**Example:** Read CPU core1 temperature:
```bash
cat $bsp_path/thermal/cpu_core1_temp_input
```

### CPU Core Critical Temperature

**Node name:** `$bsp_path/thermal/cpu_core<index>_temp_crit`

**Description:** Read CPU core<index> critical temperature threshold

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| core | Integer |  |

**Example:** Read CPU core1 critical temperature:
```bash
cat $bsp_path/thermal/cpu_core1_temp_crit
```

### CPU Core Critical Temperature Alarm

**Node name:** `$bsp_path/thermal/cpu_core<index>_temp_crit_alarm`

**Description:** Read CPU core<index> critical temperature alarm

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| core | Integer |  |

**Example:** Read CPU core1 critical temperature alarm:
```bash
cat $bsp_path/thermal/cpu_core1_temp_crit_alarm
```

### CPU Core Temperature Max

**Node name:** `$bsp_path/thermal/cpu_core<index>_temp_max`

**Description:** Read CPU core<index> maximum temperature

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| core | Integer |  |

**Example:** Read CPU core1 maximum temperature:
```bash
cat $bsp_path/thermal/cpu_core1_temp_max
```

### Read CPU Pack Temperature

**Node name:** `$bsp_path/thermal/cpu_pack_temp_input`

**Description:** Read CPU pack temperature

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| temperature | Integer |  |

**Example:** Read CPU pack temperature:
```bash
cat $bsp_path/thermal/cpu_pack_temp_input
```

### CPU Pack Critical Temperature

**Node name:** `$bsp_path/thermal/cpu_pack_temp_crit`

**Description:** Read CPU pack critical temperature threshold

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| temperature | Integer |  |

**Example:** Read CPU pack critical temperature:
```bash
cat $bsp_path/thermal/cpu_pack_temp_crit
```

### CPU Pack Critical Temperature Alarm

**Node name:** `$bsp_path/thermal/cpu_pack_temp_crit_alarm`

**Description:** Read CPU pack critical temperature alarm

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| alarm | Integer |  |

**Example:** Read CPU pack critical temperature alarm:
```bash
cat $bsp_path/thermal/cpu_pack_temp_crit_alarm
```

### CPU Pack Temperature Max

**Node name:** `$bsp_path/thermal/cpu_pack_temp_max`

**Description:** Read CPU pack maximum temperature

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| temperature | Integer |  |

**Example:** Read CPU pack maximum temperature:
```bash
cat $bsp_path/thermal/cpu_pack_temp_max
```

### Read Fan Max Speed

**Node name:** `$bsp_path/thermal/fan<index>_max_speed`

**Description:** Read fan<index> maximum speed

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| fan | Integer |  |

**Example:** Read fan1 maximum speed:
```bash
cat $bsp_path/thermal/fan1_max_speed
```

### Read Fan Min Speed

**Node name:** `$bsp_path/thermal/fan<index>_min_speed`

**Description:** Read fan<index> minimum speed

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| fan | Integer |  |

**Example:** Read fan1 minimum speed:
```bash
cat $bsp_path/thermal/fan1_min_speed
```

### Read Fan Direction

**Node name:** `$bsp_path/thermal/fan<index>_direction`

**Description:** Read fan<index> direction

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| fan | Integer |  |

**Example:** Read fan1 direction:
```bash
cat $bsp_path/thermal/fan1_direction
```
### Read Fan Status

**Node name:** `$bsp_path/thermal/fan<index>_status`

**Description:** Read fan<index> status

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| fan | Integer |  |

**Example:** Read fan1 status:
```bash
cat $bsp_path/thermal/fan1_status
```

### Read Fan Fault

**Node name:** `$bsp_path/thermal/fan<index>_fault`

**Description:** Read fan<index> fault status

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| fan | Integer |  |

**Example:** Read fan1 fault status:
```bash
cat $bsp_path/thermal/fan1_fault
```

### Read Port Ambient

**Node name:** `$bsp_path/thermal/port<index>_ambient_temp`

**Description:** Read port<index> ambient temperature

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| port | Integer |  |

**Example:** Read port1 ambient temperature:
```bash
cat $bsp_path/thermal/port1_ambient_temp
```

### Read PSU Temperature

**Node name:** `$bsp_path/thermal/psu<index>_temp_input`

**Description:** Read PSU<index> temperature

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| psu | Integer |  |

**Example:** Read PSU1 temperature:
```bash
cat $bsp_path/thermal/psu1_temp_input
```

### Read PSU Alarm

**Node name:** `$bsp_path/thermal/psu<index>_alarm`

**Description:** Read PSU<index> alarm status

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| psu | Integer |  |

**Example:** Read PSU1 alarm:
```bash
cat $bsp_path/thermal/psu1_alarm
```

### Read PSU Max

**Node name:** `$bsp_path/thermal/psu<index>_temp_max`

**Description:** Read PSU<index> maximum temperature

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| psu | Integer |  |

**Example:** Read PSU1 maximum temperature:
```bash
cat $bsp_path/thermal/psu1_temp_max
```

### Read PSU Fan Speed

**Node name:** `$bsp_path/thermal/psu<index>_fan_speed`

**Description:** Read PSU<index> fan speed

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| psu | Integer |  |

**Example:** Read PSU1 fan speed:
```bash
cat $bsp_path/thermal/psu1_fan_speed
```

### Read PSU min/max Fan Speed

**Node name:** `$bsp_path/thermal/psu<index>_fan_min_speed`
`$bsp_path/thermal/psu<index>_fan_max_speed`

**Description:** Read PSU<index> minimum and maximum fan speed

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| psu | Integer |  |

**Example:** Read PSU1 fan speeds:
```bash
cat $bsp_path/thermal/psu1_fan_min_speed
cat $bsp_path/thermal/psu1_fan_max_speed
```

### Read PSU Power Status

**Node name:** `$bsp_path/thermal/psu<index>_power_status`

**Description:** Read PSU<index> power status

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| psu | Integer |  |

**Example:** Read PSU1 power status:
```bash
cat $bsp_path/thermal/psu1_power_status
```

### Read PSU Status

**Node name:** `$bsp_path/thermal/psu<index>_status`

**Description:** Read PSU<index> status

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| psu | Integer |  |

**Example:** Read PSU1 status:
```bash
cat $bsp_path/thermal/psu1_status
```

### Read System PWM1

**Node name:** `$bsp_path/thermal/system_pwm1`

**Description:** Read system PWM1 value

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| pwm | Integer |  |

**Example:** Read system PWM1:
```bash
cat $bsp_path/thermal/system_pwm1
```

### Read Temperature Critical Module

**Node name:** `$bsp_path/thermal/module<index>_temp_crit`

**Description:** Read module<index> critical temperature threshold

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| module | Integer |  |

**Example:** Read module1 critical temperature:
```bash
cat $bsp_path/thermal/module1_temp_crit
```

### Read Temperature Emergency Module

**Node name:** `$bsp_path/thermal/module<index>_temp_emergency`

**Description:** Read module<index> emergency temperature threshold

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| module | Integer |  |

**Example:** Read module1 emergency temperature:
```bash
cat $bsp_path/thermal/module1_temp_emergency
```

### Read Temperature Trip Critical Module

**Node name:** `$bsp_path/thermal/module<index>_temp_trip_crit`

**Description:** Read module<index> trip critical temperature

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| module | Integer |  |

**Example:** Read module1 trip critical temperature:
```bash
cat $bsp_path/thermal/module1_temp_trip_crit
```

### Read Temperature Fault Module

**Node name:** `$bsp_path/thermal/module<index>_temp_fault`

**Description:** Read module<index> temperature fault status

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| module | Integer |  |

**Example:** Read module1 temperature fault:
```bash
cat $bsp_path/thermal/module1_temp_fault
```

### Read Temperature Input Module

**Node name:** `$bsp_path/thermal/module<index>_temp_input`

**Description:** Read module<index> temperature input

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| module | Integer |  |

**Example:** Read module1 temperature input:
```bash
cat $bsp_path/thermal/module1_temp_input
```

### Read Temperature Critical Gearbox

**Node name:** `$bsp_path/thermal/gearbox<index>_temp_crit`

**Description:** Read gearbox<index> critical temperature threshold

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| gearbox | Integer |  |

**Example:** Read gearbox1 critical temperature:
```bash
cat $bsp_path/thermal/gearbox1_temp_crit
```

### Read Temperature Emergency Gearbox

**Node name:** `$bsp_path/thermal/gearbox<index>_temp_emergency`

**Description:** Read gearbox<index> emergency temperature threshold

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| gearbox | Integer |  |

**Example:** Read gearbox1 emergency temperature:
```bash
cat $bsp_path/thermal/gearbox1_temp_emergency
```

### Read Temperature Trip Critical Gearbox

**Node name:** `$bsp_path/thermal/gearbox<index>_temp_trip_crit`

**Description:** Read gearbox<index> trip critical temperature

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| gearbox | Integer |  |

**Example:** Read gearbox1 trip critical temperature:
```bash
cat $bsp_path/thermal/gearbox1_temp_trip_crit
```

### Read Temperature Input Gearbox

**Node name:** `$bsp_path/thermal/gearbox<index>_temp_input`

**Description:** Read gearbox<index> temperature input

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| gearbox | Integer |  |

**Example:** Read gearbox1 temperature input:
```bash
cat $bsp_path/thermal/gearbox1_temp_input
```

### Read Switch CPU Temperature

**Node name:** `$bsp_path/thermal/switch_cpu_temp`

**Description:** Read switch CPU temperature

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| temperature | Integer |  |

**Example:** Read switch CPU temperature:
```bash
cat $bsp_path/thermal/switch_cpu_temp
```

### Read Switch Fan Temperature

**Node name:** `$bsp_path/thermal/switch_fan_temp`

**Description:** Read switch fan temperature

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| temperature | Integer |  |

**Example:** Read switch fan temperature:
```bash
cat $bsp_path/thermal/switch_fan_temp
```

### Read Switch Port Temperature

**Node name:** `$bsp_path/thermal/switch_port<index>_temp`

**Description:** Read switch port<index> temperature

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| port | Integer |  |

**Example:** Read switch port1 temperature:
```bash
cat $bsp_path/thermal/switch_port1_temp
```

### Read Switch Power Supply Temperature

**Node name:** `$bsp_path/thermal/switch_psu<index>_temp`

**Description:** Read switch power supply<index> temperature

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| psu | Integer |  |

**Example:** Read switch PSU1 temperature:
```bash
cat $bsp_path/thermal/switch_psu1_temp
```
## Watchdog

### Read Boot Status

**Node name:** `$bsp_path/watchdog/bootstatus`

**Description:** Read watchdog boot status

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| status | Integer |  |

**Example:** Read watchdog boot status:
```bash
cat $bsp_path/watchdog/bootstatus
```

### Read Identity

**Node name:** `$bsp_path/watchdog/identity`

**Description:** Read watchdog identity

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| identity | String |  |

**Example:** Read watchdog identity:
```bash
cat $bsp_path/watchdog/identity
```

### Read No Way Out

**Node name:** `$bsp_path/watchdog/nowayout`

**Description:** Read watchdog no way out setting

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| nowayout | Integer | 0/1 |

**Example:** Read watchdog no way out:
```bash
cat $bsp_path/watchdog/nowayout
```

### Read State

**Node name:** `$bsp_path/watchdog/state`

**Description:** Read watchdog state

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| state | String |  |

**Example:** Read watchdog state:
```bash
cat $bsp_path/watchdog/state
```

### Read Status

**Node name:** `$bsp_path/watchdog/status`

**Description:** Read watchdog status

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| status | String |  |

**Example:** Read watchdog status:
```bash
cat $bsp_path/watchdog/status
```

### Read Timeout

**Node name:** `$bsp_path/watchdog/timeout`

**Description:** Read watchdog timeout value

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| timeout | Integer | seconds |

**Example:** Read watchdog timeout:
```bash
cat $bsp_path/watchdog/timeout
```

### Read Timeleft

**Node name:** `$bsp_path/watchdog/timeleft`

**Description:** Read watchdog time left

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| timeleft | Integer | seconds |

**Example:** Read watchdog time left:
```bash
cat $bsp_path/watchdog/timeleft
```

## JTAG interface

### Enable / Disable JTAG mechanism

**Node name:** `$bsp_path/jtag/enable`

**Description:** Enable or disable JTAG mechanism

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| enable | Integer | 0/1 |

**Example:** Enable JTAG mechanism:
```bash
echo 1 > $bsp_path/jtag/enable
```

### Set JTAG TCK pin

**Node name:** `$bsp_path/jtag/tck`

**Description:** Set JTAG TCK pin

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| tck | Integer |  |

**Example:** Set JTAG TCK pin:
```bash
echo 1 > $bsp_path/jtag/tck
```

### Set JTAG TDI pin

**Node name:** `$bsp_path/jtag/tdi`

**Description:** Set JTAG TDI pin

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| tdi | Integer |  |

**Example:** Set JTAG TDI pin:
```bash
echo 1 > $bsp_path/jtag/tdi
```

### Set JTAG TMS pin

**Node name:** `$bsp_path/jtag/tms`

**Description:** Set JTAG TMS pin

**Access:** Write

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| tms | Integer |  |

**Example:** Set JTAG TMS pin:
```bash
echo 1 > $bsp_path/jtag/tms
```

### Get JTAG TDO pin

**Node name:** `$bsp_path/jtag/tdo`

**Description:** Get JTAG TDO pin

**Access:** Read only

**Release version:** 1.0

**Arguments:**
| Name | Data type | Values |
|------|-----------|--------|
| tdo | Integer |  |

**Example:** Get JTAG TDO pin:
```bash
cat $bsp_path/jtag/tdo
```
# Thermal Control

The thermal algorithm is described in a separate document - [Thermal Monitoring for NVIDIA Systems with Third Party OS](Thermal_Monitoring_for_NVIDIA_Systems_with_third_party_OS.md)

## Thermal Control Versions

The hw-management package supports two versions of thermal control:

### TC v2.0 (Default)
- **Script**: `/usr/bin/hw_management_thermal_control.py`
- **Service**: `hw-management-tc.service`
- **Description**: Standard thermal control implementation for most systems

### TC v2.5 (Advanced)
- **Script**: `/usr/bin/hw_management_thermal_control_2_5.py`
- **Service**: `hw-management-tc.service` (automatically selects version)
- **Description**: Enhanced thermal control with improved algorithms for newer systems
- **Supported Systems**: SN5610, SN5640, Q3401-RD

The system automatically selects the appropriate thermal control version based on the hardware platform.

# Drivers

## Watchdog

NVIDIA watchdog device is implemented in a programmable logic device. There are 2 types of HW watchdog implementations:

 Type 1 – actual HW timeout defined as a power of 2 msec. For example: Timeout 20 sec is

rounded up to 32768 msec. The maximum timeout period is 32 sec (32768 msec). Get time-left is not supported.

 Type 2 – actual HW timeout defined in seconds and is the same as user-defined timeout.

Maximum timeout is 255 sec. Get time-left is supported.

Type 1 HW watchdog implementation exists in old systems and all new systems have Type 2 HW watchdog. The two types of HW implementation also have a different register map.

NVIDIA systems can have 2 watchdogs: Main and auxiliary. Main and auxiliary watchdog devices can be enabled together on the same system. There are several actions that can be defined in the watchdog: System reset, start fans on full speed, and increase register counter. The last 2 actions are performed without a system reset. Actions without reset are provided for the auxiliary watchdog device, which is optional.

Watchdog can be started during a probe. In this case it is pinged by the watchdog core before the watchdog device is opened by the user space application.

Watchdog can be initialized in using a nowayout method. That is, once started it cannot be stopped. The mlx-wdt driver supports both HW watchdog implementations.

Watchdog driver is probed from the common mlx_platform driver. Mlx_platform driver provides an appropriate set of registers for NVIDIA watchdog device, identity name (mlx-wdt-main or mlx-wdt- aux), initial timeout, performed action in expiration and configuration flags.

Watchdog configuration flags: nowayout and start_at_boot. HW watchdog version: type1 or type2. The driver checks during initialization if the previous system reset was done by the watchdog. If yes, it makes a notification about this event.

Access to HW registers is performed through a generic regmap interface.
