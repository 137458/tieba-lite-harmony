param(
  [string]$StateFile = ""
)

if (-not $StateFile) {
  $StateFile = Join-Path $PSScriptRoot "feedback-bot-state.json"
}

$token = $env:TELEGRAM_TOKEN
$meowNick = $env:MEOW_NICKNAME

if (-not $token) {
  $cfgFile = Join-Path (Split-Path -Parent $PSScriptRoot) ".telegram_env"
  $config = @{}
  Get-Content $cfgFile | ForEach-Object {
    if ($_ -match '^(\w+)="(.+)"$') {
      $config[$matches[1]] = $matches[2]
    }
  }
  $token = $config["TOKEN"]
}

if (-not $token) {
  Write-Host "ERROR: TELEGRAM_TOKEN not set"
  exit 1
}

function UrlEncode([string]$s) {
  return [System.Uri]::EscapeDataString($s)
}

$lastUpdateId = 0
if (Test-Path $StateFile) {
  try {
    $state = Get-Content $StateFile -Raw | ConvertFrom-Json
    $lastUpdateId = [int]$state.last_update_id
  } catch {
    Write-Host "WARN: could not read state file"
  }
}
Write-Host ("Last update_id: " + $lastUpdateId)

$targetChatIds = @(-1004359764225)
$offset = $lastUpdateId + 1
$uri = "https://api.telegram.org/bot" + $token + "/getUpdates?offset=" + $offset + "&timeout=5&allowed_updates=%5B%22message%22%5D"

try {
  $resp = Invoke-RestMethod -Uri $uri -Method Get
  if ($resp.ok) {
    $updates = $resp.result
    Write-Host ("Received " + $updates.Length + " update(s)")
    $maxUpdateId = $lastUpdateId

    foreach ($update in $updates) {
      if ($update.update_id -gt $maxUpdateId) {
        $maxUpdateId = $update.update_id
      }

      $msg = $update.message
      if (-not $msg) { continue }

      $chatId = $msg.chat.id
      if ($targetChatIds -notcontains $chatId) { continue }

      $text = $msg.text
      if (-not $text) { continue }

      Write-Host ("Message: " + $text)

      if ($text -match '^/feedback(@\w+)?\s*(.*)') {
        $feedbackContent = $matches[2]
        if (-not $feedbackContent) { $feedbackContent = "(empty)" }

        $senderName = $msg.from.first_name
        if ($msg.from.username) { $senderName = "@" + $msg.from.username }

        Write-Host ("Feedback from " + $senderName + ": " + $feedbackContent)

        if ($meowNick) {
          $meowMsg = "[" + $senderName + "] " + $feedbackContent
          $meowUrl = "https://api.chuckfang.com/" + $meowNick + "/" + (UrlEncode "Tieba Feedback") + "/" + (UrlEncode $meowMsg)
          try {
            $meowResp = Invoke-RestMethod -Uri $meowUrl -Method Get
            if ($meowResp.status -eq 200) {
              Write-Host "MeoW push OK"
            } else {
              Write-Host "MeoW error: " + $meowResp.msg
            }
          } catch {
            Write-Host "MeoW failed: " + $_
          }
        }

        $replyUri = "https://api.telegram.org/bot" + $token + "/sendMessage"
        $replyParams = @{
          chat_id = $chatId
          text = "Thank you for your feedback! The developer will review it soon."
          reply_to_message_id = $msg.message_id
        }
        try {
          $replyResp = Invoke-RestMethod -Uri $replyUri -Method Post -Body $replyParams -ContentType "application/x-www-form-urlencoded"
          if ($replyResp.ok) {
            Write-Host "Reply sent OK"
          } else {
            Write-Host "Reply error: " + $replyResp.description
          }
        } catch {
          Write-Host "Reply failed: " + $_
        }
      }
    }

    if ($maxUpdateId -gt $lastUpdateId) {
      $state = "{`"last_update_id`": " + $maxUpdateId + "}"
      [System.IO.File]::WriteAllText($StateFile, $state)
      Write-Host ("State saved: update_id = " + $maxUpdateId)
    } else {
      Write-Host "No new updates"
    }
  } else {
    Write-Host "ERROR: " + $resp.description
  }
} catch {
  Write-Host "ERROR: " + $_
}