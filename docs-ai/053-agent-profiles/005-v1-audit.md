# 053.005 — Agent Profile V1 综合审计

| | |
| --- | --- |
| **日期** | 2026-07-31 |
| **基线** | `main` == `origin/main`,`b698a23f`(含 PR #632 env overrides) |
| **来源** | 两份独立评审(Claude Code 全链路调研 × 并行 agent 审计)的交叉核对与仲裁 |
| **修复** | 本轮边界补强见文末「本次修复」([PR #634](https://github.com/onevcat/Prowl/pull/634)) |

## 综合结论

V1 主体设计成立:preset 与账号绑定正交、纯函数 launch planner(预览与启动同渲染)、
UUID 派生 home 的双重包含闸、单一 launch action、三层推荐、rooted session 检测,
均按 000-plan 落地且文档与实现高度一致。不存在需要推倒重来的结构问题。

| 方面 | 判断 |
| --- | --- |
| 功能与配置 | V1 基本齐全;Canvas 无 capsule 入口、播种一次性、palette 无 Manage 项为已知小缺口 |
| 安全性 | 本机使用达标;env 作用域文案与保留名单需补强(本轮已修) |
| 架构 | 无致命缺陷;「profile 身份只在创建瞬间存在」是系统性隐患(split/handoff/restore 三路丢失) |
| 代码质量 | domain/reducer 测试密集且对抗性强(~57 专属测试);终端层(`launchAgentProfile` 以下)零测试 |
| 产品完整性 | 启动闭环完整;handoff/resume、布局恢复、CLI、profile 生命周期管理仍有明显缺口 |

## 双方一致的确认发现

按严重度排列,均经代码定位核实:

1. **启动失败静默 + 推荐记忆提前写入**。plan 失败与 home provision 失败只落日志
   (`AppFeature+AgentProfiles.swift`、`WorktreeTerminalState.launchAgentProfile`),
   用户点击后无任何反馈;且 `lastLaunchedAgentProfileID` 在 `terminalClient.send`
   之前写入——实际未启动也会改变 Recommended。【本轮已修:launch 结果事件化】
2. **可用性判定的误判与入口分叉**。「已安装」= `~/.claude`/`~/.codex` 存在:
   CLI 已装未跑、或用户只打算经 dedicated home 首登时误判为不可用且 popover
   硬禁用;palette 完全不检查,同一 profile 两个入口行为相反。【本轮已修:
   启发式降级为警示不阻断,双入口共享同一判定】
3. **旧 profile 名张冠李戴**。`launchProfileName`(`+AgentDetection.swift:305`)
   未按 runtime 门控——launched agent 退出后在同 pane 手动启动其他家 agent,
   Active Agents 仍显示旧 profile 名;`configRoot` 已门控(:130),显示名漏了。
   【本轮已修】
4. **终端层零测试**。env merge 优先级、split→tab 回退、provision 失败中止、
   身份记录/清理均无测试锁定;测试金字塔在 `TerminalClient.Command` 边界断层。
   【本轮部分补齐:provision 失败中止路径】
5. **保留名单可绕行**。`HOME` 未保留:未绑定 profile 设 `HOME=…` 即间接搬迁
   `.claude`/`.codex`,绕过 provision、删除保护与 rooted 检测——正是
   「custom home 不从 env 表格后门进入」要防的事。【本轮已修:`HOME` 入保留名单】
6. **settings 权限迁移缺口**。0600 只在写入时施加,存量 0644 文件要等下次保存;
   atomic 写的 temp 文件在 rename 前为默认权限。【本轮已修:加载时迁移 +
   0600 temp 后 rename】
7. **文档/注释漂移**。`AgentProfileLaunchPlan.environment` 注释仍称
   "Non-empty only for account-bound profiles"(env overrides 后已失真);
   编辑器与 docs 称 env "applied to the launched process",实际作用于整个
   surface;001-action 偏差 1(model suggestions 未实现)已被后续实现追平但
   未回写。【本轮已修】
8. **Profile 身份不随生命周期传播**(架构性,双方均定位):
   - 手动 split 绑定 pane → 新 surface 无 env 无身份,pane 内手敲 agent 落到默认账号;
   - handoff 接收端走无 `additionalEnvironment` 的 `createTab` overload;
   - 布局恢复不重放 env、不恢复 `launchProfilesBySurface`,重启后绑定 pane 检测回落默认 home;
   - resume(`AgentResumeRequest`/`ShellClient.runLogin`)无 env 缝(001-action 已知推迟;
     2026-08-01 已由 [047.006](../047-cross-agent-handoff/006-remove-fork-briefing.md)
     随整条 briefing resume 路径删除)。
9. **Profile home 生命周期不完整**:绑定 agent 仍在运行时可 "Remove and Trash
   Files",无活跃 surface 检查;删除保留文件后 UUID 永久悬空,无 orphan home
   管理入口。
10. 次级:播种一次性全局 flag(装新 CLI 不补种)、Repo Settings picker 对
    disabled/悬空 default 显示空白而非 None、推荐排序依赖未保证的 `sorted(by:)`
    稳定性、`★` 与 "Recommended · " 两种标记不统一、CLI 检查在 view body 同步
    stat 文件系统、profile 启动创建 worktree 首个 tab 不消费 setup script。

## 分歧仲裁

两份报告仅在以下判断上不一致,仲裁如下:

- **「env 存 API key 时不能评为本机无忧」**:事实部分成立(surface 级作用域、
  shell rc 可见、agent 退出后残留、后续进程继承),但**严重度维持「本机达标」**:
  同用户进程本就可读 0600 的 JSON 文件,surface env 不扩大信任边界;真正的缺陷
  是文案承诺(process-only)与实际(surface-wide)不符。
- **「改为 `env KEY=value codex …` 前缀注入」的修法被否决**:typed input 会进入
  shell history 与终端 scrollback,secret 暴露面比 spawn env 更大,属于倒退。
  正确方向是文案如实 + 保留名单补强(本轮),以及远期的 Keychain 引用。
- **「硬禁用不可用 profile」**:000-plan 的原意是"灰显示因、不静默改推",但
  启发式存在已证实的 false negative(dedicated-home-only 用户被锁死)。仲裁为
  **启发式不得阻断**:灰显 + 警示保留,行保持可点,启动失败在新 surface 内可见。

## 本次修复(边界补强与实现正确性)

范围刻意排除 handoff 贯通与新 runtime 接入(各有独立波次):

1. `AgentProfileEnvironmentPolicy` 保留 `HOME`;编辑器/文档文案改为如实的
   surface 级作用域表述;`AgentProfileLaunchPlan.environment` 注释修正。
2. Launch 结果事件化:新增 `agentProfileLaunched` / `agentProfileLaunchFailed`
   终端事件;`lastLaunchedAgentProfileID` 改为成功事件后写入;失败(plan 或
   provision)以 toast 呈现。
3. `launchProfileName` 与 capsule 显示名按 runtime 门控,与 `configRoot` 同规。
4. 可用性判定收敛到单一 helper,popover 与 palette 共享;灰显警示不阻断。
5. settings 文件权限:加载时迁移 0600;写入改为 0600 temp + rename,消除
   默认权限窗口。
6. 测试:上述各项 + provision 失败中止(不建 tab、不记身份)。
7. (同日追加)**login-shell executable probe**(follow-up 3 的探测部分提前落地):
   `AgentRuntimeAvailabilityProbe` 经 `ShellClient.runLogin` 在用户 login shell 内
   `command -v`,与启动共用同一条 PATH 解析,结果按 session 缓存于
   `@Shared(.inMemory)`;阳性终局、阴性/未知在每次打开 Agents popover 时后台重测。
   判定两级:probe 已应答即 ground truth("not on your shell's PATH"),未应答回退
   home 启发式("may not be installed")。播种保持 home 启发式(信号语义是"用户在用
   这家",而非"二进制存在")。launcher query 的 resolved-option 统一仍留在 follow-up。

## 遗留 follow-up(按优先级)

1. **Handoff × Profile 贯通**(既定方向):resume/`runLogin` env 缝、HUD 目标
   列表 profile 化,双路径同改。
2. **身份生命周期传播**:split 继承、布局恢复以 profileID 重新 plan 派生 env
   (env 值含 secret,不得入 snapshot)。
3. **可用性真探测**:可注入、缓存的 executable probe(login-shell PATH 解析)
   替代 home 目录启发式;launcher query 统一为单一 resolved-option 类型。
4. **Profile 生命周期**:Trash 前活跃 surface 检查、orphan home 管理、
   per-runtime 补种、Duplicate、repo picker 悬空显示、`prowl` CLI profile 感知。
5. **Secret 治理**:Keychain 引用型 env value、编辑器遮盖输入。
