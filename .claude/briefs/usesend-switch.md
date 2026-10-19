# Brief: switch outgoing email to useSend (free plan), keep Resend as fallback

Yahia (2026-10-14): "setup usesend as well for our sending emails system" — scope he picked: the clipping-site contact form AND Prism emails. Constraint: "I don't want to pay for anything" -> useSend Cloud FREE plan only (3,000/month, 100/day, 1 domain, 1 contact book). No self-hosting (SES + server cost money).
useSend: github usesend/useSend (API docs docs.usesend.com; official JS SDK `usesend-js` if it exists at a version >= 2 weeks old, else plain fetch to its REST API). Inbound email is NOT supported by useSend -> never touch inbound/webhook-receive paths that rely on Resend.

## Do (in THIS repo's worktree)
1. Find every outgoing send (Resend SDK/API calls). Add ONE mail adapter module: `sendEmail({from,to,subject,html,text,replyTo,...})` with provider chosen by env `EMAIL_PROVIDER` = `usesend` | `resend` (default `resend` so nothing changes until Yahia sets keys). useSend key env `USESEND_API_KEY` (+ `USESEND_BASE_URL` default https://app.usesend.com). If useSend fails with a 5xx/network error or daily-limit error, fall back to Resend when RESEND_API_KEY is set, and log which provider sent.
2. Route all existing sends through the adapter. Keep reply_to = visitor on contact forms, honeypot/validation unchanged (site rule: server-side send, never mailto).
3. Tests with a mocked fetch: provider switch, fallback, limit error, payload mapping. Run the repo's full test/lint/typecheck gate (Prism: zero-warnings CI gate, follow .omc/skills project rules).
4. docs/email-usesend.md: what Yahia must do (sign up free at usesend.com, add + verify the sending domain's DNS records (show which records, note SPF must include both providers while Resend stays as fallback), create an API key, set env vars in Vercel for production + preview), and how to flip EMAIL_PROVIDER.
- Never put a real key anywhere; never send a real email; never change DNS or Vercel env. Commit on your branch only; no merge/push.
Done = adapter + tests green + doc.
