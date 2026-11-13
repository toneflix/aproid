CREATE TABLE operators (
  name TEXT PRIMARY KEY,
  public_key TEXT NOT NULL UNIQUE,
  created_by TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  last_used_at INTEGER,
  revoked_at INTEGER
);

CREATE TABLE admin_nonces (
  nonce TEXT PRIMARY KEY,
  expires_at INTEGER NOT NULL
);

CREATE TABLE admin_audit (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  actor TEXT NOT NULL,
  command TEXT NOT NULL,
  input TEXT NOT NULL,
  exit INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE INDEX admin_audit_actor ON admin_audit(actor);

CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE notifications (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  channel TEXT NOT NULL,
  audience TEXT NOT NULL,
  emails TEXT,
  subject TEXT NOT NULL,
  message TEXT NOT NULL,
  link TEXT,
  link_text TEXT,
  status TEXT NOT NULL,
  cursor TEXT NOT NULL DEFAULT '',
  sent INTEGER NOT NULL DEFAULT 0,
  failed INTEGER NOT NULL DEFAULT 0,
  total INTEGER NOT NULL,
  created_by TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  finished_at INTEGER
);
