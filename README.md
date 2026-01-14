
# m365-iac

自宅ラボ環境で、Microsoft 365（Intune / Defender / Entra など）の設定を  
Graph API / PowerShell を使って IaC 化して遊ぶためのリポジトリです。

本番利用ではなく、**個人の検証・学習**を目的としています。

---

## 🧪 Lab Environment

このリポジトリは以下の構成を前提にしています：

- **Microsoft 365 Business Premium（1ユーザー）**
- **Entra Suite（トライアル）**  
  - 主に **Entra Private Access**（ZTNA）検証用  
  - 必要に応じて Global Secure Access のトラフィック分析も使用
- **Windows Server 評価版（コネクタサーバ用）**
- **Microsoft Defender for Business servers（追加）**  
  - コネクタサーバは重要資産のため、MDE を導入して検証

---

## ⚠️ Notes

- このリポジトリには **秘密情報（証明書・秘密鍵・シークレット等）を含めません**  
- Graph API の権限は **最小権限（Least Privilege）** を前提とします  
- スクリプトの動作は **必ず検証環境で確認**してください（WhatIf 推奨）

---

## 📄 License / Disclaimer

本リポジトリは **MIT License** です。  
内容の利用によって生じたいかなる損害についても作者は責任を負いません。  
**自己責任でご利用ください。**

---

## 🛠 Usage

今後つくるスクリプトの “使い方” をここに追記していきます。