// Lemon's licence key server for Razorpay (India) purchases.
//
// - POST /razorpay/webhook       Razorpay tells us about payments and refunds. Each paid Lemon
//                                purchase gets exactly one key; a refund turns its key off.
// - GET/POST /key                "Find my key": payment ID + email shows the key.
// - POST /v1/licenses/activate   The same requests and replies as Lemon Squeezy's licence API,
//   POST /v1/licenses/validate   so the Lemon app talks to both the same way.
//   POST /v1/licenses/deactivate
// - GET/POST /admin/keys         Your own tools (needs ADMIN_TOKEN): list, create by hand, disable.

const KEY_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // 32 letters: no 0/O or 1/I to mix up

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    try {
      if (url.pathname === "/razorpay/webhook" && request.method === "POST") return await razorpayWebhook(request, env, ctx);
      if (url.pathname === "/key") return await findMyKey(request, env);
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
  let message = "";
  let found = null;
  if (request.method === "POST") {
    const form = await request.formData();
    const paymentID = String(form.get("payment_id") ?? "").trim();
    const email = String(form.get("email") ?? "").trim().toLowerCase();
    const row = paymentID && email
      ? await env.DB.prepare("SELECT key, status FROM licences WHERE payment_id = ? AND email = ?").bind(paymentID, email).first()
      : null;
    if (row) found = row;
    else message = "No key matches that payment ID and email. Check both and try again, or contact support.";
  }
  const page = `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Find your Lemon key</title>
<style>
  :root { color-scheme: light dark; --accent: #f9b30d; }
  body { font: 16px/1.5 -apple-system, system-ui, sans-serif; max-width: 460px; margin: 48px auto; padding: 0 16px; }
  h1 { font-size: 26px; margin-bottom: 4px; } p.sub { color: GrayText; margin-top: 0; }
  label { display: block; font-weight: 600; margin-top: 16px; }
  input { width: 100%; box-sizing: border-box; font: inherit; padding: 10px 12px; border-radius: 10px; border: 1px solid #8886; }
  button { margin-top: 20px; width: 100%; font: inherit; font-weight: 600; padding: 12px; border: 0; border-radius: 999px; background: var(--accent); color: #000; cursor: pointer; }
  .key { font: 600 20px ui-monospace, monospace; padding: 16px; border-radius: 12px; background: #f9b30d22; text-align: center; user-select: all; word-break: break-all; }
  .note { color: GrayText; font-size: 14px; } .error { color: #d33; }
</style>
<h1>Find your Lemon key</h1>
<p class="sub">Paid with Razorpay? Enter the payment ID from your Razorpay receipt (it starts with <b>pay_</b>) and the email you paid with.</p>
${found ? `<p class="key">${escapeHTML(found.key)}</p>
<p class="note">${found.status === "active"
      ? "Open Lemon → Settings → Licence, paste this key and click Activate."
      : "This key has been turned off (for example after a refund)."}</p>` : ""}
${message ? `<p class="error">${escapeHTML(message)}</p>` : ""}
<form method="post">
  <label for="p">Payment ID</label><input id="p" name="payment_id" placeholder="pay_…" required autocomplete="off">
  <label for="e">Email</label><input id="e" name="email" type="email" placeholder="you@example.com" required>
  <button>Show My Key</button>
</form>
<p class="note">Need help? <a href="mailto:${escapeHTML(env.SUPPORT_EMAIL ?? "")}">${escapeHTML(env.SUPPORT_EMAIL ?? "")}</a></p>`;
  return new Response(page, { headers: { "Content-Type": "text/html; charset=utf-8" } });
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
