# nqtn.dev

Docker services on a VPS, with nginx as the only process on ports 80 and 443. Cloudflare proxies the domain, Let's Encrypt proves ownership through the Cloudflare DNS API, and the host firewall, fail2ban, and SSH settings sit in front of the containers.

The stacks live in [`selfhost/`](selfhost/README.md). A merged pull request to `main` deploys them. GitHub Actions copies this repo to the VPS, writes the credentials from GitHub Secrets, and runs the scripts in `selfhost/scripts/`.

## Services

```mermaid
flowchart LR
  client[Browser] --> cf[Cloudflare]
  cf --> nginx[nginx]
  nginx --> blog[blog]
  nginx --> airflow[Airflow]
  nginx --> minio[MinIO]
  nginx --> admin[Portainer Homarr Grafana Uptime Kuma pgAdmin]
  airflow --> pg[(Postgres)]
  airflow --> redis[(Redis)]
  grafana --> prom[Prometheus]
```

| URL | Service |
| --- | --- |
| https://nqtn.dev | Astro blog |
| https://airflow.nqtn.dev | Airflow |
| https://minio.nqtn.dev | MinIO console |
| https://s3.nqtn.dev | MinIO S3 API |
| https://pgadmin.nqtn.dev | pgAdmin |
| https://portainer.nqtn.dev | Portainer |
| https://homarr.nqtn.dev | Homarr start page |
| https://status.nqtn.dev | Uptime Kuma health checks |
| https://grafana.nqtn.dev | Grafana, fed by Prometheus |
| https://keycloak.nqtn.dev | Keycloak, started with the data stack |
| https://redisinsight.nqtn.dev | RedisInsight |
| https://komga.nqtn.dev | Komga books and comics, optional |
| https://adguard.nqtn.dev | AdGuard Home, optional |
| https://flower.nqtn.dev | Celery Flower, optional |

Postgres, Redis, Prometheus, and the node exporter have no public ports. nginx is the only published service.

Use a VPS with 2 vCPU and 4 GB of RAM when Airflow is included. Ubuntu 24.04 or Debian 12. SSH key access. The domain `nqtn.dev` on Cloudflare, using Cloudflare's nameservers.

## 1. Cloudflare

In the Cloudflare dashboard for `nqtn.dev`:

1. **DNS → Records**. Add an `A` record for `@` pointing at the VPS IPv4 address, proxy on (orange cloud). Add an `A` record for `*` with the same address, proxy on. Add an `AAAA` record for each if the VPS has IPv6. Proxied wildcards work on every Cloudflare plan.
2. **SSL/TLS → Overview**. Set the mode to **Full (strict)** after the first successful deploy. Before the origin certificate exists, Cloudflare returns error 526, which is expected.
3. **SSL/TLS → Edge Certificates**. Turn on **Always Use HTTPS** and **Automatic HTTPS Rewrites**. Set **Minimum TLS Version** to 1.2.
4. **Security → Settings**. Turn on **Bot Fight Mode**. Leave the free managed WAF ruleset enabled.
5. **My Profile → API Tokens → Create Token**. Use the **Edit zone DNS** template and limit it to `nqtn.dev`. Save it as the GitHub secret `CLOUDFLARE_API_TOKEN`. It is only for certificate issuance.
6. Copy the **Zone ID** from the domain overview page. A second token, limited to the same zone with **Zone → Firewall Services → Edit**, is used later by fail2ban.

Turn on two-factor authentication for the Cloudflare account.

## 2. Deploy from GitHub

Merging a pull request into `main` starts the [Deploy workflow](.github/workflows/deploy.yml). You can also run it by hand from the Actions tab. The workflow SSHes to the VPS, copies the repository to `/opt/my-linux-server`, writes `selfhost/.env` and `selfhost/networking/certbot/cloudflare.ini` from secrets, issues the certificate when it is missing, and starts the containers. Those files stay on the server. They are not committed.

Add these repository secrets before the first merge. Settings → Secrets and variables → Actions → Secrets:

| Secret | Value |
| --- | --- |
| `SSH_HOST` | VPS address, `199.241.138.175` |
| `SSH_USER` | Deploy user on the VPS |
| `SSH_PRIVATE_KEY` | Private key that can log in as that user |
| `CERTBOT_EMAIL` | Mailbox Let's Encrypt uses for expiry notices |
| `CLOUDFLARE_API_TOKEN` | Zone DNS edit token from step 1 |
| `PGADMIN_DEFAULT_EMAIL` | pgAdmin login |
| `POSTGRES_PASSWORD` | Postgres |
| `REDIS_PASSWORD` | Redis |
| `MINIO_ROOT_PASSWORD` | MinIO |
| `PGADMIN_DEFAULT_PASSWORD` | pgAdmin |
| `AIRFLOW_WWW_USER_PASSWORD` | Airflow |
| `GRAFANA_ADMIN_PASSWORD` | Grafana |
| `KEYCLOAK_DB_PASSWORD` | Keycloak database |
| `KEYCLOAK_ADMIN_PASSWORD` | Keycloak admin |
| `FERNET_KEY` | Airflow Fernet key, see below |
| `HOMARR_SECRET_ENCRYPTION_KEY` | Homarr key, see below |

Passwords are 16 or more letters and digits. Symbols break the Redis and database URLs. Generate the two keys locally and store them in a password manager:

```bash
python3 -c "import base64,os; print(base64.urlsafe_b64encode(os.urandom(32)).decode())"
openssl rand -hex 32
```

The first value is `FERNET_KEY`. The second is `HOMARR_SECRET_ENCRYPTION_KEY` (64 hex characters). `selfhost/data/config/airflow.cfg` used to contain a Fernet key. That file is gone. Generate a new key. If that old file was ever pushed or copied off the machine, treat the old key as public and leave it unused.

Optional repository variable `DEPLOY_ARGS` is passed to `scripts/deploy.sh`. Leave it empty for the full stack. `--without-data` skips Airflow and its databases. `--with-adguard`, `--with-komga`, and `--with-flower` add those services. Optional variable `SSH_PORT` defaults to 22.

### One-time access on the VPS

GitHub needs an SSH login. On the server, as root, create the deploy user and the directory the workflow writes to. Replace the key with the public half of `SSH_PRIVATE_KEY`:

```bash
adduser --disabled-password --gecos "" deploy
install -d -o deploy -g deploy -m 700 /home/deploy/.ssh /opt/my-linux-server
printf '%s\n' 'ssh-ed25519 AAAA... deploy@github' > /home/deploy/.ssh/authorized_keys
chown deploy:deploy /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys
printf '%s\n' 'deploy ALL=(ALL) NOPASSWD: /usr/bin/bash /opt/my-linux-server/selfhost/scripts/bootstrap-vps.sh' > /etc/sudoers.d/selfhost-deploy
chmod 440 /etc/sudoers.d/selfhost-deploy
```

Use the same username in `SSH_USER`. If SSH is not on port 22, set `SSH_PORT` and change the `ufw allow` line in `scripts/bootstrap-vps.sh` and `scripts/ufw-cloudflare.sh` before the first deploy.

Then, in GitHub, Actions → Deploy → Run workflow, and enable **bootstrap**. That installs Docker, UFW, fail2ban, unattended upgrades, and the daily certificate renewal cron. After it finishes, run Deploy once more with bootstrap off. The second run is a new login, so the deploy user is in the `docker` group.

Later merges to `main` deploy on their own. Bootstrap stays off. The cron at `/etc/cron.d/selfhost-certbot` renews the certificate every day at 03:00 between deploys.

The certificate covers `nqtn.dev` and `*.nqtn.dev`. If this machine already has a certificate tree in `selfhost/networking/nginx/ssl`, move it to `selfhost/networking/certbot/conf` before the first deploy so Certbot does not issue a duplicate. Set Cloudflare SSL/TLS to **Full (strict)** after that deploy succeeds, then open https://nqtn.dev.

The blog image is `s3343711/astro-blog`. If the pull is denied, log in on the server with an account that can read that image and run the workflow again.

## 7. Accept web traffic only from Cloudflare

After https://nqtn.dev loads through the orange-cloud records, replace the public 80/443 rules with Cloudflare's published ranges:

```bash
sudo bash scripts/ufw-cloudflare.sh --yes
```

SSH stays open. Refresh the nginx client-IP list when you update the firewall ranges:

```bash
bash scripts/update-cloudflare-ips.sh
```

## 8. fail2ban

`bootstrap-vps.sh` already jails SSH. Four failures in ten minutes bans the address for a day. Repeat offenders are banned for a week. Add your home IP to `ignoreip` in `security/fail2ban/jail.d/selfhost.conf` before you install it, then re-run the bootstrap script so the jail file is copied again:

```bash
sudo bash scripts/bootstrap-vps.sh
```

Check it:

```bash
sudo fail2ban-client status sshd
```

HTTP bans on the VPS firewall miss the client, because the TCP connection comes from Cloudflare. The nginx jails in `selfhost.conf` send bans to the Cloudflare API instead, and they start disabled. To turn them on:

1. Create the firewall token from step 1.
2. Install the env file and restart fail2ban:

```bash
sudo cp security/fail2ban/cloudflare.env.example /etc/fail2ban/cloudflare.env
sudo chmod 600 /etc/fail2ban/cloudflare.env
sudoedit /etc/fail2ban/cloudflare.env
```

3. In `/etc/fail2ban/jail.d/selfhost.conf`, set `enabled = true` for `nginx-limit-req` and `nginx-probes`.
4. If `ROOT_DATA_PATH` is not `/var/lib/selfhost`, point `logpath` at `${ROOT_DATA_PATH}/nginx/logs/`.
5. `sudo systemctl restart fail2ban`

nginx writes the real client address only after it trusts `CF-Connecting-IP` from Cloudflare's ranges. That list is `networking/nginx/conf.d/00-cloudflare-realip.conf`.

## 9. SSH keys

From a second terminal, confirm you can log in with your key. Then:

```bash
sudo bash scripts/bootstrap-vps.sh --with-ssh-hardening
```

Keep the first session open until the second one succeeds. The drop-in disables password login and allows root only with a key. On Ubuntu, a later `PasswordAuthentication yes` in `/etc/ssh/sshd_config` overrides the drop-in. Comment that line out if password login still works, then reload SSH again.

## 10. First login

| Service | First visit |
| --- | --- |
| Portainer | Create the admin user at https://portainer.nqtn.dev. The container can see the Docker socket, so this login is root on the host. |
| Uptime Kuma | Create the admin user at https://status.nqtn.dev. Add an HTTPS monitor for each URL in the table above, interval 60 seconds. Optional Docker host: `tcp://socket-proxy:2375`. |
| Homarr | Create the admin user at https://homarr.nqtn.dev. Add the same URLs as tiles. Docker integration host `socket-proxy`, port `2375`. The socket proxy allows reads and blocks container create and delete. |
| Grafana | User and password are `GRAFANA_ADMIN_USER` and `GRAFANA_ADMIN_PASSWORD`. Prometheus is already added. Import dashboard **1860** (Node Exporter Full) and pick the Prometheus datasource. |
| pgAdmin | Email and password are `PGADMIN_DEFAULT_EMAIL` and `PGADMIN_DEFAULT_PASSWORD`. Register a server with host `postgres`, port `5432`, and the Postgres user, password, and database from `.env`. |
| MinIO | Console user is `MINIO_ROOT_USER`. API endpoint for clients is `https://s3.nqtn.dev`. Cloudflare's free plan limits a proxied request body to 100 MB. |
| Airflow | User and password are `AIRFLOW_WWW_USER_USERNAME` and `AIRFLOW_WWW_USER_PASSWORD`. Put DAG files in `data/dags`. Example DAGs are off. |
| Keycloak | https://keycloak.nqtn.dev when the data stack is running. Admin user and password are `KEYCLOAK_ADMIN` and `KEYCLOAK_ADMIN_PASSWORD`. The database role is created in Postgres on first start. |
| RedisInsight | https://redisinsight.nqtn.dev. Add a database with host `redis`, port `6379`, and `REDIS_PASSWORD`. |
| AdGuard | Only present after `--with-adguard`. See below. |

## 11. Cloudflare Access for the admin hostnames

Application passwords stay in place. Access adds a login wall in front of them.

In **Zero Trust → Access → Applications**, add a self-hosted application for each admin hostname (`airflow`, `minio`, `pgadmin`, `portainer`, `homarr`, `grafana`, `status`, `keycloak`, `redisinsight`, and `adguard` / `komga` / `flower` if you use them). Policy: allow your email. Leave `nqtn.dev` and `s3.nqtn.dev` without Access so the site and S3 clients keep working. S3 clients authenticate with MinIO keys.

## 12. Optional pieces

AdGuard Home, web UI only. DNS ports stay closed so the VPS is not an open resolver.

```bash
bash scripts/deploy.sh --with-adguard
```

The first start serves the setup wizard on port 3000. If https://adguard.nqtn.dev does not load, edit `networking/nginx/conf.d/55-adguard.conf`, change the upstream to `adguardhome:3000`, then:

```bash
docker exec nginx nginx -s reload
```

Finish the wizard, point the upstream back at `adguardhome:80`, and reload nginx again. For DNS on your own devices, use a VPN such as Tailscale and keep port 53 off the public interface.

Komga was on `komga.nqtn.dev` in the previous proxy config. The container is optional:

```bash
bash scripts/deploy.sh --with-komga
```

Libraries go in `/var/lib/selfhost/komga/data`. Change the volume in `media/docker-compose.yml` if the files already live somewhere else. Create the Komga admin user at https://komga.nqtn.dev and put that hostname behind Cloudflare Access.

Flower:

```bash
bash scripts/deploy.sh --with-flower
```

https://flower.nqtn.dev shows Celery workers. Put it behind Cloudflare Access with the other admin hostnames.

## 13. Operate

Day-to-day changes go out by merging a pull request to `main`. The workflow writes the current secrets and recreates the containers. On the server, from `/opt/my-linux-server/selfhost`, these are the same commands the workflow runs:

Stop containers and keep volumes:

```bash
bash scripts/down.sh
```

Pull a stack and recreate it. Example for the management stack:

```bash
docker compose --env-file .env -f management/docker-compose.yml pull
docker compose --env-file .env -f management/docker-compose.yml up -d
```

Bump image tags in the compose files when you mean to upgrade. Homarr, MinIO, and Komga follow `latest`. The other images are pinned. Airflow's Postgres volume is Postgres 16. A directory written by Postgres 13 has to be dumped with the old image and restored into 16.

Backup the database and the host data directory:

```bash
docker exec postgres pg_dump -U airflow airflow > "$HOME/airflow-$(date +%F).sql"
sudo tar -C /var/lib -czf "$HOME/selfhost-data-$(date +%F).tar.gz" selfhost
```

Named volumes (`postgres-db-volume`, Grafana, Portainer, Homarr, Uptime Kuma, Prometheus) live in Docker's volume directory. `pg_dump` covers the database. For the other volumes, copy them with a short-lived container, for example:

```bash
docker run --rm -v management_grafana-data:/from -v "$HOME:/backup" alpine \
  tar -C /from -czf /backup/grafana-$(date +%F).tar.gz .
```

The volume name is `<compose-project>_<volume>`. The project name is the directory (`management`, `data`).

Logs: `docker logs nginx`, `docker logs airflow-scheduler`, and files in `/var/lib/selfhost/nginx/logs/`.

## Checklist

- Cloudflare proxy is on for `@` and `*`, SSL mode is Full (strict), minimum TLS is 1.2, Bot Fight Mode is on.
- The GitHub secrets in section 2 are set. `.env` and `cloudflare.ini` exist only on the server, mode 600, and are not committed.
- `FERNET_KEY` and `HOMARR_SECRET_ENCRYPTION_KEY` are new values stored in a password manager.
- UFW allows SSH, and 80/443 only from Cloudflare.
- `fail2ban-client status sshd` shows the jail running. Your home IP is in `ignoreip`.
- A second SSH session works with a key after `--with-ssh-hardening`.
- Portainer, Grafana, pgAdmin, Homarr, and Uptime Kuma have their own admin users, and Cloudflare Access covers those hostnames.
- The renewal cron is installed.
- Postgres is not published on a host port. The Docker socket is mounted on Portainer only. Homarr and Uptime Kuma talk to the read-only socket proxy.
