# 2026-10-07 Nuitka 自解压 PE 的常量块复原与内层管线重建

## 场景分类

二进制分析 / 自定义壳 + Nuitka onefile / Python 应用逻辑复原 / 证据链闭环

## 目标概述

对一个 Windows GUI 视频批量处理工具做完整功能逆向：剥离自定义壳，攻克内层 Nuitka 常量块编码，复原 GUI 参数、完整 ffmpeg 滤镜管线、授权上报逻辑，并将复原出的滤镜图逐阶段实跑验证。

## Scope 摘要（脱敏）

- auth_basis: own_system（离线样本，owner-operated）
- network_profile: offline
- asset_types: [binary]

> 分析在启动目标程序**之前**即用本地防火墙规则封禁厂商数据库出网，整轮运行为本地；结束后恢复防火墙原状。

## 角色

- lead_role: lead
- specialists: []

## 完整执行链路

1. `rabin2 -I/-S/-i` 三连：确认 PE32+、stripped、未签名、6 节全同权限标记 `0xe0000040`、仅 3 个 kernel32 手工解析 API 导入 → 判定自定义壳，排除 PyInstaller / Electron。
2. 解析 `.rsrc`，取出 `RCDATA id=27`（`"KAY("` + zstd），解压得 287,847,662 字节。
3. 按 `[UTF-16LE 名][0x0000][u32 长度][MZ...PE]` 切出 32 个内嵌 PE → 确认 Nuitka onefile（`launcher.dll` + `python310.dll` + `tcl86t` / `tk86t`）。
4. 定位 `launcher.dll` 的 `RCDATA id=3` = 6,125,169 字节常量块，从头 8 字节开始试错，识别真实记录边界。
5. 按 Nuitka 头文件标签表实现完整解码器；**253 个模块条目全部解码，0 失败**。
6. 用真实 Python 3.10.11 + `marshal.loads` 原生反序列化 `.bytecode` 部分（358 个标准库 code object）——放弃 xdis（多处 API 不兼容）。
7. 逐个模块 dump 字面量，结合 `CodeObjectSpec` 里的函数名 / 参数名 / 局部变量名 / docstring / 类型注解推断调用点，复原 `rev_video` 的 GUI 结构、参数范围与滤镜串。
8. 建立跨模块引用图，发现 `mp4_breaker` / `audio_metadata_breaker` 无入边 → 判为死代码，排除出执行路径。
9. 用对照实验消解一个字面量歧义：同一滤镜分别以「高度参数缺失」和「高度参数存在」两种形态执行，前者报 `Invalid too big or non positive size` 且 `exit=-22`，后者 `exit=0` → 证明常量流把滤镜切成了运行期拼接的片段。
10. 从常量流解密客户端数据库凭据（Fernet + PBKDF2HMAC-SHA256）。
11. **在启动目标程序前**用本地防火墙封禁厂商数据库出网，验证「DB 被封禁而常规网络仍可达」。
12. 启动目标，转储顶层窗口控件树 → 发现门禁是原生 Win32 对话框而非 Tk，且此刻 Nuitka 模块尚未加载 → 判定授权强制点在壳层。
13. 恢复防火墙原状，删除临时规则。
14. 用目标**同容器内**的捆绑 ffmpeg 逐阶段实跑复原出的滤镜图，五阶段全部 `exit=0`，输出几何与内置分辨率常量吻合。
15. 落地 case（scope / 11 条证据 / 5 个工作项 / 15 条时间线）、正式报告、3 张图表，跑 `review_case.py --verify-hashes --strict` 通过。

## Evidence 链摘要（脱敏）

| E-id | severity | status | source_type | 可复用命令模式 | 关联 Finding |
|------|----------|--------|-------------|----------------|--------------|
| E-001 | info | validated | command | `rabin2 -I ./sample.exe` → 3 导入 + 全节同权限判壳 | F-001 |
| E-004 | info | validated | command | `ffmpeg -filter_complex_script filter.txt -map "[outv]" …` 验证复原的滤镜树 | F-001, F-002 |
| E-008 | high | validated | command | 双层 base64 → `Fernet.decrypt` 恢复内嵌凭据 | F-004 |
| E-010 | high | candidate | manual | UIA 转储顶层窗口控件树 + 模块列表比对定位门禁层 | F-003 |

> 契约对齐：报告含 7 个 Finding（每个 ≥1 Evidence）、2 条 Path；E-010 仅单一证据源，按 validated-sufficiency 规则保持 `candidate` 未升级。

## Finding / Path 摘要

- top_finding: 客户端内嵌数据库凭据可仅凭出厂二进制离线恢复（双层 base64 的 Fernet 密文）；同时授权卡密门禁并不在已复原的 Python 层，而在壳的原生 stub。
- path_type: callflow
- path_one_liner: 壳解密 → 原生卡密门禁（payload 尚未加载）→ 解压 32 个内嵌 PE → Python 启动链静默注册 → Tk 主界面 → 六阶段滤镜 → remux 落盘。

## 踩坑记录

| 问题 | 原因 | 解决方案 | 耗时 |
|------|------|---------|------|
| `rabin2` 打不开目标 | 文件名含 CJK 字符 | 复制到 ASCII 路径再分析 | 低 |
| 资源目录遍历崩在 `unpack_from requires a buffer of at least 2213349440 bytes` | 子目录偏移的高位被置为目录标志 | 掩码 `offst & 0x7FFFFFFF`，以资源目录基址为基准计算 | 低 |
| 从 offset 0 裸扫常量块报 `unknown tag 0xf4` | 头 8 字节是头部而非常量 | 跳过 8 字节头，从第一条记录开始 | 低 |
| `xdis` 处理 marshal 数据全崩 | 3 个 API 签名在该版本均不兼容 | 弃用 xdis，改用真实 Python 3.10.11 + `marshal.loads` | 中 |
| Python 3.14 反序列化 marshal 失败 | `bad marshal data (unknown type code)`，magic 不匹配 | 装 3.10.11 embeddable 专用解释器 | 低 |
| CJK 输出触发 `UnicodeEncodeError: 'gbk' codec`（含 `\u26a0`） | Windows 控制台默认 GBK | 一律写 UTF-8 文件再读取，不直接 `print()` | 低 |
| 凭据解密全失败 | **密文是双层 base64**：先用 `urlsafe_b64decode` 再 `Fernet.decrypt` | 纠正编码层数；此前对密钥派生做的 131 种候选暴力枚举是白费功夫 | 中 |
| 按字面量原文复原的 `crop` 滤镜执行报 `exit=-22` | 常量流把一条滤镜切成若干相邻字面量 | 做 A/B 对照实验确认运行期存在高度参数，按拼接后形态复原 | 中 |
| 防火墙规则建了却不生效 | `Get-NetFirewallProfile` 显示 Private/Public `Enabled=0` | 先 `Set-NetFirewallProfile -Profile Private -Enabled True`，并先把原状导出以便复原 | 低 |
| 想观测启动行为却撞上登录对话框 | 门禁在壳的原生层，早于 payload 加载 | 记录该事实并作为 Finding 提出，不强行猜测其算法 | 低 |
| 无法查看截图 | 当前模型不支持图片输入 | 改用 UI Automation 转储控件树取文本 | 低 |

## 工具链发现

- **Nuitka onefile 的判定信号**：载荷含 `launcher.dll` + `python310.dll` + `tcl86t` / `tk86t`；`launcher.dll` 携带资源型常量块。与 PyInstaller（`PYZ-00.pyz` / `pyimod*`）完全不同。
- **常量块是最大金矿**：即使应用模块是 C 编译的、拿不到逐函数字节码，`CodeObjectSpec` 里的**函数名 / 参数名 / 局部变量名 / docstring / 类型注解 / 字面量**足以复原出可执行级的功能规格。局限是**无法把字面量归属到单个函数**，必须靠「首次使用顺序 + 变量名上下文」推断。
- **`marshal.loads` 必须用目标同版本解释器**。Nuitka 把标准库 code object 放进 `BlobData`，magic 不匹配就没有任何回旋余地。
- **字面量原文 ≠ 运行期字符串**。打包器会把长字符串切成相邻片段以复用，直接按原文复原会得出错误滤镜。A/B 对照执行是消歧的最快路径。
- **用目标自带的 ffmpeg 做验证**，不要用系统装的：编码器行为、deprecation 警告、Fontconfig 报错都与目标一致，结论才能直接对应。
- **授权逻辑可能在壳层，而不是被分析的应用层**。判据：门禁窗口出现时内层运行时模块（`launcher.dll` / `python310.dll` / `tk86t.dll`）尚未出现在进程模块列表中。
- **双层编码是常见陷阱**。遇到「密钥明明对但解密就是失败」，先怀疑编码层数，再怀疑密钥派生——逆向里暴力枚举密钥远比自己核对一遍编码便宜，但方向错了就是纯浪费。
- UI Automation 是纯文本环境下替代截图的可靠手段；CJK 文件名、GBK 控制台这类 Windows 常见摩擦点应提前规避。

## 关键代码/命令

```powershell
# 壳与载荷识别
Copy-Item '<cjk_path>\sample.exe' C:\re\sample\target.exe      # 规避 CJK 路径
rabin2 -I C:\re\sample\target.exe
rabin2 -S C:\re\sample\target.exe
rabin2 -i C:\re\sample\target.exe

# 资源提取 → zstd → 切分内嵌 PE
python rsrc.py ; python unz.py ; python carve.py

# Nuitka 常量块解码
python dec8.py       # -> consts.pkl + consts/<module>.json / .tree.txt

# 标准库 code object 反序列化（必须同版本解释器）
& 'C:\re\py310\python.exe' dec310.py

# 跨模块引用图（找死代码）
python refs.py

# 滤镜管线验证（用目标自带的 ffmpeg）
& '<payload>\ffmpeg.exe' -y -hide_banner -loglevel error `
  -i pre_bg1.mp4 -i template.mp4 `
  -filter_complex_script filter_compose.txt `
  -map "[outv]" -map 1:a -c:a aac `
  -c:v libx264 -preset veryfast -pix_fmt yuv420p -r 25 -t 4 -vsync cfr out.mp4
```

```python
# 双层 base64 的 Fernet 配置（关键顺序）
seed = "_".join(PARTS)
kdf  = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32,
                  salt=b"<salt>", iterations=100000)
key  = base64.urlsafe_b64encode(kdf.derive(seed.encode()))
raw  = base64.urlsafe_b64decode(literal)   # 第一层，漏掉必失败
val  = Fernet(key).decrypt(raw).decode()   # 第二层
```

```powershell
# 出网控制的正确顺序（含可复原）
Export-Clixml fwstate.xml -InputObject (Get-NetFirewallProfile)   # 先存原状
Set-NetFirewallProfile -Profile Private -Enabled True             # 默认可能是关的
New-NetFirewallRule -DisplayName '{RE}-Block-VendorDB' -Direction Outbound -RemoteAddress <ip> -Action Block
# ...分析...
Import-Clixml fwstate.xml | ForEach-Object { Set-NetFirewallProfile -Profile $_.Name -Enabled $_.Enabled }
Remove-NetFirewallRule -DisplayName '{RE}-Block-VendorDB'
```

## 对本包的改进建议

- `reverse-engineering` 主 skill 可补一条「打包器指纹速查」：Nuitka onefile / PyInstaller / pkg / Electron 的一眼判定信号，避免在错误假设上耗时。
- 后续若有「Nuitka 常量块解码」复用需求，`dec8.py` 的解码器与标签表值得沉淀成 `references/` 里的可复用脚本。
- `docs-generator` 的 `review_case.py --strict` 要求 Finding 字段值**不能带反引号或粗体**，否则 `field_value` 取到的字面量不匹配枚举集而报错。建议在模板里就写明纯文本字段值。
- Path 章节标题必须是 `### P-xxx`（三级）；写成 `#### P-xxx` 不会被 `PATH_HEADING` 匹配，`paths` 计数会静默为 0。值得在模板里标注。
- `diagram-generator` 在 Windows 上渲染 Mermaid 需 `npm install -g --allow-scripts=puppeteer @mermaid-js/mermaid-cli`（默认 npm 会跳过 puppeteer 的 postinstall，导致 `mmdc` 装上却渲染失败）。建议写进 bootstrap 说明。
- Mermaid 节点标签内不能出现裸 `\"` 转义；用 `&quot;`。

## 可复用的模式/脚本片段

```python
# Nuitka 常量块记录边界（伪代码）
data = blob[8:]                       # 跳过 8 字节头 (u32 0x5d7666f4)
while True:
    tag = data[pos]
    if tag == 0x2E: break             # END
    name, pos = read_cstr(data, pos)
    size, pos = read_u32(data, pos)
    count, pos = read_u16(data, pos)
    consts, pos = decode_tagged(data, pos, count)
    yield name, consts
```

```python
# 字面量拼接复原：把常量流片段还原成运行期字符串
# '":0:\'mod(t*"' + speed + "," + ")',setpts=PTS-STARTPTS[bg]"
#  -> "crop=W:H:0:'mod(t*SPEED,H)',setpts=PTS-STARTPTS[bg]"
def fuse_literals(parts):
    out, i = "", 0
    while i < len(parts):
        p = parts[i]
        if isinstance(p, str):
            out += p
        else:
            out += str(p)      # 插入运行期变量
        i += 1
    return out
```

## 进化动作

- [ ] 更新了路由矩阵
- [ ] 更新了 tool-index
- [ ] 更新了 bootstrap-manifest
- [ ] 更新了子 skill 文档
- [x] 新增了 pitfalls 记录（本文件「踩坑记录」「工具链发现」）
- [ ] 无需更新

## 环境信息

- OS: Windows 10 (19041), 管理员, PowerShell 7
- 工具版本: radare2 / Python 3.10.11 + 3.14 / zstandard / cryptography / Frida 17.16.4 / mmdc (@mermaid-js/mermaid-cli)
- 目标平台/版本: Windows x64 GUI 应用；自定义壳 + Nuitka onefile 打包

## 脱敏要求

- 目标域名/IP：已用 `{target_ip}` / `{db_name}` / `{db_user}` / `{password}` 替代
- 真实 URL 路径：仅保留结构
- Token/Cookie/密码/JWT/API key：已占位
- 厂商名与产品名按「目标特征」脱敏为「Windows GUI 视频批量处理工具」「自定义壳」

---

<!-- [进化统计] 本包累计完成项目: 22 | 本次新增模式: 3 | 本次修复工具链问题: 2 -->
<!-- [社区贡献] 完成后询问用户是否 PR 到主仓库。流程见 CONTRIBUTE-BACK.md -->
