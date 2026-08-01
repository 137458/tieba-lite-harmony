$file = Join-Path (Split-Path -Parent $PSScriptRoot) ".telegram_env"
$config = @{}
Get-Content $file | ForEach-Object {
  if ($_ -match '^(\w+)="(.+)"$') {
    $config[$matches[1]] = $matches[2]
  }
}
$token = $config["TOKEN"]

$uri = "https://api.telegram.org/bot$token/getUpdates"
try {
  $resp = Invoke-RestMethod -Uri $uri -Method Get
  if ($resp.ok) {
    $resp.result | ConvertTo-Json -Depth 10
  } else {
    Write-Host "ERROR: $($resp.description)"
  }
} catch {
  Write-Host "ERROR: $_"
}