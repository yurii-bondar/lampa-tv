# Lampa TV — Self-Hosted Media Stack

A Docker Compose stack for the [Lampa](https://lampa.mx) smart TV app. Provides torrent streaming, tracker search, and online content browsing — all self-hosted.

## What's included

| Service | Port | Purpose |
|---|---|---|
| **TorrServer** | `8090` | Torrent stream server |
| **Jackett** | `9117` | Torrent tracker aggregator |
| **FlareSolverr** | `8191` | CloudFlare bypass for Jackett |
| **Lampac** | `9118` | Online content backend for Lampa |

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

Or manually:

```bash
docker compose up -d
```

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

> **Note:** The `jackett-config/` directory is not tracked in git. On first run Jackett stores its configuration (indexers, credentials, API key) inside the Docker container. You can add indexers manually via the UI each time, or export them to a local directory once and reuse (see below).

**Adding indexers manually:**

1. On the main page click **"Add indexer"**
2. Search for and add the trackers you want (e.g. `Rutracker`, `NNMClub`, `Kinozal`, etc.)
3. For trackers that require login — click the wrench icon next to the indexer and enter credentials
4. For trackers protected by CloudFlare — go to Jackett **Settings** (top-right gear icon), set **FlareSolverr API URL** to `http://flaresolverr:8191`, click **Apply server settings**
5. Copy the **API Key** from the top-right corner of the Jackett page — you'll need it for Lampac

**Persisting Jackett config locally (optional):**

After you've set up your indexers, copy the config out of the container so you don't have to redo it after `docker compose down`:

```bash
docker cp jackett:/config/. ./jackett-config/Jackett/
```

The `docker-compose.yml` already mounts `./jackett-config` as `/config` in the container, so on the next `docker compose up` your indexers and API key will be restored automatically.

---

### Lampac

The Lampac config is located at `lampac-config/init.conf`.

To connect Jackett to Lampac, add the following block to `init.conf`:

> **Note:** Do not commit `init.conf` after adding your API key — it contains a personal secret.

```json
{
  "jackett": {
    "url": "http://jackett:9117",
    "apikey": "YOUR_JACKETT_API_KEY"
  }
}
```

Replace `YOUR_JACKETT_API_KEY` with the key copied from Jackett.

After editing the config, restart Lampac:

```bash
docker compose restart lampac
```

Verify Lampac is working: `http://localhost:9118/api/v1/info`

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

### Step 4 — Connect TorrServer

TorrServer is automatically available once the `etor` plugin is active and Lampac is configured. To verify:

1. In Lampa open any movie or series
2. Click **"Watch"** or **"Torrent"**
3. Lampa will search via Jackett → Lampac → stream through TorrServer

If TorrServer needs to be set manually:
1. Go to **Settings** → **TorrServer**
2. Set URL to `http://YOUR_LOCAL_IP:8090`

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
- Verify the API key in `lampac-config/init.conf` matches Jackett's API key

---

## Ports summary

| Port | Service | URL |
|---|---|---|
| `8090` | TorrServer | `http://YOUR_IP:8090` |
| `9117` | Jackett | `http://YOUR_IP:9117` |
| `9118` | Lampac | `http://YOUR_IP:9118` |
| `8191` | FlareSolverr | internal Docker network only |
