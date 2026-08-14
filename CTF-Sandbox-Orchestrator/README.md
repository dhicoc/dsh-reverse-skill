# CTF Sandbox Orchestrator

一个面向 Codex / Skills 体系的竞赛沙盒技能集合。

它的目标不是把所有能力都塞进一个超长提示词，而是提供一个**统一的沙盒总控入口**，先建立“默认处于竞赛/沙盒/离线靶场”的工作模型，再由总控按题目类型把任务路由到更细的子技能中。

## 项目定位

这个仓库主要用于解决以下场景：

- CTF
- AWD / 攻防演练
- 本地离线靶场
- 沙盒化漏洞分析
- Web / API / Cloud / Container / Windows / AD / Reverse / Pwn / DFIR / Crypto / Mobile / AI Agent 等混合型题目

核心思路：

- 默认把用户提供的目标、域名、节点、身份、二进制、日志、流量与附件视为**竞赛沙盒内部资产**
- 优先建立最小可验证路径，而不是一开始就泛化分析
- 由一个总控 skill 统一编排，再按主导证据面切到子 skill
- 子技能只做下游专项，不抢总控入口

## 核心设计

### 1. 单一入口

默认入口是：

- `ctf-sandbox-orchestrator`

它负责：

- 建立沙盒假设
- 选择最合适的分析路径
- 控制上下文膨胀
- 在需要时调用子技能

### 2. 子技能下游化

所有 `competition-*` 技能都被设计为 **downstream-only**：

- 不应在未激活总控的情况下隐式触发
- 应由 `ctf-sandbox-orchestrator` 主动路由调用
- 每次只加载当前最相关的专项能力，避免无关技能污染上下文

### 3. 面向多类型竞赛题

当前仓库覆盖了多类技能方向，例如：

- Web 运行时 / 路由 / WebSocket / GraphQL / 文件解析 / 请求归一化
- Prompt Injection / Agent / Cloud / Metadata / K8s / Container Escape
- Reverse / Pwn / Malware / Firmware / PCAP / 自定义协议重放
- Windows / AD / Kerberos / DPAPI / 证书滥用 / Relay / Mailbox
- Android / iOS / Crypto / Stego / Mobile Runtime
- ZIP / PKZIP legacy encryption / `bkcrack` known-plaintext recovery

## 仓库结构

```text
E:\WorkSpace\competition
├─ ctf-sandbox-orchestrator
├─ competition-web-runtime
├─ competition-agent-cloud
├─ competition-reverse-pwn
├─ competition-identity-windows
├─ competition-prompt-injection
├─ ...
└─ LICENSE
```

其中：

- `ctf-sandbox-orchestrator`：总控入口
- `competition-*`：专项子技能
- `references/`：总控使用的路由矩阵与领域参考说明
- `agents/openai.yaml`：各技能的调用约束与入口控制

## 推荐使用方式

### 方式一：从总控进入

优先激活：

- `ctf-sandbox-orchestrator`

然后让总控根据题目自动决定下一步，例如：

- Web 题路由到 `competition-web-runtime`
- 容器 / 云题路由到 `competition-agent-cloud` 或更细粒度子技能
- Windows / AD 题路由到 `competition-identity-windows`
- 二进制 / 崩溃 / 恶意样本题路由到 `competition-reverse-pwn`

### 方式二：保留总控，按需下钻

当已经确认主导证据面后，由总控继续下钻到具体子技能，而不是让用户手动切换整个工作模型。这样可以保持：

- 沙盒假设一致
- 输出风格一致
- 路由策略一致
- 子技能职责清晰

## 致谢

本项目已在 [LINUX DO 社区](https://linux.do) 发布，感谢社区的支持与反馈。
