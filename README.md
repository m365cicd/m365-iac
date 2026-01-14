# m365-iac
Microsoft 365 (Intune / Defender / Exchange / Purview / Entra) を IaC で管理エクスポート適用するためのリポジトリ。

## Structure
- `iac/` : 各ワークロードの設定（定義やエクスポート結果）
- `scripts/common/` : Graph SDK / App-only 認証 / 差分検証 / apply 共通ロジック
- `scripts/devpc/` : 開発PC初期設定などローカル用
- `scripts/cicd/` : CI/CD 用ヘルパー、ユーティリティ
- `.github/workflows/` : validate / export / apply のパイプライン
