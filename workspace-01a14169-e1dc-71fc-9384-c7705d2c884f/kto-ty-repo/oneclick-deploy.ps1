#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

Write-Host ''
Write-Host '=== kto.ty — one-click deploy to Cloudflare ===' -ForegroundColor Cyan
Write-Host ''

# Node check
try {
    $nodeVersion = (node --version) 2>$null
} catch { $nodeVersion = $null }
if (-not $nodeVersion) {
    Write-Host 'Node.js не найден. Установите Node.js 22 LTS: https://nodejs.org/' -ForegroundColor Red
    Read-Host 'Нажмите Enter для выхода'; exit 1
}
$major = [int]($nodeVersion.TrimStart('v').Split('.')[0])
if ($major -lt 22) {
    Write-Host "Нужен Node.js 22+, у вас $nodeVersion" -ForegroundColor Red
    Read-Host 'Нажмите Enter для выхода'; exit 1
}
Write-Host "Node.js: $nodeVersion" -ForegroundColor Green

# npm ci
Write-Host ''
Write-Host '[1/4] Установка зависимостей (npm ci)...' -ForegroundColor Yellow
npm ci
if ($LASTEXITCODE -ne 0) { Write-Host 'npm ci failed' -ForegroundColor Red; Read-Host 'Enter'; exit 1 }

# Inputs
Write-Host ''
Write-Host '[2/4] Введите данные (они не сохраняются в файлах):' -ForegroundColor Yellow
$groq = Read-Host 'Groq API key (gsk_...)'
if (-not $groq) { Write-Host 'Ключ обязателен' -ForegroundColor Red; Read-Host 'Enter'; exit 1 }

$cfToken = Read-Host 'Cloudflare API Token (cfat_...)'
if (-not $cfToken) { Write-Host 'Токен обязателен' -ForegroundColor Red; Read-Host 'Enter'; exit 1 }

$accountId = Read-Host 'Cloudflare Account ID'
if (-not $accountId) { Write-Host 'Account ID обязателен' -ForegroundColor Red; Read-Host 'Enter'; exit 1 }

$workerName = Read-Host 'Имя воркера (Enter = kto-ty-quiz)'
if (-not $workerName) { $workerName = 'kto-ty-quiz' }

# Env
$env:GROQ_API_KEY = $groq
$env:CLOUDFLARE_API_TOKEN = $cfToken
$env:CLOUDFLARE_ACCOUNT_ID = $accountId
$env:KTO_WORKER_NAME = $workerName
$env:CI = 'true'

# Deploy
Write-Host ''
Write-Host '[3/4] Деплой (D1 + Worker + секрет)...' -ForegroundColor Yellow
npm run deploy:setup
if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host 'Деплой завершился с ошибкой. Проверьте текст выше.' -ForegroundColor Red
    Read-Host 'Нажмите Enter для выхода'; exit 1
}

Write-Host ''
Write-Host '[4/4] Готово! Откройте ссылку *.workers.dev из вывода выше.' -ForegroundColor Green
Write-Host 'Не забудьте перевыпустить ключи, если делились ими.' -ForegroundColor DarkYellow
Read-Host 'Нажмите Enter для выхода'
