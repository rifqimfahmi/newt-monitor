# Generic Tunnel Monitor Dockerfile
# Multi-stage build for minimal image size and security

FROM alpine:3.19 AS base

# Metadata
LABEL org.opencontainers.image.title="Generic Tunnel Monitor"
LABEL org.opencontainers.image.description="A generic monitoring solution for tunnel services with automatic container restart"
LABEL org.opencontainers.image.version="1.0.2"
LABEL org.opencontainers.image.authors="Rifqi"
LABEL org.opencontainers.image.source="https://github.com/rifqimfahmi/newt-monitor"
LABEL org.opencontainers.image.licenses="MIT"

# Install runtime dependencies
RUN apk add --no-cache \
    bash \
    curl \
    docker-cli \
    ca-certificates \
    tzdata \
    && rm -rf /var/cache/apk/*

# Create app directory
WORKDIR /app

# Copy monitoring script
COPY --chmod=755 monitor.sh /app/monitor.sh

# Create directory for state files
RUN mkdir -p /tmp

# Health check for the monitor itself
HEALTHCHECK --interval=60s --timeout=10s --start-period=10s --retries=3 \
    CMD pgrep -f monitor.sh > /dev/null || exit 1

# Default environment variables (can be overridden)
ENV CHECK_INTERVAL=30 \
    SUCCESS_CODES="200,301,302" \
    RESTART_DELAY=60 \
    CONNECTION_TIMEOUT=5 \
    MAX_TIMEOUT=10 \
    RETRY_COUNT=3 \
    MAX_RESTARTS_PER_HOUR=0 \
    LOG_LEVEL=INFO

# Run the monitor
CMD ["/app/monitor.sh"]
