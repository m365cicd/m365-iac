function Invoke-WithGraphSession {
<#
.SYNOPSIS
  Microsoft Graph PowerShell SDK セッション管理の共通ラッパー

.DESCRIPTION
  - Microsoft Graph PowerShell SDK を使うスクリプトから共通で呼び出すためのヘルパーです。
  - Graph への接続(Connect)と切断(Disconnect)をまとめて扱います。
  - VS Code / ConsoleHost などホスト差に左右されにくいよう、PSModulePath をプロセス内で補正します。
    (setup-graph-sdk.ps1 のような Profile 永続化に依存しない方針)

.PARAMETER Scopes
  Connect-MgGraph に渡すスコープ配列

.PARAMETER AuthMode
  認証方式:
    - Interactive : ブラウザ認証
    - DeviceCode  : デバイスコード認証

.PARAMETER ContextScope
  Graph SDK のコンテキストスコープ:
    - Process     : この PowerShell プロセスだけ
    - CurrentUser : ユーザーで共有

.PARAMETER ForceReauth
  既に接続済みでも再認証します

.PARAMETER KeepConnected
  実行後に Disconnect しません（開発用）

.PARAMETER ScriptBlock
  接続後に実行する処理
#>

  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Scopes,

    [Parameter()]
    [ValidateSet('Interactive', 'DeviceCode')]
    [string]$AuthMode = 'DeviceCode',

    [Parameter()]
    [ValidateSet('Process', 'CurrentUser')]
    [string]$ContextScope = 'Process',

    [Parameter()]
    [switch]$ForceReauth,

    [Parameter()]
    [switch]$KeepConnected,

    [Parameter(Mandatory = $true)]
    [scriptblock]$ScriptBlock
  )

  function Add-LocalPsModulesToPSModulePath {
    $modulesRoot = Join-Path $env:LOCALAPPDATA 'PSModules'
    if (-not (Test-Path $modulesRoot)) { return }

    $parts = $env:PSModulePath -split ';'
    if ($parts -notcontains $modulesRoot) {
      $env:PSModulePath = "$modulesRoot;$env:PSModulePath"
    }
  }

  function Import-ConnectDelegated {
    $connectScript = Join-Path $PSScriptRoot '..\auth\connect-delegated.ps1'
    $connectScript = (Resolve-Path $connectScript).Path
    . $connectScript
    return $connectScript
  }

  try {
    Add-LocalPsModulesToPSModulePath

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    $connectScriptPath = Import-ConnectDelegated

    $ctx = $null
    try { $ctx = Get-MgContext } catch { $ctx = $null }

    $shouldConnect = $ForceReauth.IsPresent -or (-not $ctx)

    if ($shouldConnect) {
      Write-Host "- Graph 接続を開始します (ContextScope=$ContextScope, AuthMode=$AuthMode)"
      if (Get-Command Connect-Delegated -ErrorAction SilentlyContinue) {
        Connect-Delegated -Scopes $Scopes -AuthMode $AuthMode -ContextScope $ContextScope
      }
      else {
        & $connectScriptPath -Scopes $Scopes -AuthMode $AuthMode -ContextScope $ContextScope
      }
    }
    else {
      Write-Host "- Graph は接続済みです ($($ctx.Account), TenantId=$($ctx.TenantId), Scope=$($ctx.ContextScope))"
    }

    & $ScriptBlock
  }
  finally {
    if (-not $KeepConnected.IsPresent) {
      Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
      Write-Host "- Graph 接続を切断しました (Disconnect-MgGraph)"
    }
    else {
      Write-Host "- KeepConnected 指定のため切断しません"
    }
  }
}
