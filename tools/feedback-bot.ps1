param(
  [string]$StateFile = ""
)

if (-not $StateFile) {
  $StateFile = Join-Path $PSScriptRoot "feedback-bot-state.json"
}

# Read config
$token = $env:TELEGRAM_TOKEN
$meowNick = $env:MEOW_NICKNAME
$githubToken = $env:GITHUB_TOKEN
$githubRepo = $env:GITHUB_REPO

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

if (-not $githubRepo) { $githubRepo = "137458/tieba-lite-harmony" }

function UrlEncode([string]$s) {
  return [System.Uri]::EscapeDataString($s)
}

function Push-MeoW([string]$sender, [string]$content) {
  if (-not $meowNick) { return }
  try {
    $msg = "[$sender] $content"
    $url = "https://api.chuckfang.com/$meowNick/$(UrlEncode 'Tieba Feedback')/$(UrlEncode $msg)"
    $resp = Invoke-RestMethod -Uri $url -Method Get
    if ($resp.status -eq 200) { Write-Host "MeoW push OK" }
    else { Write-Host "MeoW error: $($resp.msg)" }
  } catch { Write-Host "MeoW failed: $_" }
}

function New-GitHubIssue([string]$sender, [string]$content) {
  if (-not $githubToken) { return "" }
  try {
    $title = "[Feedback] $($content.Substring(0, [Math]::Min(50, $content.Length)))"
    if ($content.Length -gt 50) { $title += "..." }
    $body = "**来自:** $sender`n`n**反馈内容:**`n$content`n`n---`n*Automated feedback from Telegram group*"
    $headers = @{
      Authorization = "Bearer $githubToken"
      Accept = "application/vnd.github+json"
    }
    $bodyJson = @{
      title = $title
      body = $body
      labels = @("feedback")
    } | ConvertTo-Json
    $uri = "https://api.github.com/repos/$githubRepo/issues"
    $resp = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $bodyJson -ContentType "application/json"
    Write-Host "GitHub Issue created: $($resp.html_url)"
    return $resp.html_url
  } catch {
    Write-Host "GitHub Issue failed: $_"
    return ""
  }
}

# Read last update_id
$lastUpdateId = 0
if (Test-Path $StateFile) {
  try {
    $state = Get-Content $StateFile -Raw | ConvertFrom-Json
    $lastUpdateId = [int]$state.last_update_id
  } catch { Write-Host "WARN: could not read state file" }
}
Write-Host "Last update_id: $lastUpdateId"

$targetChatIds = @(-1004359764225)
$offset = $lastUpdateId + 1
$uri = "https://api.telegram.org/bot$token/getUpdates?offset=$offset&timeout=5&allowed_updates=%5B%22message%22%5D"

try {
  $resp = Invoke-RestMethod -Uri $uri -Method Get
  if ($resp.ok) {
    $updates = $resp.result
    Write-Host "Received $($updates.Length) update(s)"
    $maxUpdateId = $lastUpdateId

    foreach ($update in $updates) {
      if ($update.update_id -gt $maxUpdateId) { $maxUpdateId = $update.update_id }

      $msg = $update.message
      if (-not $msg) { continue }

      $chatId = $msg.chat.id
      if ($targetChatIds -notcontains $chatId) { continue }

      $text = $msg.text
      if (-not $text) { continue }

      Write-Host "Message: $text"

      if ($text -match '^/feedback(@\w+)?\s*(.*)') {
        $feedbackContent = $matches[2]

        # Get sender name
        if ($msg.sender_chat) {
          $sender = "$($msg.sender_chat.title) (匿名)"
        } else {
          if ($msg.from.username) { $sender = "@$($msg.from.username)" }
          else { $sender = $msg.from.first_name }
        }

        if (-not $feedbackContent) {
          Write-Host "Empty feedback from $sender"
          $replyUri = "https://api.telegram.org/bot$token/sendMessage"
          $replyBody = @{
            chat_id = $chatId
            text = "请发送 /feedback 加上你要反馈的问题描述，例如：/feedback 登录页面闪退"
            reply_to_message_id = $msg.message_id
          }
          try {
            $r = Invoke-RestMethod -Uri $replyUri -Method Post -Body $replyBody -ContentType "application/x-www-form-urlencoded"
            if ($r.ok) { Write-Host "Reply sent OK" }
          } catch { Write-Host "Reply failed: $_" }
        } else {
          Write-Host "Feedback from $sender : $feedbackContent"

          # Push to MeoW
          Push-MeoW $sender $feedbackContent

          # Create GitHub Issue
          $issueUrl = New-GitHubIssue $sender $feedbackContent

          # Reply
          $replyText = "感谢反馈！已收到您的消息。"
          if ($issueUrl) { $replyText += "`n`nIssue: $issueUrl" }

          $replyUri = "https://api.telegram.org/bot$token/sendMessage"
          $replyBody = @{
            chat_id = $chatId
            text = $replyText
            reply_to_message_id = $msg.message_id
          }
          try {
            $r = Invoke-RestMethod -Uri $replyUri -Method Post -Body $replyBody -ContentType "application/x-www-form-urlencoded"
            if ($r.ok) { Write-Host "Reply sent OK" }
          } catch { Write-Host "Reply failed: $_" }
        }
      }
    }

    if ($maxUpdateId -gt $lastUpdateId) {
      $state = "{`"last_update_id`": $maxUpdateId}"
      [System.IO.File]::WriteAllText($StateFile, $state)
      Write-Host "State saved: update_id = $maxUpdateId"
    } else {
      Write-Host "No new updates"
    }
  } else {
    Write-Host "ERROR: $($resp.description)"
  }
} catch {
  Write-Host "ERROR: $_"
}