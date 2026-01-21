#Requires -Version 7.0
<#
.SYNOPSIS
Intune の「エンドポイント セキュリティ | ウイルス対策 (Microsoft Defender Antivirus / MDAV)」ポリシーを
Microsoft Graph API から取得して JSON にエクスポートします。

.DESCRIPTION
Intune ポータル上の場所：
  エンドポイント セキュリティ > ウイルス対策

Graph 取得方針（利用するAPIと抽出方法）：
  1) ポリシー一覧（エンドポイント セキュリティ全般を含む）
     GET https://graph.microsoft.com/{apiVersion}/deviceManagement/configurationPolicies?$top=200
     → templateReference.templateFamily == "endpointSecurityAntivirus" のみ抽出

  2) ポリシーのメタ情報（ポリシー名・テンプレートなど）
     GET https://graph.microsoft.com/{apiVersion}/deviceManagement/configurationPolicies/{policyId}

  3) 各ポリシーの設定内容（Intune UI と同等の “各項目の値” を復元するための材料）
     GET https://graph.microsoft.com/{apiVersion}/deviceManagement/configurationPolicies/{policyId}/settings?$top=200&$expand=settingDefinitions
     → settingDefinitions.options から “選択肢名/値” を解決して JSON に入れる

.NOTES
- Graph SDK の読み込みや PSModulePath 補正は Invoke-WithGraphSession.ps1 側で面倒を見る設計です。
- 認証方式の既定は Interactive（対話サインイン）です。
  DeviceCode は “状況によって” 便利ですが、セキュリティ/運用上の懸念があるため既定にはしません。
- ContextScope の既定は Process（永続化しない）です。
- 出力先を増やしすぎないため、デフォルト出力先は `_local/exports/intune/mdav/` です。
  （CI/CDで公開エクスポートしたい場合は -OutputDir を `iac/...` に指定してください）

.PARAMETER ApiVersion
Graph の API バージョン。既定は beta。
Intune 系は beta の方が情報が揃うケースがあるため、既定は beta にしています。

.PARAMETER OutputDir
エクスポート先ディレクトリ（既定: _local/exports/intune/mdav）

.PARAMETER AuthMode
Graph 接続方式。Interactive / DeviceCode のみ。
このリポジトリ方針として既定は Interactive です。

.PARAMETER ContextScope
Graph SDK のコンテキスト保持スコープ（Process / CurrentUser）
このリポジトリ方針として既定は Process です。

.EXAMPLE
# 既定値で実行：
#   ApiVersion   = beta
#   AuthMode     = Interactive
#   ContextScope = Process
#   OutputDir    = _local/exports/intune/mdav/
pwsh -File ./scripts/intune/export-mdav-policy.ps1

.EXAMPLE
# API v1.0 を指定して実行（動く場合はこれでもOK）：
#   ApiVersion   = v1.0
#   AuthMode     = Interactive
#   ContextScope = Process
pwsh -File ./scripts/intune/export-mdav-policy.ps1 -ApiVersion v1.0

.EXAMPLE
# （非推奨 / 例外用途）DeviceCode で実行したい場合：
pwsh -File ./scripts/intune/export-mdav-policy.ps1 -AuthMode DeviceCode

.EXAMPLE
# 出力先を iac 配下へ変更（公開/非公開は運用で判断）
pwsh -File ./scripts/intune/export-mdav-policy.ps1 -OutputDir ./iac/intune/mdav

.LINK
https://learn.microsoft.com/en-us/graph/api/intune-deviceconfigv2-devicemanagementconfigurationpolicy-list?view=graph-rest-beta
https://learn.microsoft.com/en-us/graph/api/intune-deviceconfigv2-devicemanagementconfigurationsetting-create?view=graph-rest-beta
#>

[CmdletBinding()]
param(
  [ValidateSet('beta', 'v1.0')]
  [string]$ApiVersion = 'beta',

  # ✅ リポジトリ方針：既定は Interactive
  [ValidateSet('Interactive', 'DeviceCode')]
  [string]$AuthMode = 'Interactive',

  # ✅ リポジトリ方針：既定は Process
  [ValidateSet('Process', 'CurrentUser')]
  [string]$ContextScope = 'Process',

  [string]$OutputDir
)

# -----------------------------
# Resolve paths
# -----------------------------
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$defaultOutput = Join-Path $repoRoot '_local\exports\intune\mdav'
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
  $OutputDir = $defaultOutput
}

# Resolve-Path できない（未作成）場合もあるので握りつぶす
$resolved = Resolve-Path -Path $OutputDir -ErrorAction SilentlyContinue
if ($resolved) { $OutputDir = $resolved.Path }

# -----------------------------
# Import helper (Graph session wrapper)
# -----------------------------
# ✅ scripts/utils または scripts/auth のどちらにも対応する（壊れにくい）
$invokeCandidates = @(
  (Join-Path $PSScriptRoot '..\utils\Invoke-WithGraphSession.ps1'),
  (Join-Path $PSScriptRoot '..\auth\Invoke-WithGraphSession.ps1')
)

$invokeWithGraphSessionPath = $invokeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $invokeWithGraphSessionPath) {
  throw "Invoke-WithGraphSession.ps1 が見つかりません: `n- $($invokeCandidates -join "`n- ")"
}

. $invokeWithGraphSessionPath

# -----------------------------
# Small helpers
# -----------------------------
function New-SafeFileName {
  param([Parameter(Mandatory)][string]$Name)

  $safe = $Name
  foreach ($c in [IO.Path]::GetInvalidFileNameChars()) {
    $safe = $safe.Replace($c, '_')
  }
  $safe = $safe -replace '\s+', ' '
  $safe = $safe.Trim()
  if ($safe.Length -gt 80) { $safe = $safe.Substring(0, 80).Trim() }
  return $safe
}

function Ensure-Directory {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Get-GraphAllPages {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Uri
  )

  $items = New-Object System.Collections.Generic.List[object]
  $next = $Uri

  while ($null -ne $next -and $next -ne '') {
    $resp = Invoke-MgGraphRequest -Method GET -Uri $next -OutputType PSObject

    if ($resp -and $resp.PSObject.Properties.Name -contains 'value') {
      foreach ($v in $resp.value) { $items.Add($v) }
    }
    else {
      if ($resp) { $items.Add($resp) }
    }

    if ($resp -and ($resp.PSObject.Properties.Name -contains '@odata.nextLink')) {
      $next = $resp.'@odata.nextLink'
    }
    else {
      $next = $null
    }
  }

  return $items
}

function Convert-SettingInstanceToExportValue {
  param(
    [Parameter(Mandatory)]$SettingInstance,
    $SettingDefinition
  )

  $odataType = $SettingInstance.'@odata.type'

  # 1) Choice Setting
  if ($SettingInstance.PSObject.Properties.Name -contains 'choiceSettingValue') {
    $selectedOptionId = $SettingInstance.choiceSettingValue.value

    $option = $null
    if ($SettingDefinition -and ($SettingDefinition.PSObject.Properties.Name -contains 'options')) {
      $option = $SettingDefinition.options | Where-Object { $_.itemId -eq $selectedOptionId } | Select-Object -First 1
    }

    $selectedOptionValue = $null
    if ($option -and $option.PSObject.Properties.Name -contains 'optionValue') {
      if ($option.optionValue -and ($option.optionValue.PSObject.Properties.Name -contains 'value')) {
        $selectedOptionValue = $option.optionValue.value
      }
    }

    return [ordered]@{
      instanceType          = 'choice'
      selectedOptionId      = $selectedOptionId
      selectedOptionName    = $option.name
      selectedOptionDisplay = $option.displayName
      selectedOptionValue   = $selectedOptionValue
    }
  }

  # 2) Simple Setting
  if ($SettingInstance.PSObject.Properties.Name -contains 'simpleSettingValue') {
    $sv = $SettingInstance.simpleSettingValue
    return [ordered]@{
      instanceType = 'simple'
      valueType    = $sv.'@odata.type'
      value        = $sv.value
    }
  }

  # 3) Choice Setting Collection
  if ($SettingInstance.PSObject.Properties.Name -contains 'choiceSettingCollectionValue') {
    return [ordered]@{
      instanceType = $odataType
      raw          = $SettingInstance
    }
  }

  # 4) その他（未知の型）
  return [ordered]@{
    instanceType = $odataType
    raw          = $SettingInstance
  }
}

# -----------------------------
# Main
# -----------------------------
Write-Host "== Export MDAV policy (Endpoint Security / Antivirus) ==" -ForegroundColor Cyan
Write-Host ("ApiVersion   : {0}" -f $ApiVersion)
Write-Host ("OutputDir    : {0}" -f $OutputDir)
Write-Host ("AuthMode     : {0}" -f $AuthMode)
Write-Host ("ContextScope : {0}" -f $ContextScope)

Ensure-Directory -Path $OutputDir

# Graph Scopes（読み取り用途）
$scopes = @(
  'DeviceManagementConfiguration.Read.All'
)

Invoke-WithGraphSession -Scopes $scopes -AuthMode $AuthMode -ContextScope $ContextScope {
  $templateFamily = 'endpointSecurityAntivirus'

  # 1) ポリシー一覧を取得して Antivirus のみ抽出
  $listUri = "https://graph.microsoft.com/$ApiVersion/deviceManagement/configurationPolicies?`$top=200"
  $allPolicies = Get-GraphAllPages -Uri $listUri

  $targetPolicies = $allPolicies |
    Where-Object {
      $_.templateReference -and
      $_.templateReference.templateFamily -eq $templateFamily
    }

  if (-not $targetPolicies -or $targetPolicies.Count -eq 0) {
    Write-Host "対象ポリシーが見つかりませんでした（templateFamily=$templateFamily）" -ForegroundColor Yellow
    return
  }

  Write-Host ("Antivirus policies found: {0}" -f $targetPolicies.Count) -ForegroundColor Green

  foreach ($p in $targetPolicies) {
    $policyId = $p.id
    $policyName = $p.name

    Write-Host ""
    Write-Host ("--- {0} ({1})" -f $policyName, $policyId) -ForegroundColor Cyan

    # 2) ポリシーのメタ情報
    $policyMetaUri = "https://graph.microsoft.com/$ApiVersion/deviceManagement/configurationPolicies/$policyId"
    $policyMeta = Invoke-MgGraphRequest -Method GET -Uri $policyMetaUri -OutputType PSObject

    # 3) 設定内容（設定定義を expand して UI 相当の情報に寄せる）
    $settingsUri = "https://graph.microsoft.com/$ApiVersion/deviceManagement/configurationPolicies/$policyId/settings?`$top=200&`$expand=settingDefinitions"
    $settingsRows = Get-GraphAllPages -Uri $settingsUri

    $exportSettings = @()

    foreach ($row in $settingsRows) {
      $inst = $row.settingInstance
      if (-not $inst) { continue }

      $def = $null
      if ($row.PSObject.Properties.Name -contains 'settingDefinitions') {
        $def = $row.settingDefinitions | Select-Object -First 1
      }

      $exportSettings += [ordered]@{
        settingDefinitionId = $inst.settingDefinitionId
        displayName         = $def.displayName
        name                = $def.name
        description         = $def.description
        baseUri             = $def.baseUri
        offsetUri           = $def.offsetUri
        value               = (Convert-SettingInstanceToExportValue -SettingInstance $inst -SettingDefinition $def)
      }
    }

    $exportObject = [ordered]@{
      exportedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
      apiVersion    = $ApiVersion
      policy        = [ordered]@{
        id                     = $policyMeta.id
        name                   = $policyMeta.name
        description            = $policyMeta.description
        platforms              = $policyMeta.platforms
        technologies           = $policyMeta.technologies
        templateFamily         = $policyMeta.templateReference.templateFamily
        templateId             = $policyMeta.templateReference.templateId
        templateDisplayName    = $policyMeta.templateReference.templateDisplayName
        templateDisplayVersion = $policyMeta.templateReference.templateDisplayVersion
        settingCount           = $policyMeta.settingCount
        createdDateTime        = $policyMeta.createdDateTime
        lastModifiedDateTime   = $policyMeta.lastModifiedDateTime
      }
      settings      = $exportSettings
    }

    $safeName = New-SafeFileName -Name $policyMeta.name
    $fileName = "{0}-{1}-{2}.json" -f $templateFamily, $safeName, $policyMeta.id
    $outPath = Join-Path $OutputDir $fileName

    $json = $exportObject | ConvertTo-Json -Depth 60
    $json | Set-Content -Path $outPath -Encoding utf8NoBOM

    Write-Host ("Exported: {0}" -f $outPath) -ForegroundColor Green
  }
}
