import os
import logging
import requests
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters, ContextTypes

# Logging
logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    level=logging.INFO
)
logger = logging.getLogger(__name__)

# Config from env
TOKEN = os.environ.get("TELEGRAM_TOKEN", "")
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")
GITHUB_REPO = os.environ.get("GITHUB_REPO", "137458/tieba-lite-harmony")
MEOW_NICK = os.environ.get("MEOW_NICKNAME", "")
RENDER_URL = os.environ.get("RENDER_URL", "")
PORT = int(os.environ.get("PORT", 8080))

# Group chat IDs that can use feedback
TARGET_CHAT_IDS = [-1004359764225]

# Track users waiting to provide feedback
waiting_for_feedback = set()


def push_meow(title: str, msg: str):
    if not MEOW_NICK:
        return
    try:
        url = f"https://api.chuckfang.com/{MEOW_NICK}/{requests.utils.quote(title, safe='')}/{requests.utils.quote(msg, safe='')}"
        resp = requests.get(url, timeout=10)
        if resp.status_code == 200:
            logger.info("MeoW push OK")
        else:
            logger.warning(f"MeoW push error: {resp.text}")
    except Exception as e:
        logger.warning(f"MeoW push failed: {e}")


def create_github_issue(sender: str, content: str) -> str:
    if not GITHUB_TOKEN:
        return ""
    try:
        headers = {
            "Authorization": f"Bearer {GITHUB_TOKEN}",
            "Accept": "application/vnd.github+json"
        }
        title = f"[Feedback] {content[:50]}"
        if len(content) > 50:
            title += "..."
        body = (
            f"**来自:** {sender}\n\n"
            f"**反馈内容:**\n{content}\n\n"
            f"---\n*Automated feedback from Telegram group*"
        )
        data = {
            "title": title,
            "body": body,
            "labels": ["feedback"]
        }
        resp = requests.post(
            f"https://api.github.com/repos/{GITHUB_REPO}/issues",
            headers=headers,
            json=data,
            timeout=15
        )
        if resp.status_code in (200, 201):
            issue_url = resp.json().get("html_url", "")
            logger.info(f"GitHub Issue created: {issue_url}")
            return issue_url
        else:
            logger.warning(f"GitHub API error: {resp.status_code} {resp.text}")
            return ""
    except Exception as e:
        logger.warning(f"GitHub Issue failed: {e}")
        return ""


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command"""
    await update.message.reply_text(
        "欢迎使用反馈机器人！\n\n"
        "可用命令：\n"
        "/feedback 内容 - 向开发者反馈问题\n"
        "/feedback - 交互式反馈（按提示输入）"
    )


async def feedback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /feedback command"""
    chat_id = update.effective_chat.id
    if chat_id not in TARGET_CHAT_IDS:
        return

    # Extract sender name
    if update.message.sender_chat:
        sender = f"{update.message.sender_chat.title} (匿名)"
    else:
        user = update.message.from_user
        sender = f"@{user.username}" if user.username else user.first_name

    # Get feedback content
    text = update.message.text
    parts = text.split(" ", 1)
    if len(parts) < 2 or not parts[1].strip():
        # No content - show interactive buttons
        keyboard = [
            [InlineKeyboardButton("反馈问题", callback_data="feedback_issue")],
            [InlineKeyboardButton("功能建议", callback_data="feedback_suggestion")],
            [InlineKeyboardButton("取消", callback_data="feedback_cancel")]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)
        await update.message.reply_text(
            "请选择反馈类型：",
            reply_markup=reply_markup
        )
        return

    content = parts[1].strip()
    await process_feedback(update, context, sender, content)


async def button_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle inline keyboard button clicks"""
    query = update.callback_query
    await query.answer()

    if query.data == "feedback_cancel":
        await query.edit_message_text("已取消反馈。")
        return

    # Mark user as waiting for feedback
    user_id = query.from_user.id
    waiting_for_feedback.add(user_id)
    context.user_data["feedback_type"] = query.data

    await query.edit_message_text(
        "请直接发送您的问题描述或建议：\n"
        "（输入 /cancel 取消）"
    )


async def handle_text(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle text messages from users in feedback mode"""
    user_id = update.effective_user.id
    if user_id not in waiting_for_feedback:
        return

    chat_id = update.effective_chat.id
    if chat_id not in TARGET_CHAT_IDS:
        return

    text = update.message.text
    if text.startswith("/cancel"):
        waiting_for_feedback.discard(user_id)
        await update.message.reply_text("已取消反馈。")
        return

    # Extract sender
    if update.message.sender_chat:
        sender = f"{update.message.sender_chat.title} (匿名)"
    else:
        user = update.message.from_user
        sender = f"@{user.username}" if user.username else user.first_name

    feedback_type = context.user_data.get("feedback_type", "feedback_issue")
    type_label = "问题反馈" if feedback_type == "feedback_issue" else "功能建议"

    content = f"[{type_label}] {text}"
    waiting_for_feedback.discard(user_id)

    await process_feedback(update, context, sender, content, is_button=True)


async def process_feedback(
    update: Update,
    context: ContextTypes.DEFAULT_TYPE,
    sender: str,
    content: str,
    is_button: bool = False
):
    """Process feedback: push to MeoW, create GitHub Issue, reply"""
    chat_id = update.effective_chat.id

    # 1. Push to MeoW
    push_meow("Tieba Feedback", f"[{sender}] {content}")

    # 2. Create GitHub Issue
    issue_url = create_github_issue(sender, content)

    # 3. Reply
    reply = "感谢反馈！已收到您的消息。"
    if issue_url:
        reply += f"\n\nIssue: {issue_url}"

    if is_button:
        await update.message.reply_text(reply)
    else:
        await update.message.reply_text(reply, reply_to_message_id=update.message.message_id)


async def post_init(app: Application):
    """Set webhook after app initialization"""
    if RENDER_URL:
        webhook_url = f"{RENDER_URL}/{TOKEN}"
        await app.bot.set_webhook(url=webhook_url)
        logger.info(f"Webhook set to {webhook_url}")
    else:
        logger.warning("RENDER_URL not set, skipping webhook setup")


def main():
    if not TOKEN:
        logger.error("TELEGRAM_TOKEN is required")
        return

    app = Application.builder().token(TOKEN).post_init(post_init).build()

    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("feedback", feedback))
    app.add_handler(CallbackQueryHandler(button_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))

    logger.info("Starting bot...")
    app.run_webhook(
        listen="0.0.0.0",
        port=PORT,
        url_path=TOKEN,
    )


if __name__ == "__main__":
    main()