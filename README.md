# My Linux Server Configuration

Self-hosted services running on a Linux server via Docker Compose, organized into independent stacks behind an Nginx reverse proxy.

## Project Structure

```
selfhost/
├── networking/           # Nginx Proxy Manager (reverse proxy + SSL)
├── blog/                 # Astro blog (s3343711/astro-blog)
├── data/                 # PostgreSQL, pgAdmin, Redis, MinIO, Apache Airflow 3.x
├── document-management/  # Komga (comic/manga server)
├── management/           # Homarr (dashboard), Portainer, Keycloak (SSO)
└── observability/        # Prometheus, Loki, Promtail, Grafana
```

## Prerequisites

1. Install Docker and Docker Compose on the server.
2. Create the shared network used by all stacks:
   ```bash
   docker network create nginx-network
   ```
3. Copy `.env.example` to `.env` in each folder that contains one, and fill in the values.

## Starting the Services

> **Important:** Start `networking` first — it owns the shared `nginx-network` and the reverse proxy.

### 1. Networking (Nginx Proxy Manager)

```bash
cd selfhost/networking
docker compose up -d
```

### 2. Data (PostgreSQL · pgAdmin · Redis · MinIO · Airflow)

```bash
cd selfhost/data
cp .env.example .env   # fill in secrets
docker compose up -d
```

### 3. Management (Homarr · Portainer · Keycloak)

```bash
cd selfhost/management
cp .env.example .env
docker compose up -d
```

### 4. Observability (Prometheus · Loki · Promtail · Grafana)

```bash
cd selfhost/observability
cp .env.example .env
docker compose up -d
```

### 5. Blog

```bash
cd selfhost/blog
docker compose up -d
```

### 6. Document Management (Komga)

```bash
cd selfhost/document-management
docker compose up -d
```

## Stopping a Stack

```bash
cd selfhost/<stack>
docker compose down
```

## Notes

- All stacks attach to the external `nginx-network`; configure virtual hosts and SSL in Nginx Proxy Manager (port `81`).
- Persistent data is stored under `~/selfhost-data/` on the host.
- The `data` stack uses a custom Airflow image — run `docker compose build` before `up` if you change the `Dockerfile`.
- Stacks are independent; one failing stack does not affect others.

