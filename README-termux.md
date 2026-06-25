# Lampa TV — Termux Installation (Android)

A guide for running TorrServer + Jackett directly on an Android phone via Termux — no Docker, no root required.

> Successfully tested on **Samsung Galaxy S25+**.

---

## Overview

| Service | Port | Runs in |
|---|---|---|
| **TorrServer** | `8090` | Termux (native ARM64 binary) |
| **Jackett** | `9117` | Termux → proot Ubuntu |

Since Jackett requires a .NET runtime that doesn't run natively in Termux, it runs inside a lightweight Ubuntu environment via `proot-distro`.

---

## Part 0 — Termux storage access

Termux needs permission to access the Android filesystem. If you haven't granted it yet, run this once right after installing Termux:

```bash
termux-setup-storage
```

A system dialog will appear — tap **Allow**. This creates a `~/storage` symlink that maps to your phone's internal storage folders (`Downloads`, `DCIM`, etc.).

> Without this step, Termux can still run everything in its own sandbox (`$HOME` = `/data/data/com.termux/files/home`), so for this guide it is not strictly required — but it's good practice to do it upfront.

---

## Part 1 — TorrServer in Termux

Run these commands in a plain Termux session (**not** inside Ubuntu).

### 1. Create a directory and navigate into it

Use the explicit path instead of `~` to avoid ambiguity between Termux sessions and proot environments:

```bash
mkdir -p $HOME/torrserver && cd $HOME/torrserver
```

### 2. Download the latest TorrServer release for ARM64

```bash
wget https://github.com/YouROK/TorrServer/releases/latest/download/TorrServer-android-arm64
```

### 3. Rename the binary

```bash
mv TorrServer-android-arm64 torrserver
```

### 4. Make it executable

```bash
chmod +x torrserver
```

### 5. Test run

```bash
./torrserver -p 8090
```

If you see `Server start on port 8090` in the logs — it's working. Press **`Ctrl + C`** to stop it for now.

---

## Part 2 — Ubuntu environment for Jackett

Jackett needs a .NET runtime. We use `proot-distro` to run a minimal Ubuntu inside Termux.

### 1. Update Termux packages and install proot-distro

```bash
pkg update && pkg upgrade -y
pkg install proot-distro -y
proot-distro install ubuntu
```

### 2. Enter Ubuntu

```bash
proot-distro login ubuntu
```

The prompt changes to `root@localhost:~#`.

### 3. Update Ubuntu and install dependencies

```bash
apt update && apt install wget tar libicu-dev openssl -y
```

### 4. Download and extract Jackett for ARM64

```bash
wget https://github.com/Jackett/Jackett/releases/latest/download/Jackett.Binaries.LinuxARM64.tar.gz
tar -xvf Jackett.Binaries.LinuxARM64.tar.gz
cd Jackett
```

---

## Part 3 — Running both services (two Termux tabs)

### Tab 1 — Jackett

You should already be inside Ubuntu in the `Jackett` directory. Start Jackett with the required .NET memory flags:

```bash
export DOTNET_GCName=libclrgc.so && export COMPlus_GCName=libclrgc.so && ./jackett -x
```

### Tab 2 — TorrServer

Swipe from the left edge of the screen → tap **NEW SESSION**, then:

```bash
cd $HOME/torrserver && ./torrserver -p 8090
```

---

## Part 4 — Configure Lampa on your TV

### 1. Add indexers in Jackett

Open `http://localhost:9117` in your phone's browser, add trackers (e.g. *Rutor*, *Rutracker*), and copy the **API Key** from the top-right corner.

### 2. Find your phone's local IP

In a new Termux tab:

```bash
ip addr show wlan0
```

Look for the number after `inet`, e.g. `192.168.0.5`.

### 3. Configure Lampa on the TV

In the Lampa app on your TV, enable the torrent plugin (`https://lampa.mx/plugins/torrent.js`) and fill in:

| Field | Value |
|---|---|
| **TorrServer** | `http://PHONE_IP:8090` |
| **Parser URL** | `http://PHONE_IP:9117/` (trailing slash required) |
| **Jackett API Key** | paste the key copied from Jackett |

---

## Quick-start checklist (after phone reboot)

Open two Termux tabs and run:

**Tab 1 — Jackett:**
```bash
proot-distro login ubuntu
cd Jackett
export DOTNET_GCName=libclrgc.so && export COMPlus_GCName=libclrgc.so && ./jackett -x
```

**Tab 2 — TorrServer:**
```bash
cd $HOME/torrserver && ./torrserver -p 8090
```
