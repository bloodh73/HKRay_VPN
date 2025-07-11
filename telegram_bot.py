import logging
import requests
import json
import os
import secrets
import string
from datetime import datetime
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, ReplyKeyboardMarkup, KeyboardButton
from telegram.ext import Application, CommandHandler, ContextTypes, CallbackQueryHandler, MessageHandler, filters

# --- تنظیمات ربات ---
# توکن ربات تلگرام خود را از BotFather اینجا قرار دهید.
BOT_TOKEN = "6937115926:AAHULNWij13zpsTYMjvbMajZm0uvMKv1c1M" 

# آدرس پایه API پنل مدیریت VPN شما.
# مطمئن شوید که این آدرس قابل دسترسی از سروری است که ربات روی آن اجرا می‌شود.
API_BASE_URL = "https://blizzardping.ir/panel/api.php?path="

# توکن ادمین پنل VPN شما.
# این توکن باید برای ادمینی باشد که دسترسی 'can_manage_users' دارد.
# برای امنیت بیشتر، این توکن را از متغیرهای محیطی بارگذاری کنید (مثلاً از طریق os.environ.get).
BOT_ADMIN_TOKEN = "c37c79f8d787b3fa9878af848c8f5ac8aa4f51ab531d5f8a45899647b04a85f9" 

# شناسه‌های عددی تلگرام ادمین‌ها (برای دسترسی به دستورات ادمین).
# اینها را با IDهای واقعی ادمین‌های تلگرام خود جایگزین کنید.
ADMIN_TELEGRAM_IDS = [97376703] # مثال: [123456789]

# اطلاعات پرداخت دستی (می‌توانید اینها را سفارشی کنید)
PAYMENT_INSTRUCTIONS = {
    "card_number": "6037-xxxx-xxxx-xxxx",
    "bank_name": "بانک ملی",
    "account_holder": "نام صاحب حساب",
    "contact_admin_for_receipt": "@YourAdminTelegramUsername" # نام کاربری تلگرام ادمین برای ارسال رسید
}

# فعال کردن لاگ‌گیری
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s', level=logging.INFO
)
logger = logging.getLogger(__name__)

# --- ذخیره‌سازی موقت سفارشات در حال انتظار (در یک سیستم واقعی از دیتابیس استفاده کنید) ---
# { telegram_user_id: { 'plan_id': int, 'status': 'pending', 'timestamp': datetime, 'username': str, 'password': str, 'plan_name': str } }
pending_orders = {}

# --- توابع کمکی برای ارتباط با API پنل VPN ---

async def call_api(endpoint, method='GET', data=None, admin_auth=False):
    """
    فراخوانی API پنل VPN.
    :param endpoint: نقطه پایانی API (مثلاً 'plans' یا 'users').
    :param method: متد HTTP (GET, POST, PUT, DELETE).
    :param data: داده‌های JSON برای ارسال در درخواست (فقط برای POST/PUT).
    :param admin_auth: اگر True باشد، توکن ادمین ربات را در هدر Authorization قرار می‌دهد.
    :return: پاسخ JSON از API.
    """
    headers = {
        'Content-Type': 'application/json',
    }
    if admin_auth:
        headers['Authorization'] = f'Bearer {BOT_ADMIN_TOKEN}'
        # اگر API شما نیاز به X-Admin-ID در هدر دارد
        # headers['X-Admin-ID'] = str(ADMIN_TELEGRAM_IDS[0]) # استفاده از اولین ادمین به عنوان ID ارسال کننده

    url = f"{API_BASE_URL}{endpoint}"
    
    try:
        if method == 'GET':
            response = requests.get(url, headers=headers)
        elif method == 'POST':
            response = requests.post(url, headers=headers, data=json.dumps(data))
        elif method == 'PUT':
            response = requests.put(url, headers=headers, data=json.dumps(data))
        elif method == 'DELETE':
            response = requests.delete(url, headers=headers)
        else:
            raise ValueError(f"متد HTTP نامعتبر: {method}")

        response.raise_for_status()  # خطاها را برای وضعیت‌های HTTP ناموفق (4xx یا 5xx) ایجاد می‌کند
        return response.json()
    except requests.exceptions.RequestException as e:
        logger.error(f"خطا در فراخوانی API {url}: {e}")
        if hasattr(e, 'response') and e.response is not None:
            logger.error(f"پاسخ خطا از API: {e.response.text}")
        raise Exception(f"خطا در ارتباط با سرور VPN: {e}")
    except json.JSONDecodeError as e:
        logger.error(f"خطا در تجزیه JSON از API {url}: {e}")
        logger.error(f"پاسخ خام: {response.text}")
        raise Exception(f"خطا در پردازش پاسخ سرور: {e}")

async def get_plans():
    """پلن‌های موجود را از API دریافت می‌کند."""
    try:
        response = await call_api('plans', admin_auth=True)
        if response and response.get('status') == 'success':
            return response.get('data', [])
        else:
            logger.error(f"پاسخ ناموفق در دریافت پلن‌ها: {response}")
            return []
    except Exception as e:
        logger.error(f"خطا در دریافت پلن‌ها: {e}")
        return []

async def create_vpn_user(telegram_user_id, plan_id):
    """یک کاربر جدید VPN را از طریق API ایجاد می‌کند."""
    username = f"tg_user_{telegram_user_id}"
    password = ''.join(secrets.choice(string.ascii_letters + string.digits) for i in range(12))

    plans = await get_plans()
    selected_plan = next((p for p in plans if p['id'] == plan_id), None)

    if not selected_plan:
        raise ValueError(f"پلن با شناسه {plan_id} یافت نشد.")

    user_data = {
        "username": username,
        "password": password,
        "plan_id": plan_id,
        "multi_user": 0,
        "visit_status": None,
        "multi_account": 0,
        "status": "active",
        "options": None,
    }
    
    try:
        response = await call_api('users', method='POST', data=user_data, admin_auth=True)
        if response and response.get('status') == 'success':
            return {
                "username": username,
                "password": password,
                "plan_name": selected_plan.get('name'),
                "message": response.get('message')
            }
        else:
            logger.error(f"پاسخ ناموفق در ایجاد کاربر VPN: {response}")
            raise Exception(response.get('message', 'خطا در ایجاد کاربر VPN.'))
    except Exception as e:
        logger.error(f"خطا در ایجاد کاربر VPN: {e}")
        raise

async def get_user_status(telegram_user_id):
    """وضعیت کاربر VPN را از طریق API دریافت می‌کند."""
    username = f"tg_user_{telegram_user_id}"
    try:
        # این روش برای تعداد زیاد کاربر کارآمد نیست.
        # بهتر است API شما قابلیت فیلتر بر اساس username را داشته باشد.
        response = await call_api('users', method='GET', admin_auth=True)
        if response and response.get('status') == 'success':
            users = response.get('data', [])
            for user in users:
                if user.get('username') == username:
                    return user
            return None # کاربر یافت نشد
        else:
            logger.error(f"پاسخ ناموفق در دریافت وضعیت کاربر: {response}")
            return None
    except Exception as e:
        logger.error(f"خطا در دریافت وضعیت کاربر: {e}")
        return None

# --- تعریف Reply Keyboard Markup ---
main_menu_keyboard = ReplyKeyboardMarkup(
    [
        [KeyboardButton("مشاهده پلن‌ها"), KeyboardButton("وضعیت حساب من")],
        [KeyboardButton("پشتیبانی")]
    ],
    resize_keyboard=True,
    one_time_keyboard=False # این کیبورد همیشه نمایش داده می‌شود
)

# --- توابع هندلر تلگرام ---

async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """هندلر برای دستور /start."""
    user = update.effective_user
    await update.message.reply_html(
        f"سلام {user.mention_html()}! به ربات فروش VPN خوش آمدید.\n"
        "برای شروع، از دکمه‌های زیر استفاده کنید:",
        reply_markup=main_menu_keyboard # اضافه کردن دکمه‌ها
    )

async def plans_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """هندلر برای دستور /plans."""
    plans = await get_plans()
    if not plans:
        await update.message.reply_text("در حال حاضر هیچ پلنی برای نمایش وجود ندارد.", reply_markup=main_menu_keyboard)
        return

    message_parts = ["پلن‌های موجود:\n"]
    keyboard = []
    for plan in plans:
        if plan.get('status') == 'active':
            message_parts.append(
                f"نام: {plan.get('name')}\n"
                f"حجم: {plan.get('volume_mb')} مگابایت\n"
                f"مدت: {plan.get('duration_days')} روز\n"
                f"قیمت: {plan.get('price')} تومان\n"
                "--------------------\n"
            )
            keyboard.append([InlineKeyboardButton(f"خرید {plan.get('name')} ({plan.get('price')} تومان)", callback_data=f"buy_{plan.get('id')}")])

    if not keyboard: # اگر هیچ پلن فعالی وجود نداشت
        await update.message.reply_text("در حال حاضر هیچ پلن فعالی برای خرید وجود ندارد.", reply_markup=main_menu_keyboard)
        return

    reply_markup_inline = InlineKeyboardMarkup(keyboard)
    await update.message.reply_text("".join(message_parts), reply_markup=reply_markup_inline)

async def buy_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """هندلر برای دکمه‌های خرید پلن."""
    query = update.callback_query
    await query.answer() # پاسخ به کال‌بک کوئری برای حذف حالت لودینگ

    plan_id = int(query.data.split('_')[1])
    telegram_user_id = query.from_user.id
    telegram_username = query.from_user.username if query.from_user.username else f"ID:{telegram_user_id}"

    plans = await get_plans()
    selected_plan = next((p for p in plans if p['id'] == plan_id), None)

    if not selected_plan:
        await query.edit_message_text("خطا: پلن انتخاب شده یافت نشد.", reply_markup=main_menu_keyboard)
        return

    # بررسی کنید که آیا کاربر قبلاً یک سفارش در حال انتظار دارد
    if telegram_user_id in pending_orders:
        await query.edit_message_text("شما قبلاً یک سفارش در حال انتظار دارید. لطفاً منتظر تأیید ادمین باشید یا با پشتیبانی تماس بگیرید.", reply_markup=main_menu_keyboard)
        return

    # ثبت سفارش در حال انتظار
    pending_orders[telegram_user_id] = {
        'plan_id': plan_id,
        'status': 'pending',
        'timestamp': datetime.now(),
        'plan_name': selected_plan.get('name'),
        'plan_price': selected_plan.get('price'),
        'telegram_username': telegram_username
    }

    # ارسال دستورالعمل پرداخت به کاربر
    payment_message = (
        f"برای خرید پلن *{selected_plan.get('name')}* به مبلغ *{selected_plan.get('price')} تومان*، "
        f"لطفاً مبلغ را به اطلاعات زیر واریز کنید:\n\n"
        f"شماره کارت: `{PAYMENT_INSTRUCTIONS['card_number']}`\n"
        f"نام بانک: {PAYMENT_INSTRUCTIONS['bank_name']}\n"
        f"نام صاحب حساب: {PAYMENT_INSTRUCTIONS['account_holder']}\n\n"
        f"پس از واریز، لطفاً *رسید پرداخت* را به ادمین {PAYMENT_INSTRUCTIONS['contact_admin_for_receipt']} ارسال کنید تا حساب شما فعال شود."
    )
    await query.edit_message_text(payment_message, parse_mode='Markdown', reply_markup=main_menu_keyboard)
    logger.info(f"سفارش جدید از کاربر {telegram_user_id} برای پلن {plan_id} ثبت شد.")

    # اطلاع‌رسانی به ادمین‌ها
    admin_notification_message = (
        f"🔔 *سفارش جدید در انتظار پرداخت!* 🔔\n\n"
        f"کاربر: {telegram_username} (ID: `{telegram_user_id}`)\n"
        f"پلن: *{selected_plan.get('name')}*\n"
        f"مبلغ: *{selected_plan.get('price')} تومان*\n"
        f"برای تأیید پرداخت، از دستور `/confirm_payment {telegram_user_id}` استفاده کنید."
    )
    for admin_id in ADMIN_TELEGRAM_IDS:
        try:
            await context.bot.send_message(chat_id=admin_id, text=admin_notification_message, parse_mode='Markdown')
        except Exception as e:
            logger.error(f"خطا در ارسال اطلاع‌رسانی به ادمین {admin_id}: {e}")

async def my_status_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """هندلر برای دستور /my_status."""
    telegram_user_id = update.effective_user.id
    user_data = await get_user_status(telegram_user_id)

    if user_data:
        user_plan = next((p for p in await get_plans() if p['id'] == user_data.get('plan_id')), None)
        plan_name = user_plan['name'] if user_plan else 'نامشخص'

        message_text = (
            f"وضعیت حساب VPN شما:\n\n"
            f"نام کاربری: `{user_data.get('username')}`\n"
            f"پلن: {plan_name}\n"
            f"حجم مصرفی: {user_data.get('used_volume', 0) / 1024:.2f} گیگابایت\n"
            f"حجم باقیمانده: {user_data.get('remaining_volume', 0) / 1024:.2f} گیگابایت\n"
            f"روزهای باقیمانده: {user_data.get('remaining_days', 0)} روز\n"
            f"تاریخ انقضا: {user_data.get('expiry_date', 'N/A')}\n"
            f"وضعیت: {user_data.get('status', 'N/A')}\n"
        )
        await update.message.reply_text(message_text, parse_mode='Markdown', reply_markup=main_menu_keyboard)
    else:
        # اگر کاربر سفارش در حال انتظار دارد
        if telegram_user_id in pending_orders:
            order = pending_orders[telegram_user_id]
            await update.message.reply_text(
                f"شما یک سفارش در حال انتظار برای پلن *{order['plan_name']}* دارید.\n"
                f"لطفاً پرداخت را تکمیل کرده و رسید را برای ادمین ارسال کنید تا حسابتان فعال شود.\n"
                f"برای مشاهده دستورالعمل‌های پرداخت مجدد، می‌توانید دوباره /plans را بزنید و پلن را انتخاب کنید."
            , parse_mode='Markdown', reply_markup=main_menu_keyboard)
        else:
            await update.message.reply_text("حساب VPN برای شما یافت نشد. لطفاً ابتدا یک پلن خریداری کنید.", reply_markup=main_menu_keyboard)

async def support_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """هندلر برای دستور /support."""
    support_message = (
        "برای پشتیبانی، لطفاً با ادمین ما تماس بگیرید:\n"
        f"نام کاربری ادمین: {PAYMENT_INSTRUCTIONS['contact_admin_for_receipt']}\n"
        "لطفاً در پیام خود، مشکل و شناسه کاربری تلگرام خود را ذکر کنید."
    )
    await update.message.reply_text(support_message, reply_markup=main_menu_keyboard)

async def admin_orders_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """هندلر برای دستور /admin_orders - فقط برای ادمین‌ها."""
    if update.effective_user.id not in ADMIN_TELEGRAM_IDS:
        await update.message.reply_text("شما اجازه دسترسی به این دستور را ندارید.")
        return

    if not pending_orders:
        await update.message.reply_text("هیچ سفارش در حال انتظاری وجود ندارد.")
        return

    message_parts = ["*سفارشات در حال انتظار:*\n\n"]
    for user_id, order in pending_orders.items():
        message_parts.append(
            f"کاربر: {order.get('telegram_username')} (ID: `{user_id}`)\n"
            f"پلن: *{order.get('plan_name')}* ({order.get('plan_price')} تومان)\n"
            f"زمان ثبت: {order.get('timestamp').strftime('%Y-%m-%d %H:%M:%S')}\n"
            f"وضعیت: {order.get('status')}\n"
            f"برای تأیید: `/confirm_payment {user_id}`\n"
            "--------------------\n"
        )
    await update.message.reply_text("".join(message_parts), parse_mode='Markdown')

async def confirm_payment_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """هندلر برای دستور /confirm_payment <telegram_user_id> - فقط برای ادمین‌ها."""
    if update.effective_user.id not in ADMIN_TELEGRAM_IDS:
        await update.message.reply_text("شما اجازه دسترسی به این دستور را ندارید.")
        return

    if not context.args or len(context.args) != 1:
        await update.message.reply_text("نحوه استفاده: `/confirm_payment <شناسه_کاربر_تلگرام>`", parse_mode='Markdown')
        return

    try:
        target_user_id = int(context.args[0])
    except ValueError:
        await update.message.reply_text("شناسه کاربر تلگرام نامعتبر است. لطفاً یک عدد وارد کنید.")
        return

    if target_user_id not in pending_orders:
        await update.message.reply_text(f"سفارشی در حال انتظار برای کاربر با ID `{target_user_id}` یافت نشد.", parse_mode='Markdown')
        return

    order_to_confirm = pending_orders[target_user_id]
    plan_id = order_to_confirm['plan_id']
    username_tg = order_to_confirm['telegram_username'] # برای پیام به کاربر

    await update.message.reply_text(f"در حال ایجاد حساب VPN برای کاربر {username_tg} (ID: `{target_user_id}`)...", parse_mode='Markdown')

    try:
        user_credentials = await create_vpn_user(target_user_id, plan_id)
        
        response_message_to_user = (
            f"تبریک! حساب VPN شما فعال شد! 🎉\n\n"
            f"اطلاعات اتصال شما برای پلن *{user_credentials['plan_name']}*:\n"
            f"نام کاربری: `{user_credentials['username']}`\n"
            f"رمز عبور: `{user_credentials['password']}`\n"
            f"لطفاً این اطلاعات را در جایی امن ذخیره کنید."
        )
        # ارسال اطلاعات به کاربر
        await context.bot.send_message(chat_id=target_user_id, text=response_message_to_user, parse_mode='Markdown')
        
        # حذف سفارش از لیست در حال انتظار
        del pending_orders[target_user_id]
        await update.message.reply_text(f"پرداخت برای کاربر {username_tg} (ID: `{target_user_id}`) تأیید شد و حساب ایجاد گردید.", parse_mode='Markdown')
        logger.info(f"پرداخت کاربر {target_user_id} برای پلن {plan_id} تأیید و حساب ایجاد شد.")

    except Exception as e:
        await update.message.reply_text(f"خطا در ایجاد حساب VPN برای کاربر {username_tg}: {e}\nلطفاً به صورت دستی بررسی کنید.", parse_mode='Markdown')
        logger.error(f"خطا در تأیید پرداخت و ایجاد حساب برای کاربر {target_user_id}: {e}")

async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """هندلر برای مدیریت خطاها."""
    logger.error(f"خطا در به‌روزرسانی {update}: {context.error}")
    if update.effective_message:
        await update.effective_message.reply_text("متاسفم، مشکلی پیش آمد. لطفاً بعداً دوباره امتحان کنید.")

async def handle_text_messages(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """هندلر برای پیام‌های متنی که دستور نیستند."""
    text = update.message.text
    if text == "مشاهده پلن‌ها":
        await plans_command(update, context)
    elif text == "وضعیت حساب من":
        await my_status_command(update, context)
    elif text == "پشتیبانی":
        await support_command(update, context)
    else:
        await update.message.reply_text("متوجه درخواست شما نشدم. لطفاً از دکمه‌ها یا دستورات موجود استفاده کنید.", reply_markup=main_menu_keyboard)


def main() -> None:
    """نقطه ورود اصلی برای اجرای ربات."""
    application = Application.builder().token(BOT_TOKEN).build()

    # اضافه کردن هندلرهای دستورات عمومی
    application.add_handler(CommandHandler("start", start_command))
    application.add_handler(CommandHandler("plans", plans_command))
    application.add_handler(CommandHandler("my_status", my_status_command))
    application.add_handler(CommandHandler("support", support_command))

    # اضافه کردن هندلر برای کال‌بک کوئری‌ها (دکمه‌های Inline)
    application.add_handler(CallbackQueryHandler(buy_callback, pattern=r'^buy_\d+$'))

    # اضافه کردن هندلرهای دستورات ادمین
    application.add_handler(CommandHandler("admin_orders", admin_orders_command))
    application.add_handler(CommandHandler("confirm_payment", confirm_payment_command))

    # اضافه کردن هندلر برای پیام‌های متنی که دستور نیستند (برای پشتیبانی از دکمه‌ها)
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text_messages))

    # اضافه کردن هندلر خطا
    application.add_error_handler(error_handler)

    # اجرای ربات (با استفاده از Long Polling)
    logger.info("ربات تلگرام شروع به کار کرد...")
    application.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == "__main__":
    main()
