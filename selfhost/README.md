# Self-host stack

VPS setup steps are in the [repository README](../README.md). This folder is what those steps start.

```text
selfhost/
├── .env.example
├── blog/                         # Astro site, not started
├── ghost/                        # Ghost and MySQL, served at YOUR_DOMAIN
├── notebooks/                    # JupyterLab, conda, Python kernel
├── n8n/                          # n8n playground
├── data/                         # Airflow, Postgres, Redis, MinIO, pgAdmin, Beoni OMS profile
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

`beoni.YOUR_DOMAIN` is the dashboard and `beoni-api.YOUR_DOMAIN` is the API. Both are one label under `*.YOUR_DOMAIN`, which is the name Cloudflare's free certificate can serve. They use the shared Postgres (database `beoni_oms`, role `beoni`). nginx proxies them. pgAdmin is the database UI.

Images are `${DOCKERHUB_USERNAME}/beoni-oms-backend` and `${DOCKERHUB_USERNAME}/beoni-oms-frontend` on Docker Hub. The beoni-oms repo publishes them from `.github/workflows/publish-images.yml` on each push to `master`.

**GitHub secrets** on this repo, before enabling the beoni switch:

| Secret | Description |
|--------|-------------|
| `BEONI_POSTGRES_PASSWORD` | Password for the `beoni` role. 16+ letters and digits. |
| `BEONI_SECRET_KEY` | FastAPI signing key (`python3 -c "import secrets; print(secrets.token_urlsafe(32))"`) |
| `BEONI_FIRST_SUPERUSER` | Email of the initial admin user |
| `BEONI_FIRST_SUPERUSER_PASSWORD` | Password for that user. 16+ letters and digits. |
| `DOCKERHUB_USERNAME` | Docker Hub account that owns the images |
| `DOCKERHUB_TOKEN` | Docker Hub access token that can pull those images |

The same `DOCKERHUB_USERNAME` and a token that can push go on the beoni-oms repo.

**Deploy:** publish the images first, then run Deploy here with **containers** and **beoni** checked. That writes the secrets, creates the Cloudflare records below, pulls the images, creates the database, and runs migrations.

**Cloudflare DNS:** Deploy creates proxied `A` records for `beoni` and `beoni-api`. `api.beoni.YOUR_DOMAIN` stays broken on the free plan because Cloudflare's certificate only covers one label.

In pgAdmin, add a server with host `postgres`, user `beoni`, database `beoni_oms`.
