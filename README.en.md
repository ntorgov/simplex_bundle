# 📡 simplex-selfhost

> One-command setup for a self-hosted [SimpleX Chat](https://simplex.chat) stack: SMP relay, XFTP file server, and TURN server for voice calls.

One script. A fully working private messenger on your own server.  
No registration. No phone numbers. No surveillance.

---

## ⚡ Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/ntorgov/simplex_bundle/refs/heads/master/installer.sh | bash
```

The script will ask a few questions (server address, ports, storage quota) and bring everything up automatically.

---

## 🧩 What Gets Installed

| Service | Image | Purpose | Default Port |
|---------|-------|---------|--------------|
| **SMP Server** | `simplexchat/smp-server` | Message relay | `993` (IMAPS) |
| **XFTP Server** | `simplexchat/xftp-server` | File & media transfer | `995` (POP3S) |
| **coturn** | `coturn/coturn` | STUN/TURN for voice calls | `3478` |

Ports 993 and 995 are intentionally chosen — they belong to the email protocol range (IMAPS/POP3S) and are almost never blocked by ISPs, unlike SimpleX's default port `5223`.

---

## 📋 Requirements

- Linux server (Ubuntu 20.04+ recommended)
- Docker (`>= 20.x`)
- `docker-compose` or the `docker compose` plugin
- `openssl` (usually pre-installed)
- A public IP address or domain name

---

## 🔧 What the Script Does

1. **Checks dependencies** — docker, docker-compose, openssl
2. **Interactively asks** for parameters: server address, ports, storage quota
3. **Generates** a random password for the TURN server
4. **Creates** `~/simplex/docker-compose.yml` and `~/simplex/credentials.txt`
5. **Pulls images** and starts the containers
6. **Prints ready-to-use strings** to paste into the SimpleX Chat app

---

## 🛡️ Firewall

After installation, open the required ports:

```bash
ufw allow 993/tcp    # SMP relay
ufw allow 995/tcp    # XFTP files
ufw allow 3478/tcp   # TURN (voice)
ufw allow 3478/udp   # TURN (voice)
ufw allow 49152:65535/udp  # TURN media range
```

---

## 📱 Configuring the App

After a successful install, the script prints the ready-made addresses. Add them to **SimpleX Chat**:

### SMP and XFTP Servers

**Settings → Network & Servers → SMP Servers** (same for XFTP):

```
smp://<fingerprint>@your-server.com:993
xftp://<fingerprint>@your-server.com:995
```

> Get the exact addresses with fingerprint from the logs:
> ```bash
> docker logs simplex-smp 2>&1 | grep "Server address"
> docker logs simplex-xftp 2>&1 | grep "Server address"
> ```

### TURN for Voice Calls

**Settings → Privacy & Security → WebRTC ICE Servers** → disable defaults → add:

```
turn:simplex:YOUR_PASSWORD@your-server.com:3478?transport=udp
turn:simplex:YOUR_PASSWORD@your-server.com:3478?transport=tcp
stun:your-server.com:3478
```

The password is stored in `~/simplex/credentials.txt`.

---

## 🔄 Management

```bash
cd ~/simplex

# Status
docker compose ps

# Logs for all services
docker compose logs -f

# Logs for a specific service
docker compose logs -f smp-server

# Stop
docker compose down

# Update images
docker compose pull && docker compose up -d
```

---

## 🗂️ File Structure

```
~/simplex/
├── docker-compose.yml       # service configuration
├── credentials.txt          # passwords and addresses (chmod 600)
├── smp/
│   ├── config/              # SMP server keys and config
│   └── logs/                # SMP logs and data
├── xftp/
│   ├── config/              # XFTP server keys and config
│   ├── logs/                # XFTP logs
│   └── files/               # file storage
```

> ⚠️ **Back up** `smp/config/ca.key` — this is the CA key for your SMP server. If lost, clients will no longer trust the server and will need to be reconfigured.

---

## 🔒 Security

- The TURN password is randomly generated on each install (`openssl rand`)
- `credentials.txt` is created with `600` permissions (owner only)
- SMP and XFTP servers use their own TLS certificates (auto-generated on first run)
- Message and file contents are never accessible to the server — end-to-end encryption happens on the client side

---

## ❓ FAQ

**Does this work in countries with heavy censorship?**  
Yes. Ports 993 and 995 belong to the email protocol range (IMAPS/POP3S) and are almost never blocked. Port 5223 (SimpleX default) often gets blocked — which is why we don't use it.

**Do I need a domain, or is an IP address enough?**  
An IP address is fine. Just enter your server's IP when the installer asks.

**What about push notifications?**  
SimpleX push notifications are routed through simplex.im servers. If those are unreachable, switch the app's background mode to **"Periodically"** — the app will poll your SMP server directly without contacting any third-party servers.

**How do I find the fingerprint of my SMP server?**
```bash
docker logs simplex-smp 2>&1 | grep "Server address"
```

---

## 📄 License

MIT — do whatever you want, attribution appreciated.

---

<p align="center">
  Made with ❤️ for those who value privacy
</p>
