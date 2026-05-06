#!/bin/bash

# Script to extract current Helm values from deployed releases
# and save them to their respective application directories

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
CLEAN_MODE=false
if [[ "$1" == "--clean" ]]; then
    CLEAN_MODE=true
fi

# Function to clean up old helm-values files
cleanup_helm_values() {
    echo "🧹 Cleaning up existing helm-values files..."
    local count=$(find . -name "helm-values*.yaml" -type f | wc -l)
    if [[ $count -gt 0 ]]; then
        find . -name "helm-values*.yaml" -type f -delete
        echo -e "${GREEN}✓${NC} Removed $count helm-values file(s)"
    else
        echo -e "${YELLOW}⊘${NC} No helm-values files found to clean"
    fi
    echo ""
}

# Show usage information
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --clean    Remove all existing helm-values*.yaml files before extraction"
    echo "  --help     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                # Extract values from all releases"
    echo "  $0 --clean        # Clean old files and extract fresh values"
    exit 0
fi

# Clean up if requested
if [[ "$CLEAN_MODE" == true ]]; then
    cleanup_helm_values
fi

echo "🔍 Extracting Helm values from deployed releases..."
echo ""

# Define manual mappings for releases that don't match directory names
declare -A MANUAL_MAPPINGS=(
    ["plex-media-server"]="plex"
    ["traefik"]="ingress/traefik"
    ["cert-manager"]="ingress/cert-manager"
    ["nfs-subdir-external-provisioner"]="storage/nfs-shares/provisioner"
    ["longhorn"]="storage/longhorn"
    ["prometheus"]="monitoring"
    ["deltabadger"]="blockchain/deltabadger"
    # Media automation
    ["radarr"]="media-automation/radarr"
    ["sonarr-tv"]="media-automation/sonarr"
    ["sonarr-anime"]="media-automation/sonarr"
    ["lidarr"]="media-automation/lidarr"
    ["prowlarr"]="media-automation/prowlarr"
    ["clonarr"]="media-automation/clonarr"
    ["seerr"]="media-automation/seerr"
    ["qbittorrent"]="media-automation/qbittorrent"
    ["flaresolverr"]="media-automation/flaresolverr"
    # Game servers
    ["palworld-server"]="game-servers/palworld-server"
    ["satisfactory-server"]="game-servers/satisfactory-server"
    # Productivity
    ["nextcloud"]="productivity/nextcloud"
    ["paperless-ngx"]="productivity/paperless-ngx"
    ["n8n"]="productivity/n8n"
    ["actual-budget"]="productivity/actual-budget"
    ["gitea"]="productivity/gitea"
    # Social
    ["bluesky-pds"]="social/bluesky-pds"
    ["nostr-rs-relay"]="social/nostr-rs-relay"
    ["nostr-strfry"]="social/nostr-strfry"
)

# Get all Helm releases
helm list -A -o json > /tmp/helm-releases.json

# Process each release
jq -c '.[]' /tmp/helm-releases.json | while read -r release; do
    RELEASE_NAME=$(echo "$release" | jq -r '.name')
    NAMESPACE=$(echo "$release" | jq -r '.namespace')

    # Determine target directory
    TARGET_DIR=""

    # Check manual mappings first
    if [[ -n "${MANUAL_MAPPINGS[$RELEASE_NAME]}" ]]; then
        TARGET_DIR="${MANUAL_MAPPINGS[$RELEASE_NAME]}"
    # Check for exact directory match
    elif [[ -d "./$RELEASE_NAME" ]]; then
        TARGET_DIR="$RELEASE_NAME"
    # Check for partial match (e.g., sonarr-tv -> sonarr)
    else
        BASE_NAME=$(echo "$RELEASE_NAME" | sed 's/-[^-]*$//')
        if [[ -d "./$BASE_NAME" ]]; then
            TARGET_DIR="$BASE_NAME"
        fi
    fi

    # Skip if no matching directory found
    if [[ -z "$TARGET_DIR" || ! -d "./$TARGET_DIR" ]]; then
        echo -e "${YELLOW}⊘ Skipping${NC} $RELEASE_NAME (namespace: $NAMESPACE) - no matching directory"
        continue
    fi

    # Determine output file name based on release-directory match
    if [[ "$RELEASE_NAME" == "$TARGET_DIR" || "$RELEASE_NAME" == "$(basename "$TARGET_DIR")" ]]; then
        # Release name matches directory - use generic filename
        OUTPUT_FILE="./$TARGET_DIR/helm-values.yaml"
    else
        # Release name differs from directory - use release-specific filename
        # This handles cases like sonarr-tv and sonarr-anime in the same directory
        OUTPUT_FILE="./$TARGET_DIR/helm-values-${RELEASE_NAME}.yaml"
    fi

    echo -e "${GREEN}✓${NC} Extracting $RELEASE_NAME (namespace: $NAMESPACE) → $OUTPUT_FILE"

    # Get values and add header comment
    {
        echo "# Extracted Helm values from release: $RELEASE_NAME"
        echo "# Namespace: $NAMESPACE"
        echo "# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
        echo "# Command: helm get values $RELEASE_NAME -n $NAMESPACE"
        echo "#"
        echo "# NOTE: This file is auto-generated and should not be committed"
        echo "# Use custom-values.yaml or values.yaml for version-controlled overrides"
        echo ""
        helm get values "$RELEASE_NAME" -n "$NAMESPACE"
    } > "$OUTPUT_FILE"
done

# Cleanup
rm -f /tmp/helm-releases.json

echo ""
echo -e "${GREEN}✅ Done!${NC} Helm values extracted to respective directories"
echo ""
echo "📝 Files created:"
find . -name "helm-values*.yaml" -type f | sort

echo ""
echo "⚠️  Remember: helm-values.yaml files are excluded from git by .gitignore"
