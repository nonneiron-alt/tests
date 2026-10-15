# Run from PowerShell: .\deploy.ps1
# Requires Node.js 20+ and a Cloudflare account. No global npm install needed.
[CmdletBinding()]
param(
    [ValidatePattern('^[a-z0-9][a-z0-9-]{0,48}[a-z0-9]$')]
    [string]$Name = 'kto-ty-quiz',
    [string]$DatabaseName = '',
    [string]$DatabaseId = '',
    [string]$AccountId = '',
    [switch]$SkipLogin,
    [switch]$SkipImport,
    [switch]$KeepSecret
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (-not $DatabaseName) { $DatabaseName = "$Name-db" }
if ($DatabaseName -notmatch '^[a-zA-Z0-9_-]+$') { throw 'DatabaseName may contain letters, numbers, underscores and hyphens only.' }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Install Node.js 20+ from https://nodejs.org/, reopen PowerShell and try again.' }
$nodeVersion = [string](& node --version)
$major = [int]($nodeVersion.Trim().TrimStart('v').Split('.')[0])
if ($major -lt 20) { throw 'Node.js 20+ is required. Install the current LTS release.' }
$script:Npx = (Get-Command npx.cmd -ErrorAction SilentlyContinue).Source
if (-not $script:Npx) { $script:Npx = (Get-Command npx -ErrorAction Stop).Source }
$env:WRANGLER_SEND_METRICS = 'false'
if ($AccountId) { $env:CLOUDFLARE_ACCOUNT_ID = $AccountId }
$utf8 = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = $utf8

function Invoke-Wrangler {
    param([string[]]$WranglerArgs, [switch]$Capture)
    if ($Capture) {
        $lines = & $script:Npx --yes wrangler@4 @WranglerArgs
        if ($LASTEXITCODE -ne 0) { throw "Wrangler failed: $($WranglerArgs -join ' ')" }
        return ($lines -join "`n")
    }
    & $script:Npx --yes wrangler@4 @WranglerArgs
    if ($LASTEXITCODE -ne 0) { throw "Wrangler failed: $($WranglerArgs -join ' ')" }
}

# ConvertFrom-Json handles arrays differently in Windows PowerShell 5.1 and PS7.
# Walk arrays explicitly instead of piping a possibly nested array to Where-Object.
function Find-D1Database {
    param([object]$Value, [string]$TargetName)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Array]) {
        foreach ($item in $Value) {
            $found = Find-D1Database -Value $item -TargetName $TargetName
            if ($null -ne $found) { return $found }
        }
        return $null
    }
    if ($Value -is [string] -or $Value -is [ValueType]) { return $null }
    $nameProperty = $Value.PSObject.Properties['name']
    if ($null -ne $nameProperty -and [string]$nameProperty.Value -eq $TargetName) {
        return $Value
    }
    foreach ($wrapper in @('result', 'results', 'databases', 'data')) {
        $property = $Value.PSObject.Properties[$wrapper]
        if ($null -ne $property) {
            $found = Find-D1Database -Value $property.Value -TargetName $TargetName
            if ($null -ne $found) { return $found }
        }
    }
    return $null
}

try {
    foreach ($file in @('worker.js', 'static/index.html', 'migrations/0001_schema.sql')) {
        if (-not (Test-Path $file)) { throw "Missing $file. Extract the complete deployment package into your quiz folder." }
    }
    Write-Host "`n[1/6] Cloudflare authentication" -ForegroundColor Cyan
    if (-not $SkipLogin -and -not $env:CLOUDFLARE_API_TOKEN) {
        Invoke-Wrangler -WranglerArgs @('login')
    } else {
        Write-Host 'Using existing Wrangler login or CLOUDFLARE_API_TOKEN.'
    }

    Write-Host "`n[2/6] Find or create D1 database: $DatabaseName" -ForegroundColor Cyan
    $uuidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    if ($DatabaseId) {
        $DatabaseId = $DatabaseId.Trim()
        if ($DatabaseId -notmatch $uuidPattern) { throw '-DatabaseId must be an actual D1 UUID from Cloudflare, not the database name.' }
        Write-Host 'Using the explicitly supplied D1 database ID; no database will be created.'
    } else {
        $listJson = Invoke-Wrangler -WranglerArgs @('d1', 'list', '--json') -Capture
        $parsed = ConvertFrom-Json -InputObject $listJson
        $database = Find-D1Database -Value $parsed -TargetName $DatabaseName
        if ($null -eq $database) {
            Invoke-Wrangler -WranglerArgs @('d1', 'create', $DatabaseName)
            $listJson = Invoke-Wrangler -WranglerArgs @('d1', 'list', '--json') -Capture
            $parsed = ConvertFrom-Json -InputObject $listJson
            $database = Find-D1Database -Value $parsed -TargetName $DatabaseName
        }
        foreach ($field in @('uuid', 'database_id', 'id')) {
            if ($null -eq $database) { break }
            $property = $database.PSObject.Properties[$field]
            if ($null -ne $property) {
                $candidate = ([string]$property.Value).Trim()
                if ($candidate -match $uuidPattern) { $DatabaseId = $candidate; break }
            }
        }
        if (-not $DatabaseId) {
            if ($null -ne $database) {
                Write-Host 'Matched D1 record (database metadata only):' -ForegroundColor Yellow
                Write-Host ($database | ConvertTo-Json -Depth 8)
            }
            throw 'Could not parse the D1 ID. Run: npx.cmd --yes wrangler@4 d1 list --json ; then re-run with -DatabaseId followed by the real UUID of your database.'
        }
    }
    $config = [ordered]@{
        name = $Name
        main = 'worker.js'
        compatibility_date = '2025-04-01'
        workers_dev = $true
        assets = [ordered]@{
            directory = './static'
            binding = 'ASSETS'
            run_worker_first = @('/api/*')
        }
        d1_databases = @([ordered]@{
            binding = 'DB'
            database_name = $DatabaseName
            database_id = $databaseId
            migrations_dir = 'migrations'
        })
        observability = @{ enabled = $true }
    }
    if ($AccountId) { $config['account_id'] = $AccountId }
    [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'wrangler.jsonc'), ($config | ConvertTo-Json -Depth 10), $utf8)
    Write-Host "Connected DB: $databaseId"

    Write-Host "`n[3/6] Apply schema and starter quizzes to remote D1" -ForegroundColor Cyan
    Invoke-Wrangler -WranglerArgs @('d1', 'migrations', 'apply', $DatabaseName, '--remote', '--config', 'wrangler.jsonc')

    Write-Host "`n[4/6] Optional import from local quizzes.sqlite3" -ForegroundColor Cyan
    if (-not $SkipImport -and (Test-Path 'quizzes.sqlite3')) {
        $pythonCmd = $null
        foreach ($candidate in @('python', 'py', 'python3')) {
            if (Get-Command $candidate -ErrorAction SilentlyContinue) {
                try { & $candidate -c 'import sqlite3, sys; sys.exit(0)' 2>$null; if ($LASTEXITCODE -eq 0) { $pythonCmd = $candidate; break } } catch { }
            }
        }
        if (-not $pythonCmd) {
            throw 'A local SQLite DB exists but Python is unavailable. Install Python, or use -SkipImport to deploy starter quizzes only.'
        }
        New-Item -ItemType Directory -Path '.deploy' -Force | Out-Null
        try {
            & $pythonCmd 'export_sqlite.py' 'quizzes.sqlite3' '.deploy/import.sql'
            if ($LASTEXITCODE -ne 0) { throw 'SQLite export failed. No local data was changed.' }
            Invoke-Wrangler -WranglerArgs @('d1', 'execute', $DatabaseName, '--remote', '--file', '.deploy/import.sql', '--config', 'wrangler.jsonc')
        } finally {
            # The SQL contains saved results; don't leave a duplicate on disk.
            Remove-Item '.deploy/import.sql' -ErrorAction SilentlyContinue
        }
    } else {
        Write-Host 'Import skipped. Existing cloud data remains untouched.'
    }

    Write-Host "`n[5/6] Deploy Worker and static assets" -ForegroundColor Cyan
    Invoke-Wrangler -WranglerArgs @('deploy', '--config', 'wrangler.jsonc')

    Write-Host "`n[6/6] Configure the server-side Groq secret" -ForegroundColor Cyan
    if ($KeepSecret) {
        $secretJson = Invoke-Wrangler -WranglerArgs @('secret', 'list', '--config', 'wrangler.jsonc') -Capture
        $secrets = @($secretJson | ConvertFrom-Json)
        if (-not ($secrets | Where-Object { $_.name -eq 'GROQ_API_KEY' })) {
            throw 'GROQ_API_KEY does not exist. Re-run without -KeepSecret.'
        }
        Write-Host 'Existing GROQ_API_KEY kept.'
    } else {
        $secureKey = Read-Host 'Paste a NEW Groq API key (input is hidden)' -AsSecureString
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
        $plainKey = $null
        try {
            $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr).Trim()
            if ($plainKey -notmatch '^gsk_\S+$') { throw 'Expected a Groq key beginning with gsk_. Re-run the script to set the secret.' }
            $plainKey | & $script:Npx --yes wrangler@4 secret put GROQ_API_KEY --config wrangler.jsonc
            if ($LASTEXITCODE -ne 0) { throw 'Could not upload GROQ_API_KEY.' }
        } finally {
            $plainKey = $null
            if ($ptr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
            if ($secureKey) { $secureKey.Dispose() }
        }
    }
    Write-Host "`nDEPLOYED! Open the workers.dev URL printed by Wrangler above." -ForegroundColor Green
    Write-Host 'Site files + API: Cloudflare Workers. Database: D1. Model: openai/gpt-oss-120b.'
    Write-Host 'Next deployment: .\deploy.ps1 -SkipLogin -KeepSecret -SkipImport'
    Write-Host 'If you used a custom -Name or -DatabaseName, pass the same values next time.'
} catch {
    Write-Host "`nDEPLOY FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Fix the error and run again. Existing database rows are not deleted.'
    exit 1
}
