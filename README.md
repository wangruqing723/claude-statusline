# Claude Code Statusline

为 [Claude Code](https://code.claude.com) 定制的状态栏脚本——双行布局，动态隐藏空字段，Gruvbox Dark 配色，支持 Git 状态、上下文进度、自定义网关名。

## 效果预览

```
[reviewer] │ ai-gateway │ Opus │ xhigh │ ctx 42% │ ↑15k ↓1k
demo │ ~/devtool/claude │ (main) ✓
```

**行1**：Agent │ 网关 │ 模型 │ 推理级别 │ 上下文占用 │ token 收发  
**行2**：会话名 │ 当前目录 │ git 分支与状态

无值的字段连同分隔符一起隐藏（Agent / 会话名 / 推理级别 / git 均可能缺失）。

## 一键安装

**macOS / Linux / WSL**（需已安装 `jq` 和 `git`）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wangruqing723/claude-statusline/main/install-statusline.sh)
```

带网关名安装（写入 shell 启动文件，让状态栏显示该名称）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wangruqing723/claude-statusline/main/install-statusline.sh) --gateway ai-gateway
```

脚本会自动：
1. 检测平台（macOS / WSL / Linux）并安装 `jq`（如缺失）
2. 写入 `~/.claude/statusline.sh` 并设置可执行权限
3. 合并写入 `~/.claude/settings.json` 的 `statusLine` 配置（保留已有配置）
4. （可选）将 `CC_GATEWAY_NAME` 写入 shell 启动文件（`.zshrc` / `.bashrc` / `.profile`）

## 手动安装

1. **下载脚本**
   ```bash
   curl -fsSL https://raw.githubusercontent.com/wangruqing723/claude-statusline/main/install-statusline.sh -o install-statusline.sh
   chmod +x install-statusline.sh
   ```

2. **运行安装**
   ```bash
   ./install-statusline.sh
   # 或带网关名
   ./install-statusline.sh --gateway ai-gateway
   ```

3. **重启 Claude Code** 即可看到新状态栏

## 卸载

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wangruqing723/claude-statusline/main/install-statusline.sh) --uninstall
```

或手动：移除 `~/.claude/settings.json` 里的 `statusLine` 配置并删除 `~/.claude/statusline.sh`。

## 字段说明

### 行1

| 字段 | 说明 | 取值来源 |
|------|------|---------|
| Agent | 子代理名（如 `[reviewer]`） | `agent.name` |
| 网关 | 中转/代理网关名或 host:port | `CC_GATEWAY_NAME` 环境变量，回退为 `ANTHROPIC_BASE_URL` 的 host:port |
| 模型 | 模型显示名（如 `Opus` / `Sonnet`） | `model.display_name` / `model.name` / `model.id` |
| 推理级别 | 思考深度（如 `xhigh` / `high`） | `effort.level` |
| 上下文占用 | `ctx XX%`，带三档配色：<50% 绿、<80% 橙、≥80% 红 | `context_window.used_percentage` |
| token 收发 | `↑收k ↓发k`，以千为单位 | `context_window.total_input_tokens` / `total_output_tokens` |

### 行2

| 字段 | 说明 |
|------|------|
| 会话名 | 命名会话的名字 |
| 当前目录 | `~` 缩写的工作目录 |
| git 分支与状态 | `(分支名) ✓` 干净 / `✗ +暂存 ~修改 ?未跟踪` 脏 |

## 自定义配色

编辑 `~/.claude/statusline.sh` 顶部的配色变量（行 58–73），参考 [256 色表](https://www.ditig.com/publications/256-colors-cheat-sheet)。

当前配色为 **Gruvbox Dark**：

```bash
AGENT_COLOR="\033[38;5;109m"     # 蓝
GATEWAY_COLOR="\033[38;5;108m"   # 青
MODEL_COLOR="\033[38;5;175m"     # 粉
EFFORT_COLOR="\033[38;5;214m"    # 橙
TOKEN_COLOR="\033[38;5;187m"     # 米
DIR_COLOR="\033[38;5;142m"       # 绿
GIT_COLOR="\033[38;5;175m"       # 粉
GIT_CLEAN="\033[38;5;142m"       # 绿
GIT_DIRTY="\033[38;5;203m"       # 红
PROGRESS_LOW="\033[38;5;142m"    # <50% 绿
PROGRESS_MID="\033[38;5;214m"    # <80% 橙
PROGRESS_HIGH="\033[38;5;203m"   # >=80% 红
```

改完后重启 Claude Code 生效，无需重新安装。

## WSL 注意事项

1. **脚本兼容性**：`install-statusline.sh` 在 WSL 内正常工作（自动识别 WSL 环境并用 `apt`/`dnf` 安装 `jq`）
2. **字符显示**：状态栏的 `│ ↑ ↓ ✓ ✗` 等 Unicode 字符能否显示取决于 **Windows 终端的字体**
   - **Windows Terminal**：推荐用 Nerd Font 或 Cascadia Code（默认支持这些字符）
   - **旧 conhost**：可能显示为方块，建议换 Windows Terminal
3. **适用范围**：此脚本是给 **WSL 内运行的 Claude Code** 用的；Windows 原生版 Claude Code 用不了（路径、shell 都不同）

## 故障排查

### 状态栏不显示

1. **检查配置**
   ```bash
   jq '.statusLine' ~/.claude/settings.json
   ```
   应输出：
   ```json
   {
     "type": "command",
     "command": "/Users/你的用户名/.claude/statusline.sh"
   }
   ```

2. **手动测试脚本**
   ```bash
   echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42,"total_input_tokens":5000,"total_output_tokens":500},"cwd":"'"$HOME"'"}' | bash ~/.claude/statusline.sh
   ```
   应打印两行带色输出。若报错 `jq: command not found`，手动装 `jq`。

3. **查看 Claude Code 日志**
   - macOS: `~/Library/Logs/Claude/`
   - Linux: `~/.config/Claude/logs/`

### 网关名不显示 / 显示成 host:port

未设置 `CC_GATEWAY_NAME` 环境变量时，脚本回退显示 `ANTHROPIC_BASE_URL` 的 host:port。

**补救**：在你的 shell 启动文件（`.zshrc` / `.bashrc`）里加：
```bash
export CC_GATEWAY_NAME="ai-gateway"
```
然后重开终端或 `source ~/.zshrc`。

### git 状态不准 / 不显示

- 确保 `git` 已安装：`git --version`
- 确保当前目录是 git 仓库：`git status`
- 检查脚本是否有 git 执行权限（某些企业环境会限制）

## 依赖

- **jq** (必须)：JSON 解析
- **git** (可选)：显示 git 分支与状态
- **bash** 3.2+（macOS 自带版本足够）

## 原理

Claude Code 的 `statusLine.command` 每次刷新时，会将当前会话状态以 JSON 格式通过 stdin 传给指定脚本，脚本输出的两行文本直接渲染为状态栏。

本脚本用 `jq` 提取字段 → bash 拼接带色字符串 → 输出到 stdout。

## 许可

MIT License — 详见 [LICENSE](LICENSE)

## 贡献

欢迎提 issue 或 PR：
- 新增配色方案
- 适配其他 shell（fish / nushell）
- 更多字段展示（PR number / worktree / 缓存命中率等）
- Windows 原生 PowerShell 版本

---

**相关链接**
- [Claude Code 官方文档](https://code.claude.com/docs)
- [statusLine 字段参考](https://code.claude.com/docs/en/statusline.md)
