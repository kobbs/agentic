# Nextcloud Docker Compose Deployment

This directory contains a complete, production-ready Docker Compose stack for Nextcloud.

The stack includes:
* **Nextcloud** (Apache/PHP image)
* **PostgreSQL 16** (Database backend)
* **Redis** (Local and distributed memory caching)
* **Traefik** (Reverse proxy with automated SSL via Let's Encrypt HTTP challenge)
* **Cron** (Dedicated background job execution for Nextcloud)

## Prerequisites

1.  **Docker and Docker Compose:** Ensure you have modern versions of Docker and Docker Compose installed on your host.
2.  **Public IP and DNS:** The server running this stack must be accessible from the internet on ports 80 and 443. Your chosen domain name (e.g., `nextcloud.example.com`) must point to your server's public IP address so Traefik can perform the Let's Encrypt HTTP challenge.

## Setup Instructions

### 1. Configure the Environment

First, create your `.env` file by copying the provided example:

```bash
cp .env.example .env
```

Open `.env` in a text editor and fill in the blanks:

*   `NEXTCLOUD_FQDN`: Your fully qualified domain name (e.g., `nextcloud.example.com`).
*   `ACME_EMAIL`: Your email address for Let's Encrypt notifications.
*   `POSTGRES_PASSWORD`: A strong password for the database.
*   *(Optional)* `NEXTCLOUD_ADMIN_USER` and `NEXTCLOUD_ADMIN_PASSWORD`: If set, Nextcloud will automatically install itself using these credentials on the first run.

### 2. Prepare Data Directories and Permissions

All persistent data is stored in bind mounts under the `./data` directory in this folder. You need to create the directory structure and set proper permissions, particularly for Traefik's `acme.json` file which stores your SSL certificates.

Run the following commands:

```bash
# Create the directory structure
mkdir -p data/traefik data/db data/redis data/nextcloud

# Create the acme.json file and set the correct permissions for Traefik
touch data/traefik/acme.json
chmod 600 data/traefik/acme.json
```

### 3. Spin up the Stack

With the configuration in place, you can start the stack in detached mode:

```bash
docker compose up -d
```

Traefik will automatically request an SSL certificate from Let's Encrypt. The first time you start the stack, Nextcloud might take a few minutes to initialize its database and files.

### 4. Access Nextcloud

Navigate to your domain (e.g., `https://nextcloud.example.com`) in your web browser. If you did not provide admin credentials in the `.env` file, you will be prompted to create an admin account.

## Important Note on Server-Side Encryption

If you plan to enable Server-Side Encryption (SSE) for user data, you can do this from within the Nextcloud web interface after the initial deployment. Go to **Settings > Administration > Security** and enable server-side encryption. Be sure to read the Nextcloud documentation on SSE before enabling it, as it has performance implications and requires careful management of encryption keys.
