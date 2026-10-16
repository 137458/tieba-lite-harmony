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

if ($BuildMode -eq 'release') {
  # H/M26 混淆守卫单一事实源：复用独立检查器（与后续 CI 同款逻辑），
  # 检测 -enable-property-obfuscation（v1.2.5 曾因混淆重命名服务器 JSON 字段引发线上事故）
  # & 调用 + 2>&1 捕获：兼容 WindowsApps python 执行别名——PS 5.1 裸调用别名
  # 不会真正启动进程（$LASTEXITCODE 保持空值），守卫会误报失败。
  # 判空用 $null -eq：PS 中 -not 0 为 true，不能用它判断退出码
  $guardOutput = & python (Join-Path $PSScriptRoot 'check-obfuscation-rules.py') $ProjectRoot 2>&1
  $guardOutput | ForEach-Object { Write-Output $_ }
  if ($null -eq $LASTEXITCODE -or $LASTEXITCODE -ne 0) {
    throw 'Release obfuscation guard failed. Remove -enable-property-obfuscation from the rule file (see tools/check-obfuscation-rules.py).'
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
