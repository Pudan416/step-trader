# Nowhere Telegram Admin Bot

Cloudflare Worker-based Telegram bot for managing Nowhere users.

## Features

### 🎛️ Interactive UI
- **Inline keyboard buttons** for quick navigation
- **User list** with one-tap access to profiles
- **Quick actions** (ban/unban, assign random nickname) via buttons

### 💬 Natural Language (LLM)
- Ask questions in plain English/Russian
- AI suggests commands based on your query
- Powered by GPT-4o-mini

### 📊 Admin Commands

| Command | Description |
|---------|-------------|
| `/menu` | Main menu with buttons |
| `/stats` | Global statistics |
| `/user <id>` | User profile + shields |
| `/setnick <id> <nickname>` | Set a user's nickname |
| `/ban <id> [reason]` | Ban user |
| `/unban <id>` | Unban user |
| `/diag` | Diagnostics |
| `/help` | Command list |

### 🖱️ Button Actions
- **📊 Stats** — Global statistics
- **👥 Users** — Recent users list
- **🔍 Find User** — Search by ID
- **🛡️ Shields** — Shields overview
- **🔧 Diagnostics** — System status
- **💬 Ask AI** — Natural language help
- **🎲 Random Name** — Assign a random nickname (per-user)

## Setup

### 1. Create Telegram Bot
```bash
# Talk to @BotFather on Telegram
# Create new bot and get token
```

### 2. Set Secrets
```bash
cd tg-admin

# Required
wrangler secret put TELEGRAM_BOT_TOKEN
wrangler secret put SUPABASE_URL
wrangler secret put SUPABASE_SERVICE_ROLE_KEY

# Optional (for AI features)
wrangler secret put OPENAI_API_KEY
```

### 3. Configure Admin IDs
Edit `wrangler.jsonc`:
```json
"vars": {
    "ADMIN_IDS": "YOUR_TELEGRAM_USER_ID"
}
```

Get your ID: message [@userinfobot](https://t.me/userinfobot)

### 4. Deploy
```bash
npm run deploy
```

### 5. Set Webhook
```bash
curl -X POST "https://api.telegram.org/bot<TOKEN>/setWebhook" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://doomctrl-tg-admin.<YOUR_SUBDOMAIN>.workers.dev"}'
```

## Development

```bash
npm install
npm run dev      # Local development
npm run deploy   # Deploy to Cloudflare
```

## Database Tables

The bot reads/writes these Supabase tables:
- `users` — User profiles
- `shields` — Shield configurations

## Security

- Only users in `ADMIN_IDS` can use commands
- Service role key has full DB access
- Webhook only accepts POST from Telegram
