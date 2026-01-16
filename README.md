# m365-iac

自宅ラボ用のリポジトリです。  
この README は **開発PC・CI/CD の環境構築手順と、リポジトリ運用要件の説明**を含みます。  
目的は、Microsoft 365（Intune / Defender / Exchange Online / Purview / Entra ID）の設定を  
**Graph API + PowerShell**で IaC 化して検証・学習することです（公開リポ・機密は含めない）。

---

# 🧪 Lab Environment（前提構成）

- **Microsoft 365 Business Premium（1ユーザー）**
- **Entra Suite（トライアル）**
  - Entra Private Access（ZTNA）検証
  - Global Secure Access のトラフィック分析
- **Windows Server 評価版（コネクタサーバ）**
- **Microsoft Defender for Business servers 追加**
  - MDE を導入して検証
- **ホスト**：Win11 Pro の Hyper-V で Windows Server 2025 を稼働予定

---

# 🔒 Security（絶対ルール）

- **秘密情報はリポジトリに含めない**
- `config.local.ps1` は Git 未管理（`.gitignore`）
- 開発PC：証明書ストア（CurrentUser\My）の Thumbprint を参照  
- CI/CD：GitHub Actions OIDC → Entra → Key Vault で実行時のみ取得
- 巨大バイナリ（ISO/VHDXなど）はコミット禁止

---

# 🆕 環境セットアップ（PowerShell / Graph SDK）— 本リポで共通化した要件

このリポジトリでは以下の要件で **開発PCと CI/CD の PowerShell 実行環境を統一**します。

## ✔ 要件まとめ
- **Microsoft Graph SDK を IaC で使用するための初期設定を共通化**
- **OneDrive/KFM の影響を避けるため**、モジュール保存先は必ず `C:\PSModules` を使う
- **PSGallery を Trusted に設定**
- **実行ポリシー(CurrentUser) = RemoteSigned**
- **PowerShell 7** を利用（開発PC・CI/CD 共通）
- スクリプトは GitHub に置き、**どの開発PCでも git pull → 1コマンドで環境再現**
- 開発PCと CI の差分は **ラッパースクリプト（devpc / cicd）で吸収**
- Graph SDK のバージョンは、開発PC：最新/任意、CI/CD：必要に応じ固定

---

# 🆕 スクリプト構成（環境セットアップ周り）

```
scripts/
├─ common/
│   └─ setup-graph-sdk.ps1        ← 開発PC・CI の共通ロジック
├─ devpc/
│   └─ setup-dev.ps1              ← 開発PC用ラッパー（PS7 導入 → 共通呼び出し）
└─ cicd/
    └─ setup-ci.ps1               ← CI/CD 用ラッパー（永続化なし → 共通呼び出し）
```

---

# 🆕 開発PCでのセットアップ手順

## ✔ 初回のみ（PowerShell 7 + Graph SDK セットアップ）

```powershell
pwsh -File ./scripts/devpc/setup-dev.ps1
```

Graph のバージョンを固定したい場合：

```powershell
pwsh -File ./scripts/devpc/setup-dev.ps1 -GraphRequiredVersion 2.28.0
```

### 📌 これで行われること
- PowerShell 7 が未インストールなら winget で自動導入
- `C:\PSModules` を作成して PSModulePath の先頭へ設定
- PSGallery を Trusted 化
- 実行ポリシー(CurrentUser) を RemoteSigned
- Microsoft.Graph（任意バージョン）を CurrentUser に install
- PSModulePath の永続化（$PROFILE）

---

# 🆕 別のPCで再現したいとき

```powershell
git clone <this-repo-url>
cd m365-iac
pwsh -File ./scripts/devpc/setup-dev.ps1
```

※どの PC でもこの 1 コマンドで同じ開発環境ができる。

---

# 🆕 CI/CD（GitHub Actions）でのセットアップ

`.github/workflows/` の任意のジョブ内で実行：

```yaml
- name: Setup Graph SDK
  shell: pwsh
  run: ./scripts/cicd/setup-ci.ps1
```

### 📌 実行内容（CI）
- `C:\PSModules` をジョブ内だけ PSModulePath に追加  
- PSGallery を Trusted  
- Microsoft.Graph を CurrentUser にインストール  
- 永続化・実行ポリシー変更は **行わない**（ジョブなので不要）

### 📌 おすすめ：モジュールキャッシュ

```yaml
- uses: actions/cache@v4
  with:
    path: C:\PSModules
    key: psmodules-${{ runner.os }}-graph
```

---

# 🛠 使い方（IaC 基本手順）

1. `config.local.ps1` を作る（Git 未管理）
2. 必要な環境変数を定義
3. 共通ロジックで **WhatIf → Validate → Apply**

```powershell
pwsh -NoProfile -File ./scripts/common/init.ps1
pwsh -NoProfile -File ./scripts/common/validate.ps1 -WhatIf
pwsh -NoProfile -File ./scripts/common/apply.ps1
```

---

# 📁 Directory

```text
m365-iac/
├─ iac/                       # Intune / Defender / Exchange / Purview / Identity の IaC
├─ scripts/
│  ├─ common/                 # Graph SDK・PS7・Auth・差分検証・apply 共通ロジック
│  ├─ devpc/                  # 開発PC用ラッパー
│  └─ cicd/                   # CI/CD 用ラッパー
├─ .github/workflows/
│  ├─ validate.yml
│  ├─ export.yml
│  └─ apply.yml
└─ README.md
```

---

# 🧹 .gitignore ポリシー（公開リポ向け）

- 非公開設定：`/config.local.ps1`、`*_local.ps1`、`*.local.ps1`、`*.env`、`*.secret*`、`secrets/`
- 開発ノイズ除外：Python 仮想環境／キャッシュ（`.venv/`、`__pycache__/` 等）、VS Code は許可リスト（`settings.json` 等のみコミット）
- 巨大バイナリ除外：`*.iso`、`*.vhd*`、`*.vmdk`、`*.qcow2`、`*.ova`、`*.ovf`
- エクスポート線引き：`exports/` は基本除外（レビュー用は `samples/`）

---

# 📜 免責

- 学習・検証目的。商用運用は想定しません。コードは無保証で、自己責任で使用してください。
