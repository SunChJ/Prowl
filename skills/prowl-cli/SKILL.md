---
name: prowl-cli
description: >-
  Use the Prowl CLI (`prowl`) to inspect or control a running Prowl GUI app and the agent sessions it hosts. Prowl runs several coding agents in parallel, each in its own pane/tab/worktree, so reach for this whenever the user wants to act on a pane other than the current one — check on, coordinate, read from, focus, send text or keys to, open, or close another pane, tab, worktree, split, window, or sibling/neighboring agent. Covers colloquial framings that never say "prowl": "check what the agent in my other window is doing", "are any of my agents running side by side still working or idle?", "tell the agent in my left split to rerun the tests", "send npm run build to the build tab and grab the output", "open ~/proj in a fresh tab", "close that scratch tab I left open". Not for ordinary editing or building inside the Prowl source repo, and not for how-to questions about Prowl's settings, preferences, or keybindings — only when the task is to actually drive panes in the live Prowl app.
metadata:
  prowl-summary: Lets an agent drive the running Prowl app through the prowl command — list panes, read or message sibling agents, send text and keys, create or close tabs and panes, launch profiles, and wait for a task to finish. Link it into a runtime's skill folder so the agent knows when and how to use prowl.
---

# Prowl CLI

Use `prowl` only when the task is to inspect or control the running Prowl GUI app: read panes, check sibling agents, focus a pane, open a repo/path in Prowl, send text, send keys, or create/close panes and tabs. Do not use it merely because the current shell is inside the Prowl repo.

The authoritative per-command reference is Prowl's manual, `components/cli.md` under the docs folder. That folder is `docs/` in a Prowl source checkout; otherwise it ships inside the app bundle, which you can locate from the installed CLI (normally `/Applications/Prowl.app/Contents/Resources/docs`):

```bash
prowl_docs="$(dirname "$(dirname "$(readlink -f "$(command -v prowl)")")")/docs"
ls "$prowl_docs/components/"   # cli.md, agent-detection.md, handoff.md, …
```

Other `docs/components/*.md` references below live in that same folder.

This skill ships inside the app: `prowl skills install prowl-cli` links it into every detected agent skill folder (`~/.claude/skills`, `~/.codex/skills`, `~/.agents/skills` — whichever parent directories exist; add `--target <claude|codex|agents>` to pick or create specific ones) so it stays current across app updates. `prowl skills list` shows per-target status; the command is local and needs no running app.

## Who You Are

Every Prowl pane exports its own identity to the processes inside it:

- `PROWL_PANE_ID` — this pane's UUID, identical to `pane.id` in `prowl list --json`.
- `PROWL_WORKTREE_PATH`, `PROWL_ROOT_PATH` — this pane's worktree directory and repository root.

Use `$PROWL_PANE_ID` as your own selector and as the guard against operating on yourself; resolve your tab and worktree from it when you need them:

```bash
me="$(prowl list --json | jq -c --arg p "$PROWL_PANE_ID" '.data.items[] | select(.pane.id == $p)')"
if [ -z "$me" ]; then
  echo "no pane matches PROWL_PANE_ID=[$PROWL_PANE_ID] — unset, or prowl reached another Prowl instance; stop, do not guess" >&2
else
  printf '%s\n' "$me" | jq -r '.tab.id, .worktree.id, .worktree.name, .worktree.path'
fi
```

Gate every action on a target behind that lookup result (`$me`), never behind the bare variable — a stale id that points at another instance would otherwise pass — and keep the dependent commands inside the branch, because a bare predicate line does not stop an interactive shell:

```bash
if [ -z "$me" ] || [ "$pane" = "$PROWL_PANE_ID" ]; then
  echo "refusing: self identity is unverified, or \$pane is me" >&2
else
  prowl send --pane "$pane" 'git status --short' --capture --timeout 30 --json
fi
```

The variable is inherited, not verified: it is missing after `sudo`/`ssh`/containers and can name the wrong pane inside a tmux/screen session attached from elsewhere. A set value that matches no `pane.id` usually means `prowl` is talking to a different Prowl instance than the one hosting your pane (two apps running; see `PROWL_CLI_SOCKET` under Pitfalls). A match only proves that pane exists, not that you are running in it: trust the value only when your process ancestry reaches the pane's shell (no tmux/screen server or detached wrapper in between); under tmux/screen or a detached wrapper, identify your pane by other means — `prowl agents --json` for the pane hosting your own agent session, or a unique `pane.cwd` — and pass it explicitly. If it is unset or matches nothing, stop rather than guess: `pane.cwd` only narrows the candidates — several panes usually share one cwd — and may stand in for you only when the match is unique. Never assume the focused pane is you — `open` and `focus` move focus, and the user may be looking anywhere.

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

Pick targets by `pane.id`, `tab.id`, `worktree.id`/`name`/`path`, and `pane.cwd`. Never trust tab titles: they are free-form and can lag or lie. Text `prowl list` / `prowl agents` also print short handles (`p7`, `t6`) that work in any target position for the life of the app process (`read p7`, `close t6`). UUIDs are the canonical identity of a *live* pane or tab, not a durable one: after an app restart restored tabs keep their tab UUID but panes are new surfaces with new UUIDs — never cache handles or pane UUIDs across a restart; re-run `prowl list`.

For a currently active Codex or Claude Code agent, `prowl agents read p7 --json` returns an immediate semantic snapshot: `.data.agent.status`, `.data.blocker.text` when blocked, and `.data.result` — a result is trustworthy only when `.data.result.state == "complete"`.

Report an event only for the pane running the current process; `agents signal` has no target or focus fallback:

```bash
prowl agents signal turn-ended --detail "Review complete" --json
prowl agents signal needs-input --session session-1 --json
```

The app attributes the socket peer PID through process ancestry. `turn-ended` means a runtime turn edge, not task/workflow completion; only `workflow done` completes a workflow step. Public `--origin` is claimed metadata and never upgrades trust.

## Common Recipes

Open a split beside yourself (or any positively identified anchor) and capture the new pane:

```bash
pane="$(prowl create pane "$PROWL_PANE_ID" --direction right --json | jq -r '.data.target.pane.id')"
```

Directions are `right`, `left`, `up`, `down`; the anchor must be a pane UUID or current `pN`. The new pane inherits the anchor's working directory, becomes focused, and Prowl selects its worktree and tab (as `create tab` does). Run input afterwards with an explicit `prowl send --pane "$pane" …`.

Launch a reviewer beside yourself after the identity guard in **Who You Are** has verified `$me`:

```bash
launch="$(prowl create pane "$PROWL_PANE_ID" --direction right --profile Reviewer --prompt - --json <<'EOF'
Review the current branch against its base. Report only actionable findings with file and line references.
EOF
)"
pane="$(printf '%s\n' "$launch" | jq -r '.data.target.pane.id')"
dispatch="$(printf '%s\n' "$launch" | jq -r '.data.dispatch.id')"
if result="$(prowl agents wait --dispatch "$dispatch" --include-screen 40 --json)"; then
  printf '%s\n' "$result" | jq -r '.data.receipt.summary, .data.target.pane.id'
else
  printf '%s\n' "$result" | jq '.error.code, .error.details'
fi
```

The returned pane is the launched agent; `.data.launch` records the resolved Profile and
`.data.dispatch` is the exact assignment receipt. `--prompt -` requires a pipe or heredoc
(never interactive stdin); Prowl carries up to 256 KiB outside initial PTY input through a
command portable across zsh, bash, and fish. Put larger requirement sets in a repository file
and prompt the Profile to read it. Add `--background` when the split must not change focus or
select a hidden anchor's tab/worktree.

Only a succeeded dispatch receipt proves that prompted assignment completed. The receipt may
arrive before the TUI paints its final response; if the next action sends another prompt to the
same pane, wait for an idle condition or read a stable screen first.

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

Every `--json` response is `{ "ok", "command", "schema_version", "data": {...} }`; failures are `{ "ok": false, "command", "schema_version", "error": { "code", "message", "details"? } }`. Wait failures use governed `.error.details` for the retained dispatch record or last condition evidence. Parser errors (bad flags) print plain text even with `--json`, so check the exit code before piping into `jq`. When JSON sits in a shell variable, use `printf '%s\n' "$json" | jq …` — zsh `echo` can turn `\u001B` escapes back into control characters. Pass shell values into `jq` with `--arg`.

Key fields by command:

- `list` → `.data.items[]` with `.worktree.{id,name,path,root_path,kind}`, `.tab.{id,title,selected}`, `.pane.{id,title,cwd,focused,agent}`, `.task.status` (`running`|`idle`|null).
- `agents` → `.data.agents[]` with `.status`, `.raw_state`, `.detection_reason`, `.type`, `.name`, `.pane.{id,focused,cwd}`, `.tab`, `.worktree`, `.project.{name,branch,path}`.
- `agents read` → `.data.agent`, `.data.blocker.text`, `.data.result.{state,text}` — `pending`, `unavailable`, `missing`, `incomplete`, `too_large` carry no partial text.
- `agents signal` → `.data.pane.{id,worktree_id}`, `.data.signal.{event,source,confidence,at,session_id,detail,claimed_origin}`; optional fields are omitted.
- `agents wait --dispatch` → `.data.receipt`, immutable `.data.target`, `.data.signals`, optional `.data.screen`; nonzero results retain the record and evidence under `.error.details`.
- `agents wait <pane> --until …` → `.data.observation.{status,raw_state,source,confidence,at,revision}`, `.data.signals`, and optional `.data.screen`.
- `read` → `.data.text`, `.data.line_count`, `.data.truncated`, `.data.mode`, `.data.source`; `.data.stabilized` / `.data.waited_ms` with `--wait-stable`.
- `send` → `.data.input`, `.data.wait.{exit_code,duration_ms}` when waiting, `.data.capture.{text,line_count,truncated}` with `--capture`.
- `create tab` / `open` → `.data.target.{pane,tab,worktree}`; `create pane` → `.data.anchor`, `.data.direction`, `.data.target`; Profile launches also include `.data.launch.{profile_id,profile_name,agent}`, prompted launches require `.data.dispatch.{id,state,created_at}`, and a safe managed-signal fallback may add `.data.warnings[]` with `code=managed_hook_degraded`.
- `profiles list` → `.data.profiles[]` with `.id`, `.name`, `.enabled`, `.runtime`, `.availability.{status,reason}`.

Terminal text is `.data.text` (read) and `.data.capture.text` (send) — never `.content`, `.output`, or `.stdout`.

## Reading Agent Output

- For Codex/Claude Code, `prowl agents read` beats scraping: check `.data.agent.status`, inspect `.data.blocker.text` before answering a prompt with `send`/`key` (read and write are not atomic), and only trust `.data.result.text` when `state == "complete"`. `--result-only` prints the raw trusted result and fails otherwise; it cannot combine with `--json`.
- Prowl-launched Claude Code, Codex, Copilot, Droid, Qoder, Pi, Oh My Pi, and OpenCode
  Profiles may expose `verified_live` channels with `source=hook_<runtime>`; manually typing
  those runtimes does not. A managed hook
  `turn-ended` proves only a runtime turn edge, never assigned-task completion. If Profile
  creation returns `managed_hook_degraded`, keep the successful pane but expect honest
  heuristic/cooperative fallback for that session.
- For an unpaired or manually launched agent, use one condition wait instead of a polling loop:

```bash
result="$(prowl agents wait "$pane" --until idle --include-screen 40 --timeout 600 --json)"
printf '%s\n' "$result" | jq '.data.observation, .data.screen'
```

  Exact/high evidence can establish the requested observable condition. If
  `jq -e '.data.observation.confidence == "heuristic"'` matches, inspect the included stable
  screen and, when needed, `prowl agents read "$pane" --json`. A finished answer with an empty
  prompt is positive evidence; a spinner/tool footer means working; a permission dialog or
  explicit question means blocked. Always use task context, and never treat heuristic evidence as task completion or perform destructive follow-up from it alone. A timeout leaves the task unresolved: inspect the pane, then re-arm the wait rather than assuming completion.
- `DISPATCH_NEEDS_INPUT` means the exact worker needs intervention. `DISPATCH_INCOMPLETE` means
  its turn ended without the required receipt. Both retain a pending receipt, so inspect
  `.error.details` and do not immediately re-arm the dispatch wait. When possible, arm
  `prowl agents wait "$pane" --until changed --timeout 120 --json` before the `send` / `key`
  intervention; otherwise use `read --wait-stable` afterward. Re-arm the strict dispatch wait
  only after newer activity or screen evidence shows the intervention took effect.
- Rendered screens can truncate or fold content. When you need an agent's complete output, have the command write a file (`… > /tmp/out.txt`) and read that; shell redirection avoids the agent's own sandbox prompts.
- `read` returning fewer lines than `--last` with `truncated: false` means the pane simply has less history — do not retry. `--source detection` returns the exact detector input instead of the viewport; it exists for diagnosing agent-state detection (see `components/agent-detection.md` in the docs folder), not for everyday reading.

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
- The CLI talks to one socket owner. With two Prowl instances running, the default `prowl` reaches whichever owns the standard socket; a manually launched dev instance and every CLI call must share the same `PROWL_CLI_SOCKET=/tmp/name.sock` *and* the CLI built with that app (`./.build/debug/prowl` from the same checkout, or `Prowl Debug.app/Contents/Resources/prowl-cli/prowl`) — the version string does not reveal a mismatch, a missing command does. Sandboxed agents must be allowed to connect to that Unix socket.
- A newer CLI talking to an older app can fail at transport level (`TRANSPORT_FAILED`) — confirm the running app was built with the command.

## Error Handling

- `APP_NOT_RUNNING`: Prowl is not reachable or the socket is stale — ask before restarting the app.
- `SOCKET_PERMISSION_DENIED`: the sandbox or filesystem blocked `connect()`; report a permission problem, not an app-liveness problem.
- `TRANSPORT_FAILED`: the connection broke or the socket path is invalid (`ENOTSOCK`, too-long `PROWL_CLI_SOCKET`).
- `TARGET_NOT_FOUND` / `TARGET_NOT_UNIQUE`: re-run `prowl list --json` and pass an explicit UUID or a current `pN`.
- `PROFILE_NOT_FOUND` / `PROFILE_NOT_UNIQUE`: re-run `prowl profiles list --json`; choose an enabled Profile UUID.
- `NO_ACTIVE_PANE`: focused-pane targeting found nothing — pass `--pane`. `SOURCE_REQUIRED`: a caller-owned command (`agents signal`, selector-free `handoff`) could not map process ancestry to a Prowl pane.
- `EMPTY_INPUT`, `INVALID_ARGUMENT`, `UNSUPPORTED_KEY`, `INVALID_REPEAT`: fix the arguments (`prowl <cmd> --help`).
- `CAPTURE_UNSUPPORTED`: drop `--capture` and use `read --wait-stable` or file redirection.
- `WAIT_TIMEOUT`: inspect `.error.details`, then re-arm the wait if the task remains active.
- `DISPATCH_FAILED` / `DISPATCH_ABANDONED`: the exact dispatch is terminal; inspect its retained record and immutable target in `.error.details`.
- `AGENT_GONE`: inspect `.error.details.mode`. `dispatch` means the exact worker is terminal and retains a record; `condition` means the target pane closed. Without details on `agents signal`, the caller pane disappeared before recording.
- `DISPATCH_NEEDS_INPUT` / `DISPATCH_INCOMPLETE`: the dispatch remains pending; use the intervention sequencing in **Reading Agent Output** before waiting again.
- `PATH_NOT_FOUND` / `PATH_NOT_DIRECTORY` / `PATH_NOT_ALLOWED`: fix the path given to `open` or `create tab --path`.

## Handing Off Your Task

`prowl handoff to <agent> --brief -` hands your task to another agent. Run it from your own pane (the calling pane is the source — no selector needed) and pipe your briefing on stdin. Prowl finds the calling pane through process ancestry, so any descendant of the pane's shell (an agent, its tool shell) works; under tmux/screen or a detached wrapper that resolution fails with `SOURCE_REQUIRED`, and in exactly those setups `$PROWL_PANE_ID` is not trustworthy either (it names the pane the tmux server started in, which may still exist) — identify your pane by other means (`prowl agents --json`, a unique `pane.cwd`) and pass it with `--pane` explicitly.

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

Required sections are `## Objective`, `## Current State`, and `## Next Steps`; optional ones are `## What Has Been Done`, `## Open Questions`, `## Risks / Watch Out`, and `## Suggested Prompt For Next Agent`. The receiver launches in a background tab of the same worktree; your session stays open. `prowl handoff save --brief -` checkpoints the same briefing without launching anyone; `--no-brief` is for an intentional context-only handoff; `--pane` hands off a pane other than your own. Details: `components/handoff.md` in the docs folder.

## Command Set

`list`, `agents`, `agents read`, `agents signal`, `agents dispatch-complete`, `agents dispatch-abandon`, `agents wait`, `profiles list`, `skills list|install|uninstall|path` (local-only), `read`, `send`, `key`, `focus`, `create tab`, `create pane`, `close`, `handoff to`, `handoff save`, and `open` (default). There is no CLI `quit`; close temporary tabs or panes with an explicit `close`. `tab create`, `tab close`, and `pane close` remain deprecated aliases for one release.
