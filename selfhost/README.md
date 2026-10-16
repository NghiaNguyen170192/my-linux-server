# Self-host stack

VPS setup steps are in the [repository README](../README.md). This folder is what those steps start.

```text
selfhost/
├── .env.example
├── blog/                         # Astro site, not started
├── ghost/                        # Ghost and MySQL, served at YOUR_DOMAIN
├── notebooks/                    # JupyterLab, conda, Python kernel
├── n8n/                          # n8n playground
├── data/                         # Airflow, Postgres, Redis, MinIO, pgAdmin
│   ├── dags/
│   ├── plugins/
│   └── config/
├── management/                   # Portainer, Homarr, Uptime Kuma, Grafana, Keycloak, RedisInsight
│   ├── docker-compose.adguard.yml
│   ├── grafana/provisioning/
│   └── prometheus/prometheus.yml
├── media/                        # Komga, optional
├── networking/                   # nginx and Certbot
│   ├── nginx/
│   └── certbot/cloudflare.ini.example
├── scripts/
│   ├── setup-deploy-user.sh   # one-time login, before the workflow can connect
│   ├── bootstrap-vps.sh       # Deploy workflow, bootstrap enabled
│   ├── ci-deploy.sh           # Deploy workflow, containers enabled
│   ├── issue-cert.sh
│   ├── deploy.sh
│   └── renew-cert.sh          # daily cron installed by bootstrap
└── security/                     # fail2ban, ssh, sysctl, docker, logrotate
```

Two Docker networks:

- `nginx-network` is the only network nginx can route to.
- `data-internal` holds Postgres, Redis, and Ghost's MySQL. nginx is not on that network. Keycloak, RedisInsight, and Ghost join it so they can reach those databases, and they also join `nginx-network` so the proxy can reach them.

Airflow settings come from `data/docker-compose.yml` and `.env`. There is no checked-in `airflow.cfg`.

`scripts/setup-deploy-user.sh` runs once, as root, before GitHub can log in. After that, the Deploy workflow is what runs on the server. Enable **bootstrap** for Docker, the firewall, and fail2ban. Enable **containers** to issue the certificate and start the stacks. Airflow, Postgres, Redis, MinIO, and pgAdmin stay off until `DEPLOY_ARGS` includes `--with-data`. `--with-adguard`, `--with-komga`, and `--with-flower` add those services.

## beoni-oms

beoni-oms (`beoni.YOUR_DOMAIN`) is deployed from a separate repository cloned at `/opt/beoni-oms` on the server. It is not a subdirectory here.

**One-time setup:** add these GitHub secrets before enabling the beoni dispatch input:

| Secret | Description |
|--------|-------------|
| `BEONI_POSTGRES_PASSWORD` | PostgreSQL password for the beoni DB |
| `BEONI_SECRET_KEY` | FastAPI JWT signing key (`python3 -c "import secrets; print(secrets.token_urlsafe(32))"`) |
| `BEONI_FIRST_SUPERUSER` | Email address of the initial admin user |
| `BEONI_FIRST_SUPERUSER_PASSWORD` | Password for the initial admin user |
| `BEONI_GITHUB_TOKEN` | PAT with `repo` read scope (only needed if beoni-oms is a private repo) |

**Optional GitHub variable:** set `BEONI_OMS_REPO` to the `owner/repo` path if it differs from `NghiaNguyen170192/beoni-oms`.

**Deploy:** run the Deploy workflow with both **containers** and **beoni** checked. The workflow clones beoni-oms to `/opt/beoni-oms`, writes its `.env`, and runs `deploy.sh --with-beoni`.

**Cloudflare DNS** (one-time): add `beoni` → A record and `*.beoni` → CNAME to `beoni.YOUR_DOMAIN` in the `YOUR_DOMAIN` zone so that `api.beoni.YOUR_DOMAIN` and `adminer.beoni.YOUR_DOMAIN` resolve.
