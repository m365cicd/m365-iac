[CmdletBinding()]
param(
  [string]$ModulesRoot = 'C:\PSModules',
  [string]$GraphRequiredVersion = ''
)

$common = Join-Path $PSScriptRoot '..\common\setup-graph-sdk.ps1' | Resolve-Path

# CI は永続化・実行ポリシー変更なし
& pwsh -NoProfile -File $common `
  -ModulesRoot $ModulesRoot `
  -GraphRequiredVersion $GraphRequiredVersion
