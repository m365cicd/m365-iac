<#
.SYNOPSIS
  Microsoft Graph PowerShell SDK の共通セットアップ（PS7 前提 / Save-Module 方式）

.DESCRIPTION
  PowerShell 7 を前提に、Microsoft Graph PowerShell SDK（GA と Beta）をユーザースコープへ初期導入します。
  保存先は OneDrive/KFM の影響を避け、権限不足になりにくい固定ディレクトリ
  **%LOCALAPPDATA%\PSModules** を採用。PSModulePath（セッション＋User 永続）の先頭に追加し、
  以降の自動読み込みを成立させます。
  既定運用は GA、必要時のみ Beta を Import します。
  本スクリプトは「モジュール配置とパス設定」のみを行い、資格情報は扱いません（Public リポ前提）。

.PARAMETER ModulesRoot
  モジュール保存先。既定: $env:LOCALAPPDATA\PSModules

.PARAMETER GraphRequiredVersion
  GA（Microsoft.Graph）の固定バージョン。未指定時は最新。

.PARAMETER PersistProfile
  $PROFILE に PSModulePath 先頭追記を永続化（開発 PC 向け）。

.PARAMETER SetExecutionPolicy
  実行ポリシー(CurrentUser) を RemoteSigned に設定（開発 PC 向け）。

.EXAMPLE
  pwsh -File ./scripts/common/setup-graph-sdk.ps1 -PersistProfile -SetExecutionPolicy

.EXAMPLE
  pwsh -File ./scripts/common/setup-graph-sdk.ps1 -GraphRequiredVersion 2.28.0

.NOTES
  - 本リポは PowerShell 7 (pwsh) 前提で運用します。
  - CI/CD では PersistProfile / SetExecutionPolicy は通常不要です。

  - Refs (設計根拠 / 公式ドキュメント)
    - about_Modules（既定モジュールロケーション / 自動読み込み）
      https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_modules?view=powershell-7.5
    - about_PSModulePath（PSModulePath の意味と構築）
      https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_psmodulepath?view=powershell-7.5
    - Graph SDK インストール（GA/Beta 併存、v2 ではメタの事前 Import 不要）
      https://github.com/microsoftgraph/msgraph-sdk-powershell
      https://github.com/MicrosoftDocs/microsoftgraph-docs-powershell/blob/main/microsoftgraph/docs-conceptual/installation.md
#>

[CmdletBinding()]
param(
  [string]$ModulesRoot = (Join-Path $env:LOCALAPPDATA 'PSModules'),
  [string]$GraphRequiredVersion = '',   # v2 では実質 Authentication の RequiredVersion として扱う
  [switch]$PersistProfile,
  [switch]$SetExecutionPolicy
)

$ErrorActionPreference = 'Stop'

Write-Host "== Microsoft Graph SDK セットアップ (Save-Module 方式 | PS7) ==" -ForegroundColor Cyan
Write-Host ("ModulesRoot: {0}" -f $ModulesRoot)

# --- OneDrive/KFM 回避チェック ---------------------------------------------------------
$oneDriveHints = @()
if ($env:OneDrive) { $oneDriveHints += $env:OneDrive }
$odDefault = Join-Path $env:USERPROFILE 'OneDrive'
if (Test-Path $odDefault) { $oneDriveHints += $odDefault }

foreach ($od in $oneDriveHints | Select-Object -Unique) {
  if ($ModulesRoot -like ("{0}*" -f $od)) {
    Write-Warning "ModulesRoot が OneDrive/KFM 配下に見えます: $ModulesRoot"
    Write-Warning "例: %LOCALAPPDATA%\PSModules のようなローカル固定パスを推奨します。"
  }
}

# --- 保存先作成 ---------------------------------------------------------
if (-not (Test-Path -LiteralPath $ModulesRoot)) {
  New-Item -ItemType Directory -Path $ModulesRoot -Force | Out-Null
  Write-Host " - 作成: $ModulesRoot"
} else {
  Write-Host " - 既存: $ModulesRoot"
}

# --- PSModulePath 先頭に追加（セッション & User 永続） -------------------------------
$sessionPaths = ($env:PSModulePath -split ';') | Where-Object { $_ -and $_.Trim() }
if ($sessionPaths.Count -eq 0 -or $sessionPaths[0] -ne $ModulesRoot) {
  $env:PSModulePath = ("{0};{1}" -f $ModulesRoot, $env:PSModulePath)
  Write-Host " - PSModulePath(セッション): 先頭を $ModulesRoot に設定"
} else {
  Write-Host " - PSModulePath(セッション): 先頭は既に $ModulesRoot"
}

if ($PersistProfile) {
  try {
    if (-not (Test-Path -LiteralPath $PROFILE)) {
      New-Item -ItemType File -Path $PROFILE -Force | Out-Null
    }
    $guardBegin = '# >>> m365-iac: prepend %LOCALAPPDATA%\PSModules to PSModulePath >>>'
    $guardEnd   = '# <<< m365-iac <<<'
    $line       = '$env:PSModulePath = (Join-Path $env:LOCALAPPDATA ''PSModules'') + '';'' + $env:PSModulePath'

    $content = Get-Content -LiteralPath $PROFILE -ErrorAction SilentlyContinue
    if ($null -eq ($content | Where-Object { $_ -eq $guardBegin })) {
      Add-Content -LiteralPath $PROFILE -Value $guardBegin
      Add-Content -LiteralPath $PROFILE -Value $line
      Add-Content -LiteralPath $PROFILE -Value $guardEnd
      Write-Host " - $PROFILE に PSModulePath を永続化"
    } else {
      Write-Host " - $PROFILE は既に PSModulePath 永続化済み"
    }
  } catch {
    Write-Warning ("プロファイル書込みに失敗: {0}" -f $_.Exception.Message)
  }
} else {
  Write-Host " - 永続化なし（PersistProfile 未指定）"
}

# --- PSGallery / NuGet provider 準備 ---------------------------------------------------
try {
  $repo = Get-PSRepository -Name 'PSGallery' -ErrorAction Stop
  if ($repo.InstallationPolicy -ne 'Trusted') {
    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
    Write-Host " - PSGallery -> Trusted"
  } else {
    Write-Host " - PSGallery は Trusted"
  }
} catch {
  Write-Warning ("PSGallery 取得/設定に失敗: {0}" -f $_.Exception.Message)
}

try {
  if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
    Write-Host " - NuGet プロバイダーを導入（CurrentUser）"
  }
} catch {
  Write-Warning ("NuGet プロバイダー導入に失敗: {0}" -f $_.Exception.Message)
}

# --- 実行ポリシー（開発 PC のみ） -----------------------------------------------------
if ($SetExecutionPolicy) {
  try {
    $cur = Get-ExecutionPolicy -Scope CurrentUser -ErrorAction SilentlyContinue
    if ($cur -notin @('RemoteSigned','Unrestricted','Bypass')) {
      Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
      Write-Host " - 実行ポリシー(CurrentUser) -> RemoteSigned"
    } else {
      Write-Host (" - 実行ポリシー(CurrentUser): {0}" -f $cur)
    }
  } catch {
    Write-Warning ("実行ポリシー設定に失敗: {0}" -f $_.Exception.Message)
  }
} else {
  Write-Host " - 実行ポリシー変更なし（SetExecutionPolicy 未指定）"
}

# --- Graph SDK Save-Module（最小：Authentication のみ。既存があればスキップ） --------
$authName = 'Microsoft.Graph.Authentication'
$authBase = Join-Path $ModulesRoot $authName
$rv       = $GraphRequiredVersion   # 未指定なら最新版

# 既存確認（ModulesRoot 配下にあるかを優先）
$authExists = Get-Module -ListAvailable $authName |
  Where-Object { $_.ModuleBase -like "$ModulesRoot*" -and ($rv ? ($_.Version -ge [version]$rv) : $true) }

if ($authExists) {
  Write-Host " - $authName は既に $ModulesRoot に存在 → Save-Module をスキップ"
} else {
  # 中途半端な同バージョン残骸を掃除（AccessDenied 回避）
  if ($rv) {
    $target = Join-Path $authBase $rv
    if (Test-Path $target) {
      try { Remove-Item $target -Recurse -Force } catch { Write-Warning " - 既存 $target の削除に失敗: $($_.Exception.Message)" }
    }
  }
  # ACL を緩和（現在ユーザーにフル）
  try {
    $me  = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $acl = Get-Acl $ModulesRoot
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($me,'FullControl','ContainerInherit, ObjectInherit','None','Allow')
    $acl.SetAccessRule($rule); Set-Acl $ModulesRoot $acl
  } catch { Write-Warning " - ACL 変更に失敗（続行）: $($_.Exception.Message)" }

  Write-Host " - Save-Module $authName -> $ModulesRoot"
  $saveParams = @{ Name=$authName; Path=$ModulesRoot; Force=$true; Repository='PSGallery' }
  if ($rv) { $saveParams['RequiredVersion'] = $rv }
  try { Save-Module @saveParams } catch { Write-Warning "Save-Module でエラー ($authName): $($_.Exception.Message)"; throw }
}

# --- 確認のため軽量 Import（メタは Import しない） ---------------------------------
try {
  Import-Module Microsoft.Graph.Authentication -Force -ErrorAction Stop | Out-Null
  Write-Host " - Import-Module Microsoft.Graph.Authentication" -ForegroundColor Green
} catch {
  Write-Warning ("Import-Module Microsoft.Graph.Authentication に失敗: {0}" -f $_.Exception.Message)
  throw
}

Write-Host "== 完了。新しい pwsh セッションで PSModulePath 永続設定が反映されます ==" -ForegroundColor Green
