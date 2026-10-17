# Lemon key server (Razorpay, India)

Lemon Squeezy makes and checks the licence keys of people who buy there. Razorpay only takes
payments, so this small server does the same job for people in India who pay with UPI or an
Indian card through Razorpay. It runs free on Cloudflare (Workers + D1).

## What it does

1. **A payment comes in.** Razorpay sends `payment.captured` to `/razorpay/webhook`. The server
   checks Razorpay's signature (so nobody can fake a payment), checks it's Lemon's price in INR,
   and creates **one** key for that payment: `LEMON-XXXXX-XXXXX-XXXXX-XXXXX` (100 random bits).
   If Razorpay sends the same notice again, no second key is made: the database refuses a
   second key for the same payment ID, and refuses any key that already exists.
2. **The buyer gets the key** by email (if Resend is set up) and on the **Find your key** page
   (`/key`): payment ID from the Razorpay receipt + email → the key. Lemon links to this page.
3. **Lemon checks the key** at `/v1/licenses/activate`, `/validate` and `/deactivate`, which work
   exactly like Lemon Squeezy's. Each key works on 2 Macs at once (`ACTIVATION_LIMIT`).
4. **A refund** (`refund.processed`) turns the key off; Lemon removes it at its next check.

Your records are in the D1 database: Cloudflare dashboard → Storage & Databases → D1 →
lemon-licences → Console, e.g. `SELECT * FROM licences ORDER BY created_at DESC;`

## Going live (one time, about 20 minutes)

1. Make a free Cloudflare account, then in this folder: `npm install` and `npx wrangler login`.
2. `npx wrangler d1 create lemon-licences`, paste the `database_id` it prints into `wrangler.toml`,
   then `npx wrangler d1 execute lemon-licences --remote --file schema.sql`.
3. In `wrangler.toml`, set `PRICE_PAISE` (₹499 → `49900`), `SUPPORT_EMAIL` and `EMAIL_FROM`.
4. Secrets (each asks you to type the value):
   - `npx wrangler secret put RAZORPAY_WEBHOOK_SECRET`: make up a long random string; you'll
     type the same one in Razorpay in step 6.
   - `npx wrangler secret put ADMIN_TOKEN`: another long random string, for `/admin/keys`.
   - Optional, to email keys: make a free [Resend](https://resend.com) account, verify your domain,
     then `npx wrangler secret put RESEND_API_KEY`.
5. `npx wrangler deploy`. It prints your address, e.g. `https://lemon-licences.yourname.workers.dev`.
6. In the Razorpay dashboard:
   - **Payment Pages → Create** a page for Lemon at exactly your price (a Payment *Page* can be paid
     by many people; a single Payment *Link* is for one payment). Make email a required field.
   - **Settings → Webhooks → Add**: URL `https://…workers.dev/razorpay/webhook`, the secret from
     step 4, events **payment.captured** and **refund.processed**.
7. In `Lemon/Core/License.swift` → `StoreConfig`: `razorpayPageURL` (your Payment Page),
   `razorpayPriceText` (e.g. "₹499") and `keyServerURL` (the address from step 5).
8. Test with Razorpay's **Test Mode** (test keys and test UPI/cards) before going live: pay, find
   the key on `/key`, activate it in Lemon, refund it, and check Lemon removes it.

## Your admin tools

```sh
# List the latest 200 keys
curl https://…workers.dev/admin/keys -H "Authorization: Bearer $ADMIN_TOKEN"
# Make a key by hand (support case, giveaway)
curl -X POST https://…workers.dev/admin/keys -H "Authorization: Bearer $ADMIN_TOKEN" -d '{"email":"someone@example.com"}'
# Turn a key off or back on
curl -X POST https://…workers.dev/admin/keys -H "Authorization: Bearer $ADMIN_TOKEN" -d '{"action":"disable","key":"LEMON-…"}'
```

## Testing locally

`./test.sh` runs the server on your Mac with a throwaway database and checks every rule (signatures,
no duplicate keys, price check, the 2-Mac limit, refunds, Find your key, admin). `KEEP=1 ./test.sh`
leaves it running so you can test the app against it:
`Lemon.app/Contents/MacOS/Lemon -LemonTestKeyServer http://localhost:8787 -LemonTestActivate LEMON-…`
