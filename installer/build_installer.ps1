$ErrorActionPreference = 'Stop'
$compilerPaths = @(
  (Join-Path $PSScriptRoot '..\.tools\InnoSetup\ISCC.exe'),
  'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
  'C:\Program Files\Inno Setup 6\ISCC.exe'
)
$compiler = $compilerPaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $compiler) {
  throw 'Inno Setup 6 is not installed.'
}
& $compiler (Join-Path $PSScriptRoot 'windows_installer.iss')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
