# gmail-await

A command-line tool that polls your Gmail inbox until new emails arrive, then prints one JSON line per email and exits.

Designed for coding agents that need to wait for incoming emails and act on them.

## Install

Copy `gmail-await` somewhere on your `PATH`:

```
cp gmail-await /usr/local/bin/
```

**Dependencies:** `gws`, `jq`, `bash`

## Usage

```
gmail-await [flags]
```

**Flags:**

| Flag | Default | Description |
|------|---------|-------------|
| `--start-history-id <id>` | none | Resume from this history ID instead of snapshotting |
| `--timeout <seconds>` | none | Max wait time (exit 1 if exceeded) |
| `--help` | - | Show help |

**Exit codes:**

| Code | Meaning |
|------|---------|
| 0 | New email(s) detected, descriptions printed to stdout |
| 1 | Timeout exceeded, or runtime error |
| 2 | Bad arguments or usage error |

## Examples

Wait for the next email:

```
gmail-await
```

Wait with a 5-minute timeout:

```
gmail-await --timeout 300
```

Resume from a known history ID (no emails missed between invocations):

```
gmail-await --start-history-id 8977613
```

## Example output

```
{"from":"Alice <alice@example.com>","to":"me@example.com","subject":"Deploy approval for staging","date":"Wed, 18 Mar 2026 14:22:00 +0000","snippet":"Hey, the staging deploy looks good to me. Go ahead and...","labels":"INBOX, UNREAD, CATEGORY_PERSONAL","messageId":"18f1a2b3c4d","threadId":"18f1a2b3c4e"}
{"from":"Bob <bob@example.com>","to":"me@example.com","subject":"Invoice for March","date":"Wed, 18 Mar 2026 15:00:00 +0000","snippet":"Please find attached...","labels":"INBOX, UNREAD","messageId":"18f1a2b3c4f","threadId":"18f1a2b3c50"}
{"historyId":"8977696"}
```

Each line is a JSON object. Email lines contain: `from`, `to`, `subject`, `date`, `snippet`, `labels`, `messageId`, `threadId`. The final line contains `historyId`, which is the checkpoint for the next invocation.

Status messages go to stderr, event output goes to stdout. This makes it easy to pipe:

```
gmail-await 2>/dev/null | process-emails
```

## Use with a coding agent

The output is JSON lines structured for machine consumption. A typical agent workflow:

1. Run `gmail-await` to block until emails arrive
2. Parse JSON lines to understand each email
3. Use `gws` with the Message ID or Thread ID to read the full body, reply, or take action
4. Loop back to step 1

```bash
history_id=""
while true; do
  args=()
  [[ -n "$history_id" ]] && args+=(--start-history-id "$history_id")
  output=$(gmail-await "${args[@]}") || continue

  while IFS= read -r line; do
    if echo "$line" | jq -e '.historyId' > /dev/null 2>&1; then
      history_id=$(echo "$line" | jq -r '.historyId')
    else
      echo "$line" | pi "Handle this email."
    fi
  done <<< "$output"
done
```

The loop threads the `historyId` from each invocation into the next, so no emails are lost between runs.

## How it works

1. **Snapshot**: Uses the `--start-history-id` if provided. Otherwise calls `gws gmail users getProfile` to get the current `historyId` as the baseline.
2. **Poll**: Every 60 seconds, calls `gws gmail users history list` with `historyTypes: "messageAdded"` and `labelId: "INBOX"` to check for new messages since the snapshot. Uses `--page-all` to retrieve all pages.
3. **Describe**: On new messages, fetches metadata for each (From, To, Subject, Date, snippet, labels) via `gws gmail users messages get` and outputs one JSON line per email. The final line contains the `historyId` checkpoint. If multiple emails arrived between polls, all are reported.

If a provided `--start-history-id` is expired (API returns an error), the script falls back to `getProfile` automatically. If a single message fetch fails, that email is skipped and the rest are still output.

### Poll interval

The default poll interval is 60 seconds. Override it with the `GMAIL_AWAIT_POLL_INTERVAL` environment variable (in seconds):

```
GMAIL_AWAIT_POLL_INTERVAL=30 gmail-await
```

### API cost

Each poll cycle makes 1 API call (history list). When new emails are detected, 1 additional call per email fetches the message metadata. At the default 60-second interval, this is 1 call/minute steady state. Well within Gmail API quotas.

## Testing

Tests use [bats-core](https://github.com/bats-core/bats-core) with [bats-support](https://github.com/bats-core/bats-support) and [bats-assert](https://github.com/bats-core/bats-assert), vendored as git submodules. After cloning, initialize them:

```
git submodule update --init --recursive
```

Run all tests:

```
./test/bats/bin/bats test/
```

Tests mock `gws` via PATH manipulation, so no Google account or network access is required. Test fixtures are derived from real Gmail API responses. The only runtime dependency for tests is `jq`.

## License

MIT
