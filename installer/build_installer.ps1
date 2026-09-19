# Script de automacao para compilar o instalador oficial do PapoCall
$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

$appVersion = "1.0.0g"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "          PAPOCALL - BUILD INSTALADOR             " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# 1. Definir apenas configuração PÚBLICA para o binário.
# O binário distribuído NUNCA deve conter LIVEKIT_API_KEY / LIVEKIT_API_SECRET:
# o cliente pede o token de voz ao backend, que assina com o segredo no servidor.
Write-Host "[1/4] Preparando configuracao publica do build (sem segredos)..." -ForegroundColor Yellow
$apiUrl = "https://papocall.vercel.app"
if (Test-Path ".env") {
    Get-Content ".env" | ForEach-Object {
        $line = $_.Trim()
        if ($line.StartsWith("PAPOCALL_API_URL=")) { $apiUrl = $line.Substring("PAPOCALL_API_URL=".Length).Replace('"', '').Trim() }
    }
}
Write-Host "      API backend: $apiUrl" -ForegroundColor DarkGray

# 2. Compilar binário nativo Flutter para Windows (somente configuração pública)
Write-Host "[2/4] Compilando Flutter Release v$appVersion para Windows..." -ForegroundColor Yellow
$env:PATH = "E:\DevTools\git\cmd;E:\DevTools\flutter\bin;$env:PATH"
Push-Location "flutter_app"
flutter build windows --release --dart-define=PAPOCALL_API_URL="$apiUrl"
Pop-Location

# Remove qualquer livekit.json legado deixado por builds antigos antes de empacotar.
# Builds anteriores a v1.0.0g gravavam a chave da API em texto puro neste arquivo.
$releaseDataDir = "flutter_app\build\windows\x64\runner\Release\data"
$legacySecret = Join-Path $releaseDataDir "livekit.json"
if (Test-Path $legacySecret) {
    Remove-Item $legacySecret -Force
    Write-Host "      Removido livekit.json legado do diretorio de build." -ForegroundColor DarkYellow
}

# Trava de seguranca: aborta se algum segredo tiver entrado no pacote
$leak = Get-ChildItem $releaseDataDir -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'livekit\.json|\.env' }
if ($leak) {
    throw "BUILD ABORTADO: arquivo de credenciais encontrado no pacote: $($leak.FullName)"
}

# 3. Localizar Inno Setup Compiler (ISCC.exe)
Write-Host "[3/4] Localizando compilador Inno Setup..." -ForegroundColor Yellow
$iscc = (Get-ChildItem "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "C:\Program Files*\Inno Setup*\ISCC.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
if (!$iscc -or !(Test-Path $iscc)) {
    throw "Compilador Inno Setup (ISCC.exe) não encontrado."
}

# 4. Compilar setup.iss
Write-Host "[4/4] Compilando PapoCall-Setup.exe v$appVersion..." -ForegroundColor Yellow
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
