type Env = {
  TELEGRAM_BOT_TOKEN: string;
  ADMIN_IDS: string; // "113872890,123"
  SUPABASE_URL: string; // https://xxxx.supabase.co
  SUPABASE_SERVICE_ROLE_KEY: string;
  OPENAI_API_KEY?: string; // For natural language processing
};

type TelegramUpdate = {
  update_id: number;
  message?: TelegramMessage;
  callback_query?: TelegramCallbackQuery;
};

type TelegramMessage = {
  message_id: number;
  date: number;
  text?: string;
  chat: { id: number; type: string };
  from?: { id: number; username?: string; first_name?: string; last_name?: string };
};

type TelegramCallbackQuery = {
  id: string;
  from: { id: number; username?: string; first_name?: string; last_name?: string };
  message?: TelegramMessage;
  data?: string;
};

type InlineKeyboardButton = {
  text: string;
  callback_data?: string;
  url?: string;
};

type InlineKeyboardMarkup = {
  inline_keyboard: InlineKeyboardButton[][];
};

// ========== Helpers ==========

function parseAdminIds(raw: string): Set<number> {
  return new Set(
    raw
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean)
      .map((s) => Number(s))
      .filter((n) => Number.isFinite(n) && n > 0)
  );
}

function requireEnv(env: Env, key: keyof Env): string {
  const v = env[key];
  if (!v || !String(v).trim()) throw new Error(`Missing env var: ${String(key)}`);
  return String(v);
}

async function tgCall<T>(env: Env, method: string, body: unknown): Promise<T> {
  const token = requireEnv(env, "TELEGRAM_BOT_TOKEN");
  const url = `https://api.telegram.org/bot${token}/${method}`;
  const resp = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  const json = (await resp.json()) as any;
  if (!resp.ok || !json?.ok) {
    throw new Error(`Telegram API error (${method}): ${JSON.stringify(json)}`);
  }
  return json.result as T;
}

async function sendMessage(
  env: Env,
  chatId: number,
  text: string,
  replyMarkup?: InlineKeyboardMarkup,
  parseMode?: string
) {
  await tgCall(env, "sendMessage", {
    chat_id: chatId,
    text,
    parse_mode: parseMode ?? "HTML",
    disable_web_page_preview: true,
    reply_markup: replyMarkup,
  });
}

async function editMessage(
  env: Env,
  chatId: number,
  messageId: number,
  text: string,
  replyMarkup?: InlineKeyboardMarkup
) {
  await tgCall(env, "editMessageText", {
    chat_id: chatId,
    message_id: messageId,
    text,
    parse_mode: "HTML",
    disable_web_page_preview: true,
    reply_markup: replyMarkup,
  });
}

async function answerCallbackQuery(env: Env, callbackQueryId: string, text?: string) {
  await tgCall(env, "answerCallbackQuery", {
    callback_query_id: callbackQueryId,
    text,
  });
}

// ========== Supabase ==========

async function supabaseRequest<T>(
  env: Env,
  path: string,
  init?: { method?: string; body?: unknown; headers?: Record<string, string> }
): Promise<{ data: T; headers: Headers }> {
  const base = requireEnv(env, "SUPABASE_URL").replace(/\/+$/, "");
  const key = requireEnv(env, "SUPABASE_SERVICE_ROLE_KEY");
  const url = `${base}${path.startsWith("/") ? "" : "/"}${path}`;
  const resp = await fetch(url, {
    method: init?.method ?? "GET",
    headers: {
      apikey: key,
      authorization: `Bearer ${key}`,
      accept: "application/json",
      ...(init?.body ? { "content-type": "application/json" } : {}),
      ...(init?.headers ?? {}),
    },
    body: init?.body ? JSON.stringify(init.body) : undefined,
  });
  const text = await resp.text();
  if (!resp.ok) {
    throw new Error(`Supabase error ${resp.status}: ${text}`);
  }
  const data = (text ? JSON.parse(text) : null) as T;
  return { data, headers: resp.headers };
}

function parseContentRangeTotal(h: Headers): number | null {
  const cr = h.get("content-range") ?? h.get("Content-Range");
  if (!cr) return null;
  const m = cr.match(/\/(\d+|\*)$/);
  if (!m) return null;
  if (m[1] === "*") return null;
  const n = Number(m[1]);
  return Number.isFinite(n) ? n : null;
}

async function countTable(env: Env, table: string, filter?: string): Promise<number> {
  const q = filter ? `&${filter}` : "";
  const { headers } = await supabaseRequest<unknown[]>(env, `/rest/v1/${table}?select=id${q}`, {
    headers: { prefer: "count=exact", range: "0-0" },
  });
  const total = parseContentRangeTotal(headers);
  if (typeof total === "number") return total;

  const pageSize = 1000;
  let offset = 0;
  let count = 0;
  while (true) {
    const { data } = await supabaseRequest<Array<{ id: string }>>(
      env,
      `/rest/v1/${table}?select=id${q}&order=created_at.desc&limit=${pageSize}&offset=${offset}`
    );
    if (data.length === 0) break;
    count += data.length;
    if (data.length < pageSize) break;
    offset += pageSize;
    if (offset > 200_000) break;
  }
  return count;
}

async function sumEnergy(env: Env, userId?: string): Promise<number> {
  const pageSize = 1000;
  let offset = 0;
  let total = 0;
  while (true) {
    const filter = userId ? `&user_id=eq.${encodeURIComponent(userId)}` : "";
    const { data } = await supabaseRequest<Array<{ delta: number }>>(
      env,
      `/rest/v1/energy_ledger?select=delta&order=created_at.desc&limit=${pageSize}&offset=${offset}${filter}`
    );
    if (data.length === 0) break;
    total += data.reduce((acc, r) => acc + (r.delta ?? 0), 0);
    if (data.length < pageSize) break;
    offset += pageSize;
    if (offset > 200_000) break;
  }
  return total;
}

async function getUser(env: Env, userId: string) {
  const { data } = await supabaseRequest<any[]>(
    env,
    `/rest/v1/users?select=id,email,nickname,country,created_at,is_banned,ban_reason,ban_until,energy_spent_lifetime,batteries_collected,current_steps_today,current_energy_balance&id=eq.${encodeURIComponent(userId)}`
  );
  return data[0] ?? null;
}

async function listUsers(env: Env, limit: number = 10) {
  const { data } = await supabaseRequest<any[]>(
    env,
    `/rest/v1/users?select=id,email,nickname,country,created_at,current_energy_balance&order=created_at.desc&limit=${limit}`
  );
  return data ?? [];
}

async function listUserShields(env: Env, userId: string) {
  const { data } = await supabaseRequest<any[]>(
    env,
    `/rest/v1/shields?select=id,user_id,bundle_id,mode,level,updated_at&user_id=eq.${encodeURIComponent(userId)}`
  );
  return data ?? [];
}

async function grantEnergy(env: Env, userId: string, delta: number, reason?: string) {
  await supabaseRequest(env, `/rest/v1/energy_ledger`, {
    method: "POST",
    headers: { prefer: "return=minimal" },
    body: { user_id: userId, delta, reason: reason ?? null },
  });
}

async function banUser(env: Env, userId: string, reason: string, until?: Date) {
  await supabaseRequest(env, `/rest/v1/users?id=eq.${encodeURIComponent(userId)}`, {
    method: "PATCH",
    headers: { prefer: "return=minimal" },
    body: {
      is_banned: true,
      ban_reason: reason,
      ban_until: until?.toISOString() ?? null,
    },
  });
}

async function unbanUser(env: Env, userId: string) {
  await supabaseRequest(env, `/rest/v1/users?id=eq.${encodeURIComponent(userId)}`, {
      method: "PATCH",
    headers: { prefer: "return=minimal" },
    body: { is_banned: false, ban_reason: null, ban_until: null },
  });
}

// ========== Nickname Generation ==========

const NICKNAME_PREFIXES = [
  // Doom-themed
  "Doom", "Dark", "Shadow", "Chaos", "Void", "Cyber", "Neo", "Night", "Storm", "Iron",
  // Walk-themed
  "Swift", "Step", "Stride", "Path", "Trail", "Road", "Walk", "Run", "Sprint", "Dash",
  // Social-themed
  "Scroll", "Swipe", "Tap", "Click", "Like", "Share", "Post", "Feed", "Viral", "Trend",
];

const NICKNAME_SUFFIXES = [
  // Doom-themed
  "Slayer", "Hunter", "Rider", "Walker", "Master", "Lord", "Knight", "Warrior", "Phantom", "Reaper",
  // Walk-themed
  "Stepper", "Runner", "Mover", "Pacer", "Tracker", "Chaser", "Seeker", "Finder", "Blazer", "Cruiser",
  // Social-themed
  "Scroller", "Surfer", "Diver", "Lurker", "Poster", "Sharer", "Viewer", "Watcher", "Browser", "Streamer",
];

function generateRandomNickname(): string {
  const prefix = NICKNAME_PREFIXES[Math.floor(Math.random() * NICKNAME_PREFIXES.length)];
  const suffix = NICKNAME_SUFFIXES[Math.floor(Math.random() * NICKNAME_SUFFIXES.length)];
  const number = Math.floor(Math.random() * 90) + 10; // 10-99
  return `${prefix}${suffix}${number}`;
}

async function isNicknameUnique(env: Env, nickname: string): Promise<boolean> {
  const rows = await supabaseRequest<{ id: string }[]>(
    env,
    `/rest/v1/users?nickname=eq.${encodeURIComponent(nickname)}&select=id&limit=1`
  );
  return rows.length === 0;
}

async function generateAndSetRandomNickname(env: Env, userId: string): Promise<string | null> {
  // Try up to 10 times to find a unique nickname
  for (let i = 0; i < 10; i++) {
    const candidate = generateRandomNickname();
    if (await isNicknameUnique(env, candidate)) {
      // Set the nickname
      await supabaseRequest(env, `/rest/v1/users?id=eq.${encodeURIComponent(userId)}`, {
        method: "PATCH",
        headers: { prefer: "return=minimal" },
        body: { nickname: candidate },
      });
      return candidate;
    }
  }
  
  // Fallback: use UUID-based name
  const fallback = `User${Date.now().toString(36).toUpperCase().slice(-6)}`;
  await supabaseRequest(env, `/rest/v1/users?id=eq.${encodeURIComponent(userId)}`, {
    method: "PATCH",
    headers: { prefer: "return=minimal" },
    body: { nickname: fallback },
  });
  return fallback;
}

// ========== LLM ==========

async function askLLM(env: Env, userMessage: string, context: string): Promise<string> {
  const apiKey = env.OPENAI_API_KEY;
  if (!apiKey) {
    return "LLM not configured. Set OPENAI_API_KEY in environment.";
  }

  const systemPrompt = `You are DOOM CTRL Admin Bot assistant. You help manage users of a mobile app that gamifies screen time.

Available actions you can suggest:
- View stats: /stats
- View user: /user <userId>
- Grant energy: /grant <userId> <amount> [reason]
- Ban user: /ban <userId> <reason>
- Unban user: /unban <userId>

Current database state:
${context}

Respond concisely in the same language as the user. If they ask to do something, provide the exact command.`;

  try {
    const resp = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userMessage },
        ],
        max_tokens: 500,
        temperature: 0.7,
      }),
    });

    const json = (await resp.json()) as any;
    return json.choices?.[0]?.message?.content ?? "No response from LLM";
  } catch (e: any) {
    return `LLM error: ${e.message}`;
  }
}

// ========== UI Components ==========

function mainMenuKeyboard(): InlineKeyboardMarkup {
  return {
    inline_keyboard: [
      [
        { text: "📊 Stats", callback_data: "stats" },
        { text: "👥 Users", callback_data: "users" },
      ],
      [
        { text: "🔍 Find User", callback_data: "find_user" },
        { text: "⚡ Grant Energy", callback_data: "grant_prompt" },
      ],
      [
        { text: "🛡️ Shields", callback_data: "shields" },
        { text: "🔧 Diagnostics", callback_data: "diag" },
      ],
      [{ text: "💬 Ask AI", callback_data: "ask_ai" }],
    ],
  };
}

function userActionsKeyboard(userId: string): InlineKeyboardMarkup {
  return {
    inline_keyboard: [
      [
        { text: "⚡ Grant +1000", callback_data: `grant:${userId}:1000` },
        { text: "⚡ Grant +5000", callback_data: `grant:${userId}:5000` },
      ],
      [
        { text: "🛡️ Shields", callback_data: `shields:${userId}` },
        { text: "📜 History", callback_data: `history:${userId}` },
      ],
      [
        { text: "🎲 Random Name", callback_data: `randname:${userId}` },
      ],
      [
        { text: "🚫 Ban", callback_data: `ban:${userId}` },
        { text: "✅ Unban", callback_data: `unban:${userId}` },
      ],
      [{ text: "« Back", callback_data: "menu" }],
    ],
  };
}

function backKeyboard(): InlineKeyboardMarkup {
  return {
    inline_keyboard: [[{ text: "« Back to Menu", callback_data: "menu" }]],
  };
}

function usersListKeyboard(users: any[]): InlineKeyboardMarkup {
  const buttons: InlineKeyboardButton[][] = users.slice(0, 8).map((u) => [
    {
      text: `${u.nickname ?? u.email?.slice(0, 15) ?? u.id.slice(0, 8)}... | ⚡${u.current_energy_balance ?? 0}`,
      callback_data: `user:${u.id}`,
    },
  ]);
  buttons.push([{ text: "« Back", callback_data: "menu" }]);
  return { inline_keyboard: buttons };
}

// ========== Message Builders ==========

function formatNumber(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return String(n);
}

async function buildStatsMessage(env: Env): Promise<string> {
  const [users, shields, energy] = await Promise.all([
    countTable(env, "users"),
    countTable(env, "shields"),
    sumEnergy(env),
  ]);

  return `<b>📊 DOOM CTRL Stats</b>

👥 <b>Users:</b> ${formatNumber(users)}
🛡️ <b>Shields:</b> ${formatNumber(shields)}
⚡ <b>Energy Granted:</b> ${formatNumber(energy)}

<i>Updated: ${new Date().toLocaleString()}</i>`;
}

async function buildUserMessage(env: Env, userId: string): Promise<string | null> {
  const [u, shields, energy] = await Promise.all([
    getUser(env, userId),
    listUserShields(env, userId),
    sumEnergy(env, userId),
  ]);

  if (!u) return null;

  let msg = `<b>👤 User Profile</b>

<b>ID:</b> <code>${u.id}</code>
<b>Email:</b> ${u.email ?? "—"}
<b>Nickname:</b> ${u.nickname ?? "—"}
<b>Country:</b> ${u.country ?? "—"}
<b>Created:</b> ${new Date(u.created_at).toLocaleDateString()}

<b>⚡ Energy:</b>
• Balance: <b>${formatNumber(u.current_energy_balance ?? 0)}</b>
• Steps today: ${formatNumber(u.current_steps_today ?? 0)}
• Spent lifetime: ${formatNumber(u.energy_spent_lifetime ?? 0)}
• Batteries: ${u.batteries_collected ?? 0}
• Granted: ${formatNumber(energy)}

<b>🛡️ Shields:</b> ${shields.length}`;

  if (shields.length > 0) {
    msg += "\n";
    for (const s of shields.slice(0, 5)) {
      msg += `\n• ${s.bundle_id.split(".").pop()} (${s.mode}, Lv${s.level})`;
    }
    if (shields.length > 5) msg += `\n• ... +${shields.length - 5} more`;
  }

  if (u.is_banned) {
    msg += `\n\n🚫 <b>BANNED:</b> ${u.ban_reason ?? "No reason"}`;
    if (u.ban_until) msg += ` (until ${new Date(u.ban_until).toLocaleDateString()})`;
  }

  return msg;
}

// ========== State for multi-step flows ==========
// Note: In production, use KV or Durable Objects. This is per-request only.
const pendingActions: Map<number, { action: string; data?: any }> = new Map();

// ========== Command Parser ==========

function parseCommand(text: string): { cmd: string; args: string[] } | null {
  const t = text.trim();
  if (!t.startsWith("/")) return null;
  const parts = t.split(/\s+/);
  const cmd = parts[0].split("@")[0].toLowerCase();
  return { cmd, args: parts.slice(1) };
}

// ========== Main Handler ==========

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      if (request.method === "GET") {
        return new Response("DOOM CTRL Admin Bot 🛡️", { status: 200 });
      }
      if (request.method !== "POST") {
        return new Response("method not allowed", { status: 405 });
      }

      const update = (await request.json()) as TelegramUpdate;

      // Handle callback queries (button presses)
      if (update.callback_query) {
        return await handleCallbackQuery(env, update.callback_query);
      }

      const msg = update.message;
      if (!msg?.chat?.id || !msg.text) return new Response("ignored", { status: 200 });

      const adminIds = parseAdminIds(requireEnv(env, "ADMIN_IDS"));
      const fromId = msg.from?.id;
      if (!fromId || !adminIds.has(fromId)) {
        return new Response("forbidden", { status: 200 });
      }

      return await handleMessage(env, msg);
    } catch (e: any) {
      try {
        const update = (await request.clone().json()) as TelegramUpdate;
        const chatId = update.message?.chat?.id ?? update.callback_query?.message?.chat?.id;
        if (chatId) {
          await sendMessage(env, chatId, `❌ Error: ${String(e?.message ?? e)}`, backKeyboard());
        }
      } catch {}
        return new Response("ok", { status: 200 });
      }
  },
};

async function handleMessage(env: Env, msg: TelegramMessage): Promise<Response> {
  const chatId = msg.chat.id;
  const text = msg.text ?? "";
  const parsed = parseCommand(text);

  // Command handling
  if (parsed) {
      const { cmd, args } = parsed;

    if (cmd === "/start" || cmd === "/menu") {
      await sendMessage(
        env,
        chatId,
        `<b>🛡️ DOOM CTRL Admin Panel</b>\n\nWelcome! Choose an action:`,
        mainMenuKeyboard()
      );
        return new Response("ok", { status: 200 });
      }

      if (cmd === "/stats") {
      const statsMsg = await buildStatsMessage(env);
      await sendMessage(env, chatId, statsMsg, backKeyboard());
        return new Response("ok", { status: 200 });
      }

      if (cmd === "/user") {
          const userId = args[0];
          if (!userId) {
        await sendMessage(env, chatId, "Usage: /user <userId>", backKeyboard());
            return new Response("ok", { status: 200 });
          }
      const userMsg = await buildUserMessage(env, userId);
      if (!userMsg) {
        await sendMessage(env, chatId, `User not found: ${userId}`, backKeyboard());
      } else {
        await sendMessage(env, chatId, userMsg, userActionsKeyboard(userId));
        }
        return new Response("ok", { status: 200 });
      }

      if (cmd === "/grant") {
          const userId = args[0];
          const deltaRaw = args[1];
          const reason = args.slice(2).join(" ");
          if (!userId || !deltaRaw) {
        await sendMessage(env, chatId, "Usage: /grant <userId> <delta> [reason]", backKeyboard());
            return new Response("ok", { status: 200 });
          }
          const delta = Number(deltaRaw);
          if (!Number.isFinite(delta) || !Number.isInteger(delta) || delta === 0) {
        await sendMessage(env, chatId, "Delta must be a non-zero integer", backKeyboard());
            return new Response("ok", { status: 200 });
          }
          await grantEnergy(env, userId, delta, reason || undefined);
      await sendMessage(
        env,
        chatId,
        `✅ Granted <b>${formatNumber(delta)}</b> energy to user\n<code>${userId}</code>`,
        backKeyboard()
      );
      return new Response("ok", { status: 200 });
    }

    if (cmd === "/setnick") {
      const userId = args[0];
      const nickname = args.slice(1).join(" ");
      if (!userId || !nickname) {
        await sendMessage(env, chatId, "Usage: /setnick <userId> <nickname>", backKeyboard());
        return new Response("ok", { status: 200 });
      }
      
      // Check uniqueness
      if (!(await isNicknameUnique(env, nickname))) {
        await sendMessage(env, chatId, `❌ Nickname "${nickname}" is already taken`, backKeyboard());
        return new Response("ok", { status: 200 });
      }

      // Set nickname
      await supabaseRequest(env, `/rest/v1/users?id=eq.${encodeURIComponent(userId)}`, {
        method: "PATCH",
        headers: { prefer: "return=minimal" },
        body: { nickname },
      });
      
      await sendMessage(env, chatId, `✅ Nickname set to <b>${nickname}</b>`, backKeyboard());
      return new Response("ok", { status: 200 });
    }

    if (cmd === "/ban") {
          const userId = args[0];
      const reason = args.slice(1).join(" ") || "Admin decision";
      if (!userId) {
        await sendMessage(env, chatId, "Usage: /ban <userId> [reason]", backKeyboard());
            return new Response("ok", { status: 200 });
          }
      await banUser(env, userId, reason);
      await sendMessage(env, chatId, `🚫 User <code>${userId}</code> banned.\nReason: ${reason}`, backKeyboard());
            return new Response("ok", { status: 200 });
          }

    if (cmd === "/unban") {
      const userId = args[0];
      if (!userId) {
        await sendMessage(env, chatId, "Usage: /unban <userId>", backKeyboard());
        return new Response("ok", { status: 200 });
      }
      await unbanUser(env, userId);
      await sendMessage(env, chatId, `✅ User <code>${userId}</code> unbanned.`, backKeyboard());
        return new Response("ok", { status: 200 });
      }

      if (cmd === "/diag") {
          const envOk = {
            TELEGRAM_BOT_TOKEN: Boolean(env.TELEGRAM_BOT_TOKEN),
            SUPABASE_URL: Boolean(env.SUPABASE_URL),
            SUPABASE_SERVICE_ROLE_KEY: Boolean(env.SUPABASE_SERVICE_ROLE_KEY),
        OPENAI_API_KEY: Boolean(env.OPENAI_API_KEY),
            ADMIN_IDS: Boolean(env.ADMIN_IDS),
          };
          const me = await tgCall<any>(env, "getMe", {});
      const [users, shields] = await Promise.all([countTable(env, "users"), countTable(env, "shields")]);

      await sendMessage(
        env,
        chatId,
        `<b>🔧 Diagnostics</b>

<b>Bot:</b> @${me?.username ?? "?"}
<b>Users:</b> ${users}
<b>Shields:</b> ${shields}

<b>Env:</b>
${Object.entries(envOk)
  .map(([k, v]) => `• ${k}: ${v ? "✅" : "❌"}`)
  .join("\n")}`,
        backKeyboard()
      );
      return new Response("ok", { status: 200 });
    }

    if (cmd === "/help") {
          await sendMessage(
            env,
        chatId,
        `<b>📖 Commands</b>

/menu — Main menu
/stats — Global statistics
/user &lt;id&gt; — User profile
/grant &lt;id&gt; &lt;amount&gt; [reason] — Grant energy
/ban &lt;id&gt; [reason] — Ban user
/unban &lt;id&gt; — Unban user
/diag — Diagnostics

Or just type a question in natural language!`,
        mainMenuKeyboard()
      );
      return new Response("ok", { status: 200 });
    }

    // Unknown command
    await sendMessage(env, chatId, `Unknown command: ${cmd}\n\nUse /help for available commands.`, mainMenuKeyboard());
    return new Response("ok", { status: 200 });
  }

  // Natural language - use LLM
  const context = await buildStatsMessage(env);
  const llmResponse = await askLLM(env, text, context);
  await sendMessage(env, chatId, `💬 <b>AI Response:</b>\n\n${llmResponse}`, mainMenuKeyboard());
  return new Response("ok", { status: 200 });
}

async function handleCallbackQuery(env: Env, query: TelegramCallbackQuery): Promise<Response> {
  const chatId = query.message?.chat?.id;
  const messageId = query.message?.message_id;
  const data = query.data ?? "";
  const fromId = query.from?.id;

  if (!chatId || !messageId) {
    await answerCallbackQuery(env, query.id);
    return new Response("ok", { status: 200 });
  }

  const adminIds = parseAdminIds(requireEnv(env, "ADMIN_IDS"));
  if (!fromId || !adminIds.has(fromId)) {
    await answerCallbackQuery(env, query.id, "Access denied");
    return new Response("ok", { status: 200 });
  }

  try {
    // Menu
    if (data === "menu") {
      await editMessage(env, chatId, messageId, `<b>🛡️ DOOM CTRL Admin Panel</b>\n\nChoose an action:`, mainMenuKeyboard());
      await answerCallbackQuery(env, query.id);
      return new Response("ok", { status: 200 });
    }

    // Stats
    if (data === "stats") {
      const statsMsg = await buildStatsMessage(env);
      await editMessage(env, chatId, messageId, statsMsg, backKeyboard());
      await answerCallbackQuery(env, query.id);
      return new Response("ok", { status: 200 });
    }

    // Users list
    if (data === "users") {
      const users = await listUsers(env, 10);
      await editMessage(
        env,
        chatId,
        messageId,
        `<b>👥 Recent Users</b>\n\nSelect a user:`,
        usersListKeyboard(users)
      );
      await answerCallbackQuery(env, query.id);
      return new Response("ok", { status: 200 });
    }

    // User detail
    if (data.startsWith("user:")) {
      const userId = data.split(":")[1];
      const userMsg = await buildUserMessage(env, userId);
      if (!userMsg) {
        await answerCallbackQuery(env, query.id, "User not found");
      } else {
        await editMessage(env, chatId, messageId, userMsg, userActionsKeyboard(userId));
        await answerCallbackQuery(env, query.id);
        }
        return new Response("ok", { status: 200 });
      }

    // Quick grant
    if (data.startsWith("grant:")) {
      const [, userId, amountStr] = data.split(":");
      const amount = Number(amountStr);
      await grantEnergy(env, userId, amount, "Admin quick grant");
      await answerCallbackQuery(env, query.id, `✅ Granted ${formatNumber(amount)} energy`);
      // Refresh user view
      const userMsg = await buildUserMessage(env, userId);
      if (userMsg) {
        await editMessage(env, chatId, messageId, userMsg, userActionsKeyboard(userId));
      }
      return new Response("ok", { status: 200 });
    }

    // Shields for user
    if (data.startsWith("shields:")) {
      const userId = data.split(":")[1];
      const shields = await listUserShields(env, userId);
      let msg = `<b>🛡️ Shields for user</b>\n<code>${userId}</code>\n\n`;
      if (shields.length === 0) {
        msg += "No shields configured.";
      } else {
        for (const s of shields) {
          msg += `• <b>${s.bundle_id}</b>\n  Mode: ${s.mode} | Level: ${s.level}\n`;
        }
      }
      await editMessage(env, chatId, messageId, msg, {
        inline_keyboard: [[{ text: "« Back to User", callback_data: `user:${userId}` }]],
      });
      await answerCallbackQuery(env, query.id);
      return new Response("ok", { status: 200 });
    }

    // Ban
    if (data.startsWith("ban:")) {
      const userId = data.split(":")[1];
      await banUser(env, userId, "Admin decision via bot");
      await answerCallbackQuery(env, query.id, "🚫 User banned");
      const userMsg = await buildUserMessage(env, userId);
      if (userMsg) {
        await editMessage(env, chatId, messageId, userMsg, userActionsKeyboard(userId));
      }
      return new Response("ok", { status: 200 });
    }

    // Unban
    if (data.startsWith("unban:")) {
      const userId = data.split(":")[1];
      await unbanUser(env, userId);
      await answerCallbackQuery(env, query.id, "✅ User unbanned");
      const userMsg = await buildUserMessage(env, userId);
      if (userMsg) {
        await editMessage(env, chatId, messageId, userMsg, userActionsKeyboard(userId));
      }
      return new Response("ok", { status: 200 });
    }

    // Find user prompt
    if (data === "find_user") {
      await editMessage(
        env,
        chatId,
        messageId,
        `<b>🔍 Find User</b>\n\nSend the user ID:\n<code>/user &lt;userId&gt;</code>`,
        backKeyboard()
      );
      await answerCallbackQuery(env, query.id);
      return new Response("ok", { status: 200 });
    }

    // Grant prompt
    if (data === "grant_prompt") {
      await editMessage(
        env,
        chatId,
        messageId,
        `<b>⚡ Grant Energy</b>\n\nSend command:\n<code>/grant &lt;userId&gt; &lt;amount&gt; [reason]</code>\n\nExample:\n<code>/grant abc123 1000 Welcome bonus</code>`,
        backKeyboard()
      );
      await answerCallbackQuery(env, query.id);
      return new Response("ok", { status: 200 });
    }

    // Shields overview
    if (data === "shields") {
      const count = await countTable(env, "shields");
      await editMessage(
        env,
        chatId,
        messageId,
        `<b>🛡️ Shields Overview</b>\n\nTotal shields: <b>${count}</b>\n\nTo view shields for a specific user, use:\n<code>/user &lt;userId&gt;</code>`,
        backKeyboard()
      );
      await answerCallbackQuery(env, query.id);
      return new Response("ok", { status: 200 });
    }

    // Diagnostics
    if (data === "diag") {
      const envOk = {
        TELEGRAM_BOT_TOKEN: Boolean(env.TELEGRAM_BOT_TOKEN),
        SUPABASE_URL: Boolean(env.SUPABASE_URL),
        SUPABASE_SERVICE_ROLE_KEY: Boolean(env.SUPABASE_SERVICE_ROLE_KEY),
        OPENAI_API_KEY: Boolean(env.OPENAI_API_KEY),
      };
      const me = await tgCall<any>(env, "getMe", {});
      const [users, shields] = await Promise.all([countTable(env, "users"), countTable(env, "shields")]);

      await editMessage(
        env,
        chatId,
        messageId,
        `<b>🔧 Diagnostics</b>

<b>Bot:</b> @${me?.username ?? "?"}
<b>Users:</b> ${users}
<b>Shields:</b> ${shields}

<b>Env:</b>
${Object.entries(envOk)
  .map(([k, v]) => `• ${k}: ${v ? "✅" : "❌"}`)
  .join("\n")}`,
        backKeyboard()
      );
      await answerCallbackQuery(env, query.id);
      return new Response("ok", { status: 200 });
    }

    // AI prompt
    if (data === "ask_ai") {
      await editMessage(
        env,
        chatId,
        messageId,
        `<b>💬 Ask AI</b>\n\nJust type your question in natural language!\n\nExamples:\n• "How many users registered today?"\n• "Show me stats"\n• "How to grant energy to a user?"`,
        backKeyboard()
      );
      await answerCallbackQuery(env, query.id);
      return new Response("ok", { status: 200 });
    }

    // Generate random nickname
    if (data.startsWith("randname:")) {
      const userId = data.split(":")[1];
      const nickname = await generateAndSetRandomNickname(env, userId);
      if (nickname) {
        await answerCallbackQuery(env, query.id, `✅ Set: ${nickname}`);
        const userMsg = await buildUserMessage(env, userId);
        if (userMsg) {
          await editMessage(env, chatId, messageId, userMsg, userActionsKeyboard(userId));
        }
      } else {
        await answerCallbackQuery(env, query.id, "❌ Failed to set nickname");
      }
      return new Response("ok", { status: 200 });
    }

    await answerCallbackQuery(env, query.id, "Unknown action");
    return new Response("ok", { status: 200 });
  } catch (e: any) {
    await answerCallbackQuery(env, query.id, `Error: ${e.message}`);
    return new Response("ok", { status: 200 });
  }
}
