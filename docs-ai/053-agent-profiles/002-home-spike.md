# 053 — HOME Path Spike(账号绑定可行性实测)

| | |
| --- | --- |
| **日期** | 2026-07-29 |
| **版本** | Claude Code 2.1.220 · codex-cli 0.144.6 · macOS 26 |
| **方法** | 全新目录 + headless 探测(`claude -p` / `codex exec`)+ 用户交互登录 + 预埋标记文件(`CLAUDE.md` / `AGENTS.md` 魔法词、`skills/spike-probe`) |
| **spike 目录** | `~/.prowl/agent-profiles-spike/{claude-a,codex-a}` |

## 结论

计划(000-plan)中账号绑定设计依赖的**全部关键假设均被实测证实**,无一需要修改。

## 实测发现

1. **Codex 拒绝不存在的 `CODEX_HOME`**:`Error finding codex home: … does not exist`。
   → 证实"启动前必须创建派生 home"。
2. **Codex 自初始化空 home**:首次运行即创建 `installation_id`、sqlite 状态库、
   `sessions/` 日期树、`skills/.system` 等;未登录 headless 直接 401。
3. **Codex rollout 跟随新根**:
   `$CODEX_HOME/sessions/2026/07/29/rollout-<ts>-<uuid>.jsonl`——布局形状与
   `AgentSessionProfile` 假设一致,但路径中**没有 `.codex` 组件**。
   → 证实检测层 parsePath 的全局子串 marker 必须改为按已知 config root 前缀匹配
   (实现步骤 4)。
4. **Claude 未登录行为**:输出 `Not logged in · Please run /login`;且未登录时即在
   config dir 内创建 `.claude.json`(状态文件跟随搬迁)与
   `projects/<encoded cwd>/<uuid>.jsonl`(transcript 根跟随搬迁);cwd 编码与检测层
   `alphanumericDashed` 规则吻合。
5. **`$CLAUDE_CONFIG_DIR/CLAUDE.md` 被原生读取**:魔法词测试回答 `PROFILE-CLAUDE-A`。
6. **`$CODEX_HOME/AGENTS.md` 被原生读取**:魔法词测试回答 `PROFILE-CODEX-A`。
   → 5/6 共同证实:绑定 profile 的专属指令无需任何注入机制。
7. **skills 从搬迁 home 被原生拾取**:两家对 `skills/spike-probe` 均回
   `SKILL-LOADED-OK`。
8. **凭证落点**:Codex 登录后 `auth.json`(0600)落在 `$CODEX_HOME`;Claude 的
   `.claude.json`(0600)在 config dir,OAuth token 走 macOS Keychain(CLI 内部机制)。
   spike 全程默认账号会话与 spike 账号会话**并行运行无串号**,行为层面证实隔离。
9. **真实 home 零污染**:以基线时间戳复查,`~/.claude/projects` 与 `~/.codex/sessions`
   在 spike 期间无任何新增写入(排除本会话自身 transcript)。
10. **TUI 首启即登录流程成立**:用户以
    `CLAUDE_CONFIG_DIR=… claude` / `CODEX_HOME=… codex` 启动全新 home 的 TUI,原生
    引导完成登录——证实删除 Sign In 按钮的决策(首次启动即登录时刻)。

## 对计划的确认

- 账号绑定机制(env 只挂新 surface、home 预创建、0600 权限、CLI 自管认证)按原计划实施。
- 实现步骤 4(session 检测 config root 参数化)是必要且充分的修法,发现 3/4 提供了
  精确证据。
- 无新增风险项;无需修改 000-plan。

## Spike 残留物

`~/.prowl/agent-profiles-spike/` 保留,供实现阶段手动测试复用(**内含两份真实登录
凭证**,不再需要时应整体移入废纸篓)。
