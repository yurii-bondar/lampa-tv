# Lampa TV — Self-Hosted Media Stack

A Docker Compose stack for the [Lampa](https://lampa.mx) smart TV app. Provides torrent streaming, tracker search, and online content browsing — all self-hosted.

## What's included

| Service | Port | Purpose |
|---|---|---|
| **TorrServer** | `8090` | Torrent stream server |
| **Jackett** | `9117` | Torrent tracker aggregator |
| **FlareSolverr** | `8191` | CloudFlare bypass for Jackett |
| **Lampac** | `9118` | Online content backend for Lampa |

Other setups:
- [README-server.md](README-server.md) — deploy to a cloud server with a public IP (+ optional Portainer)
- [README-termux.md](README-termux.md) — run TorrServer + Jackett on an Android phone via Termux

---

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) + [Docker Compose](https://docs.docker.com/compose/install/) installed
- Local IP address of the machine running the stack (e.g. `192.168.1.100`)  
  Run `ipconfig getifaddr en0` (macOS) or `ip -4 addr show | grep inet` (Linux) to find it

---

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/yurii-bondar/lampa-tv.git lampa-tv
cd lampa-tv
```

### 2. Start all services

```bash
./start.sh
```

`start.sh` creates `lampac-config/init.conf` from the template if it doesn't exist yet.

Or manually:

```bash
cp -n lampac-config/init.conf.example lampac-config/init.conf
docker compose up -d
```

> **Note:** `lampac-config/init.conf` must exist before `docker compose up`. Otherwise Docker creates an empty *directory* with that name and Lampac fails to start. If that happened, run `docker compose down && rm -rf lampac-config/init.conf` and start again.

### 3. Verify services are running

```bash
docker compose ps
```

All four containers should show status `running`.

---

## Service Setup

### TorrServer

Open in browser: `http://localhost:8090`

No additional configuration needed — it works out of the box. TorrServer will be connected to Lampa via plugin (see below).

---

### Jackett

Open in browser: `http://localhost:9117`

> **Note:** The `jackett-config/` directory is not tracked in git. `docker-compose.yml` mounts it as `/config` in the container, so Jackett's configuration (indexers, credentials, API key) is stored on the host in `jackett-config/Jackett/` and survives `docker compose down` / `up` and image updates. To start from scratch, stop Jackett and delete this directory.

**Adding indexers manually:**

1. On the main page click **"Add indexer"**
2. Search for and add the trackers you want (e.g. `Rutracker`, `NNMClub`, `Kinozal`, etc.)
3. For trackers that require login — click the wrench icon next to the indexer and enter credentials
4. For trackers protected by CloudFlare — go to Jackett **Settings** (top-right gear icon), set **FlareSolverr API URL** to `http://flaresolverr:8191`, click **Apply server settings**
5. Copy the **API Key** from the top-right corner of the Jackett page — you'll need it for the parser settings in Lampa on the TV (see [Step 4](#step-4--connect-jackett-and-torrserver))

**Using your own custom API key (optional):**

By default Jackett auto-generates a random 32-character API key on first start. You can replace it with your own short key instead — Jackett only generates a new one if the `APIKey` field is empty, so it will keep whatever value you put there.

You need to set the **same key in two places**:

1. **Jackett** — `jackett-config/Jackett/ServerConfig.json`, field `APIKey`:
   ```json
   "APIKey": "yourCustomKey123"
   ```
   - Fresh setup: create this file (see path above) with your key *before* the first `docker compose up` — Jackett will pick it up immediately instead of generating one.
   - Already running: `docker compose stop jackett`, edit the `APIKey` field in the existing file, then `docker compose start jackett`.

2. **Lampa on the TV** — **Settings** → **Parser** → Jackett API key (see [Step 4](#step-4--connect-jackett-and-torrserver))

> **Note:** Avoid `#` and other URL-special characters in the key — the key is sent as a URL query parameter, and an unencoded `#` gets treated as a fragment and truncates everything after it, breaking authentication.

---

### Lampac

The Lampac config is located at `lampac-config/init.conf` (gitignored, so local changes stay local). `start.sh` copies it from the tracked template on first run, or you can do it manually:

```bash
cp lampac-config/init.conf.example lampac-config/init.conf
```

`init.conf.example` sets up the online sources: it disables unused modules (`BaseModule.SkipModules`) and enables the Ukrainian **Kinoukr** source, which is off by default. Other Ukrainian sources (Eneyida, UAKino, UAFilm) are on by default.

> **Note:** The `jackett` block in the config is only used by Lampac's `JacRed` module, which is disabled in `SkipModules`. Torrent search does **not** go through Lampac — Lampa on the TV queries Jackett directly (see [Step 4](#step-4--connect-jackett-and-torrserver)), so the API key in `init.conf` can stay a placeholder.

After editing the config, restart Lampac:

```bash
docker compose restart lampac
```

Verify Lampac is working: `http://localhost:9118/online.js` (should return JavaScript)

---

## Lampa App Setup (Smart TV)

### Install Lampa

- **Android TV / Google TV**: install from [Google Play](https://play.google.com/store/apps/details?id=site.lampa) or sideload the APK from [lampa.mx](https://lampa.mx)
- **Samsung Tizen / LG webOS**: use the browser-based version or sideload

---

### Step 1 — Add Lampac plugin (online content + parser)

This plugin adds online streaming sources and a torrent parser to Lampa.

1. Open the Lampa app on your TV
2. Go to **Settings** → **Plugins** (or **Extensions**)
3. Click **"Add plugin"**
4. Enter the following URL:

   ```
   http://cub.red/plugin/etor
   ```

5. Save and reload the app

> This plugin enables both the **online content** tab (movies/series from Lampac) and the **torrent parser** (search via Jackett).

---

### Step 2 — Configure Lampac server URL

After the plugin is installed:

1. In Lampa go to **Settings** → **Plugins** → find **Lampac / Etor** settings
2. Set the server URL to your machine's local IP:

   ```
   http://YOUR_LOCAL_IP:9118
   ```

   Example: `http://192.168.1.100:9118`

3. Save

---

### Step 3 — Add online sources

1. In Lampa go to **Settings** → **Plugins**
2. Click **"Add plugin"**
3. Enter:

   ```
   http://YOUR_LOCAL_IP:9118/online.js
   ```

   Example: `http://192.168.1.100:9118/online.js`

4. Save and reload the app

> This registers your Lampac instance as the online content provider directly in Lampa.

---

### Step 4 — Connect Jackett and TorrServer

Torrent search goes from Lampa straight to Jackett, and playback goes through TorrServer.

1. **Settings** → **Parser**: enable the parser, choose **Jackett**, set
   - URL: `http://YOUR_LOCAL_IP:9117/` (trailing slash required)
   - API key: the key copied from Jackett
2. **Settings** → **TorrServer**: set URL to `http://YOUR_LOCAL_IP:8090`
3. Open any movie or series → **"Torrents"** — results come from Jackett and play through TorrServer

---

## Updating

```bash
docker compose pull
docker compose up -d
```

---

## Troubleshooting

**Services won't start**
```bash
docker compose logs
```

**Jackett can't reach CloudFlare-protected trackers**
- Make sure FlareSolverr is running: `docker compose ps flaresolverr`
- In Jackett **Settings** verify FlareSolverr API URL is set to `http://flaresolverr:8191` and click **Apply server settings**

**Lampa can't connect to Lampac**
- Make sure you're using the machine's LAN IP, not `localhost` (TV is on a different device)
- Check firewall — ports `9118`, `8090`, `9117` must be accessible on the local network

**No results in torrent search**
- Open Jackett at `http://localhost:9117` and test indexers manually
- Verify the API key in Lampa's **Parser** settings matches Jackett's API key

---

## Ports summary

| Port | Service | URL |
|---|---|---|
| `8090` | TorrServer | `http://YOUR_IP:8090` |
| `9117` | Jackett | `http://YOUR_IP:9117` |
| `9118` | Lampac | `http://YOUR_IP:9118` |
| `8191` | FlareSolverr | internal Docker network only |
