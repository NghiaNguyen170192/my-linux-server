# Self-host stack

VPS setup steps are in the [repository README](../README.md). This folder is what those steps start.

```text
selfhost/
├── .env.example
├── blog/                         # Astro site, YOUR_DOMAIN
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
- `data-internal` holds Postgres and Redis. nginx is not on that network. Keycloak and RedisInsight join it so they can reach those databases, and they also join `nginx-network` so the proxy can reach them.

Airflow settings come from `data/docker-compose.yml` and `.env`. There is no checked-in `airflow.cfg`.

`scripts/setup-deploy-user.sh` runs once, as root, before GitHub can log in. After that, the Deploy workflow is what runs on the server. Enable **bootstrap** for Docker, the firewall, and fail2ban. Enable **containers** to issue the certificate and start the stacks. `DEPLOY_ARGS` can be `--without-data`, `--with-adguard`, `--with-komga`, or `--with-flower`.
