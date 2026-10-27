# ==============================================================================
# FALCON SUPPORT BOT — تثبيت التشغيل التلقائي الدائم (Windows)
# ==============================================================================
# يثبّت البوت ليعمل تلقائياً:
#   1) عند تسجيل الدخول إلى Windows  (مجلد Startup — لا يحتاج كلمة مرور)
#   2) مهمة مجدولة في Task Scheduler تُعيد التشغيل عند الفشل/إعادة التشغيل
#   3) إيقاف التشغيل أثناء模式和 إصلاح تلقائي
#
#   powershell -ExecutionPolicy Bypass -File install_autostart.ps1
#   powershell -ExecutionPolicy Bypass -File install_autostart.ps1 -Uninstall
# ==============================================================================
param(
    [string]$Dir = $PSScriptRoot,
    [switch]$Uninstall,
    [switch]$WakeOnTask = $true
)

$ErrorActionPreference = "Continue"
$TaskName = "FALCON Support Bot"
$StartName = "FALCON Support Bot.lnk"

function Say([string]$m, [string]$c = "Gray") { Write-Host $m -ForegroundColor $c }

# ------------------------------------------------------------------ إلغاء التثبيت
if ($Uninstall) {
    try { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop; Say "✓ أُزيلت المهمة المجدولة" "Green" } catch { Say "ℹ لا توجد مهمة مجدولة" }
    $startup = [Environment]::GetFolderPath('Startup')
    $lnk = Join-Path $startup $StartName
    if (Test-Path $lnk) { Remove-Item $lnk -Force; Say "✓ أُزيل اختصار بدء التشغيل" "Green" }
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.CommandLine -like "*bot-local.ps1*" -or $_.CommandLine -like "*watchdog.ps1*" } |
        ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop; Say "✓ أُوقفت عملية $($_.ProcessId)" } catch { } }
    exit 0
}

# ------------------------------------------------------------ اختبارات ما قبل التثبيت
$bot = Join-Path $Dir "bot-local.ps1"
$wd  = Join-Path $Dir "watchdog.ps1"
foreach ($f in @($bot, $wd)) {
    if (-not (Test-Path $f)) { Say "✗ ملف مفقود: $f" "Red"; exit 1 }
}
$errs = $null
[System.Management.Automation.Language.Parser]::ParseFile($bot, [ref]$null, [ref]$errs) | Out-Null
if ($errs -and $errs.Count) { Say "✗ أخطاء صياغة في bot-local.ps1" "Red"; exit 1 }
[System.Management.Automation.Language.Parser]::ParseFile($wd, [ref]$null, [ref]$errs) | Out-Null
if ($errs -and $errs.Count) { Say "✗ أخطاء صياغة في watchdog.ps1" "Red"; exit 1 }
Say "✓ فحص الصياغة سليم" "Green"

# ------------------------------------------------- 1) اختصار مجلد Startup (عند الدخول)
$startup = [Environment]::GetFolderPath('Startup')
$lnk = Join-Path $startup $StartName
try {
    $sh = New-Object -ComObject WScript.Shell
    $sc = $sh.CreateShortcut($lnk)
    $sc.TargetPath = "powershell.exe"
    $sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$wd`""
    $sc.WorkingDirectory = $Dir
    $sc.WindowStyle = 7   # minimized
    $sc.Description = "FALCON Support Bot - watchdog"
    $sc.Save()
    Say "✓ اختصار بدء التشغيل: $lnk" "Green"
} catch {
    Say "⚠️ لم يُنشأ الاختصار: $($_.Exception.Message)" "Yellow"
}

# ------------------------------- 2) مهمة مجدولة: عند الدخول + كل 5 دقائق (للتعافي)
try {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$wd`""
    $t1 = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $t2 = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
        -RepetitionInterval (New-TimeSpan -Minutes 5)
    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
    if ($WakeOnTask) {
        try { $set.WakeToRun = $true } catch { }
    }
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($t1, $t2) `
        -Settings $set -Description "FALCON Support Bot - watcher دائم" -Force `
        -User "$env:USERDOMAIN\$env:USERNAME" -RunLevel Highest -ErrorAction Stop | Out-Null
    Say "✓ المهمة المجدولة '$TaskName' مسجّلة (عند الدخول + كل 5 دقائق)" "Green"
} catch {
    Say "⚠️ تعذّر تسجيل المهمة المجدولة: $($_.Exception.Message)" "Yellow"
}

# ------------------------------------------------------------ 3) تشغيل فوري الآن
$running = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like "*watchdog.ps1*" })
if ($running.Count -eq 0) {
    Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$wd`"" -WindowStyle Hidden
    Start-Sleep -Seconds 4
    Say "✓ شُغِّل المراقب الآن" "Green"
} else {
    Say "ℹ المراقب يعمل بالفعل (PID $($running[0].ProcessId))" "Yellow"
}

# ------------------------------------------------------------------ 4) تحقق
Start-Sleep -Seconds 8
$bots = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like "*bot-local.ps1*" })
Say ""
Say "=== الحالة ===" "Cyan"
Say "  عمليات البوت : $($bots.Count)"
if (Test-Path (Join-Path $Dir "support_bot.log")) {
    Say "  آخر السجل    :"
    Get-Content (Join-Path $Dir "support_bot.log") -Tail 3 | ForEach-Object { Say "    $_" "DarkGray" }
}
Say ""
Say "✅ تم التثبيت — البوت يعمل تلقائياً بعد كل إعادة تشغيل للجهاز." "Green"
