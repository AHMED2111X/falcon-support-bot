# ==============================================================================
# FALCON SUPPORT BOT — إرسال رسالة الترحيب الجميلة + تثبيتها
# ==============================================================================
param(
    [string]$TokenFile = "$PSScriptRoot\bot_token.txt",
    [string]$ConfigFile = "$PSScriptRoot\config.json",
    [switch]$NoPin
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

$welcome = @"
🛡️ <b>FALCON SUPPORT</b>
<i>مجموعة الدعم الرسمية — FALCON STORE ROOT</i>

أهلاً بك 👋
هنا مكانك لعرض أي مشكلة في <b>FALCON INTEGRITY FIX</b>، وسنتكفّل بها بإذن الله.

━━━━━━━━━━━━━━━━━━━━
📋 <b>الرجاء إرسال هذه المعلومات</b>
━━━━━━━━━━━━━━━━━━━━
1️⃣ موديل الجهاز وإصدار أندرويد
2️⃣ نوع مدير الروت (Magisk / KernelSU) ونسخته
3️⃣ رقم إصدار FALCON (من وصف الوحدة في مدير الروت)
4️⃣ نتيجة الفحص: أخضر واحد أم ثلاثة؟ وما الرسالة بالضبط؟
5️⃣ 📎 صورة للخطأ إن وُجدت

━━━━━━━━━━━━━━━━━━━━
⛔ <b>قواعد المجموعة</b>
━━━━━━━━━━━━━━━━━━━━
• يُحذف فوراً: أي رابط أو معرّف تيليجرام أو رسالة سبام
• ⏱️ رسالة واحدة كل 10 ثوانٍ لكل شخص
• ✅ الصور Screenshots مسموحة ومفيدة جداً
• 🚫 لا إعلانات ولا عروض ولا روابط دعوة

━━━━━━━━━━━━━━━━━━━━
📎 <b>أوامر سريعة</b>
━━━━━━━━━━━━━━━━━━━━
/links  روابط المشروع  ·  /rules  القواعد  ·  /id  معرّفك

⏳ نرد خلال ساعات قليلة بإذن الله — جزاكم الله خيراً 🤍
"@

$keyboard = '{"inline_keyboard":[[{"text":"\ud83d\udce1 القناة الرسمية","url":"https://t.me/FALCON_KERNEL_PRO"},{"text":"\u2b07\ufe0f تحميل التحديث","url":"https://github.com/AHMED2111X/AHMED2111X/releases/latest"}]]}'

Write-Host "=== إرسال رسالة الترحيب ===" -ForegroundColor Cyan
# نبني الـJSON يدوياً لضمان بنية لوحة الأزرار (PowerPress يسطّح المصفوفات المتداخلة)
$payload = '{"chat_id":"' + $Gid + '","parse_mode":"HTML","reply_markup":' + $keyboard + ',"text":' + (($welcome | ConvertTo-Json -Compress)) + '}'
$bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
$r = Invoke-RestMethod -Uri "$api/sendMessage" -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes -TimeoutSec 60
if (-not $r.ok) { Write-Host "❌ فشل: $($r.description)" -ForegroundColor Red; exit 1 }
Write-Host "✓ أُرسلت (message_id=$($r.result.message_id))" -ForegroundColor Green

if (-not $NoPin) {
    Write-Host "=== تثبيتها ===" -ForegroundColor Cyan
    try {
        $p = Tg "pinChatMessage" @{ chat_id = $Gid; message_id = "$($r.result.message_id)"; disable_notification = $false }
        if ($p.ok) { Write-Host "✓ ثُبّتت في أعلى المجموعة" -ForegroundColor Green }
        else { Write-Host "⚠️ التثبيت: $($p.description)" -ForegroundColor Yellow }
    } catch {
        Write-Host "⚠️ التثبيت: $($_.ErrorDetails.Message)" -ForegroundColor Yellow
    }
}

# حفظ نسخة في ملف لم<RUN>ح later
[System.IO.File]::WriteAllText("$PSScriptRoot\welcome_message.txt", $welcome, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "✓ حُفظت الرسالة في welcome_message.txt" -ForegroundColor DarkGray
