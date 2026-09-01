[CmdletBinding()]
param(
  [ValidateSet('debug', 'release')]
  [string]$BuildMode = 'debug',
  [string]$Product = 'default',
  [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$DevEcoRoot = if ($env:DEVECO_HOME) { $env:DEVECO_HOME } else { 'D:\Program Files\Huawei\DevEco Studio' }
$Node = Join-Path $DevEcoRoot 'tools\node\node.exe'
$Hvigor = Join-Path $DevEcoRoot 'tools\hvigor\bin\hvigorw.js'
$env:JAVA_HOME = if ($env:JAVA_HOME) { $env:JAVA_HOME } else { Join-Path $DevEcoRoot 'jbr' }
$env:NODE_HOME = Join-Path $DevEcoRoot 'tools\node'
$env:Path = "$(Join-Path $env:JAVA_HOME 'bin');$env:NODE_HOME;$env:Path"

foreach ($required in @($Node, $Hvigor, (Join-Path $env:JAVA_HOME 'bin\java.exe'))) {
  if (-not (Test-Path -LiteralPath $required)) {
    throw "DevEco tool not found: $required. Set DEVECO_HOME to your DevEco Studio installation directory."
  }
}

Push-Location $ProjectRoot
try {
  if ($Clean) {
    Remove-Item -LiteralPath (Join-Path $ProjectRoot 'entry\build') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $ProjectRoot '.hvigor') -Recurse -Force -ErrorAction SilentlyContinue
  }
  & $Node $Hvigor --no-daemon assembleHap -p "product=$Product" -p "buildMode=$BuildMode"
  if ($LASTEXITCODE -ne 0) {
    throw "Hvigor build failed with exit code $LASTEXITCODE."
  }
} finally {
  Pop-Location
}
