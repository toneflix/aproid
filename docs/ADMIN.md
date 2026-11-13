# Admin CLI

`flyylink-admin` manages FlyyLink from your own machine: users, licences, trials, settings and notices. It talks to the website's worker at `/api/admin/run`, so nothing needs the Cloudflare dashboard or `wrangler d1 execute`.

## Install

Needs Node 22 or later.

```sh
cd web/cli
npm install
npm run build
npm link        # puts flyylink-admin on your PATH
```

## Connect

1. Run `flyylink-admin login`. It makes a key for this machine and prints its public key. Add `--url=` to use another site, such as a preview.
2. **First operator:** set the public key as a worker secret and deploy:

   ```sh
   cd web
   npx wrangler secret put ADMIN_BOOTSTRAP_KEY
   ```

   Then make it permanent with `flyylink-admin operators:add <your name> <public key>`. The bootstrap key stops working once an operator exists, so you can delete the secret afterwards.

   **Later operators:** an existing operator runs `flyylink-admin operators:add <name> <their public key>`.

3. Check with `flyylink-admin status` and `flyylink-admin stats`.

The key lives in `~/.config/flyylink-admin/config.json` (mode 600). Set `FLYYLINK_ADMIN_CONFIG` to keep another file, such as one per site.

## Use

```sh
flyylink-admin wizard                          # pick a task from a menu
flyylink-admin commands                        # every command
flyylink-admin users:list --search=gmail       # pick a user, then what to do with them
flyylink-admin licences:grant ada@example.com
flyylink-admin settings:set max_computers 6
flyylink-admin notify:send licensed --channel=both --subject="New in 2.0" --message="Line one\nLine two"
flyylink-admin <command> --help
```

On a terminal, missing input is asked for and listings let you pick a row and an action. Pass `-n` to skip questions, or `--json` for the raw result.

| Area      | Commands                                                                                  |
| --------- | ----------------------------------------------------------------------------------------- |
| Users     | `users:list`, `users:show`, `users:sign-out`, `users:delete`, `computers:remove`          |
| Licences  | `licences:list`, `licences:grant`, `licences:revoke`, `licences:restore`                  |
| Trials    | `trials:extend <machine> <days>`, `trials:reset <machine>`                                |
| Settings  | `settings:list`, `settings:set <key> <value>`, `settings:unset <key>`                     |
| Notices   | `notify:send <to>`, `notify:continue <id>`, `notify:list`                                 |
| Operators | `operators:add`, `operators:list`, `operators:revoke`, `audit:list`, `stats`              |

## Settings

Settings are stored in D1 and override the worker's defaults until unset.

| Key                  | Default                    |
| -------------------- | -------------------------- |
| `trial_days`         | `TRIAL_DAYS`, or 14        |
| `max_computers`      | 5                          |
| `removals_per_month` | 3                          |
| `review_emails`      | `REVIEW_EMAILS`            |

`trial_days` changes the server only. The site's copy still uses the `TRIAL_DAYS` build variable, and the apps show 14 days until they first reach the server.

## Notices

`notify:send <to>` takes `all`, `licensed`, `unlicensed`, or emails separated by commas. `--channel` picks how it goes:

- `email` (default): the designed email template, sent through SendPulse in batches of 20. The CLI keeps going until everyone has it; if it stops, `notify:continue <id>` carries on.
- `app`: a notification in the Mac and Windows apps, shown when each computer next checks its licence (every few hours). Licensed computers count as `licensed`; computers on a trial count as `unlicensed`. Notices older than 30 days, or sent before the app was installed, aren't shown. Phones never get them.
- `both`: each of the above.

`--link` adds a button. `--dry-run` counts recipients without sending.

## Security

Each request is signed with the machine's Ed25519 key over the method, path, time, a single-use nonce and the body. The worker refuses requests more than 5 minutes off its clock, reused nonces, revoked keys and unknown commands. Every command is recorded under the operator's name (`audit:list`).
