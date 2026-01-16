# m365-iac

自宅ラボ用のリポジトリです。この README は **ローカル開発PC・CI/CD 共通の環境構築手順**と、**M365 設定を IaC 化するための使い方**をまとめています。

目的は Microsoft 365（Intune / Defender / Exchange Online / Purview / Entra ID）の設定を **Graph API + PowerShell** でコード管理し、再現性・標準化を実現することです。

---

# 1. Environment (Lab Overview)
- Microsoft 365 Business Premium（1ユーザー）
- Entra Suite（トライアル）
- Windows Server 評価版（コネクタサーバ／ZTNA 検証）
- Microsoft Defender for Business servers（MDE 導入）
- Hyper-V 上に仮想 Windows Server 2025 を構築予定

---

# 2. Security Policies（重要）
- 機密情報（証明書・秘密鍵・シークレット）をリポジトリに含めない
- `config.local.ps1` は Git 管理外
- 開発PC：証明書ストア（CurrentUser\My）から Thumbprint を参照
- CI/CD：GitHub Actions OIDC → Entra → Key Vault（実行時取得）
- 大容量バイナリ（ISO/VHDX はコミット禁止）

---

# 3. Environment Setup（PowerShell 実行環境の統一）
開発PCと CI/CD サーバで **同じ挙動になる PowerShell 実行環境**を提供するため、次のルールを採用します。

## 3.1 PowerShell 7 の利用
- 開発PC：未導入なら自動インストール（winget）
- CI/CD：`windows-latest` には pwsh が既に含まれる

## 3.2 Microsoft Graph SDK のセットアップ（共通）
共通ロジック：`scripts/common/setup-graph-sdk.ps1`

実行内容：
- `C:\PSModules` を作成し、PSModulePath の先頭に追加
- PSGallery を Trusted 化
- 実行ポリシー（CurrentUser）を RemoteSigned（開発PCのみ）
- Microsoft.Graph を CurrentUser に Install（任意でバージョン固定）

## 3.3 開発PC向けラッパー（devpc）
`scripts/devpc/setup-dev.ps1`
- PowerShell 7 の自動導入
- 共通スクリプトを `-PersistProfile -SetExecutionPolicy` 付きで呼び出し

## 3.4 CI/CD 用ラッパー（cicd）
`scripts/cicd/setup-ci.ps1`
- プロファイル永続化なし（ジョブ完結のため）
- PSU モジュールは `C:\PSModules` をキャッシュ可能

## 3.5 再現手順（別PC）
```powershell
git clone <repo>
cd m365-iac
pwsh -File ./scripts/devpc/setup-dev.ps1
```

---

# 4. Usage（IaC 運用フロー）
1. `config.local.ps1` を作成し、TenantId / ClientId / Thumbprint を記述（Git 管理外）
2. WhatIf → Validate → Apply の順で IaC を適用

```powershell
pwsh -NoProfile -File ./scripts/common/init.ps1
pwsh -NoProfile -File ./scripts/common/validate.ps1 -WhatIf
pwsh -NoProfile -File ./scripts/common/apply.ps1
```

---

# 5. CI/CD（GitHub Actions）
- 認証は GitHub OIDC → Entra のフェデレーション
- Key Vault から実行時取得
- モジュールキャッシュ例：
```yaml
- uses: actions/cache@v4
  with:
    path: C:\PSModules
    key: psmodules-${{ runner.os }}
```

---

# 6. Directory Structure
```
m365-iac/
├─ iac/              # Intune / Defender / Exchange / Purview / Identity
├─ scripts/
│  ├─ common/        # Graph SDK / Auth / Apply などの共通ロジック
│  ├─ devpc/         # 開発PC用ラッパー
│  └─ cicd/          # CI/CD用ラッパー
├─ .github/workflows/
│  ├─ validate.yml
│  ├─ export.yml
│  └─ apply.yml
└─ README.md
```

---

# 7. .gitignore Policies
- 非公開ファイル：`config.local.ps1`, `*.secret*`, `*.env` 等
- 開発ノイズ：`.venv/`, `__pycache__/` 等
- 大容量バイナリ：ISO/VHDX など

---

# 8. Disclaimer
学習・検証目的。商用運用は保証しません。