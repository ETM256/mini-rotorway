param(
    [string]$Output = "MiniMotorwaysRBX.rbxlx"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$toolDir = Join-Path $env:TEMP "mini-motorways-rbx-tools"
$rojo = Join-Path $toolDir "rojo.exe"

if (-not (Test-Path $rojo)) {
    Write-Host "Telechargement de Rojo..."
    New-Item -ItemType Directory -Force -Path $toolDir | Out-Null
    $zip = Join-Path $toolDir "rojo.zip"
    Invoke-WebRequest -Uri "https://github.com/rojo-rbx/rojo/releases/download/v7.7.1/rojo-7.7.1-windows-x86_64.zip" -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $toolDir -Force
}

$outPath = Join-Path $root $Output
& $rojo build (Join-Path $root "default.project.json") -o $outPath

# Roblox Studio serialise les sources en ProtectedString : on aligne le fichier.
if (Get-Command node -ErrorAction SilentlyContinue) {
    node (Join-Path $PSScriptRoot "fix-source-tags.js") $outPath
} else {
    Write-Host "Node introuvable : le fichier reste lisible, mais garde ses balises <string>."
}

Write-Host ""
Write-Host "Pret : $outPath"
Write-Host "Ouvre-le dans Roblox Studio (File > Open from File) puis appuie sur Play."
