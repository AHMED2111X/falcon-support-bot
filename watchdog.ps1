# ==============================================================================
# FALCON SUPPORT BOT — المراقب الدائم (Watchdog)
# ==============================================================================
# يبقى البوت حياً 24/7 على هذا الجهاز:
#   • يفحص كل 60 ثانية إن كان البوت يعمل
#   • يعيد تشغيله فوراً إن سقط (انقطاع شبكة / إغلاق للخطأ)
#   • يمنع تشغيل نسختين معاً (تعارض 409 مع تيليجرام)
#   • يوقظ الجهاز من السبات لتشغيل البوت
#
#   powershell -ExecutionPolicy Bypass -File watchdog.ps1
# ==============================================================================
param(
    [string]$BotScript = "$PSScriptRoot\bot-local.ps1",
    [int]$CheckSeconds = 60
)

$ErrorActionPreference = "Continue"
$LogFile = "$PSScriptRoot\watchdog.log"

function WLog([string]$m) {
    $line = "[{0}] [watchdog] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $m
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Get-BotProc {
    try {
        return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop |
            Where-Object { $_.CommandLine -like "*bot-local.ps1*" })
    } catch { return @() }
}

WLog "بدأ المراقب — يتابع: $BotScript"
$last = $null

while ($true) {
    try {
        $procs = Get-BotProc
        if ($procs.Count -eq 0) {
            WLog "البوت متوقف — إعادة تشغيل…"
            Start-Process powershell `
                -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$BotScript`"" `
                -WindowStyle Hidden
            Start-Sleep -Seconds 12
            $n = (Get-BotProc).Count
            WLog "تمت إعادة التشغيل (عدد النسخ الآن: $n)"
            if ($n -gt 1) {
                # حذف النسخ المكرّرة (النسخة الأقدم) لمنع تعارض getUpdates
                $all = Get-BotProc
                for ($i = 1; $i -lt $all.Count; $i++) {
                    try { Stop-Process -Id $all[$i].ProcessId -Force -ErrorAction Stop; WLog "أُغلقت نسخة مكرّرة (PID $($all[$i].ProcessId))" } catch { }
                }
            }
        } else {
            $cur = ($procs | ForEach-Object { $_.ProcessId }) -join ','
            if ($cur -ne $last) { WLog "البوت يعمل (PID: $cur)"; $last = $cur }
        }
    } catch {
        WLog "خطأ في المراقبة: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds $CheckSeconds
}
