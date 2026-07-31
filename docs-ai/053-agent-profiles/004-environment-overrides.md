# 053 修订:Profile 自定义环境变量(Environment Overrides)

- 日期:2026-07-31
- 状态:计划(实现前);实现结果回填至本文档末尾
- 关联:[000-plan.md](000-plan.md)(launch plan 管道)、[001-action.md](001-action.md)
  (resume 环境补丁的既有推迟)

## 背景与动机

053 的环境补丁(`AgentProfileLaunchPlan.environment`)目前只有一个内部来源:
`bindsDedicatedHome` 写入 `CLAUDE_CONFIG_DIR` / `CODEX_HOME`。onevcat 需要用户可
配置的 per-profile 环境变量覆盖,典型场景是临时改写 base url / api key——例如
`OPENAI_BASE_URL` + `OPENAI_API_KEY` 指向 DeepSeek,得到一个 "Codex but using
DeepSeek" 的 profile。

管道已经全通:plan.environment → `TerminalClient.launchAgentProfile` →
`WorktreeTerminalState`(`additionalEnvironment`)→ `GhosttySurfaceView` 把补丁
以 `ghostty_env_var_s` 数组交给 libghostty 在 spawn 时施加(非 shell 字符串,
无注入面)。缺的只有:模型字段、planner 合并、编辑器 UI。

## 设计

### 模型

`AgentProfile` 新增有序数组字段(非字典:table UI 需要稳定的行身份与顺序,且要
容忍编辑中的半成品行):

```swift
nonisolated struct AgentProfileEnvironmentOverride:
  Codable, Equatable, Sendable, Identifiable
{
  var id: UUID
  var name: String
  var value: String
}

var environmentOverrides: [AgentProfileEnvironmentOverride] = []
```

- 解码沿用既有 per-field 迁移模式:`decodeIfPresent ?? []`,旧数据零迁移。
- 持久化按原样保存(允许空行存在);**合法性在 plan 时刻裁决**,不在持久化时刻。

### Planner 合并语义(`AgentProfileLaunchPlanner.plan`)

1. 先施加用户 overrides:name 做 trim;trim 后为空的行跳过(编辑中间态);
   **name 必须是合法 POSIX 名**(`[A-Za-z_][A-Za-z0-9_]*`,天然排除 `=`/NUL),
   **保留名被拒绝**(见下);value 原样保留(空 value 是合法的"设为空",不是
   忽略),含 NUL 的 value 拒绝(strdup 会静默截断)。同名重复时后者胜(shell
   export 语义)。被拒绝的行在 UI 上可见标记,不静默消失。
2. 再写 dedicated-home 变量——**账号绑定永远压过同名用户行**,账号隔离的安全
   推理必须保持可证明。
3. **保留名单**:`PROWL_` 前缀(worktree/root 内部事实不可伪造)与各 runtime 的
   account-home 变量(`CLAUDE_CONFIG_DIR` / `CODEX_HOME`,从 adapter 的
   `accountHomeEnvironmentVariable` 推导,不硬编码)。未绑定 profile 若允许设
   `CODEX_HOME`,会绕过目录 provision、删除保护与 rooted session 检测——
   "自定义 home"是另一个需要完整支持的能力,不从 env 表格后门进入。
4. 下游 surface 合并(patch 压过 worktree 注入变量)保持不变:保留名已在
   planner 被过滤,到达下游的补丁均为合法用户覆盖。

### Launch Preview 引用修复与脱敏

`previewText` 目前把 env 前缀渲染为裸 `KEY=value`,用户值一旦含空格/引号/`$`,
预览即失真。修复:渲染为 `NAME=<quoted-value>`——只对 value 加引号(`'` →
`'"'"'` 习语),不把整个赋值当作一个 token。同时:

- **脱敏**:name 命中 secret 样模式(`KEY`/`TOKEN`/`SECRET`/`PASSWORD`,大小写
  不敏感)的值在预览中以掩码显示,绝不展示完整 secret。
- 预览语义澄清:env 前缀是"等价的可复制 shell 表示";真实注入走 Ghostty spawn
  的 env 数组,不经 shell。UI 文案从 "this exact command" 调整为不再对 env
  前缀作逐字承诺。

### 编辑器 UI

Advanced section 内、Extra Arguments 之下:紧凑两列表格——表头(Name / Value)、
每行两个 `.monospaced()` TextField、行尾删除按钮、底部 "Add Variable" 按钮;空列表
只渲染添加按钮。SwiftUI `Table` 与 `Form` 在高度/选中上互相打架,故用 ForEach 网格
保持 Form 原生观感。行文本编辑走既有 `BindingReducer` 通道自动持久化;增删行用
专用 action(`addEnvironmentOverride` / `removeEnvironmentOverride(id:)`),沿
`.setIcon` 模式。`runtimeChanged` **清空** overrides——与 extraArguments 一致:
`OPENAI_BASE_URL` 之类的值属于所选 runtime 的语义,切换 runtime 后残留只会造成
静默错配。非法/保留名的行内联标记(warning 图标 + help),不阻塞输入。

## 已知边界(与 053 既有推迟一致,本波不扩)

- **resume/handoff 不携带环境补丁**:`AgentResumeRequest` 无 env 字段、
  `ShellClient.runLogin` 无 env 缝。dedicatedHome 在 001-action.md 偏差 2 已推迟至
  handoff 波次,自定义 env 继承同一缺口——绑定/覆盖 pane 的 briefing resume 降级
  为 context-only。
- **布局恢复不重放补丁**:`WorktreeTerminalState+LayoutSnapshot` 重建 surface 时
  不带 `additionalEnvironment`,dedicatedHome 已有同样缺口,一并留待后续波次。
- **明文存储(边界的显式放宽)**:000-plan.md:56 原本把"裸 API key 进 Prowl
  JSON"排除在外(Keychain 引用整体推迟)。本修订按 onevcat 的显式需求放宽:
  用户在 env 表格中输入的值(可能含 api key)明文存于 `global.onevcat.json`。
  配套硬化:settings 写入统一收紧文件权限至 `0600`(此前落盘为 0644,同机
  他用户可读);预览对 secret 样名字掩码。Keychain 引用仍列为后续方向,不在
  本波实现。

## Codex 审阅(2026-07-31)

实现前由并行 codex(gpt-5.6-terra xhigh)审阅本文档与相关源码,四条意见全部或
部分采纳:

1. **明文密钥 P0** → 部分采纳:不上 Keychain(v1 过重,保持 053 的推迟),但
   采纳 0600 权限收紧、预览脱敏、文档显式声明边界放宽(见上节)。
2. **name 只 trim 不足** → 采纳:POSIX 名校验、空 value 语义为"设为空"、
   无效行 UI 可见。
3. **保留变量策略漏洞**(未绑定 profile 可设 `CODEX_HOME` 绕过防护;`PROWL_*`
   可被伪造)→ 采纳:全局保留名单,planner 过滤 + UI 标记。
4. **quoting 精确化**(`NAME=<quoted-value>`、预览是等价表示非执行路径、
   不展示 secret)→ 采纳。

## 验证

- 单测:解码默认值、round-trip、合并顺序(后者胜)、home 变量压过同名用户行、
  空 name 过滤、preview 引用。
- `make check` + `make build-app`;手动:override `OPENAI_BASE_URL` 的 profile,
  预览显示带引号前缀,启动后 pane 内 `echo $OPENAI_BASE_URL` 命中。
