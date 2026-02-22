#!/usr/bin/env bash
# cwt - Claude Worktree launcher
# Issue番号からworktree+Claude+Playwrightセッションをグリッドペインで一括起動
#
# Usage:
#   cwt <issue-number>...           複数issueのworktree+Claudeセッションを起動
#   cwt list                        アクティブなworktree一覧
#   cwt rm <branch-name>...         worktreeを削除
#   cwt clean                       ブラウザセッションと不要worktreeをクリーンアップ
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

set -euo pipefail

# ---- 設定 ----
USE_GTR=false
MAX_PANES=5

if command -v git-gtr &>/dev/null; then
  USE_GTR=true
fi

# ---- パス解決 ----
# スクリプト自身のパスを取得（シンボリックリンク解決）
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
GITBASH='C:\Program Files\Git\bin\bash.exe'
# wt.exe に渡すランチャーパス（Windows形式）
LAUNCHER_WIN="$(cygpath -w "$SCRIPT_PATH" 2>/dev/null || echo "$SCRIPT_PATH")"

# ============================================================
# --launch モード: 各ペイン内で実行されるランチャー機能
# Usage: cwt --launch <issue_num> <branch_name> <repo_root>
# ============================================================
run_launcher() {
  local issue_num="$1"
  local branch_name="$2"
  local repo_root="$3"

  # ネスト防止: CLAUDECODE 環境変数をクリア
  unset CLAUDECODE 2>/dev/null || true

  # Playwright セッションを設定
  export PLAYWRIGHT_CLI_SESSION="$branch_name"

  # Windows パスを Unix パスに変換（Git Bash 用）
  if command -v cygpath &>/dev/null; then
    repo_root="$(cygpath -u "$repo_root")"
  fi

  cd "$repo_root"

  # worktree ディレクトリ
  local wt_dir="${repo_root}/.worktrees/${branch_name}"

  # worktree が未作成なら作成
  if [ ! -d "$wt_dir" ]; then
    echo "Creating worktree: ${branch_name}..."
    git worktree add "$wt_dir" -b "$branch_name" 2>/dev/null || \
      git worktree add "$wt_dir" "$branch_name" 2>/dev/null || \
      echo "Warning: worktree creation had issues, continuing anyway"
  fi

  # worktree ディレクトリに移動
  if [ -d "$wt_dir" ]; then
    cd "$wt_dir"
    echo "=== Issue #${issue_num} ==="
    echo "=== Worktree: $(pwd) ==="
    echo "=== Branch: ${branch_name} ==="
    echo "=== Playwright Session: ${branch_name} ==="
    echo ""
    claude .
  else
    echo "Error: Failed to create worktree at ${wt_dir}"
    echo "Falling back to main repo..."
    echo "=== Issue #${issue_num} (no worktree) ==="
    echo "=== Playwright Session: ${branch_name} ==="
    echo ""
    claude .
  fi

  # Claude 終了後もシェルを維持
  exec bash
}

# ============================================================
# 通常モード: ヘルパー関数
# ============================================================
print_help() {
  sed -n '2,20s/^# //p' "$SCRIPT_PATH"
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
    sanitized=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | sed 's/^-//;s/-$//' | cut -c1-40)
    echo "issue-${issue_num}-${sanitized}"
  fi
}

# ---- グリッドレイアウトで全ペインを起動 ----
launch_grid() {
  local repo_root win_repo
  repo_root="$(git rev-parse --show-toplevel)"
  win_repo="$(cygpath -w "$repo_root")"

  local -a issues=("$@")
  local n=${#issues[@]}
  local -a branches

  for i in "${!issues[@]}"; do
    branches[$i]="$(make_branch_name "${issues[$i]}")"
    echo "  Issue #${issues[$i]} → ${branches[$i]}"
  done
  echo ""

  # split-pane を実行
  do_sp() {
    local idx=$1
    shift
    local split_args=("$@")
    echo "  [pane $((idx+1))/$n] #${issues[$idx]} (${split_args[*]})"
    wt.exe -w 0 sp "${split_args[@]}" \
      --title "Claude: #${issues[$idx]}" \
      -d "${win_repo}" \
      "${GITBASH}" --login "${LAUNCHER_WIN}" --launch \
      "${issues[$idx]}" "${branches[$idx]}" "${win_repo}"
    sleep 2
  }

  # move-focus を実行
  do_mf() {
    wt.exe -w 0 mf "$1"
    sleep 0.5
  }

  case $n in
    1)
      # [cur | A]
      do_sp 0 -V
      ;;
    2)
      # [cur | A | B]
      do_sp 0 -V -s 0.67
      do_sp 1 -V
      ;;
    3)
      # [cur | A]
      # [B   | C]
      do_sp 1 -H -s 0.5
      do_mf up
      do_sp 0 -V -s 0.5
      do_mf down
      do_sp 2 -V
      ;;
    4)
      # [cur | A    ]
      # [B   | C | D]
      do_sp 1 -H -s 0.5
      do_mf up
      do_sp 0 -V -s 0.5
      do_mf down
      do_sp 2 -V -s 0.67
      do_sp 3 -V
      ;;
    5)
      # [cur | A | B]
      # [C   | D | E]
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

# worktree 一覧表示
list_worktrees() {
  echo "=== Git Worktrees ==="
  if $USE_GTR; then
    git gtr list
  else
    git worktree list
  fi
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

# ============================================================
# メインエントリポイント
# ============================================================
if [ $# -eq 0 ]; then
  print_help
  exit 0
fi

case "$1" in
  --launch)
    # ランチャーモード: 各ペインから呼ばれる
    shift
    run_launcher "$@"
    ;;

  -h|--help|help)
    print_help
    ;;

  list|ls)
    list_worktrees
    ;;

  rm|remove)
    shift
    remove_worktrees "$@"
    ;;

  clean)
    cleanup
    ;;

  *)
    # 引数は全て issue 番号として扱う
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

    echo "=== cwt: ${total} issues → $(( total + 1 )) panes ==="
    echo "Layout: ${layout}"
    echo ""

    args=()
    count=0
    for issue in "$@"; do
      count=$((count + 1))
      if [ "$count" -gt "$MAX_PANES" ]; then break; fi
      args+=("$issue")
    done

    launch_grid "${args[@]}"

    echo ""
    echo "=== All ${#args[@]} sessions launched ==="
    echo "Tips:"
    echo "  cwt list       - 一覧表示"
    echo "  cwt rm <name>  - 削除"
    echo "  cwt clean      - 全クリーンアップ"
    ;;
esac
