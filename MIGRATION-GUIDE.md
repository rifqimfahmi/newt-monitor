# 🚚 Migration Guide: Moving to Separate Repository

This guide provides step-by-step instructions for moving the `tunnel-monitor` folder from this Appwrite project to its own standalone Git repository and publishing the Docker image to GitHub Container Registry (GHCR) and/or Docker Hub.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Step 1: Create New Repository](#step-1-create-new-repository)
- [Step 2: Extract and Push Code](#step-2-extract-and-push-code)
- [Step 3: Set Up GitHub Actions](#step-3-set-up-github-actions)
- [Step 4: Configure Secrets](#step-4-configure-secrets)
- [Step 5: Create First Release](#step-5-create-first-release)
- [Step 6: Update Appwrite docker-compose.yml](#step-6-update-appwrite-docker-composeyml)
- [Step 7: Verify Everything Works](#step-7-verify-everything-works)
- [Alternative: Keep as Subfolder](#alternative-keep-as-subfolder)

---

## Prerequisites

Before starting, ensure you have:

- [x] Git installed and configured
- [x] GitHub account with repository creation permissions
- [x] Docker installed locally (for testing)
- [x] Basic understanding of Git, GitHub Actions, and Docker

---

## Step 1: Create New Repository

### On GitHub

1. Go to https://github.com/new
2. Create a new repository:
   - **Name**: `tunnel-monitor` (or your preferred name)
   - **Description**: "Generic tunnel monitoring with automatic container restart"
   - **Visibility**: Public (for GHCR free tier) or Private
   - **Initialize**: ❌ Do NOT initialize with README, .gitignore, or license
3. Click "Create repository"

### Note Your Repository URL

```bash
# SSH (recommended)
git@github.com:YOUR_USERNAME/tunnel-monitor.git

# HTTPS
https://github.com/YOUR_USERNAME/tunnel-monitor.git
```

---

## Step 2: Extract and Push Code

### Method A: Copy Folder (Simplest)

```bash
# Navigate to parent directory
cd /home/rifqi/Documents/projects/appwrite

# Copy tunnel-monitor to new location
cp -r appwrite/tunnel-monitor ~/tunnel-monitor-repo
cd ~/tunnel-monitor-repo

# Initialize git
git init
git add .
git commit -m "Initial commit: Generic Tunnel Monitor v1.0.0"

# Add remote and push
git branch -M main
git remote add origin git@github.com:YOUR_USERNAME/tunnel-monitor.git
git push -u origin main
```

### Method B: Preserve Git History (Advanced)

If you want to preserve commit history from the Appwrite repo:

```bash
# Clone the Appwrite repo
cd /tmp
git clone /home/rifqi/Documents/projects/appwrite/appwrite appwrite-temp
cd appwrite-temp

# Filter to only tunnel-monitor folder
git filter-branch --subdirectory-filter tunnel-monitor -- --all

# Add new remote and push
git remote set-url origin git@github.com:YOUR_USERNAME/tunnel-monitor.git
git push -u origin main

# Clean up
cd ..
rm -rf appwrite-temp
```

---

## Step 3: Set Up GitHub Actions

The folder already includes GitHub Actions workflows in `.github/workflows/`. You'll need to create these files after the initial push:

### Create `.github/workflows/docker-publish.yml`

This workflow will automatically build and publish your Docker image.

```yaml
name: Build and Publish Docker Image

on:
  push:
    branches:
      - main
    tags:
      - 'v*.*.*'
  pull_request:
    branches:
      - main
  workflow_dispatch:

env:
  REGISTRY_GHCR: ghcr.io
  REGISTRY_DOCKER: docker.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GitHub Container Registry
        if: github.event_name != 'pull_request'
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY_GHCR }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Log in to Docker Hub
        if: github.event_name != 'pull_request' && secrets.DOCKERHUB_USERNAME != ''
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY_DOCKER }}
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: |
            ${{ env.REGISTRY_GHCR }}/${{ env.IMAGE_NAME }}
            ${{ env.REGISTRY_DOCKER }}/${{ secrets.DOCKERHUB_USERNAME }}/tunnel-monitor
          tags: |
            # Tag for branch
            type=ref,event=branch
            # Tag for PR
            type=ref,event=pr
            # Tag for semver
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=semver,pattern={{major}}
            # Tag latest
            type=raw,value=latest,enable={{is_default_branch}}
            # Tag edge for main branch
            type=edge,branch=main

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Generate release notes
        if: startsWith(github.ref, 'refs/tags/v')
        run: |
          echo "## Docker Images" > release-notes.md
          echo "" >> release-notes.md
          echo "### GitHub Container Registry" >> release-notes.md
          echo '```bash' >> release-notes.md
          echo "docker pull ghcr.io/${{ github.repository }}:${GITHUB_REF_NAME#v}" >> release-notes.md
          echo '```' >> release-notes.md
          echo "" >> release-notes.md
          echo "### Docker Hub" >> release-notes.md
          echo '```bash' >> release-notes.md
          echo "docker pull ${{ secrets.DOCKERHUB_USERNAME }}/tunnel-monitor:${GITHUB_REF_NAME#v}" >> release-notes.md
          echo '```' >> release-notes.md

      - name: Create GitHub Release
        if: startsWith(github.ref, 'refs/tags/v')
        uses: softprops/action-gh-release@v1
        with:
          body_path: release-notes.md
          draft: false
          prerelease: false
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### Add this workflow to your repository

```bash
cd ~/tunnel-monitor-repo
mkdir -p .github/workflows
# Create the file above and save it as .github/workflows/docker-publish.yml

git add .github/workflows/docker-publish.yml
git commit -m "Add GitHub Actions workflow for Docker publishing"
git push
```

---

## Step 4: Configure Secrets

### GitHub Container Registry (GHCR) - Automatic

GHCR uses `GITHUB_TOKEN` which is automatically available. No setup needed! ✅

### Docker Hub (Optional)

If you also want to publish to Docker Hub:

1. Go to https://hub.docker.com/settings/security
2. Click "New Access Token"
3. Name: "GitHub Actions"
4. Access permissions: "Read, Write, Delete"
5. Generate and copy the token

6. Go to your GitHub repo → Settings → Secrets and variables → Actions
7. Add two secrets:
   - **Name**: `DOCKERHUB_USERNAME`, **Value**: your Docker Hub username
   - **Name**: `DOCKERHUB_TOKEN`, **Value**: the token you just created

---

## Step 5: Create First Release

### Using Git Tags (Recommended)

```bash
cd ~/tunnel-monitor-repo

# Create and push a version tag
git tag -a v1.0.0 -m "Release v1.0.0: Initial public release"
git push origin v1.0.0
```

This will:
1. ✅ Trigger GitHub Actions
2. ✅ Build multi-arch Docker images (amd64, arm64)
3. ✅ Push to GHCR with tags: `1.0.0`, `1.0`, `1`, `latest`
4. ✅ Push to Docker Hub (if configured)
5. ✅ Create a GitHub Release

### Monitor the Build

1. Go to your repo → Actions tab
2. Watch the "Build and Publish Docker Image" workflow
3. Should complete in ~5-10 minutes

### Verify Published Images

```bash
# Check GHCR
docker pull ghcr.io/YOUR_USERNAME/tunnel-monitor:1.0.0

# Check Docker Hub (if configured)
docker pull YOUR_USERNAME/tunnel-monitor:1.0.0
```

---

## Step 6: Update Appwrite docker-compose.yml

Now update your Appwrite setup to use the published image instead of building locally.

### Before (Current)

```yaml
  newt-monitor:
    build: 
      context: .
      dockerfile: healthcheck.newt.Dockerfile
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ${PWD}:/app/project
    working_dir: /app/project
    restart: unless-stopped
    profiles:
      - tunnel
    environment:
      - CONTAINER_NAME=newt
      - CHECK_INTERVAL=30
```

### After (Using Published Image)

```yaml
  newt-monitor:
    image: ghcr.io/YOUR_USERNAME/tunnel-monitor:1.0.0  # Pin to specific version
    container_name: newt-monitor
    restart: unless-stopped
    profiles:
      - tunnel
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - MONITOR_URL=https://appwrite.this-thingy.xyz  # Add this!
      - CONTAINER_NAME=appwrite-newt
      - CHECK_INTERVAL=30
      - LOG_LEVEL=INFO
```

### Apply Changes

```bash
cd /home/rifqi/Documents/projects/appwrite/appwrite

# Stop old monitor
docker-compose --profile tunnel down newt-monitor

# Pull new image
docker pull ghcr.io/YOUR_USERNAME/tunnel-monitor:1.0.0

# Start new monitor
docker-compose --profile tunnel up -d newt-monitor
```

### Verify It's Working

```bash
# Check logs
docker logs -f newt-monitor

# You should see:
# [INFO] Generic Tunnel Monitor v1.0.0
# [INFO] Configuration validated successfully
# [INFO] Starting monitoring loop...
# [INFO] Service is healthy (HTTP check passed)
```

---

## Step 7: Verify Everything Works

### Test the Monitor

```bash
# Check that monitor is running
docker ps | grep newt-monitor

# Watch logs
docker logs -f newt-monitor

# Test by stopping the tunnel (should restart automatically)
docker stop appwrite-newt
# Monitor should detect failure and restart it

# Check restart history
docker exec newt-monitor cat /tmp/restart_history.log
```

### Clean Up Old Files (Optional)

Once verified working, you can remove old files from Appwrite repo:

```bash
cd /home/rifqi/Documents/projects/appwrite/appwrite

# Remove old Dockerfile and script (keep docker-compose.yml)
rm healthcheck.newt.Dockerfile
rm newt-monitor.sh

# Remove the tunnel-monitor folder (now in separate repo)
rm -rf tunnel-monitor

# Commit changes
git add .
git commit -m "Remove tunnel-monitor (moved to separate repository)"
git push
```

---

## Alternative: Keep as Subfolder

If you want to keep `tunnel-monitor` in the Appwrite repo but still publish it:

### Option 1: Git Submodule

```bash
cd /home/rifqi/Documents/projects/appwrite/appwrite

# Remove folder
rm -rf tunnel-monitor

# Add as submodule
git submodule add git@github.com:YOUR_USERNAME/tunnel-monitor.git tunnel-monitor
git commit -m "Add tunnel-monitor as submodule"
git push
```

### Option 2: Keep Local Copy

Keep `tunnel-monitor/` in your Appwrite repo for reference, but always pull the published Docker image. Update your `.gitignore`:

```
# .gitignore
tunnel-monitor/
```

---

## Updating to New Versions

### Release New Version

```bash
cd ~/tunnel-monitor-repo

# Make changes
# ... edit files ...

# Commit changes
git add .
git commit -m "Add feature: XYZ"
git push

# Create new version tag
git tag -a v1.1.0 -m "Release v1.1.0: Add XYZ feature"
git push origin v1.1.0

# GitHub Actions will automatically build and publish
```

### Update Appwrite Setup

```bash
cd /home/rifqi/Documents/projects/appwrite/appwrite

# Update docker-compose.yml
# Change: ghcr.io/YOUR_USERNAME/tunnel-monitor:1.0.0
# To:     ghcr.io/YOUR_USERNAME/tunnel-monitor:1.1.0

# Pull new image
docker pull ghcr.io/YOUR_USERNAME/tunnel-monitor:1.1.0

# Restart monitor
docker-compose --profile tunnel up -d newt-monitor
```

---

## Troubleshooting

### GitHub Actions Fails

**Issue**: Workflow fails with "permission denied"

**Fix**: Go to repo → Settings → Actions → General → Workflow permissions → Select "Read and write permissions"

### Image Not Found on GHCR

**Issue**: `docker pull` fails with "not found"

**Fix**: 
1. Verify workflow completed successfully
2. Go to repo → Packages → Make package public
3. Or authenticate: `echo $CR_PAT | docker login ghcr.io -u YOUR_USERNAME --password-stdin`

### Build Fails - Multi-arch

**Issue**: ARM64 build fails

**Fix**: Remove ARM64 from platforms if not needed:
```yaml
platforms: linux/amd64  # Remove linux/arm64
```

### Monitor Not Restarting Container

**Issue**: Monitor runs but doesn't restart tunnel

**Fix**: Check Docker socket permissions
```bash
# Verify socket is mounted
docker inspect newt-monitor | grep docker.sock

# Should show: /var/run/docker.sock:/var/run/docker.sock
```

---

## Best Practices

### Version Pinning

**Production**: Always pin to specific version
```yaml
image: ghcr.io/YOUR_USERNAME/tunnel-monitor:1.0.0  # ✅ Good
```

**Development**: Use latest or edge
```yaml
image: ghcr.io/YOUR_USERNAME/tunnel-monitor:latest  # ✅ OK for dev
```

### Semantic Versioning

Follow SemVer strictly:

- **v1.0.0 → v1.0.1**: Bug fixes (safe to upgrade)
- **v1.0.0 → v1.1.0**: New features (review changelog)
- **v1.0.0 → v2.0.0**: Breaking changes (read upgrade guide)

### Changelog

Maintain `CHANGELOG.md`:

```markdown
# Changelog

## [1.1.0] - 2025-01-15
### Added
- Webhook notification support
- Prometheus metrics endpoint

### Fixed
- Restart loop detection accuracy

## [1.0.0] - 2025-12-26
### Added
- Initial release
- HTTP health checks
- Automatic container restart
```

---

## Summary Checklist

After migration, verify:

- [ ] New repository created on GitHub
- [ ] Code pushed to new repository
- [ ] GitHub Actions workflow configured
- [ ] Docker Hub secrets added (if using)
- [ ] First release tag created (v1.0.0)
- [ ] Docker images published to GHCR
- [ ] Docker images published to Docker Hub (optional)
- [ ] Appwrite docker-compose.yml updated
- [ ] Monitor tested and working
- [ ] Old files removed from Appwrite repo
- [ ] Documentation updated with correct URLs

---

## Need Help?

- **GitHub Actions Docs**: https://docs.github.com/en/actions
- **GHCR Docs**: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
- **Docker Hub**: https://docs.docker.com/docker-hub/
- **Issue Tracker**: https://github.com/YOUR_USERNAME/tunnel-monitor/issues

---

**Good luck with your migration! 🚀**

This standalone repository will make the tunnel monitor reusable across all your projects and shareable with the community.
