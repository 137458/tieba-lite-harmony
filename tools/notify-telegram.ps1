param(
  [Parameter(Mandatory = $true)]
  [string]$Version,
  [Parameter(Mandatory = $true)]
  [string]$ReleaseUrl
)

# Read config
$rootDir = Split-Path -Parent $PSScriptRoot
$configFile = Join-Path $rootDir ".telegram_env"
if (-not (Test-Path $configFile)) {
  Write-Host "ERROR: .telegram_env not found"
  exit 1
}

# Parse config
$config = @{}
Get-Content $configFile | ForEach-Object {
  if ($_ -match '^(\w+)="(.+)"$') {
    $config[$matches[1]] = $matches[2]
  }
}
$token = $config["TOKEN"]
$chatId = $config["CHAT_ID"]
if (-not $token -or -not $chatId) {
  Write-Host "ERROR: missing TOKEN or CHAT_ID"
  exit 1
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
try {
  $resp = Invoke-RestMethod -Uri $endpoint -Method Post -Body $params -ContentType "application/x-www-form-urlencoded"
  if ($resp.ok) {
    Write-Host "OK: sent $Version"
  } else {
    Write-Host "ERROR: $($resp.description)"
  }
} catch {
  Write-Host "ERROR: $_"
}