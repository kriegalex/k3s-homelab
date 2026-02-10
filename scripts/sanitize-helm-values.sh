#!/bin/bash

# Sanitize helm values for public git commits
# Copies helm-values.yaml (gitignored, real values) → values.yaml (committed, generic placeholders)
# Also sanitizes other committed files (README.md, ingress, PVC, etc.) in-place
#
# Usage:
#   ./scripts/sanitize-helm-values.sh              # Sanitize helm-values → values.yaml only
#   ./scripts/sanitize-helm-values.sh --all         # Also sanitize README, ingress, PVC files in-place
#   ./scripts/sanitize-helm-values.sh --check       # Dry-run: report what would be sanitized

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
MODE="values-only"
if [[ "$1" == "--all" ]]; then
    MODE="all"
elif [[ "$1" == "--check" ]]; then
    MODE="check"
elif [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Sanitize helm values and config files for public git commits."
    echo ""
    echo "Options:"
    echo "  (none)     Copy helm-values.yaml → values.yaml with sanitization"
    echo "  --all      Also sanitize README.md, ingress, PVC files in-place"
    echo "  --check    Dry-run: report files that contain private data"
    echo "  --help     Show this help message"
    exit 0
fi

# ─────────────────────────────────────────────
# Sanitization replacements
# ─────────────────────────────────────────────

# Check if an IP is in a private/reserved range (RFC 1918, loopback, link-local)
is_private_ip() {
    local ip="$1"
    [[ "$ip" =~ ^10\. ]] ||
    [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] ||
    [[ "$ip" =~ ^192\.168\. ]] ||
    [[ "$ip" =~ ^127\. ]] ||
    [[ "$ip" =~ ^169\.254\. ]] ||
    [[ "$ip" =~ ^0\. ]]
}

# Replace public IPs with RFC 5737 documentation range (203.0.113.0/24)
sanitize_public_ips() {
    local file="$1"
    local counter=1
    local found_public=false

    while read -r ip; do
        if ! is_private_ip "$ip"; then
            local escaped="${ip//./\\.}"
            local replacement="203.0.113.${counter}"
            sed -i "s/${escaped}/${replacement}/g" "$file"
            echo -e "${YELLOW}    ⚠ Replaced public IP ${ip} → ${replacement}${NC}"
            counter=$((counter + 1))
            found_public=true
        fi
    done < <(grep -oP '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b' "$file" 2>/dev/null | sort -u)

    $found_public
}

apply_sanitization() {
    local file="$1"

    # Domain replacements (order matters: specific before general)
    sed -i 's/git-pi\.lourenco\.ch/git.homelab.example.com/g' "$file"
    sed -i 's/noreply@lourenco\.ch/noreply@homelab.example.com/g' "$file"
    sed -i 's/lourenco\.ch/homelab.example.com/g' "$file"
    sed -i 's/21crypto\.ch/crypto.example.com/g' "$file"
    sed -i 's/\.k3s\.home/.local/g' "$file"
    sed -i 's/pihole-k8s\.local/pihole.local/g' "$file"

    # Replace any public IPs with documentation range
    sanitize_public_ips "$file" || true
}

# ─────────────────────────────────────────────
# Check mode: report files with private data
# ─────────────────────────────────────────────
if [[ "$MODE" == "check" ]]; then
    echo -e "${BLUE}🔍 Checking for private data in committed files...${NC}"
    echo ""

    FOUND=0
    while IFS= read -r -d '' file; do
        reasons=""

        # Check for private domains
        if grep -qE 'lourenco\.ch|21crypto\.ch|\.k3s\.home|pihole-k8s\.local' "$file" 2>/dev/null; then
            reasons="domains"
        fi

        # Check for public IPs
        has_public=false
        while read -r ip; do
            if ! is_private_ip "$ip"; then
                has_public=true
                break
            fi
        done < <(grep -oP '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b' "$file" 2>/dev/null | sort -u)

        if [[ "$has_public" == true ]]; then
            reasons="${reasons:+$reasons, }public IPs"
        fi

        if [[ -n "$reasons" ]]; then
            echo -e "${YELLOW}  ⚠${NC}  ${file#$REPO_ROOT/} ($reasons)"
            FOUND=$((FOUND + 1))
        fi
    done < <(find "$REPO_ROOT" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.md" \) \
        -not -path "*/.git/*" \
        -not -path "*/.gitea/scripts/*" \
        -not -path "*/helm-values*.yaml" \
        -not -name "PLAN-*.md" \
        -print0)

    if [[ $FOUND -eq 0 ]]; then
        echo -e "${GREEN}✅ No identifying data found in committed files${NC}"
    else
        echo ""
        echo -e "${YELLOW}Found $FOUND file(s) with identifying data${NC}"
    fi
    exit 0
fi

# ─────────────────────────────────────────────
# Values mode: helm-values.yaml → values.yaml
# ─────────────────────────────────────────────
echo -e "${BLUE}🔧 Sanitizing helm values for public release...${NC}"
echo ""

COUNT=0
while IFS= read -r -d '' src; do
    dir=$(dirname "$src")
    base=$(basename "$src")

    # Determine output filename
    if [[ "$base" == "helm-values.yaml" ]]; then
        dst="$dir/values.yaml"
    elif [[ "$base" =~ ^helm-values-(.+)\.yaml$ ]]; then
        dst="$dir/values-${BASH_REMATCH[1]}.yaml"
    else
        continue
    fi

    cp "$src" "$dst"
    apply_sanitization "$dst"

    # Strip the auto-generated header comment about not committing
    sed -i '/^# NOTE: This file is auto-generated and should not be committed$/d' "$dst"
    sed -i 's/^# Use custom-values.yaml or values.yaml for version-controlled overrides$/# Version-controlled values with sanitized placeholders/' "$dst"

    echo -e "${GREEN}  ✓${NC}  ${src#$REPO_ROOT/} → ${dst#$REPO_ROOT/}"
    COUNT=$((COUNT + 1))
done < <(find "$REPO_ROOT" -type f \( -name "helm-values.yaml" -o -name "helm-values-*.yaml" \) \
    -not -path "*/.git/*" -print0)

if [[ $COUNT -eq 0 ]]; then
    echo -e "${YELLOW}  ⊘  No helm-values.yaml files found${NC}"
    echo "     Run extract-helm-values.sh first to extract values from live releases"
else
    echo ""
    echo -e "${GREEN}✅ Sanitized $COUNT file(s)${NC}"
fi

# ─────────────────────────────────────────────
# All mode: also sanitize committed files in-place
# ─────────────────────────────────────────────
if [[ "$MODE" == "all" ]]; then
    echo ""
    echo -e "${BLUE}🔧 Sanitizing committed files in-place...${NC}"
    echo ""

    INPLACE_COUNT=0
    while IFS= read -r -d '' file; do
        needs_sanitization=false

        # Check for private domains
        if grep -qE 'lourenco\.ch|21crypto\.ch|\.k3s\.home|pihole-k8s\.local' "$file" 2>/dev/null; then
            needs_sanitization=true
        fi

        # Check for public IPs
        if [[ "$needs_sanitization" == false ]]; then
            while read -r ip; do
                if ! is_private_ip "$ip"; then
                    needs_sanitization=true
                    break
                fi
            done < <(grep -oP '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b' "$file" 2>/dev/null | sort -u)
        fi

        if [[ "$needs_sanitization" == true ]]; then
            apply_sanitization "$file"
            echo -e "${GREEN}  ✓${NC}  ${file#$REPO_ROOT/}"
            INPLACE_COUNT=$((INPLACE_COUNT + 1))
        fi
    done < <(find "$REPO_ROOT" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.md" \) \
        -not -path "*/.git/*" \
        -not -path "*/.gitea/scripts/*" \
        -not -path "*/helm-values*.yaml" \
        -not -name "PLAN-*.md" \
        -print0)

    if [[ $INPLACE_COUNT -eq 0 ]]; then
        echo -e "${GREEN}  ✅ No files needed in-place sanitization${NC}"
    else
        echo ""
        echo -e "${GREEN}✅ Sanitized $INPLACE_COUNT file(s) in-place${NC}"
    fi
fi
