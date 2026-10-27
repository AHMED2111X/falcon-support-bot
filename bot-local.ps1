# ==============================================================================
# FALCON SUPPORT BOT — نسخة محلية (PowerShell) للتجربة الفورية
# ==============================================================================
# تعمل بنفس قواعد support-bot.js بالضبط (انظر SPAM_PATTERNS هناك).
# ⚠️ تحتاج تشغيل طويل المدى: البوت لا يعمل إلا والجهاز مفتوح.
#    للاستخدام الدائم استخدم نسخة Cloudflare Worker (support-bot.js).
#
#   powershell -ExecutionPolicy Bypass -File bot-local.ps1
#   powershell -ExecutionPolicy Bypass -File bot-local.ps1 -Once
# ==============================================================================
param(
    [string]$TokenFile = "$PSScriptRoot\bot_token.txt",
    [string]$ConfigFile = "$PSScriptRoot\config.json",
    [int]$SlowMode = 10,
    [switch]$Once,
    [switch]$NoDelete
)

$ErrorActionPreference = "Continue"

if (-not (Test-Path $TokenFile)) { throw "ملف التوكن غير موجود: $TokenFile" }
$Token = (Get-Content $TokenFile -Raw).Trim()
if (-not $Token) { throw "التوكن فارغ" }

$cfg = @{}
if (Test-Path $ConfigFile) { $cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json }
$AdminId = if ($cfg.admin_id) { [string]$cfg.admin_id } else { "" }
$Links = @()
if ($cfg.links) { $Links = $cfg.links }

$api = "https://api.telegram.org/bot$Token"
$LogFile = "$PSScriptRoot\support_bot.log"
$StateFile = "$PSScriptRoot\.state.json"
$LockFile  = "$PSScriptRoot\.bot.lock"

function Write-Log([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $m
    Write-Host $line
    # تدوير السجل: لا يتجاوز 1 ميجابايت
    try {
        if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length -gt 1MB)) {
            $keep = Get-Content $LogFile -Tail 800
            Set-Content -Path $LogFile -Value $keep -Encoding UTF8
        }
        Add-Content -Path $LogFile -Value $line -Encoding UTF8
    } catch { }
}

# --- منع تشغيل نسختين معاً (تعارض 409 مع تيليجرام) ---
function Acquire-Lock {
    if (Test-Path $LockFile) {
        $old = 0
        try { $old = [int](Get-Content $LockFile -Raw).Trim() } catch { $old = 0 }
        if ($old -gt 0) {
            $alive = $false
            try { $alive = [bool](Get-Process -Id $old -ErrorAction SilentlyContinue) } catch { }
            if ($alive) {
                Write-Log "توجد نسخة أخرى تعمل (PID $old) — الخروج."
                exit 0
            }
        }
    }
    Set-Content -Path $LockFile -Value $PID -Encoding ASCII
}
function Release-Lock {
    try { Remove-Item $LockFile -Force -ErrorAction SilentlyContinue } catch { }
}
trap { Release-Lock; break }

# 🛡️ حارس السلامة: البوت لا يحظر ولا يطرد ولا يكتم أي مستخدم أبداً.
#    القائمة أدناه تُرفض قبل أي نداء للـTelegram API.
$script:ForbiddenMethods = @(
    'banChatMember', 'restrictChatMember', 'unbanChatMember', 'unbanChatSenderChat',
    'setChatPermissionsForAll', 'kickChatMember', 'banChatSenderChat'
)

function Tg([string]$Method, $Body) {
    if ($script:ForbiddenMethods -contains $Method) {
        Write-Log "BLOCKED unsafe method: $Method (حارس السلامة)"
        return @{ ok = $false; description = 'blocked by safety guard' }
    }
    try {
        if ($null -eq $Body) {
            $r = Invoke-RestMethod -Uri "$api/$Method" -Method Get -TimeoutSec 90
        } else {
            $j = $Body | ConvertTo-Json -Depth 10 -Compress
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($j)
            $r = Invoke-RestMethod -Uri "$api/$Method" -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes -TimeoutSec 90
        }
        return $r
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match '409') {
            Write-Log "تعارض 409 — نسخة أخرى تستقبل التحديثات. الخروج."
            Release-Lock
            exit 0
        }
        Write-Log "API error ($Method): $msg"
        return $null
    }
}

# ------------------------------------------------------------------ كشف السبام
# ⚠️ نفس القواعد مطبَّقة في support-bot.js — حافظ على التطابق.
$SpamPatterns = @(
    '(^|[\s(])@[A-Za-z0-9_]{4,}',
    '\b(t\.me|telegram\.me|telegram\.dog|telegram\.pw|telesco\.pe)/',
    '\bhttps?://',
    '\bwww\.[A-Za-z0-9-]+\.[A-Za-z]{2,}',
    '\b[a-z0-9][a-z0-9-]{1,}\.(com|net|org|io|xyz|top|link|ru|ir|cc|app|dev|info|co|uk|sa|ae|eg|ps|ly)\b',
    '\b\d{9,}\b',
    '\b(vip|airdrop|giveaway|freemoney|free\s+money|click\s?here|invite\s?only|mining|invest\s?now|boost\s+your)\b'
)
$SpamWords = @("اضغط هنا", "اضغط على الرابط", "hxxp", "sxxp", "join now", "register now")

function Test-SpamText([string]$text) {
    if (-not $text) { return $false }
    foreach ($p in $SpamPatterns) {
        if ($text -match $p) { return $true }
    }
    $low = " " + $text.ToLower() + " "
    foreach ($w in $SpamWords) {
        if ($low.Contains($w.ToLower())) { return $true }
    }
    return $false
}

function Test-SpamMessage($m) {
    if ($m.forward_origin -or $m.forward_from) { return $true }
    if ($m.sticker)     { return $true }
    if ($m.animation)   { return $true }
    if ($m.voice)       { return $true }
    if ($m.video_note)  { return $true }
    if ($m.contact)     { return $true }
    if ($m.dice)        { return $true }
    if ($m.poll)        { return $true }
    if ($m.game)        { return $true }
    if ($m.text -and (Test-SpamText $m.text)) { return $true }
    if ($m.caption -and (Test-SpamText $m.caption)) { return $true }
    return $false
}

# ------------------------------------------------------------------ نصوص الردود
function Get-Template {
@"
🛠️ <b>وصلت مشكلك</b> — شكراً لك 👋

لتسريع الحل، أرسل هذه التفاصيل:

1️⃣ موديل الجهاز + إصدار أندرويد
2️⃣ نوع مدير الروت (Magisk / KernelSU) ونسخته
3️⃣ رقم إصدار FALCON (من وصف الوحدة)
4️⃣ نتيجة الفحص: أخضر واحد أم ثلاثة؟ وما الرسالة؟
5️⃣ 📎 صورة للخطأ إن وُجدت

⏳ نرد خلال ساعات قليلة بإذن الله.
"@
}

function Get-Rules {
@"
📋 <b>قواعد مجموعة الدعم</b>

✅ اكتب مشكلتك بالتفصيل (نص عادي فقط).
❌ يُحذف فوراً: أي رابط أو معرّف تيليجرام أو رسالة سبام.
⏱️ رسالة واحدة كل $SlowMode ثوانٍ لكل شخص.
📎 الصور Screenshots مسموحة ومفيدة جداً.
🚫 لا إعلانات ولا عروض ولا روابط دعوة.
🤝 لا حظر ولا طرد — البوت يحذف الرسائل فقط.

🔗 /links — روابط المشروع
📋 /id — معرّفك الرقمي
"@
}

function Get-Links {
    if (-not $Links -or $Links.Count -eq 0) { return "🔗 <b>روابط FALCON</b>`n`nلم تُضبط الروابط بعد." }
    $t = "🔗 <b>روابط FALCON</b>`n"
    foreach ($l in $Links) { $t += "`n• $($l.title) — $($l.url)" }
    return $t
}

function Get-Start {
@"
🛡️ <b>FALCON SUPPORT</b>
<i>مجموعة الدعم الرسمية — FALCON STORE ROOT</i>

أهلاً بك 👋
اكتب مشكلتك هنا وسأجمع لك البيانات المطلوبة، ويرد عليك المشرف.

💡 <b>لماذا هذه المجموعة؟</b>
لأن أسئلة ومشكلات المستخدمين كانت تتشتّت في التعليقات والرسائل الخاصة، فتفقد غيرها وتضيع الحلول القيّمة. هنا مكان واحد والحل يبقى للجميع.

/rules — القواعد
/links — روابط المشروع
/id — معرّفك الرقمي
"@
}

# ------------------------------------------------------------------- الحالة
$state = @{ seen = @{}; slowSet = @{} }
if (Test-Path $StateFile) { try { $state = Get-Content $StateFile -Raw | ConvertFrom-Json -AsHashtable } catch { } }

# --- إشعار المشرف عن الرسائل المحذوفة (بحد أقصى مرة كل 10 دقائق) ---
# ⚠️ البوت لا يستطيع بدء محادثة خاصة مع المستخدم ⇒ نستعمل القناة كبديل.
$NotifyState = "$PSScriptRoot\.notify.state"
function Notify-Spam([string]$chatTitle, [string]$who, [string]$preview) {
    try {
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $last = 0
        if (Test-Path $NotifyState) { try { $last = [int64](Get-Content $NotifyState -Raw) } catch { $last = 0 } }
        if (($now - $last) -lt 600) { return }
        Set-Content -Path $NotifyState -Value $now -Encoding ASCII
        $text = "🧹 حُذفت رسالة سبام في $chatTitle`n👤 من: $who`n🔎 السبب: $preview"
        $sent = $false
        if ($AdminId) {
            $r = Tg "sendMessage" @{ chat_id = $AdminId; text = $text }
            if ($r -and $r.ok) { $sent = $true }
        }
        if (-not $sent -and $ChannelId) {
            $null = Tg "sendMessage" @{ chat_id = $ChannelId; text = $text }
        }
    } catch { }
}

# ------------------------------------------------------------------- التشغيل
$me = Tg "getMe" $null
if (-not $me -or -not $me.ok) { throw "فشل الاتصال بالبوت — تحقق من التوكن" }
Acquire-Lock
Write-Log "Bot: @$($me.result.username) (id $($me.result.id))"

# ⚠️ long-polling يتطلب حذف الـwebhook
$wh = Tg "getWebhookInfo" $null
if ($wh -and $wh.ok -and $wh.result.url) {
    Write-Log "يوجد webhook نشط ($($wh.result.url)) — سيتم حذفه حتى يعمل هذا البوت محلياً."
    $null = Tg "deleteWebhook" @{ drop_pending_updates = $false }
    Write-Log "تم حذف الـwebhook."
}

$offset = 0
Write-Log "بدأ الاستقبال… (Ctrl+C للإيقاف)"

while ($true) {
    try {
        $up = Tg "getUpdates" @{ offset = "$offset"; timeout = 45; allowed_updates = '["message","edited_message","channel_post"]' }
        if (-not $up -or -not $up.ok) { Start-Sleep -Seconds 5; continue }
        foreach ($u in $up.result) {
            $offset = [int]$u.update_id + 1
            $m = $u.message
            if (-not $m) { $m = $u.edited_message }
            if (-not $m) { $m = $u.channel_post }
            if (-not $m -or -not $m.chat) { continue }

            $chat = $m.chat
            $isGroup = ($chat.type -eq "group" -or $chat.type -eq "supergroup")
            $text = if ($m.text) { [string]$m.text } else { "" }
            $from = $m.from
            $fromId = if ($from) { [string]$from.id } else { "" }
            $isAdmin = ($AdminId -ne "" -and $fromId -eq $AdminId)

            # 🛡️ البوت لا يلمس رسائل أي بوت (ولا رسائله هو) — أبداً
            if ($from -and $from.is_bot) { continue }

            # --- الأوامر ---
            if ($text -like "/*") {
                $cmd = ($text -split "\s+")[0].ToLower().Replace("@falcon_verify_2026_bot", "")
                switch ($cmd) {
                    "/links" { $null = Tg "sendMessage" @{ chat_id = "$($chat.id)"; text = (Get-Links); parse_mode = "HTML" }; continue }
                    "/rules" { $null = Tg "sendMessage" @{ chat_id = "$($chat.id)"; text = (Get-Rules); parse_mode = "HTML" }; continue }
                    "/id" {
                        $un = if ($from.username) { "@$($from.username)" } else { "—" }
                        $null = Tg "sendMessage" @{ chat_id = "$($chat.id)"; text = "🆔 معرّفك: ``$fromId```n👤 اسمك: $($from.first_name)`n🔗 $un" }
                        continue
                    }
                }
                if ($isAdmin -and $cmd -eq "/slow") {
                    $arg = ($text -split "\s+")[1]
                    if ($arg -match '^\d+$') {
                        $r = Tg "setChatSlowModeDelay" @{ chat_id = "$($chat.id)"; slow_mode_delay = [int]$arg }
                        $msg = if ($r.ok) { "⏱️ تم ضبط الرسائل البطيئة: $arg ثانية" } else { "⚠️ فشل: $($r.description)" }
                        $null = Tg "sendMessage" @{ chat_id = "$($chat.id)"; text = $msg }
                    }
                    continue
                }
                if ($isAdmin -and $cmd -eq "/broadcast") {
                    $body = ($text -replace "^/\S+\s*", "")
                    if ($body) { $null = Tg "sendMessage" @{ chat_id = "$($chat.id)"; text = "📢 $body" } }
                    continue
                }
            }

            if (-not $isGroup) { continue }

            # --- الرسائل البطيئة (مرة واحدة لكل مجموعة) ---
            $ck = "$($chat.id)"
            if (-not $state.slowSet.ContainsKey($ck)) {
                $null = Tg "setChatSlowModeDelay" @{ chat_id = $ck; slow_mode_delay = $SlowMode }
                $state.slowSet[$ck] = $SlowMode
                Write-Log "تم تفعيل الرسائل البطيئة ($SlowMode ثانية) في $($chat.title)"
            }

            # --- الحذف الفوري ---
            if (-not $NoDelete -and (Test-SpamMessage $m)) {
                $d = Tg "deleteMessage" @{ chat_id = $ck; message_id = "$($m.message_id)" }
                if ($d.ok) {
                    $who = if ($from.username) { "@$($from.username)" } else { $fromId }
                    Write-Log "🧹 حُذفت رسالة سبام من $who في $($chat.title)"
                    $preview = if ($m.text) { $m.text } elseif ($m.caption) { $m.caption } else { "إعادة توجيه / ملصق" }
                    if ($preview.Length -gt 120) { $preview = $preview.Substring(0, 120) }
                    Notify-Spam "$($chat.title)" $who $preview
                }
                continue
            }

            # --- رسالة مشكلة حقيقية → رد بالقالب ---
            if ($text -and -not $text.StartsWith("/") -and $fromId) {
                $last = 0
                if ($state.seen.ContainsKey($fromId)) { $last = [int64]$state.seen[$fromId] }
                if (([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - $last) -gt 1800000) {
                    $state.seen[$fromId] = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                    $null = Tg "sendMessage" @{ chat_id = $ck; text = (Get-Template); parse_mode = "HTML"; reply_to_message_id = "$($m.message_id)" }
                }
            }
        }
        if ($Once) { break }
    } catch {
        Write-Log "خطأ في الحلقة: $($_.Exception.Message)"
        Start-Sleep -Seconds 5
    }
    try { $state | ConvertTo-Json -Depth 5 | Set-Content -Path $StateFile -Encoding UTF8 } catch { }
}
