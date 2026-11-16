<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://github.com/CodeClarityCE/identity/blob/main/logo/vectorized/logo_name_white.svg">
  <source media="(prefers-color-scheme: light)" srcset="https://github.com/CodeClarityCE/identity/blob/main/logo/vectorized/logo_name_black.svg">
  <img alt="codeclarity-logo" src="https://github.com/CodeClarityCE/identity/blob/main/logo/vectorized/logo_name_black.svg">
</picture>

# CodeClarity Deployment Guide

**Secure your software, empower your team.**

[![License](https://img.shields.io/github/license/codeclarityce/codeclarity-dev)](LICENSE.txt)
[![Website](https://img.shields.io/badge/Website-Visit-blue)](https://www.codeclarity.io)

## 🚀 What is CodeClarity?

CodeClarity is a **powerful, open-source security analysis platform** that serves as an alternative to Snyk, Checkmarx, and Black Duck. It provides:

- **⚡ Fast source code analysis** - Identify dependencies, licenses, and vulnerabilities instantly
- **🏠 Full on-premises control** - Your code never leaves your environment
- **🔗 CI/CD integration** - Seamlessly integrates with GitHub Actions, Jenkins, and more
- **🧩 Extensible plugin system** - Create custom analysis pipelines with modular plugins
- **📊 Comprehensive reporting** - SBOM generation, vulnerability detection, license compliance

### Current Plugin Ecosystem

- **Built-in Plugins**: SBOM builder, vulnerability finder, license finder
- **External Integrations**: CodeQL support
- **Expanding Library**: More plugins coming soon

![CodeClarity Platform Overview](https://github.com/CodeClarityCE/identity/blob/main/illustration/rasterized/demo_illu.png)

<details open="open">
<summary>Table of Contents</summary>

- [CodeClarity Deployment Guide](#codeclarity-deployment-guide)
  - [🚀 What is CodeClarity?](#-what-is-codeclarity)
  - [📋 System Requirements](#-system-requirements)
  - [⚡ Install](#-install)
  - [👤 Create the First User](#-create-the-first-user)
  - [🔒 TLS](#-tls)
  - [🔌 Ports](#-ports)
  - [🔐 Secrets](#-secrets)
  - [📚 Knowledge Database](#-knowledge-database)
  - [🔄 Upgrade and Maintain](#-upgrade-and-maintain)
  - [🤝 Contributing](#-contributing)
  - [🐛 Reporting Issues](#-reporting-issues)
  - [📄 License](#-license)

</details>

## 📋 System Requirements

- **Docker Engine** with **Docker Compose 2.24 or later**. [Docker install](https://docs.docker.com/engine/install/) | [Compose install](https://docs.docker.com/compose/install/)
- **CodeQL is optional and x86_64 only.** The CodeQL plugin is off unless you turn on its profile: `docker compose --profile codeql up -d`, or `COMPOSE_PROFILES=codeql` in `.env`. It runs only on `linux/amd64` and is not supported on arm64, where the rest of the stack runs natively. While it is off, analyzers that use CodeQL are shown as unavailable and cannot be started; the Default Analyzer does not use CodeQL.
- **CPU:** at least 4 vCPUs. The vulnerability and CodeQL plugins are each limited to 4 CPUs, and Docker refuses to start a container whose CPU limit is above the host's count. 8 vCPUs are recommended.
- **Memory:** at least 16 GB. The services reserve about 11 GB together. 32 GB is recommended for several analyses at once.
- **Disk:** at least 40 GB, on SSD. About 1.5 GB of compressed images, of which CodeQL is 1.2 GB, plus the 0.6 GB knowledge dump image, which stays on disk after the restore. Then the knowledge database, analyses, cached git clones and 30 days of metrics, which all grow. 100 GB is recommended.
- **Network:** inbound 80/tcp and 443/tcp (443/udp for HTTP/3, optional); see [Ports](#-ports) to use others. Outbound to Docker Hub, the git hosts you analyze, the npm registry and the vulnerability sources (NVD, OSV).

Nothing else is needed on the host: no git, git-lfs, openssl or installer script.

## ⚡ Install

1. Download `docker-compose.yaml` and `env.example` from the [latest release](https://github.com/CodeClarityCE/deployment/releases) into an empty directory. Every image in that Compose file is pinned by digest, so every install of a release runs the same images. To check where the files came from: `gh attestation verify docker-compose.yaml -R CodeClarityCE/deployment` (and the same for `env.example`).
2. Save `env.example` as `.env` (`cp env.example .env`). The release asset is this repository's `.env.example`; GitHub drops the leading dot when it is uploaded, so it downloads as `env.example`. It already sets `CODECLARITY_VERSION` to the release. Set `DOMAIN` to the name the instance is reached at. HTTPS follows it (see [TLS](#-tls)).
3. Start the stack:

   ```bash
   docker compose up -d
   ```

On first start, one-shot setup jobs run before the app starts: `generate-secrets` creates the instance's secrets, the database init script creates the databases and roles, `knowledge-restore` restores the knowledge database from the knowledge dump image, `migrate` applies the migrations, and `default-analyzer` creates the global "Default Analyzer". Nothing prompts and no file is rewritten. If a job fails, the app services stay stopped and the job's error is in `docker compose logs <job>`.

Running `docker compose up -d` again is always safe: each job finds its work done and does nothing.

## 👤 Create the First User

A new instance has no accounts. Create one, then log in at `https://<DOMAIN>`:

```bash
docker compose run --rm api create-user --email you@example.com --name "Your Name" --password 'a-long-password'
```

The user is activated and verified, so no mail server is needed, and owns a personal organization. Running it again for an existing email changes nothing; add `--reset-password` to set a new password. To keep the password out of your shell history, pass it as `CREATE_USER_PASSWORD` instead: `docker compose run --rm -e CREATE_USER_PASSWORD api create-user ...`. `CREATE_USER_EMAIL` and `CREATE_USER_NAME` in `.env` are defaults for the other two flags.

## 🔒 TLS

Caddy, in the `frontend` service, serves HTTPS for `DOMAIN` with no extra steps:

- `DOMAIN=localhost`: a certificate from Caddy's internal certificate authority, so your browser asks you to trust it. Its root is in the `codeclarity_caddy_data` volume: `docker compose exec frontend cat /data/caddy/pki/authorities/local/root.crt`.
- A public name: a certificate from Let's Encrypt (or ZeroSSL), renewed automatically. DNS for the name must point at this host, and ports 80 and 443 must be reachable from the internet.
- Your own certificate: set `TLS_CERT` (full chain) and `TLS_KEY` in `.env` as PEM in double quotes, both or neither, then `docker compose up -d`. Caddy serves them for `DOMAIN` and does not request a certificate. Do the same after renewing them. Compose copies them into the container from `.env`; no file is mounted from the host.

To try a public name without hitting Let's Encrypt's rate limits, set `ACME_CA=https://acme-staging-v02.api.letsencrypt.org/directory`, run `docker compose up -d`, and check that `docker compose logs frontend` shows `certificate obtained successfully` and that `curl -kv https://<DOMAIN>/ 2>&1 | grep issuer` names a staging issuer (`(STAGING)`). Then remove `ACME_CA` and run `docker compose up -d` again; Caddy gets a trusted certificate.

## 🔌 Ports

Caddy publishes HTTP on 80 and HTTPS on 443. When one is taken on the host, set another in `.env`, then `docker compose up -d`:

```bash
HTTP_PORT=8080
HTTPS_PORT=8443
HTTP3_PORT=8443
```

The instance is then at `https://<DOMAIN>:8443`, and `http://<DOMAIN>:8080` redirects there. Links in emails and the GitHub and GitLab sign-in callbacks use the same port, so register the callbacks as `https://<DOMAIN>:8443/auth/github/callback` and `https://<DOMAIN>:8443/auth/gitlab/callback`. Leave `HTTPS_PORT` unset for 443: setting it to 443 adds `:443` to those URLs.

Automatic certificates for a public `DOMAIN` need ports 80 and 443 reachable from the internet as themselves. Behind other ports, use your own certificate (`TLS_CERT` and `TLS_KEY`, see [TLS](#-tls)), or forward 80 and 443 to the published ports.

## 🔐 Secrets

Every secret is generated on first start into the `codeclarity_secrets` Docker volume and never regenerated: the Postgres, role, pgbouncer and RabbitMQ passwords, the JWT signing keys, the internal certificate authority with the Postgres and RabbitMQ certificates, the cookie secret and the Grafana admin password. Each service mounts a volume holding only what it reads. No secret lives in this repository or in `.env`.

The Grafana admin password (user `admin`) is printed by:

```bash
docker compose run --rm --no-deps --entrypoint cat grafana /run/codeclarity/admin_password
```

Back up the `codeclarity_secrets` volume with the database: a restored database without its secrets locks the services out.

## 📚 Knowledge Database

The knowledge database is restored from the `codeclarityce/knowledge-dump` image on first start, and `service-knowledge` keeps it current. It runs without an NVD API key, at NVD's lower rate; for faster updates, [request a key](https://nvd.nist.gov/developers/request-an-api-key), set `NVD_API_KEY` in `.env` and run `docker compose up -d`.

## 🔄 Upgrade and Maintain

- `docker compose up -d`: install, upgrade or start. Migrations run once, before the API and services start.
- Upgrade: replace `docker-compose.yaml` with the new release's, set `CODECLARITY_VERSION` in `.env` to that release, then `docker compose up -d`. Users, analyses and secrets are kept, and the new migrations run first. The stack does not start while `.env` names another release than the Compose file; the `version-check` job's log says which.
- `docker compose down`: stop the stack. Data and secrets stay in their volumes.
- `docker compose logs -f <service>`: follow a service's logs.
- `docker compose pull`: download the images again.

> [!NOTE]
> Grafana alerts on failed or stale knowledge sources. Alerts show in Grafana until you add a contact point there. If you override `KNOWLEDGE_STALE_AFTER_HOURS_*` on the API, change the thresholds in the `grafana-alerting` config in `docker-compose.yaml` to match.

> [!CAUTION]
> Your data is stored in Docker volumes and persists between restarts. Back up the volumes, including `codeclarity_secrets`, before major updates.

## 🤝 Contributing

If you'd like to contribute code or documentation, please see [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines on how to do so.

## 🐛 Reporting Issues

Please report any issues with the setup process or other problems encountered while using this repository by opening a new issue in this project's GitHub page.

## 📄 License

This project is licensed under the AGPL-3.0-or-later license. You can find the full license details in the [LICENSE](./LICENSE) file.
