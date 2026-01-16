<#
.SYNOPSIS
  Microsoft Graph PowerShell SDK の共通セットアップ（OneDrive/KFM 影響回避・Save-Module 方式）

.DESCRIPTION
  本スクリプトは、開発PCおよび CI/CD（GitHub Actions）で同一挙動となるよう、
  Microsoft Graph PowerShell SDK を **固定ディレクトリ (C:\PSModules)** に配置し、
  実行環境（PSModulePath / PSGallery / 実行ポリシー / プロファイル永続化）を整備します。

  重要な設計判断（将来のセッション向けメモ / Public リポ前提）
  ------------------------------------------------------------------
  - PowerShell 7 (pwsh) を前提条件とする（PS5.1 は対象外）。
  - OneDrive/KFM の影響を回避するため、**Install-Module ではなく Save-Module** を採用。
    * Install-Module -Scope CurrentUser は保存先が "Documents\PowerShell\Modules" に固定され、
      KFM（OneDrive）配下へリダイレクトされ得るため再現性が損なわれる。
    * Save-Module -Path C:\PSModules により、保存先を明示的に固定して回避する。
  - ModulesRoot（既定: C:\PSModules）を **PSModulePath の先頭**に設定。
  - 開発PCでは、任意で **PSModulePath 永続化** と **実行ポリシー(CurrentUser)=RemoteSigned** を適用。
  - 管理者権限は不要（CurrentUser スコープで動作）。
  - Secrets/証明書は扱わない（Public リポのため）。

.PARAMETER ModulesRoot
  Microsoft.Graph を保存するディレクトリ（既定: C:\PSModules）。

.PARAMETER GraphRequiredVersion
  Microsoft.Graph の固定バージョン。未指定時は最新を保存。

.PARAMETER PersistProfile
  $PROFILE に PSModulePath 先頭追加（C:\PSModules）を追記して永続化。

.PARAMETER SetExecutionPolicy
  CurrentUser スコープの実行ポリシーを RemoteSigned に設定。

.EXAMPLE
  pwsh -File ./scripts/common/setup-graph-sdk.ps1 -PersistProfile -SetExecutionPolicy

.EXAMPLE
  pwsh -File ./scripts/common/setup-graph-sdk.ps1 -GraphRequiredVersion 2.28.0

.NOTES
  - CI では PersistProfile/SetExecutionPolicy は通常不要。
  - 本ファイルは Public リポジトリ公開を前提に、可読性とコメントを重視している。
#>

[CmdletBinding()] param(
  [string]$ModulesRoot = 'C:\PSModules',
  [string]$GraphRequiredVersion = '',
  [switch]$PersistProfile,
  [switch]$SetExecutionPolicy
)

Write-Host "== Microsoft Graph SDK セットアップ (Save-Module 方式) ==" -ForegroundColor Cyan
Write-Host ("ModulesRoot: {0}" -f $ModulesRoot)

$oneDriveHints = @()
if ($env:OneDrive) { $oneDriveHints += $env:OneDrive }
$odDefault = Join-Path $env:USERPROFILE 'OneDrive'
if (Test-Path $odDefault) { $oneDriveHints += $odDefault }
foreach ($od in $oneDriveHints | Select-Object -Unique) {
  if ($ModulesRoot -like ("{0}*" -f $od)) {
    Write-Warning "ModulesRoot が OneDrive/KFM 配下に見えます: $ModulesRoot"
    Write-Warning "例: C:\PSModules のようなローカル固定パスを推奨します。"
  }
}

if (-not (Test-Path -LiteralPath $ModulesRoot)) {
  New-Item -ItemType Directory -Path $ModulesRoot -Force | Out-Null
  Write-Host " - 作成: $ModulesRoot"
} else {
  Write-Host " - 既存: $ModulesRoot"
}

$paths = $env:PSModulePath -split ';' | Where-Object { $_ }
if ($paths.Count -eq 0 -or $paths[0] -ne $ModulesRoot) {
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
    $guardBegin = '# >>> m365-iac: prepend C\PSModules to PSModulePath >>>'
    $guardEnd   = '# <<< m365-iac <<<'
    $line       = '$env:PSModulePath = "C:\PSModules;" + $env:PSModulePath'

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

try {
  if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
    Write-Host " - NuGet プロバイダーを導入（CurrentUser）"
  }
} catch {
  Write-Warning ("NuGet プロバイダー導入に失敗: {0}" -f $_.Exception.Message)
}

$saveParams = @{
  Name       = 'Microsoft.Graph'
  Repository = 'PSGallery'
  Path       = $ModulesRoot
  Force      = $true
}
if ($GraphRequiredVersion) { $saveParams['RequiredVersion'] = $GraphRequiredVersion }

Write-Host (" - Save-Module Microsoft.Graph -> {0}" -f $ModulesRoot)
try {
  Save-Module @saveParams
} catch {
  Write-Warning ("Save-Module でエラー: {0}" -f $_.Exception.Message)
}

$graphRoot = Join-Path $ModulesRoot 'Microsoft.Graph'
$mods = @()
if (Test-Path -LiteralPath $graphRoot) {
  $mods = Get-ChildItem -LiteralPath $graphRoot -Directory -ErrorAction SilentlyContinue |
          Sort-Object Name -Descending |
          ForEach-Object { [PSCustomObject]@{ Name='Microsoft.Graph'; Version=$_.Name; ModuleBase=$_.FullName } }
}

if ($mods.Count -gt 0) {
  $latest = $mods | Select-Object -First 1
  try {
    Import-Module Microsoft.Graph -RequiredVersion $latest.Version -ErrorAction Stop | Out-Null
    Write-Host (" - Import-Module Microsoft.Graph ({0})" -f $latest.Version) -ForegroundColor Green
  } catch {
    Write-Warning ("Import-Module に失敗: {0}" -f $_.Exception.Message)
  }

  $mods | Format-Table Name,Version,ModuleBase -AutoSize
  Write-Host "== 完了。必要なら PowerShell を再起動すると永続設定が反映されます ==" -ForegroundColor Green
} else {
  Write-Warning ("Microsoft.Graph が {0} に見つかりません。Save-Module のログをご確認ください。" -f $ModulesRoot)
}

$docPath = [Environment]::GetFolderPath('MyDocuments')
$graphInDocs = Join-Path $docPath 'PowerShell\Modules\Microsoft.Graph'
if (Test-Path -LiteralPath $graphInDocs) {
  Write-Warning ("OneDrive/ドキュメント配下にも Microsoft.Graph が見つかりました: {0}" -f $graphInDocs)
  Write-Warning "今後の混乱を避けるため、不要なら削除をご検討ください（現在は ModulesRoot を先頭にしています）。"
}
