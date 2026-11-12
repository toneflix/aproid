CREATE TABLE accounts (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL
);

CREATE TABLE licences (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id),
  provider TEXT NOT NULL,
  order_id TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  UNIQUE (provider, order_id)
);

CREATE INDEX licences_account ON licences(account_id);

CREATE TABLE computers (
  account_id TEXT NOT NULL REFERENCES accounts(id),
  machine TEXT NOT NULL,
  name TEXT NOT NULL,
  platform TEXT NOT NULL,
  secret_hash TEXT NOT NULL,
  activated_at INTEGER NOT NULL,
  seen_at INTEGER NOT NULL,
  removed_at INTEGER,
  PRIMARY KEY (account_id, machine)
);

CREATE TABLE trials (
  machine TEXT PRIMARY KEY,
  started_at INTEGER NOT NULL
);

CREATE TABLE codes (
  email TEXT PRIMARY KEY,
  code_hash TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  window_start INTEGER NOT NULL,
  sends INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE sessions (
  token_hash TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id),
  expires_at INTEGER NOT NULL
);
