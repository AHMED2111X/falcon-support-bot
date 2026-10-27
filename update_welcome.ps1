# ==============================================================================
# FALCON SUPPORT BOT — تحديث الرسالة المثبّتة (تشمل: لماذا أُنشئت المجموعة)
# ==============================================================================
param(
    [string]$TokenFile = "$PSScriptRoot\bot_token.txt",
    [string]$ConfigFile = "$PSScriptRoot\config.json",
    [int]$MessageId = 12
)

$ErrorActionPreference = "Stop"
$Token = (Get-Content $TokenFile -Raw).Trim()
$cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json
$Gid = [string]$cfg.group_id
$api = "https://api.telegram.org/bot$Token"

function Tg([string]$m, $b) {
    $j = $b | ConvertTo-Json -Depth 12 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($j)
    return Invoke-RestMethod -Uri "$api/$m" -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes -TimeoutSec 60
}

$text = @"
🛡️ *FALCON SUPPORT*
*مجموعة الدعم الرسمية — FALCON STORE ROOT*

━━━━━━━━━━━━━━━━━━━━
💡 *لماذا أُنشئت هذه المجموعة؟*
━━━━━━━━━━━━━━━━━━━━
لأن أسئلة ومشكلات مستخدمي *FALCON INTEGRITY FIX* كانت تتشتّت بين التعليقات والرسائل الخاصة، فتفقد غيرها وتضيع الحلول القيّمة.

هنا مكان واحد:
• ❓ سؤالك يجيب عليه أحدهم — وأقرب ما يكون
• 💡 الحل الذي ينفعك قد ينفع غيرك أيضاً
• 🧩 كل تجربة نضيفها للمنهج

━━━━━━━━━━━━━━━━━━━━
📋 *أرسل هذه المعلومات لتسريع الحل*
━━━━━━━━━━━━━━━━━━━━
1️⃣ موديل الجهاز وإصدار أندرويد
2️⃣ نوع مدير الروت (Magisk / KernelSU) ونسخته
3️⃣ رقم إصدار FALCON (من وصف الوحدة في مدير الروت)
4️⃣ نتيجة الفحص: أخضر واحد أم ثلاثة؟ وما الرسالة بالضبط؟
5️⃣ 📎 صورة للخطأ إن وُجدت

━━━━━━━━━━━━━━━━━━━━
⛔ *قواعد المجموعة*
━━━━━━━━━━━━━━━━━━━━
• يُحذف فوراً: أي رابط أو معرّف تيليجرام أو رسالة سبام
• ⏱️ رسالة واحدة كل 10 ثوانٍ لكل شخص
• ✅ الصور Screenshots مسموحة ومفيدة جداً
• 🚫 لا إعلانات ولا عروض ولا روابط دعوة
• 🤝 لا حظر ولا طرد — البوت يحذف الرسائل فقط

━━━━━━━━━━━━━━━━━━━━
📎 *أوامر سريعة*
━━━━━━━━━━━━━━━━━━━━
/links  روابط المشروع  ·  /rules  القواعد  ·  /id  معرّفك

⏳ نرد خلال ساعات قليلة بإذن الله — جزاكم الله خيراً 🤍
"@

Write-Host "=== تحديث الرسالة المثبّتة ===" -ForegroundColor Cyan
$r = Tg "editMessageText" @{ chat_id = $Gid; message_id = "$MessageId"; text = $text; parse_mode = "Markdown" }
if ($r.ok) { Write-Host "✓ حُدّثت الرسالة المثبّتة" -ForegroundColor Green }
else { Write-Host "❌ $($r.description)" -ForegroundColor Red; exit 1 }

Write-Host "=== إعادة تثبيتها في الأعلى ===" -ForegroundColor Cyan
try {
    $p = Tg "pinChatMessage" @{ chat_id = $Gid; message_id = "$MessageId"; disable_notification = $false }
    if ($p.ok) { Write-Host "✓ مثبّتة" -ForegroundColor Green } else { Write-Host "⚠️ $($p.description)" -ForegroundColor Yellow }
} catch { Write-Host "⚠️ $($_.ErrorDetails.Message)" -ForegroundColor Yellow }

[System.IO.File]::WriteAllText("$PSScriptRoot\welcome_message.txt", $text, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "✓ حُفظت في welcome_message.txt" -ForegroundColor DarkGray
