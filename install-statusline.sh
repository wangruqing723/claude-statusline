#!/usr/bin/env bash
# ==============================================================================
# Claude Code Statusline 一键安装脚本
#
# 兼容: macOS / Linux / Windows WSL
# 用法: bash install-statusline.sh [--gateway <名称>] [--uninstall]
#
#   --gateway <名称>  可选。写入当前 shell 的启动文件，让状态栏显示该网关名。
#                     不传则状态栏回退显示 ANTHROPIC_BASE_URL 的 host:port。
#   --uninstall       移除 statusLine 配置（不动脚本文件本身）。
#
# 本脚本自包含：内嵌了完整的 statusline.sh，单文件拷到目标机即可运行。
# ==============================================================================

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
STATUSLINE="$CLAUDE_DIR/statusline.sh"

GATEWAY_NAME=""
DO_UNINSTALL=0

# ── 参数解析
while [[ $# -gt 0 ]]; do
    case "$1" in
        --gateway)   GATEWAY_NAME="${2:-}"; shift 2 ;;
        --uninstall) DO_UNINSTALL=1; shift ;;
        -h|--help)   sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "未知参数: $1（用 --help 查看用法）" >&2; exit 1 ;;
    esac
done

# ── 平台探测
detect_platform() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)
            if grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
                echo "wsl"
            else
                echo "linux"
            fi ;;
        *) echo "unknown" ;;
    esac
}
PLATFORM="$(detect_platform)"

# ── 依赖检查：jq 为脚本硬依赖
ensure_jq() {
    if command -v jq &>/dev/null; then
        echo "  ✓ jq 已安装: $(jq --version)"
        return 0
    fi

    echo "  ! 未检测到 jq（statusline 解析 JSON 必需）"
    case "$PLATFORM" in
        macos)
            if command -v brew &>/dev/null; then
                echo "  → 执行: brew install jq"
                brew install jq
            else
                echo "  ✗ 未找到 Homebrew。请先装 Homebrew，或手动执行: brew install jq" >&2
                echo "    Homebrew 安装: https://brew.sh" >&2
                return 1
            fi ;;
        wsl|linux)
            if command -v apt-get &>/dev/null; then
                echo "  → 执行: sudo apt-get update && sudo apt-get install -y jq"
                sudo apt-get update && sudo apt-get install -y jq
            elif command -v dnf &>/dev/null; then
                echo "  → 执行: sudo dnf install -y jq"
                sudo dnf install -y jq
            elif command -v pacman &>/dev/null; then
                echo "  → 执行: sudo pacman -S --noconfirm jq"
                sudo pacman -S --noconfirm jq
            else
                echo "  ✗ 未识别包管理器。请手动安装 jq: https://jqlang.github.io/jq/download/" >&2
                return 1
            fi ;;
        *)
            echo "  ✗ 未识别系统，请手动安装 jq: https://jqlang.github.io/jq/download/" >&2
            return 1 ;;
    esac
}

# ── 定位 shell 启动文件（用于写 CC_GATEWAY_NAME）
shell_rc_file() {
    local shell_name
    shell_name="$(basename "${SHELL:-bash}")"
    case "$shell_name" in
        zsh)  echo "$HOME/.zshrc" ;;
        bash) [[ -f "$HOME/.bashrc" ]] && echo "$HOME/.bashrc" || echo "$HOME/.bash_profile" ;;
        *)    echo "$HOME/.profile" ;;
    esac
}

# ── 合并写入 statusLine 到 settings.json（保留其余配置）
write_settings() {
    mkdir -p "$CLAUDE_DIR"
    [[ -f "$SETTINGS" ]] || echo '{}' > "$SETTINGS"

    local tmp="$CLAUDE_DIR/.settings.json.tmp.$$"
    jq --arg cmd "$STATUSLINE" \
       '.statusLine = {type: "command", command: $cmd}' \
       "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    echo "  ✓ 已写入 statusLine 配置 → $SETTINGS"
}

# ==============================================================================
# 卸载分支
# ==============================================================================
if [[ "$DO_UNINSTALL" -eq 1 ]]; then
    echo "==> 卸载 statusLine 配置"
    if [[ ! -f "$SETTINGS" ]]; then
        echo "  ! 未找到 $SETTINGS，无需卸载"
        exit 0
    fi
    tmp="$CLAUDE_DIR/.settings.json.tmp.$$"
    jq 'del(.statusLine)' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    echo "  ✓ 已移除 statusLine 配置"
    echo "  （脚本文件 $STATUSLINE 仍保留，如需删除请手动 rm）"
    exit 0
fi

# ==============================================================================
# 安装主流程
# ==============================================================================
echo "==> 平台: $PLATFORM"
echo "==> 目标目录: $CLAUDE_DIR"
echo ""

echo "==> [1/4] 检查依赖"
ensure_jq

echo ""
echo "==> [2/4] 写入 statusline.sh"
mkdir -p "$CLAUDE_DIR"
cat > "$STATUSLINE" <<'STATUSLINE_EOF'
#!/bin/bash
# Claude Code Statusline — 配色: Gruvbox Dark
#
# 行1: Agent │ 网关 │ 模型 │ 推理级别 │ 上下文进度 │ token 收发
# 行2: 会话名 │ 当前目录 │ git 分支与状态
#
# 无值的字段连同其分隔符一起隐藏（Agent / 会话名 / 推理级别 / git 均可能缺失）。
# 网关名取自 CC_GATEWAY_NAME（见 ~/.claude-env）；未设置时回退为 ANTHROPIC_BASE_URL 的 host:port。

# 检测 jq 依赖
if ! command -v jq &> /dev/null; then
    echo "[CC-Statusline] 错误: 需要安装 jq 命令" >&2
    echo "macOS: brew install jq" >&2
    echo "Ubuntu/Debian: sudo apt install jq" >&2
    echo "Fedora: sudo dnf install jq" >&2
    echo "其他系统: https://jqlang.github.io/jq/download/" >&2
    exit 1
fi

JSON_INPUT=$(cat)

# ── 字段提取：一次 jq 按行输出全部字段（macOS 自带 bash 3.2 无 mapfile，用 while read 收集）
FIELDS=()
while IFS= read -r _f; do FIELDS+=("$_f"); done < <(
    printf '%s' "$JSON_INPUT" | jq -r '
        (.agent.name // ""),
        (.model.display_name // .model.name // .model.id // "Claude"),
        (.effort.level // ""),
        (.context_window.used_percentage // 0),
        (.context_window.total_input_tokens // 0),
        (.context_window.total_output_tokens // 0),
        (.session_name // ""),
        (.cwd // .workspace.current_dir // "")
    '
)

agent="${FIELDS[0]}"
model="${FIELDS[1]}"
effort="${FIELDS[2]}"
percent="${FIELDS[3]}"
input="${FIELDS[4]}"
output="${FIELDS[5]}"
session_name="${FIELDS[6]}"
cwd="${FIELDS[7]}"

# 网关名：优先 CC_GATEWAY_NAME，否则从 base URL 剥出 host:port
gateway="${CC_GATEWAY_NAME:-}"
if [[ -z "$gateway" && -n "$ANTHROPIC_BASE_URL" ]]; then
    gateway="${ANTHROPIC_BASE_URL#*://}"
    gateway="${gateway%%/*}"
fi

# 百分比规整：去掉小数、非数字兜底为 0、上限 100
percent="${percent%%.*}"
[[ "$percent" =~ ^[0-9]+$ ]] || percent=0
(( percent > 100 )) && percent=100

# ── 配色
RESET="\033[0m"
SEP_COLOR="\033[38;5;240m"      # 分隔竖线：暗灰，不抢视线
AGENT_COLOR="\033[38;5;109m"    # 蓝
GATEWAY_COLOR="\033[38;5;108m"  # 青
MODEL_COLOR="\033[38;5;175m"    # 粉
EFFORT_COLOR="\033[38;5;214m"   # 橙
TOKEN_COLOR="\033[38;5;187m"    # 米
SESSION_COLOR="\033[38;5;109m"  # 蓝
DIR_COLOR="\033[38;5;142m"      # 绿
GIT_COLOR="\033[38;5;175m"      # 粉
GIT_CLEAN="\033[38;5;142m"      # 绿
GIT_DIRTY="\033[38;5;203m"      # 红
PROGRESS_LOW="\033[38;5;142m"   # <50% 绿
PROGRESS_MID="\033[38;5;214m"   # <80% 橙
PROGRESS_HIGH="\033[38;5;203m"  # >=80% 红

SEP="${SEP_COLOR} │ ${RESET}"

# 按占用率给上下文百分比着色：<50 绿，<80 橙，>=80 红
get_progress_color() {
    local p=$1
    if   (( p < 50 )); then printf '%s' "$PROGRESS_LOW"
    elif (( p < 80 )); then printf '%s' "$PROGRESS_MID"
    else                    printf '%s' "$PROGRESS_HIGH"
    fi
}

get_directory() {
    local dir="$1"
    if [[ "$dir" == "$HOME"* ]]; then
        printf '~%s' "${dir#$HOME}"
    else
        printf '%s' "$dir"
    fi
}

format_tokens() { printf '%s' "$(($1 / 1000))"; }

# 用分隔符拼接非空片段
join_parts() {
    local out="" p
    for p in "$@"; do
        [[ -z "$p" ]] && continue
        [[ -n "$out" ]] && out+="$SEP"
        out+="$p"
    done
    printf '%b\n' "$out"
}

# ── 行1 各片段
p_agent=""
[[ -n "$agent" ]] && p_agent="${AGENT_COLOR}[${agent}]${RESET}"

p_gateway=""
[[ -n "$gateway" ]] && p_gateway="${GATEWAY_COLOR}${gateway}${RESET}"

p_model="${MODEL_COLOR}${model}${RESET}"

p_effort=""
[[ -n "$effort" ]] && p_effort="${EFFORT_COLOR}${effort}${RESET}"

p_ctx="$(get_progress_color "$percent")ctx ${percent}%${RESET}"

p_tokens="${TOKEN_COLOR}↑$(format_tokens "$input")k ↓$(format_tokens "$output")k${RESET}"

join_parts "$p_agent" "$p_gateway" "$p_model" "$p_effort" "$p_ctx" "$p_tokens"

# ── 行2 各片段
p_session=""
[[ -n "$session_name" ]] && p_session="${SESSION_COLOR}${session_name}${RESET}"

p_dir=""
[[ -n "$cwd" ]] && p_dir="${DIR_COLOR}$(get_directory "$cwd")${RESET}"

p_git=""
if [[ -n "$cwd" ]]; then
    git_branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [[ -n "$git_branch" ]]; then
        p_git="${GIT_COLOR}(${git_branch})${RESET}"
        if git -C "$cwd" diff --quiet 2>/dev/null && git -C "$cwd" diff --cached --quiet 2>/dev/null; then
            p_git+=" ${GIT_CLEAN}✓${RESET}"
        else
            p_git+=" ${GIT_DIRTY}✗${RESET}"
            staged=$(git -C "$cwd" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
            modified=$(git -C "$cwd" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
            untracked=$(git -C "$cwd" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
            [[ "$staged"    -gt 0 ]] && p_git+=" ${GIT_CLEAN}+${staged}${RESET}"
            [[ "$modified"  -gt 0 ]] && p_git+=" ${PROGRESS_MID}~${modified}${RESET}"
            [[ "$untracked" -gt 0 ]] && p_git+=" ${TOKEN_COLOR}?${untracked}${RESET}"
        fi
    fi
fi

join_parts "$p_session" "$p_dir" "$p_git"

# 确保脚本始终以退出码 0 结束，避免最后一条 && 短路导致 Claude Code 判定 statusline 失败而不渲染
exit 0
STATUSLINE_EOF

chmod +x "$STATUSLINE"
echo "  ✓ 已写入并可执行: $STATUSLINE"

echo ""
echo "==> [3/4] 配置 settings.json"
write_settings

echo ""
echo "==> [4/4] 可选：网关名"
if [[ -n "$GATEWAY_NAME" ]]; then
    RC="$(shell_rc_file)"
    if grep -q 'CC_GATEWAY_NAME' "$RC" 2>/dev/null; then
        echo "  ! $RC 中已存在 CC_GATEWAY_NAME，跳过（如需修改请手动编辑）"
    else
        printf '\n# Claude Code statusline 网关显示名\nexport CC_GATEWAY_NAME="%s"\n' "$GATEWAY_NAME" >> "$RC"
        echo "  ✓ 已写入 $RC: CC_GATEWAY_NAME=\"$GATEWAY_NAME\""
    fi
else
    echo "  跳过（未传 --gateway）。状态栏将显示 ANTHROPIC_BASE_URL 的 host:port。"
fi

echo ""
echo "==> 验证渲染"
echo '{"agent":{"name":"demo"},"model":{"display_name":"Opus"},"effort":{"level":"high"},"context_window":{"used_percentage":42,"total_input_tokens":15500,"total_output_tokens":1200},"session_name":"demo","cwd":"'"$HOME"'"}' | bash "$STATUSLINE"
echo "  (上面两行为实际渲染效果，退出码 $?)"

echo ""
echo "=============================================="
echo " 安装完成"
echo "=============================================="
echo " • 开一个新终端（或 source 你的 shell 启动文件）使 CC_GATEWAY_NAME 生效"
echo " • 重启 Claude Code 即可看到新状态栏"
echo " • 卸载: bash $0 --uninstall"
