If you want to develop with dawarich you can use the devcontainer, with your IDE. It is tested with visual studio code.

**NOTE:** On Apple Silicon (M1/M2/M3), `postgis/postgis:17-3.5-alpine` is not available due to architecture mismatch.
In `.devcontainer/docker-compose.yml`, replace it with `imresamu/postgis:17-3.5-alpine` instead before building the container.

Load the directory in Vs-Code and press F1. And Run the command: `Dev Containers: Rebuild Containers` after a while you should see a terminal.

Now you can create/prepare the Database (this need to be done once):
```bash
bundle exec rails db:prepare
```

Afterwards you can run sidekiq:
```bash
bundle exec sidekiq

```

And in a second terminal the dawarich-app:
```bash
bundle exec bin/dev
```

You can connect with a web browser to http://127.0.0.l:3000/ and login with the default credentials.

## Sign in with Apple (web) — local testing

The web Sign in with Apple flow is Cloud-only and requires HTTPS end-to-end (Apple's `form_post` callback rejects HTTP redirect_uris, and the auth-state cookies are set with `secure: true` unconditionally).

To exercise the flow against real Apple from a local machine:

1. Run a public HTTPS tunnel pointed at your local Rails server (e.g. `cloudflared tunnel`, `ngrok`, or Caddy with a tunnel).
2. Add the tunnel hostname to the Services ID's "Domains and Subdomains" list in the Apple Developer console, and add the corresponding `/users/auth/apple/callback` URL to "Return URLs". (Apple console steps are documented in Phase 0 of `superpowers/plans/2026-05-20-sign-in-with-apple-web.md`.)
3. Set these env vars before booting the app:
   ```bash
   SELF_HOSTED=false \
   APPLE_WEB_SERVICES_ID=app.dawarich.web \
   APPLE_WEB_TEAM_ID=<10-char Team ID> \
   APPLE_WEB_KEY_ID=<10-char Key ID> \
   APPLE_WEB_P8_BASE64=$(base64 -i ~/path/to/AuthKey_<KEY_ID>.p8 | tr -d '\n') \
   APPLE_WEB_REDIRECT_URI=https://<your-tunnel>/users/auth/apple/callback \
   bundle exec bin/dev
   ```
4. Visit `https://<your-tunnel>/users/sign_in` and click "Sign in with Apple".

Self-hosters cannot run this flow — it binds to Dawarich's Apple Developer account and the `dawarich.app` domain. Self-hosted instances use OIDC for SSO instead.
