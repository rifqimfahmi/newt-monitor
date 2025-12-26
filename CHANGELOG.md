# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

---

## [1.0.2] - 2025-12-26

### Summary
change default MAX_RESTARTS_PER_HOUR=unlimited


---

## [1.0.1] - 2025-12-26

### Summary
use default root


### Planned
- Custom health check commands
- Prometheus metrics endpoint
- Support for multiple containers
- TCP/UDP health checks
- Exponential backoff retry strategy

---

## [1.0.0] - 2025-12-26

### Added
- Initial release of Generic Tunnel Monitor
- HTTP/HTTPS health checking with configurable status codes
- Automatic container restart on failure detection
- Smart restart loop prevention (max restarts per hour)
- Retry logic with configurable retry count
- Rich colored logging with multiple log levels (ERROR, WARN, INFO, DEBUG)
- Webhook notifications for status changes (Slack, Discord, etc.)
- Configuration validation on startup
- Graceful shutdown handling (SIGTERM, SIGINT)
- Docker health check for the monitor itself
- Non-root user security (UID 1000)
- Minimal Alpine-based Docker image (~15MB)
- Multi-architecture support (amd64, arm64)
- Comprehensive documentation:
  - README.md with quick start and examples
  - ARCHITECTURE.md with design decisions
  - MIGRATION-GUIDE.md for repository extraction
- Docker Compose examples for:
  - Newt tunnel
  - ngrok tunnel
  - Cloudflare Tunnel
- GitHub Actions workflow for automated Docker publishing
- MIT License

### Security
- Runs as non-root user (monitor:monitor, UID 1000)
- Minimal Alpine base image to reduce attack surface
- Input validation for all configuration parameters
- Documented security considerations for Docker socket access

---

## Version History

- **v1.0.0** - Initial public release (2025-12-26)

---

## Contributing

Please read [README.md](README.md#contributing) for details on our code of conduct and the process for submitting pull requests.

## Links

- [GitHub Repository](https://github.com/yourusername/tunnel-monitor)
- [Docker Hub](https://hub.docker.com/r/yourusername/tunnel-monitor)
- [GitHub Container Registry](https://ghcr.io/yourusername/tunnel-monitor)
- [Issue Tracker](https://github.com/yourusername/tunnel-monitor/issues)
