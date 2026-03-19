# Common test helpers for gmail-await tests

GMAIL_AWAIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/gmail-await"
FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures"

_common_setup() {
  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'

  export GMAIL_AWAIT_POLL_INTERVAL=0

  # Create mock directories
  export MOCK_DIR="$BATS_TEST_TMPDIR/mock"
  export MOCK_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$MOCK_DIR" "$MOCK_BIN"

  # Create the mock gws script
  cat > "$MOCK_BIN/gws" <<'MOCK_SCRIPT'
#!/usr/bin/env bash

# Determine endpoint from arguments
endpoint=""
if [[ "$*" == *"getProfile"* ]]; then
  endpoint="profile"
elif [[ "$*" == *"history list"* ]]; then
  endpoint="history"
elif [[ "$*" == *"messages get"* ]]; then
  endpoint="message"
fi

if [[ -z "$endpoint" ]]; then
  echo "mock gws: unknown command: $*" >&2
  exit 1
fi

# Increment per-endpoint call counter
counter_file="${MOCK_DIR}/${endpoint}_count"
count=$(cat "$counter_file" 2>/dev/null || echo 0)
count=$((count + 1))
echo "$count" > "$counter_file"

# Check for failure on this specific call
if [[ -f "${MOCK_DIR}/${endpoint}_fail_${count}" ]]; then
  echo '{"error": {"code": 404, "message": "Not found"}}' >&2
  exit 1
fi

# Check for global failure
if [[ -f "${MOCK_DIR}/${endpoint}_fail" ]]; then
  echo '{"error": {"code": 500, "message": "Server error"}}' >&2
  exit 1
fi

# Return response for this specific call, or fall back to default
response_file="${MOCK_DIR}/${endpoint}_response_${count}.json"
if [[ ! -f "$response_file" ]]; then
  response_file="${MOCK_DIR}/${endpoint}_response.json"
fi

if [[ -f "$response_file" ]]; then
  cat "$response_file"
else
  echo "{}"
fi
MOCK_SCRIPT
  chmod +x "$MOCK_BIN/gws"

  # Prepend mock bin to PATH
  export PATH="$MOCK_BIN:$PATH"
}

# --- Mock configuration helpers ---

# Configure the default profile response
mock_gws_profile() {
  cp "$1" "$MOCK_DIR/profile_response.json"
}

# Make all profile calls fail
mock_gws_profile_fail() {
  touch "$MOCK_DIR/profile_fail"
}

# Configure history response for the nth call
mock_gws_history() {
  local call_number="$1"
  local fixture="$2"
  cp "$fixture" "$MOCK_DIR/history_response_${call_number}.json"
}

# Configure default history response (used when no call-specific response exists)
mock_gws_history_default() {
  cp "$1" "$MOCK_DIR/history_response.json"
}

# Make the nth history call fail
mock_gws_history_fail() {
  local call_number="$1"
  touch "$MOCK_DIR/history_fail_${call_number}"
}

# Configure the default message response
mock_gws_message() {
  cp "$1" "$MOCK_DIR/message_response.json"
}

# Configure message response for the nth call
mock_gws_message_nth() {
  local call_number="$1"
  local fixture="$2"
  cp "$fixture" "$MOCK_DIR/message_response_${call_number}.json"
}

# Make the nth message call fail
mock_gws_message_fail() {
  local call_number="$1"
  touch "$MOCK_DIR/message_fail_${call_number}"
}
