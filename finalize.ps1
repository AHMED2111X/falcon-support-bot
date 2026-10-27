# ==============================================================================
# FALCON SUPPORT BOT — التهيئة النهائية للمجموعة (يعمل بعد إضافة البوت مشرفاً)
# ==============================================================================
# يشغّل كل إعدادات مجموعة الدعم عبر Telegram Bot API:
#   1) الرسائل البطيئة (10 ثوانٍ)
#   2) وصف المجموعة + قالب الفحص
#   3) permissions: منع الإعلانات الخارجية / الروابط (كطبقة أولى)
#   4) رسالة ترحيب + قواعد
#   5) تفعيل "الموافقة على الأعضاء الجدد" إن كان مدعوماً
#   6) تقرير حالة نهائي
#
#   powershell -ExecutionPolicy Bypass -File finalize.ps1
# ==============================================================================
param(
    [string]$TokenFile = "$PSScriptRoot\bot_token.txt",
    [string]$ConfigFile = "$PSScriptRoot\config.json",
    [int]$SlowMode = 10,
    [switch]$SendWelcome
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $TokenFile)) { throw "ملف التوكن غير موجود" }
$Token = (Get-Content $TokenFile -Raw).Trim()
$cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json
$Gid = [string]$cfg.group_id
$Admin = [string]$cfg.admin_id
$api = "https://api.telegram.org/bot$Token"

function Tg([string]$m, $b) {
    try {
        if ($null -eq $b) { return (Invoke-RestMethod -Uri "$api/$m" -Method Get -TimeoutSec 60) }
        $j = $b | ConvertTo-Json -Depth 10 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($j)
        return (Invoke-RestMethod -Uri "$api/$m" -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes -TimeoutSec 60)
    } catch {
        return @{ ok = $false; description = ($_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue).description }
    }
}

Write-Host "=== تهيئة مجموعة الدعم $Gid ===" -ForegroundColor Cyan

# 0) فحص: هل البوت مشرف في المجموعة؟
$me = Tg "getMe" $null
$cm = $null
try { $cm = Tg "getChatMember" @{ chat_id = $Gid; user_id = "$($me.result.id)" } } catch { $cm = $null }
if (-not $cm -or -not $cm.ok) {
    Write-Host "❌ البوت ليس في المجموعة بعد (أو لا يرىها)." -ForegroundColor Red
    Write-Host ""
    Write-Host "   المطلوب (في تطبيق تيليجرام، 30 ثانية):" -ForegroundColor Yellow
    Write-Host "   1) افتح مجموعة  FALCON SUPPORT" -ForegroundColor Yellow
    Write-Host "   2) إدارة المجموعة ← أضف مشرفاً ← @FALCON_VERIFY_2026_BOT" -ForegroundColor Yellow
    Write-Host "   3) فعّل: «حذف الرسائل» + «تقييد الأعضاء»  ثم احفظ" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   بعدها أعد تشغيل هذا السكربت وسيُهيّأ كل شيء تلقائياً." -ForegroundColor Yellow
    exit 1
}
Write-Host "  البوت: $($cm.result.status) · حذف=$($cm.result.can_delete_messages) · تقييد=$($cm.result.can_restrict_members)" -ForegroundColor DarkGray

# 1) الرسائل البطيئة
$r = Tg "setChatSlowModeDelay" @{ chat_id = $Gid; slow_mode_delay = $SlowMode }
if ($r.ok) {
    Write-Host "  ✅ الرسائل البطيئة: $SlowMode ثانية" -ForegroundColor Green
} else {
    Write-Host "  ℹ️ الرسائل البطيئة: اضبطها من التطبيق (المجموعة ← إدارة ← البطيء ← $SlowMode ثوانٍ)" -ForegroundColor DarkGray
    Write-Host "     (تُترك خارج صلاحيات البوت عمداً حتى لا يستطيع الحظر أو الطرد)" -ForegroundColor DarkGray
}

# 2) وصف المجموعة
$desc = "🛡️ مجموعة الدعم الرسمية — FALCON STORE ROOT" + "`n`n" +
        "✅ اكتب مشكلتك هنا (نص عادي)." + "`n" +
        "❌ يُحذف فوراً: أي رابط أو معرّف تيليجرام (@user) أو رسائل سبام." + "`n" +
        "⏱️ رسالة واحدة كل $SlowMode ثوانٍ لكل شخص." + "`n`n" +
        "🔗 /links — روابط المشروع" + "`n" +
        "📋 /rules — القواعد" + "`n" +
        "🆔 /id — معرّفك الرقمي"
$r = Tg "setChatDescription" @{ chat_id = $Gid; description = $desc }
if ($r.ok) {
    Write-Host "  ✅ وصف المجموعة" -ForegroundColor Green
} else {
    Write-Host "  ℹ️ الوصف: يحتاج صلاحية المالك (غير مهم — الرسالة المثبّتة تغطّي ذلك)" -ForegroundColor DarkGray
}

# 3)_permissions: طبقة أولى — منع الرسائل التي تحتوي روابط (Bots/groups فقط تُقيَّد بهذا)
$perms = @{
    chat_id = $Gid
    permissions = @{
        can_send_messages = $true
        can_send_polls = $true
        can_send_other_messages = $true
        can_add_web_page_previews = $false
        can_change_info = $false
        can_invite_users = $true
        can_pin_messages = $false
        can_manage_topics = $false
    }
}
$r = Tg "setChatPermissions" $perms
Write-Host $(if ($r.ok) { "  ✅ صلاحيات المجموعة (منع معاينة الروابط)" } else { "  ⚠️ صلاحيات: $($r.description)" }) -ForegroundColor $(if ($r.ok) { "Green" } else { "Yellow" })

# 4) الموافقة على الأعضاء الجدد — تترك للتطبيق (لا يحتاج البوت هذا الحق)

# 5) رسالة الترحيب + القواعد
if ($SendWelcome) {
    $welcomeFallback = @"

🛡️ *مرحباً بك في مجموعة الدعم — FALCON*

اكتب مشكلتك بالتفصيل وسأجمع لك البيانات المطلوبة، ويرد عليك المشرف.

📋 *ما يجب أن تكتبه:*
1️⃣ موديل الجهاز + إصدار أندرويد
2️⃣ نوع مدير الروت (Magisk / KernelSU) ونسخته
3️⃣ رقم إصدار FALCON
4️⃣ هل الفحص أخضر واحد أم ثلاثة؟
5️⃣ 📎 صورة للخطأ

⛔ *يُحذف فوراً:* أي رابط أو معرّف تيليجرام أو رسالة سبام.
⏱️ رسالة واحدة كل $SlowMode ثوانٍ لكل شخص.

🔗 /links — روابط المشروع
"@
    $welcome = if (Test-Path "$PSScriptRoot\welcome_message.txt") { (Get-Content "$PSScriptRoot\welcome_message.txt" -Raw) } else { $welcomeFallback }
    $r = Tg "sendMessage" @{ chat_id = $Gid; text = $welcome; parse_mode = "Markdown" }
    Write-Host $(if ($r.ok) { "  ✅ رسالة الترحيب" } else { "  ⚠️ ترحيب: $($r.description)" }) -ForegroundColor $(if ($r.ok) { "Green" } else { "Yellow" })
}

# 6) إشعار المشرف
if ($Admin) {
    $r = Tg "sendMessage" @{ chat_id = $Admin; text = "🛡️ تم تفعيل بوت الدعم في مجموعة FALCON SUPPORT.`n• الرسائل البطيئة: $SlowMode ثانية`n• حذف الروابط والمعرّفات: مفعّل`n• القالب التلقائي: مفعّل`n`nجرّب: أرسل رسالة فيها رابط وسيُحذف فوراً." }
    Write-Host $(if ($r.ok) { "  ✅ إشعار المشرف" } else { "  ⚠️ إشعار: $($r.description)" }) -ForegroundColor $(if ($r.ok) { "Green" } else { "Yellow" })
}

# 7) تقرير الحالة
Write-Host "`n=== الحالة النهائية ===" -ForegroundColor Cyan
$ch = Tg "getChat" @{ chat_id = $Gid }
Write-Host "  العنوان   : $($ch.result.title)"
Write-Host "  المعرّف   : $($ch.result.id)"
Write-Host "  رابط عام  : $(if ($ch.result.username) { '@' + $ch.result.username } else { 'غير منشور' })"
$ad = Tg "getChatAdministrators" @{ chat_id = $Gid }
foreach ($a in $ad.result) {
    Write-Host ("  مشرف     : {0,-22} {1,-14} حذف={2} تقييد={3}" -f "@$($a.user.username)", $a.status, $a.can_delete_messages, $a.can_restrict_members)
}
Write-Host "`n✅ اكتملت التهيئة." -ForegroundColor Green
