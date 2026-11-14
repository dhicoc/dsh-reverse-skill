# dsh-reverse-skill

[![awesome · DSH plugin](https://awesome-dsh-plugin.com/badge.svg)](https://github.com/awesome-dsh-plugin/awesome-dsh-plugin)



[![Awesome](https://awesome.re/badge.svg)](https://github.com/awesome-dsh-plugin/awesome-dsh-plugin)


> **分发通道：只走 GitHub。npm registry 不受支持。**
>
> 本插件**不通过 npm 分发**。registry 上的 `@dhicoc/dsh-reverse-skill` 是历史遗留的 1.0.x（peer 卡在 `@deepseek-ai/dsh-skill ^0.0.1-rc.1`），已被当前 DSH 的兼容性预检拒绝，不会再更新、也不会再发新版本。**不要用 `npm install` 或裸包名安装。**
>
> 安装（跟随 `main`）：
>
> ```bash
> dsh plugin add github:dhicoc/dsh-reverse-skill
> ```
>
> 安装（固定版本，推荐用于可复现环境）：
>
> ```bash
> dsh plugin add github:dhicoc/dsh-reverse-skill#v1.2.1
> ```
>
> 升级 / 降级 = 用目标 tag 重跑一次安装命令。可用 tag 见 [Releases](https://github.com/dhicoc/dsh-reverse-skill/releases)。

> **reverse-skill 的完整 DeepSeek Harness（dsh）插件版。**
> 把上游 [`zhaoxuya520/reverse-skill`](https://github.com/zhaoxuya520/reverse-skill)（27k★，MIT）全部 **88 个 SKILL.md** 原样封装成一个 dsh Cordis 插件，随包分发、随插件加载，无需手动维护候选清单。

---


### 适用范围（请遵守）

本仓库内容仅用于 **授权的** 逆向工程、渗透测试与安全研究。使用者须确保对目标系统拥有合法授权。一切未授权行为与本仓库无关。

本包包含具有合法安全用途、同时也可能被滥用的内容（渗透测试技术、参考资料与辅助脚本），属 npm 所称的 **dual-use（军民两用）内容**。仓库根目录的 [`DISCLOSURE`](./DISCLOSURE) 文件对此作了完整说明。

---

## 目录结构

```text
dsh-reverse-skill/
├── src/
│   └── index.ts                 # 数据驱动的 Cordis 插件：递归扫描并注册全部 SKILL.md
├── skills/                      # 46 个领域技能（上游 skills/ 复制）
│   ├── reverse-skill-router/
│   │   └── SKILL.md             # 路由技能（上游 skills/SKILL.md；见下）
│   ├── pentest-tools/           # 含嵌套子技能 src-hunter 等
│   └── reverse-engineering/     # 含嵌套子技能 dsl-vm-reverse 等
├── CTF-Sandbox-Orchestrator/    # 42 个 CTF 赛道技能
├── port.py                      # 归一化脚本（上游 → 本仓库的搬运/前导matter修正）
├── package.json
├── tsconfig.json
├── DISCLOSURE                   # 双用途内容声明（内容与用途说明）
└── LICENSE                      # MIT（与上游一致）
```

> 相对路径：`src/index.ts` 通过 `fileURLToPath(new URL('../skills', import.meta.url))` 定位资源（编译后 `lib/index.js` 同样成立，因为 `skills/` 与 `lib/` 同属包根目录的相邻子目录）。注意这里**不能**再套一层 `dirname()`——`../skills` 这个 URL 已经指向目录本身，多套 `dirname` 会把它截断成包根目录，从而把 `node_modules` 里的 SKILL.md 也算进来。

> 路由技能的位置：上游把路由器放在 `skills/SKILL.md`，但其 frontmatter 声明 `name: reverse-skill-router`，与 [agentskills.io 规范](https://agentskills.io/specification) 的「`name` 必须等于父目录名」不一致（issue #21）。本仓库因此把它放到 `skills/reverse-skill-router/SKILL.md`，其余 87 个技能本就符合该规则。插件按 frontmatter `name` 注册，所以运行时行为不变；这也正是 `port.py` 里 `restructure_router()` 一直想做的布局。文档仍留在 `skills/` 层，因此该文件内的路径引用带 `../` 前缀。

---

## 安装（插件形态，GitHub 通道）

本仓库已声明 `dsh.bundle` manifest（见 `cordis.patch.yml`），一行命令即可安装并激活：

```bash
# 跟随 main（拿到最新提交）
dsh plugin add github:dhicoc/dsh-reverse-skill

# 固定到某个 release tag（可复现，推荐）
dsh plugin add github:dhicoc/dsh-reverse-skill#v1.2.1
```

需要指定 profile 时加 `--profile <name>`（浏览器 UI 通常是 `web`；桌面端由 Electron 管理 `desktop`，请用应用自带的插件管理器）。

### 为什么不走 npm

npm 通道对本包**永久不可用**，因此仓库不再维护它：

- registry 上只有 1.0.2–1.0.5，其 `peerDependencies` 全是 `@deepseek-ai/dsh-skill: ^0.0.1-rc.1`，DSH ≥ 0.2.0 在安装**预检阶段**即拒绝，不会写入任何内容；
- 1.1.x 起的 staged 发布被 npm 的 dual-use 内容扫描判定为 blocked（见 [`DISCLOSURE`](./DISCLOSURE) 与 `package.json` 的 `contentPolicy`），本包属双用途安全研究内容，恢复通道也无把握；
- 因此 `npm install @dhicoc/dsh-reverse-skill` 与 `dsh plugin add @dhicoc/dsh-reverse-skill`（裸包名）**都会失败**，且失败发生在版本解析阶段，与本机环境无关。

GitHub 通道走 `git`，用仓库里已提交的 `lib/` 预编译产物，且由仓库自身的 `package.json` 满足兼容性校验，因此可用。npm 上残留的 1.0.5 已标记 deprecated 指向本仓库。

### 升级 / 降级 / 回滚

GitHub 分发没有 registry 的 `latest` 概念，版本就是 tag：

```bash
# 升级到新 release
dsh plugin add github:dhicoc/dsh-reverse-skill#v1.2.2
# 回滚
dsh plugin add github:dhicoc/dsh-reverse-skill#v1.2.0
# 跟随 main 最新提交
dsh plugin add github:dhicoc/dsh-reverse-skill
```

同名包会被替换，不需要先卸载。改完重启应用（或重载 Web UI）让 profile 重新组合，并用下面命令确认插件行已生效：

```bash
dsh --profile <your-profile> --dump-config | findstr reverse-skill
```

安装后 dsh 会读取 `cordis.patch.yml` 把 `reverse-skill` 这个 Cordis 插件插入当前 profile，启动时自动注册 88 个技能。若你想在 profile / package 配置里手动引用，名称是 `@dhicoc/dsh-reverse-skill`：

```yaml
# dsh 配置（示例，键名可能因版本而异）
plugins:
  - "@dhicoc/dsh-reverse-skill"
```

加载后，插件在 `apply(ctx)` 里调用 `ctx.skills.registerProvider(...)`，把 88 个技能注册进 `ctx.skills`。模型可通过 `ctx.skills` → `tool-skill` 自动调用，用户也可通过技能名手动调用（受各 SKILL.md 的 `user-invocable` 控制）。

### 从源码构建（可选）

`lib/` 已随仓库提交，从 GitHub 安装**无需**构建。仅在你需要自行编译时才需要开发依赖：

```bash
# 只装开发依赖（cordis / dsh-skill 由 dsh 运行时提供，这里用于类型与构建）
npm install
npm run build        # tsc → 生成 lib/ 与 lib/types/
```

`package.json` 中已声明：

```json
"main": "lib/index.js",
"types": "lib/types/index.d.ts",
"peerDependencies": {
  "@deepseek-ai/cordis": "~4.0.4",
  "@deepseek-ai/dsh-skill": "^0.2.0-rc.2"
}
```

### （可选）非插件回退：直接当 preset 用

本仓库同时携带完整的 `skills/` 与 `CTF-Sandbox-Orchestrator/` 目录，可作为 preset 直接挂载，无需构建：

```yaml
skills:
  local:
    customSkillDirs:
      - "./dsh-reverse-skill/skills"
      - "./dsh-reverse-skill/CTF-Sandbox-Orchestrator"
```

> dsh 技能发现优先级（先命中先生效）：项目 `.dsh` → 项目 `.agents` → `customSkillDirs` → 用户 `.dsh` → 用户 `.agents`。**插件路径**用本仓库自带的递归 scanner，能同时发现路由器与嵌套子技能（如 `pentest-tools/src-hunter`）；preset 回退走 dsh 的扁平发现，只扫直接子目录——路由器因为已移入 `skills/reverse-skill-router/` 反而能被扫到，但嵌套子技能仍会漏。因此**推荐用插件路径**。

---

## 插件工作原理（数据驱动，零手写清单）

`src/index.ts` 不做任何硬编码候选列表，而是：

1. 递归遍历 `skills/` 与 `CTF-Sandbox-Orchestrator/`，找到每个 `SKILL.md`；
2. 解析前导 matter（把 `metadata.user-invocable` 提升为顶层 `user-invocable`；上游文件原样打包，CRLF / BOM 在运行时归一化）；
3. 构造 `SkillCandidate`（含 `resourceBase: {kind:'directory', path}`、结果缓存）；
4. 注册一个 `SkillProvider`，`get()` 时返回完整 body。

新增/删除技能只需改目录，插件自动同步。

### 可复跑验证

在仓库根目录运行：

```bash
npm test
```

该命令会重新编译插件，并通过实际注册的 `SkillProvider` 断言 88 个已打包技能都能被 `list()` 发现、名称无重复且均能按需 `get()` 返回非空正文。测试还会临时创建一个带 UTF-8 BOM 和 CRLF 的 `SKILL.md`，确认扫描器不会静默跳过此类文件；fixture 在测试结束后会自动删除。

---

## 已知限制（诚实告知）

- **`agents/*.yaml` 不可移植**：上游 43 个 OpenAI Agents SDK 的 agent 定义无法映射到 dsh 的 `ctx.subagent`（dsh 仅支持拉起 Codex / Claude Code CLI）。这些 agent 定义未纳入插件。
- **`allowed-tools` / `disallowed-tools` 不被 dsh 强制**：dsh 当前把这两项视为未知字段，延迟执行。技能内的工具约束需自行在 harness 层保证。
- **前导 matter 仅依赖 `name` / `description` / `user-invocable`**：本仓库 scanner 只读这三个字段，上游原始文件原样打包（CRLF / BOM 在运行时归一化），无需改写；其余字段作为技能正文一并随 `get()` 返回。
- **MCP 工具（如 burp-mcp）需另行配置**：技能正文里引用的外部 MCP server 不在本插件范围内，请按 dsh 的 `mcp.servers` 自行接入。
- **文档链接已重写**：正文内相对链接已改为 `../`（及 CTF 相关为 `../../CTF-Sandbox-Orchestrator/`），以适配 dsh 扁平挂载路径。
- **分发通道只有 GitHub**：npm 通道永久不可用（历史 1.0.x 与当前 DSH 不兼容，且 dual-use 扫描 blocked），仓库不再向 npm 发版；升级 / 回滚都通过用目标 tag 重跑 GitHub 安装命令完成。


## License

`LICENSE` 为 **MIT**，与上游 `reverse-skill` 保持一致。内容版权归原 upstream 作者与贡献者；本仓库为 dsh 适配封装。
