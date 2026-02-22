---
description: Worktree + Playwright セッション管理（一覧・作成・削除・確認）
argument-hint: [list|new <issue>|rm <branch>|clean|session]
allowed-tools: Bash(git worktree:*), Bash(git gtr:*), Bash(git branch:*), Bash(git status:*), Bash(gh issue:*), Bash(playwright-cli:*), Bash(cwt:*)
model: haiku
---
# cwt - Worktree + Playwright セッション管理

Git worktree と Playwright CLI セッションの統合管理を行う。

## 引数

- `$ARGUMENTS`:
  - `list` / 引数なし: 現在のworktree一覧 + Playwrightセッション一覧
  - `new <issue-number>`: issue番号からworktree作成
  - `rm <branch-name>`: worktreeとPlaywrightセッションを削除
  - `clean`: 不要なworktree + Playwrightセッションをクリーンアップ
  - `session`: 現在のPlaywrightセッション名を表示

## 実行手順

### list (デフォルト)

```bash
echo "=== Git Worktrees ==="
git worktree list

echo ""
echo "=== Playwright Sessions ==="
playwright-cli list 2>/dev/null || echo "(no active sessions)"

echo ""
echo "=== Active Branches ==="
git branch -a | grep "issue-"
```

### new <issue-number>

1. issue情報を取得
2. ブランチ名を生成（`/bn` と同じ命名規則）
3. `git worktree add` でworktree作成
4. ユーザーに次のステップを案内:
   ```
   次のコマンドで新しいターミナルからClaude+Playwrightセッションを起動:
   PLAYWRIGHT_CLI_SESSION=<branch> claude --worktree <branch>

   または cwt スクリプトで一括起動:
   cwt <issue-number>
   ```

### rm <branch-name>

```bash
# 1. Playwrightセッションを閉じる
playwright-cli -s=<branch-name> close 2>/dev/null || true

# 2. worktreeを削除
git worktree remove <path> --force

# 3. ブランチを削除するか確認
git branch -D <branch-name>  # ユーザー確認後
```

### clean

```bash
# 1. 全Playwrightセッションを閉じる
playwright-cli close-all 2>/dev/null || true

# 2. 不要worktreeをプルーニング
git worktree prune

# 3. 結果を表示
git worktree list
```

### session

現在のClaude Codeセッションで使用中のPlaywrightセッション名を表示:

```bash
echo "PLAYWRIGHT_CLI_SESSION=${PLAYWRIGHT_CLI_SESSION:-"(未設定 - default)"}"
```

## 注意事項

- worktree削除前に未コミット変更がないか確認すること
- `cwt` スクリプトを使えば、issue番号指定だけでworktree作成+Claude起動が可能
