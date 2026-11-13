# flyylink-admin

The admin CLI for the FlyyLink server. Setup and commands are in [docs/ADMIN.md](../../docs/ADMIN.md).

```sh
npm install
npm run build      # dist/index.js
npm link           # flyylink-admin on your PATH
npm test           # builds, then runs it against the worker with an in-memory database
```

Command definitions are shared with the worker, in `web/worker/admin/protocol`.
