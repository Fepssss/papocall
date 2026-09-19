# Script de automacao para compilar o instalador oficial do PapoCall
$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "          PAPOCALL - BUILD INSTALADOR             " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# 1. Carregar credenciais locais do .env para injetar de forma segura no build nativo
Write-Host "[1/4] Carregando credenciais locais para injeção segura no binário..." -ForegroundColor Yellow
$lkUrl = "wss://papocall-9lgrt380.livekit.cloud"
$lkKey = ""
$lkSecret = ""

if (Test-Path ".env") {
    Get-Content ".env" | ForEach-Object {
        $line = $_.Trim()
        if ($line.StartsWith("LIVEKIT_URL=")) { $lkUrl = $line.Substring("LIVEKIT_URL=".Length).Replace('"', '').Trim() }
        if ($line.StartsWith("LIVEKIT_API_KEY=")) { $lkKey = $line.Substring("LIVEKIT_API_KEY=".Length).Replace('"', '').Trim() }
        if ($line.StartsWith("LIVEKIT_API_SECRET=")) { $lkSecret = $line.Substring("LIVEKIT_API_SECRET=".Length).Replace('"', '').Trim() }
    }
}

# 2. Compilar binário nativo Flutter v1.0.0f com as credenciais embutidas
Write-Host "[2/4] Compilando Flutter Release v1.0.0f para Windows..." -ForegroundColor Yellow
$env:PATH = "E:\DevTools\git\cmd;E:\DevTools\flutter\bin;$env:PATH"
Push-Location "flutter_app"
flutter build windows --release --dart-define=LIVEKIT_URL="$lkUrl" --dart-define=LIVEKIT_API_KEY="$lkKey" --dart-define=LIVEKIT_API_SECRET="$lkSecret"
Pop-Location

# Garantir arquivo bundled data/livekit.json para redundância total
$releaseDataDir = "flutter_app\build\windows\x64\runner\Release\data"
if (Test-Path $releaseDataDir) {
    $lkJson = @{ url = $lkUrl; apiKey = $lkKey; apiSecret = $lkSecret } | ConvertTo-Json
    Set-Content -Path "$releaseDataDir\livekit.json" -Value $lkJson -Force
}

# 3. Localizar Inno Setup Compiler (ISCC.exe)
Write-Host "[3/4] Localizando compilador Inno Setup..." -ForegroundColor Yellow
$iscc = (Get-ChildItem "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "C:\Program Files*\Inno Setup*\ISCC.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
if (!$iscc -or !(Test-Path $iscc)) {
    throw "Compilador Inno Setup (ISCC.exe) não encontrado."
}

# 4. Compilar setup.iss
Write-Host "[4/4] Compilando PapoCall-Setup.exe v1.0.0f..." -ForegroundColor Yellow
& "$iscc" "installer\setup.iss"

if ($LASTEXITCODE -eq 0 -and (Test-Path "public\downloads\PapoCall-Setup.exe")) {
    Copy-Item "public\downloads\PapoCall-Setup.exe" -Destination "PapoCall-Setup.exe" -Force
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "       INSTALADOR GERADO COM SUCESSO!            " -ForegroundColor Green
    Write-Host "  Arquivo: PapoCall-Setup.exe" -ForegroundColor Green
    Write-Host "==================================================" -ForegroundColor Cyan
} else {
    throw "Erro ao gerar instalador."
}
