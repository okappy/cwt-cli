#!/usr/bin/env bash
# cwt - Claude Worktree launcher
# Issue番号からworktree+Claude+Playwrightセッションをグリッドペインで一括起動
#
# Usage:
#   cwt <issue-number>...           複数issueのworktree+Claudeセッションを起動
#   cwt list                        アクティブなworktree一覧（ポート情報付き）
#   cwt rm <branch-name>...         worktreeを削除
#   cwt clean                       ブラウザセッションと不要worktreeをクリーンアップ
#   cwt ports                       現在のworktreeのポート情報を表示
#
# Grid layouts (current pane = top-left control):
#   N=1: [cur | A]                    1x2
#   N=2: [cur | A | B]               1x3
#   N=3: [cur | A] / [B | C]         2x2
#   N=4: [cur | A] / [B | C | D]     top2 + bottom3
#   N=5: [cur | A | B] / [C | D | E] 3x2
#
# 例:
#   cwt 42 43 45                    3つのissueを並列開発
#   cwt list                        現在のworktree確認
#   cwt rm issue-42 issue-43        完了したworktreeを削除
#   cwt clean                       全クリーンアップ
#   cwt ports                       現在のworktreeのポート確認

set -euo pipefail

# ---- 設定 ----
USE_GTR=false
MAX_PANES=5

if command -v git-gtr &>/dev/null; then
  USE_GTR=true
fi

# ---- 環境検出 ----
if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
  CWT_ENV="wsl"
elif [ -n "${MSYSTEM:-}" ] || [ -n "${MINGW_PREFIX:-}" ]; then
  CWT_ENV="gitbash"
else
  CWT_ENV="other"
fi

to_win_path() {
  case "$CWT_ENV" in
  wsl) wslpath -w "$1" ;;
  gitbash) cygpath -w "$1" ;;
  *) echo "$1" ;;
  esac
}

to_unix_path() {
  case "$CWT_ENV" in
  wsl) wslpath -u "$1" ;;
  gitbash) cygpath -u "$1" ;;
  *) echo "$1" ;;
  esac
}

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
LAUNCHER_WIN="$(to_win_path "$SCRIPT_PATH")"

case "$CWT_ENV" in
wsl)
  PANE_SHELL="wsl.exe"
  PANE_SHELL_ARGS=("--cd" "~")
  ;;
gitbash)
  PANE_SHELL='C:\Program Files\Git\bin\bash.exe'
  PANE_SHELL_ARGS=("--login")
  ;;
*)
  PANE_SHELL="bash"
  PANE_SHELL_ARGS=()
  ;;
esac

# ============================================================
# ポート管理
# ============================================================

PORT_SCAN_FILES=(
  ".env.example" ".env.sample" ".env.template" ".env"
  "docker-compose.yml" "docker-compose.yaml" "docker-compose.override.yml"
  "Makefile" "package.json" "pyproject.toml" "setup.cfg"
  "config.yml" "config.yaml" "app.yml" "app.yaml"
  "README.md" "CLAUDE.md"
)

detect_ports() {
  local root="$1"
  declare -A seen=()
  local results=()
  for fname in "${PORT_SCAN_FILES[@]}"; do
    local fpath="$root/$fname"
    [ -f "$fpath" ] || continue
    while IFS= read -r port; do
      [[ "$port" =~ ^[0-9]+$ ]] || continue
      ((port >= 1024 && port <= 65535)) || continue
      [[ -z "${seen[$port]+x}" ]] || continue
      seen[$port]=1
      results+=("$port")
    done < <(grep -oP '(?i)(?:port\s+|PORT[S_A-Z0-9]*\s*[:=]\s*|:\s*|EXPOSE\s+|listen\s+)(\d{4,5})\b' \
      "$fpath" 2>/dev/null | grep -oP '\d{4,5}' || true)
  done
  printf '%s\n' "${results[@]}"
}

find_free_port() {
  for port in $(shuf -i 50000-60000); do
    if command -v ss &>/dev/null; then
      ss -tln 2>/dev/null | grep -qE ":${port}\b" || {
        echo "$port"
        return 0
      }
    else
      netstat -tln 2>/dev/null | grep -qE ":${port}\b" || {
        echo "$port"
        return 0
      }
    fi
  done
  echo "ERROR: no free port" >&2
  return 1
}

find_free_ports() {
  local count="$1"
  local -a used=() ports=()
  for ((i = 0; i < count; i++)); do
    local port
    while true; do
      port=$(find_free_port) || {
        echo "ERROR: ポート確保に失敗" >&2
        return 1
      }
      local dup=false
      for u in "${used[@]:-}"; do [[ "$u" == "$port" ]] && {
        dup=true
        break
      }; done
      $dup || break
    done
    ports+=("$port")
    used+=("$port")
  done
  printf '%s\n' "${ports[@]}"
}

read_port_keys() {
  grep -oP '(?<=^PORT_KEYS=).*' "$1" 2>/dev/null || true
}

write_cwt_template() {
  local cwt="$1"
  shift
  local keys_str
  keys_str=$(
    IFS=','
    echo "$*"
  )
  {
    echo "# CWT Port Template - $(date '+%Y-%m-%d %H:%M:%S')"
    echo "# アプリが使用するTCPポートの種類を定義します。"
    echo "# cwt でworktreeを作成すると各worktreeに50000-60000のポートが自動割り当てられます。"
    echo "#"
    echo "PORT_KEYS=${keys_str}"
  } >"$cwt"
  echo "✅ .cwt テンプレートを保存: $cwt"
}

write_cwt_worktree() {
  local cwt_path="$1" branch="$2"
  shift 2
  local pairs=("$@")
  {
    echo "# CWT Port Configuration - ${branch}"
    echo "# アプリ起動時は必ずこのファイルのポートを使用してください。"
    echo "# 使い方: source .cwt && npm run dev -- --port \$PORT_3000"
    echo "#"
    echo "# WARNING: このポートはworktreeごとに固有です。デフォルトポートを使うと競合します。"
    echo "#"
  } >"$cwt_path"
  local i=0
  while ((i < ${#pairs[@]})); do
    echo "PORT_${pairs[$i]}=${pairs[$((i + 1))]}" >>"$cwt_path"
    ((i += 2))
  done
  echo "" >>"$cwt_path"
  echo "# 割り当て: $(date '+%Y-%m-%d %H:%M:%S')" >>"$cwt_path"
}

scan_and_confirm() {
  local root="$1"
  local -a found=()
  found=($(detect_ports "$root"))
  echo "" >&2
  echo "🔍 スキャン結果:" >&2
  if [ ${#found[@]} -eq 0 ]; then
    echo "  （検出なし）" >&2
  else
    for p in "${found[@]}"; do echo "  PORT_${p}" >&2; done
  fi
  echo "" >&2
  if [ ${#found[@]} -gt 0 ]; then
    printf "この結果を適用しますか？ [Y=適用 / n=手動入力]: " >&2
    read -r ans </dev/tty
    if [[ "$ans" =~ ^[Nn] ]]; then
      printf "ポートをカンマ区切りで入力: " >&2
      read -r manual </dev/tty
      IFS=',' read -ra found <<<"$manual"
    fi
  fi
  printf '%s\n' "${found[@]}"
}

resolve_port_keys() {
  local root="$1"
  local cwt="$root/.cwt"
  local -a port_keys=()
  if [ -f "$cwt" ]; then
    echo "" >&2
    echo "──────────────────────────────────────────" >&2
    echo "📄 既存の .cwt テンプレートが見つかりました:" >&2
    echo "──────────────────────────────────────────" >&2
    cat "$cwt" >&2
    echo "──────────────────────────────────────────" >&2
    local keys_str
    keys_str=$(read_port_keys "$cwt")
    if [ -n "$keys_str" ]; then
      printf "\nそのまま使用しますか？ [Y=そのまま / n=再スキャン]: " >&2
      read -r ans </dev/tty
      if [[ "$ans" =~ ^[Nn] ]]; then
        port_keys=($(scan_and_confirm "$root"))
      else
        IFS=',' read -ra port_keys <<<"$keys_str"
      fi
    else
      echo "⚠️  PORT_KEYS が未定義。スキャンします。" >&2
      port_keys=($(scan_and_confirm "$root"))
    fi
  else
    port_keys=($(scan_and_confirm "$root"))
  fi
  if [ ${#port_keys[@]} -eq 0 ]; then
    printf "⚠️  ポートが検出できませんでした。カンマ区切りで入力: " >&2
    read -r manual </dev/tty
    IFS=',' read -ra port_keys <<<"$manual"
  fi
  write_cwt_template "$cwt" "${port_keys[@]}" >&2
  printf '%s\n' "${port_keys[@]}"
}

# ============================================================
# --launch モード: 各ペイン内で実行されるランチャー機能
# ============================================================
run_launcher() {
  local issue_num="$1"
  local branch_name="$2"
  local repo_root="$3"

  unset CLAUDECODE 2>/dev/null || true

  export PLAYWRIGHT_CLI_SESSION="$branch_name"

  repo_root="$(to_unix_path "$repo_root")"
  cd "$repo_root"

  local wt_dir="${repo_root}/.worktrees/${branch_name}"

  if [ ! -d "$wt_dir" ]; then
    echo "Creating worktree: ${branch_name}..."
    git worktree add "$wt_dir" -b "$branch_name" 2>/dev/null ||
      git worktree add "$wt_dir" "$branch_name" 2>/dev/null ||
      echo "Warning: worktree creation had issues, continuing anyway"
  fi

  if [ -d "$wt_dir" ]; then
    cd "$wt_dir"
    echo "=== Issue #${issue_num} ==="
    echo "=== Worktree: $(pwd) ==="
    echo "=== Branch: ${branch_name} ==="
    echo "=== Playwright Session: ${branch_name} ==="

    if [ -f ".cwt" ] && grep -q '^PORT_[0-9]' ".cwt"; then
      echo "=== Ports ==="
      grep '^PORT_[0-9]' .cwt | sed 's/^/   /'
      while IFS='=' read -r key val; do
        export "$key=$val"
      done < <(grep '^PORT_[0-9]' .cwt)
    fi
    echo ""
    claude .
  else
    echo "Error: Failed to create worktree at ${wt_dir}"
    echo "Falling back to main repo..."
    echo "=== Issue #${issue_num} (no worktree) ==="
    echo ""
    claude .
  fi

  exec bash
}

# ============================================================
# 通常モード: ヘルパー関数
# ============================================================
print_help() {
  sed -n '2,21s/^# //p' "$SCRIPT_PATH"
}

get_repo() {
  git remote get-url origin 2>/dev/null | sed 's/\.git$//' | grep -oE '[^/]+/[^/]+$'
}

make_branch_name() {
  local issue_num="$1"
  local repo
  repo="$(get_repo)"

  local title
  title=$(gh issue view "$issue_num" -R "$repo" --json title -q .title 2>/dev/null || echo "")

  if [ -z "$title" ]; then
    echo "issue-${issue_num}"
    return
  fi

  if echo "$title" | grep -qP '[^\x00-\x7F]'; then
    echo "issue-${issue_num}"
  else
    local sanitized
    sanitized=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' |
      sed 's/-\+/-/g' | sed 's/^-//;s/-$//' | cut -c1-40)
    echo "issue-${issue_num}-${sanitized}"
  fi
}

# ---- グリッドレイアウトで全ペインを起動（ポート割り当て付き） ----
launch_grid() {
  local repo_root win_repo
  repo_root="$(git rev-parse --show-toplevel)"
  win_repo="$(to_win_path "$repo_root")"

  local -a issues=("$@")
  local n=${#issues[@]}
  local -a branches

  # ─── ポート種類を確定（1回だけ） ───
  echo "🔎 ポート種類を確認中..."
  local -a port_keys=()
  while IFS= read -r k; do port_keys+=("$k"); done \
    < <(resolve_port_keys "$repo_root")

  local num_keys=${#port_keys[@]}
  if ((num_keys > 0)); then
    echo "📋 ポート割り当て: ${n} worktrees × ${num_keys} ports = $((n * num_keys)) 個確保"
  else
    echo "⚠️  ポート種類が未定義。ポートなしで起動します。"
  fi

  # ─── worktree名を決定 ───
  echo ""
  for i in "${!issues[@]}"; do
    branches[$i]="$(make_branch_name "${issues[$i]}")"
    echo "  Issue #${issues[$i]} → ${branches[$i]}"
  done
  echo ""

  # ─── 全ポートを一括確保 ───
  local -a all_ports=()
  if ((num_keys > 0)); then
    echo "🔒 空きポートを確保中..."
    while IFS= read -r p; do all_ports+=("$p"); done \
      < <(find_free_ports $((n * num_keys)))
    echo "   確保: ${all_ports[*]}"
    echo ""
  fi

  # ─── 各worktreeを作成して.cwtを書き込み ───
  local port_idx=0
  for i in "${!issues[@]}"; do
    local branch="${branches[$i]}"
    local wt_dir="${repo_root}/.worktrees/${branch}"

    if [ ! -d "$wt_dir" ]; then
      git -C "$repo_root" worktree add "$wt_dir" -b "$branch" 2>/dev/null ||
        git -C "$repo_root" worktree add "$wt_dir" "$branch" 2>/dev/null ||
        echo "⚠️  worktree作成に問題: $branch"
    fi

    if ((num_keys > 0)) && [ -d "$wt_dir" ]; then
      local pairs=()
      for key in "${port_keys[@]}"; do
        pairs+=("$key" "${all_ports[$port_idx]}")
        echo "  ${branch}: PORT_${key} → ${all_ports[$port_idx]}"
        ((port_idx++))
      done
      write_cwt_worktree "${wt_dir}/.cwt" "$branch" "${pairs[@]}"
    fi
  done
  echo ""

  # ─── Windows Terminal グリッド起動 ───
  do_sp() {
    local idx=$1
    shift
    local split_args=("$@")
    echo "  [pane $((idx + 1))/$n] #${issues[$idx]} (${split_args[*]})"
    wt.exe -w 0 sp "${split_args[@]}" \
      --title "Claude: #${issues[$idx]}" \
      -d "${win_repo}" \
      "${PANE_SHELL}" "${PANE_SHELL_ARGS[@]}" "${LAUNCHER_WIN}" --launch \
      "${issues[$idx]}" "${branches[$idx]}" "${win_repo}"
    sleep 2
  }

  do_mf() {
    wt.exe -w 0 mf "$1"
    sleep 0.5
  }

  case $n in
  1)
    do_sp 0 -V
    ;;
  2)
    do_sp 0 -V -s 0.67
    do_sp 1 -V
    ;;
  3)
    do_sp 1 -H -s 0.5
    do_mf up
    do_sp 0 -V -s 0.5
    do_mf down
    do_sp 2 -V
    ;;
  4)
    do_sp 1 -H -s 0.5
    do_mf up
    do_sp 0 -V -s 0.5
    do_mf down
    do_sp 2 -V -s 0.67
    do_sp 3 -V
    ;;
  5)
    do_sp 2 -H -s 0.5
    do_mf up
    do_sp 0 -V -s 0.67
    do_sp 1 -V
    do_mf down
    do_sp 3 -V -s 0.67
    do_sp 4 -V
    ;;
  esac
}

# worktree 一覧表示（ポート情報付き）
list_worktrees() {
  echo "=== Git Worktrees ==="
  if $USE_GTR; then
    git gtr list
  else
    git worktree list
  fi

  echo ""
  echo "=== Port Assignments ==="
  local found_any=false
  while IFS= read -r line; do
    local wt_path
    wt_path=$(echo "$line" | awk '{print $1}')
    local cwt="${wt_path}/.cwt"
    if [ -f "$cwt" ] && grep -q '^PORT_[0-9]' "$cwt"; then
      found_any=true
      echo "  📝 $(basename "$wt_path"):"
      grep '^PORT_[0-9]' "$cwt" | sed 's/^/     /'
    fi
  done < <(git worktree list | tail -n +2)
  $found_any || echo "  （ポート割り当てなし）"

  echo ""
  echo "=== Playwright CLI Sessions ==="
  playwright-cli list 2>/dev/null || echo "  (no active sessions)"
}

# worktree 削除
remove_worktrees() {
  for branch in "$@"; do
    echo "Removing worktree: ${branch}..."
    playwright-cli -s="$branch" close 2>/dev/null || true

    if $USE_GTR; then
      git gtr rm "$branch" --delete-branch --yes 2>/dev/null || true
    else
      local repo_root
      repo_root="$(git rev-parse --show-toplevel)"
      local wt_path="${repo_root}/.worktrees/${branch}"
      if [ -d "$wt_path" ]; then
        git worktree remove "$wt_path" --force 2>/dev/null || true
      fi
      git branch -D "$branch" 2>/dev/null || true
    fi
    echo "  Done."
  done
}

# クリーンアップ
cleanup() {
  echo "=== Cleaning up ==="
  echo "Closing all playwright sessions..."
  playwright-cli close-all 2>/dev/null || true

  if $USE_GTR; then
    echo "Cleaning merged worktrees..."
    git gtr clean --merged --yes 2>/dev/null || true
  fi

  echo "Pruning stale worktrees..."
  git worktree prune
  echo "Done."
}

# 現在のworktreeのポート情報表示
show_ports() {
  if [ -f ".cwt" ]; then
    echo "=== Port Configuration ($(basename "$(pwd)")) ==="
    cat .cwt
  else
    echo "⚠️  .cwt ファイルが見つかりません（このworktreeにはポートが未割り当てです）"
  fi
}

# ============================================================
# メインエントリポイント
# ============================================================
if [ $# -eq 0 ]; then
  print_help
  exit 0
fi

case "$1" in
--launch)
  shift
  run_launcher "$@"
  ;;

-h | --help | help)
  print_help
  ;;

list | ls)
  list_worktrees
  ;;

rm | remove)
  shift
  remove_worktrees "$@"
  ;;

clean)
  cleanup
  ;;

ports)
  show_ports
  ;;

*)
  for issue in "$@"; do
    if ! [[ "$issue" =~ ^[0-9]+$ ]]; then
      echo "Error: '$issue' is not a valid issue number."
      echo "Usage: cwt <issue-number>..."
      exit 1
    fi
  done

  total=$#
  if [ "$total" -gt "$MAX_PANES" ]; then
    echo "Warning: Max ${MAX_PANES} panes. Only first ${MAX_PANES} issues will be launched."
    total=$MAX_PANES
  fi

  case $total in
  1) layout="[cur | A]" ;;
  2) layout="[cur | A | B]" ;;
  3) layout="[cur | A] / [B | C]" ;;
  4) layout="[cur | A] / [B | C | D]" ;;
  5) layout="[cur | A | B] / [C | D | E]" ;;
  esac

  echo "=== cwt: ${total} issues → $((total + 1)) panes ==="
  echo "Layout: ${layout}"
  echo ""

  args=()
  count=0
  for issue in "$@"; do
    count=$((count + 1))
    [ "$count" -gt "$MAX_PANES" ] && break
    args+=("$issue")
  done

  launch_grid "${args[@]}"

  echo ""
  echo "=== All ${#args[@]} sessions launched ==="
  echo "Tips:"
  echo "  cwt list       - 一覧表示（ポート情報付き）"
  echo "  cwt ports      - 現在のworktreeのポート確認"
  echo "  cwt rm <n>     - 削除"
  echo "  cwt clean      - 全クリーンアップ"
  ;;
esac
