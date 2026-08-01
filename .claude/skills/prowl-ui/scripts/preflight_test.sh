#!/bin/bash

set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
preflight="$script_dir/preflight.sh"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/prowl-ui-preflight.XXXXXX")"
mock="$scratch/agent-ctrl"

cleanup() {
  /usr/bin/trash "$scratch" 2>/dev/null || true
}
trap cleanup EXIT

cat >"$mock" <<'EOF'
#!/bin/bash
case "${1:-}" in
  --version)
    printf 'agent-ctrl %s\n' "${MOCK_VERSION:-0.1.3}"
    ;;
  info)
    printf '%s\n' "${MOCK_INFO_JSON:-}"
    ;;
  doctor)
    printf '%s\n' "${MOCK_DOCTOR_JSON:-}"
    ;;
  *)
    exit 64
    ;;
esac
EOF
chmod +x "$mock"

failures=0
output=""
status=0

run_preflight() {
  set +e
  output="$(
    AGENT_CTRL_BIN="${AGENT_CTRL_BIN_OVERRIDE:-$mock}" \
      MOCK_VERSION="${MOCK_VERSION_OVERRIDE:-0.1.3}" \
      MOCK_INFO_JSON="${MOCK_INFO_OVERRIDE:-}" \
      MOCK_DOCTOR_JSON="${MOCK_DOCTOR_OVERRIDE:-}" \
      /bin/bash "$preflight" 2>&1
  )"
  status=$?
  set -e
}

assert_status() {
  local expected="$1"
  local name="$2"
  if [[ "$status" -ne "$expected" ]]; then
    printf 'FAIL %s: expected exit %s, got %s\n%s\n' "$name" "$expected" "$status" "$output"
    failures=$((failures + 1))
  fi
}

assert_json() {
  local filter="$1"
  local name="$2"
  if ! printf '%s\n' "$output" | jq -e "$filter" >/dev/null; then
    printf 'FAIL %s: output did not match %s\n%s\n' "$name" "$filter" "$output"
    failures=$((failures + 1))
  fi
}

AGENT_CTRL_BIN_OVERRIDE="$scratch/missing"
run_preflight
assert_status 2 "missing binary"
assert_json '.status == "SKIPPED" and .reason == "agent_ctrl_not_installed"' "missing binary"

AGENT_CTRL_BIN_OVERRIDE="$mock"
MOCK_VERSION_OVERRIDE="0.1.2"
run_preflight
assert_status 2 "old version"
assert_json '.status == "SKIPPED" and .reason == "unsupported_version" and .minimum_version == "0.1.3"' \
  "old version"

MOCK_VERSION_OVERRIDE="0.1.3"
MOCK_INFO_OVERRIDE='{"os":"macos","recommended_surface":"ax","surfaces":[{"kind":"ax","status":"ready"}],"macos_accessibility":"denied"}'
MOCK_DOCTOR_OVERRIDE='{"success":false,"checks":[{"id":"env.surface.ax","status":"pass"},{"id":"perm.accessibility","status":"fail"}]}'
run_preflight
assert_status 2 "accessibility denied"
assert_json '.status == "SKIPPED" and .reason == "accessibility_not_ready"' "accessibility denied"

MOCK_INFO_OVERRIDE='{"os":"macos","recommended_surface":"ax","surfaces":[{"kind":"ax","status":"ready"}],"macos_accessibility":"trusted"}'
MOCK_DOCTOR_OVERRIDE='{"success":true,"checks":[{"id":"env.surface.ax","status":"pass"},{"id":"perm.accessibility","status":"pass"}]}'
run_preflight
assert_status 0 "ready"
assert_json '.status == "READY" and .version == "0.1.3" and .surface == "ax"' "ready"

MOCK_VERSION_OVERRIDE="0.1.3+local"
run_preflight
assert_status 0 "build metadata version"
assert_json '.status == "READY" and .version == "0.1.3+local"' "build metadata version"

MOCK_DOCTOR_OVERRIDE='not-json'
run_preflight
assert_status 2 "invalid diagnostics"
assert_json '.status == "SKIPPED" and .reason == "diagnostics_unavailable"' "invalid diagnostics"

if [[ "$failures" -ne 0 ]]; then
  printf '%s preflight test(s) failed\n' "$failures"
  exit 1
fi

printf 'All prowl-ui preflight tests passed\n'
