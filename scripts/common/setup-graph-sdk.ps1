<#
.SYNOPSIS
  Microsoft Graph PowerShell SDK のセットアップ（共通）

.DESCRIPTION
  - OneDrive/KFM 配下を避け、指定モジュールルート（既定: C:\PSModules）を PSModulePath の先頭へ
  - PSGallery を Trusted に設定
  - Microsoft.Graph を CurrentUser に Install-Module（任意で RequiredVersion 固定）
  - 必要に応じてプロファイルへ PSModulePath を永続化（PersistProfile スイッチ）

.PARAMETER ModulesRoot
  モジュール保存先（デフォルト: C:\PSModules）

.PARAMETER GraphRequiredVersion
  固定したい Microsoft.Graph のバージョン（未指定なら最新）

.PARAMETER PersistProfile
  $PROFILE へ PSModulePath の先頭追加を永続化（CI では通常しない）

.PARAMETER SetExecutionPolicy
  CurrentUser スコープの実行ポリシーを RemoteSigned に設定（CIでは通常しない）

.EXAMPLE
  pwsh -File .\scripts\common\setup-graph-sdk.ps1 -PersistProfile -SetExecutionPolicy

.EXAMPLE
  pwsh -File .\scripts\common\setup-graph-sdk.ps1 -GraphRequiredVersion 2.28.0
#>

[CmdletBinding()]
param(
  [string]$ModulesRoot = 'C:\PSModules',
  [string]$GraphRequiredVersion = '',
  [switch]$PersistProfile,
  [switch]$SetExecutionPolicy
)

Write-Host "== Microsoft Graph SDK セットアップ ==" -ForegroundColor Cyan
Write-Host "ModulesRoot: $ModulesRoot"

# 0) OneDrive/KFM 直下の誤設定を避けるための注意喚起（チェックのみ）
$oneDrivePaths = @()
if ($env:OneDrive) { $oneDrivePaths += $env:OneDrive }
$oneDriveDefault = Join-Path $env:USERPROFILE 'OneDrive'
if (Test-Path $oneDriveDefault) { $oneDrivePaths += $oneDriveDefault }

foreach ($od in $oneDrivePaths | Select-Object -Unique) {
  if ($ModulesRoot -like "$od*") {
    Write-Warning "ModulesRoot が OneDrive/KFM 配下に見えます: $ModulesRoot"
    Write-Warning "例: C:\PSModules のようなローカル固定パスを推奨します。"
  }
}

# 1) モジュールフォルダ作成
if (-not (Test-Path -LiteralPath $ModulesRoot)) {
  New-Item -ItemType Directory -Path $ModulesRoot -Force | Out-Null
  Write-Host " - 作成: $ModulesRoot"
} else {
  Write-Host " - 既存: $ModulesRoot"
}

# 2) 今のセッションの PSModulePath 先頭に設定
$paths = $env:PSModulePath -split ';' | Where-Object { $_ -ne '' }
if ($paths.Count -eq 0 -or $paths[0] -ne $ModulesRoot) {
  $env:PSModulePath = "$ModulesRoot;$($env:PSModulePath)"
  Write-Host " - PSModulePath(セッション): 先頭を $ModulesRoot に設定"
} else {
  Write-Host " - PSModulePath(セッション): 先頭は既に $ModulesRoot"
}

# 3) 永続化（任意）
if ($PersistProfile.IsPresent) {
  try {
    if (-not (Test-Path -LiteralPath $PROFILE)) {
      New-Item -ItemType File -Path $PROFILE -Force | Out-Null
    }
    $profileLine = '$env:PSModulePath = "' + $ModulesRoot + ';" + $env:PSModulePath'
    if (-not (Select-String -Path $PROFILE -Pattern [regex]::Escape($profileLine) -SimpleMatch -Quiet)) {
      Add-Content -Path $PROFILE -Value $profileLine
      Write-Host " - $PROFILE に PSModulePath を永続化"
    } else {
      Write-Host " - $PROFILE は既に PSModulePath 永続化済み"
    }
  } catch {
    Write-Warning "プロファイル書込みに失敗: $($_.Exception.Message)"
  }
} else {
  Write-Host " - 永続化なし（PersistProfile 未指定）"
}

# 4) PSGallery 信頼
try {
  $repo = Get-PSRepository -Name 'PSGallery' -ErrorAction Stop
  if ($repo.InstallationPolicy -ne 'Trusted') {
    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
    Write-Host " - PSGallery -> Trusted"
  } else {
    Write-Host " - PSGallery は Trusted"
  }
} catch {
  Write-Warning "PSGallery 取得/設定に失敗: $($_.Exception.Message)"
}

# 5) 実行ポリシー（任意）
if ($SetExecutionPolicy.IsPresent) {
  try {
    $cur = Get-ExecutionPolicy -Scope CurrentUser -ErrorAction SilentlyContinue
    if ($cur -notin @('RemoteSigned','Unrestricted','Bypass')) {
      Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
      Write-Host " - 実行ポリシー(CurrentUser) -> RemoteSigned"
    } else {
      Write-Host " - 実行ポリシー(CurrentUser): $cur"
    }
  } catch {
    Write-Warning "実行ポリシー設定に失敗: $($_.Exception.Message)"
  }
} else {
  Write-Host " - 実行ポリシー変更なし（SetExecutionPolicy 未指定）"
}

# 6) Microsoft.Graph の導入（CurrentUser）
$installParams = @{
  Name       = 'Microsoft.Graph'
  Scope      = 'CurrentUser'
  Repository = 'PSGallery'
  Force      = $true
}
if ($GraphRequiredVersion) { $installParams.RequiredVersion = $GraphRequiredVersion }

Write-Host " - Install-Module Microsoft.Graph (CurrentUser)"
try {
  Install-Module @installParams
} catch {
  Write-Warning "Install-Module でエラー: $($_.Exception.Message)"
}

# 7) 結果表示
$mods = Get-Module Microsoft.Graph -ListAvailable | Sort-Object Version -Descending
if ($mods) {
  $mods | Select-Object Name,Version,ModuleBase | Format-Table -AutoSize
  Write-Host "== 完了。必要なら PowerShell 再起動で永続設定が反映されます ==" -ForegroundColor Green
} else {
  Write-Warning "Microsoft.Graph が見つかりません。PSModulePath/インストール状況をご確認ください。"
}
