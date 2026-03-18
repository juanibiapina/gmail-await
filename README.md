# gmail-await

A command-line tool that polls your Gmail inbox until a new email arrives, then prints a structured description and exits.

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
| `--timeout <seconds>` | none | Max wait time (exit 1 if exceeded) |
| `--help` | - | Show help |

**Exit codes:**

| Code | Meaning |
|------|---------|
| 0 | New email detected, description printed to stdout |
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

## Example output

```
## New email

From: alice@example.com
To: me@example.com
Subject: Deploy approval for staging
Date: Wed, 18 Mar 2026 14:22:00 +0000
Snippet: Hey, the staging deploy looks good to me. Go ahead and...
Labels: INBOX, UNREAD, CATEGORY_PERSONAL
Message ID: 18f1a2b3c4d
Thread ID: 18f1a2b3c4e
```

Status messages go to stderr, event output goes to stdout. This makes it easy to pipe:

```
gmail-await 2>/dev/null | process-email
```

## Use with a coding agent

The output is plain text structured for machine consumption. A typical agent workflow:

1. Run `gmail-await` to block until an email arrives
2. Parse the output to understand the email
3. Use `gws` with the Message ID or Thread ID to read the full body, reply, or take action
4. Loop back to step 1

```bash
while true; do
  gmail-await | pi "Handle this email."
done
```

Each invocation snapshots the current state on startup, so the loop naturally picks up emails one at a time.

## How it works

1. **Snapshot**: Calls `gws gmail users getProfile` to get the current `historyId`, which marks the baseline.
2. **Poll**: Every 60 seconds, calls `gws gmail users history list` with `historyTypes: ["messageAdded"]` and `labelId: "INBOX"` to check for new messages since the snapshot.
3. **Describe**: On the first new message, fetches its metadata (From, To, Subject, Date, snippet, labels) via `gws gmail users messages get` and prints the structured description.

One event per exit. If multiple emails arrived between polls, only the first is reported. The next invocation picks up the rest naturally.

### API cost

Each poll cycle makes 1 API call (history list). When a new email is detected, 1 additional call fetches the message metadata. At 60-second intervals, this is 1 call/minute steady state. Well within Gmail API quotas.

## License

MIT
