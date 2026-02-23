#!/bin/bash
################################################################################
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the names of the copyright holders nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# Alternatively, this software may be distributed under the terms of the
# GNU General Public License ("GPL") version 2 as published by the Free
# Software Foundation.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
# VR DPC Update - Single Entrypoint Wrapper
#
# Installed path:
#   /usr/bin/hw-management-dpc-update.sh
#
# Usage:
#   hw-management-dpc-update.sh <pkg.tar.gz>          # update (default: skip-if-identical)
#   hw-management-dpc-update.sh --verify <pkg.tar.gz> # verify-only (no update)
#   hw-management-dpc-update.sh --force <pkg.tar.gz>  # bypass skip-if-identical
#   hw-management-dpc-update.sh --show [--json]       # show current versions
#
# Notes:
# - Flags can appear before/after the tar path.
# - Debug output must never contaminate stdout that callers parse:
#   set DPC_DEBUG=1 for stderr-only debug logs and bash -x reruns on failures.
# - Tar extraction is quiet by default; set DPC_VERBOSE=1 to print tar file lists.
#
# Tool lookup order (preferred first):
#   1) /usr/bin
#   2) $DPC_TOOLS_PATHS (colon-separated directories)
#
# Dependencies:
# - bash, tar, jq
# - for VR version readout: i2cget/i2cset and access to devtree (/var/run/hw-management/config/devtree)
################################################################################

# Ensure we're running under bash (OpenBMC images sometimes default to BusyBox sh/ash).
if [[ -z "${BASH_VERSION:-}" ]]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  echo "[DPC] ERROR: This script requires bash (not /bin/sh). 'bash' not found." >&2
  exit 1
fi

set -euo pipefail

LOG_PREFIX="[DPC]"

# Temp dir cleanup must be global: EXIT traps run after local vars go out of scope under `set -u`.
DPC_TMPDIR=""

die() {
  echo "${LOG_PREFIX} ERROR: $*" >&2
  exit 1
}

info() {
  echo "${LOG_PREFIX} $*"
}

debug() {
  if [[ "${DPC_DEBUG:-0}" == "1" ]]; then
    # IMPORTANT: debug must go to stderr so it never contaminates stdout that callers parse.
    echo "${LOG_PREFIX} DEBUG: $*" >&2
  fi
}

if [[ "${DPC_DEBUG:-0}" == "1" ]]; then
  debug "Debug logging enabled (DPC_DEBUG=1)"
  debug "DPC_TOOLS_PATHS=${DPC_TOOLS_PATHS:-}"
  debug "DPC_DEVTREE_PATH=${DPC_DEVTREE_PATH:-/var/run/hw-management/config/devtree}"
fi

usage() {
  cat >&2 <<'EOF'
Usage:
  hw-management-dpc-update.sh <dpc_pkg.tar.gz>
  hw-management-dpc-update.sh --show [--json]
  hw-management-dpc-update.sh [--force] [--verify] <dpc_pkg.tar.gz>

Options:
  --show             Print current VR model+revision information
  --json             With --show, output machine-readable JSON
  --force            Run update even if identical
  --verify           Verify prerequisites (pkg layout, JSON, scripts, I2C access) but do not update

Exit codes:
  0  Success (including "skipped: identical")
  1  Failure
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

_iter_tool_dirs() {
  # Echo candidate directories (one per line) in preference order:
  #  1) /usr/bin
  #  2) $DPC_TOOLS_PATHS (colon-separated)
  echo "/usr/bin"

  if [[ -n "${DPC_TOOLS_PATHS:-}" ]]; then
    local IFS=":"
    local d
    for d in $DPC_TOOLS_PATHS; do
      [[ -n "$d" ]] && echo "$d"
    done
  fi
}

find_tool() {
  # find_tool <filename>
  local name="$1"
  debug "find_tool name=$name"
  local d
  while read -r d; do
    [[ -n "$d" ]] || continue
    if [[ -f "$d/$name" ]]; then
      debug "find_tool hit: $d/$name"
      echo "$d/$name"
      return 0
    fi
  done < <(_iter_tool_dirs)
  debug "find_tool miss: $name"
  return 1
}

find_tool_candidates() {
  # find_tool_candidates <filename>
  # Prints matching full paths, one per line, in preference order.
  local name="$1"
  local d
  while read -r d; do
    [[ -n "$d" ]] || continue
    if [[ -f "$d/$name" ]]; then
      echo "$d/$name"
    fi
  done < <(_iter_tool_dirs)
}

realpath_fallback() {
  # Try realpath/readlink -f, otherwise best-effort absolute path.
  if command -v realpath >/dev/null 2>&1; then
    realpath "$1"
    return 0
  fi
  if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then
    readlink -f "$1"
    return 0
  fi
  case "$1" in
    /*) echo "$1" ;;
    *) echo "$(pwd -P)/$1" ;;
  esac
}

# Read simple VAR=VALUE assignment from a config file without executing it.
conf_get() {
  local file="$1"
  local var="$2"
  local default="${3:-}"
  local line
  line="$(grep -E "^[[:space:]]*${var}=" "$file" 2>/dev/null | tail -n 1 || true)"
  if [[ -z "$line" ]]; then
    echo "$default"
    return 0
  fi
  local val="${line#*=}"
  val="$(echo "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")"
  echo "$val"
}

csv_expected_for_page_cmd() {
  # Extract expected value from CSV for a given (page, cmd_code).
  # CSV format (as used by hw-management-vr-dpc-update.sh):
  # dev_addr,cmd_code,wr,p0_name,p0_byte,p0_val,p1_name,p1_byte,p1_val,p2_name,p2_byte,p2_val
  local csv_file="$1"
  local page="$2"
  local cmd_code="$3" # e.g. 0xbb

  local val_col
  case "$page" in
    0) val_col=6 ;;
    1) val_col=9 ;;
    2) val_col=12 ;;
    *) return 1 ;;
  esac

  awk -F',' -v cmd="$cmd_code" -v col="$val_col" '
    NR==1 { next }
    {
      c=tolower($2)
      if (c==tolower(cmd)) {
        v=$col
        gsub(/\r/,"",v)
        v=tolower(substr(v,1,6))
        print v
        exit
      }
    }
  ' "$csv_file"
}

show_cmd() {
  local json=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *)
        die "Unknown option for show: $1"
        ;;
    esac
  done

  local read_vr="/usr/bin/hw-management-read-vr-model-version.sh"
  [[ -f "$read_vr" ]] || die "Missing required read-vr script: $read_vr"

  if [[ $json -eq 1 ]]; then
    # Must output clean JSON to stdout.
    exec bash "$read_vr" --show --json
  else
    exec bash "$read_vr" --show
  fi
}

apply_cmd() {
  local skip_identical=1
  local verify_only=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      # Backwards-compat alias (default behavior). Kept to avoid breaking older automation.
      --skip-identical) shift ;;
      --force) skip_identical=0; shift ;;
      --verify) verify_only=1; shift ;;
      -h|--help) usage; exit 0 ;;
      --) shift; break ;;
      -*)
        die "Unknown option: $1"
        ;;
      *)
        break
        ;;
    esac
  done

  [[ $# -eq 1 ]] || die "Expected exactly one package tar.gz path"
  local pkg_path
  pkg_path="$(realpath_fallback "$1")"
  [[ -f "$pkg_path" ]] || die "Package not found: $pkg_path"
  debug "apply pkg_path=$pkg_path"

  need_cmd tar
  need_cmd jq

  build_targets_tsv() {
    # Emit TSV lines:
    #   bus<TAB>devtype<TAB>addr<TAB>exp_model<TAB>exp_rev
    local pkg_dir="$1"
    local json_cfg="$2" # filename inside pkg_dir

    jq -r '.Devices[] | [.Bus, .DeviceType, .ConfigFile, .DeviceConfigFile] | @tsv' "${pkg_dir}/${json_cfg}" | \
    while IFS=$'\t' read -r bus devtype cfg cfgconf; do
      [[ -n "$bus" && -n "$devtype" ]] || continue

      if [[ "$cfg" != /* ]]; then cfg="${pkg_dir}/${cfg}"; fi
      if [[ "$cfgconf" != /* ]]; then cfgconf="${pkg_dir}/${cfgconf}"; fi

      local model_reg rev_reg model_page rev_page
      model_reg="$(conf_get "$cfgconf" DPC_MODEL_ID 0xba)"
      rev_reg="$(conf_get "$cfgconf" DPC_REVISION_ID 0xbb)"
      model_page="$(conf_get "$cfgconf" DPC_MODEL_ID_PAGE 1)"
      rev_page="$(conf_get "$cfgconf" DPC_REVISION_ID_PAGE 1)"

      # Device I2C address comes from the CSV (first column of first data row).
      local addr
      addr="$(
        awk -F',' '
          NR==1 { next }
          {
            a=$1
            gsub(/\r/,"",a)
            gsub(/^[[:space:]]+|[[:space:]]+$/,"",a)
            if (a!="") { print tolower(a); exit }
          }
        ' "$cfg"
      )"

      local exp_model exp_rev
      exp_model="$(csv_expected_for_page_cmd "$cfg" "$model_page" "$model_reg")"
      exp_rev="$(csv_expected_for_page_cmd "$cfg" "$rev_page" "$rev_reg")"

      echo -e "${bus}\t${devtype}\t${addr}\t${exp_model}\t${exp_rev}"
    done
  }

  print_verify_summary() {
    local pkg_dir="$1"
    local json_cfg="$2"

    info "Reading current VR versions..."
    local current_json
    current_json="$(read_vr_json_or_die "$pkg_dir")"

    info "Deriving target VR versions from package..."
    local targets
    targets="$(build_targets_tsv "$pkg_dir" "$json_cfg")"

    echo ""
    echo "[DPC] VERIFY SUMMARY"
    printf "%-6s %-8s %-12s %-16s %-16s %-16s %-16s %-8s\n" "BUS" "ADDR" "DEVTYPE" "CUR_MODEL" "CUR_REV" "TGT_MODEL" "TGT_REV" "STATUS"
    printf "%-6s %-8s %-12s %-16s %-16s %-16s %-16s %-8s\n" "======" "========" "============" "================" "================" "================" "================" "========"

    local mismatch=0
    while IFS=$'\t' read -r bus devtype addr exp_model exp_rev; do
      [[ -n "$bus" && -n "$devtype" ]] || continue

      local cur_model cur_rev
      cur_model="$(echo "$current_json" | jq -r --arg bus "$bus" --arg dev "$devtype" --arg addr "${addr:-}" '
        def norm(x): (x|tostring|ascii_downcase);
        if ($addr|length)>0 then
          (first(.[] | select(.bus==($bus|tostring) and .device_name==$dev and norm(.address)==norm($addr)) | .model) // empty)
        else
          (first(.[] | select(.bus==($bus|tostring) and .device_name==$dev) | .model) // empty)
        end
      ')"
      cur_rev="$(echo "$current_json" | jq -r --arg bus "$bus" --arg dev "$devtype" --arg addr "${addr:-}" '
        def norm(x): (x|tostring|ascii_downcase);
        if ($addr|length)>0 then
          (first(.[] | select(.bus==($bus|tostring) and .device_name==$dev and norm(.address)==norm($addr)) | .revision_id) // empty)
        else
          (first(.[] | select(.bus==($bus|tostring) and .device_name==$dev) | .revision_id) // empty)
        end
      ')"

      local status="OK"
      if [[ -z "$cur_model" || -z "$cur_rev" ]]; then
        status="NO_CUR"
        mismatch=1
      elif [[ -z "${exp_model:-}" || -z "${exp_rev:-}" ]]; then
        status="NO_TGT"
        mismatch=1
      else
        # Normalize
        local n_cur_model n_cur_rev n_exp_model n_exp_rev
        n_cur_model="$(echo "$cur_model" | tr '[:upper:]' '[:lower:]')"
        n_cur_rev="$(echo "$cur_rev" | tr '[:upper:]' '[:lower:]')"
        n_exp_model="$(echo "${exp_model:-}" | tr '[:upper:]' '[:lower:]')"
        n_exp_rev="$(echo "${exp_rev:-}" | tr '[:upper:]' '[:lower:]')"
        if [[ "$n_cur_model" != "$n_exp_model" || "$n_cur_rev" != "$n_exp_rev" ]]; then
          status="DIFF"
          mismatch=1
        fi
      fi

      printf "%-6s %-8s %-12s %-16s %-16s %-16s %-16s %-8s\n" \
        "$bus" "${addr:-}" "$devtype" "${cur_model:-}" "${cur_rev:-}" "${exp_model:-}" "${exp_rev:-}" "$status"
    done <<< "$targets"

    echo ""
    if [[ $mismatch -eq 0 ]]; then
      info "VERIFY RESULT: All targets match current model+revision. Default behavior is to SKIP the update."
      info "VERIFY NOTE: Use --force to run the update anyway."
    else
      info "VERIFY RESULT: New revisions are available in the package"
    fi
    echo ""
  }

  read_vr_json_or_die() {
    # Use only the system-installed read-vr script.
    # Hard requirement: it must support --show --json and produce valid JSON.
    local read_vr="/usr/bin/hw-management-read-vr-model-version.sh"
    [[ -f "$read_vr" ]] || die "Missing required read-vr script: $read_vr"

    local out
    out="$(bash "$read_vr" --show --json)" || die "read-vr failed: $read_vr --show --json"
    echo "$out" | jq empty >/dev/null 2>&1 || die "read-vr did not return valid JSON"
    echo "$out"
  }

  verify_i2c_access() {
    # This performs a real I2C read via the read-vr script.
    # It will i2cset PAGE and i2cget model/revision from devices described by devtree.
    local devtree="${DPC_DEVTREE_PATH:-/var/run/hw-management/config/devtree}"

    need_cmd i2cget
    need_cmd i2cset
    [[ -r "$devtree" ]] || die "Missing or unreadable devtree: $devtree"

    # Check device nodes exist for buses in devtree (best effort)
    local buses
    buses="$(awk '{print $3}' "$devtree" 2>/dev/null | grep -E '^[0-9]+$' | sort -n | uniq || true)"
    if [[ -n "$buses" ]]; then
      while read -r b; do
        [[ -n "$b" ]] || continue
        if [[ ! -e "/dev/i2c-$b" ]]; then
          die "Missing I2C device node: /dev/i2c-$b (from devtree)"
        fi
        if [[ ! -r "/dev/i2c-$b" || ! -w "/dev/i2c-$b" ]]; then
          die "Insufficient permissions for /dev/i2c-$b (need read+write)"
        fi
      done <<< "$buses"
    fi

    info "Verifying I2C access..."
    local out
    out="$(read_vr_json_or_die)"
    echo "$out" | jq empty >/dev/null 2>&1 || die "read-vr did not return valid JSON"
    # Require at least one entry and at least one non-N/A read to consider I2C accessible.
    local count_ok
    count_ok="$(echo "$out" | jq '[.[] | select(.model!="N/A" and .revision_id!="N/A")] | length')"
    [[ "$count_ok" =~ ^[0-9]+$ ]] || die "Unexpected JSON from internal read"
    [[ "$count_ok" -gt 0 ]] || die "I2C access check failed: no readable VR model/revision values"
    info "I2C access OK (readable VR model/revision values found)."
  }

  verify_package() {
    local pkg_path="$1"
    local tmp="$2"

    validate_json_config_pkg() {
      # Validate JSON config structure and referenced files (similar to hw-management-vr-dpc-update-all.sh --validate-json)
      # Paths are resolved relative to pkg_dir when not absolute.
      local pkg_dir="$1"
      local json_cfg="$2"
      local json_file="${pkg_dir}/${json_cfg}"

      local errors=0

      jq empty "$json_file" >/dev/null 2>&1 || { info "ERROR: Invalid JSON syntax: $json_file"; return 1; }

      local system_hid
      system_hid="$(jq -r '."System HID" // empty' "$json_file")"
      if [[ -z "$system_hid" ]]; then
        info "ERROR: JSON missing 'System HID'"
        errors=$((errors + 1))
      elif [[ ! "$system_hid" =~ ^[Hh][Ii]([Dd])?[0-9]{3}$ ]]; then
        info "ERROR: Invalid 'System HID' format (expected HI### or HID###): $system_hid"
        errors=$((errors + 1))
      fi

      local devices_type
      devices_type="$(jq -r '.Devices | type // empty' "$json_file" 2>/dev/null || true)"
      if [[ "$devices_type" != "array" ]]; then
        info "ERROR: JSON missing 'Devices' array"
        return 1
      fi

      local num_devices
      num_devices="$(jq -r '.Devices | length // 0' "$json_file")"
      [[ "$num_devices" =~ ^[0-9]+$ ]] || num_devices=0

      local i=0
      while [[ $i -lt $num_devices ]]; do
        local device_type bus config_file crc_file device_config_file
        device_type="$(jq -r ".Devices[$i].DeviceType // empty" "$json_file")"
        bus="$(jq -r ".Devices[$i].Bus // empty" "$json_file")"
        config_file="$(jq -r ".Devices[$i].ConfigFile // empty" "$json_file")"
        crc_file="$(jq -r ".Devices[$i].CrcFile // empty" "$json_file")"
        device_config_file="$(jq -r ".Devices[$i].DeviceConfigFile // empty" "$json_file")"

        if [[ -z "$device_type" ]]; then
          info "ERROR: Devices[$i] missing DeviceType"
          errors=$((errors + 1))
        fi
        if [[ -z "$bus" || ! "$bus" =~ ^[0-9]+$ ]]; then
          info "ERROR: Devices[$i] invalid Bus: '${bus}'"
          errors=$((errors + 1))
        fi
        if [[ -z "$config_file" ]]; then
          info "ERROR: Devices[$i] missing ConfigFile"
          errors=$((errors + 1))
        fi
        if [[ -z "$crc_file" ]]; then
          info "ERROR: Devices[$i] missing CrcFile"
          errors=$((errors + 1))
        fi
        if [[ -z "$device_config_file" ]]; then
          info "ERROR: Devices[$i] missing DeviceConfigFile"
          errors=$((errors + 1))
        fi

        # Resolve and verify files exist when provided
        if [[ -n "$config_file" ]]; then
          [[ "$config_file" != /* ]] && config_file="${pkg_dir}/${config_file}"
          [[ -f "$config_file" ]] || { info "ERROR: Devices[$i] ConfigFile not found: $config_file"; errors=$((errors + 1)); }
        fi
        if [[ -n "$crc_file" ]]; then
          [[ "$crc_file" != /* ]] && crc_file="${pkg_dir}/${crc_file}"
          [[ -f "$crc_file" ]] || { info "ERROR: Devices[$i] CrcFile not found: $crc_file"; errors=$((errors + 1)); }
        fi
        if [[ -n "$device_config_file" ]]; then
          [[ "$device_config_file" != /* ]] && device_config_file="${pkg_dir}/${device_config_file}"
          [[ -f "$device_config_file" ]] || { info "ERROR: Devices[$i] DeviceConfigFile not found: $device_config_file"; errors=$((errors + 1)); }
        fi

        i=$((i + 1))
      done

      if [[ $errors -ne 0 ]]; then
        info "ERROR: Package JSON validation failed ($errors error(s))"
        return 1
      fi

      info "Package JSON validation OK (${num_devices} device(s))"
      return 0
    }

    # Verify tar can be listed and top dir detected
    tar -tf "$pkg_path" >/dev/null 2>&1 || die "Cannot read tar contents: $pkg_path"
    local top_dir
    top_dir="$(tar -tf "$pkg_path" | awk -F/ 'NR==1{print $1}')"
    [[ -n "$top_dir" ]] || die "Could not detect top-level directory inside tar"

    # Extract for deeper validation
    if [[ "${DPC_VERBOSE:-0}" == "1" ]]; then
      tar -xvf "$pkg_path" -C "$tmp"
    else
      tar -xf "$pkg_path" -C "$tmp" >/dev/null 2>&1
    fi
    local pkg_dir="${tmp}/${top_dir}"
    [[ -d "$pkg_dir" ]] || die "Extracted top-level directory not found: $pkg_dir"
    debug "verify extracted pkg_dir=$pkg_dir"

    # Find JSON config
    local json_cfg="dpc_rosalind.json"
    if [[ ! -f "${pkg_dir}/${json_cfg}" ]]; then
      local _jsons=()
      ( shopt -s nullglob; cd "$pkg_dir" && _jsons=( *.json ) && printf '%s\n' "${_jsons[0]-}" ) >"${tmp}/.json_pick" || true
      json_cfg="$(cat "${tmp}/.json_pick" 2>/dev/null || true)"
    fi
    [[ -n "$json_cfg" && -f "${pkg_dir}/${json_cfg}" ]] || die "JSON configuration file not found in package dir"
    debug "verify json_cfg=$json_cfg"
    validate_json_config_pkg "$pkg_dir" "$json_cfg" || die "JSON validation failed"

    # Ensure per-device updater exists (/usr/bin preferred, then $DPC_TOOLS_PATHS)
    if ! find_tool hw-management-vr-dpc-update.sh >/dev/null 2>&1; then
      die "Missing hw-management-vr-dpc-update.sh (searched /usr/bin and \$DPC_TOOLS_PATHS)"
    fi

    VERIFIED_PKG_DIR="$pkg_dir"
    VERIFIED_JSON_CFG="$json_cfg"
    info "Package verify OK (top_dir=$top_dir, json=$json_cfg)."
  }

  # Run a batch update directly from a JSON config file (similar to hw-management-vr-dpc-update-all.sh)
  # using the per-device updater script shipped in the extracted package directory.
  run_update_from_json() {
    local pkg_dir="$1"
    local json_file="$2"

    [[ -f "$json_file" ]] || die "JSON configuration file not found: $json_file"
    jq empty "$json_file" >/dev/null 2>&1 || die "Invalid JSON syntax: $json_file"

    local system_hid
    system_hid="$(jq -r '."System HID" // empty' "$json_file")"
    [[ -n "$system_hid" ]] || die "Missing 'System HID' in JSON configuration"
    # Accept both HI### and HID### (legacy variants); normalize to hid### (what the per-device updater expects).
    [[ "$system_hid" =~ ^[Hh][Ii]([Dd])?[0-9]{3}$ ]] || die "Invalid 'System HID' format (expected HI### or HID###): $system_hid"
    local system_hid_lower
    system_hid_lower="$(echo "$system_hid" | tr '[:upper:]' '[:lower:]' | sed -E 's/^hi(d)?/hid/')"

    local updater
    updater="$(find_tool hw-management-vr-dpc-update.sh)" || die "Per-device updater not found (searched /usr/bin and \$DPC_TOOLS_PATHS): hw-management-vr-dpc-update.sh"
    debug "updater selected: $updater"

    local num_devices
    num_devices="$(jq -r '.Devices | length // 0' "$json_file")"
    [[ "$num_devices" =~ ^[0-9]+$ ]] || die "Invalid '.Devices' array length in JSON"

    info "Applying update from JSON (System HID: $system_hid, Devices: $num_devices)"

    local ok=0
    local fail=0

    local i=0
    while [[ $i -lt $num_devices ]]; do
      local device_type bus config_file crc_file device_config_file
      device_type="$(jq -r ".Devices[$i].DeviceType // empty" "$json_file")"
      bus="$(jq -r ".Devices[$i].Bus // empty" "$json_file")"
      config_file="$(jq -r ".Devices[$i].ConfigFile // empty" "$json_file")"
      crc_file="$(jq -r ".Devices[$i].CrcFile // empty" "$json_file")"
      device_config_file="$(jq -r ".Devices[$i].DeviceConfigFile // empty" "$json_file")"

      if [[ -z "$device_type" || -z "$bus" || -z "$config_file" || -z "$crc_file" || -z "$device_config_file" ]]; then
        info "ERROR: JSON device[$i] is missing required fields (DeviceType/Bus/ConfigFile/CrcFile/DeviceConfigFile)"
        fail=$((fail + 1))
        i=$((i + 1))
        continue
      fi
      [[ "$bus" =~ ^[0-9]+$ ]] || { info "ERROR: JSON device[$i] Bus is not numeric: $bus"; fail=$((fail + 1)); i=$((i + 1)); continue; }

      # Resolve relative file paths within the package directory.
      if [[ "$config_file" != /* ]]; then config_file="${pkg_dir}/${config_file}"; fi
      if [[ "$crc_file" != /* ]]; then crc_file="${pkg_dir}/${crc_file}"; fi
      if [[ "$device_config_file" != /* ]]; then device_config_file="${pkg_dir}/${device_config_file}"; fi

      [[ -f "$config_file" ]] || { info "ERROR: Missing ConfigFile for device[$i]: $config_file"; fail=$((fail + 1)); i=$((i + 1)); continue; }
      [[ -f "$crc_file" ]] || { info "ERROR: Missing CrcFile for device[$i]: $crc_file"; fail=$((fail + 1)); i=$((i + 1)); continue; }
      [[ -f "$device_config_file" ]] || { info "ERROR: Missing DeviceConfigFile for device[$i]: $device_config_file"; fail=$((fail + 1)); i=$((i + 1)); continue; }

      info "Updating device[$i]: Type=$device_type Bus=$bus"
      local cmd=(
        bash "$updater"
        "$bus"
        "$device_type"
        "$system_hid_lower"
        "$config_file"
        "$crc_file"
        "$device_config_file"
      )

      if "${cmd[@]}"; then
        ok=$((ok + 1))
      else
        local rc=$?
        info "ERROR: Update failed for device[$i]: Type=$device_type Bus=$bus"
        info "ERROR: rc=$rc (updater may log details to syslog via logger)"
        if [[ "${DPC_DEBUG:-0}" == "1" ]]; then
          info "DEBUG: Re-running failed device[$i] with 'bash -x' (may be verbose)..."
          ( set +e; bash -x "$updater" "$bus" "$device_type" "$system_hid_lower" "$config_file" "$crc_file" "$device_config_file" ) || true
        fi
        fail=$((fail + 1))
      fi

      i=$((i + 1))
    done

    info "Batch summary: ok=$ok failed=$fail"
    [[ $fail -eq 0 ]] || return 1
    return 0
  }

  stop_health_services_if_possible() {
    # Best-effort stop to avoid concurrent access to VRs on SONiC.
    # On systems without systemd/systemctl (e.g., some BMC images), this is a no-op.
    if ! command -v systemctl >/dev/null 2>&1; then
      info "Service stop: systemctl not found; skipping service stop."
      return 0
    fi

    local stopped_any=0
    for svc in health-statsd.service system-health.service; do
      if systemctl is-active --quiet "$svc" 2>/dev/null; then
        info "Stopping service: $svc"
        systemctl stop "$svc" >/dev/null 2>&1 || true
        stopped_any=1
      fi
    done

    if [[ $stopped_any -eq 1 ]]; then
      info "Services stopped."
    else
      info "Service stop: nothing active to stop."
    fi
  }

  print_vr_versions_table() {
    # Print a compact table from read-vr JSON.
    local label="$1" # e.g. BEFORE/AFTER
    local json="$2"
    echo ""
    echo "[DPC] VR versions ${label}:"
    printf "%-6s %-8s %-12s %-16s %-16s\n" "BUS" "ADDR" "DEVTYPE" "MODEL" "REV"
    printf "%-6s %-8s %-12s %-16s %-16s\n" "======" "========" "============" "================" "================"
    echo "$json" | jq -r '.[] | [.bus, .address, .device_name, .model, .revision_id] | @tsv' | \
      while IFS=$'\t' read -r bus addr dev model rev; do
        printf "%-6s %-8s %-12s %-16s %-16s\n" "$bus" "$addr" "$dev" "$model" "$rev"
      done
    echo ""
  }

  local tmp
  # mktemp flags differ across implementations (GNU vs BusyBox).
  tmp="$(
    mktemp -d 2>/dev/null || \
    mktemp -d -t dpc-fw-XXXXXX 2>/dev/null || \
    mktemp -d "/tmp/dpc-fw.XXXXXX" 2>/dev/null
  )"
  [[ -n "$tmp" ]] || die "mktemp failed (no usable mktemp implementation?)"
  DPC_TMPDIR="$tmp"
  trap '[[ -n "${DPC_TMPDIR:-}" ]] && rm -rf "$DPC_TMPDIR"' EXIT
  debug "tmpdir=$tmp"

  if [[ $verify_only -eq 1 ]]; then
    info "Verify mode: checking prerequisites only."
    VERIFIED_PKG_DIR=""
    VERIFIED_JSON_CFG=""
    verify_package "$pkg_path" "$tmp"
    verify_i2c_access "$VERIFIED_PKG_DIR"
    print_verify_summary "$VERIFIED_PKG_DIR" "$VERIFIED_JSON_CFG"
    info "VERIFY PASSED."
    exit 0
  fi

  info "Extracting package: $pkg_path"
  if [[ "${DPC_VERBOSE:-0}" == "1" ]]; then
    tar -xvf "$pkg_path" -C "$tmp"
  else
    tar -xf "$pkg_path" -C "$tmp" >/dev/null 2>&1
  fi

  local top_dir
  top_dir="$(tar -tf "$pkg_path" | awk -F/ 'NR==1{print $1}')"
  [[ -n "$top_dir" ]] || die "Could not detect top-level directory inside tar"

  local pkg_dir="${tmp}/${top_dir}"
  [[ -d "$pkg_dir" ]] || die "Extracted top-level directory not found: $pkg_dir"
  debug "apply extracted pkg_dir=$pkg_dir"

  # Find JSON config inside package
  local json_cfg="dpc_rosalind.json"
  if [[ ! -f "${pkg_dir}/${json_cfg}" ]]; then
    local _jsons=()
    ( shopt -s nullglob; cd "$pkg_dir" && _jsons=( *.json ) && printf '%s\n' "${_jsons[0]-}" ) >"${tmp}/.json_pick" || true
    json_cfg="$(cat "${tmp}/.json_pick" 2>/dev/null || true)"
  fi
  [[ -n "$json_cfg" && -f "${pkg_dir}/${json_cfg}" ]] || die "JSON configuration file not found in package dir"
  debug "apply json_cfg=$json_cfg"

  if [[ $skip_identical -eq 1 ]]; then
    info "Checking current vs package targets..."
    local current_json
    current_json="$(read_vr_json_or_die)"

      local targets
      targets="$(build_targets_tsv "$pkg_dir" "$json_cfg")"

      local mismatch=0
      while IFS=$'\t' read -r bus devtype addr exp_model exp_rev; do
        [[ -n "$bus" && -n "$devtype" ]] || continue

        local cur_model cur_rev
        cur_model="$(echo "$current_json" | jq -r --arg bus "$bus" --arg dev "$devtype" --arg addr "${addr:-}" '
          def norm(x): (x|tostring|ascii_downcase);
          if ($addr|length)>0 then
            (first(.[] | select(.bus==($bus|tostring) and .device_name==$dev and norm(.address)==norm($addr)) | .model) // empty)
          else
            (first(.[] | select(.bus==($bus|tostring) and .device_name==$dev) | .model) // empty)
          end
        ')"
        cur_rev="$(echo "$current_json" | jq -r --arg bus "$bus" --arg dev "$devtype" --arg addr "${addr:-}" '
          def norm(x): (x|tostring|ascii_downcase);
          if ($addr|length)>0 then
            (first(.[] | select(.bus==($bus|tostring) and .device_name==$dev and norm(.address)==norm($addr)) | .revision_id) // empty)
          else
            (first(.[] | select(.bus==($bus|tostring) and .device_name==$dev) | .revision_id) // empty)
          end
        ')"

        if [[ -z "$cur_model" || -z "$cur_rev" ]]; then
          info "WARN: Could not find current entry for DeviceType=$devtype Bus=$bus Addr=${addr:-} (will NOT skip)"
          mismatch=1
          continue
        fi

        cur_model="$(echo "$cur_model" | tr '[:upper:]' '[:lower:]')"
        cur_rev="$(echo "$cur_rev" | tr '[:upper:]' '[:lower:]')"
        exp_model="$(echo "${exp_model:-}" | tr '[:upper:]' '[:lower:]')"
        exp_rev="$(echo "${exp_rev:-}" | tr '[:upper:]' '[:lower:]')"

        if [[ -z "$exp_model" || -z "$exp_rev" ]]; then
          info "WARN: Could not parse expected model/revision from package for DeviceType=$devtype Bus=$bus (will NOT skip)"
          mismatch=1
          continue
        fi

        if [[ "$cur_model" != "$exp_model" || "$cur_rev" != "$exp_rev" ]]; then
          info "Needs update: DeviceType=$devtype Bus=$bus current(model=$cur_model rev=$cur_rev) target(model=$exp_model rev=$exp_rev)"
          mismatch=1
        else
          info "Up-to-date: DeviceType=$devtype Bus=$bus model=$cur_model rev=$cur_rev"
        fi
      done <<< "$targets"

    if [[ $mismatch -eq 0 ]]; then
      info "No changes needed. Skipping update."
      exit 0
    fi
  fi

  # Show versions before update and stop services (best-effort) before flashing.
  local vr_before
  vr_before="$(read_vr_json_or_die)"
  print_vr_versions_table "BEFORE update" "$vr_before"

  stop_health_services_if_possible

  info "Running package update (from JSON via per-device updater)..."
  run_update_from_json "$pkg_dir" "${pkg_dir}/${json_cfg}"

  # Show versions after update for quick confirmation.
  local vr_after
  vr_after="$(read_vr_json_or_die)"
  print_vr_versions_table "AFTER update" "$vr_after"

  info "Update completed."
  info "NOTE: Reboot (or AC cycle) is required to fully apply DPC changes."
}

main() {
  [[ $# -ge 1 ]] || { usage; exit 1; }

  local show=0
  local json=0
  local force=0
  local verify=0
  local pkg=""

  # Parse flags anywhere; allow exactly one positional arg (the tar path).
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --show) show=1; shift ;;
      --json) json=1; shift ;;
      --force) force=1; shift ;;
      --verify) verify=1; shift ;;
      # Backwards-compat alias (no-op)
      --skip-identical) shift ;;
      -h|--help|help) usage; exit 0 ;;
      --) shift; break ;;
      -*)
        die "Unknown option: $1"
        ;;
      *)
        if [[ -n "$pkg" ]]; then
          die "Expected exactly one package tar.gz path"
        fi
        pkg="$1"
        shift
        ;;
    esac
  done

  # Any args after -- are treated as positional (at most one).
  while [[ $# -gt 0 ]]; do
    if [[ -n "$pkg" ]]; then
      die "Expected exactly one package tar.gz path"
    fi
    pkg="$1"
    shift
  done

  if [[ $show -eq 1 ]]; then
    # For show mode, only --json is meaningful and no package path is allowed.
    if [[ -n "$pkg" || $force -eq 1 || $verify -eq 1 ]]; then
      die "--show does not take a package path and cannot be combined with --force/--verify"
    fi
    if [[ $json -eq 1 ]]; then
      show_cmd --json
    else
      show_cmd
    fi
    exit $?
  fi

  # Apply mode (default): require exactly one package path.
  [[ $json -eq 0 ]] || die "--json is only valid with --show"
  [[ -n "$pkg" ]] || die "Expected exactly one package tar.gz path"

  local apply_args=()
  if [[ $force -eq 1 ]]; then apply_args+=(--force); fi
  if [[ $verify -eq 1 ]]; then apply_args+=(--verify); fi
  apply_cmd "${apply_args[@]}" "$pkg"
  exit $?
}

main "$@"

