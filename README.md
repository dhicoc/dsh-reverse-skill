# dsh-reverse-skill

[![awesome · DSH plugin](https://awesome-dsh-plugin.com/badge.svg)](https://github.com/awesome-dsh-plugin/awesome-dsh-plugin)



[![Awesome](https://awesome.re/badge.svg)](https://github.com/awesome-dsh-plugin/awesome-dsh-plugin)


> **reverse-skill 的完整 DeepSeek Harness（dsh）插件版。**
> 把上游 [`zhaoxuya520/reverse-skill`](https://github.com/zhaoxuya520/reverse-skill)（27k★，MIT）全部 **87 个 SKILL.md** 原样封装成一个 dsh Cordis 插件，随包分发、随插件加载，无需手动维护候选清单。

---


### 适用范围（请遵守）

本仓库内容仅用于 **授权的** 逆向工程、渗透测试与安全研究。使用者须确保对目标系统拥有合法授权。一切未授权行为与本仓库无关。

---

## 目录结构

```text
dsh-reverse-skill/
├── src/
│   └── index.ts                 # 数据驱动的 Cordis 插件：递归扫描并注册全部 SKILL.md
├── skills/                      # 45 个领域技能（上游 skills/ 1:1 复制）
│   ├── SKILL.md                 # 路由技能 reverse-skill-router（上游根 SKILL.md）
│   ├── pentest-tools/           # 含嵌套子技能 src-hunter 等
│   └── reverse-engineering/     # 含嵌套子技能 dsl-vm-reverse 等
├── CTF-Sandbox-Orchestrator/    # 42 个 CTF 赛道技能
├── port.py                      # 归一化脚本（上游 → 本仓库的搬运/前导matter修正）
├── package.json
├── tsconfig.json
└── LICENSE                      # MIT（与上游一致）
```

> 相对路径：`src/index.ts` 通过 `fileURLToPath(new URL('../skills', import.meta.url))` 定位资源（编译后 `lib/index.js` 同样成立，因为 `skills/` 与 `lib/` 同属包根目录的相邻子目录）。注意这里**不能**再套一层 `dirname()`——`../skills` 这个 URL 已经指向目录本身，多套 `dirname` 会把它截断成包根目录，从而把 `node_modules` 里的 SKILL.md 也算进来。

---

## 安装（插件形态）

### 1. 安装依赖与构建

```bash
# 安装 peer 依赖（cordis / dsh-skill 由 dsh 运行时提供，这里用于类型与构建）
npm install
npm run build        # tsc → 生成 lib/ 与 lib/types/
```

`package.json` 中已声明：

```json
"main": "lib/index.js",
"types": "lib/types/index.d.ts",
"peerDependencies": {
  "@deepseek-ai/cordis": "^4.0.1",
  "@deepseek-ai/dsh-skill": "^0.0.1-rc.1"
}
```

### 2. 在 dsh 中启用本插件

本仓库已声明 `dsh.bundle` manifest（见 `cordis.patch.yml`），因此可直接用一行命令安装并激活：

```bash
# 从 GitHub 安装并激活（推荐）
dsh plugin add github:dhicoc/dsh-reverse-skill
```

安装后 dsh 会读取 `cordis.patch.yml` 把 `reverse-skill` 这个 Cordis 插件插入当前 profile，启动时自动注册 87 个技能。若你想在 profile / package 配置里手动引用，包名是 `@dhicoc/dsh-reverse-skill`：

```yaml
# dsh 配置（示例，键名可能因版本而异）
plugins:
  - "@dhicoc/dsh-reverse-skill"
```

加载后，插件在 `apply(ctx)` 里调用 `ctx.skills.registerProvider(...)`，把 87 个技能注册进 `ctx.skills`。模型可通过 `ctx.skills` → `tool-skill` 自动调用，用户也可通过技能名手动调用（受各 SKILL.md 的 `user-invocable` 控制）。

### 3. （可选）非插件回退：直接当 preset 用

本仓库同时携带完整的 `skills/` 与 `CTF-Sandbox-Orchestrator/` 目录，可作为 preset 直接挂载，无需构建：

```yaml
skills:
  local:
    customSkillDirs:
      - "./dsh-reverse-skill/skills"
      - "./dsh-reverse-skill/CTF-Sandbox-Orchestrator"
```

> dsh 技能发现优先级（先命中先生效）：项目 `.dsh` → 项目 `.agents` → `customSkillDirs` → 用户 `.dsh` → 用户 `.agents`。**插件路径**使用本仓库自带的递归 scanner（能发现根 `skills/SKILL.md` 路由器与嵌套子技能）；若改用可选 preset 回退（dsh 扁平发现，只扫直接子目录），根 `SKILL.md` 路由器不在子目录内、不会被发现——因此推荐用插件路径。

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

该命令会重新编译插件，并通过实际注册的 `SkillProvider` 断言 87 个已打包技能都能被 `list()` 发现、名称无重复且均能按需 `get()` 返回非空正文。测试还会临时创建一个带 UTF-8 BOM 和 CRLF 的 `SKILL.md`，确认扫描器不会静默跳过此类文件；fixture 在测试结束后会自动删除。发布工作流也会在 `npm publish` 前运行同一检查。

---

## 已知限制（诚实告知）

- **`agents/*.yaml` 不可移植**：上游 43 个 OpenAI Agents SDK 的 agent 定义无法映射到 dsh 的 `ctx.subagent`（dsh 仅支持拉起 Codex / Claude Code CLI）。这些 agent 定义未纳入插件。
- **`allowed-tools` / `disallowed-tools` 不被 dsh 强制**：dsh 当前把这两项视为未知字段，延迟执行。技能内的工具约束需自行在 harness 层保证。
- **前导 matter 仅依赖 `name` / `description` / `user-invocable`**：本仓库 scanner 只读这三个字段，上游原始文件原样打包（CRLF / BOM 在运行时归一化），无需改写；其余字段作为技能正文一并随 `get()` 返回。
- **MCP 工具（如 burp-mcp）需另行配置**：技能正文里引用的外部 MCP server 不在本插件范围内，请按 dsh 的 `mcp.servers` 自行接入。
- **文档链接已重写**：正文内相对链接已改为 `../`（及 CTF 相关为 `../../CTF-Sandbox-Orchestrator/`），以适配 dsh 扁平挂载路径。


## License

`LICENSE` 为 **MIT**，与上游 `reverse-skill` 保持一致。内容版权归原 upstream 作者与贡献者；本仓库为 dsh 适配封装。
