#!/bin/bash

###########################################
# Release Helper Script
# Simplifies the process of creating new releases
###########################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}==>${NC} $1"
}

# Check if we're in the right directory
if [[ ! -f "VERSION" ]] || [[ ! -f "Dockerfile" ]]; then
    log_error "Must be run from the tunnel-monitor root directory"
    exit 1
fi

# Get current version
CURRENT_VERSION=$(cat VERSION | tr -d '\n')
log_info "Current version: $CURRENT_VERSION"

# Parse semver
IFS='.' read -ra VERSION_PARTS <<< "$CURRENT_VERSION"
MAJOR="${VERSION_PARTS[0]}"
MINOR="${VERSION_PARTS[1]}"
PATCH="${VERSION_PARTS[2]}"

echo ""
echo "What type of release is this?"
echo "  1) Major (breaking changes) - ${MAJOR}.x.x -> $((MAJOR+1)).0.0"
echo "  2) Minor (new features)     - ${MAJOR}.${MINOR}.x -> ${MAJOR}.$((MINOR+1)).0"
echo "  3) Patch (bug fixes)        - ${MAJOR}.${MINOR}.${PATCH} -> ${MAJOR}.${MINOR}.$((PATCH+1))"
echo "  4) Custom version"
echo ""
read -p "Select (1-4): " RELEASE_TYPE

case $RELEASE_TYPE in
    1)
        NEW_VERSION="$((MAJOR+1)).0.0"
        ;;
    2)
        NEW_VERSION="${MAJOR}.$((MINOR+1)).0"
        ;;
    3)
        NEW_VERSION="${MAJOR}.${MINOR}.$((PATCH+1))"
        ;;
    4)
        read -p "Enter new version (x.y.z): " NEW_VERSION
        # Validate semver format
        if ! [[ $NEW_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            log_error "Invalid version format. Must be x.y.z"
            exit 1
        fi
        ;;
    *)
        log_error "Invalid selection"
        exit 1
        ;;
esac

log_step "New version will be: $NEW_VERSION"

# Confirm
echo ""
read -p "Continue with release v$NEW_VERSION? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
    log_warn "Release cancelled"
    exit 0
fi

# Check for uncommitted changes
if [[ -n $(git status -s) ]]; then
    log_error "You have uncommitted changes. Please commit or stash them first."
    git status -s
    exit 1
fi

# Update VERSION file
log_step "Updating VERSION file..."
echo "$NEW_VERSION" > VERSION

# Update monitor.sh version
log_step "Updating monitor.sh version string..."
sed -i "s/Generic Tunnel Monitor v.*/Generic Tunnel Monitor v$NEW_VERSION\"/" monitor.sh

# Update Dockerfile version label
log_step "Updating Dockerfile version label..."
sed -i "s/org.opencontainers.image.version=\".*/org.opencontainers.image.version=\"$NEW_VERSION\"/" Dockerfile

# Ask for changelog entry
echo ""
log_step "Update CHANGELOG.md"
echo ""
echo "Please describe the changes in this release:"
read -p "Summary: " CHANGELOG_SUMMARY

# Prepare changelog entry
CHANGELOG_DATE=$(date +%Y-%m-%d)
CHANGELOG_ENTRY="## [$NEW_VERSION] - $CHANGELOG_DATE

### Summary
$CHANGELOG_SUMMARY

"

# Insert into CHANGELOG.md after [Unreleased] section
sed -i "/## \[Unreleased\]/a\\
\\
---\\
\\
$CHANGELOG_ENTRY" CHANGELOG.md

log_info "CHANGELOG.md updated"

# Commit changes
log_step "Committing changes..."
git add VERSION monitor.sh Dockerfile CHANGELOG.md
git commit -m "Release v$NEW_VERSION"

# Create tag
log_step "Creating git tag v$NEW_VERSION..."
git tag -a "v$NEW_VERSION" -m "Release v$NEW_VERSION: $CHANGELOG_SUMMARY"

log_info "Release v$NEW_VERSION prepared successfully!"
echo ""
echo "Next steps:"
echo "  1. Review changes: git show"
echo "  2. Push commits:   git push origin main"
echo "  3. Push tag:       git push origin v$NEW_VERSION"
echo ""
echo "GitHub Actions will automatically:"
echo "  ✅ Build Docker images for amd64 and arm64"
echo "  ✅ Push to GitHub Container Registry"
echo "  ✅ Push to Docker Hub (if configured)"
echo "  ✅ Create GitHub Release with notes"
echo ""
read -p "Push now? (y/n): " PUSH_NOW

if [[ "$PUSH_NOW" == "y" ]]; then
    log_step "Pushing to remote..."
    git push origin main
    git push origin "v$NEW_VERSION"
    
    log_info "Release pushed! Check GitHub Actions for build progress:"
    echo "  https://github.com/$(git remote get-url origin | sed 's/.*github.com[:/]\(.*\)\.git/\1/')/actions"
else
    log_warn "Remember to push manually:"
    echo "  git push origin main"
    echo "  git push origin v$NEW_VERSION"
fi

log_info "Done! 🎉"
