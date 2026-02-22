---
description: playwright-cli使用時のセッション分離ルール
globs:
  - "**/playwright*"
  - "**/.playwright/**"
---

# playwright-cli セッション分離ルール

## セッション決定の優先順位

1. **環境変数 `PLAYWRIGHT_CLI_SESSION`** が設定済み → 自動的に全コマンドに適用されるため `-s=` フラグ不要
2. **環境変数未設定** → 必ず `-s=<name>` フラグを付けること

## 環境変数の確認方法

```bash
echo $PLAYWRIGHT_CLI_SESSION
```

- 値がある場合: そのまま `playwright-cli open ...` でOK（自動適用）
- 空の場合: `-s=<name>` を毎回指定すること

## 理由

`-s=` も `PLAYWRIGHT_CLI_SESSION` も無い状態だと全セッションが `default` ブラウザを共有し、別のClaude Codeセッション（worktree等）が同じブラウザを操作してしまう。

## Worktreeとの連携

`cwt` スクリプトまたは手動で Claude を起動する際に環境変数を設定:

```bash
# cwt スクリプト（推奨）
cwt 42 43 45

# 手動起動
PLAYWRIGHT_CLI_SESSION=issue-42 claude --worktree issue-42
```

## 使用例

```bash
# 環境変数が設定済みの場合（-s= 不要）
playwright-cli open https://example.com
playwright-cli snapshot
playwright-cli close

# 環境変数が未設定の場合（-s= 必須）
playwright-cli -s=feature-auth open https://example.com
playwright-cli -s=feature-auth snapshot
playwright-cli -s=feature-auth close
```
