param(
  [switch]$SkipFlutterBuild
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$InstallerDir = $PSScriptRoot
$ReleaseDir = Join-Path $ProjectRoot 'build\windows\x64\runner\Release'
$ObjDir = Join-Path $InstallerDir 'obj'
$HarvestFile = Join-Path $InstallerDir 'harvest.wxs'
$OutputMsi = Join-Path $InstallerDir 'POS_APP_Setup.msi'
$WixBin = 'C:\Program Files (x86)\WiX Toolset v3.14\bin'
$Heat = Join-Path $WixBin 'heat.exe'
$Candle = Join-Path $WixBin 'candle.exe'
$Light = Join-Path $WixBin 'light.exe'
$Flutter = 'C:\flutter\bin\flutter.bat'

function Invoke-Checked {
  param(
    [string]$FilePath,
    [string[]]$Arguments
  )

  & $FilePath @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$FilePath failed with exit code $LASTEXITCODE"
  }
}

foreach ($tool in @($Heat, $Candle, $Light)) {
  if (-not (Test-Path $tool)) {
    throw "WiX tool not found: $tool"
  }
}

if (-not $SkipFlutterBuild) {
  Push-Location $ProjectRoot
  try {
    & $Flutter build windows --release
  } finally {
    Pop-Location
  }
}

if (-not (Test-Path (Join-Path $ReleaseDir 'point_of_sale.exe'))) {
  throw "Release build not found. Expected: $ReleaseDir\point_of_sale.exe"
}

New-Item -ItemType Directory -Force $ObjDir | Out-Null
Remove-Item -LiteralPath $HarvestFile -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $OutputMsi -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path $ObjDir -Filter '*.wixobj' -File -ErrorAction SilentlyContinue |
  Remove-Item -Force

& $Heat dir $ReleaseDir `
  -cg ReleaseFiles `
  -dr INSTALLFOLDER `
  -srd `
  -sreg `
  -gg `
  -var var.ReleaseDir `
  -out $HarvestFile
if ($LASTEXITCODE -ne 0) {
  throw "heat.exe failed with exit code $LASTEXITCODE"
}

& $Candle `
  -arch x64 `
  "-dReleaseDir=$ReleaseDir" `
  "-dInstallerDir=$InstallerDir" `
  -out "$ObjDir\" `
  (Join-Path $InstallerDir 'product.wxs') `
  $HarvestFile
if ($LASTEXITCODE -ne 0) {
  throw "candle.exe failed with exit code $LASTEXITCODE"
}

& $Light `
  -ext WixUIExtension `
  -cultures:en-us `
  -sval `
  -out $OutputMsi `
  (Join-Path $ObjDir 'product.wixobj') `
  (Join-Path $ObjDir 'harvest.wixobj')
if ($LASTEXITCODE -ne 0) {
  throw "light.exe failed with exit code $LASTEXITCODE"
}

Write-Host "MSI created: $OutputMsi"
