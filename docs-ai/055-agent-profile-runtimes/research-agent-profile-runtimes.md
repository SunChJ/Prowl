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

`DetectedAgent` and Agent Profiles now expose the same fifteen runtime
families. `pi` identifies Pi; `omp` and `oh-my-pi` identify Oh My Pi. The two
runtimes are independent even though OMP originated as a Pi fork.

| Detection token | Launch runtime | Installed version | Prowl validation |
| --- | --- | --- | --- |
| `pi` | Pi / `pi` | 0.82.0 | Detected as `pi` |
| `omp` | Oh My Pi / `omp` | 17.2.1 | Live guarded launch reproduced the installed baseline's incorrect `pi` collapse; independent `.omp` output is covered by the shipped production-path tests |
| `claude` | Claude Code / `claude` | 2.1.220 | Detected as `claude` |
| `codex` | Codex / `codex` | 0.146.0 | Detected as `codex` |
| `gemini` | Gemini CLI / `gemini` | 0.46.0 | Detected as `gemini`; workspace trust screen shown |
| `cursor-agent` | Cursor Agent / `cursor-agent` | 2026.05.09-0afadcc | Detected as `cursor-agent` |
| `cline` | Cline CLI / `cline --tui` | 3.0.48 | Detected as `cline`; bare `cline` was rejected as the Profile entry because it opens Kanban |
| `opencode` | OpenCode / `opencode` | 1.17.18 | Detected as `opencode` |
| `copilot` | GitHub Copilot CLI / `copilot` | 1.0.70 | Detected as `copilot`; workspace trust screen shown |
| `kimi` | Kimi Code CLI / `kimi` | 1.41.0 | Detected as `kimi`; update notice shown |
| `droid` | Factory Droid / `droid` | 0.186.0 | Detected as `droid` |
| `amp` | Amp / `amp` | 0.0.1783746383-g8a60c7 | Detected as `amp` |
| `qodercli` | Qoder CLI / `qodercli` | 1.0.48 | Detected as `qodercli`; existing login accepted |
| `qwen` | Qwen Code / `qwen` | 0.21.2 | Installed during research; detected as `qwen`; provider setup required |
| `grok` | Grok Build / `grok` | 0.2.118 | Detected as `grok` |

Every disposable tab was closed by its exact pane/tab identifier and focus was
returned to the original development pane. No missing credential prevented
interactive startup or Prowl detection. Qwen had no configured provider, so
authenticated task execution remains **Best effort** rather than Live proof.

The execution-policy follow-up was also exercised live: Cline rendered
`Auto-approve all disabled` under `--auto-approve false`; Grok accepted
`--permission-mode default`; and OMP accepted `--approval-mode always-ask`.
The installed pre-PR app reported that OMP pane as `pi`, reproducing the split's
product bug, and OMP printed a concrete `omp --resume <id>` command on exit.
The newly built Debug app could not host a second terminal runtime beside the
running production app (`runtimeSurfaces=0`), so post-split `.omp` output is
validated by classifier, session resolver, Active Agents, and CLI payload tests
rather than mislabeled as a same-process live check.

## Shipped capability matrix

Legend: ✅ exposed or admitted by Prowl; — deliberately hidden because the CLI
contract cannot satisfy Prowl's field semantics; ⚠️ native behavior exists but
is not admitted to the stricter Prowl workflow.

| Runtime | Interactive / prompt / headless | Model | Reasoning | Execution mode selection | Dedicated home | Native resume / fork | Handoff-safe source briefing | Profile |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Claude Code | ✅ / ✅ / `-p` | ✅ | `--effort` | bare / `--dangerously-skip-permissions` | `CLAUDE_CONFIG_DIR` | ✅ / ✅ | ✅ forked print resume | ✅ |
| Codex | ✅ / ✅ / `exec` | ✅ | `model_reasoning_effort` | guarded / bypass approvals and sandbox | `CODEX_HOME` | ✅ / ephemeral | ✅ ephemeral exec resume | ✅ |
| Gemini CLI | ✅ / `--prompt-interactive` / `--prompt` | ✅ | — | bare / YOLO plus sandbox disabled | `GEMINI_CLI_HOME`; sessions under `.gemini` | ✅ / — | ⚠️ not admitted | ✅ |
| Cursor Agent | ✅ / positional / `--print` | ✅ | — | bare / YOLO plus sandbox disabled | **— no verified full-state relocation** | ✅ / — | ⚠️ not admitted | ✅ |
| Cline CLI | `--tui` / `--tui <prompt>` / positional | ✅ | `--thinking` | `--auto-approve false` / `true` | `--config`, `--data-dir`, and `--hooks-dir` | ✅ task / — | ⚠️ not admitted | ✅ |
| OpenCode | ✅ / `--prompt` / `run` | ✅ | `--variant` | bare / `--auto` | **— config-dir only; auth and sessions remain in XDG data** | ✅ / ✅ | ⚠️ not admitted | ✅ |
| GitHub Copilot | ✅ / `--interactive` / `--prompt` | ✅ | `--reasoning-effort` | bare / `--allow-all` | `COPILOT_HOME` | ✅ / — | ⚠️ not admitted | ✅ |
| Kimi Code | ✅ / `--prompt` / `--print --prompt` | ✅ | — (boolean thinking is not an effort scale) | bare / `--yolo` | **— alternate paths do not relocate every data class** | ✅ / ✅ | ⚠️ not admitted | ✅ |
| Factory Droid | ✅ / positional / `exec` | **— interactive CLI has no model option** | — | **— tiered interactive autonomy; full bypass is headless-only** | **— settings overlay only** | ✅ / ✅ | ⚠️ not admitted | ✅ |
| Amp | ✅ / **— seeded interactive prompt unavailable** / `--execute` | **— `--mode` is not a model selector** | `--effort` | **— default has no approval prompts; guarded mode is settings-only** | **— settings/log paths do not relocate auth and threads** | ✅ continue / — | ⚠️ not admitted | ✅ bare launch |
| Qoder CLI | ✅ / `--prompt-interactive` / `--print` | ✅ | `--reasoning-effort` | bare / skip permissions | `--config-dir` | ✅ / ✅ | ⚠️ not admitted | ✅ |
| Qwen Code | ✅ / `--prompt-interactive` / `--prompt` | ✅ | `--reasoning-effort` | bare / YOLO plus sandbox disabled | `QWEN_HOME` | ✅ / — | ⚠️ not admitted | ✅ Best effort |
| Grok Build | ✅ / positional / `--single` | ✅ | `--reasoning-effort` | `default` / `bypassPermissions` plus sandbox off | **— no verified full-state relocation** | ✅ / ✅ | ⚠️ not admitted | ✅ |
| Pi | ✅ / positional / `--print` | ✅ | `--thinking` | **— default has no approval prompts or sandbox; no guarded CLI mode** | `PI_CODING_AGENT_DIR` | ✅ / ✅ | ⚠️ not admitted | ✅ |
| Oh My Pi | ✅ / positional / `--print` | ✅ | `--thinking` | `always-ask` / `yolo` | `PI_CODING_AGENT_DIR` | ✅ / ✅ | ⚠️ not admitted | ✅ |

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
- **Execution mode is hidden only for Droid, Amp, and Pi.** Droid's interactive
  `--auto low|medium|high` values are a third, tiered autonomy model, while its
  full bypass is available only on headless `droid exec`. Amp and Pi default to
  no approval prompts, but neither exposes a launch flag for the inverse,
  approval-required Standard mode. Cline, Grok, and Oh My Pi do expose both
  sides, so Prowl renders their guarded flag for Standard and their
  least-restricted flag(s) for Unrestricted.
- **Only Claude Code and Codex remain admitted to handoff-safe source
  briefing.** Other CLIs may resume or fork sessions, but output capture,
  source-session immutability, confidence gates, and timeout/error behavior
  have not yet been proven as one protocol. Generic Profile registration no
  longer implies resume support.

### Permission-semantics evidence

- [Pi's coding-agent README](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/README.md)
  explicitly rejects permission popups and recommends a container or extension
  for confirmation flows. `pi --approve` means project resource trust, not tool
  approval; `--tools`, `--exclude-tools`, and `--no-tools` filter capabilities
  but do not create Prowl's Standard mode.
- [Cline's CLI reference](https://docs.cline.bot/cli/cli-reference) documents
  `--auto-approve <boolean>`, allowing Prowl to render both values explicitly.
- [Droid's CLI reference](https://docs.factory.ai/reference/cli-reference)
  documents tiered `--auto` for the interactive root and limits
  `--skip-permissions-unsafe` to `droid exec`.
- [Amp's manual](https://ampcode.com/manual) and
  [permission announcement](https://ampcode.com/news/neo) place guarded-file
  behavior in settings/plugins, not a per-launch inverse flag.
- [Grok's permission](https://docs.x.ai/build/features/permissions) and
  [sandbox](https://docs.x.ai/build/features/sandbox) documentation show that
  the two axes are independent, so Unrestricted must set both.
- [Oh My Pi's approval-mode documentation](https://github.com/can1357/oh-my-pi/blob/main/docs/approval-mode.md)
  defines `always-ask`, `write`, and `yolo`. Prowl maps the first and last while
  leaving the middle tier to Extra Arguments.

## Account isolation evidence

| Runtime | Evidence and session-root consequence |
| --- | --- |
| Claude Code | Existing live support; `CLAUDE_CONFIG_DIR` points directly at the managed root. |
| Codex | Existing live support; `CODEX_HOME` points directly at the managed root. |
| Gemini CLI | [Official configuration](https://geminicli.com/docs/reference/configuration/) documents `GEMINI_CLI_HOME` as a user-home base; Gemini creates `.gemini` beneath it, so Prowl records `<managed>/.gemini` for session resolution. |
| Cline CLI | Local 3.0.48 help documents separate config, data, and hooks directories. A temporary `CLINE_DATA_DIR` run created state under that directory; Prowl supplies all three CLI paths and resolves sessions under `<managed>/data/tasks`. |
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

- a launch adapter keyed by `AgentProfileRuntime`, with a one-to-one mapping to
  the canonical detected runtime, including independent Pi and OMP families;
- independent profile-field capabilities, so the editor renders only options
  the adapter can implement honestly;
- an adapter-declared execution-mode set, so a runtime may render both guarded
  and least-restricted modes with asymmetric flags, or hide the field entirely;
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
