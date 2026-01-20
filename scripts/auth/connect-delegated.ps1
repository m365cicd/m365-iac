<#
.SYNOPSIS
  Microsoft Graph PowerShell SDK の委任（Delegated）認証を共通化するヘルパー

.DESCRIPTION
  Microsoft Graph PowerShell SDK（Connect-MgGraph）を利用したスクリプトで、
  毎回同じ「ログイン処理」を書かないための共通認証スクリプトです。

  - 既定は Interactive 認証（ブラウザ/OS の認証UI）を使用します。
  - GUI が出せない環境・UI が開かない環境では Device Code 認証を選択できます。
  - 取得したコンテキスト（Get-MgContext）が要求スコープを満たす場合は再ログインしません。
  - Public リポジトリ前提のため、資格情報（秘密情報）は扱いません。

  ★Conditional Access (CA) の注意
  - Device Code フローはセキュリティ観点で「可能ならブロック推奨」とされるケースが多く、
    テナントによっては CA で明示的にブロックされます。
  - そのため、既定は Interactive を推奨し、Device Code は “逃げ道” として提供します。

.PARAMETER Scopes
  Connect-MgGraph に渡す委任権限スコープ配列。
  例: "User.Read", "DeviceManagementConfiguration.Read.All"

.PARAMETER TenantId
  接続先の Tenant Id (GUID) または audience（organizations / common / consumers）。
  未指定なら既定テナント。

.PARAMETER AuthMode
  認証方式。
  - Interactive : 既定。ブラウザ/OS 認証UIでサインイン
  - DeviceCode  : 端末コードフロー（GUIが出せない環境向け）

.PARAMETER ContextScope
  トークンキャッシュのスコープ。
  - Process     : この PowerShell プロセス内だけ（既定、事故りにくい）
  - CurrentUser : ユーザーで共有（複数セッションで使い回す）

.PARAMETER ForceReauth
  既存の接続状態があっても Disconnect → 再認証します。

.PARAMETER ShowWelcome
  Connect-MgGraph の Welcome 表示を抑制しません（既定は抑制）。

.EXAMPLE
  # 既定（Interactive）
  .\scripts\auth\connect-delegated.ps1 -Scopes "User.Read"

.EXAMPLE
  # GUIが出せない/Interactiveが不安定 → Device Code
  .\scripts\auth\connect-delegated.ps1 -AuthMode DeviceCode -Scopes "User.Read"

.EXAMPLE
  # 他スクリプトから dot-source して関数として利用
  . "$PSScriptRoot\connect-delegated.ps1"
  Connect-M365GraphDelegated -Scopes "User.Read" -AuthMode Interactive

.NOTES
  - Connect-MgGraph の -UseDeviceCode は Device Code 認証を選択します。
  - Device Code は組織によって CA でブロックされることがあります。

.REFERENCES
  - Connect-MgGraph (Microsoft Learn)
    https://learn.microsoft.com/powershell/module/microsoft.graph.authentication/connect-mggraph
  - Microsoft Graph PowerShell: authentication commands
    https://learn.microsoft.com/powershell/microsoftgraph/authentication-commands
  - 条件付きアクセス: 認証フロー（Device Code フローの制御）
    https://learn.microsoft.com/ja-jp/entra/identity/conditional-access/policy-block-authentication-flows
#>

[CmdletBinding()]
param(
  [string[]]$Scopes = @('User.Read'),
  [string]$TenantId = '',
  [ValidateSet('Interactive','DeviceCode')]
  [string]$AuthMode = 'Interactive',
  [ValidateSet('Process','CurrentUser')]
  [string]$ContextScope = 'Process',
  [switch]$ForceReauth,
  [switch]$ShowWelcome
)

$ErrorActionPreference = 'Stop'

function Assert-GraphAuthModule {
  # Connect-MgGraph は Microsoft.Graph.Authentication に含まれる
  $modName = 'Microsoft.Graph.Authentication'
  if (-not (Get-Module -ListAvailable $modName)) {
    Write-Error @"
Microsoft Graph Authentication モジュールが見つかりません: $modName
先に scripts/setup/setup-dev.ps1 または scripts/setup/setup-graph-sdk.ps1 を実行してください。
"@
    throw "Missing module: $modName"
  }

  try {
    Import-Module $modName -Force -ErrorAction Stop | Out-Null
  } catch {
    Write-Error "Import-Module $modName に失敗: $($_.Exception.Message)"
    throw
  }
}

function Test-ScopesSatisfied {
  param(
    [Parameter(Mandatory)][string[]]$Required,
    [Parameter(Mandatory)][string[]]$Granted
  )
  # Graph の Scopes は大文字小文字が揺れることがあるので case-insensitive で比較
  $g = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($s in $Granted) { [void]$g.Add($s) }

  foreach ($r in $Required) {
    if (-not $g.Contains($r)) { return $false }
  }
  return $true
}

function Connect-M365GraphDelegated {
  [CmdletBinding()]
  param()

  Assert-GraphAuthModule

  # 既存コンテキスト確認
  $ctx = $null
  try { $ctx = Get-MgContext -ErrorAction SilentlyContinue } catch {}

  if ($ForceReauth -and $ctx) {
    try {
      Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
      Write-Host " - Disconnect-MgGraph: done (ForceReauth)" -ForegroundColor DarkGray
    } catch {}
    $ctx = $null
  }

  # 既に要求スコープを満たしているなら再ログイン不要
  if ($ctx -and $ctx.Scopes -and (Test-ScopesSatisfied -Required $Scopes -Granted $ctx.Scopes)) {
    Write-Host "== 既に接続済み（要求スコープを満たしています）==" -ForegroundColor Green
    Write-Host ("Account : {0}" -f $ctx.Account) -ForegroundColor DarkGray
    Write-Host ("Tenant  : {0}" -f $ctx.TenantId) -ForegroundColor DarkGray
    Write-Host ("Scopes  : {0}" -f ($ctx.Scopes -join ', ')) -ForegroundColor DarkGray
    return $ctx
  }

  # Connect-MgGraph 引数組み立て
  $connectParams = @{
    Scopes       = $Scopes
    ContextScope = $ContextScope
  }
  if (-not $ShowWelcome) { $connectParams['NoWelcome'] = $true }
  if ($TenantId) { $connectParams['TenantId'] = $TenantId }

  if ($AuthMode -eq 'DeviceCode') {
    # 公式パラメータ: -UseDeviceCode（別名もあるが正式名で統一）
    $connectParams['UseDeviceCode'] = $true
  }

  Write-Host "== Connect-MgGraph（Delegated）==" -ForegroundColor Cyan
  Write-Host ("AuthMode     : {0}" -f $AuthMode) -ForegroundColor DarkGray
  Write-Host ("ContextScope : {0}" -f $ContextScope) -ForegroundColor DarkGray
  Write-Host ("TenantId     : {0}" -f ($(if($TenantId){$TenantId}else{'(default)'}))) -ForegroundColor DarkGray
  Write-Host ("Scopes       : {0}" -f ($Scopes -join ', ')) -ForegroundColor DarkGray

  try {
    Connect-MgGraph @connectParams | Out-Null
  } catch {
    Write-Warning "Connect-MgGraph に失敗: $($_.Exception.Message)"

    if ($AuthMode -eq 'DeviceCode') {
      Write-Warning "Device Code フローは Conditional Access でブロックされることがあります。"
      Write-Warning "Interactive に切り替えるか、テナント管理者に許可可否を確認してください。"
    } else {
      Write-Warning "Interactive UI が出ない場合、-AuthMode DeviceCode を試してください。"
    }
    throw
  }

  # 接続後のコンテキスト確認
  $ctx2 = $null
  try { $ctx2 = Get-MgContext -ErrorAction SilentlyContinue } catch {}

  if (-not $ctx2) {
    Write-Warning "接続後に Get-MgContext が取得できませんでした（環境依存の可能性）。"
    return $null
  }

  Write-Host "== Connected ==" -ForegroundColor Green
  Write-Host ("Account : {0}" -f $ctx2.Account) -ForegroundColor DarkGray
  Write-Host ("Tenant  : {0}" -f $ctx2.TenantId) -ForegroundColor DarkGray
  Write-Host ("Scopes  : {0}" -f ($ctx2.Scopes -join ', ')) -ForegroundColor DarkGray
  return $ctx2
}

# --- 実行方法 ---------------------------------------------------------
# 1) スクリプト単体実行: そのまま接続する
# 2) dot-source: 関数だけ読み込んで、呼び出し側が実行する
if ($MyInvocation.InvocationName -ne '.') {
  Connect-M365GraphDelegated
}
