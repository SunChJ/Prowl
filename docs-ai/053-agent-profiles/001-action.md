# 053 — Agent Profiles: Action

| | |
| --- | --- |
| **日期** | 2026-07-29 |
| **分支** | `agent/agent-profiles-v1` |
| **前置** | [000-plan.md](000-plan.md)(含全部讨论修订)· [002-home-spike.md](002-home-spike.md)(HOME 实测) |

## 实施概要

按计划分五个提交块实现,每块独立通过测试、lint 与构建:

1. **`8fa9c5b5` — domain 与 adapter**:`AgentProfile` 模型(preset 字段 + placement +
   可选账号绑定)、normalization、三层推荐 resolver、`ShellWordSplitter`;
   `AgentStartIntent`(`.interactive` / `.prompt` / `.headless`)取代恒有 prompt,
   handoff 调用点迁移;`AgentLaunchConfiguration` 增加 effort 与 extraArguments
   (向后兼容解码);adapter 声明能力位(`CLAUDE_CONFIG_DIR` / `CODEX_HOME`)与
   effort 建议;`UserGlobalSettings` / `UserRepositorySettings` 扩展。
2. **`b542cadb` — launch plan 与终端/检测**:`AgentProfileLaunchPlanner`(纯函数,
   预览与启动共用渲染)、`AgentProfileHomeProvisioner`(0700 + 包含校验)、
   `~/.prowl/agent-profiles/` 路径;`TerminalClient.launchAgentProfile` 经
   `GhosttySurfaceView(environment:)` 注入补丁,split 无可分割时退化为 tab,
   surface 记录 launch 身份;claude/codex 的 `AgentSessionProfile` 增加 rooted
   布局,resolver 对绑定 surface 独占使用。
3. **`ff536478` — AppFeature**:单一 `launchAgentProfile` action(解析 → 计划 →
   终端命令 + per-repo 记忆);`AgentProfileSeeder` 启动时一次性播种(安装启发:
   默认 home 存在),删除的种子不复活。
4. **`a87d8f69` — Settings UI**:独立 Agents tab(列表顺序即兜底优先级、编辑器、
   Advanced 附加参数/绑定/预览);`.unrestricted` 保存前确认;绑定 profile 删除
   走"确认 + 默认保留 + 可选 Trash";`AgentProfileHomeClient` 统一文件操作与
   包含闸;Repo Settings 增加 Default Agent Profile 选择器。
5. **`cf446750` — 入口与身份露出**:Agents capsule 永远是菜单(Hand Off 领衔、
   推荐排前、未安装灰显示因、Manage 入口);palette "Launch Agent" 行共享同一
   action;Prowl 启动的 pane 在 Active Agents/capsule 显示 launch 时冻结的
   profile 名。

文档同步:新增 `docs/components/agent-profiles.md`,并更新 settings /
command-palette / active-agents / handoff 与 `docs/README.md` 索引。

## 测试证据

- 全量套件:`make test` 通过,**2105 个测试全绿**(5 个 warning 为 SPM 依赖扫描
  既有噪音)。
- 新增/扩展:`AgentProfileTests`(normalization、推荐回退、splitter、launch plan、
  包含校验、provisioner 权限、settings 兼容解码)、`AgentRuntimeAdapterTests`
  (三态 argv、effort 映射、附加参数顺序、能力位、legacy 解码)、
  `AgentProfilesFeatureTests`(增删改排、unrestricted 确认、绑定删除 Trash、
  repo 默认持久化)、`AppFeatureAgentProfileTests`(launch 命令与记忆、禁用忽略、
  播种一次性、palette 条目、身份展示)、`AgentSessionProfileTests` rooted 布局。
- `make check` 与 `make build-app` 全程零错误零警告。
- 前置实测见 002-home-spike.md(指令文件/skills 原生拾取、凭证落点、并行登录
  无串号、真实 home 零污染)。

## 与计划的偏差

1. **model 建议列表未实现**:model 为纯自由文本,只有 effort 有 adapter 建议列表。
   原因:没有可靠的已验证 model 目录,硬编码会立即过时;后续可与 effort 同构补上。
   (2026-07-31 追记:已按同构方式补上,adapter 现声明 `modelSuggestions`;本偏差关闭。)
2. **resume 携带环境补丁推迟到 handoff 波次**:检测层的 config root 已实现,但
   `AgentResumeRequest` 未增加环境字段——填充它需要 handoff 的结构化请求改造
   (正是计划明确推迟的双路径工程)。当前从绑定 pane 发起 handoff 时,briefing
   resume 会找不到 session 并优雅降级为 context-only。已知且可接受。
   (2026-08-01 追记:[047.006](../047-cross-agent-handoff/006-remove-fork-briefing.md)
   已删除 briefing resume;该偏差不再存在。)
3. **Settings 列表排序用上下移动(右键菜单)而非拖拽**:Form 内拖拽在 macOS 上
   体验不佳;顺序语义(兜底优先级)不受影响。
