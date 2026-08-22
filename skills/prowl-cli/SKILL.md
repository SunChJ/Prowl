---
name: prowl-cli
description: >-
  Use the Prowl CLI (`prowl`) to inspect or control a running Prowl GUI app and the agent sessions it hosts. Prowl runs several coding agents in parallel, each in its own pane/tab/worktree, so reach for this whenever the user wants to act on a pane other than the current one — check on, coordinate, read from, focus, send text or keys to, open, or close another pane, tab, worktree, split, window, or sibling/neighboring agent. Covers colloquial framings that never say "prowl": "check what the agent in my other window is doing", "are any of my agents running side by side still working or idle?", "tell the agent in my left split to rerun the tests", "send npm run build to the build tab and grab the output", "open ~/proj in a fresh tab", "close that scratch tab I left open". Not for ordinary editing or building inside the Prowl source repo, and not for how-to questions about Prowl's settings, preferences, or keybindings — only when the task is to actually drive panes in the live Prowl app.
---

# Prowl CLI

Use `prowl` only when the task is to inspect or control the running Prowl GUI app: read panes, check sibling agents, focus a pane, open a repo/path in Prowl, send text, send keys, or create/close panes and tabs. Do not use it merely because the current shell is inside the Prowl repo. The authoritative per-command reference is `docs/components/cli.md`.

## Who You Are

Every Prowl pane exports its own identity to the processes inside it:

- `PROWL_PANE_ID` — this pane's UUID, identical to `pane.id` in `prowl list --json`.
- `PROWL_WORKTREE_PATH`, `PROWL_ROOT_PATH` — this pane's worktree directory and repository root.

Use `$PROWL_PANE_ID` as your own selector and as the guard against operating on yourself; resolve your tab and worktree from it when you need them:

```bash
me="$(prowl list --json | jq -c --arg p "$PROWL_PANE_ID" '.data.items[] | select(.pane.id == $p)')"
printf '%s\n' "$me" | jq -r '.tab.id, .worktree.id, .worktree.name, .worktree.path'
test "$pane" != "$PROWL_PANE_ID"   # before sending anything to $pane
```

The variable is inherited, not verified: it is missing after `sudo`/`ssh`/containers and can name the wrong pane inside a tmux/screen session attached from elsewhere. If it is unset or matches no `pane.id`, pick yourself from `prowl list --json` by `pane.cwd`. Never assume the focused pane is you — `open` and `focus` move focus, and the user may be looking anywhere.

## Safe Default Workflow

Resolve a concrete pane before `read`, `send`, `key`, `focus`, or `close`, and pass it explicitly:

```bash
prowl list --json      # every pane: worktree → tab → pane, plus worktree task.status
prowl agents --json    # detected agent panes only: status working|blocked|idle|done
prowl read --pane "$pane" --last 80 --wait-stable --json
prowl send --pane "$pane" 'printf "PWD:%s\n" "$PWD"' --capture --timeout 30 --json
prowl key --pane "$pane" enter --json
prowl focus --pane "$pane" --json
```

Pick targets by `pane.id`, `tab.id`, `worktree.id`/`name`/`path`, and `pane.cwd`. Never trust tab titles: they are free-form and can lag or lie. Text `prowl list` / `prowl agents` also print short handles (`p7`, `t6`) that work in any target position for the life of the app process (`read p7`, `close t6`); UUIDs are the only identity that survives an app restart.

For a currently active Codex or Claude Code agent, `prowl agents read p7 --json` returns an immediate semantic snapshot: `.data.agent.status`, `.data.blocker.text` when blocked, and `.data.result` — a result is trustworthy only when `.data.result.state == "complete"`.

## Common Recipes

Open a split beside yourself (or any positively identified anchor) and capture the new pane:

```bash
pane="$(prowl create pane "$PROWL_PANE_ID" --direction right --json | jq -r '.data.target.pane.id')"
```

Directions are `right`, `left`, `up`, `down`; the anchor must be a pane UUID or current `pN`. The new pane inherits the anchor's working directory, becomes focused, and Prowl selects its worktree and tab (as `create tab` does). Run input afterwards with an explicit `prowl send --pane "$pane" …`.

Create a fresh tab in a listed worktree:

```bash
pane="$(prowl create tab "$worktree" --json | jq -r '.data.target.pane.id')"
```

Prefer a `worktree.id` or `worktree.name` from `prowl list --json` over a hand-typed path; `--path` only sets the new tab's working directory inside that worktree. `prowl open /path` is navigation — it may reuse an existing pane — so use `create tab`/`create pane` when you need a guaranteed new shell.

Run a command and capture its output and exit code:

```bash
out="$(prowl send --pane "$pane" 'git status --short' --capture --timeout 30 --json)"
printf '%s\n' "$out" | jq -r '.data.capture.text, .data.wait.exit_code'
```

Deliver input without waiting, or pre-fill and submit later:

```bash
prowl send --pane "$pane" 'long-running command' --no-wait --json
prowl send --pane "$pane" 'echo ready' --no-enter --no-wait --json && prowl key --pane "$pane" enter --json
```

Send multiline input from stdin:

```bash
printf '%s\n' 'echo first' 'echo second' | prowl send --pane "$pane" --capture --timeout 30 --json
```

Close what you created:

```bash
prowl close "$pane" --json
prowl close --tab "$tab" --force --json   # --force skips the GUI confirmation for protected work
```

`close` requires an explicit pane or tab and has no focus or worktree fallback.

## Parsing JSON Output

Every `--json` response is `{ "ok", "command", "schema_version", "data": {...} }`; failures are `{ "ok": false, "error": { "code", "message" } }`. Parser errors (bad flags) print plain text even with `--json`, so check the exit code before piping into `jq`. When JSON sits in a shell variable, use `printf '%s\n' "$json" | jq …` — zsh `echo` can turn `\u001B` escapes back into control characters. Pass shell values into `jq` with `--arg`.

Key fields by command:

- `list` → `.data.items[]` with `.worktree.{id,name,path,root_path,kind}`, `.tab.{id,title,selected}`, `.pane.{id,title,cwd,focused,agent}`, `.task.status` (`running`|`idle`|null).
- `agents` → `.data.agents[]` with `.status`, `.raw_state`, `.detection_reason`, `.type`, `.name`, `.pane.{id,focused,cwd}`, `.tab`, `.worktree`, `.project.{name,branch,path}`.
- `agents read` → `.data.agent`, `.data.blocker.text`, `.data.result.{state,text}` — `pending`, `unavailable`, `missing`, `incomplete`, `too_large` carry no partial text.
- `read` → `.data.text`, `.data.line_count`, `.data.truncated`, `.data.mode`, `.data.source`; `.data.stabilized` / `.data.waited_ms` with `--wait-stable`.
- `send` → `.data.input`, `.data.wait.{exit_code,duration_ms}` when waiting, `.data.capture.{text,line_count,truncated}` with `--capture`.
- `create tab` / `open` → `.data.target.{pane,tab,worktree}`; `create pane` → `.data.anchor`, `.data.direction`, `.data.target`.

Terminal text is `.data.text` (read) and `.data.capture.text` (send) — never `.content`, `.output`, or `.stdout`.

## Reading Agent Output

- For Codex/Claude Code, `prowl agents read` beats scraping: check `.data.agent.status`, inspect `.data.blocker.text` before answering a prompt with `send`/`key` (read and write are not atomic), and only trust `.data.result.text` when `state == "complete"`. `--result-only` prints the raw trusted result and fails otherwise; it cannot combine with `--json`.
- For everything else, `prowl read --pane "$pane" --last 200 --wait-stable --json` blocks until the screen stops changing. `task.status` flips to `idle` before a TUI finishes painting, so poll it only to wait for a `working` agent, then still read with `--wait-stable`:

```bash
for i in 1 2 3 4 5 6; do
  task_state="$(prowl list --json | jq -r --arg p "$pane" '.data.items[] | select(.pane.id == $p) | .task.status')"
  [ "$task_state" = idle ] && break
  sleep 1
done
```

- Rendered screens can truncate or fold content. When you need an agent's complete output, have the command write a file (`… > /tmp/out.txt`) and read that; shell redirection avoids the agent's own sandbox prompts.
- `read` returning fewer lines than `--last` with `truncated: false` means the pane simply has less history — do not retry. `--source detection` returns the exact detector input instead of the viewport; it exists for diagnosing agent-state detection (see `docs/components/agent-detection.md`), not for everyday reading.

## Targeting & Arguments

- Selectors are mutually exclusive: `--pane <uuid|pN>`, `--tab <uuid|tN>`, `--worktree <id|name|path>`, or `-t/--target` (auto: `pN`, `tN`, then UUID, then worktree). A stale handle fails rather than falling back to a same-named worktree.
- `send` and `key` positionals are count-sensitive: `send 'text'` and `key enter` go to the *focused* pane, `send p7 'text'` / `key p7 enter` to `p7`, and stdin replaces the text argument. Avoid positional targeting in automation.
- `send --capture` waits for completion and sends Enter; it cannot combine with `--no-wait` or `--no-enter`. `--capture` needs shell integration (OSC 133) on the target pane.
- `key --repeat <1-100>` repeats a token, e.g. `prowl key --pane "$pane" down --repeat 10`.
- Quote payloads with outer single quotes when variables should expand in the *target* pane: `prowl send --pane "$pane" 'printf "PWD:%s\n" "$PWD"'`.
- In zsh, never name a variable `status` — it is readonly.

## Pitfalls

- `open /path` may refocus an existing pane; it is not a create command.
- Focus is not stable and is not you: `open` and `focus` change it, and the user clicks around.
- `send --capture` captures a screen diff; multiline input may include command echo.
- The CLI talks to one socket owner. With two Prowl instances running, the default `prowl` reaches whichever owns the standard socket; a manually launched dev instance and every CLI call must share the same `PROWL_CLI_SOCKET=/tmp/name.sock`. Sandboxed agents must be allowed to connect to that Unix socket.
- A newer CLI talking to an older app can fail at transport level (`TRANSPORT_FAILED`) — confirm the running app was built with the command.

## Error Handling

- `APP_NOT_RUNNING`: Prowl is not reachable or the socket is stale — ask before restarting the app.
- `SOCKET_PERMISSION_DENIED`: the sandbox or filesystem blocked `connect()`; report a permission problem, not an app-liveness problem.
- `TRANSPORT_FAILED`: the connection broke or the socket path is invalid (`ENOTSOCK`, too-long `PROWL_CLI_SOCKET`).
- `TARGET_NOT_FOUND` / `TARGET_NOT_UNIQUE`: re-run `prowl list --json` and pass an explicit UUID or a current `pN`.
- `NO_ACTIVE_PANE`: focused-pane targeting found nothing — pass `--pane`. `SOURCE_REQUIRED`: `handoff` was run outside a Prowl pane without a selector.
- `EMPTY_INPUT`, `INVALID_ARGUMENT`, `UNSUPPORTED_KEY`, `INVALID_REPEAT`: fix the arguments (`prowl <cmd> --help`).
- `CAPTURE_UNSUPPORTED`: drop `--capture` and use `read --wait-stable` or file redirection. `WAIT_TIMEOUT`: raise `--timeout` or use `--no-wait`.
- `PATH_NOT_FOUND` / `PATH_NOT_DIRECTORY` / `PATH_NOT_ALLOWED`: fix the path given to `open` or `create tab --path`.

## Handing Off Your Task

`prowl handoff to <agent> --brief -` hands your task to another agent. Run it from your own pane (the calling pane is the source — no selector needed) and pipe your briefing on stdin:

```bash
prowl handoff to codex --brief - <<'EOF'
# Handoff
## Objective
…
## Current State
…
## Next Steps
…
EOF
```

Required sections are `## Objective`, `## Current State`, and `## Next Steps`; optional ones are `## What Has Been Done`, `## Open Questions`, `## Risks / Watch Out`, and `## Suggested Prompt For Next Agent`. The receiver launches in a background tab of the same worktree; your session stays open. `prowl handoff save --brief -` checkpoints the same briefing without launching anyone; `--no-brief` is for an intentional context-only handoff; `--pane` hands off a pane other than your own. Details: `docs/components/handoff.md`.

## Command Set

`list`, `agents`, `agents read`, `read`, `send`, `key`, `focus`, `create tab`, `create pane`, `close`, `handoff to`, `handoff save`, and `open` (default). There is no CLI `quit`; close temporary tabs or panes with an explicit `close`. `tab create`, `tab close`, and `pane close` remain deprecated aliases for one release.
