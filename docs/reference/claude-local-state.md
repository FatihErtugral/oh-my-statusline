---
id: claude-local-state
type: reference
verification: unverified
sources:
  - "https://github.com/knowald/cmon (a third-party monitor reading the same records)"
  - "https://claudeissues.com/issue/38184-feature-request-reliable-session-state-detection-api (closed as not planned)"
updated: 2026-10-17
---
# Claude Code local state

This page records the Claude Code files the open-sessions segment reads, as
they were observed. Anthropic does not document any of them. Read it when the
segment shows wrong counts or disappears after a Claude Code update, or before
you change what the segment reads.

Unverified: everything below was read on 2026-10-17 from the Claude Code
2.1.302 Linux binary (its session-record parser and workflow journal reader)
and from the files of one Linux machine running 2.1.289 and 2.1.302 side by
side. A version change can move any of it without notice.

## Session records

One file per running Claude Code process:
`$CLAUDE_CONFIG_DIR/sessions/<pid>.json`, or `~/.claude/sessions/<pid>.json`.
Each file holds one line of JSON with no trailing newline. Claude Code itself
ignores (and deletes) files whose name is not the canonical decimal pid.

| Field | Values seen | Meaning |
| --- | --- | --- |
| `status` | `busy`, `shell`, `waiting`, `idle` | the binary's accepted set; any other value is read as absent |
| `kind` | `interactive`, `bg`, `daemon`, `daemon-worker` | `daemon` is the supervisor, not a session; `bg` and `daemon-worker` are sessions running in the background |
| `spare` | `true` or absent | a pre-warmed process that is not a session yet |
| `procStart` | string | the process start token (see below) |
| `sessionId` | UUID | names the session's directory under `projects/` |
| `waitingFor` | string | what a `waiting` session is blocked on |

`waiting` covers a permission prompt, a sandbox or worker request, a goal
proposal, an open dialog, or a question to the user. In other words, the
session is waiting on the user.

A record outlives a crashed process. Claude Code decides whether a record is
live with two checks: the pid exists (`kill -0`), and the start token still
matches. The token differs by OS:

- **Linux:** field 22 of `/proc/<pid>/stat` (start time in clock ticks since
  boot), stored as a decimal string.
- **macOS:** the trimmed output of `LC_ALL=C TZ=UTC ps -o lstart= -p <pid>`,
  for example `Sat Oct 17 15:37:01 2026`.

Next to each record sits `<pid>.<hash>.key`. On the machine observed, its
mtime equals the process start time; nothing rewrites it later.

## Workflow journals

Each workflow run writes a journal at
`projects/<encoded cwd>/<sessionId>/subagents/workflows/<runId>/journal.jsonl`.
The file has one JSON object per line, and the line's first two keys are
always `type`, then `key`:

| `type` | When |
| --- | --- |
| `launched` | once, when the run starts |
| `started` | an agent starts; a retry or an identical agent starts the same `key` again |
| `result` | an agent finished; the line also carries the agent's whole return value |
| `failed` | an agent failed |
| `restoring`, `restored` | bracket the replayed lines when a run resumes |

At any moment, the number of agents running in a run is, per `key`, the count
of `started` lines minus the count of `result` and `failed` lines. When a run
ends, Claude Code writes `projects/<encoded cwd>/<sessionId>/workflows/<runId>.json`
(with a `status`), so a journal that has this sibling file belongs to a run that is over.

Plain subagents started with the Agent tool keep a transcript and a
`.meta.json` under `subagents/`, but no journal. Nothing on disk marks when
one of them ends.

## What the status line payload lacks

The status line payload (Claude Code 2.1.302) carries `effort.level`, but not
ultracode. Ultracode is a separate per-session toggle (`/effort ultracode
on|off`): when it turns on, the effort level stays the same. A status line
script therefore cannot tell that ultracode is on. The payload also carries no
field about other sessions or about running agents. That is why the counts
come from the files above, and why the status line can only notice changes in
other sessions on a `refreshInterval` timer: there is no event for them.
