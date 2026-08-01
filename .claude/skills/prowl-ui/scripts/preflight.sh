#!/bin/bash

set -u
set -o pipefail

minimum_version="0.1.3"

skip() {
  local reason="$1"
  local version="${2:-}"

  if command -v jq >/dev/null 2>&1; then
    jq -cn \
      --arg reason "$reason" \
      --arg version "$version" \
      --arg minimum_version "$minimum_version" \
      '{status: "SKIPPED", reason: $reason}
       + (if $version == "" then {} else {version: $version} end)
       + (if $reason == "unsupported_version" then {minimum_version: $minimum_version} else {} end)'
  else
    printf '{"status":"SKIPPED","reason":"%s"}\n' "$reason"
  fi
  exit 2
}

version_is_supported() {
  local candidate="$1"
  local minimum="$2"
  local candidate_major candidate_minor candidate_patch
  local minimum_major minimum_minor minimum_patch

  candidate="${candidate%%-*}"
  candidate="${candidate%%+*}"
  IFS=. read -r candidate_major candidate_minor candidate_patch <<<"$candidate"
  IFS=. read -r minimum_major minimum_minor minimum_patch <<<"$minimum"

  [[ "$candidate_major" =~ ^[0-9]+$ && "$candidate_minor" =~ ^[0-9]+$ && "$candidate_patch" =~ ^[0-9]+$ ]] ||
    return 1

  ((candidate_major > minimum_major)) && return 0
  ((candidate_major < minimum_major)) && return 1
  ((candidate_minor > minimum_minor)) && return 0
  ((candidate_minor < minimum_minor)) && return 1
  ((candidate_patch >= minimum_patch))
}

if ! command -v jq >/dev/null 2>&1; then
  skip "json_parser_not_installed"
fi

if [[ -n "${AGENT_CTRL_BIN:-}" ]]; then
  agent_ctrl="$AGENT_CTRL_BIN"
  [[ -x "$agent_ctrl" ]] || skip "agent_ctrl_not_installed"
else
  agent_ctrl="$(command -v agent-ctrl 2>/dev/null || true)"
  [[ -n "$agent_ctrl" && -x "$agent_ctrl" ]] || skip "agent_ctrl_not_installed"
fi

version_output="$("$agent_ctrl" --version 2>/dev/null || true)"
if [[ "$version_output" =~ ([0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?) ]]; then
  version="${BASH_REMATCH[1]}"
else
  skip "version_unavailable"
fi

version_is_supported "$version" "$minimum_version" || skip "unsupported_version" "$version"

info_json="$("$agent_ctrl" info --json 2>/dev/null || true)"
doctor_json="$("$agent_ctrl" doctor --json --quick 2>/dev/null || true)"

if ! jq -e . >/dev/null 2>&1 <<<"$info_json" || ! jq -e . >/dev/null 2>&1 <<<"$doctor_json"; then
  skip "diagnostics_unavailable" "$version"
fi

info_ready="$(
  jq -r '
    .os == "macos"
      and .recommended_surface == "ax"
      and .macos_accessibility == "trusted"
      and any(.surfaces[]?; .kind == "ax" and .status == "ready")
  ' <<<"$info_json"
)"
doctor_ready="$(
  jq -r '
    .success == true
      and any(.checks[]?; .id == "env.surface.ax" and .status == "pass")
      and any(.checks[]?; .id == "perm.accessibility" and .status == "pass")
  ' <<<"$doctor_json"
)"

if [[ "$info_ready" != "true" || "$doctor_ready" != "true" ]]; then
  skip "accessibility_not_ready" "$version"
fi

jq -cn \
  --arg binary "$agent_ctrl" \
  --arg version "$version" \
  '{status: "READY", binary: $binary, version: $version, surface: "ax"}'
