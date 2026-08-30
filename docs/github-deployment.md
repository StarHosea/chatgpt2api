# GitHub Actions production deployment

Pushing to `main` deploys the current commit to `140.238.56.209` as `muhaoxing`.
The application is exposed only on `127.0.0.1:3010`; OpenResty publishes it at
`https://image-d.shuangdeng.space` with a Let's Encrypt certificate. The
server's existing `certbot.timer` renews that certificate automatically.

Before the first push, add these repository secrets in GitHub under
`Settings -> Secrets and variables -> Actions`:

| Secret | Value |
| --- | --- |
| `DEPLOY_SSH_KEY` | The complete private key from `~/.ssh/arm` that can log in as `muhaoxing`. |
| `CHATGPT2API_AUTH_KEY` | A newly generated, high-entropy API key for this deployment. |

The workflow syncs source files with `rsync`, then builds on the ARM server. It
intentionally preserves these server files between releases:

- `data/`
- `config.json`
- `.env`

The domain must resolve to `140.238.56.209` before Certbot can issue its
certificate. Until then, the workflow still deploys the app and keeps an HTTP
reverse proxy ready; a later push or manual run automatically retries TLS.
`image.shuangdeng.sapce` and `image-d.shuangdeng.sapce` are not deployed because
they have no DNS records.
