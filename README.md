# 🔍 Generic Tunnel Monitor

A production-ready, generic monitoring solution for tunnel services (Newt, ngrok, Cloudflare Tunnel, etc.) with automatic container restart capabilities.

[![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white)](https://hub.docker.com/r/yourusername/tunnel-monitor)
[![GitHub](https://img.shields.io/badge/github-%23121011.svg?style=for-the-badge&logo=github&logoColor=white)](https://github.com/yourusername/tunnel-monitor)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)

## ✨ Features

- 🎯 **Generic & Reusable** - Works with any tunnel service (Newt, ngrok, Cloudflare, etc.)
- 🔄 **Automatic Restart** - Detects failures and restarts containers automatically
- 🛡️ **Smart Protection** - Prevents restart loops with configurable limits
- 📊 **Configurable Health Checks** - Customize HTTP codes, retry logic, timeouts
- 🔔 **Webhook Notifications** - Send alerts to Slack, Discord, or custom webhooks
- 📝 **Rich Logging** - Color-coded logs with multiple log levels (ERROR, WARN, INFO, DEBUG)
- 🔒 **Secure** - Runs as non-root user, minimal Alpine base image
- 🐳 **Docker Native** - Easy deployment with Docker and Docker Compose

## 🚀 Quick Start

### Using Docker

```bash
docker run -d \
  --name tunnel-monitor \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e MONITOR_URL=https://your-tunnel-url.com \
  -e CONTAINER_NAME=your-tunnel-container \
  ghcr.io/yourusername/tunnel-monitor:latest
```

### Using Docker Compose

```yaml
services:
  tunnel-monitor:
    image: ghcr.io/yourusername/tunnel-monitor:latest
    container_name: tunnel-monitor
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - MONITOR_URL=https://your-tunnel-url.com
      - CONTAINER_NAME=your-tunnel-container
      - CHECK_INTERVAL=30
```

## 📋 Configuration

### Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `MONITOR_URL` | URL to monitor for health checks | `https://tunnel.example.com` |
| `CONTAINER_NAME` | Name of the container to restart | `appwrite-newt` |

### Optional Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CHECK_INTERVAL` | `30` | Seconds between health checks (minimum: 5) |
| `SUCCESS_CODES` | `200,301,302` | Comma-separated HTTP status codes considered healthy |
| `RESTART_DELAY` | `60` | Seconds to wait after restarting container |
| `CONNECTION_TIMEOUT` | `5` | Connection timeout in seconds |
| `MAX_TIMEOUT` | `10` | Maximum request timeout in seconds |
| `RETRY_COUNT` | `3` | Number of failed checks before restart |
| `MAX_RESTARTS_PER_HOUR` | `5` | Maximum restarts allowed per hour (prevents loops) |
| `NOTIFY_WEBHOOK` | - | Webhook URL for notifications (optional) |
| `LOG_LEVEL` | `INFO` | Log level: `ERROR`, `WARN`, `INFO`, `DEBUG` |

## 📚 Usage Examples

### Example 1: Monitoring Newt Tunnel

```yaml
services:
  newt:
    image: fosrl/newt
    container_name: appwrite-newt
    restart: unless-stopped
    environment:
      - PANGOLIN_ENDPOINT=https://appsto.me
      - NEWT_ID=your-newt-id
      - NEWT_SECRET=${NEWT_SECRET}

  newt-monitor:
    image: ghcr.io/yourusername/tunnel-monitor:latest
    container_name: newt-monitor
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - MONITOR_URL=https://your-app.this-thingy.xyz
      - CONTAINER_NAME=appwrite-newt
      - CHECK_INTERVAL=30
      - RETRY_COUNT=3
      - LOG_LEVEL=INFO
```

### Example 2: Monitoring ngrok Tunnel

```yaml
services:
  ngrok:
    image: ngrok/ngrok:latest
    container_name: my-ngrok
    restart: unless-stopped
    command: http host.docker.internal:3000
    environment:
      - NGROK_AUTHTOKEN=${NGROK_AUTHTOKEN}

  ngrok-monitor:
    image: ghcr.io/yourusername/tunnel-monitor:latest
    container_name: ngrok-monitor
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - MONITOR_URL=https://your-ngrok-url.ngrok.io
      - CONTAINER_NAME=my-ngrok
      - CHECK_INTERVAL=20
      - SUCCESS_CODES=200,404  # ngrok may return 404 for root
```

### Example 3: Monitoring Cloudflare Tunnel

```yaml
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflare-tunnel
    restart: unless-stopped
    command: tunnel run
    environment:
      - TUNNEL_TOKEN=${TUNNEL_TOKEN}

  cloudflare-monitor:
    image: ghcr.io/yourusername/tunnel-monitor:latest
    container_name: cloudflare-monitor
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - MONITOR_URL=https://your-app.yourdomain.com
      - CONTAINER_NAME=cloudflare-tunnel
      - CHECK_INTERVAL=45
      - RETRY_COUNT=5
```

### Example 4: With Webhook Notifications

```yaml
services:
  tunnel-monitor:
    image: ghcr.io/yourusername/tunnel-monitor:latest
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - MONITOR_URL=https://tunnel.example.com
      - CONTAINER_NAME=my-tunnel
      - NOTIFY_WEBHOOK=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
      - LOG_LEVEL=DEBUG
```

## 🔔 Webhook Notifications

When configured, the monitor sends JSON payloads to your webhook URL:

```json
{
  "status": "unhealthy",
  "message": "Service is down, attempting restart",
  "container": "appwrite-newt",
  "url": "https://tunnel.example.com",
  "timestamp": "2025-12-26T09:30:00Z",
  "hostname": "docker-host"
}
```

**Status values:** `unhealthy`, `recovered`, `critical`, `stopped`

### Slack Webhook Example

Create a webhook at https://api.slack.com/messaging/webhooks and use:

```bash
NOTIFY_WEBHOOK=https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX
```

## 🔧 Building from Source

```bash
# Clone the repository
git clone https://github.com/yourusername/tunnel-monitor.git
cd tunnel-monitor

# Build the image
docker build -t tunnel-monitor:local .

# Run locally
docker run -d \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e MONITOR_URL=https://example.com \
  -e CONTAINER_NAME=test-container \
  tunnel-monitor:local
```

## 📦 Versioning

This project uses **Semantic Versioning 2.0.0**:

- **MAJOR** version for incompatible API changes
- **MINOR** version for backwards-compatible features
- **PATCH** version for backwards-compatible bug fixes

### Docker Tags

```bash
# Specific version (recommended for production)
ghcr.io/yourusername/tunnel-monitor:1.0.0

# Major version (auto-updated with new minors/patches)
ghcr.io/yourusername/tunnel-monitor:1

# Minor version (auto-updated with new patches)
ghcr.io/yourusername/tunnel-monitor:1.0

# Latest stable (always latest release)
ghcr.io/yourusername/tunnel-monitor:latest

# Development (latest commit on main)
ghcr.io/yourusername/tunnel-monitor:edge
```

**Production Recommendation:** Pin to a specific version (e.g., `1.0.0`) and upgrade deliberately.

## 🛠️ Troubleshooting

### Monitor keeps restarting containers

- Increase `RETRY_COUNT` to reduce false positives
- Check if `SUCCESS_CODES` includes all valid response codes
- Verify the monitored URL is correct and accessible
- Review logs with `LOG_LEVEL=DEBUG`

### Container not found error

```bash
# Verify container name matches exactly
docker ps --format '{{.Names}}' | grep your-container-name
```

### Permission denied on Docker socket

Ensure the Docker socket is properly mounted:
```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock
```

### Check monitor logs

```bash
docker logs tunnel-monitor
docker logs -f tunnel-monitor  # Follow logs
```

## 🔒 Security Considerations

- **Runs as non-root user** (UID 1000) for enhanced security
- **Minimal Alpine base** reduces attack surface
- **Docker socket access** - Monitor has full Docker control (required for restart functionality)
- **No network exposure** - Monitor doesn't expose any ports
- **Webhook secrets** - Use environment files to protect sensitive URLs

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links

- **Docker Hub:** https://hub.docker.com/r/yourusername/tunnel-monitor
- **GitHub Container Registry:** https://ghcr.io/yourusername/tunnel-monitor
- **Issue Tracker:** https://github.com/yourusername/tunnel-monitor/issues
- **Documentation:** https://github.com/yourusername/tunnel-monitor/wiki

## 📊 Architecture

For detailed information about design decisions and internal architecture, see [ARCHITECTURE.md](ARCHITECTURE.md).

## 🚚 Migration Guide

Moving this to a separate repository? See [MIGRATION-GUIDE.md](MIGRATION-GUIDE.md) for step-by-step instructions.

---

**Made with ❤️ for the tunnel monitoring community**
