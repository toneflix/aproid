# flyylink-cli

The admin CLI for the FlyyLink server: `npm install -g @toneflix/flyylink-cli`. Setup, commands and publishing are in [docs/ADMIN.md](../../docs/ADMIN.md).

```sh
npm install
npm run build      # dist/index.js
npm link           # this checkout as flyylink-cli, for trying changes
npm test           # builds, then runs it against the worker with an in-memory database
```

Command definitions are shared with the worker, in `web/worker/admin/protocol`.
