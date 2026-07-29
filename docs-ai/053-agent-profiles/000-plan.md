# 053 — Agent Profiles: Plan

| | |
| --- | --- |
| **Status** | Planned |
| **Anchor date** | 2026-07-29 |
| **Primary PRs** | pending |
| **Related** | [047 cross-agent handoff](../047-cross-agent-handoff/000-plan.md), [048 agent runtime adapters](../048-agent-runtime-adapters/000-plan.md), [049 Agents toolbar entry](../049-agents-toolbar-entry/000-plan.md), closed prototype [#617](https://github.com/onevcat/Prowl/pull/617) |

## 背景

Prowl 目前只能安全启动 Claude Code 和 Codex 两种已验证的 runtime。adapter 层
(`AgentRuntimeAdapter`) 已经拥有结构化的 model / execution-mode argv 渲染,工具栏 Agents
capsule 的无 agent 形态被预留给快速启动入口。尚不存在持久化的 profile、面向用户的启动器,
或账号选择能力。

已关闭的原型 [#617](https://github.com/onevcat/Prowl/pull/617) 验证了 `CLAUDE_CONFIG_DIR` 与
`CODEX_HOME` 可以让两份登录并存,同时也暴露了关键约束:这两个环境变量搬走的是 runtime 的
**整个 home**——skills、全局指令文件(`CLAUDE.md` / `AGENTS.md`)、session 历史、settings
全部跟随,而不仅仅是凭据。

### 本次重写的动因

本计划的初稿把"每个 profile 无条件派生一个私有 runtime home"作为核心机制。讨论后确认这
混淆了两根正交的轴:

| 轴 | 机制 | 副作用 |
| --- | --- | --- |
| **Preset 轴**:model、reasoning effort、execution mode | 纯 argv,adapter 已支持 | 零副作用,天然共享 skills / 全局指令 / session 历史 |
| **Account 轴**:独立登录与用量 | 只能搬 home(#617 唯一验证过的机制) | 把 skills、指令、历史全部拖入隔离 |

Profile 的本体是 **preset**(对已知 runtime 的一组命名预置配置);账号隔离是一个**可选的、
按 runtime 能力位门控的绑定**,用户显式选择并知情承担隔离代价。用量跟随 OAuth 登录,
"只分用量不分登录"不存在中间路线。

## 目标

- 为两种已验证 runtime(Claude Code、Codex)定义命名 profile;同一 runtime 可有多个
  profile,profile 不等于品牌。
- 从 Agents 菜单选择 profile 后,在当前 worktree 新建并选中一个 tab,以交互模式启动
  agent,无初始 prompt。
- 每个 profile 持久化可选 model、可选 reasoning effort、显式 execution mode,全部以 argv
  渲染。
- **默认形态(纯 preset)**:profile 运行在共享的默认 home,不设置任何环境变量;skills、
  全局指令、session 历史与 `--resume` 列表保持统一。
- **可选账号绑定(opt-in)**:profile 显式绑定独立账号时,才派生私有 runtime home,用于
  独立登录与独立用量;仅此时出现登录/状态管理控件。
- Agents capsule 永远是菜单:列出推荐与已启用的 profile、不可用项及原因、管理入口;有
  运行中 agent 时附带现有 Active Agents 内容。
- 路径 route 为每个 worktree 选出初始推荐 profile。
- Profile UUID 保持稳定,使未来的 handoff 集成可以引用 profile 而非裸 agent token。

### 非目标

- 不改动现有 Hand Off UI、`prowl handoff` 契约或继承配置行为。
- 不把 API key、OAuth token、`auth.json` 内容放进 Prowl JSON、日志、分析或 SwiftUI 状态;
  V1 只使用 CLI 自管认证。裸 API key 输入(需 Keychain 引用 + agent-only 启动边界)整体
  推迟。
- 不接受任意可执行文件路径、shell 片段或自由格式 CLI flag。
- 不在 profile 或 route 变化时修改运行中的 pane,不拦截用户在既有 shell 中手动输入的
  `claude` / `codex`。
- 不支持检测到但未验证的 runtime。
- 不做共享配置的自动 symlink(#617 教训);账号绑定 profile 的**子目录级显式共享**
  (如 skills/、session 目录)列为 follow-up,不进 V1。
- 不做 per-profile 指令/skill 注入:Claude Code 有 `--append-system-prompt` 等通道,但
  Codex 交互式 TUI 没有已验证的等价机制;建模为未来的 adapter 能力位后再做。
- 不做 profile 导入/导出或 skills / 指令文件的可视化编辑器。

## 产品形态

### Profile 与 Settings

Settings 新增 **Agents** 区,持有有序的全局 profile 集合与 path route,存放于
`UserGlobalSettings` 而非 repository settings:账号与 agent 偏好是本地用户的私有配置,
不得成为仓库配置。

一个 profile 包含:稳定 UUID、显示名、启用状态、runtime、可选 model、可选 reasoning
effort、既有的显式 execution mode、启动位置(placement),以及**可选的账号绑定**。reasoning effort 存为自由
字符串,`nil` 表示 runtime 默认;编辑器按 runtime 展示 adapter 自带的已知档位建议
(两家共有的 low/medium/high,及各自的扩展档位,如 Codex 的 `minimal` / `xhigh`),同时
允许直接填写任意值。自定义值只作为**单一参数值**渲染进类型化参数——Claude Code 的
`--effort`、Codex 的 `model_reasoning_effort` config override——走既有的安全 argv 渲染,
不经过 shell 解释;未知档位由 CLI 启动时自行报错,在新 tab 内直接可见,Prowl 不做预校验。
`.unrestricted` 保留但视觉上标记为危险,保存时需要显式确认;绝不从其他 profile 或来源
pane 推断。

**未绑定账号的 profile(默认)**:不派生目录、不设置环境变量、不显示登录控件;状态栏
说明其使用系统默认登录。

**绑定账号的 profile**:编辑器提供 **Sign In**、**Refresh status**、**Reveal Profile
Files**。Sign In 新开一个已附加 profile 环境的终端 tab,运行该 runtime 的常规登录命令。
状态探测以 CLI 输出而非退出码为准:两家 CLI 都可能在未登录时返回非零,Codex 可能经
stderr 报告。home 不存在时直接判定"未登录",不得先调用 Codex。绑定开关旁必须写明隔离
代价:该 profile 将拥有独立的 skills、全局指令与 session 历史。

### 启动与 Agents 菜单

Agents capsule 不再因无运行中 agent 而禁用,而是**永远作为菜单**存在:

- 无 agent 时:当前 worktree 的 **Recommended** profile 排最前,其后是全部已启用
  profile;不可用项(CLI 未安装、profile 被禁用)灰显并展示原因;底部提供
  "Manage Agent Profiles…" 直达 Settings。
- 有运行中 agent 时:保留现有 Active Agents / Hand Off 内容,并附带上述启动项。

选择 profile 即在该 worktree 新建一个 surface 并以交互模式启动 runtime,无初始 prompt。
启动位置由 profile 的 placement 决定:**New Tab**(默认)或 **New Split**(带方向,复用
custom command 既有的 `UserCustomSplitDirection`)。split 同样是全新 surface,身份记录与
结构化启动规则完全一致;当该 worktree 尚无可分割的 surface 时,split 退化为新 tab。绝不
向既有 shell 注入文本:Prowl 无法证明那个 shell 处于空闲、可安全接管的状态。

Prowl 启动的 surface 在创建时记录 profile UUID;检测到但非 Prowl 启动的 agent 只显示
"检测到 Codex"这类事实,绝不猜测其归属的 profile 或账号。

### 路由

Route 把标准化的本地路径前缀映射到 profile UUID。最长目录边界匹配获胜;可选的
per-runtime 默认项覆盖未匹配的仓库。解析是只读的,不创建任何目录。Route 只决定初始
推荐——显式选择其他 profile 永远优先。profile 在启动时记录到新 surface 上,之后的 route
编辑绝不重新标记或修改活跃 pane。

### 账号绑定与 runtime home(opt-in)

账号绑定由 adapter 能力位(`supportsAccountIsolation`)门控;两家已验证 runtime 均通过
`CLAUDE_CONFIG_DIR` / `CODEX_HOME` 支持。

绑定 profile 的 home 从其 UUID 派生,位于 Prowl 数据目录之下,绝不来自显示名或用户
提供的路径。启动准备阶段先创建 runtime 目录(Codex 拒绝不存在的 `CODEX_HOME`)、校验
解析后的路径仍在 profile-home 基目录内,并施加 owner-only 权限。

home 对 Prowl 是不透明的:对应环境变量只附加到新终端 surface——Claude Code 用
`CLAUDE_CONFIG_DIR`,Codex 用 `CODEX_HOME`——使启动的 agent 及其子进程看到选定上下文。
Prowl 不解析、不复制、不展示凭据文件。用户在该 home 内自行管理 runtime 支持的文件;
项目内的指令文件仍归项目所有。

Follow-up(非 V1):为绑定 profile 提供子目录级的显式共享开关(目录 symlink 接回默认
home 的 skills/、session 目录)。#617 的分叉教训针对的是会被 CLI 原子重写的文件
(`settings.json`、`config.toml`、`auth.json`),这几个永远不得共享;以读为主的子目录
风险可控,但仍需逐 runtime 验证后才能提供。

## 实现方式

1. 引入 Codable 的 `AgentProfile` domain model(preset 字段 + placement + 可选账号绑定)
   与 route resolver 及 normalization 测试。runtime enum 限定为 Claude Code 与 Codex,校验非空
   显示名与 UUID 唯一性,normalization 时丢弃指向不可用 profile 的 route。扩展
   `supacode/Features/Settings/Models/UserGlobalSettings.swift` 及其 shared key,兼容缺少
   新字段的既有 JSON。
2. 在 `supacode/Domain/AgentRuntime/AgentRuntimeAdapter.swift` 中把启动意图类型化为
   `.interactive` 或 `.prompt(String)`,禁止空 prompt 哨兵。`AgentLaunchConfiguration`
   增加可选 reasoning effort,由各 adapter 自行完成 argv/config 映射与校验。为 adapter
   增加能力位:V1 实际使用 `supportsAccountIsolation`,为 handoff 与指令注入预留位置,
   取代散落的品牌硬编码判断。
3. 把 profile 解析为单一 launch specification:profile UUID、类型化启动请求、argv、
   placement,以及**仅账号绑定时非空**的环境 patch。扩展
   `supacode/Clients/Terminal/TerminalClient.swift` 与
   `supacode/Features/Terminal/Models/WorktreeTerminalState.swift` 的 surface 创建路径,
   使新 tab 与新 split 均经 `GhosttySurfaceView(environment:)` 接收 patch;不得把环境
   变量赋值拼进 shell 输入。在既有检测状态旁记录每个 surface 的启动 profile。
4. 新增小型 Settings reducer/view:profile 编辑、route 编辑,以及账号绑定分支的状态/登录
   动作。文件操作全部藏在注入的 profile-home dependency 之后,测试绝不触碰真实登录目录。
5. 扩展 `supacode/Features/Repositories/Views/AgentsToolbarButton.swift` 及其在
   `supacode/Features/Repositories/Views/WorktreeDetailView.swift` 中的接线:改为永远是
   菜单;检测态保留现有 Hand Off 动作,启动项经 `AppFeature` 派发单一 profile-launch
   action。
6. 实现完成后,更新对应的现状文档,并以实际 PR 与测试证据撰写 `001-action.md`。

## 从 #617 带入的经验

| 发现 | Profile 决策 |
| --- | --- |
| Per-surface 环境变量可隔离两份 CLI 登录。 | 环境变量只在新 surface 启动边界施加,且仅限账号绑定 profile。 |
| `CODEX_HOME` 必须在 Codex 启动前存在。 | 启动或登录前先创建派生 home。 |
| 搬迁后的 home 包含 settings 与 skills,不止认证文件。 | 隔离是全有或全无的账号轴代价,因此 preset 为默认、绑定为 opt-in。 |
| 共享配置的 symlink 会在 CLI 重写文件时静默分叉。 | V1 不做任何自动 link;被重写的文件永不共享,子目录共享留作显式 follow-up。 |
| 账号/路径变化不得影响活跃 pane。 | surface 创建时记录 profile ID;route 只影响后续启动。 |
| 认证状态输出对流与退出码敏感。 | 在可测试的 client 后解析两条流的已知输出。 |

## Handoff 边界

Profile 是 V1 的**启动**特性,与 049 划定的边界一致。其稳定 ID 与解析后的 launch
specification 有意可被 handoff 复用,但 V1 的 handoff 目标列表维持现有 agent 列表不变。

未来的 handoff 集成必须让选定 profile 同时贯穿两条路径:HUD 的注入请求与 CLI/fallback
处理器。只更新 `supacode/Features/HandoffHud/Reducer/HandoffHudFeature.swift` 会让 fallback
静默丢失 profile,因为 `supacode/CLIService/HandoffCommandHandler.swift` 目前会重建继承
配置。该阶段应扩展结构化的 handoff request/registry 边界;绝不能在请求开始后再读取
"当前 profile"。

## 验证

- Domain 测试:profile normalization、UUID 稳定性、非法/缺失 route、最长路径边界匹配、
  旧版 JSON 解码、无任何持久化的敏感材料;纯 preset profile 必须产生空环境 patch。
- Adapter 测试(`supacodeTests/AgentRuntimeAdapterTests.swift`):无 prompt 的交互式
  argv、model/effort 映射(含自定义 effort 值的安全渲染)、标准与危险模式、shell 转义、
  能力位取值。
- Settings 与 profile-home 测试:保存/重载、绑定 profile 的派生目录 owner-only 权限、
  home 缺失时的状态判定、stdout/stderr/非零退出码的登录状态解析、绝不访问真实凭据。
- Reducer/终端测试:菜单各可用性状态、正确的 worktree/cwd/环境 patch、每次选择恰好新建
  一个 surface(tab 或按 placement 的 split,空 worktree 时 split 退化为 tab)、route
  编辑后 surface 的 profile 身份保持稳定、纯 preset 启动不设任何环境变量。
- 手动验证:(a) 同一 runtime 的两个纯 preset(不同 model/effort)并排启动,确认共享同一
  登录且 `--resume` 历史统一;(b) 两个账号绑定 profile 分别登录不同账号并排运行,确认
  各 CLI 报告自己的身份;(c) 修改 route 后确认只有后续启动受影响。

## 备选与决策

- **Preset 优先,而非 home 优先。** 初稿把私有 home 当作 profile 本体,把账号轴的隔离
  代价强加给所有 profile;重写后 preset 是默认形态,绝大多数用例零副作用。
- **隔离 opt-in,而非无条件。** 用户显式勾选账号绑定并知情承担 skills/历史隔离的代价;
  UI 必须写明该代价。
- **能力位,而非品牌硬编码。** `supportsAccountIsolation` 等 adapter 能力位使 V1 仍只
  发货两家 runtime,但结构上为后续 runtime 留门。
- **Profile home 优于裸凭据。** 保留 CLI 支持的认证流程,避免 Prowl 变成密钥管理器;
  Keychain 引用只对未来的裸 API key 场景有意义,整体推迟。
- **新 tab 优于向当前 shell 注入。** 保护进行中的 shell 工作,并让 agent 从进程启动起
  就拥有一致环境。
- **全局路径 route 优于 per-repository 持久化账号名。** 最长前缀解析自动完成工作/个人
  切换,不把本地身份泄漏进仓库配置。
- **不做自动共享配置 symlink。** 便利是真实的,但 #617 观察到的歧义与静默分叉使其不适
  合作为 V1 默认;子目录级显式共享作为 follow-up 逐项验证。
- **指令/skill 注入推迟。** Codex 侧没有已验证的注入机制;作为 adapter 能力位在后续
  波次实现,避免 V1 只对单一 runtime 成立的承诺。
- **Handoff 后续跟进,而非部分集成。** Profile-aware 的 handoff 必须在正常与 fallback
  两条执行路径上同时正确;推迟比让两者不一致更安全。

## Amendments

- 2026-07-29 — 依据与 onevcat 的设计讨论全文重写并改用中文:profile 从"私有 runtime
  home"重新定义为"preset + 可选账号绑定";新增 adapter 能力位与永远是菜单的 Agents
  capsule;指令/skill 注入与子目录共享明确列为 follow-up;handoff 边界维持不变。
- 2026-07-29 — reasoning effort 从固定三档改为"per-runtime 建议档位 + 自由填值":档位
  集合随模型演进,硬编码枚举会过时;自定义值仅作为类型化参数的单一值渲染,不构成自由
  格式 flag。execution mode 维持既有 `standard` / `unrestricted` 两档不变。
- 2026-07-29 — profile 新增 per-profile 启动位置(placement):New Tab(默认)或
  New Split(方向复用 custom command 的 `UserCustomSplitDirection`);无可分割 surface
  时退化为新 tab。粒度与 custom command 的 per-command 先例一致。
