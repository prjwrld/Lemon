// Lemon's licence key server for Razorpay (India) purchases.
//
// - POST /razorpay/webhook       Razorpay tells us about payments and refunds. Each paid Lemon
//                                purchase gets exactly one key; a refund turns its key off.
// - GET/POST /key                "Find my key": payment ID + email shows the key (/logo.png is its icon).
// - POST /v1/licenses/activate   The same requests and replies as Lemon Squeezy's licence API,
//   POST /v1/licenses/validate   so the Lemon app talks to both the same way.
//   POST /v1/licenses/deactivate
// - GET/POST /admin/keys         Your own tools (needs ADMIN_TOKEN): list, create by hand, disable.

import { LOGO_PNG_BASE64 } from "./logo.js";

const KEY_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // 32 letters: no 0/O or 1/I to mix up

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    try {
      if (url.pathname === "/razorpay/webhook" && request.method === "POST") return await razorpayWebhook(request, env, ctx);
      if (url.pathname === "/key") return await findMyKey(request, env);
      if (url.pathname === "/logo.png" || url.pathname === "/favicon.ico") return logo();
      if (url.pathname.startsWith("/v1/licenses/") && request.method === "POST") {
        return await licenceAPI(url.pathname.slice("/v1/licenses/".length), request, env);
      }
      if (url.pathname === "/admin/keys") return await admin(request, env);
      return json({ error: "Not found." }, 404);
    } catch (error) {
      console.error(error);
      return json({ error: "Something went wrong on the licence server. Please try again." }, 500);
    }
  },
};

// MARK: Razorpay

async function razorpayWebhook(request, env, ctx) {
  // Razorpay signs the raw body with the webhook secret (HMAC-SHA256, hex).
  const body = await request.text();
  const expected = await hmacHex(env.RAZORPAY_WEBHOOK_SECRET ?? "", body);
  if (!env.RAZORPAY_WEBHOOK_SECRET || !timingSafeEqual(expected, request.headers.get("X-Razorpay-Signature") ?? "")) {
    return json({ error: "Bad signature." }, 401);
  }
  let event;
  try { event = JSON.parse(body); } catch { return json({ error: "Bad JSON." }, 400); }

  if (event.event === "payment.captured") {
    const payment = event.payload?.payment?.entity ?? {};
    // Only Lemon's price in rupees makes a key, so other sales on the same Razorpay account don't.
    if (payment.currency !== "INR" || payment.amount !== Number(env.PRICE_PAISE) || !payment.id) {
      return json({ ok: true, ignored: "Not a Lemon purchase (amount or currency differ)." });
    }
    const { key, created } = await createLicence(env, payment.id, payment.email ?? "", payment.amount);
    if (created && payment.email && env.RESEND_API_KEY) ctx.waitUntil(emailKey(env, payment.email, key, payment.id));
    return json({ ok: true, created });
  }

  if (event.event?.startsWith("refund.")) {
    const paymentID = event.payload?.refund?.entity?.payment_id;
    if (paymentID) await env.DB.prepare("UPDATE licences SET status = 'disabled' WHERE payment_id = ?").bind(paymentID).run();
    return json({ ok: true });
  }

  return json({ ok: true, ignored: event.event });
}

/// Makes the key for a payment, or returns the one it already has. Never makes two.
async function createLicence(env, paymentID, email, amount) {
  for (let attempt = 0; attempt < 5; attempt++) {
    const key = newKey();
    try {
      const result = await env.DB.prepare(
        `INSERT INTO licences (key, payment_id, email, amount, activation_limit) VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(payment_id) DO NOTHING`)
        .bind(key, paymentID, email.trim().toLowerCase(), amount, Number(env.ACTIVATION_LIMIT ?? 2)).run();
      if (result.meta.changes === 1) return { key, created: true };
      // This payment already has a key (Razorpay sent the same notice again).
      const existing = await env.DB.prepare("SELECT key FROM licences WHERE payment_id = ?").bind(paymentID).first();
      return { key: existing.key, created: false };
    } catch (error) {
      // The same key already exists (practically impossible with 100 random bits): try another.
      if (!String(error).includes("licences.key")) throw error;
    }
  }
  throw new Error("Couldn't make a unique key.");
}

function newKey() {
  const bytes = crypto.getRandomValues(new Uint8Array(20));
  const letters = Array.from(bytes, (b) => KEY_ALPHABET[b & 31]).join(""); // 256 is a multiple of 32: no bias
  return "LEMON-" + letters.match(/.{5}/g).join("-");
}

async function emailKey(env, to, key, paymentID) {
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from: env.EMAIL_FROM,
      to,
      subject: "Your Lemon licence key",
      text: `Thank you for buying Lemon!\n\nYour licence key:\n\n    ${key}\n\n` +
        `Open Lemon → Settings → Licence, paste the key and click Activate. It works on up to ` +
        `${env.ACTIVATION_LIMIT ?? 2} Macs at once.\n\nPayment ID: ${paymentID}\n` +
        `Questions? Write to ${env.SUPPORT_EMAIL}.\n`,
    }),
  });
  if (!response.ok) console.error("Key email failed", response.status, await response.text());
}

// MARK: Find my key

async function findMyKey(request, env) {
  const url = new URL(request.url);
  let paymentID = (url.searchParams.get("payment_id") ?? url.searchParams.get("razorpay_payment_id") ?? "").trim();
  let email = "";
  let found = null;
  let message = "";
  if (request.method === "POST") {
    const form = await request.formData();
    paymentID = String(form.get("payment_id") ?? "").trim();
    email = String(form.get("email") ?? "").trim().toLowerCase();
    found = paymentID && email
      ? await env.DB.prepare("SELECT key, status FROM licences WHERE payment_id = ? AND email = ?").bind(paymentID, email).first()
      : null;
    if (!found) message = "We couldn't find a key for that payment ID and email. Check both, or contact support.";
  }
  const support = escapeHTML(env.SUPPORT_EMAIL ?? "");
  const result = found ? (found.status === "active" ? `
    <section class="result" aria-live="polite">
      <div class="result-head"><span class="badge ok">✓ Paid</span><span class="muted">Your licence key</span></div>
      <div class="key-row">
        <code id="key">${escapeHTML(found.key)}</code>
        <button type="button" class="copy" id="copy">Copy Key</button>
      </div>
      <ol class="steps">
        <li>Open <b>Lemon</b> from the menu bar</li>
        <li>Go to <b>Settings → Licence</b></li>
        <li>Paste the key and click <b>Activate</b></li>
      </ol>
      <p class="muted small">Works on up to ${Number(env.ACTIVATION_LIMIT ?? 2)} Macs at once. Keep this key somewhere safe.</p>
    </section>` : `
    <section class="result" aria-live="polite">
      <div class="result-head"><span class="badge off">Turned off</span><span class="muted">${escapeHTML(found.key)}</span></div>
      <p class="small">This key no longer works, for example after a refund. Questions? <a href="mailto:${support}">${support}</a></p>
    </section>`) : "";

  const page = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Find your Lemon key</title>
<link rel="icon" href="/logo.png">
<style>
  :root {
    --bg: #faf8f2; --card: #ffffff; --text: #1d1d1f; --muted: #6e6e73; --line: #e7e3d8;
    --field: #f5f3ed; --accent: #ffd60a; --accent-deep: #f5b700; --ok: #1f9d55; --off: #c0392b;
    --shadow: 0 1px 2px rgb(0 0 0 / 0.04), 0 12px 40px rgb(120 90 0 / 0.10);
    color-scheme: light dark;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #0f0f10; --card: #1c1c1e; --text: #f5f5f7; --muted: #98989d; --line: #2c2c2e;
      --field: #2a2a2d; --shadow: 0 1px 2px rgb(0 0 0 / 0.3), 0 20px 60px rgb(0 0 0 / 0.45);
    }
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 32px 16px;
    font: 16px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Inter", system-ui, sans-serif;
    color: var(--text); background: var(--bg);
    background-image: radial-gradient(60rem 30rem at 50% -10%, rgb(255 214 10 / 0.22), transparent 70%);
    -webkit-font-smoothing: antialiased;
  }
  main { width: 100%; max-width: 440px; }
  .brand { display: flex; flex-direction: column; align-items: center; text-align: center; margin-bottom: 24px; }
  .brand img { width: 104px; height: 104px; filter: drop-shadow(0 10px 24px rgb(245 183 0 / 0.28)); } /* the icon has its own shape */
  .brand .name { margin-top: 12px; font-size: 13px; font-weight: 600; letter-spacing: 0.08em; text-transform: uppercase; color: var(--muted); }
  h1 { margin: 4px 0 6px; font-size: 28px; line-height: 1.2; letter-spacing: -0.02em; }
  .lead { margin: 0; color: var(--muted); }
  .card { background: var(--card); border: 1px solid var(--line); border-radius: 20px; padding: 24px; box-shadow: var(--shadow); }
  label { display: block; font-size: 14px; font-weight: 600; margin: 0 0 6px; }
  .hint { font-weight: 400; color: var(--muted); }
  input {
    width: 100%; font: inherit; color: var(--text); background: var(--field);
    border: 1px solid transparent; border-radius: 12px; padding: 12px 14px; margin-bottom: 16px;
    transition: border-color .15s, box-shadow .15s, background .15s;
  }
  input::placeholder { color: var(--muted); opacity: .8; }
  input:focus { outline: none; background: var(--card); border-color: var(--accent-deep); box-shadow: 0 0 0 4px rgb(255 214 10 / 0.25); }
  .primary {
    width: 100%; font: inherit; font-weight: 650; color: #1d1d1f; cursor: pointer;
    background: linear-gradient(180deg, var(--accent), var(--accent-deep)); border: 0; border-radius: 999px; padding: 13px;
    box-shadow: 0 6px 18px rgb(245 183 0 / 0.35); transition: transform .1s, filter .15s;
  }
  .primary:hover { filter: brightness(1.04); } .primary:active { transform: scale(0.99); }
  .error { display: flex; gap: 10px; align-items: flex-start; margin: 0 0 16px; padding: 12px 14px; border-radius: 12px;
    background: rgb(192 57 43 / 0.10); color: var(--off); font-size: 14px; }
  .result { margin-bottom: 20px; padding: 18px; border-radius: 16px; background: rgb(255 214 10 / 0.12); border: 1px solid rgb(245 183 0 / 0.35); }
  .result-head { display: flex; align-items: center; gap: 10px; margin-bottom: 12px; font-size: 14px; }
  .badge { font-size: 12px; font-weight: 700; padding: 3px 10px; border-radius: 999px; }
  .badge.ok { background: rgb(31 157 85 / 0.14); color: var(--ok); } .badge.off { background: rgb(192 57 43 / 0.14); color: var(--off); }
  .key-row { display: flex; flex-direction: column; gap: 8px; }
  code { font: 600 clamp(13px, 3.6vw, 16px)/1.4 ui-monospace, "SF Mono", Menlo, monospace; padding: 14px 10px; border-radius: 12px;
    background: var(--card); border: 1px solid var(--line); text-align: center; white-space: nowrap; overflow-x: auto; user-select: all; }
  .copy { font: inherit; font-size: 14px; font-weight: 600; cursor: pointer; padding: 10px 16px; border-radius: 12px; border: 1px solid var(--line);
    background: var(--card); color: var(--text); }
  .copy:hover { border-color: var(--accent-deep); }
  .copy.done { color: var(--ok); border-color: var(--ok); }
  .steps { margin: 16px 0 8px; padding-left: 22px; font-size: 14px; } .steps li { margin: 4px 0; }
  .muted { color: var(--muted); } .small { font-size: 13px; margin: 0; }
  details summary { cursor: pointer; font-size: 14px; color: var(--muted); list-style: none; text-align: center; }
  details summary::-webkit-details-marker { display: none; }
  details[open] summary { margin-bottom: 16px; }
  footer { margin-top: 20px; text-align: center; font-size: 13px; color: var(--muted); }
  a { color: inherit; text-decoration-color: var(--accent-deep); text-underline-offset: 3px; }
  a:hover { color: var(--accent-deep); }
</style>
</head>
<body>
<main>
  <header class="brand">
    <img src="/logo.png" alt="Lemon" width="104" height="104">
    <div class="name">Lemon for Mac</div>
    <h1>${found ? "Here's your key" : "Find your licence key"}</h1>
    <p class="lead">${found ? "Thanks for buying Lemon." : "Paid with UPI or Razorpay? Enter your payment details to get your key."}</p>
  </header>

  <div class="card">
    ${result}
    ${message ? `<p class="error" role="alert"><span aria-hidden="true">⚠︎</span><span>${escapeHTML(message)}</span></p>` : ""}
    ${found ? `<details><summary>Look up another purchase</summary>` : ""}
    <form method="post">
      <label for="p">Payment ID <span class="hint">· on your Razorpay receipt, starts with pay_</span></label>
      <input id="p" name="payment_id" placeholder="pay_XXXXXXXXXXXXXX" value="${escapeHTML(paymentID)}" required autocomplete="off" spellcheck="false">
      <label for="e">Email <span class="hint">· the one you paid with</span></label>
      <input id="e" name="email" type="email" placeholder="you@example.com" value="${escapeHTML(email)}" required autocomplete="email">
      <button class="primary">Show My Key</button>
    </form>
    ${found ? `</details>` : ""}
  </div>

  <footer>Need help? <a href="mailto:${support}">${support}</a></footer>
</main>
<script>
  const copy = document.getElementById("copy");
  if (copy) copy.addEventListener("click", async () => {
    try { await navigator.clipboard.writeText(document.getElementById("key").textContent); copy.textContent = "Copied ✓"; copy.classList.add("done"); }
    catch { getSelection().selectAllChildren(document.getElementById("key")); }
  });
</script>
</body>
</html>`;
  return new Response(page, { headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" } });
}

// MARK: Licence API (same shape as https://docs.lemonsqueezy.com/api/license-api)

async function licenceAPI(action, request, env) {
  const form = new URLSearchParams(await request.text());
  const key = (form.get("license_key") ?? "").trim().toUpperCase();
  const licence = key ? await env.DB.prepare("SELECT * FROM licences WHERE key = ?").bind(key).first() : null;
  const keyInfo = licence && { key: licence.key, status: licence.status === "active" ? "active" : "disabled", activation_limit: licence.activation_limit };

  if (action === "activate") {
    if (!licence) return json({ activated: false, error: "license_key not found." }, 404);
    if (licence.status !== "active") return json({ activated: false, error: "This licence key has been turned off.", license_key: keyInfo }, 400);
    const { count } = await env.DB.prepare("SELECT COUNT(*) AS count FROM activations WHERE key = ?").bind(key).first();
    if (count >= licence.activation_limit) {
      return json({ activated: false, error: `This licence key is already active on ${licence.activation_limit} Macs. Deactivate one first.`, license_key: keyInfo }, 400);
    }
    const instance = { id: crypto.randomUUID(), name: (form.get("instance_name") ?? "").slice(0, 200) };
    await env.DB.prepare("INSERT INTO activations (id, key, instance_name) VALUES (?, ?, ?)").bind(instance.id, key, instance.name).run();
    return json({ activated: true, error: null, license_key: keyInfo, instance, meta: { product_name: "Lemon" } });
  }

  if (action === "validate") {
    if (!licence) return json({ valid: false, error: "license_key not found." }, 404);
    const instanceID = form.get("instance_id");
    if (instanceID) {
      const activation = await env.DB.prepare("SELECT id FROM activations WHERE id = ? AND key = ?").bind(instanceID, key).first();
      if (!activation) return json({ valid: false, error: "license_key instance not found.", license_key: keyInfo }, 404);
    }
    const valid = licence.status === "active";
    return json({ valid, error: valid ? null : "This licence key has been turned off.", license_key: keyInfo, meta: { product_name: "Lemon" } });
  }

  if (action === "deactivate") {
    if (!licence) return json({ deactivated: false, error: "license_key not found." }, 404);
    const result = await env.DB.prepare("DELETE FROM activations WHERE id = ? AND key = ?").bind(form.get("instance_id") ?? "", key).run();
    return json({ deactivated: result.meta.changes === 1, error: result.meta.changes === 1 ? null : "license_key instance not found.", license_key: keyInfo });
  }

  return json({ error: "Not found." }, 404);
}

// MARK: Admin

async function admin(request, env) {
  const token = (request.headers.get("Authorization") ?? "").replace(/^Bearer /, "");
  if (!env.ADMIN_TOKEN || !timingSafeEqual(token, env.ADMIN_TOKEN)) return json({ error: "Not allowed." }, 401);

  if (request.method === "GET") {
    const { results } = await env.DB.prepare(
      `SELECT l.key, l.payment_id, l.email, l.amount, l.status, l.activation_limit, l.created_at,
              (SELECT COUNT(*) FROM activations a WHERE a.key = l.key) AS active_macs
       FROM licences l ORDER BY l.created_at DESC LIMIT 200`).all();
    return json({ licences: results });
  }
  if (request.method === "POST") {
    const input = await request.json();
    if (input.action === "disable" || input.action === "enable") {
      const result = await env.DB.prepare("UPDATE licences SET status = ? WHERE key = ?")
        .bind(input.action === "disable" ? "disabled" : "active", String(input.key ?? "").toUpperCase()).run();
      return json({ ok: result.meta.changes === 1 });
    }
    // Make a key by hand (e.g. a support case or a giveaway).
    const { key } = await createLicence(env, "manual_" + crypto.randomUUID(), String(input.email ?? ""), 0);
    return json({ key });
  }
  return json({ error: "Not found." }, 404);
}

// MARK: Helpers

function logo() {
  const bytes = Uint8Array.from(atob(LOGO_PNG_BASE64), (c) => c.charCodeAt(0));
  return new Response(bytes, { headers: { "Content-Type": "image/png", "Cache-Control": "public, max-age=86400" } });
}

function json(value, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: { "Content-Type": "application/json" } });
}

async function hmacHex(secret, message) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return Array.from(new Uint8Array(signature), (b) => b.toString(16).padStart(2, "0")).join("");
}

/// Compares two strings in the same time whatever they contain, so timing can't leak secrets.
function timingSafeEqual(a, b) {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  let difference = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) difference |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return difference === 0;
}

function escapeHTML(text) {
  return String(text).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}
