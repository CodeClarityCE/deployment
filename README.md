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
- **External Integrations**: CodeQL support (optional, x86_64 only)
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
  - [🧩 Optional Components](#-optional-components)
  - [📈 Monitoring](#-monitoring)
  - [📏 Larger Instances](#-larger-instances)
  - [📚 Knowledge Database](#-knowledge-database)
  - [🔄 Upgrade and Maintain](#-upgrade-and-maintain)
  - [🤝 Contributing](#-contributing)
  - [🐛 Reporting Issues](#-reporting-issues)
  - [📄 License](#-license)

</details>

## 📋 System Requirements

The default stack is designed and tested for a **reference machine**: a Raspberry Pi 5 with 8 GB of memory and an SSD (arm64). A small x86_64 machine with the same memory, such as an 8 GB laptop, runs the same stack. For more, see [Larger Instances](#-larger-instances).

- **Docker Engine** with **Docker Compose 2.24 or later**. [Docker install](https://docs.docker.com/engine/install/) | [Compose install](https://docs.docker.com/compose/install/)
- **Platform:** `linux/amd64` or `linux/arm64`. Every default image runs natively on both. CodeQL is x86_64 only and not supported on arm64 (see [Optional Components](#-optional-components)).
- **CPU:** at least 4 vCPUs. No container is limited to more than 4 CPUs, and Docker refuses to start a container whose CPU limit is above the host's count.
- **Memory:** at least 8 GB. The memory limits of the containers that run by default add up to at most 6.5 GiB, which leaves 1.5 GiB of the 8 GiB for the host. Analyses run one at a time; further submissions wait in the queue and run in turn.
- **Disk:** at least 40 GB, on SSD. About 1.5 GB of compressed images, of which CodeQL is 1.2 GB and is only downloaded with its profile, plus the 0.6 GB knowledge dump image, which stays on disk after the restore. Then the knowledge database, analyses, cached git clones and, with monitoring on, 30 days of metrics, which all grow. 100 GB is recommended.
- **Network:** inbound 80/tcp and 443/tcp (443/udp for HTTP/3, optional), plus 3001/tcp for Grafana with the monitoring profile; see [Ports](#-ports) to use others. Outbound to Docker Hub, the git hosts you analyze, the npm registry and the vulnerability sources (NVD, OSV).

Nothing else is needed on the host: no git, git-lfs, openssl or installer script.

### Measured on the reference machine

A CI job on an arm64 runner runs the default stack with the knowledge dump and the Default Analyzer on an npm project of about 1,000 dependencies. It fails if a container is killed for running out of memory, the stack's peak memory goes over 6.5 GiB, UI pages or API calls go over 1 s at p95 while the analysis runs, or the analysis does not finish.

| Measure                                         | Target                                          | Measured                       |
| ----------------------------------------------- | ----------------------------------------------- | ------------------------------ |
| Stack peak memory during an analysis            | at most 6.5 GiB                                 | pending the first baseline run |
| Containers killed for running out of memory     | none                                            | pending the first baseline run |
| UI pages and API calls, p95, during an analysis | under 1 s                                       | pending the first baseline run |
| Default Analyzer, about 1,000 npm dependencies  | finishes                                        | pending the first baseline run |
| Analysis time                                   | recorded only; the runner is faster than a Pi 5 | pending the first baseline run |

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

`--name` takes a first and a last name, as signup does. The user is activated and verified, so no mail server is needed, and owns a personal organization. Running it again for an existing email changes nothing; add `--reset-password` to set a new password. To keep the password out of your shell history, pass it as `CREATE_USER_PASSWORD` instead: `docker compose run --rm -e CREATE_USER_PASSWORD api create-user ...`. `CREATE_USER_EMAIL` and `CREATE_USER_NAME` in `.env` are defaults for the other two flags.

## 🔒 TLS

Caddy, in the `frontend` service, serves HTTPS for `DOMAIN` with no extra steps:

- `DOMAIN=localhost`: a certificate from Caddy's internal certificate authority, so your browser asks you to trust it. Its root is in the `codeclarity_caddy_data` volume: `docker compose exec frontend cat /data/caddy/pki/authorities/local/root.crt`.
- A public name: a certificate from Let's Encrypt (or ZeroSSL), renewed automatically. DNS for the name must point at this host, and ports 80 and 443 must be reachable from the internet.
- Your own certificate: set `TLS_CERT` (full chain) and `TLS_KEY` in `.env` as PEM in double quotes, both or neither, then `docker compose up -d`. Caddy serves them for `DOMAIN` and does not request a certificate. Do the same after renewing them. Compose copies them into the container from `.env`; no file is mounted from the host.

To try a public name without hitting Let's Encrypt's rate limits, set `ACME_CA=https://acme-staging-v02.api.letsencrypt.org/directory`, run `docker compose up -d`, and check that `docker compose logs frontend` shows `certificate obtained successfully` and that `curl -kv https://<DOMAIN>/ 2>&1 | grep issuer` names a staging issuer (`(STAGING)`). Then remove `ACME_CA` and run `docker compose up -d` again; Caddy gets a trusted certificate.

## 🔌 Ports

Caddy publishes HTTP on 80 and HTTPS on 443, and Grafana on 3001, which answers only with the [monitoring](#-monitoring) profile. The API has no port of its own: it is at `https://<DOMAIN>/api`. When 80 or 443 is taken on the host, set another in `.env`, then `docker compose up -d`:

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

## 🧩 Optional Components

Two components are off by default, so a small machine spends its memory on analyses. Each has a Compose profile that turns it on:

| Profile      | Runs                                                                           | Platform                    |
| ------------ | ------------------------------------------------------------------------------ | --------------------------- |
| `monitoring` | Prometheus, Grafana and the Postgres exporter (see [Monitoring](#-monitoring)) | amd64 and arm64             |
| `codeql`     | The CodeQL plugin, for analyzers that use CodeQL                               | x86_64 (`linux/amd64`) only |

To turn one or both on, list them in `.env`, then run `docker compose up -d`:

```bash
COMPOSE_PROFILES=monitoring,codeql
```

`docker compose --profile codeql up -d` does the same for one run, without changing `.env`.

> [!IMPORTANT]
> CodeQL is not supported on arm64, such as a Raspberry Pi. Leave the `codeql` profile off there: the image is only built for `linux/amd64`, and running it under emulation is not supported.

### Unavailable analyzers

An analyzer is shown as unavailable when a plugin it needs is not running, and starting an analysis with it is refused with the same reason, so nobody waits for a failure:

- **Unavailable (off on this instance):** the plugin belongs to an optional component that is not turned on, such as CodeQL. The reason names the component, for example "Needs CodeQL, which is off on this instance." Turn on its profile to make it available.
- **Temporarily unavailable:** a plugin that should run has stopped, for example because it crashed or is restarting. The reason names the plugin and says to try again shortly, for example "vuln-finder is temporarily down. Try again shortly." The API logs a warning naming the plugin (`docker compose logs api`), and the organization's analyzers list shows the same state. Once the plugin runs again, its analyzers are available with no other step.

Both are detected live, from whether a plugin is connected to its queue; there is no setting to keep in sync. If a plugin stops while an analysis is waiting on it, the dispatcher fails that analysis a few minutes later, naming the plugin, instead of leaving it to the 24 h recovery limit.

## 📈 Monitoring

Prometheus, Grafana and the Postgres exporter are an optional component, off by default so a small machine spends its memory on analyses. To turn them on, set this in `.env`, then run `docker compose up -d`:

```bash
COMPOSE_PROFILES=monitoring
```

Grafana is then at `https://<DOMAIN>:3001`, as user `admin` with the password printed by the command in [Secrets](#-secrets). While monitoring is off, that address answers `503` with a message saying how to turn it on.

Prometheus does not scrape CodeQL by default. With the `codeql` profile on, add `'plugin-codeql:8080'` to the `codeclarity-plugins` targets in `config/prometheus.yml`.

To turn monitoring off again, remove `COMPOSE_PROFILES=monitoring` and stop its containers; their data stays in its volumes:

```bash
docker compose --profile monitoring rm --stop --force prometheus grafana postgres_exporter
```

## 📏 Larger Instances

On a bigger machine, run several analyses at once and give Postgres more memory. This example is for an x86_64 host with 8 or more vCPUs and 32 GB of memory: 8 downloaders, 4 of each analysis plugin, Postgres with four times the default memory, and both optional components. Together its containers' memory limits add up to about 25 GiB.

Add this to `.env` (on arm64, leave out `codeql`):

```bash
COMPOSE_PROFILES=monitoring,codeql
PG_SHARED_BUFFERS=4GB
PG_EFFECTIVE_CACHE_SIZE=12GB
PG_WORK_MEM=32MB
```

Save this as `docker-compose.override.yaml` next to `docker-compose.yaml`. Compose reads both, and upgrading only replaces `docker-compose.yaml`, so the override stays:

```yaml
services:
  service-downloader:
    deploy:
      replicas: 8
  plugin-js-sbom:
    deploy:
      replicas: 4
  plugin-php-sbom:
    deploy:
      replicas: 4
  plugin-license-finder:
    deploy:
      replicas: 4
  plugin-vuln-finder:
    deploy:
      replicas: 4
  # Room for 4 GB of shared buffers plus the connections' work memory.
  db:
    deploy:
      resources:
        limits:
          memory: 8G
```

Then run `docker compose up -d`. To check the merged result first: `docker compose config`.

Keep `PG_SHARED_BUFFERS` at about half of the `db` memory limit, and `PG_MAX_CONNECTIONS` at 100 or more. More replicas do not need more Postgres connections: pgbouncer opens at most 80 and the rest wait for a free one.

## 📚 Knowledge Database

The knowledge database is restored from the `codeclarityce/knowledge-dump` image on first start, and `service-knowledge` keeps it current. It runs without an NVD API key, at NVD's lower rate; for faster updates, [request a key](https://nvd.nist.gov/developers/request-an-api-key), set `NVD_API_KEY` in `.env` and run `docker compose up -d`.

## 🔄 Upgrade and Maintain

- `docker compose up -d`: install, upgrade or start. Migrations run once, before the API and services start.
- Upgrade: replace `docker-compose.yaml` with the new release's, set `CODECLARITY_VERSION` in `.env` to that release, then `docker compose up -d`. Users, analyses and secrets are kept, and the new migrations run first. The stack does not start while `.env` names another release than the Compose file; the `version-check` job's log says which.
- Upgrading from a release where monitoring ran by default: monitoring is now off until you turn on its profile (see [Monitoring](#-monitoring)). Its containers keep running after the upgrade until you set the profile or remove them.
- Upgrading from a release before Postgres was tuned for 8 GB: Postgres now starts with 1 GB of shared buffers, a 3 GB cache size, 16 MB of work memory and at most 100 connections, in place of 128 MB of shared buffers and 200 connections. Settings are not migrated: on a bigger machine, raise them with the `PG_*` settings in `.env` and the `db` memory limit (see [Larger Instances](#-larger-instances)).
- Upgrading from a release that published port 3000: it is no longer published (nothing answered on it), so any firewall or forwarding rule for 3000 can go.
- `docker compose down`: stop the stack. Data and secrets stay in their volumes.
- `docker compose logs -f <service>`: follow a service's logs.
- `docker compose pull`: download the images again.

> [!NOTE]
> With monitoring on, Grafana alerts on failed or stale knowledge sources. Alerts show in Grafana until you add a contact point there. If you override `KNOWLEDGE_STALE_AFTER_HOURS_*` on the API, change the thresholds in the `grafana-alerting` config in `docker-compose.yaml` to match.

> [!CAUTION]
> Your data is stored in Docker volumes and persists between restarts. Back up the volumes, including `codeclarity_secrets`, before major updates.

## 🤝 Contributing

If you'd like to contribute code or documentation, please see [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines on how to do so.

## 🐛 Reporting Issues

Please report any issues with the setup process or other problems encountered while using this repository by opening a new issue in this project's GitHub page.

## 📄 License

This project is licensed under the AGPL-3.0-or-later license. You can find the full license details in the [LICENSE](./LICENSE) file.
