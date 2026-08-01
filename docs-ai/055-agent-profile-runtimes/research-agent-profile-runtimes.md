# Agent Profile Runtime Research

This record supports [entry 055](000-plan.md). It separates CLI contract
evidence, Prowl launch/detection evidence, authenticated task execution, and
Prowl workflow admission; one is not proof of another.

## Method

For each runtime, the investigation used this order:

1. resolve the executable and capture its installed version and `--help`;
2. check official documentation when help was ambiguous or incomplete;
3. launch the CLI in a disposable Prowl pane, confirm the process classifier,
   inspect the visible TUI, then close only that tab;
4. inspect upstream source when a required capability appeared absent or a
   relocation flag might cover only part of the runtime's state.

Evidence labels:

- **Live** — observed in a local Prowl pane on 2026-08-01;
- **Help** — verified from the installed CLI's help/version output;
- **Docs** — verified from official product documentation;
- **Source** — verified from the runtime's upstream implementation;
- **Best effort** — launch was verified, but authenticated task execution was
  unavailable or unnecessary.

## Prowl catalog

`DetectedAgent` has fourteen families. Agent Profiles expose fifteen launch
runtimes because `pi`, `omp`, and `oh-my-pi` are intentionally classified as
the same Pi family while Pi and Oh My Pi remain different executables and
Profile option contracts.

| Detection token | Launch runtime | Installed version | Live Prowl result |
| --- | --- | --- | --- |
| `pi` | Pi / `pi` | 0.82.0 | Detected as `pi` |
| `pi` | Oh My Pi / `omp` | 17.2.1 | Detected as `pi`, OMP icon token preserved by launch Profile |
| `claude` | Claude Code / `claude` | 2.1.220 | Detected as `claude` |
| `codex` | Codex / `codex` | 0.146.0 | Detected as `codex` |
| `gemini` | Gemini CLI / `gemini` | 0.46.0 | Detected as `gemini`; workspace trust screen shown |
| `cursor-agent` | Cursor Agent / `cursor-agent` | 2026.05.09-0afadcc | Detected as `cursor-agent` |
| `cline` | Cline CLI / `cline --tui` | 2.18.0 | Detected as `cline`; bare `cline` was rejected as the Profile entry because it opens Kanban |
| `opencode` | OpenCode / `opencode` | 1.17.18 | Detected as `opencode` |
| `copilot` | GitHub Copilot CLI / `copilot` | 1.0.70 | Detected as `copilot`; workspace trust screen shown |
| `kimi` | Kimi Code CLI / `kimi` | 1.41.0 | Detected as `kimi`; update notice shown |
| `droid` | Factory Droid / `droid` | 0.170.0 | Detected as `droid` |
| `amp` | Amp / `amp` | 0.0.1783746383-g8a60c7 | Detected as `amp` |
| `qodercli` | Qoder CLI / `qodercli` | 1.0.48 | Detected as `qodercli`; existing login accepted |
| `qwen` | Qwen Code / `qwen` | 0.21.2 | Installed during research; detected as `qwen`; provider setup required |
| `grok` | Grok Build / `grok` | 0.2.118 | Detected as `grok` |

Every disposable tab was closed by its exact pane/tab identifier and focus was
returned to the original development pane. No missing credential prevented
interactive startup or Prowl detection. Qwen had no configured provider, so
authenticated task execution remains **Best effort** rather than Live proof.

## Shipped capability matrix

Legend: ✅ exposed by Agent Profiles; — deliberately hidden because the CLI
contract cannot satisfy Prowl's field semantics; ⚠️ CLI has related behavior,
but it is not admitted to that Prowl workflow.

| Runtime | Interactive / prompt / headless | Model | Reasoning | Unrestricted | Dedicated home | Safe Prowl resume | Profile |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Claude Code | ✅ / ✅ / `-p` | ✅ | `--effort` | `--dangerously-skip-permissions` | `CLAUDE_CONFIG_DIR` | ✅ forked print resume | ✅ |
| Codex | ✅ / ✅ / `exec` | ✅ | `model_reasoning_effort` | bypass approvals and sandbox | `CODEX_HOME` | ✅ ephemeral exec resume | ✅ |
| Gemini CLI | ✅ / `--prompt-interactive` / `--prompt` | ✅ | — | YOLO plus sandbox disabled | `GEMINI_CLI_HOME`; sessions under `.gemini` | ⚠️ resume exists, safe fork not admitted | ✅ |
| Cursor Agent | ✅ / positional / `--print` | ✅ | — | YOLO plus sandbox disabled | **— no verified full-state relocation** | ⚠️ resume exists, safe fork not admitted | ✅ |
| Cline CLI | `--tui` / `--tui <prompt>` / positional | ✅ | `--thinking` | — | `--config`, `--data-dir`, and `--hooks-dir` | ⚠️ task resume exists, safe fork not admitted | ✅ |
| OpenCode | ✅ / `--prompt` / `run` | ✅ | `--variant` | `--auto` | **— config-dir only; auth and sessions remain in XDG data** | ⚠️ fork flag exists, protocol not admitted | ✅ |
| GitHub Copilot | ✅ / `--interactive` / `--prompt` | ✅ | `--reasoning-effort` | `--allow-all` | `COPILOT_HOME` | ⚠️ resume exists, safe fork not admitted | ✅ |
| Kimi Code | ✅ / `--prompt` / `--print --prompt` | ✅ | — (boolean thinking is not an effort scale) | `--yolo` | **— alternate config/share paths do not relocate every data class** | ⚠️ resume/fork exists, protocol not admitted | ✅ |
| Factory Droid | ✅ / positional / `exec` | **— interactive CLI has no model option** | — | — (`--auto` is an autonomy level) | **— settings overlay only** | ⚠️ fork exists, protocol not admitted | ✅ |
| Amp | ✅ / **— seeded interactive prompt unavailable** / `--execute` | **— `--mode` is not a model selector** | `--effort` | — | **— settings/log paths do not relocate auth and threads** | ⚠️ continue exists, safe fork not admitted | ✅ bare launch |
| Qoder CLI | ✅ / `--prompt-interactive` / `--print` | ✅ | `--reasoning-effort` | skip permissions | `--config-dir` | ⚠️ fork-session exists, protocol not admitted | ✅ |
| Qwen Code | ✅ / `--prompt-interactive` / `--prompt` | ✅ | `--reasoning-effort` | YOLO plus sandbox disabled | `QWEN_HOME` | ⚠️ resume exists, safe fork not admitted | ✅ Best effort |
| Grok Build | ✅ / positional / `--single` | ✅ | `--reasoning-effort` | **— auto-approval does not prove sandbox removal** | **— no verified full-state relocation** | ⚠️ fork-session exists, protocol not admitted | ✅ |
| Pi | ✅ / positional / `--print` | ✅ | `--thinking` | — (no launch-wide bypass contract) | `PI_CODING_AGENT_DIR` | ⚠️ fork exists, protocol not admitted | ✅ |
| Oh My Pi | ✅ / positional / `--print` | ✅ | `--thinking` | `--approval-mode yolo` | `PI_CODING_AGENT_DIR` | ⚠️ resume exists, safe fork not admitted | ✅ |

### Explicit unsupported results after false-positive checks

- **Full Dedicated Home is unavailable for Cursor, OpenCode, Kimi, Droid,
  Amp, and Grok.** Prowl does not substitute `HOME`: that would redirect every
  child process and bypass managed-home provisioning/deletion. OpenCode's
  `OPENCODE_CONFIG_DIR`, Kimi's config/share overrides, Droid's settings file,
  and Amp's settings/log overrides cover only subsets of native state. Their
  own docs/source still place credentials, sessions, caches, or threads in
  other roots.
- **Amp cannot accept a seeded prompt and remain interactive through argv.**
  `--execute` is headless, while interactive input is read from the TUI/stdin.
  The launch adapter therefore throws an unsupported-intent error instead of
  presenting headless execution as an interactive handoff receiver. Bare
  Agent Profile launch is fully supported.
- **Model is unavailable for Droid and Amp Profiles.** Droid's model and
  reasoning flags belong to `droid exec`, not the interactive root command;
  Amp's `--mode` selects a bundled agent mode rather than a model identifier.
- **Reasoning effort is unavailable for Gemini, Cursor, Kimi, and Droid.** A
  boolean thinking switch is not rendered through Prowl's scalar effort field.
- **Unrestricted mode is hidden for Cline, Droid, Amp, Grok, and Pi.** Their
  closest flags do not prove the exact Prowl promise of both no permission
  prompts and no sandboxing. Experts can still use Extra Arguments, and the UI
  will say the effective mode follows those arguments instead of making a
  false Standard/Unrestricted claim.
- **Only Claude Code and Codex remain admitted to side-effect-free Prowl
  resume.** Other CLIs may resume or fork sessions, but output capture,
  source-session immutability, confidence gates, and timeout/error behavior
  have not yet been proven as one protocol. Generic Profile registration no
  longer implies resume support.

## Account isolation evidence

| Runtime | Evidence and session-root consequence |
| --- | --- |
| Claude Code | Existing live support; `CLAUDE_CONFIG_DIR` points directly at the managed root. |
| Codex | Existing live support; `CODEX_HOME` points directly at the managed root. |
| Gemini CLI | [Official configuration](https://geminicli.com/docs/reference/configuration/) documents `GEMINI_CLI_HOME` as a user-home base; Gemini creates `.gemini` beneath it, so Prowl records `<managed>/.gemini` for session resolution. |
| Cline CLI | Local 2.18 help documents separate config, data, and hooks directories. A temporary `CLINE_DATA_DIR` run created state under that directory; Prowl supplies all three CLI paths and resolves sessions under `<managed>/data/tasks`. |
| GitHub Copilot | Local `copilot help environment` and the [official CLI reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference) identify `COPILOT_HOME`; session-state and pid logs are rooted directly below it. |
| Qoder CLI | Local 1.0.48 help describes `--config-dir` as a custom user-level config root; local session layout remains `projects/<cwd>/<uuid>.jsonl` below it. |
| Qwen Code | [Official settings documentation](https://qwenlm.github.io/qwen-code-docs/en/users/configuration/settings/) documents `QWEN_HOME` for credentials, settings, memory, skills, and global state. Prowl resolves projects and pid sidecars directly below that root. |
| Pi | [Upstream documentation](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent) documents `PI_CODING_AGENT_DIR`; session and user capability discovery are below that directory. |
| Oh My Pi | Local help documents the same variable. Upstream `profile-isolation.test.ts` additionally proves user commands and skills follow `getAgentDir()` rather than leaking from the default `~/.omp/agent`; Prowl uses its managed path instead of OMP's name-based profile location. |

## Architecture findings

The original adapter required start, observation, account isolation, and safe
resume together. Registration therefore meant `canStart == canResume`, and a
single `accountHomeEnvironmentVariable` assumed the provisioned directory was
also the native session root. Both assumptions fail in the expanded catalog.

The implementation now uses:

- a launch adapter keyed by `AgentProfileRuntime`, preserving Pi/OMP executable
  identity while mapping both to the Pi detection family;
- independent profile-field capabilities, so the editor renders only options
  the adapter can implement honestly;
- an optional `AgentProfileHomeRelocation` that supports environment variables,
  one or more managed path arguments, and a distinct session root;
- a separate resume-adapter lookup, leaving `canResume` true only for proven
  workflows;
- an explicit Handoff destination policy, so expanding generic launch support
  cannot silently expand the current handoff UX.

This boundary is suitable for a later profile-based handoff or cross-review
workflow: it can select a Profile, require prompted-interactive or headless
support as appropriate, and independently require safe resume when it needs to
prepare context from a native session.

## Installation and credential notes

Qwen Code was the only missing executable. It was installed from its official
Homebrew distribution (`brew install qwen-code`) and validated in a Prowl pane.
The installed release no longer offers the old free OAuth path; it opened
provider setup and no paid credential was added. The Profile adapter is based
on local help plus the official [Quickstart](https://qwenlm.github.io/qwen-code-docs/en/users/quickstart/)
and configuration documentation, with authenticated task execution left for
community/user verification.
