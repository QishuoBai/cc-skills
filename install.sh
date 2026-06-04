#!/usr/bin/env bash
#
# cc-skills install — 一键安装 CLI 工具
#
# 自动扫描 clis/ 目录，将 CLI 工具通过 symlink 安装到 PATH 中。
#
# 约定：每个 CLI 是 clis/<name>/ 目录，内含同名可执行文件 <name>。
#
# 用法:
#   ./install.sh                       安装所有 CLI
#   ./install.sh <name>                安装指定 CLI
#   ./install.sh --list                列出所有可用 CLI
#   ./install.sh --uninstall           卸载所有已安装的 CLI
#   ./install.sh --uninstall <name>    卸载指定 CLI

set -euo pipefail

# ══════════════════════════════════════════════
# 常量
# ══════════════════════════════════════════════

readonly VERSION="1.0.0"
readonly REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly CLIS_DIR="$REPO_DIR/clis"
readonly BIN_DIR="$HOME/.local/bin"
readonly SYMLINK_MARKER="cc-skills"  # symlink 描述中标记来源

# ══════════════════════════════════════════════
# 颜色 & 输出
# ══════════════════════════════════════════════

if [[ -t 1 ]]; then
  readonly C_RESET=$'\033[0m'
  readonly C_BOLD=$'\033[1m'
  readonly C_DIM=$'\033[2m'
  readonly C_GREEN=$'\033[32m'
  readonly C_RED=$'\033[31m'
  readonly C_YELLOW=$'\033[33m'
  readonly C_CYAN=$'\033[36m'
  readonly C_GRAY=$'\033[90m'
else
  readonly C_RESET='' C_BOLD='' C_DIM='' C_GREEN='' C_RED='' C_YELLOW='' C_CYAN='' C_GRAY=''
fi

info()  { echo "${C_CYAN}▸${C_RESET} $*"; }
ok()    { echo "${C_GREEN}✓${C_RESET} $*"; }
warn()  { echo "${C_YELLOW}⚠${C_RESET} $*"; }
err()   { echo "${C_RED}✗${C_RESET} $*" >&2; }

# ══════════════════════════════════════════════
# CLI 发现
# ══════════════════════════════════════════════

# 发现所有可用的 CLI，返回名称列表（每行一个）
discover_clis() {
  local clis=()
  if [[ ! -d "$CLIS_DIR" ]]; then
    return
  fi
  for dir in "$CLIS_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    local name
    name=$(basename "$dir")
    local exe="$dir/$name"
    # 必须是存在的可执行文件（或至少是普通文件，我们后续加权限）
    if [[ -f "$exe" ]]; then
      clis+=("$name")
    fi
  done
  printf '%s\n' "${clis[@]}"
}

# 获取某个 CLI 的源文件绝对路径
cli_source_path() {
  local name="$1"
  echo "$CLIS_DIR/$name/$name"
}

# 获取某个 CLI 的 symlink 目标路径
cli_link_path() {
  local name="$1"
  echo "$BIN_DIR/$name"
}

# 检查某个 CLI 是否已安装
cli_is_installed() {
  local name="$1"
  local link
  link=$(cli_link_path "$name")
  if [[ -L "$link" ]]; then
    local target
    target=$(readlink "$link")
    local source
    source=$(cli_source_path "$name")
    # 判断 symlink 是否指向我们的仓库
    [[ "$target" == "$source" ]] && return 0
  fi
  return 1
}

# 获取 CLI 的版本（从文件中读取 VERSION 常量，或返回 "unknown"）
cli_version() {
  local name="$1"
  local source
  source=$(cli_source_path "$name")
  local ver
  ver=$(sed -n 's/.*readonly VERSION="\([^"]*\)".*/\1/p' "$source" 2>/dev/null | head -1)
  if [[ -z "$ver" ]]; then
    ver=$(sed -n 's/.*VERSION="\([^"]*\)".*/\1/p' "$source" 2>/dev/null | head -1)
  fi
  echo "${ver:-unknown}"
}

# 获取 CLI 的描述（从文件头注释提取第一行描述）
cli_description() {
  local name="$1"
  local source
  source=$(cli_source_path "$name")
  # 从 # name — description 格式提取（兼容 macOS sed）
  local desc
  desc=$(head -10 "$source" 2>/dev/null | sed -n 's/.*— *//p' | head -1)
  echo "${desc:-}"
}

# ══════════════════════════════════════════════
# 安装 / 卸载
# ══════════════════════════════════════════════

# 确保 bin 目录存在
ensure_bin_dir() {
  if [[ ! -d "$BIN_DIR" ]]; then
    info "创建 bin 目录 → $BIN_DIR"
    mkdir -p "$BIN_DIR"
  fi
}

# 检查 bin 目录是否在 PATH 中
check_path() {
  case ":$PATH:" in
    *":$BIN_DIR:"*) return 0 ;;
    *) return 1 ;;
  esac
}

# 自动将 bin 目录添加到 shell 配置的 PATH 中
ensure_path() {
  if check_path; then
    return 0
  fi

  # 检测当前 shell 对应的配置文件
  local rc_file=""
  local shell_name
  shell_name=$(basename "${SHELL:-/bin/bash}")

  case "$shell_name" in
    zsh)  rc_file="$HOME/.zshrc" ;;
    bash)
      if [[ -f "$HOME/.bashrc" ]]; then
        rc_file="$HOME/.bashrc"
      elif [[ -f "$HOME/.bash_profile" ]]; then
        rc_file="$HOME/.bash_profile"
      fi
      ;;
    fish) rc_file="$HOME/.config/fish/config.fish" ;;
  esac

  # 未检测到支持的 shell，回退到常见文件
  if [[ -z "$rc_file" ]]; then
    for f in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
      if [[ -f "$f" ]]; then
        rc_file="$f"
        break
      fi
    done
  fi

  # 仍然找不到，尝试创建 ~/.zshrc（macOS 默认）
  if [[ -z "$rc_file" ]]; then
    rc_file="$HOME/.zshrc"
  fi

  local path_line='export PATH="$HOME/.local/bin:$PATH"'

  # 检查配置文件中是否已有类似的未注释配置（避免重复添加）
  if [[ -f "$rc_file" ]]; then
    # 排除注释行（以 # 开头，允许前导空白），只匹配实际生效的 PATH 配置
    if grep -v '^\s*#' "$rc_file" 2>/dev/null | grep -q '\.local/bin'; then
      # 已有配置但当前 shell 未生效，提示用户 source
      ok "$BIN_DIR 已在 $rc_file 的 PATH 配置中"
      echo ""
      info "当前终端未生效，请执行: ${C_DIM}source $rc_file${C_RESET}"
      return 0
    fi
  fi

  # 追加 PATH 配置
  local marker="# cc-skills: add ~/.local/bin to PATH"
  {
    echo ""
    echo "$marker"
    if [[ "$shell_name" == "fish" ]]; then
      echo 'fish_add_path "$HOME/.local/bin"'
    else
      echo "$path_line"
    fi
  } >> "$rc_file"

  ok "已自动将 PATH 配置写入 ${C_BOLD}$rc_file${C_RESET}"
  echo ""
  info "当前终端立即生效，请执行: ${C_DIM}source $rc_file${C_RESET}"

  # 尝试在当前 shell 中直接生效（导出到环境）
  export PATH="$BIN_DIR:$PATH"
}

# 安装单个 CLI
install_cli() {
  local name="$1"
  local source
  source=$(cli_source_path "$name")
  local link
  link=$(cli_link_path "$name")

  # 检查源文件存在
  if [[ ! -f "$source" ]]; then
    err "$name: 源文件不存在 ($source)"
    return 1
  fi

  # 确保可执行权限
  if [[ ! -x "$source" ]]; then
    info "$name: 添加可执行权限"
    chmod +x "$source"
  fi

  # 如果已安装且指向正确，跳过
  if cli_is_installed "$name"; then
    ok "$name: 已安装 (v$(cli_version "$name"))"
    return 0
  fi

  # 如果 link 已存在但不是我们的（冲突）
  if [[ -e "$link" || -L "$link" ]]; then
    local existing_target
    existing_target=$(readlink -f "$link" 2>/dev/null || readlink "$link" 2>/dev/null || echo "?")
    warn "$name: $link 已存在 → $existing_target"
    warn "  跳过（请手动处理冲突）"
    return 1
  fi

  # 创建 symlink
  ln -s "$source" "$link"
  ok "$name: 已安装 → $link (v$(cli_version "$name"))"
  return 0
}

# 卸载单个 CLI
uninstall_cli() {
  local name="$1"
  local link
  link=$(cli_link_path "$name")

  if [[ ! -L "$link" ]]; then
    warn "$name: 未安装"
    return 0
  fi

  # 确认是我们创建的 symlink
  local target
  target=$(readlink "$link")
  if [[ "$target" != "$(cli_source_path "$name")" ]]; then
    warn "$name: $link 不是由本脚本创建的 (→ $target)，跳过"
    return 1
  fi

  rm -f "$link"
  ok "$name: 已卸载"
  return 0
}

# ══════════════════════════════════════════════
# 子命令
# ══════════════════════════════════════════════

cmd_list() {
  local clis
  clis=$(discover_clis)

  if [[ -z "$clis" ]]; then
    warn "未发现任何 CLI 工具 ($CLIS_DIR)"
    return
  fi

  echo ""
  echo "${C_BOLD}可用的 CLI 工具:${C_RESET}"
  echo ""

  while IFS= read -r name; do
    local status_icon status_text
    if cli_is_installed "$name"; then
      status_icon="${C_GREEN}✓${C_RESET}"
      status_text="${C_GREEN}已安装${C_RESET}"
    else
      status_icon="${C_GRAY}○${C_RESET}"
      status_text="${C_GRAY}未安装${C_RESET}"
    fi

    local desc
    desc=$(cli_description "$name")
    local ver
    ver=$(cli_version "$name")

    printf "  %s  ${C_BOLD}%-24s${C_RESET}  v%-10s  %s\n" "$status_icon" "$name" "$ver" "$desc"
  done <<< "$clis"

  echo ""
  echo "  安装:   ${C_DIM}./install.sh [name]${C_RESET}"
  echo "  卸载:   ${C_DIM}./install.sh --uninstall [name]${C_RESET}"
  echo ""
}

cmd_install() {
  local target="${1:-}"

  ensure_bin_dir

  local clis
  if [[ -n "$target" ]]; then
    # 安装指定 CLI
    local source
    source=$(cli_source_path "$target")
    if [[ ! -f "$source" ]]; then
      err "未找到 CLI: $target"
      echo ""
      echo "可用的 CLI:"
      discover_clis | while IFS= read -r n; do echo "  - $n"; done
      return 1
    fi
    clis="$target"
  else
    # 安装全部
    clis=$(discover_clis)
    if [[ -z "$clis" ]]; then
      warn "未发现任何 CLI 工具 ($CLIS_DIR)"
      return 1
    fi
  fi

  local count=0
  local failed=0

  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if install_cli "$name"; then
      (( count++ )) || true
    else
      (( failed++ )) || true
    fi
  done <<< "$clis"

  echo ""
  if (( count > 0 )); then
    ok "已安装 ${count} 个 CLI 工具到 $BIN_DIR"
  fi
  if (( failed > 0 )); then
    warn "${failed} 个安装失败或被跳过"
  fi

  # PATH 检查 & 自动配置
  echo ""
  ensure_path
}

cmd_uninstall() {
  local target="${1:-}"

  local clis
  if [[ -n "$target" ]]; then
    clis="$target"
  else
    # 卸载所有已安装的
    local all_clis
    all_clis=$(discover_clis)
    if [[ -z "$all_clis" ]]; then
      warn "未发现任何 CLI 工具"
      return
    fi
    clis="$all_clis"
  fi

  local count=0

  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if uninstall_cli "$name"; then
      (( count++ )) || true
    fi
  done <<< "$clis"

  echo ""
  if (( count > 0 )); then
    ok "已卸载 ${count} 个 CLI 工具"
  else
    info "没有需要卸载的 CLI"
  fi
}

cmd_help() {
  cat << EOF

${C_BOLD}cc-skills install${C_RESET} v${VERSION} — CLI 工具安装器

${C_BOLD}用法:${C_RESET}
  ./install.sh                         安装所有 CLI 工具
  ./install.sh <name>                  安装指定 CLI
  ./install.sh --list                  列出所有可用 CLI 及状态
  ./install.sh --uninstall             卸载所有已安装的 CLI
  ./install.sh --uninstall <name>      卸载指定 CLI
  ./install.sh --help                  显示本帮助

${C_BOLD}约定:${C_RESET}
  每个 CLI 工具位于 clis/<name>/ 目录下，含同名可执行文件。
  安装时在 ${BIN_DIR} 创建 symlink 指向源文件。

${C_BOLD}示例:${C_RESET}
  ./install.sh                         ${C_GRAY}# 安装全部${C_RESET}
  ./install.sh openclaw-watchdog       ${C_GRAY}# 只安装 watchdog${C_RESET}
  ./install.sh --list                  ${C_GRAY}# 查看可用 CLI${C_RESET}
  ./install.sh --uninstall             ${C_GRAY}# 卸载全部${C_RESET}

EOF
}

# ══════════════════════════════════════════════
# 入口
# ══════════════════════════════════════════════

main() {
  case "${1:-}" in
    --list|-l)
      cmd_list
      ;;
    --uninstall|-u)
      shift 2>/dev/null || true
      cmd_uninstall "${1:-}"
      ;;
    --help|-h)
      cmd_help
      ;;
    "")
      cmd_install
      ;;
    *)
      # 可能是 CLI 名称
      if [[ "$1" == -* ]]; then
        err "未知选项: $1"
        cmd_help
        exit 1
      fi
      cmd_install "$1"
      ;;
  esac
}

main "$@"
