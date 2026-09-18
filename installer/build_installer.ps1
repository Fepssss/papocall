# Script de automacao para compilar o instalador oficial do PapoCall
$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "          PAPOCALL - BUILD INSTALADOR             " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# 1. Garantir que o binário nativo Flutter está compilado
Write-Host "[1/3] Verificando binários nativos Flutter v1.0.0a..." -ForegroundColor Yellow
$flutterExe = "flutter_app\build\windows\x64\runner\Release\papocall.exe"
if (!(Test-Path $flutterExe)) {
    $env:PATH = "E:\DevTools\git\cmd;E:\DevTools\flutter\bin;$env:PATH"
    Push-Location "flutter_app"
    flutter build windows --release
    Pop-Location
}

# 2. Localizar Inno Setup Compiler (ISCC.exe)
Write-Host "[2/3] Localizando compilador Inno Setup..." -ForegroundColor Yellow
$iscc = (Get-ChildItem "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "C:\Program Files*\Inno Setup*\ISCC.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
if (!$iscc -or !(Test-Path $iscc)) {
    throw "Compilador Inno Setup (ISCC.exe) não encontrado."
}

# 3. Compilar setup.iss
Write-Host "[3/3] Compilando PapoCall-Setup.exe..." -ForegroundColor Yellow
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
