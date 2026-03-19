#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  load 'test_helper/common'
  _common_setup
}

# =============================================================================
# Argument parsing
# =============================================================================

@test "--help exits 0 with usage" {
  run -0 "$GMAIL_AWAIT" --help
  assert_output --partial 'Usage: gmail-await'
}

@test "-h exits 0 with usage" {
  run -0 "$GMAIL_AWAIT" -h
  assert_output --partial 'Usage: gmail-await'
}

@test "--start-history-id without value exits 2" {
  run -2 "$GMAIL_AWAIT" --start-history-id
  assert_output --partial 'requires a value'
}

@test "--timeout without value exits 2" {
  run -2 "$GMAIL_AWAIT" --timeout
  assert_output --partial 'requires a value'
}

@test "--timeout with non-numeric value exits 2" {
  run -2 "$GMAIL_AWAIT" --timeout abc
  assert_output --partial 'positive number'
}

@test "--timeout 0 exits 2" {
  run -2 "$GMAIL_AWAIT" --timeout 0
  assert_output --partial 'positive number'
}

@test "unknown flag exits 2" {
  run -2 "$GMAIL_AWAIT" --foo
  assert_output --partial 'Unknown flag'
}

@test "positional argument exits 2" {
  run -2 "$GMAIL_AWAIT" something
  assert_output --partial 'Unexpected argument'
}

# =============================================================================
# Snapshot phase
# =============================================================================

@test "without --start-history-id: fetches profile and starts watching" {
  mock_gws_profile "$FIXTURES/profile.json"
  mock_gws_history 1 "$FIXTURES/history_with_message.json"
  mock_gws_message "$FIXTURES/message.json"

  run --separate-stderr -0 "$GMAIL_AWAIT"
  assert [ -n "$stderr" ]
  assert [ "$(echo "$stderr" | grep -c 'Watching Gmail inbox')" -eq 1 ]
}

@test "getProfile failure exits 1" {
  mock_gws_profile_fail

  run -1 "$GMAIL_AWAIT"
  assert_output --partial 'Could not fetch Gmail profile'
}

@test "profile with null historyId exits 1" {
  mock_gws_profile "$FIXTURES/profile_null_history.json"

  run -1 "$GMAIL_AWAIT"
  assert_output --partial 'Could not extract historyId'
}

@test "with --start-history-id: skips profile and prints resuming message" {
  mock_gws_history 1 "$FIXTURES/history_with_message.json"
  mock_gws_message "$FIXTURES/message.json"

  run --separate-stderr -0 "$GMAIL_AWAIT" --start-history-id 100
  assert [ -n "$stderr" ]
  assert [ "$(echo "$stderr" | grep -c 'Resuming from history ID 100')" -eq 1 ]
  # Should not have called getProfile
  assert [ ! -f "$MOCK_DIR/profile_count" ]
}

# =============================================================================
# Poll loop - timeout
# =============================================================================

@test "timeout expires with no email: exits 1" {
  mock_gws_profile "$FIXTURES/profile.json"
  mock_gws_history_default "$FIXTURES/history_empty.json"

  export GMAIL_AWAIT_POLL_INTERVAL=1
  run --separate-stderr -1 "$GMAIL_AWAIT" --timeout 1
  assert [ "$(echo "$stderr" | grep -c 'Timeout after')" -eq 1 ]
}

@test "timeout with remaining less than poll_interval: exits 1" {
  mock_gws_profile "$FIXTURES/profile.json"
  mock_gws_history_default "$FIXTURES/history_empty.json"

  export GMAIL_AWAIT_POLL_INTERVAL=10
  run --separate-stderr -1 "$GMAIL_AWAIT" --timeout 1
  assert [ "$(echo "$stderr" | grep -c 'Timeout after')" -eq 1 ]
}

# =============================================================================
# Poll loop - error recovery
# =============================================================================

@test "API error with --start-history-id: re-snapshots from profile" {
  mock_gws_profile "$FIXTURES/profile.json"
  mock_gws_history_fail 1
  mock_gws_history 2 "$FIXTURES/history_with_message.json"
  mock_gws_message "$FIXTURES/message.json"

  run --separate-stderr -0 "$GMAIL_AWAIT" --start-history-id 100
  assert [ "$(echo "$stderr" | grep -c 'history ID may be expired')" -eq 1 ]
  # Verify it called profile to re-snapshot
  assert [ -f "$MOCK_DIR/profile_count" ]
}

@test "API error without --start-history-id: retries next cycle" {
  mock_gws_profile "$FIXTURES/profile.json"
  mock_gws_history_fail 1
  mock_gws_history 2 "$FIXTURES/history_with_message.json"
  mock_gws_message "$FIXTURES/message.json"

  run --separate-stderr -0 "$GMAIL_AWAIT"
  assert [ "$(echo "$stderr" | grep -c 'API error, retrying')" -eq 1 ]
}

@test "message fetch failure: skips message and outputs historyId" {
  mock_gws_profile "$FIXTURES/profile.json"
  mock_gws_history 1 "$FIXTURES/history_with_message.json"
  mock_gws_message_fail 1

  run --separate-stderr -0 "$GMAIL_AWAIT"
  assert [ "$(echo "$stderr" | grep -c 'Could not fetch message')" -eq 1 ]
  # Only the historyId line, no email lines
  assert_output '{"historyId":"8978700"}'
}

# =============================================================================
# Poll loop - data filtering
# =============================================================================

@test "history with no entries: continues polling" {
  mock_gws_profile "$FIXTURES/profile.json"
  mock_gws_history 1 "$FIXTURES/history_empty.json"
  mock_gws_history 2 "$FIXTURES/history_with_message.json"
  mock_gws_message "$FIXTURES/message.json"

  run -0 "$GMAIL_AWAIT"
  assert_output --partial '"subject":"Deploy approval for staging"'
}

@test "history entries but no messagesAdded: continues polling" {
  mock_gws_profile "$FIXTURES/profile.json"
  mock_gws_history 1 "$FIXTURES/history_no_messages_added.json"
  mock_gws_history 2 "$FIXTURES/history_with_message.json"
  mock_gws_message "$FIXTURES/message.json"

  run -0 "$GMAIL_AWAIT"
  assert_output --partial '"subject":"Deploy approval for staging"'
}

# =============================================================================
# Happy path and output format
# =============================================================================

@test "email on first poll: exits 0 with JSON output" {
  mock_gws_profile "$FIXTURES/profile.json"
  mock_gws_history 1 "$FIXTURES/history_with_message.json"
  mock_gws_message "$FIXTURES/message.json"

  run --separate-stderr -0 "$GMAIL_AWAIT"
  # First line is the email JSON, second line is the historyId
  email_line=$(echo "$output" | head -1)
  assert [ "$(echo "$email_line" | jq -r '.subject')" = "Deploy approval for staging" ]
  history_line=$(echo "$output" | tail -1)
  assert [ "$(echo "$history_line" | jq -r '.historyId')" = "8978700" ]
}

@test "no email first poll, email second poll: exits 0" {
  mock_gws_profile "$FIXTURES/profile.json"
  mock_gws_history 1 "$FIXTURES/history_empty.json"
  mock_gws_history 2 "$FIXTURES/history_with_message.json"
  mock_gws_message "$FIXTURES/message.json"

  run -0 "$GMAIL_AWAIT"
  assert_output --partial '"subject":"Deploy approval for staging"'
}

@test "output contains all expected fields" {
  mock_gws_profile "$FIXTURES/profile.json"
  mock_gws_history 1 "$FIXTURES/history_with_message.json"
  mock_gws_message "$FIXTURES/message.json"

  run --separate-stderr -0 "$GMAIL_AWAIT"

  # Parse the email JSON line
  email_line=$(echo "$output" | head -1)
  assert [ "$(echo "$email_line" | jq -r '.from')" = "Alice Smith <alice@example.com>" ]
  assert [ "$(echo "$email_line" | jq -r '.to')" = "user@example.com" ]
  assert [ "$(echo "$email_line" | jq -r '.subject')" = "Deploy approval for staging" ]
  assert [ "$(echo "$email_line" | jq -r '.date')" = "Wed, 18 Mar 2026 14:22:00 +0000" ]
  assert [ "$(echo "$email_line" | jq -r '.snippet')" = "Hey, the staging deploy looks good to me. Go ahead and..." ]
  assert [ "$(echo "$email_line" | jq -r '.labels')" = "INBOX, UNREAD, CATEGORY_PERSONAL" ]
  assert [ "$(echo "$email_line" | jq -r '.messageId')" = "msg001" ]
  assert [ "$(echo "$email_line" | jq -r '.threadId')" = "thread001" ]

  # Parse the historyId line
  history_line=$(echo "$output" | tail -1)
  assert [ "$(echo "$history_line" | jq -r '.historyId')" = "8978700" ]
}

# =============================================================================
# Multiple emails
# =============================================================================

@test "multiple emails: outputs one JSON line per email plus historyId line" {
  mock_gws_profile "$FIXTURES/profile.json"
  mock_gws_history 1 "$FIXTURES/history_with_two_messages.json"
  mock_gws_message_nth 1 "$FIXTURES/message.json"
  mock_gws_message_nth 2 "$FIXTURES/message_2.json"

  run --separate-stderr -0 "$GMAIL_AWAIT"

  # Should have 3 lines: 2 emails + 1 historyId
  line_count=$(echo "$output" | wc -l)
  assert [ "$line_count" -eq 3 ]

  # Check first email
  line1=$(echo "$output" | sed -n '1p')
  assert [ "$(echo "$line1" | jq -r '.subject')" = "Deploy approval for staging" ]
  assert [ "$(echo "$line1" | jq -r '.from')" = "Alice Smith <alice@example.com>" ]

  # Check second email
  line2=$(echo "$output" | sed -n '2p')
  assert [ "$(echo "$line2" | jq -r '.subject')" = "Invoice for March" ]
  assert [ "$(echo "$line2" | jq -r '.from')" = "Bob Jones <bob@example.com>" ]

  # Check historyId line
  line3=$(echo "$output" | sed -n '3p')
  assert [ "$(echo "$line3" | jq -r '.historyId')" = "8978700" ]
}

@test "one message fetch fails, others still output" {
  mock_gws_profile "$FIXTURES/profile.json"
  mock_gws_history 1 "$FIXTURES/history_with_two_messages.json"
  mock_gws_message_fail 1
  mock_gws_message_nth 2 "$FIXTURES/message_2.json"

  run --separate-stderr -0 "$GMAIL_AWAIT"
  assert [ "$(echo "$stderr" | grep -c 'Could not fetch message')" -eq 1 ]

  # Should have 2 lines: 1 email + 1 historyId
  line_count=$(echo "$output" | wc -l)
  assert [ "$line_count" -eq 2 ]

  # Check the successful email
  line1=$(echo "$output" | sed -n '1p')
  assert [ "$(echo "$line1" | jq -r '.subject')" = "Invoice for March" ]

  # Check historyId line
  line2=$(echo "$output" | sed -n '2p')
  assert [ "$(echo "$line2" | jq -r '.historyId')" = "8978700" ]
}
