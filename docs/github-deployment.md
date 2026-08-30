# GitHub Actions production deployment

Pushing to `main` deploys the current commit to `140.238.56.209` as `muhaoxing`.
The application is exposed only on `127.0.0.1:3010`; OpenResty publishes it at
`https://image.shuangdeng.sapce` and `https://image-d.shuangdeng.sapce` using one
application and one Let's Encrypt certificate. The server's existing
`certbot.timer` renews that certificate automatically.

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

Create A records for both deployment domains and point them to
`140.238.56.209`. They must resolve before Certbot can issue the shared
certificate. Until then, the workflow still deploys the app and keeps an HTTP
reverse proxy ready; a later push or manual run automatically retries TLS. The
similarly named `image.shuangdeng.space` is deliberately left unchanged because
it currently points to a different CDN.
