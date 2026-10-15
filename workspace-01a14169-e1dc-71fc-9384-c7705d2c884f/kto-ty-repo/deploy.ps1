# Developer deployment wrapper. No embedded credentials or self-extracting payload.
[CmdletBinding()]
param(
    [string]$Name = 'kto-ty-quiz',
    [string]$DatabaseName = '',
    [string]$DatabaseId = '',
    [string]$AccountId = '',
    [switch]$KeepSecret
)
$ErrorActionPreference = 'Stop'
try {
    # Intentionally resolve paths after parameter binding (Windows PowerShell 5.1).
    $root = $PSScriptRoot
    if (-not $root) { $root = Split-Path -Parent $MyInvocation.MyCommand.Path }
    Set-Location $root
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Install Node.js 22+ LTS and reopen PowerShell.' }
    $version = [string](& node --version)
    if ([int]($version.Trim().TrimStart('v').Split('.')[0]) -lt 22) { throw 'Node.js 22+ is required.' }
    $npm = (Get-Command npm.cmd -ErrorAction SilentlyContinue).Source
    if (-not $npm) { $npm = (Get-Command npm -ErrorAction Stop).Source }
    & $npm ci
    if ($LASTEXITCODE -ne 0) { throw 'npm ci failed.' }
    $env:KTO_WORKER_NAME = $Name
    $env:KTO_DATABASE_NAME = $DatabaseName
    $env:KTO_DATABASE_ID = $DatabaseId
    $env:KTO_ACCOUNT_ID = $AccountId
    $env:KTO_KEEP_SECRET = '0'
    if ($KeepSecret) { $env:KTO_KEEP_SECRET = '1' }
    $temporaryKey = $false
    $secureKey = $null
    if (-not $KeepSecret -and -not $env:GROQ_API_KEY) {
        $secureKey = Read-Host 'Groq key (hidden input)' -AsSecureString
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
        try { $env:GROQ_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr); $temporaryKey = $true }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr); $secureKey.Dispose() }
    }
    try {
        & node deploy.mjs
        if ($LASTEXITCODE -ne 0) { throw 'Deployment failed. See Wrangler output above.' }
    } finally {
        if ($temporaryKey) { Remove-Item Env:GROQ_API_KEY -ErrorAction SilentlyContinue }
    }
} catch {
    Write-Host "DEPLOY FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
