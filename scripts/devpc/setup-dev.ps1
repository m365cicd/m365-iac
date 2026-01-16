[CmdletBinding()]
param(
  [string]$ModulesRoot = 'C:\PSModules',
  [string]$GraphRequiredVersion = ''
)

function Test-Pwsh {
  try {
    $v = & pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>$null
    return [bool]$v
  } catch { return $false }
}

Write-Host "== 開発PC セットアップ ==" -ForegroundColor Cyan

if (-not (Test-Pwsh)) {
  Write-Host " - PowerShell 7 (pwsh) が見つかりません。winget で導入を試みます..."
  try {
    winget install --id Microsoft.PowerShell --source winget --silent --accept-source-agreements --accept-package-agreements
    Write-Host " - PowerShell 7 の導入を完了（新しい pwsh セッションで反映）"
  } catch {
    Write-Warning "PowerShell 7 の導入に失敗: $($_.Exception.Message)。MSI 等で手動導入してください。"
  }
} else {
  Write-Host " - PowerShell 7 (pwsh) 検出済み"
}

$common = Join-Path $PSScriptRoot '..\common\setup-graph-sdk.ps1' | Resolve-Path
& pwsh -NoProfile -File $common `
  -ModulesRoot $ModulesRoot `
  -GraphRequiredVersion $GraphRequiredVersion `
  -PersistProfile `
  -SetExecutionPolicy
