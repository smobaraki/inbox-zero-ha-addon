# Inbox Zero Home Assistant Add-on

[Inbox Zero](https://www.getinboxzero.com) — the open source AI email assistant —
as a Home Assistant add-on.

The add-on runs the **official pre-built Inbox Zero stack** on the host Docker
daemon (via the add-on's Docker API access):

- Web app (`ghcr.io/elie222/inbox-zero`)
- BullMQ queue worker (same image, `start-worker.sh`)
- Scheduled-tasks cron loop
- Embedded infrastructure: PostgreSQL 16, Redis 7 and the Upstash-compatible
  Redis HTTP bridge (`hiett/serverless-redis-http`)

No external services are required, and all persistent data is kept on the
add-on's `/data` volume so it is included in regular Home Assistant backups.

## Installation

1. In Home Assistant, go to **Settings** → **Add-ons** → **Add-on Store**
2. Click the three dots menu → **Repositories**
3. Add: `https://github.com/smobaraki/inbox-zero-ha-addon`
4. Click **Add**, then install the **Inbox Zero** add-on
5. Configure (see below), then start

> The add-on requires Docker API access. It is granted automatically via
> `docker_api: true` in the add-on configuration (this also requires the add-on
> to run without AppArmor, which is configured in the add-on manifest).

> The add-on's `config.yaml` points to a prebuilt image. If you install from
> this repository before the image is published, build it once and push it to
> your own container registry (see [Building the image](#building-the-image))
> and update the `image:` line accordingly.

## Configuration

| Option | Description |
|--------|-------------|
| `domain` | **Required.** The public domain Inbox Zero is served from (e.g. `inbox.example.com`). Used to build `NEXT_PUBLIC_BASE_URL`. |
| `http_port` | Host port the web app listens on (default `3000`). |
| `google_client_id` | Google OAuth client ID. Leave empty if Google is not used. |
| `google_client_secret` | Google OAuth client secret. |
| `google_pubsub_topic_name` | Google Pub/Sub topic for Gmail push notifications (`projects/<id>/topics/<name>`). Optional; a placeholder is used when empty. |
| `microsoft_client_id` | Microsoft (Azure AD) OAuth client ID. |
| `microsoft_client_secret` | Microsoft OAuth client secret. |
| `microsoft_tenant_id` | Microsoft tenant ID. Leave `common` for personal accounts. |
| `llm_api_key` | API key for the AI provider (maps to `ANTHROPIC_API_KEY`; Anthropic is the default provider). |
| `default_llms` | Default model chain (`provider:model`). Default `anthropic:claude-sonnet-4-6`. |
| `auth_allowed_emails` | Optional comma-separated signup allowlist. |
| `bypass_premium_checks` | Bypass premium checks (default `true`). |
| `app_release` | Inbox Zero image tag. Default `latest`. |
| `extra_env` | Optional list of extra `KEY=VALUE` environment variables (for OpenAI/Slack/Telegram/etc.). |

All internal secrets (database password, Auth.js secret, email-encryption keys,
internal API key, cron secret, Redis tokens, Pub/Sub verification token) are
generated on first boot and stored in the add-on's `/data` volume — never in
this repository.

## HTTPS / OAuth (required for sign-in)

Inbox Zero signs users in through Google and/or Microsoft OAuth, which requires
a **public HTTPS URL**. The add-on publishes the web app on plain HTTP at
`http_port`; you must front it with a reverse proxy that terminates TLS at
`https://<domain>` and forwards to `http://<home-assistant-host>:<http_port>`.

Use whatever you already run — HA's own ingress, Nabu Casa remote access, Nginx
Proxy Manager, Caddy, Traefik, or a Cloudflare Tunnel. Configure the OAuth
providers' redirect URIs to `https://<domain>/api/auth/callback/<provider>`.

If you only use Microsoft sign-in, set `google_client_id` and
`google_client_secret` to `skipped` (the app requires non-empty values).

## First login

The first user who signs in becomes the Inbox Zero administrator.

## Building the image

The add-on image is tiny (Docker CLI + Compose + startup script); the Inbox
Zero stack itself is pulled from the GitHub Container Registry at runtime. Build
and push it like this:

```bash
cd inbox-zero
IMAGE=<your-dockerhub-user>/inbox-zero-ha-addon ./build.sh --push
```

Then set `image: <your-dockerhub-user>/inbox-zero-ha-addon` in
`inbox-zero/config.yaml`.

## Backups

All Inbox Zero data lives in the add-on's `/data` directory (PostgreSQL, Redis
and generated secrets). It is included in normal Home Assistant add-on backups.

## Troubleshooting

- Logs: open the add-on's **Log** tab (it streams the stack's container logs),
  or run `docker ps` / `docker compose -p inbox-zero-ha logs` from the HA host.
- **First start is slow**: the images are large and are pulled on first boot.
  Be patient and watch the **Log** tab.
- **Stopping the add-on** runs `docker compose down` for the `inbox-zero-ha`
  project. If the host reboots without a graceful stop, the
  `restart: unless-stopped` containers may keep running until the add-on is
  started (and stopped) again.
