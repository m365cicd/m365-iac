
<#! 
.SYNOPSIS
  開発PC向けセットアップ（PS7 前提／インストール処理は含まない）

.DESCRIPTION
  - 既にインストール済みの PowerShell 7 (pwsh) を前提として、
    共通セットアップ scripts/common/setup-graph-sdk.ps1 を呼び出します。
  - 開発PCでは PSModulePath の永続化と実行ポリシー(CurrentUser)=RemoteSigned を実施します。

.PREREQUISITES
  - Git がインストール済み
  - PowerShell 7 (pwsh) がインストール済み
    参考: https://github.com/PowerShell/PowerShell/releases/latest
#>

[CmdletBinding()]
param(
  [string]$ModulesRoot = 'C:\PSModules',
  [string]$GraphRequiredVersion = ''
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

$common = Join-Path $PSScriptRoot '..\common\setup-graph-sdk.ps1' | Resolve-Path

$args = @(
  '-NoProfile','-File', $common.Path,
  '-ModulesRoot', $ModulesRoot
)
if ($GraphRequiredVersion) { $args += @('-GraphRequiredVersion', $GraphRequiredVersion) }
# 開発PCでは永続化＋実行ポリシー設定を有効化
$args += @('-PersistProfile','-SetExecutionPolicy')

Write-Host " - pwsh で共通セットアップを実行します..." -ForegroundColor Cyan
& pwsh @args
if ($LASTEXITCODE -ne 0) {
  Write-Warning "共通セットアップが非ゼロ終了コードで終了しました。ログを確認してください。"
}

Write-Host "== 完了。新しい pwsh を開くとプロファイルの永続化が反映されます ==" -ForegroundColor Green
