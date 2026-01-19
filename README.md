# m365-iac

Microsoft 365（Intune / Defender / Exchange Online / Purview / Entra ID）を **Microsoft Graph PowerShell** で IaC（Infrastructure as Code）化する自宅ラボ用リポジトリです。  
開発 PC と CI/CD（GitHub Actions）で **同じ挙動**を再現できるよう、PowerShell 実行環境と Graph SDK の導入を **スクリプトで標準化**しています。

---

## 0. TL;DR（最短セットアップ：新規開発PC）

> 前提：**Git** と **PowerShell 7 (pwsh)** が既にインストールされていること

```powershell
# リポジトリを取得
git clone https://github.com/m365cicd/m365-iac.git
cd m365-iac

# 開発PCセットアップ（既定：GA を利用できる状態で開始）
pwsh -File ./scripts/setup/setup-dev.ps1
```

> ※ Beta（Microsoft.Graph.Beta）も **同時にインストール**されます。  
>   使う/使わないの切り替えは、各セッションで Import を切り替えてください（詳細はスクリプトヘッダー参照）。

---

## 1. 目的（What & Why）

- **What**: Microsoft 365 構成を **Graph API + PowerShell（Graph SDK）** でコード管理し、再現性・標準化を実現する  
- **Why**:
  - 手作業の GUI 設定は再現性が低く、差分の見える化/追跡が難しい
  - IaC により「レビュー」「ロールバック」「自動適用」「ラボ再構築」を効率化

---

## 2. 設計の原則（Design Principles）

- **PowerShell 7（pwsh）前提**  
  - **Microsoft Graph PowerShell SDK の推奨が PowerShell 7** であるため、本リポは PS7 を必須前提に統一しています。  
  - なお **Windows 11 / Windows Server 2025 の標準搭載は Windows PowerShell 5.1** です（互換性のため残っていますが、本リポの対象外）。PS7 を別途導入して利用してください。
- **Graph SDK は GA + Beta を併存導入**  
  既定は GA（Microsoft.Graph）を利用できる状態で開始します。**Beta（Microsoft.Graph.Beta）も同時にインストール**しておき、最新 API 検証が必要な場面だけセッションで Import を切り替える運用を想定しています。
- **モジュール保存先はユーザースコープの固定ディレクトリ**  
  `**%LOCALAPPDATA%\PSModules**` を採用（OneDrive/KFM 影響回避・権限不足の回避・再現性の確保）
- **Public リポ前提の安全性**  
  スクリプトは “導入/パス設定/Import” のみを担い、認証情報は扱わない（認証はワークフローや別スクリプトで実行）

---

## 3. 前提条件（Prerequisites）

- **PowerShell 7 (pwsh)** と **Git** が導入済であること

- **（参考）PowerShell 5.1 からの導入手順（管理者権限不要）**

```powershell
# 1. Git のインストール
winget install --id Git.Git --source winget --scope user

# 2. PowerShell 7 (最新安定版) のインストール
winget install --id Microsoft.PowerShell --source winget --scope user

# 3. VS Code のインストール
winget install --id Microsoft.VisualStudioCode --source winget --scope user

# 4. VS Code 拡張機能のインストール
‌code --install-extension MS-CEINTL.vscode-language-pack-ja --force
code --install-extension ms-vscode.PowerShell --force
code --install-extension redhat.vscode-yaml --force
code --install-extension GitHub.vscode-pull-request-github --force
code --install-extension eamodio.gitlens --force
```

---

## 4. ディレクトリ構成（Directory Structure）

```
m365-iac/
├─ iac/                  # Intune / Defender / Exchange / Purview / Entra ID の IaC 定義（JSON/YAML）
├─ scripts/
│  ├─ setup/              # 開発PC/CI向けの環境セットアップ（管理者権限なし前提）
│  │  ├─ setup-graph-sdk.ps1      # Graph SDK導入（GA/Beta 併存など）
│  │  ├─ setup-dev.ps1            # 開発PC向けセットアップ（ユーザースコープ）
│  │  └─ setup-ci.ps1             # CI向けセットアップ（GitHub Actions想定）
│  │
│  ├─ auth/               # 認証（対話型 / アプリ登録型）
│  ├─ assessments/        # 状態確認・監査・ドリフト検知
│  ├─ intune/             # Intune 取得・適用スクリプト
│  ├─ defender/           # Defender 取得・適用スクリプト
│  └─ utils/              # JSON I/O / diff / 共通関数など
│
├─ .github/workflows/     # CI/CD（validate/export/apply）
├─ _logs/                 # ログ（Git管理外）
└─ README.md
```

---

## 5. スクリプトの役割（Scripts Overview）

### 5.1 `scripts/setup/setup-graph-sdk.ps1`（中核）

- **何をするか**
  - 保存先 `**%LOCALAPPDATA%\PSModules**` を作成  
  - `PSModulePath` の **先頭**に追加（**セッション**＋**User 永続**）  
  - **PSGallery** を Trusted 化、**NuGet Provider** の準備  
  - **Graph SDK（GA + Beta）** を `Save-Module` で保存（Install-Module は使用しない）  
  - 既定で **GA** を Import（**Beta も同時にインストール**されます）

- **なぜそうするか（要点）**
  - OneDrive/KFM 配下になりがちな **`Documents\PowerShell\Modules`** を避ける  
  - **ユーザースコープ**で権限不足になりにくく、ラボ再構築が容易  
  - GA を既定にして保守性/安定性を担保。**Beta は “インストール済み” にしておき、必要なときにだけ使う**

- **主なパラメータ**
  - `-ModulesRoot`（既定: `%LOCALAPPDATA%\PSModules`）  
  - `-GraphRequiredVersion`（GA の固定バージョン）  
  - `-PersistProfile`（開発PC向け：`$PROFILE` に PSModulePath を永続化）  
  - `-SetExecutionPolicy`（開発PC向け：CurrentUser=RemoteSigned）

> 詳細はスクリプト先頭のコメントベースヘルプを参照。

---

### 5.2 `scripts/setup/setup-dev.ps1`（開発 PC ラッパー）

- **前提**：PowerShell 7（pwsh）必須  
- **内容**：共通スクリプトを **`-PersistProfile -SetExecutionPolicy` 付き**で呼び出して初期導入  
  （`PSModulePath` の永続化と実行ポリシー設定を実施）  
- **例**：
```powershell
# 既定（GA を利用できる状態で開始。Beta もインストール済）
pwsh -File ./scripts/devpc/setup-dev.ps1

# GA のバージョンを固定して導入
pwsh -File ./scripts/devpc/setup-dev.ps1 -GraphRequiredVersion 2.28.0
```

---

### 5.3 `scripts/setup/setup-ci.ps1`（CI/CD ラッパー）

- **内容**：共通スクリプトを **永続化なし**で呼び出して初期導入  
  （既定は GA。**Beta も同時にインストール**されます）
- **注意**：Self-hosted Agent は **実行ユーザー固定**を推奨（`%LOCALAPPDATA%` の安定化）
- **例（ジョブ内）**：
```powershell
pwsh -File ./scripts/setup/setup-ci.ps1
```

---

## 6. CI/CD（GitHub Actions）の例

```yaml
name: validate
on:
  workflow_dispatch:

jobs:
  validate:
    runs-on: windows-latest

    steps:
      - uses: actions/checkout@v4

      # （任意）モジュールキャッシュ：Self-hosted では実行ユーザーに合わせてパスを調整
      - uses: actions/cache@v4
        with:
          path: ${{ env.LOCALAPPDATA }}\PSModules
          key: psmodules-${{ runner.os }}

      - name: Setup Graph SDK (GA default, Beta also installed)
        shell: pwsh
        run: pwsh -File ./scripts/setup/setup-ci.ps1

      - name: Connect and validate
        shell: pwsh
        run: |
          # 認証は OIDC / Key Vault 等、貴社ポリシーに沿って実装（このリポでは扱いません）
          # Connect-MgGraph -Scopes "User.Read.All","Group.Read.All"
          pwsh -File ./scripts/common/validate.ps1 -WhatIf
```

> 認証（Connect-MgGraph 等）は **このリポのスクリプトでは扱いません**。パイプライン側で OIDC などの方式を採用してください。

---

## 7. セキュリティ & 運用ポリシー（Security / Ops）

- **リポジトリにシークレットを含めない**  
  `config.local.ps1`, `*.secret*`, `*.env` などは Git 管理外に  
- **調査・検証時の一時ログは `_logs/` に出力します（Git 管理外）**
- **証明書/Thumbprint/アプリ登録などの機微情報は外出し**  
  - 開発PC：CurrentUser 証明書ストアを参照  
  - CI/CD：OIDC フェデレーションや Key Vault を利用  
- **大容量バイナリ（ISO/VHDX など）はコミット禁止**

---

## 8. トラブルシューティング（Troubleshooting）

- **`Import-Module Microsoft.Graph` に失敗する**  
  - `pwsh` で実行しているか確認（PS7 必須）  
  - `PSModulePath` に `%LOCALAPPDATA%\PSModules` が先頭で入っているか  
  - `scripts/setup/setup-graph-sdk.ps1` を単体で実行し、ログを確認
- **Beta のコマンドが見つからない**  
  - Beta も **インストール済み** です。セッションで必要なら `Import-Module Microsoft.Graph.Beta` を実行
- **CI で同じユーザーでもパスが変わる**  
  - ランナーの実行ユーザーを固定しているか確認  
  - `Write-Host $env:LOCALAPPDATA` で実体を確認し、`actions/cache` の `path` を合わせる

---

## 9. よくある質問（FAQ）

**Q. なぜ `Install-Module` ではなく `Save-Module`？**  
A. `Install-Module -Scope CurrentUser` は保存先が `Documents\PowerShell\Modules` に固定され、**OneDrive/KFM の影響**を受けやすいです。任意ディレクトリ（`%LOCALAPPDATA%\PSModules`）に直接展開するため `Save-Module` を採用しています。

**Q. 既定を GA にしている理由は？**  
A. **保守性と安定性**を最優先するためです。**Beta もインストール**はされますが、最新 API が必要な用途に限って Import して使います。

**Q. PS7 必須なの？**  
A. はい。本リポは **PowerShell 7 前提**で統一しています（WinPS 5.1 は対象外）。  
   なお **Win11/Windows Server 2025 に標準搭載されるのは 5.1** です。別途 PS7 を導入して利用してください。

---

## 10. 免責（Disclaimer）

検証/学習目的のリポジトリです。商用運用の可用性・完全性・適合性は保証しません。運用前に十分なテスト・レビュー・リスク評価を行ってください。
