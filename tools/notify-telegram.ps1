param(
  [Parameter(Mandatory = $true)]
  [string]$Version,
  [Parameter(Mandatory = $true)]
  [string]$ReleaseUrl,
  [string]$Proxy = ""
)

# Read config
$rootDir = Split-Path -Parent $PSScriptRoot
$configFile = Join-Path $rootDir ".telegram_env"
if (-not (Test-Path $configFile)) {
  Write-Host "ERROR: .telegram_env not found"
  exit 1
}

# Parse config (robust against CRLF / spaces / quotes)
$config = @{}
Get-Content $configFile | ForEach-Object {
  $line = $_.Trim()
  if ($line -match '^(\w+)\s*=\s*(.*)$') {
    $key = $matches[1]
    $val = $matches[2].Trim('"', "'", ' ')
    $config[$key] = $val
  }
}
$token = $config["TOKEN"]
$chatId = $config["CHAT_ID"]
if (-not $token -or -not $chatId) {
  Write-Host "ERROR: missing TOKEN or CHAT_ID"
  exit 1
}

# Resolve proxy: parameter > HTTPS_PROXY > HTTP_PROXY > ALL_PROXY
if (-not $Proxy) {
  if ($env:HTTPS_PROXY) { $Proxy = $env:HTTPS_PROXY }
  elseif ($env:HTTP_PROXY) { $Proxy = $env:HTTP_PROXY }
  elseif ($env:ALL_PROXY) { $Proxy = $env:ALL_PROXY }
}

# Construct message
$msg = "<b>Tieba Lite $Version</b>" + [char]10 + [char]10
$msg = $msg + "<a href=""" + $ReleaseUrl + """>View Release</a>"

# Send
$endpoint = "https://api.telegram.org/bot$token/sendMessage"
$params = @{
  chat_id = $chatId
  text = $msg
  parse_mode = "HTML"
  disable_web_page_preview = $false
}

$irmArgs = @{
  Uri = $endpoint
  Method = "Post"
  Body = $params
  ContentType = "application/x-www-form-urlencoded"
}
if ($Proxy) {
  $irmArgs["Proxy"] = $Proxy
}

try {
  $resp = Invoke-RestMethod @irmArgs
  if ($resp.ok) {
    Write-Host "OK: sent $Version"
  } else {
    Write-Host "ERROR: $($resp.description)"
  }
} catch {
  Write-Host "ERROR: $_"
}
