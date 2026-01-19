<#
.SYNOPSIS
  CI/CD エージェント向けセットアップ（PS7 前提 / 永続化なし）

.DESCRIPTION
  共通セットアップ（scripts/common/setup-graph-sdk.ps1）を呼び出し、
  Microsoft Graph SDK（GA + Beta）を **ユーザースコープ**に導入します。
  保存先は **%LOCALAPPDATA%\PSModules** を使用します（実行ユーザーに依存）。
  Self-hosted Agent は実行ユーザーを固定することで、モジュールキャッシュの再現性を確保できます。
  既定は GA を利用し、ベータ API が必要なジョブのみ -UseBeta を付与します。
  認証（Connect-MgGraph 等）はパイプラインのステップ側で実施してください。

.PARAMETER ModulesRoot
  モジュール保存先。既定: $env:LOCALAPPDATA\PSModules

.PARAMETER GraphRequiredVersion
  GA（Microsoft.Graph）の固定バージョン。未指定時は最新。

.PARAMETER UseBeta
  ジョブで Beta（Microsoft.Graph.Beta）を使用する場合に指定。

.EXAMPLE
  # 既定 (GA) の例
  pwsh -File ./scripts/cicd/setup-ci.ps1

.EXAMPLE
  # Beta を使うジョブ例
  pwsh -File ./scripts/cicd/setup-ci.ps1 -UseBeta

.NOTES
  本スクリプトは資格情報を扱いません。PSModulePath の永続化や実行ポリシーの変更は行いません。
#>

[CmdletBinding()]
param(
  [string]$ModulesRoot = (Join-Path $env:LOCALAPPDATA 'PSModules'),
  [string]$GraphRequiredVersion = '',
  [switch]$UseBeta
)

# 1) 共通セットアップ（永続化・実行ポリシー変更なし）
$common = Join-Path $PSScriptRoot '..\common\setup-graph-sdk.ps1' | Resolve-Path
& pwsh -NoProfile -File $common `
  -ModulesRoot $ModulesRoot `
  -GraphRequiredVersion $GraphRequiredVersion

# 2) ★親プロセスにも PSModulePath を先頭追記
$paths = ($env:PSModulePath -split ';') | Where-Object { $_ -and $_.Trim() }
if ($paths.Count -eq 0 -or -not ($paths -contains $ModulesRoot)) {
  $env:PSModulePath = "$ModulesRoot;$env:PSModulePath"
  Write-Host " - 親PSModulePath: 先頭を $ModulesRoot に設定"
} else {
  Write-Host " - 親PSModulePath: 既に $ModulesRoot を含む"
}

# 3) 軽量 Import（メタは Import しない）
Import-Module Microsoft.Graph.Authentication -Force
Write-Host " - Import: Microsoft.Graph.Authentication"
if ($UseBeta) {
  Write-Host " - Beta API は必要時にサブモジュールが自動ロードされます（事前のメタ Import は不要）"
}

Write-Host ("CI SDK bootstrap done. User={0}, LocalAppData={1}" -f `
  [System.Security.Principal.WindowsIdentity]::GetCurrent().Name, $env:LOCALAPPDATA)
