-- Lemon's licence keys for Razorpay purchases.
-- UNIQUE constraints make the database itself refuse a duplicate key or a second key for one payment.

CREATE TABLE IF NOT EXISTS licences (
  key              TEXT PRIMARY KEY,                -- LEMON-XXXXX-XXXXX-XXXXX-XXXXX
  payment_id       TEXT NOT NULL UNIQUE,            -- Razorpay pay_… (or manual_… for keys made by hand)
  email            TEXT NOT NULL DEFAULT '',
  amount           INTEGER NOT NULL DEFAULT 0,      -- in paise
  status           TEXT NOT NULL DEFAULT 'active',  -- 'active' or 'disabled' (refunded or turned off)
  activation_limit INTEGER NOT NULL DEFAULT 2,      -- how many Macs at once
  created_at       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS activations (
  id            TEXT PRIMARY KEY,                   -- random UUID, given to the Mac as its instance ID
  key           TEXT NOT NULL REFERENCES licences(key),
  instance_name TEXT NOT NULL DEFAULT '',           -- the Mac's name, e.g. "Prajwal's MacBook Air"
  created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS activations_by_key ON activations(key);
