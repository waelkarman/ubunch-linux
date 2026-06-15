#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Source configuration
# ---------------------------------------------------------------------------
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# ---------------------------------------------------------------------------
# Constants derived from config
# ---------------------------------------------------------------------------
BUNDLES_DIRECTORY="packages"
LOCAL_REPO_NAME="ubunch-linux-repo"
export REPO_BUILD_DIR="$PROJECT_ROOT_DIR/$BUNDLES_DIRECTORY/$LOCAL_REPO_NAME"
POOL_DIR="$REPO_BUILD_DIR/pool/main"

# ---------------------------------------------------------------------------
# 1. Prepare local repo directory structure
# ---------------------------------------------------------------------------
echo "[+] Preparing local repo structure..."
rm -rf "$REPO_BUILD_DIR"
mkdir -p "$POOL_DIR"
mkdir -p "$REPO_BUILD_DIR/dists/$RELEASE/main/binary-$ARCH"

# ---------------------------------------------------------------------------
# Helper: rebuild repo indexes (chiamare da dentro $REPO_BUILD_DIR)
# ---------------------------------------------------------------------------
rebuild_indexes() {
    echo "[+] (Re)building repo indexes..."
    dpkg-scanpackages --arch "$ARCH" pool/main /dev/null 2>/dev/null \
    | tee "dists/$RELEASE/main/binary-$ARCH/Packages" \
    | gzip -9c > "dists/$RELEASE/main/binary-$ARCH/Packages.gz"

    pushd "dists/$RELEASE" > /dev/null
    cat > /tmp/apt-release.conf <<EOF
APT::FTPArchive::Release {
    Origin "Ubunch Linux";
    Label "Ubunch Linux Repository";
    Suite "$RELEASE";
    Codename "$RELEASE";
    Architectures "$ARCH";
    Components "main";
    Description "Ubunch Linux OS Local Repository";
};
EOF
    apt-ftparchive -c /tmp/apt-release.conf release . > Release
    rm -f /tmp/apt-release.conf
    popd > /dev/null
}

# ---------------------------------------------------------------------------
# 2. Register local apt source (solo per usi esterni allo script)
# ---------------------------------------------------------------------------
echo "[+] Registering local apt source..."
sudo rm -f /etc/apt/sources.list.d/agile-bundles-repo.list
sudo rm -f "/etc/apt/sources.list.d/$LOCAL_REPO_NAME.list"
echo "deb [arch=$ARCH trusted=yes] file://$REPO_BUILD_DIR $RELEASE main" \
    | sudo tee "/etc/apt/sources.list.d/$LOCAL_REPO_NAME.list" > /dev/null

# ---------------------------------------------------------------------------
# 3. Build each required bundle
# ---------------------------------------------------------------------------
echo "[+] Building required bundles: ${IMAGE_INSTALL[*]}"

for bundle_name in "${IMAGE_INSTALL[@]}"; do
    [[ -z "$bundle_name" ]] && continue
    bundle_dir="$PROJECT_ROOT_DIR/$BUNDLES_DIRECTORY/$bundle_name"

    if [[ -f "$bundle_dir/build.sh" ]]; then
        echo "[+] Building bundle: $bundle_name"
        pushd "$bundle_dir" > /dev/null
        if ! compgen -G "./${bundle_name}*.deb" > /dev/null; then
            echo "    No pre-built .deb found — running build.sh..."
            ./build.sh
        else
            echo "    Pre-built .deb found, skipping build."
        fi
        popd > /dev/null
    else 
        echo "fatal error: $bundle_dir build script does not exist"
        exit 1
    fi

    if compgen -G "$bundle_dir/${bundle_name}*.deb" > /dev/null; then
        echo "[+] Copying ${bundle_name}*.deb to pool..."
        cp "$bundle_dir/${bundle_name}"*.deb "$POOL_DIR/"
    else
        echo "WARNING: No .deb found for bundle '$bundle_name', skipping."
    fi
done

# Indexes dopo la copia di tutti i bundle
pushd "$REPO_BUILD_DIR" > /dev/null
rebuild_indexes
popd > /dev/null

# ---------------------------------------------------------------------------
# 4. Build apt_list.txt (custom debs + standard packages)
# ---------------------------------------------------------------------------
> "$REPO_BUILD_DIR/apt_list.txt"

for deb in "$POOL_DIR"/*.deb; do
    [[ -f "$deb" ]] || continue
    package_name="$(basename "$deb")"
    echo "${package_name%%_*}" >> "$REPO_BUILD_DIR/apt_list.txt"
done

for pkg in "${PACKAGES[@]}"; do
    if apt-cache show "$pkg" &>/dev/null; then
        echo "$pkg" >> "$REPO_BUILD_DIR/apt_list.txt"
    else
        echo "FATAL ERROR: package '$pkg' not found in any available repo"
        exit 1
    fi
done

awk '!seen[$0]++' "$REPO_BUILD_DIR/apt_list.txt" > /tmp/apt_list_dedup.txt \
    && mv /tmp/apt_list_dedup.txt "$REPO_BUILD_DIR/apt_list.txt"

# ---------------------------------------------------------------------------
# 5. Extract dependencies from custom .deb files
# ---------------------------------------------------------------------------
echo "=== Custom .deb in pool ==="
for deb in "$POOL_DIR"/*.deb; do
    [[ -f "$deb" ]] && echo "  + $(basename "$deb")"
done

echo "=== Extracting dependencies from custom .deb ==="
EXTRA_DEPS=()

for deb in "$POOL_DIR"/*.deb; do
    [[ -f "$deb" ]] || continue
    DEPS="$(dpkg-deb -f "$deb" Depends 2>/dev/null || true)"
    if [[ -n "$DEPS" ]]; then
        echo "  $(basename "$deb"): $DEPS"
        while IFS= read -r dep; do
            [[ -n "$dep" ]] && EXTRA_DEPS+=("$dep")
        done < <(
            echo "$DEPS" \
            | sed 's/([^)]*)//g' \
            | tr ',' '\n' \
            | sed 's/|.*$//' \
            | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
            | grep -v '^$'
        )
    fi
done

if [[ ${#EXTRA_DEPS[@]} -gt 0 ]]; then
    readarray -t EXTRA_DEPS < <(printf '%s\n' "${EXTRA_DEPS[@]}" | sort -u)
    echo "  Extracted ${#EXTRA_DEPS[@]} unique dependencies:"
    printf '    - %s\n' "${EXTRA_DEPS[@]}"
fi

ALL_PACKAGES=("${PACKAGES[@]}" "${EXTRA_DEPS[@]}")
echo "=== Total packages to download: ${#ALL_PACKAGES[@]} ==="

# ---------------------------------------------------------------------------
# 6. Update apt e download pacchetti — ambiente completamente isolato
#    (nessun repo aziendale/agile viene contattato)
# ---------------------------------------------------------------------------
FAKE_ROOT="$(mktemp -d /tmp/fake-root-ubunch-XXXXXX)"
DOWNLOAD_CACHE="$(mktemp -d /tmp/apt-cache-ubunch-XXXXXX)"
TEMP_SOURCES="$(mktemp /tmp/apt-sources-ubunch-XXXXXX.list)"
TEMP_STATE="$(mktemp -d /tmp/apt-state-ubunch-XXXXXX)"
trap 'rm -rf "$FAKE_ROOT" "$DOWNLOAD_CACHE" "$TEMP_SOURCES" "$TEMP_STATE"' EXIT

mkdir -p "$FAKE_ROOT/var/lib/dpkg"
mkdir -p "$DOWNLOAD_CACHE/archives/partial"
mkdir -p "$TEMP_STATE/lists/partial"
touch "$FAKE_ROOT/var/lib/dpkg/status"

# Solo i repo Ubuntu ufficiali + il nostro repo locale
cat > "$TEMP_SOURCES" <<EOF
deb http://archive.ubuntu.com/ubuntu $RELEASE main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu $RELEASE-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu $RELEASE-security main restricted universe multiverse
deb [arch=$ARCH trusted=yes] file://$REPO_BUILD_DIR $RELEASE main
EOF

# Opzioni comuni — isolano completamente apt dall'host
APT_OPTS=(
    -o Dir::Etc::SourceList="$TEMP_SOURCES"
    -o Dir::Etc::SourceParts="-"
    -o Dir::State::Lists="$TEMP_STATE/lists"
    -o Dir::State::status="$FAKE_ROOT/var/lib/dpkg/status"
    -o Dir::Cache="$DOWNLOAD_CACHE"
    -o Dir::Cache::Archives="$DOWNLOAD_CACHE/archives"
)

echo "=== apt-get update (repo isolato, niente agile/aziendale) ==="
apt-get update "${APT_OPTS[@]}"

echo "=== Downloading packages + dependencies (fake dpkg root) ==="
apt-get install \
    --download-only \
    --install-recommends \
    -y \
    "${APT_OPTS[@]}" \
    "${ALL_PACKAGES[@]}"

DOWNLOADED="$(find "$DOWNLOAD_CACHE/archives" -maxdepth 1 -name "*.deb" -type f | wc -l)"
echo "Downloaded: $DOWNLOADED packages"

if [[ "$DOWNLOADED" -gt 0 ]]; then
    echo "=== Copying downloaded packages to pool ==="
    find "$DOWNLOAD_CACHE/archives" -maxdepth 1 -name "*.deb" -type f \
        -exec cp {} "$POOL_DIR/" \;
else
    echo "WARNING: No packages downloaded by apt-get!"
fi

# trap pulisce automaticamente FAKE_ROOT, DOWNLOAD_CACHE, TEMP_SOURCES, TEMP_STATE

# ---------------------------------------------------------------------------
# 7. Set permissions on local repo
# ---------------------------------------------------------------------------
sudo chmod -R a+r "$REPO_BUILD_DIR"
sudo find "$REPO_BUILD_DIR" -type d -exec chmod a+x {} \;

# ---------------------------------------------------------------------------
# 8. Rebuild final indexes
# ---------------------------------------------------------------------------
pushd "$REPO_BUILD_DIR" > /dev/null
rebuild_indexes
popd > /dev/null

# ---------------------------------------------------------------------------
# 9. Validate
# ---------------------------------------------------------------------------
TOTAL_DEBS="$(find "$POOL_DIR" -name "*.deb" -type f | wc -l)"
INDEXED_PKGS="$(zcat "$REPO_BUILD_DIR/dists/$RELEASE/main/binary-$ARCH/Packages.gz" \
    | grep -c '^Package:' || true)"
REPO_SIZE="$(du -sh "$REPO_BUILD_DIR" | cut -f1)"

echo ""
echo "=== Validation ==="
echo "   Total .deb files : $TOTAL_DEBS"
echo "   Indexed packages  : $INDEXED_PKGS"
echo "   Repository size   : $REPO_SIZE"

if [[ "$TOTAL_DEBS" -ne "$INDEXED_PKGS" ]]; then
    echo "   WARNING: mismatch between .deb count and indexed packages!"
fi
if [[ "$TOTAL_DEBS" -lt 20 ]]; then
    echo "   WARNING: only $TOTAL_DEBS packages in pool — expected 50+."
fi

echo ""
echo "=== Repo ready: $REPO_BUILD_DIR ==="

# ---------------------------------------------------------------------------
# 10. Build base OS image
# ---------------------------------------------------------------------------
echo "[+] Building base OS..."
pushd "$PROJECT_ROOT_DIR/ubunch" > /dev/null
sudo -E ./main.sh
popd > /dev/null