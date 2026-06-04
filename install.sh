#!/usr/bin/env bash
#
# cc-skills install — 一键安装 CLI 工具 & Skills
#
# 自动扫描 clis/ 和 skills/ 目录，通过 symlink 安装到系统中。
#
# 约定：
#   - 每个 CLI 是 clis/<name>/ 目录，内含同名可执行文件 <name>
#   - 每个 Skill 是 skills/<name>/ 目录，内含 SKILL.md
#
# 用法:
#   ./install.sh                       安装所有 CLI 和 Skills
#   ./install.sh <name>                安装指定 CLI 或 Skill
#   ./install.sh --cli                 仅安装所有 CLI
#   ./install.sh --skill               仅安装所有 Skills
#   ./install.sh --list                列出所有可用项及状态
#   ./install.sh --uninstall           卸载所有已安装项
#   ./install.sh --uninstall <name>    卸载指定项

set -euo pipefail

# ══════════════════════════════════════════════
# 常量
# ══════════════════════════════════════════════

readonly VERSION="1.1.0"
readonly REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly CLIS_DIR="$REPO_DIR/clis"
readonly SKILLS_DIR="$REPO_DIR/skills"
readonly BIN_DIR="$HOME/.local/bin"
readonly CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
readonly CLAUDE_CODE_URL="https://docs.anthropic.com/en/docs/claude-code/overview"

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
  readonly C_MAGENTA=$'\033[35m'
else
  readonly C_RESET='' C_BOLD='' C_DIM='' C_GREEN='' C_RED='' C_YELLOW='' C_CYAN='' C_GRAY='' C_MAGENTA=''
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
    if [[ -f "$exe" ]]; then
      clis+=("$name")
    fi
  done
  if [[ ${#clis[@]} -gt 0 ]]; then
    printf '%s\n' "${clis[@]}"
  fi
}

# 发现所有可用的 Skills，返回名称列表（每行一个）
discover_skills() {
  local skills=()
  if [[ ! -d "$SKILLS_DIR" ]]; then
    return
  fi
  for dir in "$SKILLS_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    local name
    name=$(basename "$dir")
    # 跳过以 . 开头的隐藏目录
    [[ "$name" == .* ]] && continue
    # 必须包含 SKILL.md
    if [[ -f "$dir/SKILL.md" ]]; then
      skills+=("$name")
    fi
  done
  if [[ ${#skills[@]} -gt 0 ]]; then
    printf '%s\n' "${skills[@]}"
  fi
}

# ══════════════════════════════════════════════
# CLI 路径 & 状态
# ══════════════════════════════════════════════

cli_source_path() {
  local name="$1"
  echo "$CLIS_DIR/$name/$name"
}

cli_link_path() {
  local name="$1"
  echo "$BIN_DIR/$name"
}

cli_is_installed() {
  local name="$1"
  local link
  link=$(cli_link_path "$name")
  if [[ -L "$link" ]]; then
    local target
    target=$(readlink "$link")
    local source
    source=$(cli_source_path "$name")
    [[ "$target" == "$source" ]] && return 0
  fi
  return 1
}

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

cli_description() {
  local name="$1"
  local source
  source=$(cli_source_path "$name")
  local desc
  desc=$(head -10 "$source" 2>/dev/null | sed -n 's/.*— *//p' | head -1)
  echo "${desc:-}"
}

# ══════════════════════════════════════════════
# Skill 路径 & 状态
# ══════════════════════════════════════════════

skill_source_path() {
  local name="$1"
  echo "$SKILLS_DIR/$name"
}

skill_link_path() {
  local name="$1"
  echo "$CLAUDE_SKILLS_DIR/$name"
}

skill_is_installed() {
  local name="$1"
  local link
  link=$(skill_link_path "$name")
  if [[ -L "$link" ]]; then
    local target
    target=$(readlink "$link")
    local source
    source=$(skill_source_path "$name")
    [[ "$target" == "$source" ]] && return 0
  fi
  return 1
}

skill_description() {
  local name="$1"
  local source
  source=$(skill_source_path "$name")
  local skill_md="$source/SKILL.md"
  if [[ ! -f "$skill_md" ]]; then
    echo ""
    return
  fi
  # 从 YAML frontmatter 的 description 字段提取第一行
  local desc
  desc=$(sed -n '/^description:/,/^---$/p' "$skill_md" 2>/dev/null | head -1 | sed 's/^description: *>* *//')
  if [[ -z "$desc" ]]; then
    # 尝试从 # 标题行提取
    desc=$(grep -m1 '^# ' "$skill_md" 2>/dev/null | sed 's/^# //' | sed 's/ — .*//')
  fi
  echo "${desc:-}"
}

# ══════════════════════════════════════════════
# CLI 安装 / 卸载
# ══════════════════════════════════════════════

ensure_bin_dir() {
  if [[ ! -d "$BIN_DIR" ]]; then
    info "创建 bin 目录 → $BIN_DIR"
    mkdir -p "$BIN_DIR"
  fi
}

check_path() {
  case ":$PATH:" in
    *":$BIN_DIR:"*) return 0 ;;
    *) return 1 ;;
  esac
}

ensure_path() {
  if check_path; then
    return 0
  fi

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

  if [[ -z "$rc_file" ]]; then
    for f in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
      if [[ -f "$f" ]]; then
        rc_file="$f"
        break
      fi
    done
  fi

  if [[ -z "$rc_file" ]]; then
    rc_file="$HOME/.zshrc"
  fi

  local path_line='export PATH="$HOME/.local/bin:$PATH"'

  if [[ -f "$rc_file" ]]; then
    if grep -v '^\s*#' "$rc_file" 2>/dev/null | grep -q '\.local/bin'; then
      ok "$BIN_DIR 已在 $rc_file 的 PATH 配置中"
      echo ""
      info "当前终端未生效，请执行: ${C_DIM}source $rc_file${C_RESET}"
      return 0
    fi
  fi

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
  export PATH="$BIN_DIR:$PATH"
}

install_cli() {
  local name="$1"
  local source
  source=$(cli_source_path "$name")
  local link
  link=$(cli_link_path "$name")

  if [[ ! -f "$source" ]]; then
    err "$name: 源文件不存在 ($source)"
    return 1
  fi

  if [[ ! -x "$source" ]]; then
    info "$name: 添加可执行权限"
    chmod +x "$source"
  fi

  if cli_is_installed "$name"; then
    ok "${C_DIM}[CLI]${C_RESET} $name: 已安装 (v$(cli_version "$name"))"
    return 0
  fi

  if [[ -e "$link" || -L "$link" ]]; then
    local existing_target
    existing_target=$(readlink -f "$link" 2>/dev/null || readlink "$link" 2>/dev/null || echo "?")
    warn "$name: $link 已存在 → $existing_target"
    warn "  跳过（请手动处理冲突）"
    return 1
  fi

  ln -s "$source" "$link"
  ok "${C_DIM}[CLI]${C_RESET} $name: 已安装 → $link (v$(cli_version "$name"))"
  return 0
}

uninstall_cli() {
  local name="$1"
  local link
  link=$(cli_link_path "$name")

  if [[ ! -L "$link" ]]; then
    warn "$name: 未安装"
    return 0
  fi

  local target
  target=$(readlink "$link")
  if [[ "$target" != "$(cli_source_path "$name")" ]]; then
    warn "$name: $link 不是由本脚本创建的 (→ $target)，跳过"
    return 1
  fi

  rm -f "$link"
  ok "${C_DIM}[CLI]${C_RESET} $name: 已卸载"
  return 0
}

# ══════════════════════════════════════════════
# Skill 安装 / 卸载
# ══════════════════════════════════════════════

# 检查 Claude Code 是否已安装（skills 目录是否存在）
check_claude_code() {
  if [[ -d "$CLAUDE_SKILLS_DIR" ]]; then
    return 0
  fi
  # 也检查 ~/.claude 目录是否存在（可能 skills 目录还没创建）
  if [[ -d "$HOME/.claude" ]]; then
    return 0
  fi
  return 1
}

ensure_claude_skills_dir() {
  if check_claude_code; then
    if [[ ! -d "$CLAUDE_SKILLS_DIR" ]]; then
      info "创建 Claude Code skills 目录 → $CLAUDE_SKILLS_DIR"
      mkdir -p "$CLAUDE_SKILLS_DIR"
    fi
    return 0
  fi

  err "未检测到 Claude Code 安装"
  echo ""
  echo "  Skills 需要安装到 ${C_BOLD}$CLAUDE_SKILLS_DIR${C_RESET}，"
  echo "  该目录属于 Claude Code（Anthropic 的 CLI 工具）。"
  echo ""
  echo "  请先安装 Claude Code："
  echo "  ${C_CYAN}$CLAUDE_CODE_URL${C_RESET}"
  echo ""
  return 1
}

install_skill() {
  local name="$1"
  local source
  source=$(skill_source_path "$name")
  local link
  link=$(skill_link_path "$name")

  if [[ ! -d "$source" ]]; then
    err "$name: 源目录不存在 ($source)"
    return 1
  fi

  if skill_is_installed "$name"; then
    ok "${C_MAGENTA}[Skill]${C_RESET} $name: 已安装"
    return 0
  fi

  if [[ -e "$link" || -L "$link" ]]; then
    local existing_target
    existing_target=$(readlink -f "$link" 2>/dev/null || readlink "$link" 2>/dev/null || echo "?")
    warn "$name: $link 已存在 → $existing_target"
    warn "  跳过（请手动处理冲突）"
    return 1
  fi

  ln -s "$source" "$link"
  ok "${C_MAGENTA}[Skill]${C_RESET} $name: 已安装 → $link"
  return 0
}

uninstall_skill() {
  local name="$1"
  local link
  link=$(skill_link_path "$name")

  if [[ ! -L "$link" ]]; then
    warn "$name: 未安装"
    return 0
  fi

  local target
  target=$(readlink "$link")
  if [[ "$target" != "$(skill_source_path "$name")" ]]; then
    warn "$name: $link 不是由本脚本创建的 (→ $target)，跳过"
    return 1
  fi

  rm -f "$link"
  ok "${C_MAGENTA}[Skill]${C_RESET} $name: 已卸载"
  return 0
}

# ══════════════════════════════════════════════
# 子命令
# ══════════════════════════════════════════════

cmd_list() {
  local has_any=false

  # CLI 列表
  local clis
  clis=$(discover_clis)

  if [[ -n "$clis" ]]; then
    has_any=true
    echo ""
    echo "${C_BOLD}📦 CLI 工具:${C_RESET}"
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
    echo "  ${C_DIM}安装路径: $BIN_DIR${C_RESET}"
  fi

  # Skills 列表
  local skills
  skills=$(discover_skills)

  if [[ -n "$skills" ]]; then
    has_any=true
    echo ""
    echo "${C_BOLD}🧩 Skills:${C_RESET}"
    echo ""

    while IFS= read -r name; do
      local status_icon
      if skill_is_installed "$name"; then
        status_icon="${C_GREEN}✓${C_RESET}"
      else
        status_icon="${C_GRAY}○${C_RESET}"
      fi

      local desc
      desc=$(skill_description "$name")

      printf "  %s  ${C_BOLD}%-24s${C_RESET}  %s\n" "$status_icon" "$name" "${C_DIM}${desc}${C_RESET}"
    done <<< "$skills"

    echo ""
    echo "  ${C_DIM}安装路径: $CLAUDE_SKILLS_DIR${C_RESET}"
  fi

  if [[ "$has_any" == false ]]; then
    warn "未发现任何 CLI 工具或 Skills"
    return
  fi

  echo ""
  echo "  安装:     ${C_DIM}./install.sh [name]${C_RESET}"
  echo "  仅 CLI:   ${C_DIM}./install.sh --cli${C_RESET}"
  echo "  仅 Skill: ${C_DIM}./install.sh --skill${C_RESET}"
  echo "  卸载:     ${C_DIM}./install.sh --uninstall [name]${C_RESET}"
  echo ""
}

cmd_install() {
  local target="${1:-}"
  local filter="${2:-}"   # --cli 或 --skill 过滤

  local cli_count=0 cli_failed=0
  local skill_count=0 skill_failed=0
  local installed_any=false

  # 安装指定名称
  if [[ -n "$target" && "$target" != --* ]]; then
    local found=false

    # 尝试作为 CLI 安装
    if [[ "$filter" != "--skill" ]] && [[ -f "$(cli_source_path "$target")" ]]; then
      ensure_bin_dir
      if install_cli "$target"; then
        (( cli_count++ )) || true
      else
        (( cli_failed++ )) || true
      fi
      ensure_path
      found=true
    fi

    # 尝试作为 Skill 安装
    if [[ "$filter" != "--cli" ]] && [[ -d "$(skill_source_path "$target")" ]]; then
      if ensure_claude_skills_dir; then
        if install_skill "$target"; then
          (( skill_count++ )) || true
        else
          (( skill_failed++ )) || true
        fi
      fi
      found=true
    fi

    if [[ "$found" == false ]]; then
      err "未找到: $target"
      echo ""
      echo "可用的 CLI:"
      discover_clis | while IFS= read -r n; do echo "  - $n"; done
      echo "可用的 Skills:"
      discover_skills | while IFS= read -r n; do echo "  - $n"; done
      return 1
    fi

    echo ""
    return 0
  fi

  # 安装所有 CLI
  if [[ "$filter" != "--skill" ]]; then
    local clis
    clis=$(discover_clis)
    if [[ -n "$clis" ]]; then
      ensure_bin_dir
      while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        if install_cli "$name"; then
          (( cli_count++ )) || true
        else
          (( cli_failed++ )) || true
        fi
      done <<< "$clis"
      installed_any=true
    fi
  fi

  # 安装所有 Skills
  if [[ "$filter" != "--cli" ]]; then
    local skills
    skills=$(discover_skills)
    if [[ -n "$skills" ]]; then
      if ensure_claude_skills_dir; then
        while IFS= read -r name; do
          [[ -z "$name" ]] && continue
          if install_skill "$name"; then
            (( skill_count++ )) || true
          else
            (( skill_failed++ )) || true
          fi
        done <<< "$skills"
        installed_any=true
      else
        warn "跳过 Skills 安装（Claude Code 未安装）"
      fi
    fi
  fi

  # PATH 配置（仅在有 CLI 安装时）
  if [[ $cli_count -gt 0 ]]; then
    echo ""
    ensure_path
  fi

  # 汇总
  local total_count=$((cli_count + skill_count))
  local total_failed=$((cli_failed + skill_failed))

  echo ""
  if (( total_count > 0 )); then
    local parts=()
    if (( cli_count > 0 )); then
      parts+=("${cli_count} 个 CLI")
    fi
    if (( skill_count > 0 )); then
      parts+=("${skill_count} 个 Skill")
    fi
    local summary
    summary=$(IFS='、'; echo "${parts[*]}")
    ok "已安装 ${summary}"
  fi
  if (( total_failed > 0 )); then
    warn "${total_failed} 个安装失败或被跳过"
  fi
  if [[ "$installed_any" == false && $total_count -eq 0 ]]; then
    info "没有需要安装的项目"
  fi
}

cmd_uninstall() {
  local target="${1:-}"

  local cli_count=0 skill_count=0

  if [[ -n "$target" ]]; then
    # 卸载指定项
    local found=false

    if cli_is_installed "$target" 2>/dev/null || [[ -f "$(cli_source_path "$target")" ]]; then
      if uninstall_cli "$target"; then
        (( cli_count++ )) || true
      fi
      found=true
    fi

    if skill_is_installed "$target" 2>/dev/null || [[ -d "$(skill_source_path "$target")" ]]; then
      if uninstall_skill "$target"; then
        (( skill_count++ )) || true
      fi
      found=true
    fi

    if [[ "$found" == false ]]; then
      warn "$target: 未安装"
    fi
  else
    # 卸载所有 CLI
    local clis
    clis=$(discover_clis)
    if [[ -n "$clis" ]]; then
      while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        if cli_is_installed "$name" 2>/dev/null; then
          if uninstall_cli "$name"; then
            (( cli_count++ )) || true
          fi
        fi
      done <<< "$clis"
    fi

    # 卸载所有 Skills
    local skills
    skills=$(discover_skills)
    if [[ -n "$skills" ]]; then
      while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        if skill_is_installed "$name" 2>/dev/null; then
          if uninstall_skill "$name"; then
            (( skill_count++ )) || true
          fi
        fi
      done <<< "$skills"
    fi
  fi

  echo ""
  local total=$((cli_count + skill_count))
  if (( total > 0 )); then
    local parts=()
    if (( cli_count > 0 )); then
      parts+=("${cli_count} 个 CLI")
    fi
    if (( skill_count > 0 )); then
      parts+=("${skill_count} 个 Skill")
    fi
    local summary
    summary=$(IFS='、'; echo "${parts[*]}")
    ok "已卸载 ${summary}"
  else
    info "没有需要卸载的项目"
  fi
}

cmd_help() {
  cat << EOF

${C_BOLD}cc-skills install${C_RESET} v${VERSION} — CLI 工具 & Skills 安装器

${C_BOLD}用法:${C_RESET}
  ./install.sh                         安装所有 CLI 和 Skills
  ./install.sh <name>                  安装指定 CLI 或 Skill
  ./install.sh --cli                   仅安装所有 CLI 工具
  ./install.sh --skill                 仅安装所有 Skills
  ./install.sh --list                  列出所有可用项及状态
  ./install.sh --uninstall             卸载所有已安装项
  ./install.sh --uninstall <name>      卸载指定项
  ./install.sh --help                  显示本帮助

${C_BOLD}约定:${C_RESET}
  CLI 工具:   clis/<name>/ 目录，内含同名可执行文件
              安装时在 $BIN_DIR 创建 symlink
  Skills:     skills/<name>/ 目录，内含 SKILL.md
              安装时在 $CLAUDE_SKILLS_DIR 创建 symlink

${C_BOLD}示例:${C_RESET}
  ./install.sh                         ${C_GRAY}# 安装全部${C_RESET}
  ./install.sh --cli                   ${C_GRAY}# 仅安装 CLI 工具${C_RESET}
  ./install.sh --skill                 ${C_GRAY}# 仅安装 Skills${C_RESET}
  ./install.sh memo                    ${C_GRAY}# 安装 memo（CLI 和/或 Skill）${C_RESET}
  ./install.sh --list                  ${C_GRAY}# 查看所有可用项${C_RESET}
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
    --cli)
      shift 2>/dev/null || true
      cmd_install "${1:-}" "--cli"
      ;;
    --skill)
      shift 2>/dev/null || true
      cmd_install "${1:-}" "--skill"
      ;;
    "")
      cmd_install
      ;;
    *)
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
