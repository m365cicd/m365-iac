<#
.SYNOPSIS
  Microsoft Graph PowerShell SDK の共通セットアップ（PS7 前提 / Save-Module 方式 / 軽量インストール）

.DESCRIPTION
  PowerShell 7 を前提に、Microsoft Graph PowerShell SDK をユーザースコープへ初期導入します。

  本リポジトリは「SDK 全部を入れない」軽量主義：
  - 既定では Microsoft.Graph.Authentication のみを Save-Module します
  - 実際の Graph 呼び出しは Invoke-MgGraphRequest を中心に組み立てる想定です
    （必要になったモジュールだけ後で追加導入する運用も可能）

  保存先は OneDrive/KFM の影響を避け、権限不足になりにくい固定ディレクトリ
  **%LOCALAPPDATA%\PSModules** を採用。
  PSModulePath（セッションのみ）の先頭に追加し、自動読み込みを成立させます。

  本スクリプトは「モジュール配置とパス設定（セッションのみ）」を行い、
  PowerShell Profile（$PROFILE）には一切追記しません（Public リポ前提）。

.PARAMETER ModulesRoot
  モジュール保存先。既定: $env:LOCALAPPDATA\PSModules

.PARAMETER GraphRequiredVersion
  Microsoft.Graph.Authentication の固定バージョン。未指定時は最新。

.PARAMETER SetExecutionPolicy
  実行ポリシー(CurrentUser) を RemoteSigned に設定（開発 PC 向け）。
  ※環境によっては GPO 等でブロックされるため、必ず結果を表示します。

.PARAMETER TrustPSGallery
  PSGallery を Trusted に設定します（永続設定）。
  既定では PSGallery の設定は変更しません。

.EXAMPLE
  pwsh -File ./scripts/setup/setup-graph-sdk.ps1

.EXAMPLE
  pwsh -File ./scripts/setup/setup-graph-sdk.ps1 -SetExecutionPolicy -TrustPSGallery

.NOTES
  - 本リポは PowerShell 7 (pwsh) 前提で運用します。
  - CI/CD では SetExecutionPolicy / TrustPSGallery は通常不要です。

  Refs (設計根拠 / 公式ドキュメント)
    - about_PSModulePath（PSModulePath の意味と構築）
      https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_psmodulepath?view=powershell-7.5
    - about_Modules（既定モジュールロケーション / 自動読み込み）
      https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_modules?view=powershell-7.5
    - Graph PowerShell 認証コマンド（delegated/app-only, context scope 等）
      https://learn.microsoft.com/ja-jp/powershell/microsoftgraph/authentication-commands?view=graph-powershell-beta
#>

[CmdletBinding()]
param(
  [string]$ModulesRoot = (Join-Path $env:LOCALAPPDATA 'PSModules'),
  [string]$GraphRequiredVersion = '',
  [switch]$SetExecutionPolicy,
  [switch]$TrustPSGallery
)

$ErrorActionPreference = 'Stop'

Write-Host "== Microsoft Graph SDK セットアップ (Save-Module | PS7 | Lightweight) ==" -ForegroundColor Cyan
Write-Host ("PowerShell: {0}" -f $PSVersionTable.PSVersion)
Write-Host ("ModulesRoot: {0}" -f $ModulesRoot)

# --- ExecutionPolicy (Before) ----------------------------------------------------------
Write-Host "== ExecutionPolicy (Before) ==" -ForegroundColor DarkCyan
try {
  Get-ExecutionPolicy -List | Format-Table -AutoSize | Out-String | Write-Host
} catch {
  Write-Warning ("Get-ExecutionPolicy -List failed: {0}" -f $_.Exception.Message)
}

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

# --- 保存先作成 ------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $ModulesRoot)) {
  New-Item -ItemType Directory -Path $ModulesRoot -Force | Out-Null
  Write-Host " - 作成: $ModulesRoot"
} else {
  Write-Host " - 既存: $ModulesRoot"
}

# --- PSModulePath 先頭に追加（セッション） ---------------------------------------------
$sessionPaths = ($env:PSModulePath -split ';') | Where-Object { $_ -and $_.Trim() }
if ($sessionPaths.Count -eq 0 -or $sessionPaths[0] -ne $ModulesRoot) {
  $env:PSModulePath = ("{0};{1}" -f $ModulesRoot, $env:PSModulePath)
  Write-Host " - PSModulePath(セッション): 先頭を $ModulesRoot に設定"
} else {
  Write-Host " - PSModulePath(セッション): 先頭は既に $ModulesRoot"
}

# --- PSModulePath 永続化は行わない -----------------------------------------------------
Write-Host " - PSModulePath の永続化は行いません（$PROFILE は変更しません）"

# --- PSGallery / NuGet provider --------------------------------------------------------
try {
  $repo = Get-PSRepository -Name 'PSGallery' -ErrorAction Stop
  Write-Host (" - PSGallery policy: {0}" -f $repo.InstallationPolicy)

  if ($TrustPSGallery) {
    if ($repo.InstallationPolicy -ne 'Trusted') {
      Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
      Write-Host " - PSGallery -> Trusted (requested)"
    } else {
      Write-Host " - PSGallery は既に Trusted"
    }
  } else {
    Write-Host " - PSGallery policy は変更しません（必要なら -TrustPSGallery を付けてください）"
  }
} catch {
  Write-Warning ("PSGallery 取得/設定に失敗: {0}" -f $_.Exception.Message)
}

try {
  if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
    Write-Host " - NuGet プロバイダーを導入（CurrentUser）"
  } else {
    Write-Host " - NuGet プロバイダーは既に存在"
  }
} catch {
  Write-Warning ("NuGet プロバイダー導入に失敗: {0}" -f $_.Exception.Message)
}

# --- 実行ポリシー（開発PCのみ） -------------------------------------------------------
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

# --- ExecutionPolicy (After) -----------------------------------------------------------
Write-Host "== ExecutionPolicy (After) ==" -ForegroundColor DarkCyan
try {
  Get-ExecutionPolicy -List | Format-Table -AutoSize | Out-String | Write-Host
} catch {
  Write-Warning ("Get-ExecutionPolicy -List failed: {0}" -f $_.Exception.Message)
}

# --- Graph SDK Save-Module（軽量：Authentication のみ） --------------------------------
$authName = 'Microsoft.Graph.Authentication'
$authBase = Join-Path $ModulesRoot $authName
$rv       = $GraphRequiredVersion

$authExists = Get-Module -ListAvailable $authName |
  Where-Object { $_.ModuleBase -like "$ModulesRoot*" -and ($rv ? ($_.Version -ge [version]$rv) : $true) }

if ($authExists) {
  Write-Host " - $authName は既に $ModulesRoot に存在 → Save-Module をスキップ"
} else {
  if ($rv) {
    $target = Join-Path $authBase $rv
    if (Test-Path $target) {
      try { Remove-Item $target -Recurse -Force } catch { Write-Warning " - 既存 $target の削除に失敗: $($_.Exception.Message)" }
    }
  }

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

# --- 確認のため軽量 Import -------------------------------------------------------------
try {
  Import-Module Microsoft.Graph.Authentication -Force -ErrorAction Stop | Out-Null
  Write-Host " - Import-Module Microsoft.Graph.Authentication" -ForegroundColor Green
} catch {
  Write-Warning ("Import-Module Microsoft.Graph.Authentication に失敗: {0}" -f $_.Exception.Message)
  throw
}

# --- どれが入ったか表示 ----------------------------------------------------------------
try {
  Get-Module -ListAvailable Microsoft.Graph.Authentication |
    Sort-Object Version -Descending |
    Select-Object -First 1 Name, Version, ModuleBase |
    Format-Table -AutoSize | Out-String | Write-Host
} catch {
  Write-Warning ("Module inventory failed: {0}" -f $_.Exception.Message)
}

Write-Host "== 完了 ==" -ForegroundColor Green
Write-Host "TIP: 実際のGraph呼び出しは Invoke-MgGraphRequest を中心に組み立てると、モジュール大量導入を避けられます。"
