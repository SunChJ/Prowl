# 053.003 — Agent Profile 图标

| | |
| --- | --- |
| **状态** | Implemented |
| **日期** | 2026-07-31 |
| **相关** | [000-plan](000-plan.md) · [001-action](001-action.md) · `docs/components/agent-profiles.md` |

## Context

Agent Profile 是用户在 Settings、工具栏 Agents popover 与 Command Palette 中选择的
命名 preset。现有行只显示通用启动图标，无法在多个同 runtime profile 之间建立视觉
识别；但 profile 未设置图标时不应丢失 Claude Code / Codex 的品牌识别。

## Scope

- 为 `AgentProfile` 增加可选 SF Symbol override；旧 JSON 解码为 `nil`。
- Settings → Agents 的编辑器提供与 repository appearance 同样的预览 tile 与图标菜单，
  复用 `TabIconPickerView` 的 preset / 任意 SF Symbol 输入能力。
- 在 Settings profile 列表、toolbar Agents popover 和 Command Palette 的 profile launch
  条目显示 resolved profile icon。
- 未设置 override 时，以上 surface 使用 runtime 的 `CommandIconMap` 品牌 asset，找不到
  asset 时回退其 SF Symbol。

## Design decisions

1. 持久化值为可选 SF Symbol 名称，而不是 `RepositoryIconSource`。Profile 是全局设置，
   没有 repository-root 作为用户图片生命周期与导入目录的自然所有者；支持图片会增加
   资产存储与清理契约，却没有本功能需要。
2. 图标属于 profile launcher 的身份，不改变已运行 terminal pane 或 Active Agents 的
   进程识别 icon。后两者表示实际检测到的 CLI，不应因 profile 后续编辑或删除而改变。
3. `nil` 不是通用 placeholder，而是 runtime 品牌 icon。清除 override 立即恢复 Claude
   Code / Codex 的既有品牌识别。

## Implementation shape

| Concern | Planned owner |
| --- | --- |
| Persistence / migration | `supacode/Domain/AgentProfile/AgentProfile.swift` |
| Icon resolution and rendering | shared profile-icon view beside Settings / launcher surfaces |
| Picker state and mutation | `AgentProfileEditorFeature` + `AgentProfileEditorView` |
| Settings list | `AgentProfilesSettingsView` |
| Toolbar launcher | `AgentsToolbarButton` + `WorktreeDetailView` |
| Command Palette launcher | `CommandPaletteItem` + `CommandPaletteOverlayView` |

## Result

- `AgentProfile.icon` persists an optional SF Symbol; legacy records decode it as `nil`.
- `AgentProfileIconResolver` maps an override to an SF Symbol and `nil` to the existing
  `CommandIconMap` runtime brand asset with a `sparkles` safety fallback.
- Settings now has the repository-style icon preview menu and `TabIconPickerView`; the
  profile list and repository Default Agent Profile picker render the resolved icon.
- Toolbar Agents launch rows and Command Palette launch rows carry the same resolved
  profile source. Live panes and Active Agents retain detected process-brand icons.

## Verification

- Legacy decode keeps `icon == nil`; edited profile persists an override.
- Reducer test covers setting and clearing the override.
- Launcher and palette factories carry the resolved custom icon and runtime fallback.
- Build the app, run changed-file checks, then manually inspect Settings and the Agents popover.

## Non-goals

- Per-profile colors, imported bitmap/SVG assets, or agent-specific image storage.
- Replacing live terminal / Active Agents process-brand icons.
