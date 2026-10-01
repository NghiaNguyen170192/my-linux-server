# Self-host stack

VPS setup steps are in the [repository README](../README.md). This folder is what those steps start.

```text
selfhost/
├── .env.example
├── blog/                         # Astro site, nqtn.dev
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
│   ├── setup-deploy-user.sh
│   ├── bootstrap-vps.sh
│   ├── issue-cert.sh
│   ├── ci-deploy.sh
│   ├── deploy.sh
│   ├── ufw-cloudflare.sh
│   ├── update-cloudflare-ips.sh
│   ├── renew-cert.sh
│   └── down.sh
└── security/                     # fail2ban, ssh, sysctl, docker, logrotate
```

Two Docker networks:

- `nginx-network` is the only network nginx can route to.
- `data-internal` holds Postgres and Redis. nginx is not on that network. Keycloak and RedisInsight join it so they can reach those databases, and they also join `nginx-network` so the proxy can reach them.

Airflow settings come from `data/docker-compose.yml` and `.env`. There is no checked-in `airflow.cfg`.

The login step is `scripts/setup-deploy-user.sh`. Container commands below run later, from this directory on the server:

```bash
bash scripts/issue-cert.sh
bash scripts/deploy.sh
bash scripts/renew-cert.sh
bash scripts/down.sh
```

`bash scripts/deploy.sh --without-data` skips Airflow. `--with-adguard`, `--with-komga`, and `--with-flower` add those services.
