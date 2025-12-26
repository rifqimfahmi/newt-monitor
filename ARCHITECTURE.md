# 🏗️ Architecture & Design Decisions

This document explains the internal architecture, design decisions, and rationale behind the Generic Tunnel Monitor. It's intended for developers, maintainers, and AI assistants who need to understand the system deeply.

## Table of Contents

- [Overview](#overview)
- [Core Design Principles](#core-design-principles)
- [Architecture Diagram](#architecture-diagram)
- [Component Breakdown](#component-breakdown)
- [Design Decisions](#design-decisions)
- [State Management](#state-management)
- [Error Handling Strategy](#error-handling-strategy)
- [Security Considerations](#security-considerations)
- [Performance Considerations](#performance-considerations)
- [Extension Points](#extension-points)

---

## Overview

The Generic Tunnel Monitor is a lightweight, containerized solution for monitoring tunnel services (Newt, ngrok, Cloudflare Tunnel, etc.) and automatically restarting them when they become unhealthy. It follows the Unix philosophy: **do one thing and do it well**.

### Why This Architecture?

1. **Separation of Concerns**: Monitor and tunnel are separate containers
2. **Reusability**: Generic enough to work with any tunnel service
3. **Reliability**: Smart restart logic prevents loops and cascading failures
4. **Observability**: Rich logging and optional webhook notifications
5. **Security**: Runs as non-root, minimal attack surface

---

## Core Design Principles

### 1. Single Responsibility Principle (SRP)

**Decision**: Keep monitor and tunnel as separate containers.

**Rationale**:
- Each container does one thing well
- Easier to debug and maintain
- Allows independent scaling
- Follows Docker best practices (one process per container)
- Monitor can watch multiple containers if needed

**Alternative Considered**: Combined single-container image
- **Rejected** because it violates SRP and makes the system less flexible

### 2. Configuration Over Code

**Decision**: Use environment variables for all configuration.

**Rationale**:
- No code changes needed for different use cases
- 12-factor app methodology compliance
- Easy integration with orchestration tools (Docker Compose, Kubernetes)
- No configuration files to manage

### 3. Fail-Safe Defaults

**Decision**: Conservative defaults that prevent damage.

**Examples**:
- `MAX_RESTARTS_PER_HOUR=5` - Prevents restart storms
- `RETRY_COUNT=3` - Reduces false positives
- `CHECK_INTERVAL=30` - Balanced between responsiveness and load

### 4. Defensive Programming

**Decision**: Validate everything, assume nothing.

**Implementation**:
- Input validation on startup
- Graceful degradation (webhook failures don't crash monitor)
- Boundary checking on numeric values
- Container existence verification before restart

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                         Host System                          │
│                                                               │
│  ┌──────────────────┐         ┌──────────────────┐          │
│  │  Tunnel Service  │         │  Tunnel Monitor  │          │
│  │  (Newt/ngrok/CF) │         │                  │          │
│  │                  │         │  ┌────────────┐  │          │
│  │  Port: varies    │◄────────┤  │ Health     │  │          │
│  │                  │  HTTP   │  │ Checker    │  │          │
│  │                  │  Check  │  │            │  │          │
│  └──────────────────┘         │  └────────────┘  │          │
│           ▲                   │         │        │          │
│           │                   │         ▼        │          │
│           │                   │  ┌────────────┐  │          │
│           │                   │  │ Restart    │  │          │
│           └───────────────────┤  │ Logic      │  │          │
│         Docker API            │  │            │  │          │
│        (restart cmd)          │  └────────────┘  │          │
│                               │         │        │          │
│  ┌──────────────────┐         │         ▼        │          │
│  │ Docker Socket    │◄────────┤  ┌────────────┐  │          │
│  │ /var/run/        │         │  │ State      │  │          │
│  │ docker.sock      │         │  │ Manager    │  │          │
│  └──────────────────┘         │  └────────────┘  │          │
│                               │         │        │          │
│                               │         ▼        │          │
│                               │  ┌────────────┐  │          │
│  ┌──────────────────┐         │  │ Logging &  │  │          │
│  │ External Webhook │◄────────┤  │ Notify     │  │          │
│  │ (Slack/Discord)  │  HTTPS  │  └────────────┘  │          │
│  └──────────────────┘         └──────────────────┘          │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

---

## Component Breakdown

### 1. Health Checker (`check_health`)

**Purpose**: Determines if the monitored service is healthy.

**How it works**:
1. Makes HTTP request to `MONITOR_URL`
2. Checks if response code is in `SUCCESS_CODES`
3. Returns success (0) or failure (1)

**Key Features**:
- Configurable timeouts prevent hanging
- Supports multiple success codes (200, 301, 302, etc.)
- Uses curl for reliability and wide protocol support

**Why not use ping?**
- HTTP checks verify application-level health, not just network connectivity
- Tunnel services expose HTTP endpoints, making this more appropriate

### 2. Restart Controller

**Components**:
- `restart_container()` - Executes the restart
- `check_restart_limit()` - Prevents restart loops
- `record_restart()` - Tracks restart history

**How it works**:

```
Consecutive Failures >= RETRY_COUNT?
    ↓
Check restart history (last hour)
    ↓
Restarts < MAX_RESTARTS_PER_HOUR?
    ↓
Execute: docker restart <container>
    ↓
Record timestamp to /tmp/restart_history.log
    ↓
Sleep RESTART_DELAY seconds
```

**Restart Loop Prevention**:
- Tracks restart timestamps in `/tmp/restart_history.log`
- Counts restarts in rolling 1-hour window
- Refuses to restart if limit exceeded
- Pauses for 5 minutes when limit hit

**Why this approach?**
- Time-based limiting is more robust than count-based
- Rolling window adapts to sporadic issues vs. persistent problems
- Pause prevents CPU spinning while allowing recovery

### 3. State Manager

**State Files**:
- `/tmp/restart_history.log` - Restart timestamps (Unix epoch)

**Why `/tmp`?**
- Ephemeral storage is acceptable (resets on monitor restart)
- No persistence needed across monitor lifecycles
- Prevents disk fill issues

**State Cleanup**:
- Old entries (>1 hour) automatically pruned
- Prevents unbounded growth

### 4. Logging System

**Log Levels**:
```
ERROR → Critical issues, always shown
WARN  → Warnings, shown unless LOG_LEVEL=ERROR
INFO  → Normal operations, shown by default
DEBUG → Verbose details, opt-in
```

**Color Coding**:
- 🔴 RED - Errors
- 🟡 YELLOW - Warnings
- 🟢 GREEN - Info
- 🔵 BLUE - Debug

**Design Decision**: Color codes despite being containerized
- **Rationale**: Docker logs preserve ANSI codes, improving readability
- **Trade-off**: Slight complexity for significant UX improvement

### 5. Notification System

**Webhook Payload**:
```json
{
  "status": "unhealthy|recovered|critical|stopped",
  "message": "Human-readable description",
  "container": "Container name",
  "url": "Monitored URL",
  "timestamp": "ISO 8601 UTC",
  "hostname": "Docker host identifier"
}
```

**Design Decision**: JSON POST to generic webhook
- **Rationale**: Works with Slack, Discord, custom services
- **Alternative**: Built-in integrations (Slack SDK, etc.)
  - **Rejected**: Increases complexity and image size

**Failure Handling**: Webhook failures log warning but don't crash monitor
- **Rationale**: Monitoring is primary function, notifications are secondary

---

## Design Decisions

### Decision 1: Why Bash Instead of Python/Go?

**Choice**: Bash script

**Rationale**:
- ✅ Simpler deployment (no runtime dependencies beyond Alpine packages)
- ✅ Smaller image size (~15MB vs 50-200MB)
- ✅ Faster startup time
- ✅ Direct shell access to docker/curl commands
- ✅ Easy to read and modify

**Trade-offs**:
- ❌ Less structured than compiled languages
- ❌ No static type checking
- **Mitigation**: Extensive validation, clear function boundaries

### Decision 2: HTTP Checks Only (No TCP/ICMP)

**Choice**: HTTP/HTTPS only

**Rationale**:
- Tunnel services expose HTTP endpoints
- Application-level health is more meaningful
- curl is universally available

**Future Extension**: Could add custom health check commands via `CUSTOM_HEALTH_CHECK` env var

### Decision 3: Docker Socket Access

**Choice**: Require `/var/run/docker.sock` mount

**Security Implications**: Monitor has full Docker API access

**Rationale**:
- ✅ Only way to restart containers from inside a container
- ✅ Standard pattern for Docker management tools
- ✅ Document security implications clearly

**Mitigations**:
- Run as non-root user (UID 1000)
- Minimal Alpine base image
- No network exposure
- Clear documentation

### Decision 4: Non-Root User

**Choice**: Create and use `monitor:monitor` (UID/GID 1000)

**Rationale**:
- Principle of least privilege
- Reduces attack surface
- Industry best practice

**Note**: Docker socket access still requires host-level permissions

### Decision 5: Stateless Design

**Choice**: No persistent state across monitor restarts

**Rationale**:
- Simpler design
- Self-healing (fresh start on monitor restart)
- No state corruption issues

**Trade-off**: Restart counters reset when monitor restarts
- **Mitigation**: Monitor should rarely restart, and fresh state is safer

---

## State Management

### Restart History

**File**: `/tmp/restart_history.log`

**Format**:
```
1703580000
1703580100
1703580250
```
(Unix timestamps, one per line)

**Operations**:

1. **Record Restart**:
```bash
echo "$(date +%s)" >> /tmp/restart_history.log
```

2. **Count Recent**:
```bash
# Count entries >= (now - 3600)
awk -v cutoff="$hour_ago" '$1 >= cutoff' /tmp/restart_history.log | wc -l
```

3. **Cleanup Old**:
```bash
# Keep only entries from last hour
awk -v cutoff="$hour_ago" '$1 >= cutoff' input > output
```

**Why not a database?**
- Overkill for simple counters
- File operations are atomic enough for single process
- No external dependencies

---

## Error Handling Strategy

### Validation Phase (Startup)

**Fail Fast**: Exit immediately if configuration invalid

**Checked**:
- Required environment variables present
- Numeric values are valid numbers
- Required commands (curl, docker) available
- Numeric ranges (CHECK_INTERVAL >= 5, etc.)

### Runtime Phase

**Graceful Degradation**: Non-critical failures don't crash monitor

**Examples**:
- Webhook failure → Log warning, continue monitoring
- Container not found → Log error, continue checking
- Health check timeout → Count as failure, continue loop

**Critical Failures**: Exit with error
- Docker daemon unreachable
- Invalid configuration discovered at runtime

### Signal Handling

```bash
trap cleanup SIGTERM SIGINT
```

**Graceful Shutdown**:
1. Log shutdown message
2. Send "stopped" notification
3. Exit cleanly (code 0)

**Why**: Allows proper cleanup in orchestrated environments

---

## Security Considerations

### Attack Surface Analysis

**Exposed Interfaces**:
1. ✅ Docker socket (required, documented risk)
2. ✅ Network (outbound only - HTTP checks + webhooks)
3. ❌ No inbound network connections
4. ❌ No exposed ports

**Privilege Analysis**:
- Container runs as UID 1000 (non-root)
- Docker socket access grants container management
- No host filesystem access (except socket)

### Threat Model

**Threats**:
1. **Malicious webhook URL** → Could exfiltrate monitoring data
   - Mitigation: User controls webhook, no secrets in payload
2. **Docker socket escape** → Could control host
   - Mitigation: Inherent design requirement, document clearly
3. **DoS via rapid restarts** → Could overwhelm system
   - Mitigation: MAX_RESTARTS_PER_HOUR limit

### Recommendations

1. **Use docker.sock carefully** - Only in trusted environments
2. **Secure webhooks** - Use HTTPS, validate SSL certs
3. **Environment files** - Don't commit secrets to git
4. **Network policies** - Restrict monitor's network access if possible

---

## Performance Considerations

### Resource Usage

**CPU**: Minimal
- Sleep most of the time
- Brief spike during health checks
- Negligible during restarts

**Memory**: < 10MB typical
- Bash interpreter + small script
- No data accumulation
- Restart history is tiny (< 1KB)

**Network**: Minimal
- Periodic HTTP checks (1 req per CHECK_INTERVAL)
- Occasional webhook POSTs
- No continuous connections

### Scalability

**Single Monitor**:
- Can theoretically watch multiple containers
- Current design: one URL, one container
- Future: Could accept container lists

**Multiple Monitors**:
- Each monitors one service
- No coordination needed
- Kubernetes: One monitor per tunnel service

---

## Extension Points

### Future Enhancements

1. **Custom Health Checks**:
```bash
CUSTOM_HEALTH_CHECK="curl -f http://localhost:8080/health"
```

2. **Multiple Containers**:
```bash
CONTAINER_NAMES="tunnel1,tunnel2,tunnel3"
```

3. **Prometheus Metrics**:
```bash
# Expose metrics on :9090/metrics
- checks_total
- restarts_total
- health_status
```

4. **TCP/UDP Health Checks**:
```bash
CHECK_TYPE=tcp
MONITOR_URL=localhost:8080
```

5. **Smart Retry with Backoff**:
```bash
# Exponential backoff between retries
RETRY_BACKOFF=exponential  # linear, exponential, fibonacci
```

6. **Dependency Checks**:
```bash
# Don't restart if dependency is down
DEPENDENCY_CHECK_URL=https://api.example.com/health
```

### How to Extend

1. **Fork the repository**
2. **Add new functions** following existing patterns
3. **Update configuration validation** for new env vars
4. **Add tests** (see Testing Strategy below)
5. **Update documentation**
6. **Submit PR**

---

## Testing Strategy

### Manual Testing

```bash
# Build image
docker build -t tunnel-monitor:test .

# Test with fake URL (should restart container)
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e MONITOR_URL=http://localhost:9999 \
  -e CONTAINER_NAME=test-container \
  -e LOG_LEVEL=DEBUG \
  tunnel-monitor:test

# Test with real URL (should stay healthy)
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e MONITOR_URL=https://google.com \
  -e CONTAINER_NAME=test-container \
  -e LOG_LEVEL=DEBUG \
  tunnel-monitor:test
```

### Automated Testing (Future)

```bash
# Unit tests (bash_unit or bats)
tests/
  test_health_check.sh
  test_restart_logic.sh
  test_state_management.sh

# Integration tests
tests/integration/
  test_docker_interaction.sh
  test_webhook_notifications.sh
```

---

## Debugging Guide

### Common Issues

1. **Monitor exits immediately**
   - Check: Configuration validation logs
   - Fix: Ensure required env vars are set

2. **Container restarts too often**
   - Check: `LOG_LEVEL=DEBUG` to see health check results
   - Fix: Adjust `SUCCESS_CODES`, `RETRY_COUNT`

3. **Container never restarts**
   - Check: Docker socket permissions
   - Fix: Ensure volume mount is correct

### Debug Commands

```bash
# Watch logs in real-time
docker logs -f tunnel-monitor

# Check restart history
docker exec tunnel-monitor cat /tmp/restart_history.log

# Verify container can see target container
docker exec tunnel-monitor docker ps --filter name=target-container

# Test health check manually
docker exec tunnel-monitor curl -v https://your-tunnel-url.com
```

---

## Conclusion

This architecture balances **simplicity**, **reliability**, and **extensibility**. The design choices prioritize:

1. **Operational simplicity** - Easy to deploy and understand
2. **Reliability** - Fail-safe defaults and smart error handling
3. **Security** - Minimal privileges, clear documentation of risks
4. **Maintainability** - Clear code structure, comprehensive documentation

The system is production-ready while remaining flexible enough for future enhancements.

---

**Document Version**: 1.0.0  
**Last Updated**: 2025-12-26  
**Maintained By**: Community contributors
