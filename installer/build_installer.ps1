# Script de automacao para compilar o instalador oficial do PapoCall
$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "          PAPOCALL - BUILD INSTALADOR             " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# 1. A versao nasce de um unico lugar: a constante dentro do proprio aplicativo.
# O atualizador compara numero com numero, entao instalador, manifesto e binario
# tem que carregar exatamente o mesmo MAJOR.MINOR.PATCH — senao quem ja esta no
# ar nunca recebe a novidade, ou recebe uma mais velha que a sua.
Write-Host "[1/6] Lendo a versao oficial do aplicativo..." -ForegroundColor Yellow
$versionFile = "flutter_app\lib\utils\app_version.dart"
$versionLine = Select-String -Path $versionFile -Pattern "const String kAppVersionLabel = '" -SimpleMatch | Select-Object -First 1
if (-not $versionLine) {
    throw "NAO ENCONTRADO o ponto de versionamento em $versionFile."
}
$versaoCasada = [regex]::Match($versionLine.Line, "kAppVersionLabel\s*=\s*'(\d+)\.(\d+)\.(\d+)'")
if (-not $versaoCasada.Success) {
    throw "A versao em $versionFile nao esta no formato MAJOR.MINOR.PATCH (ex.: 1.1.0)."
}
$major = [int]$versaoCasada.Groups[1].Value
$minor = [int]$versaoCasada.Groups[2].Value
$patch = [int]$versaoCasada.Groups[3].Value
$appVersion = "$major.$minor.$patch"
Write-Host "      Versao: v$appVersion" -ForegroundColor DarkGray

# O pubspec precisa concordar: e ele que aparece no window title e nos metadados
# do pacote Flutter. Uma divergencia aqui e sempre esquecimento de quem editou.
$pubspecLinha = Select-String -Path "flutter_app\pubspec.yaml" -Pattern "^version:" | Select-Object -First 1
$padraoEsperado = '^version:\s*' + [regex]::Escape($appVersion) + '(\+|$)'
if (-not ($pubspecLinha.Line -match $padraoEsperado)) {
    throw "pubspec.yaml diz '$($pubspecLinha.Line)' mas o aplicativo esta em v$appVersion. Sincronize as duas linhas."
}

# 2. Definir apenas configuracao PUBLICA para o binario.
# O binario distribuido NUNCA deve conter LIVEKIT_API_KEY / LIVEKIT_API_SECRET:
# o cliente pede o token de voz ao backend, que assina com o segredo no servidor.
Write-Host "[2/6] Preparando configuracao publica do build (sem segredos)..." -ForegroundColor Yellow
$apiUrl = "https://papocall.onrender.com"
$siteUrl = "https://papocall.vercel.app"
if (Test-Path ".env") {
    Get-Content ".env" | ForEach-Object {
        $line = $_.Trim()
        if ($line.StartsWith("PAPOCALL_API_URL=")) { $apiUrl = $line.Substring("PAPOCALL_API_URL=".Length).Replace('"', '').Trim() }
        if ($line.StartsWith("PAPOCALL_SITE_URL=")) { $siteUrl = $line.Substring("PAPOCALL_SITE_URL=".Length).Replace('"', '').Trim() }
    }
}
$siteUrl = $siteUrl.TrimEnd('/')
Write-Host "      API backend: $apiUrl" -ForegroundColor DarkGray
Write-Host "      Site/manifesto: $siteUrl" -ForegroundColor DarkGray

# 3. Compilar binario nativo Flutter para Windows (somente configuracao publica)
Write-Host "[3/6] Compilando Flutter Release v$appVersion para Windows..." -ForegroundColor Yellow
$env:PATH = "E:\DevTools\git\cmd;E:\DevTools\flutter\bin;$env:PATH"
Push-Location "flutter_app"
flutter build windows --release `
    --dart-define=PAPOCALL_API_URL="$apiUrl" `
    --dart-define=PAPOCALL_SITE_URL="$siteUrl"
$buildExit = $LASTEXITCODE
Pop-Location
if ($buildExit -ne 0) { throw "O build do Flutter falhou (codigo $buildExit)." }

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

# 4. Localizar Inno Setup Compiler (ISCC.exe)
Write-Host "[4/6] Localizando compilador Inno Setup..." -ForegroundColor Yellow
$iscc = (Get-ChildItem "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "C:\Program Files*\Inno Setup*\ISCC.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
if (!$iscc -or !(Test-Path $iscc)) {
    throw "Compilador Inno Setup (ISCC.exe) não encontrado."
}

# 5. Compilar setup.iss
Write-Host "[5/6] Compilando PapoCall-Setup.exe v$appVersion..." -ForegroundColor Yellow
& "$iscc" "/DMyAppVersion=$appVersion" "/DVersionInfoNumber=$major.$minor.$patch.0" "installer\setup.iss"

$installerPath = Join-Path $projectRoot "public\downloads\PapoCall-Setup.exe"
if ($LASTEXITCODE -ne 0 -or !(Test-Path $installerPath)) {
    throw "Erro ao gerar instalador."
}

# 6. Publicar o manifesto que o atualizador consulta, com o SHA-256 calculado
# sobre o arquivo recem-compilado. A soma vem do binario, nao de alguem
# digitando: e ela que impede o app de executar um .exe trocado no caminho.
Write-Host "[6/6] Gerando public\version.json com o SHA-256 do instalador..." -ForegroundColor Yellow
$sha256 = (Get-FileHash -Path $installerPath -Algorithm SHA256).Hash.ToLower()
if ($sha256 -notmatch '^[0-9a-f]{64}$') {
    throw "O SHA-256 calculado nao tem a forma esperada: $sha256"
}
$tamanho = (Get-Item $installerPath).Length

$notas = "Melhorias e correcoes desta versao."
$notasArquivo = Join-Path $PSScriptRoot "release_notes.txt"
if (Test-Path $notasArquivo) {
    $notasLidas = (Get-Content $notasArquivo -Raw -Encoding UTF8).Trim()
    if ($notasLidas) { $notas = $notasLidas }
}

$manifesto = [ordered]@{
    version     = $appVersion
    url         = "$siteUrl/downloads/PapoCall-Setup.exe"
    sha256      = $sha256
    sizeBytes   = $tamanho
    notes       = $notas
    publishedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}
$json = $manifesto | ConvertTo-Json

# Sem BOM: o parser JSON do aplicativo recusa um arquivo com byte-order-mark,
# e um manifesto ilegivel deixa todo mundo preso na versao antiga.
$utf8SemBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $projectRoot "public\version.json"), $json, $utf8SemBom)

Copy-Item $installerPath -Destination (Join-Path $projectRoot "PapoCall-Setup.exe") -Force

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "       INSTALADOR GERADO COM SUCESSO!            " -ForegroundColor Green
Write-Host "  Arquivo: PapoCall-Setup.exe v$appVersion" -ForegroundColor Green
Write-Host "  SHA-256: $sha256" -ForegroundColor DarkGray
Write-Host "  Manifesto: public\version.json" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan
