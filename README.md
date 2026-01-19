# m365-iac

Microsoft 365（Intune / Defender / Exchange Online / Purview / Entra ID）を **Microsoft Graph PowerShell** で IaC（Infrastructure as Code）化する **自宅ラボ向け**リポジトリです。  
開発PC と CI/CD（GitHub Actions）で **同じ挙動**を再現できるよう、PowerShell 実行環境と Graph SDK の導入を **スクリプトで標準化**します。

> ✅ 目標：**管理者権限なし（User スコープ）**で「状態取得」「差分検出」「バックアップ」を自動化する  
> ✅ 方針：まずは **軽量（Authentication 最小導入）**で始め、必要に応じて拡張

---

## 0. TL;DR（最短セットアップ：開発PC）

> 前提：PowerShell 7 (`pwsh`) が使えること

```powershell
# リポジトリを取得
git clone https://github.com/m365cicd/m365-iac.git
cd m365-iac

# 開発PCセットアップ（Graph PowerShell SDK の最小構成を User スコープに導入）
pwsh -File ./scripts/setup/setup-dev.ps1
```

### 最小構成でできること（重要）
このリポの初期セットアップは **最小構成として `Microsoft.Graph.Authentication` のみ導入**します。  
これだけで以下が利用できます：

- `Connect-MgGraph`（対話認証 / Device Code 認証など）
- `Invoke-MgGraphRequest`（Graph REST API を直接叩ける）

> 🔥 「全部入り SDK を入れなくても Graph を叩ける」＝**軽い / 早い / 管理者権限不要でやりやすい**

---

## 1. 目的（What & Why）

- **What**: Microsoft 365 の構成/状態を **Graph API + PowerShell** でコード化し、再現性・標準化を実現する
- **Why**:
  - GUI 手作業は再現性が低い（差分が追いにくい / 戻しにくい）
  - IaC により「レビュー」「ロールバック」「定期バックアップ」「ドリフト検知」が可能

---

## 2. 用語の整理（混乱しやすいポイント）

### 2.1 Graph API の v1.0 / beta（サーバ側）
- `https://graph.microsoft.com/v1.0/...` → GA（安定）
- `https://graph.microsoft.com/beta/...` → Preview（破壊的変更あり）

> ⚠️ beta は仕様変更・破壊的変更があり得るため、本番依存は非推奨です。

### 2.2 Graph PowerShell SDK の v2（クライアント側）
PowerShell モジュールのバージョンです（例：`Microsoft.Graph.Authentication 2.34.0` の **2.x** など）。  
Graph API の v1.0/beta と **別物**です。

---

## 3. 設計の原則（Design Principles）

- **PowerShell 7（pwsh）前提**
  - Graph PowerShell は PS7 利用が推奨されるため、本リポは PS7 前提で統一します。
- **モジュールは User スコープの固定ディレクトリに保存**
  - 既定の `Documents\PowerShell\Modules` は OneDrive(KFM) 配下になりがちで、再現性や権限面で面倒になることがあります。
  - そのため本リポでは **`%LOCALAPPDATA%\PSModules`** を採用します。
- **最小導入（Authentication only）で始める**
  - “全部入り SDK” は重い（初回ダウンロードが長い）ため、
    最初は `Microsoft.Graph.Authentication` だけを導入し、
    **必要な API は `Invoke-MgGraphRequest` で叩く**方針です。
- **Public リポ前提の安全設計**
  - スクリプトは “導入/パス設定/Import” のみを担い、認証情報は扱いません。
  - シークレットは Git 管理外へ。

---

## 4. 前提条件（Prerequisites）

### 4.1 必須
- Windows 10/11
- PowerShell 7（`pwsh`）
- Git（リポ取得のため）

### 4.2 管理者権限なし（User スコープ）で導入する例（winget）
> ※環境によってはインストーラーが UAC を要求する場合があります。

```powershell
# Git（User スコープ）
winget install --id Git.Git --source winget --scope user

# PowerShell 7（User スコープ）
winget install --id Microsoft.PowerShell --source winget --scope user
```

### 4.3 VS Code（任意）
VS Code は必須ではありません。使いたい人だけどうぞ。

```powershell
winget install --id Microsoft.VisualStudioCode --source winget --scope user
```

VS Code 拡張（任意・例）：

```powershell
code --install-extension MS-CEINTL.vscode-language-pack-ja --force
code --install-extension ms-vscode.PowerShell --force
code --install-extension redhat.vscode-yaml --force
code --install-extension GitHub.vscode-pull-request-github --force
code --install-extension eamodio.gitlens --force
```

---

## 5. ディレクトリ構成（Directory Structure）

```
m365-iac/
├─ iac/                  # Intune / Defender / Exchange / Purview / Entra ID の IaC 定義（JSON/YAML）
├─ scripts/
│  ├─ setup/             # 開発PC/CI向けの環境セットアップ（管理者権限なし前提）
│  │  ├─ setup-graph-sdk.ps1   # Graph PowerShell 最小導入（Authentication）
│  │  ├─ setup-dev.ps1         # 開発PC向け（永続化あり）
│  │  └─ setup-ci.ps1          # CI向け（永続化なし）
│  │
│  ├─ auth/              # 認証（対話型 / アプリ登録型）
│  ├─ assessments/       # 状態確認・監査・ドリフト検知
│  ├─ intune/            # Intune 取得・適用スクリプト
│  ├─ defender/          # Defender 取得・適用スクリプト
│  └─ utils/             # JSON I/O / diff / 共通関数など
│
├─ .github/workflows/    # CI/CD（validate/export/apply）
├─ _logs/                # ログ（Git管理外）
└─ README.md
```

---

## 6. セットアップスクリプト（Scripts Overview）

### 6.1 `scripts/setup/setup-graph-sdk.ps1`（中核）
**やること**
- 保存先 `"%LOCALAPPDATA%\PSModules"` を作成
- `PSModulePath` の **先頭**に追加（セッション）
- （開発PCのみ）`$PROFILE` へ PSModulePath 追記を **永続化**
- `Microsoft.Graph.Authentication` を `Save-Module` で展開
- 確認として `Import-Module Microsoft.Graph.Authentication`

**ポイント**
- “全部入り SDK” は導入しない（まず軽量運用）
- 必要 API は `Invoke-MgGraphRequest` で **/v1.0 と /beta をURLで明示して呼ぶ**

---

### 6.2 `scripts/setup/setup-dev.ps1`（開発PC向け）
- `setup-graph-sdk.ps1` を呼び出し
  - `-PersistProfile`（PSModulePath 永続化）
  - （可能なら）CurrentUser の実行ポリシーを調整

> 実行ポリシー設定が組織ポリシーでブロックされる場合があります。  
> その場合でも `Import-Module` や `Connect-MgGraph` 自体は実行できることがあります（環境に依存）。

---

### 6.3 `scripts/setup/setup-ci.ps1`（CI向け）
- `setup-graph-sdk.ps1` を永続化なしで呼び出します。
- Self-hosted Runner の場合は実行ユーザー固定がオススメです（`%LOCALAPPDATA%` が安定します）。

---

## 7. 認証（Delegated）例：まずは Device Code が安定

WAM（Web Account Manager）による対話認証は、環境によってウィンドウが背面に隠れることがあります。  
**まずは Device Code 認証が安定です。**

```powershell
# 最小構成でもOK（Authenticationだけで動く）
Connect-MgGraph -Scopes "User.Read" -UseDeviceCode
Get-MgContext
```

---

## 8. v1.0 / beta の使い分け（最小構成運用）

最小構成（Authenticationのみ）でも、REST URL を指定すれば呼べます。

```powershell
# v1.0（安定）
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/me"

# beta（プレビュー）
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/me"
```

> 💡 本リポは **「beta をインストールする」という発想ではなく、URLで明示して呼ぶ**方針です。

---

## 9. CI/CD（GitHub Actions）例（最小構成）

```yaml
name: validate
on:
  workflow_dispatch:

jobs:
  validate:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Graph PowerShell (minimal)
        shell: pwsh
        run: pwsh -File ./scripts/setup/setup-ci.ps1

      - name: Validate (example)
        shell: pwsh
        run: |
          # 認証は OIDC / Key Vault / 証明書など、組織ポリシーに沿って実装してください
          # Connect-MgGraph ...
          Write-Host "validate job placeholder"
```

---

## 10. トラブルシューティング（Troubleshooting）

### 10.1 `Connect-MgGraph` が見つからない
- `pwsh`（PowerShell 7）で実行しているか確認
- `PSModulePath` に `%LOCALAPPDATA%\PSModules` が入っているか確認

```powershell
$env:PSModulePath -split ';'
Get-Module -ListAvailable Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Authentication -Force
Get-Command Connect-MgGraph
```

### 10.2 対話認証ウィンドウが出ない
まずは Device Code を使ってください：

```powershell
Connect-MgGraph -Scopes "User.Read" -UseDeviceCode
```

### 10.3 実行ポリシー変更が `Security error` になる
組織ポリシーで制御されている可能性があります。  
このリポは “最小導入” なので、実行ポリシー変更ができなくても運用できる場合があります。

---

## 11. セキュリティ（Security）

- **シークレットをリポに入れない**
  - `*.secret*`, `*.env`, `config.local.ps1` などは Git 管理外
- **ログは `_logs/` に出力（Git管理外）**
- 大容量バイナリ（ISO/VHDX/TS/mp4）はコミット禁止

---

## 12. 免責（Disclaimer）
検証/学習目的の自宅ラボリポジトリです。  
商用運用の可用性・完全性・適合性は保証しません。運用前に十分なテスト・レビューを行ってください。

---

## 13. Refs（公式ドキュメント）
- Install the Microsoft Graph PowerShell SDK  
  https://learn.microsoft.com/ja-jp/powershell/microsoftgraph/installation?view=graph-powershell-1.0
- Invoke-MgGraphRequest（cmdlet reference）  
  https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.authentication/invoke-mggraphrequest?view=graph-powershell-1.0
- Microsoft Graph REST API overview（v1.0 / beta の説明）  
  https://learn.microsoft.com/en-us/graph/api/overview?view=graph-rest-1.0
- Upgrade to Microsoft Graph PowerShell SDK v2, now generally available  
  https://devblogs.microsoft.com/microsoft365dev/upgrade-to-microsoft-graph-powershell-sdk-v2-now-generally-available/
- Connect to Microsoft 365 with Microsoft Graph PowerShell（日本語）  
  https://learn.microsoft.com/ja-jp/microsoft-365/enterprise/connect-to-microsoft-365-powershell?view=o365-worldwide
