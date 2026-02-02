#!/bin/bash
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#

Describe 'VR DPC update entrypoint + read-vr JSON'
  # Resolve repo root from this spec file location:
  #   tests/shell/spec/ -> repo root is ../../..
  spec_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
  repo_root="$(cd "${spec_dir}/../../.." >/dev/null 2>&1 && pwd -P)"

  dpc_update="${repo_root}/usr/usr/bin/hw-management-dpc-update.sh"
  read_vr="${repo_root}/usr/usr/bin/hw-management-read-vr-model-version.sh"

  setup_test_env() {
    TEST_TMPDIR="$(mktemp -d)"
    TEST_BINDIR="${TEST_TMPDIR}/bin"
    mkdir -p "$TEST_BINDIR"

    # Stub i2c tools so tests don't require real hardware.
    cat > "${TEST_BINDIR}/i2cget" <<'EOF'
#!/bin/sh
exit 0
EOF
    cat > "${TEST_BINDIR}/i2cset" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "${TEST_BINDIR}/i2cget" "${TEST_BINDIR}/i2cset"

    # Single-line devtree content (space-separated). Use an unsupported device type to avoid I2C reads.
    TEST_DEVTREE="${TEST_TMPDIR}/devtree"
    echo "tps53679 0x40 X voltmon-test0" > "$TEST_DEVTREE"
  }

  teardown_test_env() {
    rm -rf "${TEST_TMPDIR:-}"
  }

  BeforeEach 'setup_test_env'
  AfterEach 'teardown_test_env'

  Describe 'hw-management-read-vr-model-version.sh --show --json'
    It 'prints clean JSON from a single-line devtree'
      When run bash -c "PATH='${TEST_BINDIR}':\"\$PATH\" DEVTREE_FILE='${TEST_DEVTREE}' bash '${read_vr}' --show --json"
      The status should be success
      The output should start with "["
      The output should include "\"voltmon_name\":\"voltmon-test0\""
      The output should include "\"pmic_index\""
      The output should include "\"device_name\":\"tps53679\""
      The output should include "\"bus\":\"X\""
      The output should include "\"address\":\"0x40\""
      The output should include "\"model\":\"Not supported\""
      The output should include "\"revision_id\":\"Not supported\""
    End
  End

  Describe 'hw-management-dpc-update.sh --verify argument parsing'
    build_test_pkg() {
      PKG_ROOT="${TEST_TMPDIR}/pkg"
      PKG_TOP="${PKG_ROOT}/ROSALIND_PKG"
      mkdir -p "$PKG_TOP"

      # Minimal referenced files
      cat > "${PKG_TOP}/cfg.csv" <<'EOF'
dev_addr,cmd_code,wr,p0_name,p0_byte,p0_val,p1_name,p1_byte,p1_val,p2_name,p2_byte,p2_val
0x40,0xba,wr,model,2,0x1234,,,,,,
0x40,0xbb,wr,rev,2,0x5678,,,,,,
EOF
      echo "crc 0 0xdeadbeef" > "${PKG_TOP}/crc.txt"
      cat > "${PKG_TOP}/dev.conf" <<'EOF'
DPC_MODEL_ID=0xba
DPC_REVISION_ID=0xbb
DPC_MODEL_ID_PAGE=0
DPC_REVISION_ID_PAGE=0
EOF

      # Package JSON expects numeric Bus; devtree bus in this test is intentionally non-numeric ("X")
      # to avoid /dev/i2c-* checks in verify mode.
      cat > "${PKG_TOP}/dpc_rosalind.json" <<'EOF'
{
  "System HID": "HI123",
  "Devices": [
    {
      "DeviceType": "mp2974",
      "Bus": 1,
      "ConfigFile": "cfg.csv",
      "CrcFile": "crc.txt",
      "DeviceConfigFile": "dev.conf"
    }
  ]
}
EOF

      TAR_PATH="${TEST_TMPDIR}/pkg.tar.gz"
      ( cd "$PKG_ROOT" && tar -czf "$TAR_PATH" "ROSALIND_PKG" )
    }

    It 'accepts --verify before tar path'
      build_test_pkg
      [[ -x /usr/bin/hw-management-read-vr-model-version.sh ]] || Skip "requires /usr/bin/hw-management-read-vr-model-version.sh"
      When run bash -c "PATH='${TEST_BINDIR}':\"\$PATH\" DPC_TOOLS_PATHS='${repo_root}/usr/usr/bin' DEVTREE_FILE='${TEST_DEVTREE}' DPC_DEVTREE_PATH='${TEST_DEVTREE}' bash '${dpc_update}' --verify '${TAR_PATH}'"
      The status should be success
      The output should include "VERIFY PASSED."
    End

    It 'accepts --verify after tar path'
      build_test_pkg
      [[ -x /usr/bin/hw-management-read-vr-model-version.sh ]] || Skip "requires /usr/bin/hw-management-read-vr-model-version.sh"
      When run bash -c "PATH='${TEST_BINDIR}':\"\$PATH\" DPC_TOOLS_PATHS='${repo_root}/usr/usr/bin' DEVTREE_FILE='${TEST_DEVTREE}' DPC_DEVTREE_PATH='${TEST_DEVTREE}' bash '${dpc_update}' '${TAR_PATH}' --verify"
      The status should be success
      The output should include "VERIFY PASSED."
    End
  End

  Describe 'debug output separation'
    It 'writes debug logs to stderr without contaminating JSON stdout'
      [[ -x /usr/bin/hw-management-read-vr-model-version.sh ]] || Skip "requires /usr/bin/hw-management-read-vr-model-version.sh"
      When run bash -c "PATH='${TEST_BINDIR}':\"\$PATH\" DPC_TOOLS_PATHS='${repo_root}/usr/usr/bin' DEVTREE_FILE='${TEST_DEVTREE}' DPC_DEBUG=1 bash '${dpc_update}' --show --json"
      The status should be success
      The output should start with "["
      The output should not include "DEBUG"
      The error should include "[DPC] DEBUG:"
    End
  End
End

