#!/bin/bash
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause

Describe 'MPS VR DPC per-device updater: revision check and CRC file'
  # shellspec runs from tests/shell (where .shellspec lives).
  repo_root="$(cd "${SHELLSPEC_PROJECT_ROOT:-$PWD}/../.." >/dev/null 2>&1 && pwd -P)"
  updater_src="${repo_root}/usr/usr/bin/hw-management-vr-dpc-update.sh"

  setup_test_env() {
    TEST_TMPDIR="$(mktemp -d)"
    TEST_BINDIR="${TEST_TMPDIR}/bin"
    mkdir -p "$TEST_BINDIR" "${TEST_TMPDIR}/sys/i2c-7"

    # No I2C on the test host: stub the tools. i2cget answers from the
    # environment so each example sets what the VR reports.
    cat > "${TEST_BINDIR}/i2cget" <<'EOF'
#!/bin/sh
# i2cget -y -f BUS ADDR REG w
case "$5" in
  0x9e|0x9E) echo "${FAKE_MODEL:-0x0601}" ;;
  0x9f|0x9F) echo "${FAKE_REV:-0x0001}" ;;
  0xf0|0xF0) echo "${FAKE_CRC:-0x2947}" ;;
  0xab) echo "${FAKE_CRC_NORMAL:-0x96ca}" ;;
  0xad) echo "${FAKE_CRC_MULTI:-0x1234}" ;;
  *) echo 0x0000 ;;
esac
EOF
    printf '#!/bin/sh\nexit 0\n' > "${TEST_BINDIR}/i2cset"
    # The updater logs through logger; print the message instead.
    printf '#!/bin/sh\nfor a; do m="$a"; done\necho "$m"\n' > "${TEST_BINDIR}/logger"
    printf '#!/bin/sh\nexit 0\n' > "${TEST_BINDIR}/sleep"
    chmod +x "${TEST_BINDIR}"/*

    # Same script, with only the sysfs bus-existence path redirected.
    UPDATER="${TEST_TMPDIR}/updater.sh"
    sed "s#/sys/class/i2c-dev#${TEST_TMPDIR}/sys#" "$updater_src" > "$UPDATER"

    CONF="${TEST_TMPDIR}/config.conf"
    printf 'WP_VAL=0x00\nDPC_MODEL_ID=0x9e\nDPC_REVISION_ID=0x9f\nDPC_MODEL_ID_PAGE=1\nDPC_REVISION_ID_PAGE=0\n' > "$CONF"

    # 15-column MP29816 layout: pages 0, 1, 2 and a Page4 group. CRLF line ends.
    CSV="${TEST_TMPDIR}/pkg_rev2.csv"
    {
      printf 'Device Address,Command code,W/R,Page0.Command name,Page0.Byte,Page0.Value,Page1.Command name,Page1.Byte,Page1.Value,Page2.Command name,Page2.Byte,Page2.Value,Page4.Command name,Page4.Byte,Page4.Value\r\n'
      printf '0x66,0x1D,RW,,,,,,,MFR_PRODUCT_ID2,2,0xB816,,,\r\n'
      printf '0x66,0x9E,RW,MFR_CONFIG_ID,2,0x5200,MFR_CONFIG_ID2,2,0x0601,,,,,,\r\n'
      printf '0x66,0x9F,RW,MFR_USER_REVISION,2,0x0002,MFR_APS_ITH_OPTI,2,0x0000,,,,,,\r\n'
      printf '0x66,0xF0,RW,,,,EXPECTED_USER_CRC,2,0x2947,,,,,,\r\n'
    } > "$CSV"

    CRC_RAW="${TEST_TMPDIR}/crc_raw.txt"
    printf '0x2947' > "$CRC_RAW"

    # Legacy two-CRC device: no EXPECTED_USER_CRC row, CRC in the third field.
    CSV_LEGACY="${TEST_TMPDIR}/legacy.csv"
    {
      printf 'device_addr,cmd_code,wr,p0_name,p0_byte,p0_val,p1_name,p1_byte,p1_val,p2_name,p2_byte,p2_val\n'
      printf '0x62,0x21,RW,VOUT_COMMAND,2,0x0100,,,,,,\n'
    } > "$CSV_LEGACY"
    CRC_LEGACY="${TEST_TMPDIR}/crc_legacy.txt"
    printf 'crc normal 96CA\ncrc multi 1234\n' > "$CRC_LEGACY"
  }

  teardown_test_env() {
    rm -rf "${TEST_TMPDIR:-}"
  }

  BeforeEach 'setup_test_env'
  AfterEach 'teardown_test_env'

  run_updater() {
    PATH="${TEST_BINDIR}:${PATH}" bash "$UPDATER" "$@" 2>&1
  }

  Describe 'revision check'
    It 'allows an upgrade (device rev 1, package rev 2)'
      export FAKE_REV=0x0001
      When call run_updater 7 mp29816 0 "$CSV" "$CRC_RAW" "$CONF"
      The status should be success
      The output should include 'Device revision 0x0001 (1), package revision 0x0002 (2) - OK'
    End

    It 'allows the same revision'
      export FAKE_REV=0x0002
      When call run_updater 7 mp29816 0 "$CSV" "$CRC_RAW" "$CONF"
      The status should be success
      The output should include 'Device revision 0x0002 (2), package revision 0x0002 (2) - OK'
    End

    It 'refuses a downgrade (device rev 3, package rev 2)'
      export FAKE_REV=0x0003
      When call run_updater 7 mp29816 0 "$CSV" "$CRC_RAW" "$CONF"
      The status should be failure
      The output should include 'downgrade refused (use --force)'
      The output should include 'Revision validation failed - exiting'
    End

    It 'allows a downgrade with --force'
      export FAKE_REV=0x0003
      When call run_updater --force 7 mp29816 0 "$CSV" "$CRC_RAW" "$CONF"
      The status should be success
      The output should include '--force allows downgrade'
    End

    It 'does not compare revisions across models'
      export FAKE_MODEL=0x0530 FAKE_REV=0x0400
      When call run_updater 7 mp29816 0 "$CSV" "$CRC_RAW" "$CONF"
      The status should be success
      The output should include 'Device model 0x0530, package model 0x0601 - revision not compared'
    End

    It 'keeps the device address after reading the CSV'
      export FAKE_REV=0x0001
      When call run_updater 7 mp29816 0 "$CSV" "$CRC_RAW" "$CONF"
      The status should be success
      The output should include 'CRC read - cmd=0xF0 page=1 Normal: 0x2947'
    End
  End

  Describe 'CRC file'
    It 'accepts a bare single value and skips the update when it matches'
      export FAKE_REV=0x0002 FAKE_CRC=0x2947
      When call run_updater 7 mp29816 0 "$CSV" "$CRC_RAW" "$CONF"
      The status should be success
      The output should include 'Parsed CRC values - Normal: 2947, Multi:  (count=1)'
      The output should include 'CRC validation passed - no update needed'
    End

    It 'reports a mismatch against the single value'
      export FAKE_REV=0x0002 FAKE_CRC=0x1111
      When call run_updater 7 mp29816 0 "$CSV" "$CRC_RAW" "$CONF"
      # The stubbed VR does not take the register writes that follow.
      The status should be failure
      The output should include 'CRC mismatch - normal: actual 0x1111, expected 0x2947'
      The output should include 'CRC validation failed - proceeding with update'
      The output should not include 'Invalid CSV value'
    End

    It 'still reads the legacy two-line format'
      When call run_updater 7 mp2975 0 "$CSV_LEGACY" "$CRC_LEGACY"
      The status should be success
      The output should include 'Parsed CRC values - Normal: 96ca, Multi: 1234 (count=2)'
      The output should include 'CRC match - normal: 0x96ca'
      The output should include 'CRC match - multi: 0x1234'
    End
  End
End
