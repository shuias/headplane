# Headplane

> A feature-complete web UI for [Headscale](https://headscale.net)

**English** | [简体中文](./README.zh-CN.md)

<picture>
    <source
        media="(prefers-color-scheme: dark)"
        srcset="./docs/assets/preview-dark.png"
    >
    <source
        media="(prefers-color-scheme: light)"
        srcset="./docs/assets/preview-light.png"
    >
    <img
        alt="Preview"
        src="./docs/assets/preview-dark.png"
    >
</picture>

Headscale is the de-facto self-hosted version of Tailscale, a popular Wireguard
based VPN service. By default, it does not ship with a web UI, which is where
Headplane comes in. Headplane is a feature-complete web UI for Headscale, allowing
you to manage your nodes, networks, and ACLs with ease.

Headplane aims to replicate the functionality offered by the official Tailscale
product and dashboard, being one of the most feature complete Headscale UIs available.

## Features

- Machine management, including expiry, network routing, name, and owner management
- Access Control List (ACL) and tagging configuration for ACL enforcement
- Support for OpenID Connect (OIDC) as a login provider
- The ability to edit DNS settings and automatically provision Headscale
- Configurability for Headscale's settings

## Local deployment (this fork)

This fork of [tale/headplane](https://github.com/tale/headplane) additionally
carries a self-contained Docker Compose stack that runs Headplane together with
Headscale, Dex (a local OIDC provider) and Traefik. It is meant for evaluating
OIDC sign-in and the Headplane ↔ Headscale integration on a single machine.

### Services

| Service    | Container           | Image                            | Exposed                | Role                                             |
| ---------- | ------------------- | -------------------------------- | ---------------------- | ------------------------------------------------ |
| traefik    | `headplane-traefik` | `traefik:v3.2`                   | `8082` (web), `8081`   | Single entrypoint, routes by path                |
| dex        | `headplane-dex`     | `ghcr.io/dexidp/dex:v2.41.1`     | internal `5556`        | OIDC issuer for Headplane and Headscale          |
| headscale  | `headscale`         | `headscale/headscale:0.29.3`     | internal `8080`        | Tailnet control server                           |
| headplane  | `headplane`         | `ghcr.io/tale/headplane:latest`  | internal `3000`        | Web UI, served under `/admin`                    |
| nginx-auth | `headplane-nginx-auth` | `nginx:1.27-alpine`           | none                   | Optional Basic Auth sidecar, opt-in via `--profile basic-auth` |

Path routing on port `8082`:

| Path                                     | Backend    |
| ---------------------------------------- | ---------- |
| `/admin` and `/admin/**`                 | Headplane  |
| `/.well-known/**`, `/dex/**`, `/oidc/**` | Dex        |
| everything else                          | Headscale  |

### Prerequisites

- Docker 26 or newer with Compose v2/v5
- The hostname `dex.local` resolving to `127.0.0.1`, on the host **and** in the
  browser. Add it once with:

  ```sh
  sudo sh -c 'echo "127.0.0.1 dex.local" >> /etc/hosts'
  ```

  Containers do not need this: Compose maps `dex.local` to `host-gateway` for
  Headplane and Headscale, so OIDC discovery works from inside them too.

### First run

1. Generate the local secret files and the `.env` template:

   ```sh
   ./scripts/bootstrap-secrets.sh
   ```

2. Fill in the values it reports as missing:

   - `secrets/headplane_headscale_api_key`: issue it with
     `docker exec headscale headscale apikeys create` after the stack is up.
   - `.env`: client secrets (must equal the values in `secrets/`) and the two
     bcrypt password hashes for the demo users.

3. Start everything:

   ```sh
   docker compose up -d
   docker compose ps
   ```

4. Open <http://dex.local:8082/admin/login> and sign in with
   `alice@example.com` / `secret123`. The first OIDC user becomes the Owner.

### How sign-in works

```text
Browser ──> Traefik :8082 ──> Headplane :3000 (/admin)
                │                   │
                ├──> Dex :5556      │ OIDC authorization code + PKCE
                │    (issuer, JWKS) │
                └──> Headscale :8080 │ API key (users list, nodes, ACLs)
```

Headplane authenticates the browser through Dex and then talks to Headscale
with a long-lived API key. After the OIDC callback it lists Headscale users and
associates the OIDC subject with the matching Headscale user, so both sides
share one identity.

Four values must agree character for character, or you get redirect loops or
`invalid_client`:

| Setting                                | Where                                                   |
| -------------------------------------- | ------------------------------------------------------- |
| Issuer                                 | `dex/config.yaml` `issuer`, `config.yaml` `oidc.issuer`, `headscale/config.yaml` `oidc.issuer` |
| Panel callback                         | `dex/config.yaml` `headplane-client.redirectURIs`, derived from `server.base_url` + `/admin/oidc/callback` |
| Control-plane callback                 | `dex/config.yaml` `headscale-client.redirectURIs`, derived from `oidc.public_base_url` + `/oidc/callback` |
| Cookie security vs. scheme             | `server.cookie_secure: false` while the entrypoint is plain HTTP |

Behind a reverse proxy, `X-Forwarded-Proto`, `X-Forwarded-Host` and
`X-Forwarded-Port` must describe the browser-visible origin; `compose.yaml`
sets them on the Headplane router.

### Configuration and secrets

Tracked files describe the deployment; credentials stay untracked.

| File                          | Tracked | Contents                                              |
| ----------------------------- | ------- | ----------------------------------------------------- |
| `compose.yaml`                | yes     | Services, routing, mounts                             |
| `config.yaml`                 | yes     | Headplane config, references `/run/secrets/*`         |
| `headscale/config.yaml`       | yes     | Headscale config, references `/run/secrets/*`         |
| `dex/config.yaml`             | yes     | Dex clients and users, references env var names       |
| `.env.example`                | yes     | Names of the Dex secrets and password hashes          |
| `scripts/bootstrap-secrets.sh`| yes     | Creates the local secret files                        |
| `.env`                        | no      | Dex client secrets and bcrypt hashes                  |
| `secrets/`                    | no      | Cookie signing key, Headscale API key, OIDC secrets   |
| `dex-data/`, `headplane-data/`| no      | SQLite databases                                      |
| `traefik/users.htpasswd`      | no      | Basic Auth file (`users.htpasswd.example` is tracked)  |

Headplane and Headscale read their secrets through the `*_path` options; Dex
reads them from the environment through `secretEnv` and `hashFromEnv`. Nothing
sensitive belongs in a tracked file.

### Operations

```sh
docker compose ps                     # status and health
docker compose logs -f headplane      # follow one service
docker compose restart headplane      # restart one service
docker compose pull && docker compose up -d   # update images

docker exec headscale headscale users list
docker exec headscale headscale nodes list
docker exec headscale headscale apikeys create
```

Health endpoints:

```sh
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8082/.well-known/openid-configuration
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8082/admin/login
docker inspect headplane --format '{{.State.Health.Status}}'
```

Back up `dex-data/`, `headplane-data/`, `.cache/headscale/` and `secrets/`.
Rotating a secret means writing the new value to its file (or `.env`) and
recreating the affected services; existing sessions are invalidated when
`cookie_secret` changes.

### Automation

Two cron jobs keep the stack current and available. Both write to `logs/`.

| Schedule | Script                | Job                                                        | Log                       |
| -------- | --------------------- | ---------------------------------------------------------- | ------------------------- |
| 05:00 daily | `scripts/daily-sync.sh` | Merge `upstream/main`, push the fork, pull images, restart | `logs/daily-sync.log`     |
| every 5 min | `scripts/watchdog.sh`   | Start missing containers, restart unhealthy ones            | `logs/watchdog.log`       |

`daily-sync.sh` exits without touching anything when upstream has no new
commits. When it does, it merges, pushes `main` to `origin`, then runs
`docker compose pull` and `docker compose up -d`. A merge that conflicts is
aborted and logged for manual handling, so the working tree is never left
half-merged. A failed push is logged but does not block the restart.

`watchdog.sh` starts any container that is not running, restarts Headplane
when its health check reports `unhealthy`, and restarts Headplane and Dex when
either `/.well-known/openid-configuration` or `/admin/login` stops returning
200. It waits 180 seconds after startup before probing, so a booting stack is
not mistaken for a broken one.

Pause the watchdog during planned maintenance with:

```sh
touch logs/.maintenance      # pause
rm logs/.maintenance         # resume
```

Boot behaviour comes from `restart: unless-stopped` on all four services plus
the Docker daemon being enabled, so the stack returns after a reboot. A stack
that was stopped explicitly with `docker compose down` stays down until the
next watchdog run.

Adjust or remove the jobs with `crontab -e`.

### Troubleshooting

| Symptom                                                | Cause                                                                 | Fix                                                        |
| ------------------------------------------------------ | --------------------------------------------------------------------- | ---------------------------------------------------------- |
| Headplane `unhealthy`, health endpoint returns 500     | Headscale or Dex unreachable at boot; Headplane's health check needs Headscale | Fix Headscale/Dex first; check `docker logs headplane` |
| `cannot specify static passwords without enabling password db` | Dex needs `enablePasswordDB: true` for `staticPasswords`     | Set it in `dex/config.yaml`                                 |
| Headscale crash-loops with `dial tcp [::1]:8082`       | OIDC issuer is a `localhost` URL, which never leaves the container     | Use the shared hostname (`dex.local`) in all three configs  |
| Redirect loop back to `/login` after sign-in           | `base_url`, issuer, callback URI or `cookie_secure` disagree          | Re-check the four values in the table above                 |
| `invalid_client` at the token endpoint                 | Client secret in `.env` differs from `secrets/`                        | Keep them identical, then recreate Dex and Headplane        |
| `discovery` returns 404                                | Traefik route precedence changed                                       | Check priorities: Headplane 200, Dex 150, Headscale 100     |
| `nginx-auth` restarts forever                          | Optional sidecar with a placeholder config                             | It is set to `restart: "no"`; re-enable it deliberately      |

### Syncing with upstream

```sh
git fetch upstream
git merge upstream/main
```

`origin` points at this fork, `upstream` at `tale/headplane`.

## Documentation

Refer to the [website](https://headplane.net) for installation and configuration
details. Deployment notes specific to this fork live in this README and in the
generated operations manual (`headplane运维及操作手册.html`).

## Versioning

Headplane uses [semantic versioning](https://semver.org/) for its releases (since v0.6.0).
Pre-release builds are available under the `next` tag and get updated when a new release
PR is opened and actively in testing.

## Contributing

Headplane is an open-source project and contributions are welcome! If you have
any suggestions, bug reports, or feature requests, please open an issue. Also
refer to the [contributor guidelines](./.github/CONTRIBUTING.md) for more info.

---

<picture>
    <source
        media="(prefers-color-scheme: dark)"
        srcset="./docs/assets/acls-dark.png"
    >
    <source
        media="(prefers-color-scheme: light)"
        srcset="./docs/assets/acls-light.png"
    >
    <img
        alt="ACLs"
        src="./docs/assets/acls-dark.png"
    >
</picture>

<picture>
    <source
        media="(prefers-color-scheme: dark)"
        srcset="./docs/assets/machine-dark.png"
    >
    <source
        media="(prefers-color-scheme: light)"
        srcset="./docs/assets/machine-light.png"
    >
    <img
        alt="Machine Management"
        src="./docs/assets/machine-dark.png"
    >
</picture>

> Copyright (c) 2025 Aarnav Tale
