<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://github.com/CodeClarityCE/identity/blob/main/logo/vectorized/logo_name_white.svg">
  <source media="(prefers-color-scheme: light)" srcset="https://github.com/CodeClarityCE/identity/blob/main/logo/vectorized/logo_name_black.svg">
  <img alt="codeclarity-logo" src="https://github.com/CodeClarityCE/identity/blob/main/logo/vectorized/logo_name_black.svg">
</picture>
<br>
<br>

Secure your software empower your team.

[![License](https://img.shields.io/github/license/codeclarityce/codeclarity-dev)](LICENSE.txt)

<details open="open">
<summary>Table of Contents</summary>

- [Overview](#overview)
- [License](#license)
- [Requirements](#requirements)
- [Setup Instructions](#setup-instructions)
  - [1. Download and Execute the Setup Script](#1-download-and-execute-the-setup-script)
  - [2. Follow the Installation](#2-follow-the-installation)
    - [1. Installing on Localhost](#1-installing-on-localhost)
    - [2. Installing on a specific domain name](#2-installing-on-a-specific-domain-name)
  - [3. Update DB (Optional)](#3-update-db-optional)
  - [4. Maintaining the Platform](#4-maintaining-the-platform)
- [Start using the platform](#start-using-the-platform)
- [Contributing](#contributing)
- [Reporting Issues](#reporting-issues)

</details>

---
<br>

![CodeClarity! Secure your software empower your team!](https://github.com/CodeClarityCE/identity/blob/main/illustration/rasterized/demo_illu.png)

## Overview

This repository contains all the configuration files needed to deploy CodeClarity. It simplifies the setup process, allowing you to quickly get the platform running.
## License

This project is licensed under the AGPL-3.0-or-later license.  You can find the full license details in the [LICENSE](./LICENSE) file.

## Requirements

Before you begin, ensure you have the following installed on your system:

*   **curl:** Used for downloading the setup script and dumps.
*   **openssl:** Required for generating certificates.
*   **Docker:**  A containerization platform.  [Installation instructions](https://docs.docker.com/engine/install/) are available on the Docker website.
*   **Docker Compose:** A tool for defining and running multi-container Docker applications. [Installation instructions](https://www.digitalocean.com/community/tutorials/how-to-install-and-use-docker-compose-on-ubuntu-20-04) can be found here.
*   **make:** (Optional) Used for automating certain build and deployment tasks.

## Setup Instructions

### 1. Download and Execute the Setup Script

This script automates the cloning of the deployment repository and initiates the setup process.
```bash
curl -O https://raw.githubusercontent.com/CodeClarityCE/deployment/main/setup.sh && sh setup.sh
```

### 2. Follow the Installation
#### 1. Installing on Localhost
Answer ```Y``` to the question:
```bash
Is this installation running on localhost (Y/n)?
Y
```

Here are the actions performed:
1.  **Clone the Deployment Repository:** It retrieves the necessary configuration files from the CodeClarityCE deployment repository.
2.  **Start Docker Containers:** It initiates the Docker containers defined in the `docker-compose.yml` file, setting up the core services of CodeClarity.
3.  **Download Database Dumps:** It downloads pre-populated database dumps containing initial data for the platform.
4.  **Create Databases:** It creates the required databases for CodeClarity, ensuring a clean and organized data storage environment.
5.  **Restore Database Content:** It restores the downloaded database dumps into the created databases, populating the platform with initial data.
6.  **Restart Containers:** It restarts the Docker containers to apply the database changes and ensure all services are running with the latest data.

#### 2. Installing on a specific domain name
Answer ```n``` to the question:
```bash
Is this installation running on localhost (Y/n)?
n
```

Then provide the domain name pointing to your server (e.g. ```localtest.io```):
```
Enter the domain name (localtest.io):
localtest.io
```

CodeClarity can use Caddy to generate certificates for you if your server is publicly accessible.
If you want Caddy to generate the certificates, answer ```Y``` to the following question:
```
Do you want Caddy to generate certificates (Y/n)?
Y
```

If you want to use your own certificate, then answer ```n``` to this question.
The setup script will generate certificates in the `certs` directory that you can replace with your own before restarting the platform using `docker compose restart`.

### 3. Update DB (Optional)

Please apply for an NVD API key [here](https://nvd.nist.gov/developers/request-an-api-key), and fill it in `.env.codeclarity`.

Run the command to update the knowledge DB:

```bash
make knowledge-update
```

### 4. Maintaining the Platform
Once the initial configuration is complete, you no longer need to execute the setup script to start the platform. You can use standard Docker Compose commands for ongoing management:
```bash
# Start the platform
docker compose up -d

# Stop the platform
docker compose down

# Restart the platform
docker compose restart

# Pull the docker images from the repository
docker compose pull
```

To update the platform, simply pull the latest changes from the repository using `git pull` and then restart the containers with `docker compose up -d`.

## Start using the platform

You can visit [https://localhost:443](https://localhost:443) to start using the platform. You might need to accept the self-signed certificate generated by Caddy.

If you imported the dump we provide, you can connect using the following credentials:

- login: `john.doe@codeclarity.io`
- password: `ThisIs4Str0ngP4ssW0rd?`

Now, follow [this guide](https://www.codeclarity.io/docs/createanalysis) to create your first analysis!

## Contributing

If you'd like to contribute code or documentation, please see [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines on how to do so.

## Reporting Issues

Please report any issues with the setup process or other problems encountered while using this repository by opening a new issue in this project's GitHub page.
