# Lampa TV — Deploying to a Cloud Server

A guide for running the stack on any VPS / cloud server with a public IP and Docker, so the TV can use it from anywhere.

> Tested on Ubuntu (ARM64) in Oracle Cloud.

All images used by the stack are available for both `amd64` and `arm64`.

---

## Overview

| Service | Port | Public | Protection |
|---|---|---|---|
| **TorrServer** | `8090` | yes | login/password (`TS_HTTPAUTH`) |
| **Jackett** | `9117` | yes | API key for search, admin password for the UI |
| **Lampac** | `9118` | yes | none |
| **FlareSolverr** | `8191` | no | internal Docker network only |
| **Portainer** (optional) | `9443` | no | localhost only, via SSH tunnel |

Server-specific settings live in `docker-compose.override.yml`, which Docker Compose loads automatically on top of `docker-compose.yml`. The base compose file stays the same for local use.

> **Note:** Ports published by Docker bypass the host's `ufw` / iptables `INPUT` rules. On a cloud server the cloud firewall (security list / security group) is what actually controls access — see [Step 6](#6-open-ports-in-the-cloud-firewall).

---

## 1. Prepare the server

Install Docker Engine with the Compose plugin: https://docs.docker.com/engine/install/ubuntu/

Create the stack directory:

```bash
sudo mkdir -p /opt/lampa-tv && sudo chown $USER:$USER /opt/lampa-tv
```

---

## 2. Copy files from your machine

Run from the repository root on your local machine. `rsync` is often missing on fresh images, so use `tar` over SSH. `COPYFILE_DISABLE=1` stops macOS from adding `._*` metadata files.

```bash
COPYFILE_DISABLE=1 tar czf - docker-compose.yml docker-compose.override.yml.example start.sh lampac-config \
  | ssh -i ~/path/to/key user@SERVER_IP 'tar xzf - -C /opt/lampa-tv'
```

**Reusing your local Jackett indexers (optional):** add `jackett-config` to the `tar` command above. The directory includes `DataProtection/` keys, so saved tracker credentials keep working on the server.

Lampac config holds the Jackett API key — keep it private on the server:

```bash
chmod 600 /opt/lampa-tv/lampac-config/init.conf
```

---

## 3. Server overrides and TorrServer credentials

On the server:

```bash
cd /opt/lampa-tv
cp docker-compose.override.yml.example docker-compose.override.yml
```

Set `PUID` / `PGID` in `docker-compose.override.yml` to the output of `id -u` / `id -g`.

Create TorrServer credentials (user `lampa`, random 8-char password):

```bash
mkdir -p torrserver-config
P=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | cut -c1-8)
printf '{"lampa":"%s"}\n' "$P" > torrserver-config/accs.db
chmod 600 torrserver-config/accs.db
echo "TorrServer password: $P"
```

To change the password later, edit `torrserver-config/accs.db` and run `sudo docker compose restart torrserver`.

---

## 4. Start the stack

```bash
cd /opt/lampa-tv
sudo ./start.sh
```

`start.sh` creates `lampac-config/init.conf` from the template if it's missing and warns if the Jackett API key is not set.

Check from the server:

```bash
sudo docker compose ps
curl -s localhost:8090/echo                                          # TorrServer version
curl -s -o /dev/null -w '%{http_code}\n' localhost:8090/torrents      # 401 = auth enabled
curl -s -o /dev/null -w '%{http_code}\n' localhost:9118/online.js     # 200
```

---

## 5. Protect Jackett before opening it

Jackett's admin UI has no password by default — anyone reaching port `9117` would see your tracker settings. Set a password **before** opening the port in the cloud firewall, either in the UI (**Admin password** field → **Set Password**) or from the server:

```bash
cd /opt/lampa-tv
P=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | cut -c1-20)
J=$(mktemp)
curl -s -L -o /dev/null -c $J -b $J localhost:9117/UI/Dashboard   # get a session cookie
curl -s -o /dev/null -w '%{http_code}\n' -c $J -b $J -X POST \
  -H 'Content-Type: application/json' --data "\"$P\"" \
  localhost:9117/api/v2.0/server/adminpassword                    # 204 = done
rm -f $J
echo "Jackett admin password: $P"
```

> **Tip:** The API key is the only thing protecting the search API, and the TV sends it over plain HTTP. Use a long random key (Jackett UI → reset API key) and update it in `lampac-config/init.conf` and on the TV.

---

## 6. Open ports in the cloud firewall

Allow inbound TCP `8090`, `9117`, `9118` from `0.0.0.0/0`. Do **not** open `8191` or `9443`.

Where to do it depends on the provider:

| Provider | Where |
|---|---|
| AWS (EC2 / Lightsail) | Security Group of the instance / Lightsail **Networking** tab |
| Google Cloud | VPC network → **Firewall** rules |
| Azure | Network Security Group of the VM |
| DigitalOcean, Hetzner | Cloud Firewall, if one is attached (otherwise ports are open by default) |
| Oracle Cloud | VCN Security List or NSG — see below |

If the provider has no cloud firewall and you use `ufw`, remember that it does **not** filter Docker-published ports.

### Example: Oracle Cloud (console)

Networking → Virtual Cloud Networks → your VCN → Security Lists (or the instance's NSG) → **Add Ingress Rules** → Source `0.0.0.0/0`, IP Protocol TCP, Destination port `8090` (repeat for `9117`, `9118`).

### Example: Oracle Cloud (CLI)

```bash
brew install oci-cli                                   # or see Oracle docs for Linux
oci session authenticate --region <REGION>             # browser login, profile DEFAULT
```

> **Warning:** `security-list update` **replaces** the whole rule list. The commands below take the current rules, append the new ones and keep a backup. Check the counts before applying.

```bash
o() { oci --auth security_token "$@"; }
INST=<INSTANCE_OCID>   # on the server: curl -s -H "Authorization: Bearer Oracle" http://169.254.169.254/opc/v2/instance/ | jq -r .id

SUBNET=$(o compute instance list-vnics --instance-id $INST --query 'data[0]."subnet-id"' --raw-output)
SL=$(o network subnet get --subnet-id $SUBNET --query 'data."security-list-ids"[0]' --raw-output)
o network security-list get --security-list-id $SL > sl-backup.json

rule() { printf '{"protocol":"6","source":"0.0.0.0/0","sourceType":"CIDR_BLOCK","isStateless":false,"description":"lampa-tv %s","tcpOptions":{"destinationPortRange":{"min":%s,"max":%s}}}' $2 $1 $1; }
jq --argjson new "[$(rule 8090 TorrServer),$(rule 9117 Jackett),$(rule 9118 Lampac)]" \
  '.data."ingress-security-rules"
   | walk(if type=="object" then with_entries(select(.value!=null) | .key|=gsub("-(?<c>[a-z])";.c|ascii_upcase)) else . end)
   + $new' sl-backup.json > ingress-new.json

echo "before: $(jq '.data."ingress-security-rules"|length' sl-backup.json)  after: $(jq length ingress-new.json)"

o network security-list update --security-list-id $SL \
  --ingress-security-rules file://ingress-new.json --force \
  --query 'length(data."ingress-security-rules")'
```

To roll back, convert `sl-backup.json` the same way (without `+ $new`) and run the `update` again.

Check from your machine:

```bash
curl -s http://SERVER_IP:8090/echo                                     # TorrServer version
curl -s -o /dev/null -w '%{http_code}\n' http://SERVER_IP:9118/online.js  # 200
curl -s -o /dev/null -w '%{http_code}\n' http://SERVER_IP:9117/UI/Dashboard  # 302 to login
```

---

## 7. Configure Lampa on the TV

Same as in [README.md](README.md#lampa-app-setup-smart-tv), using the server IP:

| Field | Value |
|---|---|
| Lampac server / plugin | `http://SERVER_IP:9118`, `http://SERVER_IP:9118/online.js` |
| TorrServer | `http://SERVER_IP:8090`, login `lampa` + password from step 3 |
| Parser (Jackett) | `http://SERVER_IP:9117/` + Jackett API key |

---

## 8. Portainer (optional)

A web UI for managing containers, images, volumes and networks on the server. It has full control over Docker (effectively root on the host), so it listens on localhost only.

Copy `portainer/docker-compose.yml` to the server, then:

```bash
sudo mkdir -p /opt/portainer && sudo chown $USER:$USER /opt/portainer
# copy portainer/docker-compose.yml to /opt/portainer/
cd /opt/portainer
(umask 077; openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | cut -c1-16 > admin-password.txt)
cat admin-password.txt
sudo docker compose up -d
```

The admin password is set on first start, so there is no open "create admin" window. Changing it later in the UI is fine — the file is only read once.

Open it through an SSH tunnel from your machine:

```bash
ssh -i ~/path/to/key -N -L 9443:127.0.0.1:9443 user@SERVER_IP
```

Then go to `https://localhost:9443` (accept the self-signed certificate), user `admin`.

---

## Updating

```bash
cd /opt/lampa-tv && sudo docker compose pull && sudo docker compose up -d
cd /opt/portainer && sudo docker compose pull && sudo docker compose up -d
```

---

## Troubleshooting

**Ports open in the cloud firewall but still unreachable**
- Make sure the container publishes `0.0.0.0:<port>`: `sudo docker compose ps`
- Some cloud images (e.g. Oracle Cloud Ubuntu) also have a `REJECT` rule in iptables `FORWARD`; Docker's own chains come first, so published ports normally work — check with `sudo iptables -S FORWARD`

**A tracker asks to log in again after moving to the server**
- Update the credentials in Jackett (wrench icon → login/password → **Okay** → **Test**)
- Some trackers block datacenter IPs — check `sudo docker compose logs jackett`

**Lampac doesn't start, `init.conf` is a directory**
- Docker created it because the file was missing: `sudo docker compose down && rm -rf lampac-config/init.conf`, then `sudo ./start.sh`
