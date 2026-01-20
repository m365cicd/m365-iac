# M365 アカウント運用メモ（個人ラボ / m365-iac）

このメモは **「Microsoft 365 Business Premium 1ライセンスで IaC 検証を回す」**ための、  
アカウントと権限の最小構成（覚えやすさ重視）の早見表です。

> ⚠️ 注意（Public リポ前提）
> - 実ユーザー名（UPN）・電話番号・回復用メールなどの機微情報は書かない
> - 本文は「役割・原則・手順のテンプレ」だけを置く

---

## 0. 前提（ポリシー）

- **最小権限（Least Privilege）**：普段使いアカウントを強権限にしない
- **責務分離（Separation of duties）**：
  - 日常利用/個人データ → **Daily（①）**
  - テナント設定変更/IaC適用 → **OpsAdmin（②）**
  - 事故復旧（最後の鍵） → **BreakGlass（③）**
- **MFA は必須**（Security defaults / Conditional Access のどちらかで実現）
- **ブラウザプロファイル分離**（Daily / Admin / BreakGlass）を推奨

---

## 1. アカウント構成（3アカウント版 / PIMなし前提）

| No | 呼び名 | ライセンス | 目的 | 目安のサインイン頻度 |
|---:|---|---|---|---|
| ① | **Daily（普段使い）** | ✅ あり（BP割当） | Outlook/Excel/Teams + Graph で「自分のデータ」を読む/書く | 毎日 |
| ② | **OpsAdmin（管理用）** | ❌ なし | Intune/Defender/Entra など **設定変更・IaC適用** | 週に数回 |
| ③ | **BreakGlass（緊急用）** | ❌ なし | ②が詰んだ時の復旧（最後の鍵） | 原則ログインしない |

---

## 2. ロール設計（おすすめ最小 / PIMなし前提）

### ① Daily（普段使い）
- **原則：Entra ディレクトリロールなし**（= ふつうのユーザー）
- 例外：状態を「読むだけ」したい場合のみ Reader 系を検討（必要最小）

### ② OpsAdmin（管理用）
- **重要：Privileged Role Administrator（特権ロール管理者）は外さない**
  - ②が “ロールを付け外しできる担当者” でないと詰むため
  - ②からこれを外すと、①や②自身のロール変更ができなくなり、
    結果として BreakGlass（③）を頻繁に使う運用に落ちがち
- 追加ロールは「必要になったら足す」でOK（最小権限で）
  - Intune を触る → **Intune Administrator**
  - Defender を触る → **Security Administrator**
  - Entra Private Access / アプリ周り → **Application Administrator**（必要になったら）

### ③ BreakGlass（緊急用）
- **Global Administrator（恒久）**
- 普段使わない（最後の鍵）

---

## 3. Microsoft公式：Break-glass（緊急用GA）を推奨する根拠

Microsoft Learn の公式ガイドでは、**緊急用（break-glass）アカウントを用意すること**が推奨されています。

- Emergency access（Break-glass）運用の推奨事項  
  https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/security-planning
- 役割ベストプラクティス（緊急用アカウントの推奨を含む）  
  https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/best-practices
- 条件付きアクセス設計（ロックアウト防止の観点）  
  https://learn.microsoft.com/en-us/entra/identity/conditional-access/plan-conditional-access

---

## 4. どの作業にどのアカウントが必要か（早見表）

記号：
- ✅ = 推奨アカウント
- △ = できるが推奨しない / 場合による
- ❌ = 原則やらない

| 作業カテゴリ | 例（やること） | ① Daily | ② OpsAdmin | ③ BreakGlass | 補足（注意点） |
|---|---|:---:|:---:|:---:|---|
| 普段利用 | Outlook/Excel/Teams | ✅ | ❌ | ❌ | ①は普段使い専用 |
| 個人データ自動化（Graph） | 自分の予定表登録、メール送信、OneDrive操作 | ✅ | △ | ❌ | “自分のデータ”はディレクトリロール不要が多い |
| テナント設定「閲覧」 | Intune/Defender 設定のエクスポート、監査 | △ | ✅ | ❌ | ①に閲覧ロールを足すより、②でまとめるのが安全 |
| テナント設定「変更/IaC適用」 | Intuneポリシー適用、Defender設定変更 | ❌ | ✅ | ❌ | 基本は②で実施（責務分離） |
| ユーザー/グループ管理 | ユーザー追加/削除、グループ作成 | ❌ | ✅ | ❌ | 必要になったら追加ロールを付与 |
| ロール割当の変更 | ①②のロール付与・解除 | ❌ | ✅ | ✅ | 通常は②（PRA）で実施。詰んだら③ |
| アプリ登録（CI/CD用） | GitHub Actions用アプリ作成、権限付与 | ❌ | ✅ | ✅ | 通常は②。最終手段として③ |
| Admin Consent | アプリ権限の管理者同意 | ❌ | ✅ | ✅ | 職場環境だとここで詰まりがち |
| 条件付きアクセス（CA） | 管理者のサインイン制限 | ❌ | ✅ | ✅ | ミスるとロックアウト。③は慎重に扱う |
| Security defaults | MFA強制をON/OFF | ❌ | ✅ | ✅ | 小規模の最短防御 |
| Intune 管理 | 構成プロファイル、MDAV、Firewall、Compliance | ❌ | ✅ | ❌ | ②に Intune Admin |
| Defender 管理 | MDEポリシー、アラート運用 | ❌ | ✅ | ❌ | ②に Security Admin |
| Entra Private Access | コネクタ導入/アプリ設定 | ❌ | ✅ | ✅ | ②に App Admin（必要時） |
| 事故対応 | ②がログイン不能、CAミス、権限事故 | ❌ | ❌ | ✅ | BreakGlass運用（普段触らない） |

---

## 5. 運用のコツ（ラボでも “それっぽく” 安全に）

### 5.1 ブラウザプロファイル分離（おすすめ）
- Edge/Chrome を 3つ作る：**Daily / Admin / BreakGlass**
- 管理センターは Admin プロファイルだけで開く  
  → “普段のブラウザに GA が残る事故”が減る

### 5.2 認証（MFA）をスマホ1台で回す
- Microsoft Authenticator に ①②③ を全部登録するのは普通
- SMSは可能でも、できれば Authenticator中心に寄せる

### 5.3 IaCの実行ルール（迷わない）
- export/read（状態確認） → ①でもOK / 安全寄りなら②
- apply（変更適用） → ②のみ

---

## 6. TODO（あとで余力があれば）

- [ ] ② OpsAdmin に付与する「最小ロールセット」：Intune / Defender / Entra / Exchange / Purview 別
- [ ] connect-delegated.ps1 の推奨パターン（Interactive / DeviceCode）
- [ ] GitHub Actions（アプリ登録/OIDC）に必要な権限と手順
- [ ] 職場環境で詰まりがちなポイント（CA/Consent/準拠デバイス）まとめ
- [ ] Entra Suite（90日評価）導入後：PIMで “必要な時だけ権限昇格（JIT）” 運用を試す
