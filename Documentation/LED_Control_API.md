<!-- SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES -->

# LED Control API

Common reference for NVIDIA switch **hw-management** LED control over sysfs.
Covers the **host CPU** stack (primary), kernel **CPLD** behaviour, and notes for
the **BMC** stack.

**Related documents**

| Document | Purpose |
|----------|---------|
| [Chassis Management User Manual §3.13 / §3.16](Chassis_Management_for_NVIDIA_Switch_Systems_with_Sysfs_rev.3.2.md) | Formal API node definitions (legacy naming) |
| [examples/hw-management-led-sysfs.txt](../examples/hw-management-led-sysfs.txt) | Host runtime tree under `/var/run/hw-management/led/` |
| [bmc/examples/hw-management-bmc-led-sysfs.txt](../bmc/examples/hw-management-bmc-led-sysfs.txt) | BMC LED notes and kernel sysfs layout |
| [mockup/hw-management/led/](../mockup/hw-management/led/) | Annotated example files |

**Stack applicability:** Host and BMC share the same kernel `leds-mlxreg` driver and
`/sys/class/leds/mlxreg:*` nodes. The **host** package populates
`/var/run/hw-management/led/` via `hw-management-chassis-events.sh`. The **BMC**
package has udev rules for LED add/remove but does not yet mirror the host virtual
tree in `hw-management-bmc-events.sh`; BMC code may write kernel LED sysfs directly
(see `turn_off_host_reset_leds()` in `bmc/usr/etc/HI189/hw-management-bmc-events.sh`).

---

## 1. Architecture

```
CPLD / FPGA LED registers
        ↓  (I2C / mlxreg-io)
Kernel: drivers/leds/leds-mlxreg.c  →  /sys/class/leds/mlxreg:<func>:<color>/
        ↓  udev add/remove (50-hw-management-events.rules)
Userspace: hw-management-chassis-events.sh
        ↓  symlinks + state script
Virtual API: /var/run/hw-management/led/   ($bsp_path/led)
```

| Layer | Component | Role |
|-------|-----------|------|
| Hardware | CPLD | Boot-time LED patterns; PSU/FAN status aggregation (see §5) |
| Kernel | `leds-mlxreg` | Register-backed LED class devices; HW/SW ownership hand-off |
| Kernel | `mlx-platform.c` | Per-SKU LED register map (`fanN:green`, `status:amber`, …) |
| udev | `50-hw-management-events.rules` | Fires on `mlxreg*:*:{green,red,orange,amber,blue}` |
| Userspace | `hw-management-chassis-events.sh` | Creates stable symlinks under `$bsp_path/led/` |
| Userspace | `hw-management-led-state-conversion.sh` | Derives aggregate colour / blink state |

**Required kernel config** (see root `README.md`):

- `CONFIG_LEDS_MLXREG=m`
- `CONFIG_LEDS_CLASS=y`, `CONFIG_NEW_LEDS=y`
- `CONFIG_LEDS_TRIGGERS=y`, `CONFIG_LEDS_TRIGGER_TIMER=m`

**Key kernel patches** (`recipes-kernel/linux/linux-6.12/`):

| Patch | Subject |
|-------|---------|
| `0017-leds-mlxreg-Add-support-for-new-flavour-of-capabilit.patch` | Capability register: bitmap or slot counter |
| `0018-leds-mlxreg-Remove-code-for-amber-LED-colour.patch` | Amber/orange/red share red colour code path |
| `0021-leds-mlxreg-Skip-setting-LED-color-during-initializa.patch` | Preserve CPLD boot LED state at driver probe |
| `0060-leds-mlxreg-Provide-conversion-for-hardware-LED-colo.patch` | Read back HW-specific colour codes |
| `8004-leds-leds-mlxreg-Downstream-Send-udev-event-from-led.patch` | udev `change` on brightness write (SN2201) |

---

## 2. Runtime API (`$bsp_path/led`)

`$bsp_path` is `/var/run/hw-management` on standard Linux distributions.

### 2.1 Naming convention

The **runtime implementation** uses the `led_<function>` prefix (created by
`hw-management-chassis-events.sh`). The user manual (§3.16) documents an older
`<function>_status_led` form. Map as follows:

| Runtime name (implementation) | User manual §3.16 name | Kernel label (`mlxreg:…`) |
|-------------------------------|------------------------|---------------------------|
| `led_fan` | — (group FAN status) | `fan` |
| `led_fan<N>` | `fan<N>_status_led` | `fan<N>` |
| `led_psu` | `psu_status_led` / `psu<N>_status_led` | `psu` |
| `led_status` | `status_led` | `status` |
| `led_uid` | UID LED nodes (§3.16.22+) | `uid` |
| `led_power` | — | `power` |
| Line card: `lc<M>/led/led_status` | `lc<M>_status_led` | `<busprefix>:status` |

**`led_fan` vs `led_fan<N>`:** Some platforms expose a single **group** FAN status
LED (`led_fan` ← `mlxreg:fan:green|amber`) that reflects the worst state across all
fan trays while CPLD hardware is in control (see §4.3). Other platforms expose only
**per-tray** LEDs (`led_fan1` … `led_fan<N>` ← `mlxreg:fan1:*`, …). A given SKU
may have one or both; nodes appear only when present in platform LED data and pass
capability gating in the driver.

`<function>` comes from the middle field of the kernel LED name
(`mlxreg:<function>:<color>`).

### 2.2 Per-LED file set

For each logical LED group `led_<func>` the host stack creates:

| File | Type | Description |
|------|------|-------------|
| `led_<func>` | Regular file | Aggregate state: `none`, `green`, `amber`, `red`, `blue`, or `<color>_blink` |
| `led_<func>_state` | Script symlink | Runs `hw-management-led-state-conversion.sh` to refresh `led_<func>` |
| `led_<func>_capability` | Regular file | Space-separated list of supported states, e.g. `none green green_blink amber amber_blink` |
| `led_<func>_<color>` | Symlink | → `/sys/class/leds/mlxreg:<func>:<color>/brightness` |
| `led_<func>_<color>_trigger` | Symlink | → `…/trigger` |
| `led_<func>_<color>_delay_on` | Symlink | → `…/delay_on` (ms) |
| `led_<func>_<color>_delay_off` | Symlink | → `…/delay_off` (ms) |

**Colour alias:** kernel nodes may use `:orange`; userspace renames to `amber`
in symlink names and capability strings.

**Line cards:** when the LED device path contains `leds-mlxreg.<bus>`, symlinks are
created under `$bsp_path/lc<N>/led/` instead of `$bsp_path/led/`.

See [examples/hw-management-led-sysfs.txt](../examples/hw-management-led-sysfs.txt)
for a full tree example.

### 2.3 Read API

```bash
# Refresh aggregate state, then read it
$bsp_path/led/led_fan_state
cat $bsp_path/led/led_fan
# → green | amber | …  (group FAN status, CPLD worst-status while HW-owned)

$bsp_path/led/led_fan1_state
cat $bsp_path/led/led_fan1
# → green | amber | red | blue | none | green_blink | amber_blink | …

# Read supported colours / modes
cat $bsp_path/led/led_fan_capability
cat $bsp_path/led/led_fan1_capability

# Read raw brightness of one colour channel (0 = off, max_brightness = on)
cat $bsp_path/led/led_fan_green
cat $bsp_path/led/led_fan1_green
```

`hw-management-led-state-conversion.sh` scans colour brightness files and blink
timing (`delay_on`, `delay_off`). The first active non-blink colour wins; if
`delay_on`, `delay_off`, and brightness are all non-zero, state is `<color>_blink`.

### 2.4 Write API

Writes go to the per-colour symlinks (kernel `brightness`, `trigger`, `delay_*`).

```bash
# Solid green on fan1 (turn off other colours first)
echo 0   > $bsp_path/led/led_fan1_amber
echo 255 > $bsp_path/led/led_fan1_green
$bsp_path/led/led_fan1_state

# Solid amber
echo 0   > $bsp_path/led/led_fan1_green
echo 255 > $bsp_path/led/led_fan1_amber
$bsp_path/led/led_fan1_state

# Blinking amber (~3 Hz hardware-supported timing)
echo timer > $bsp_path/led/led_fan1_amber_trigger
echo 167  > $bsp_path/led/led_fan1_amber_delay_on
echo 167  > $bsp_path/led/led_fan1_amber_delay_off
echo 255  > $bsp_path/led/led_fan1_amber
$bsp_path/led/led_fan1_state
# → amber_blink

# Turn LED off
echo 0 > $bsp_path/led/led_fan1_green
echo 0 > $bsp_path/led/led_fan1_amber
echo none > $bsp_path/led/led_fan1_green_trigger
$bsp_path/led/led_fan1_state
```

`max_brightness` is typically `255`. Use the value from
`/sys/class/leds/mlxreg:<func>:<color>/max_brightness` when in doubt.

**UID LED** supports `blue` (and platform-specific colours). **Status / fan / PSU**
LEDs support `green`, `amber` (or `orange` at kernel level), and `red` on some
platforms.

### 2.5 Kernel sysfs (direct access)

All virtual nodes symlink into:

```
/sys/class/leds/mlxreg:<function>:<color>/
├── brightness      # 0 … max_brightness
├── max_brightness
├── trigger         # none | timer | …
├── delay_on        # ms (timer trigger)
└── delay_off       # ms (timer trigger)
```

Modular / line-card LEDs use a bus prefix instead of `mlxreg`:
`pcicard48:status:green`, etc.

Validation script: `bmc/tests/hw-management-bmc-led-validation.sh` (exercises
kernel nodes; usable on host or BMC).

### 2.6 Platform notes

| Topic | Detail |
|-------|--------|
| Group vs per-tray FAN LEDs | `led_fan` (`mlxreg:fan:*`) = chassis group status; `led_fan<N>` = per-tray. SKU may have one or both |
| LED capability gating | Driver skips LEDs not equipped on this SKU (capability register bitmap or slot counter — patch `0017`) |
| Multi-instance same name | Line cards: `mlxreg:status:green` vs `pcicard48:status:green` (patch `0005` on 5.14) |
| SN2201 fan tray | GPIO override via `fantray-led-event` in chassis-events (not CPLD mlxreg) |
| Thermal → LED | **Not implemented** in hw-management package; NOS/platform policy sets LEDs from `$bsp_path/thermal/` health if desired |

---

## 3. Supported colours and register encoding

CPLD LED registers use a common encoding (driver `leds-mlxreg.c`):

| Meaning | Software code | Hardware (pre-SW) code |
|---------|---------------|------------------------|
| Off | `0x00` | `0x00` |
| Red / amber / orange solid | `0x05` | `0x01` |
| Green solid | `0x0D` | `0x09` |
| +3 Hz blink | +`0x01` | +`0x01` |
| +6 Hz blink | +`0x02` | +`0x02` |

Amber, orange, and red share the same red base colour in software (patch `0018`).
Userspace exposes `amber` even when the kernel node is named `:orange`.

---

## 4. CPLD LED control

This section describes **hardware CPLD behaviour** for PSU and FAN status LEDs and
how the kernel driver exposes it. It complements §3.16 of the user manual.

### 4.1 Hardware ownership at boot

After power-on and through early boot, the **CPLD retains control** of PSU and FAN
status LEDs. Typical behaviour:

- CPLD drives LED patterns directly from fan tach, PSU presence, and fault logic.
- The kernel `leds-mlxreg` driver **does not write** LED registers during probe
  (patch `0021`). Boot-time patterns (e.g. system status **green blink**) remain
  visible until software takes over.
- On read, while still under hardware control, the driver converts HW colour codes
  (`0x01`, `0x09`) to the correct sysfs colour (patch `0060`).

### 4.2 Software takeover

**The first write to any LED register on the system transfers control from CPLD
hardware logic to software** for all LEDs on that LED controller instance.

- Trigger: any `brightness` write (or other register write) through
  `/sys/class/leds/mlxreg:*` or the virtual `$bsp_path/led/led_*_<color>` symlinks.
- Effect: CPLD automatic PSU/FAN status updates stop for the remainder of the
  power cycle.
- Restoration: only a **system reboot** (or power cycle) returns ownership to CPLD
  hardware control.

Platform software that needs CPLD-driven status LEDs during early boot should
**delay the first LED write** until the NOS is ready to manage indicators itself.

### 4.3 Worst-status aggregation (PSU / FAN)

While CPLD hardware controls PSU and FAN status LEDs (before the first software
write), the CPLD computes each **group status LED** as the **worst** state across
all LEDs in that group:

| Priority (worst first) | Colour | Typical meaning |
|------------------------|--------|-----------------|
| 1 | Red | Critical fault |
| 2 | Amber / orange | Warning, degraded |
| 3 | Green | Healthy |
| 4 | Off / blink patterns | Platform-specific boot / activity |

**Examples**

- All FAN tray LEDs green → group **`led_fan`** is **green**.
- Any single fan tray LED amber/orange → **`led_fan`** is **amber** (even if all
  others are green).
- Any fan tray LED red → **`led_fan`** is **red** (dominates amber and green).

The same worst-status rule applies to the **`led_psu`** group LED across PSU
slots.

This aggregation is performed **in CPLD hardware**, not in hw-management userspace.
After software takeover (§4.2), the NOS is responsible for setting aggregate
group LEDs (`led_fan`, `led_psu`, `led_status`) if exposed on the platform.

### 4.4 Interaction with virtual API

| Phase | Read `$bsp_path/led/led_fan` | Write `$bsp_path/led/led_fan_*` |
|-------|-------------------------------|----------------------------------|
| Before first SW write | CPLD worst-status across fan trays (HW readback) | — |
| After first SW write | Software-programmed group state | Updates register; disables HW aggregation |

| Phase | Read `$bsp_path/led/led_fan1` | Write `$bsp_path/led/led_fan1_*` |
|-------|-------------------------------|----------------------------------|
| Before first SW write | Reflects CPLD state via driver HW readback | — |
| After first SW write | Reflects software-programmed state | Updates CPLD register; disables HW aggregation |

Run `led_<func>_state` after external changes to refresh the aggregate file.

---

## 5. Line card (LC) LEDs

Line card status LEDs use the same file layout under:

```
/var/run/hw-management/lc<index>/led/
```

Kernel devices appear as `leds-mlxreg.<i2c_bus>` with names like
`<busprefix>:status:green`. LC LED API is documented in user manual §3.13; runtime
names follow `led_status`, `led_status_green`, etc., inside the LC directory.

---

## 6. BMC stack

| Item | Detail |
|------|--------|
| udev rules | `bmc/usr/etc/HI189/5-hw-management-bmc-events.rules` — LED add/remove |
| Virtual tree | **Not populated** — no `led` case in `hw-management-bmc-events.sh` `add`/`rm` |
| Direct kernel access | `turn_off_host_reset_leds()` writes `mlxreg:status:green` on CPU reset |
| Validation | `bmc/tests/hw-management-bmc-led-validation.sh` |
| Future | Mirror host `hw-management-chassis-events.sh` LED handler to create `$bsp_path/led/` on BMC |

See [bmc/examples/hw-management-bmc-led-sysfs.txt](../bmc/examples/hw-management-bmc-led-sysfs.txt).

---

## 7. Examples

### Read group FAN status LED after boot (CPLD still in control)

```bash
$bsp_path/led/led_fan_state
cat $bsp_path/led/led_fan
# e.g. green while all trays healthy; amber if any tray degraded
```

### Read system status LED after boot (CPLD still in control)

```bash
$bsp_path/led/led_status_state
cat $bsp_path/led/led_status
# e.g. green_blink while hardware owns the LED
```

### Set all fan LEDs green from NOS (takes over from CPLD)

```bash
for n in 1 2 3 4; do
    echo 0   > $bsp_path/led/led_fan${n}_amber 2>/dev/null || true
    echo 255 > $bsp_path/led/led_fan${n}_green
    $bsp_path/led/led_fan${n}_state
done
# First brightness write above disables further CPLD HW aggregation until reboot.
```

### Read kernel LED directly

```bash
cat /sys/class/leds/mlxreg:status:green/brightness
ls /sys/class/leds/mlxreg:*
```

---

## 8. Testing

| Test | Location |
|------|----------|
| LED state conversion (unit) | `tests/shell/spec/hw_management_led_state_conversion_spec.sh` |
| Kernel LED read/write (HW) | `bmc/tests/hw-management-bmc-led-validation.sh` |
| Mockup reference tree | `mockup/hw-management/led/` |

---

## 9. Document history

| Version | Date | Notes |
|---------|------|-------|
| 1.0 | 2026-07-14 | Initial common LED API doc; CPLD ownership and worst-status aggregation |
