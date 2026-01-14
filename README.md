# m365-iac

自宅ラボ用のリポジトリです。  
このREADMEは **M365 Copilotとの環境説明用を兼ねており、Copilotに作文してもらった**ものです。  
目的は、Microsoft 365（Intune / Defender / Exchange Online / Purview / Entra ID）の設定を  
**Graph API + PowerShell**で IaC 化して検証・学習することです（公開リポ・機密は含めない）。

---

## 🧪 Lab Environment
このリポジトリは、以下の構成を前提としています：

- **Microsoft 365 Business Premium（1ユーザー）**
- **Entra Suite（トライアル）**
  - 主に **Entra Private Access（ZTNA）** 検証用
  - 必要に応じて **Global Secure Access** のトラフィック分析も使用
- **Windows Server 評価版（コネクタサーバ用）**
- **Microsoft Defender for Business servers（追加）**
  - コネクタサーバは **重要資産** のため、**Microsoft Defender for Endpoint（MDE）** を導入して検証
- **ホスト**：Win11 Pro の Hyper‑V 上に仮想サーバ（Windows Server 2025）を構築予定

---

## 🔒 Security（絶対ルール）
- **秘密情報はリポジトリに含めない**（証明書・秘密鍵・シークレット・個人情報）
- **`config.local.ps1` は Git管理外**（`.gitignore`で除外）。TenantId / ClientId / Thumbprint などの識別子のみ記載し、PFXは保存しない
- 開発PCは **証明書ストア（CurrentUser\My）の Thumbprint 参照**。  
  CI/CDは **GitHub Actions OIDC → Entra → Key Vault 実行時取得**（ログ非出力・メモリのみ・終了時廃棄）
- **巨大バイナリ（ISO/VHD/VHDX 等）はコミットしない**（構築コードで再現／Artifacts／Releaseで配布）

---

## 🛠 使い方（ローカル最小手順）
1. リポジトリ直下に `config.local.ps1` を作成（公開されません）
2. 環境変数を設定（例）
   ```powershell
   $env:M365_TENANT_ID   = "<your-tenant-id>"
   $env:M365_APP_ID      = "<your-app-id>"
   $env:M365_CERT_THUMB  = "<your-cert-thumbprint>"  # 開発PCの証明書ストアの拇印
   ```
3. 共通ロジックで **WhatIf → Validate → Apply** の順
   ```powershell
   pwsh -NoProfile -File ./scripts/common/init.ps1
   pwsh -NoProfile -File ./scripts/common/validate.ps1 -WhatIf
   # レビュー後に必要最小限の Write 権限を付与してから
   pwsh -NoProfile -File ./scripts/common/apply.ps1
   ```

---

## ⚙️ CI/CD（GitHub Actions）
- 認証：**OIDC**（GitHub → Entra）でフェデレーション、**Key Vault**から実行時取得
- 主なワークフロー：`validate.yml`（Lint/差分/権限確認）、`export.yml`（機密除外でエクスポート）、`apply.yml`（PR承認後に適用）
- リポは公開のため、**Secrets／証明書の静的配置禁止**

---

## 📁 Directory（初回通知の構成をそのまま記載）
```text
m365-iac/
├─ iac/
│  ├─ intune/
│  │   ├─ deviceConfigurations/
│  │   ├─ compliancePolicies/
│  │   └─ ...
│  ├─ defender/
│  │   ├─ endpoint/
│  │   ├─ securitycenter/
│  │   └─ ...
│  ├─ exchange/
│  │   ├─ transportRules/
│  │   ├─ dkim/
│  │   └─ ...
│  ├─ purview/
│  │   ├─ dlp/
│  │   ├─ sensitivityLabels/
│  │   └─ ...
│  └─ identity/
│      ├─ groups/
│      └─ roles/
│
├─ scripts/
│  ├─ common/   ← Graph SDK、PS7、App-only 認証、差分検証、apply 共通ロジック
│  ├─ devpc/
│  └─ cicd/
│
├─ .github/
│  └─ workflows/
│      ├─ validate.yml
│      ├─ export.yml
│      └─ apply.yml
└─ README.md
```

---

## 🧹 .gitignore ポリシー（公開リポ向け）
- 非公開設定：`/config.local.ps1`、`*_local.ps1`、`*.local.ps1`、`*.env`、`*.secret*`、`secrets/`
- 開発ノイズ除外：Python仮想環境／キャッシュ（`.venv/`、`__pycache__/` 等）、VS Code は許可リスト（`settings.json` 等のみコミット）
- 巨大バイナリ除外：`*.iso`、`*.vhd*`、`*.vmdk`、`*.qcow2`、`*.ova`、`*.ovf`
- エクスポート線引き：`exports/` は基本除外（レビュー用は `samples/`）

---

## 📜 免責
- 学習・検証目的。商用運用は想定しません。コードは無保証で、自己責任で使用してください。