<#
.SYNOPSIS
  開発 PC 向けセットアップ（PS7 前提 / インストール処理は含まない）

.DESCRIPTION
  既に PowerShell 7 (pwsh) が導入されている前提で、
  共通セットアップ（scripts/common/setup-graph-sdk.ps1）を呼び出します。
  開発 PC では PSModulePath の **永続化** と、実行ポリシー(CurrentUser)=**RemoteSigned** を適用します。
  既定は GA（Microsoft.Graph）を利用し、最新 API 検証等が必要な場合のみ Beta（Microsoft.Graph.Beta）を Import します。
  保存先は **%LOCALAPPDATA%\PSModules** を使用します（OneDrive/KFM 影響回避・権限不足を避けるため）。

.PARAMETER ModulesRoot
  モジュール保存先。既定: $env:LOCALAPPDATA\PSModules

.PARAMETER GraphRequiredVersion
  GA（Microsoft.Graph）の固定バージョン。未指定時は最新。

.PARAMETER UseBeta
  セッションで Beta（Microsoft.Graph.Beta）を使用する場合に指定。

.EXAMPLE
  pwsh -File ./scripts/devpc/setup-dev.ps1
  # 既定 (GA) でセットアップ。PSModulePath 永続化と実行ポリシー設定を行う。

.EXAMPLE
  pwsh -File ./scripts/devpc/setup-dev.ps1 -UseBeta
  # 開発セッションで Microsoft.Graph.Beta を Import。

.NOTES
  本スクリプトは資格情報を扱いません（Public リポ前提）。認証は利用側のスクリプトで行います。
#>

[CmdletBinding()]
param(
  [string]$ModulesRoot = (Join-Path $env:LOCALAPPDATA 'PSModules'),
  [string]$GraphRequiredVersion = '',
  [switch]$UseBeta
)

function Assert-PwshExists {
  try {
    $v = & pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.Major' 2>$null
    if (-not $v -or [int]$v -lt 7) { throw 'pwsh not found or version < 7' }
  } catch {
    Write-Error "PowerShell 7 (pwsh) が見つかりません。先に PS7 をインストールしてください。"
    throw
  }
}

Write-Host "== 開発PC セットアップ（PS7 前提）==" -ForegroundColor Cyan
Assert-PwshExists

# 1) 共通セットアップ（保存先作成・PSModulePath 追加・Authentication 保存）
$common = Join-Path $PSScriptRoot '..\common\setup-graph-sdk.ps1' | Resolve-Path
$args = @(
  '-NoProfile','-File', $common.Path,
  '-ModulesRoot', $ModulesRoot
)
if ($GraphRequiredVersion) { $args += @('-GraphRequiredVersion', $GraphRequiredVersion) }
$args += @('-PersistProfile','-SetExecutionPolicy')  # 開発PCでは永続化＋実行ポリシー設定

Write-Host " - 共通セットアップを pwsh で実行..." -ForegroundColor Cyan
& pwsh @args
if ($LASTEXITCODE -ne 0) {
  Write-Warning "共通セットアップが非ゼロ終了コードで終了しました。ログを確認してください。"
}

# 2) ★親プロセスにも PSModulePath を先頭追記（子での変更は親に伝播しない）
$paths = ($env:PSModulePath -split ';') | Where-Object { $_ -and $_.Trim() }
if ($paths.Count -eq 0 -or -not ($paths -contains $ModulesRoot)) {
  $env:PSModulePath = "$ModulesRoot;$env:PSModulePath"
  Write-Host " - 親PSModulePath: 先頭を $ModulesRoot に設定"
} else {
  Write-Host " - 親PSModulePath: 既に $ModulesRoot を含む"
}

# 3) ★軽量 Import：Authentication のみ（メタは Import しない）
try {
  Import-Module Microsoft.Graph.Authentication -Force -ErrorAction Stop
  Write-Host " - Import: Microsoft.Graph.Authentication"
  if ($UseBeta) {
    Write-Host " - Beta API は必要時にサブモジュールが自動ロードされます（事前のメタ Import は不要）"
  } else {
    Write-Host " - 既定は GA（v1.0）。必要時にサブモジュールが自動ロードされます。"
  }
} catch {
  Write-Warning ("Import-Module Microsoft.Graph.Authentication に失敗: {0}" -f $_.Exception.Message)
  throw
}

Write-Host "== 完了。新しい pwsh を開くとプロファイル永続化が反映されます ==" -ForegroundColor Green
