/**
 * ============================================================================
 *  FALCON SUPPORT BOT — بوت الدعم لقناة FALCON_KERNEL_PRO
 *  Cloudflare Worker (يعمل 24/7 · مجاني · بدون خادم)
 * ============================================================================
 *
 *  ما يفعله:
 *   1) حذف فوري لأي رسالة فيها رابط أو معرّف تيليجرام أو سبام.
 *   2) الرد على رسائل المشكلة الحقيقية بقالب بيانات (مرة كل 30 دقيقة لكل شخص).
 *   3) تفعيل "الرسائل البطيئة" (Slow Mode) = 10 ثوانٍ لكل شخص.
 *   4) أوامر للمشرفين: /slow /silent /stats /broadcast /links /rules /id
 *
 *  المسار:  POST /tg/webhook/<SECRET>
 *  يُسجَّل كـ Telegram Webhook على البوت.
 *
 *  الإعداد (متغيرات Cloudflare):
 *    BOT_TOKEN   = توكن البوت
 *    TG_SECRET   = مسار سري (نفسه في رابط الـwebhook)
 *    ADMIN_ID    = معرّف تيليجرام للمشرف (رقم)
 *    CHANNEL_ID  = معرّف القناة (رقم سالب) لإرسال التقارير
 *    SLOW_MODE   = ثواني الرسائل البطيئة (افتراضي 10)
 *    LINKS_JSON  = JSON بالروابط
 * ============================================================================
 */

const DEFAULTS = {
  slowMode: 10,
  templateCooldownMs: 30 * 60 * 1000, // 30 دقيقة
  adminId: "",
  channelId: "",
};

// ---------------------------------------------------------------- الإعدادات
function readConfig(env) {
  let links = [];
  try {
    if (env.LINKS_JSON) links = JSON.parse(env.LINKS_JSON);
  } catch (_) {
    links = [];
  }
  return {
    botToken: env.BOT_TOKEN || "",
    secret: env.TG_SECRET || "",
    adminId: env.ADMIN_ID || DEFAULTS.adminId,
    channelId: env.CHANNEL_ID || DEFAULTS.channelId,
    slowMode: parseInt(env.SLOW_MODE || DEFAULTS.slowMode, 10) || DEFAULTS.slowMode,
    links,
  };
}

// ---------------------------------------------------------------------------
// 🛡️ ضمانة السلامة: البوت لا يحظر ولا يطرد ولا يكتم أي مستخدم أبداً.
//    القائمة أدناه تُفحص قبل كل نداء للـTelegram API، وأي محاولة حظر تُرفض.
//    البوت يحذف الرسائل فقط (رسائل سبام) — وهذا لا يمسّ أي شخص.
// ---------------------------------------------------------------------------
const FORBIDDEN_METHODS = new Set([
  "banChatMember",
  "restrictChatMember",
  "unbanChatMember",
  "unbanChatSenderChat",
  "setChatPermissionsForAll",
  "kickChatMember",
  "banChatSenderChat",
]);

// ------------------------------------------------------------- كشف السبام
// ⚠️ نفس القواعد مطبَّقة في bot-local.ps1 (نسخة PowerShell) — حافظ على التطابق.
const SPAM_PATTERNS = [
  // معرّف تيليجرام: @username
  /(^|[\s(])@[A-Za-z0-9_]{4,}/,
  // روابط تيليجرام
  /\b(t\.me|telegram\.me|telegram\.dog|telegram\.pw|telesco\.pe)\//i,
  // روابط عامة
  /\bhttps?:\/\//i,
  /\bwww\.[A-Za-z0-9-]+\.[A-Za-z]{2,}/i,
  // نطاقات مكتوبة بدون بروتوكول
  /\b[a-z0-9][a-z0-9-]{1,}\.(com|net|org|io|xyz|top|link|ru|ir|cc|app|dev|info|co|uk|sa|ae|eg|ps|ly)\b/i,
  // معرّفات تيليجرام رقمية (9 أرقام فأكثر)
  /\b\d{9,}\b/,
  // كلمات سبام شائعة
  /\b(vip|airdrop|giveaway|freemoney|free\s+money|click\s?here|invite\s?only|mining|invest\s?now|boost\s+your)\b/i,
];

// ⛔ كلمات عربية مختصرة عمداً: أي كلمة عامة (تسجيل/اشتراك/ربح...) تُحذف
//    رسالات شرعية. الاكتشاف يعتمد على الروابط والمعرّفات لا على الكلمات.
const SPAM_WORDS_AR = [
  "اضغط هنا",
  "اضغط على الرابط",
  "hxxp",
  "sxxp",
  "join now",
  "register now",
];

function isSpamText(text) {
  if (!text) return false;
  for (const re of SPAM_PATTERNS) {
    if (re.test(text)) return true;
  }
  const low = " " + text.toLowerCase() + " ";
  for (const w of SPAM_WORDS_AR) {
    if (low.includes(w.toLowerCase())) return true;
  }
  return false;
}

// رسالة غير نصية تُعتبر سبام (ملصق/جيف/صوت) — الصور مستثناة (مفيدة للدعم)
function isSpamMedia(msg) {
  if (msg.forward_origin || msg.forward_from) return true; // رسالة مُعاد توجيهها
  if (msg.sticker) return true;
  if (msg.animation) return true;
  if (msg.voice) return true;
  if (msg.video_note) return true;
  if (msg.contact) return true;
  if (msg.dice) return true;
  if (msg.poll) return true;
  if (msg.game) return true;
  return false;
}

function isSpamMessage(msg) {
  if (isSpamMedia(msg)) return true;
  if (msg.text && isSpamText(msg.text)) return true;
  if (msg.caption && isSpamText(msg.caption)) return true;
  return false;
}

// --------------------------------------------------------------- نصوص الردود
function templateText() {
  return [
    "🛠️ *وصلت مشكلتك* — شكراً لك 👋",
    "",
    "لتسريع الحل، أرسل هذه التفاصيل:",
    "",
    "1️⃣ موديل الجهاز + إصدار أندرويد",
    "2️⃣ نوع مدير الروت (Magisk / KernelSU) ونسخته",
    "3️⃣ رقم إصدار FALCON (من وصف الوحدة)",
    "4️⃣ نتيجة الفحص: أخضر واحد أم ثلاثة؟ وما الرسالة؟",
    "5️⃣ 📎 صورة للخطأ إن وُجدت",
    "",
    "⏳ نرد خلال ساعات قليلة بإذن الله.",
  ].join("\n");
}

function rulesText(cfg) {
  return [
    "📋 *قواعد مجموعة الدعم*",
    "",
    "✅ اكتب مشكلتك بالتفصيل (نص عادي فقط).",
    "❌ يُحذف فوراً: أي رابط أو معرّف تيليجرام أو رسالة سبام.",
    "⏱️ رسالة واحدة كل 10 ثوانٍ لكل شخص.",
    "📎 الصور Screenshots مسموحة ومفيدة جداً.",
    "🚫 لا إعلانات ولا عروض ولا روابط دعوة.",
    "🤝 لا حظر ولا طرد — البوت يحذف الرسائل فقط.",
    "",
    "🔗 /links — روابط المشروع",
    "📋 /id — معرّفك الرقمي",
  ].join("\n");
}

function linksText(cfg) {
  const lines = ["🔗 *روابط FALCON*", ""];
  if (cfg.links && cfg.links.length) {
    for (const l of cfg.links) {
      lines.push(`${l.title} — ${l.url}`);
    }
  } else {
    lines.push("لم تُضبط الروابط بعد.");
  }
  return lines.join("\n");
}

function startText(cfg) {
  return [
    "🛡️ *FALCON SUPPORT*",
    "*مجموعة الدعم الرسمية — FALCON STORE ROOT*",
    "",
    "أهلاً بك 👋",
    "اكتب مشكلتك هنا وسأجمع لك البيانات المطلوبة، ويرد عليك المشرف.",
    "",
    "💡 *لماذا هذه المجموعة؟*",
    "لأن أسئلة ومشكلات المستخدمين كانت تتشتّت في التعليقات والرسائل الخاصة، فتفقد غيرها وتضيع الحلول القيّمة. هنا مكان واحد والحل يبقى للجميع.",
    "",
    "/rules — القواعد",
    "/links — روابط المشروع",
    "/id — معرّفك الرقمي",
  ].join("\n");
}

// --------------------------------------------------------------- استدعاء API
async function tg(cfg, method, body) {
  if (!cfg.botToken) return { ok: false, description: "no bot token" };
  // 🛡️ حارس السلامة: لا يُسمح بأي نداء حظر/طرد/كتم — إطلاقاً
  if (FORBIDDEN_METHODS.has(method)) {
    console.error(`[FALCON-BOT] BLOCKED unsafe method: ${method}`);
    return { ok: false, description: "blocked by safety guard" };
  }
  const url = `https://api.telegram.org/bot${cfg.botToken}/${method}`;
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body || {}),
    });
    return await res.json();
  } catch (e) {
    return { ok: false, description: String(e) };
  }
}

// ------------------------------------------------------------------- الحالة
// ذاكرة مؤقتة داخل الـisolate (تُصفَّر عند إعادة تشغيل الـWorker) — كافية
// لمنع تكرار القالب على نفس الشخص خلال فترة قصيرة.
const seen = new Map();
let lastNotify = 0;

function shouldReply(userId) {
  const now = Date.now();
  const last = seen.get(userId) || 0;
  if (now - last < DEFAULTS.templateCooldownMs) return false;
  seen.set(userId, now);
  if (seen.size > 5000) {
    for (const [k, v] of seen) if (now - v > DEFAULTS.templateCooldownMs) seen.delete(k);
  }
  return true;
}

// ------------------------------------------------------------ معالجة التحديث
async function handleUpdate(cfg, update, env) {
  const msg = update.message || update.edited_message || update.channel_post;
  if (!msg || !msg.chat) return;

  const chat = msg.chat;
  const isGroup = chat.type === "group" || chat.type === "supergroup";
  const text = msg.text || "";
  const from = msg.from || {};
  const isAdmin = cfg.adminId && String(from.id) === String(cfg.adminId);

  // 🛡️ البوت لا يلمس رسائل أي بوت (ولا رسائله هو) — أبداً
  if (from.is_bot) return;

  // --- أوامر المشرف (تعمل في القناة أيضاً) ---
  if (text.startsWith("/")) {
    const [cmdRaw, ...rest] = text.split(/\s+/);
    const cmd = cmdRaw.split("@")[0].toLowerCase();

    if (cmd === "/links") {
      await tg(cfg, "sendMessage", { chat_id: chat.id, text: linksText(cfg), parse_mode: "Markdown" });
      return;
    }
    if (cmd === "/rules") {
      await tg(cfg, "sendMessage", { chat_id: chat.id, text: rulesText(cfg), parse_mode: "Markdown" });
      return;
    }
    if (cmd === "/id" && from.id) {
      await tg(cfg, "sendMessage", {
        chat_id: chat.id,
        text: `🆔 معرّفك: \`${from.id}\`\n👤 اسمك: ${from.first_name || ""}\n🔗 @${from.username || "—"}`,
      });
      return;
    }
    if (isAdmin) {
      if (cmd === "/slow") {
        const n = parseInt(rest[0], 10);
        if (!n || n < 0 || n > 3600) {
          await tg(cfg, "sendMessage", { chat_id: chat.id, text: "⚠️ الاستعمال: /slow <0..3600>" });
        } else {
          const r = await tg(cfg, "setChatSlowModeDelay", { chat_id: chat.id, slow_mode_delay: n });
          await tg(cfg, "sendMessage", {
            chat_id: chat.id,
            text: r.ok ? `⏱️ تم ضبط الرسائل البطيئة: ${n} ثانية` : `⚠️ فشل: ${r.description}`,
          });
        }
        return;
      }
      if (cmd === "/silent") {
        const on = (rest[0] || "").toLowerCase() === "on";
        env.SILENT = on ? "1" : "0";
        await tg(cfg, "sendMessage", { chat_id: chat.id, text: on ? "🔇 تم إيقاف الحذف المؤقت" : "🔊 تم تفعيل الحذف" });
        return;
      }
      if (cmd === "/broadcast") {
        const body = rest.join(" ");
        if (body) await tg(cfg, "sendMessage", { chat_id: chat.id, text: "📢 " + body });
        return;
      }
    }
  }

  if (!isGroup) return;

  // --- تفعيل الرسائل البطيئة (مرة واحدة لكل مجموعة) ---
  if (!env.SLOW_SET || env.SLOW_SET !== String(chat.id)) {
    const r = await tg(cfg, "setChatSlowModeDelay", { chat_id: chat.id, slow_mode_delay: cfg.slowMode });
    if (r.ok) env.SLOW_SET = String(chat.id);
  }

  // --- الحذف الفوري ---
  if (!env.SILENT && isSpamMessage(msg)) {
    const del = await tg(cfg, "deleteMessage", { chat_id: chat.id, message_id: msg.message_id });
    if (del.ok) {
      console.log(`[FALCON-BOT] deleted spam in ${chat.id} by @${from.username || from.id}`);
      // إشعار المشرف (بلا إزعاج: رسالة واحدة مجمّعة)
      // إشعار المشرف (بحد أقصى مرة كل 10 دقائق) — وقناة بديلة لأن البوت
      // لا يستطيع بدء محادثة خاصة مع المستخدم
      const now = Date.now();
      if (now - (lastNotify || 0) > 600000) {
        lastNotify = now;
        const note = `🧹 حُذفت رسالة سبام في ${chat.title || chat.id}\n👤 من: @${from.username || from.id}\n🔎 السبب: ${(msg.text || msg.caption || "إعادة توجيه / ملصق").slice(0, 120)}`;
        let sent = false;
        if (cfg.adminId) {
          const r = await tg(cfg, "sendMessage", { chat_id: cfg.adminId, text: note });
          sent = !!(r && r.ok);
        }
        if (!sent && cfg.channelId) {
          await tg(cfg, "sendMessage", { chat_id: cfg.channelId, text: note });
        }
      }
    }
    return;
  }

  // --- رسالة مشكلة حقيقية → رد بالقالب ---
  if (text && !text.startsWith("/") && shouldReply(from.id)) {
    await tg(cfg, "sendMessage", {
      chat_id: chat.id,
      text: templateText(),
      parse_mode: "Markdown",
      reply_to_message_id: msg.message_id,
    });
  }
}

// -------------------------------------------------------------------- Worker
export default {
  async fetch(request, env) {
    const cfg = readConfig(env);
    const url = new URL(request.url);

    // فحص الصحة
    if (url.pathname === "/tg/health") {
      return new Response(JSON.stringify({ ok: true, bot: "FALCON_SUPPORT_BOT", time: Date.now() }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    // استقبال التحديثات
    const prefix = "/tg/webhook/";
    if (url.pathname.startsWith(prefix) && request.method === "POST") {
      const given = url.pathname.slice(prefix.length);
      if (!cfg.secret || given !== cfg.secret) {
        return new Response("forbidden", { status: 403 });
      }
      let update = null;
      try {
        update = await request.json();
      } catch (_) {
        return new Response("bad request", { status: 400 });
      }
      try {
        await handleUpdate(cfg, update, env);
      } catch (e) {
        console.error("[FALCON-BOT] error:", String(e));
      }
      return new Response("ok", { status: 200 });
    }

    // كل ما عداه: رد بسيط
    return new Response("FALCON Support Bot is running.", {
      headers: { "Content-Type": "text/plain; charset=utf-8" },
    });
  },
};
