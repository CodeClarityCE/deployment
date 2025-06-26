<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://github.com/CodeClarityCE/identity/blob/main/logo/vectorized/logo_name_white.svg">
  <source media="(prefers-color-scheme: light)" srcset="https://github.com/CodeClarityCE/identity/blob/main/logo/vectorized/logo_name_black.svg">
  <img alt="codeclarity-logo" src="https://github.com/CodeClarityCE/identity/blob/main/logo/vectorized/logo_name_black.svg">
</picture>

Secure your software empower your team.

[![License](https://img.shields.io/github/license/codeclarityce/codeclarity-dev)](LICENSE.txt)
[![Website](https://img.shields.io/badge/Website-Visit-blue)](https://www.codeclarity.io)

CodeClarity is an open-source alternative to Snyk, Checkmarx, and Black Duck, offering fast source code analysis to identify dependencies, licenses, and vulnerabilities instantly.

It runs fully on-premises, giving you full control over your code.

Integrate CodeClarity into your CI/CD (e.g., GitHub Actions, Bash) to block vulnerable code automatically.

Create custom analysis pipelines by linking plugins. Currently, there are three in-house plugins (SBOM builder, vulnerability finder, license finder) and one external (CodeQL), with more coming soon.

![CodeClarity! Secure your software empower your team!](https://github.com/CodeClarityCE/identity/blob/main/illustration/rasterized/demo_illu.png)

<details open="open">
<summary>Table of Contents</summary>

- [Overview](#overview)
- [License](#license)
- [Requirements](#requirements)
- [Setup Instructions](#setup-instructions)
  - [1. Download and Run the Setup Script](#1-download-and-run-the-setup-script)
    - [2. Installing on a specific domain name](#2-installing-on-a-specific-domain-name)
  - [3. Update the Knowledge Database (Optional)](#3-update-the-knowledge-database-optional)
  - [4. Maintaining the Platform](#4-maintaining-the-platform)
- [Start Using the Platform](#start-using-the-platform)
- [Contributing](#contributing)
- [Reporting Issues](#reporting-issues)

</details>

## Overview

This repository contains all the configuration files needed to deploy CodeClarity. It simplifies the setup process, allowing you to quickly get the platform running.

## License

This project is licensed under the AGPL-3.0-or-later license.  You can find the full license details in the [LICENSE](./LICENSE) file.

## Requirements

Before you begin, make sure your system meets the following requirements:

- **curl**: For downloading the setup script and database dumps. [Install instructions](https://curl.se/download.html)
- **git**: Required for cloning the deployment repository and updating the platform. [Install instructions](https://git-scm.com/downloads)
- **openssl**: Required for generating SSL certificates. [Install instructions](https://www.openssl.org/source/)
- **Docker & Docker Compose**: Containerization platform and orchestration tool for running CodeClarity. [Docker install](https://docs.docker.com/engine/install/) | [Compose install](https://docs.docker.com/compose/install/)
- **make** (optional): Simplifies maintenance and update tasks. [Install instructions](https://www.gnu.org/software/make/)

> [!TIP]
> If you're new to Docker, check out the <a href="https://docs.docker.com/get-started/" target="_blank">Docker Get Started guide</a> for a quick introduction.

## Setup Instructions

### 1. Download and Run the Setup Script

This script will automatically clone the deployment repository and guide you through the initial setup of CodeClarity.

> [!WARNING]
> Please make sure the Docker daemon is running before executing the setup script.

```bash
curl -O https://raw.githubusercontent.com/CodeClarityCE/deployment/main/setup.sh && bash setup.sh
```

<details>
  <summary>What does this script do?</summary>
  <ol>
    <li><strong>Clone the Deployment Repository:</strong> Downloads all necessary configuration files from the CodeClarityCE deployment repository.</li>
    <li><strong>Start Docker Containers:</strong> Launches the core CodeClarity services using <code>docker-compose.yml</code>.</li>
    <li><strong>Download Database Dumps:</strong> Retrieves pre-populated database dumps with initial platform data.</li>
    <li><strong>Create Databases:</strong> Sets up the required databases for CodeClarity, ensuring a clean environment.</li>
    <li><strong>Restore Database Content:</strong> Loads the initial data into the databases.</li>
    <li><strong>Restart Containers:</strong> Restarts all services to apply changes and ensure everything is running correctly.</li>
  </ol>
</details>

#### 2. Installing on a specific domain name

Answer ```n``` to the question:

```bash
Is this installation running on localhost (Y/n)?
n
```

Then provide the domain name pointing to your server (e.g. ```localtest.io```):

```bash
Enter the domain name (localtest.io):
localtest.io
```

CodeClarity can use Caddy to generate certificates for you if your server is publicly accessible.
If you want Caddy to generate the certificates, answer ```Y``` to the following question:

```bash
Do you want Caddy to generate certificates (Y/n)?
Y
```

If you want to use your own certificate, then answer ```n``` to this question.
The setup script will generate certificates in the `certs` directory that you can replace with your own before restarting the platform using `docker compose restart`.

### 3. Update the Knowledge Database (Optional)

To keep your vulnerability database up to date, you can refresh it using the latest data from the National Vulnerability Database (NVD).

> [!NOTE]
> Apply for a free [NVD API key](https://nvd.nist.gov/developers/request-an-api-key) and add it to your `.env.codeclarity` file before updating.

**To update the knowledge database, run:**

```bash
make knowledge-update
```

This will download and import the latest vulnerability data, ensuring your platform has the most current security information.

### 4. Maintaining the Platform

After the initial setup, you can manage CodeClarity using standard Docker Compose commands—no need to rerun the setup script.

> [!NOTE]
> Common Docker Compose Commands
>
> - `docker compose up -d`: Start the platform in the background (detached mode).
> - `docker compose down`: Stop the platform and remove containers.
> - `docker compose restart`: Restart all platform containers.
> - `docker compose pull`: Download the latest Docker images from the repository.

> [!TIP]
> To update CodeClarity to the latest version:
>
> - `git pull`: Fetch the latest changes from the deployment repository.
> - `docker compose pull`: Download updated Docker images.
> - `docker compose restart`: Restart containers to apply updates.

> [!CAUTION]
> Your data is stored in Docker volumes and will persist between restarts. However, always back up your data before performing major updates.

## Start Using the Platform

You're ready to access CodeClarity! Open [https://localhost:443](https://localhost:443) in your browser to get started.

> [!WARNING]
> Your browser may prompt you to accept the self-signed certificate generated by Caddy. This is expected for local installations.

> [!NOTE]
> To help you get started quickly, use the following credentials:
>
> - **Login:** `john.doe@codeclarity.io`
> - **Password:** `ThisIs4Str0ngP4ssW0rd?`

*We recommend changing your password after your first login.*

Ready to explore? Follow the [Create Your First Analysis](https://doc.codeclarity.io/docs/0.0.21/tutorials/basic/create-analysis) guide to begin analyzing your code!

## Contributing

If you'd like to contribute code or documentation, please see [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines on how to do so.

## Reporting Issues

Please report any issues with the setup process or other problems encountered while using this repository by opening a new issue in this project's GitHub page.
