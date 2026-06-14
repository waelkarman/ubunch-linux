#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Source configuration
# ---------------------------------------------------------------------------
UBUNCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$UBUNCH_DIR/../config.sh"

# ---------------------------------------------------------------------------
# Constants — tutti i path relativi a UBUNCH_DIR
# ---------------------------------------------------------------------------
EXTRACT_TMP_DIR="$UBUNCH_DIR/iso_extracted"
ISO_URL="https://mirror.imt-systems.com/ubuntu/24.04.2/$ORIGINAL_IMAGE"
EFI_DIR="$EXTRACT_TMP_DIR/EFI/boot"
EFI_IMG="$UBUNCH_DIR/efi.img"
EFI_TEMP="$UBUNCH_DIR/efi-temp"
TPM_STATE="$UBUNCH_DIR/tpm_state"
DISK_IMG="$UBUNCH_DIR/primary_disc.img"
GRUB_DIR="$EXTRACT_TMP_DIR/boot/grub"
THEME_DIR="$GRUB_DIR/themes/grub2-theme"
REPO_DEST="$EXTRACT_TMP_DIR/srv"
ISO_OUTPUT="$UBUNCH_DIR/${ISO_OUT}.iso"
OVMF_DIR="$UBUNCH_DIR/OVMF"
OVMF_CODE="$OVMF_DIR/OVMF_CODE_4M.fd"
OVMF_VARS_ORIG="$OVMF_DIR/OVMF_VARS_4M.fd"
OVMF_VARS_RUN="$UBUNCH_DIR/OVMF_VARS_runtime.fd"
ISO_FILE="$UBUNCH_DIR/$ORIGINAL_IMAGE"

# ---------------------------------------------------------------------------
# Cleanup iniziale artifacts precedenti (non l'ISO sorgente)
# ---------------------------------------------------------------------------
echo "[+] Cleaning previous build artifacts..."
rm -rf "$EFI_TEMP" "$EFI_IMG" "$TPM_STATE" "$EXTRACT_TMP_DIR"
rm -f  "$DISK_IMG" "$OVMF_VARS_RUN" "$ISO_OUT.iso"

# ---------------------------------------------------------------------------
# Trap: cleanup su EXIT — registrato subito, gestisce anche swtpm
# ---------------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    echo "[+] Cleanup on exit (code: $exit_code)..."

    if [[ -f "$TPM_STATE/swtpm.pid" ]]; then
        local swtpm_pid
        swtpm_pid="$(cat "$TPM_STATE/swtpm.pid" 2>/dev/null || true)"
        if [[ -n "$swtpm_pid" ]] && ps -p "$swtpm_pid" > /dev/null 2>&1; then
            echo "    Terminating swtpm (PID $swtpm_pid)..."
            kill -TERM "$swtpm_pid" 2>/dev/null || true
            sleep 3
            if ps -p "$swtpm_pid" > /dev/null 2>&1; then
                echo "    Force killing swtpm (PID $swtpm_pid)..."
                kill -9 "$swtpm_pid" 2>/dev/null || true
            fi
        else
            echo "    swtpm already terminated."
        fi
    fi

    rm -rf "$EFI_TEMP" "$EFI_IMG" "$TPM_STATE" "$EXTRACT_TMP_DIR"
    rm -f  "$DISK_IMG" "$OVMF_VARS_RUN" "$ISO_OUT.iso"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# 1. Download ISO sorgente (se non gia' presente)
# ---------------------------------------------------------------------------
echo "[+] Checking ISO: $ORIGINAL_IMAGE ..."
if [[ -f "$ISO_FILE" ]]; then
    echo "    ISO already available, skipping download."
else
    echo "    Downloading ISO from $ISO_URL ..."
    curl -L --progress-bar -o "$ISO_FILE" "$ISO_URL"
fi

# ---------------------------------------------------------------------------
# 2. Estrai ISO
# ---------------------------------------------------------------------------
echo "[+] Extracting ISO to $EXTRACT_TMP_DIR ..."
mkdir -p "$EXTRACT_TMP_DIR"
xorriso -osirrox on -indev "$ISO_FILE" -extract / "$EXTRACT_TMP_DIR"
# xorriso estrae in sola lettura — rendi tutto scrivibile
chmod -R u+w "$EXTRACT_TMP_DIR"

# ---------------------------------------------------------------------------
# 3. Copia repo locale nell'albero ISO
# ---------------------------------------------------------------------------
echo "[+] Copying local repo into ISO..."
rm -rf "$REPO_DEST"
mkdir -p "$REPO_DEST"
cp -a "$REPO_BUILD_DIR" "$REPO_DEST/"

# ---------------------------------------------------------------------------
# 4. GRUB theme
# ---------------------------------------------------------------------------
echo "[+] Creating GRUB theme..."
mkdir -p "$THEME_DIR"
cp "$UBUNCH_DIR/linux-scaled.jpg" "$THEME_DIR/"

cat > "$THEME_DIR/theme.txt" << 'EOF'
desktop-color: "#FFFFFF"
desktop-image: "linux-scaled.jpg"

title-text: ""

+ label {
    text = "Welcome to Ubunch Linux OS Installer"
    left = 0
    top = 8%
    width = 100%
    height = 80
    align = "center"
    color = "#000000"
}

+ boot_menu {
    left = 5%
    top = 30%
    width = 60%
    height = 40%
    item_color = "#000000"
    selected_item_color = "#FF0000"
    item_height = 32
    item_spacing = 8
    item_padding = 10
    icon_width = 32
    icon_height = 32
}
EOF

# ---------------------------------------------------------------------------
# 5. GRUB config
# ---------------------------------------------------------------------------
echo "[+] Creating grub.cfg..."
mkdir -p "$GRUB_DIR"

cat > "$GRUB_DIR/grub.cfg" << EOF
insmod all_video
insmod gfxterm
insmod jpeg
terminal_output gfxterm
set gfxmode=auto
set gfxpayload=keep
set theme=(cd0)/boot/grub/themes/grub2-theme/theme.txt
set default=0
set timeout=-1

menuentry "Install Ubunch Linux + GRUB2 [offline] - ($RELEASE)" {
    clear
    echo ""
    echo "========================================================================="
    echo "        Ubunch Linux OS - Offline Automated Installation                 "
    echo "========================================================================="
    echo ""
    echo "  - Wait until the machine powers off completely"
    echo ""
    sleep 5
    set gfxpayload=keep
    set root=(cd0)
    linux  /casper/vmlinuz quiet autoinstall ds=nocloud\;s=/cdrom/base-os-offline-grub2/
    initrd /casper/initrd
}

menuentry "Install Ubunch Linux + GRUB2 [online] - ($RELEASE)" {
    clear
    echo ""
    echo "========================================================================="
    echo "        Ubunch Linux OS - Online Automated Installation                  "
    echo "========================================================================="
    echo ""
    echo "  - Wait until the machine powers off completely"
    echo ""
    sleep 5
    set gfxpayload=keep
    set root=(cd0)
    linux  /casper/vmlinuz quiet autoinstall ds=nocloud\;s=/cdrom/base-os-online-grub2/
    initrd /casper/initrd
}

menuentry "Install Ubunch Linux + systemd-boot [offline] - ($RELEASE)" {
    clear
    echo ""
    echo "========================================================================="
    echo "        Ubunch Linux OS - Offline Automated Installation                 "
    echo "========================================================================="
    echo ""
    echo "  - Wait until the machine powers off completely"
    echo ""
    sleep 5
    set gfxpayload=keep
    set root=(cd0)
    linux  /casper/vmlinuz quiet autoinstall ds=nocloud\;s=/cdrom/base-os-offline-systemd-boot/
    initrd /casper/initrd
}

menuentry "Install Ubunch Linux + systemd-boot [online] - ($RELEASE)" {
    clear
    echo ""
    echo "========================================================================="
    echo "        Ubunch Linux OS - Offline Automated Installation                 "
    echo "========================================================================="
    echo ""
    echo "  - Wait until the machine powers off completely"
    echo ""
    sleep 5
    set gfxpayload=keep
    set root=(cd0)
    linux  /casper/vmlinuz quiet autoinstall ds=nocloud\;s=/cdrom/base-os-online-systemd-boot/
    initrd /casper/initrd
}

menuentry "Enter UEFI Firmware" {
    echo "Entering BIOS Settings..."
    sleep 1
    fwsetup
}

menuentry "Reboot System" {
    echo "Rebooting..."
    sleep 1
    reboot
}
EOF

# ---------------------------------------------------------------------------
# 6. Genera bootx64.efi — unica fonte di verita' per il boot UEFI
#    grub-mkstandalone lo produce standalone (nessuna dipendenza esterna)
# ---------------------------------------------------------------------------
echo "[+] Generating bootx64.efi via grub-mkstandalone..."
mkdir -p "$EFI_DIR"

grub-mkstandalone \
    --format=x86_64-efi \
    --output="$EFI_DIR/bootx64.efi" \
    --locales="" \
    --fonts="" \
    "boot/grub/grub.cfg=$GRUB_DIR/grub.cfg"

# ---------------------------------------------------------------------------
# 7. Cloud-init user-data
# ---------------------------------------------------------------------------
echo "[+] Setting up cloud-init configs..."
mkdir -p "$EXTRACT_TMP_DIR/ubunch-data"

# Keyfile temporaneo per LUKS — generato fresh ad ogni build
dd if=/dev/urandom of="$EXTRACT_TMP_DIR/ubunch-data/temp_keyfile" bs=512 count=1
chmod 600 "$EXTRACT_TMP_DIR/ubunch-data/temp_keyfile"

mkdir -p "$EXTRACT_TMP_DIR/base-os-offline-grub2"
touch    "$EXTRACT_TMP_DIR/base-os-offline-grub2/meta-data"
cp "$UBUNCH_DIR/os/base-os-offline-grub2" "$EXTRACT_TMP_DIR/base-os-offline-grub2/user-data"

mkdir -p "$EXTRACT_TMP_DIR/base-os-online-grub2"
touch    "$EXTRACT_TMP_DIR/base-os-online-grub2/meta-data"
cp "$UBUNCH_DIR/os/base-os-online-grub2" "$EXTRACT_TMP_DIR/base-os-online-grub2/user-data"

mkdir -p "$EXTRACT_TMP_DIR/base-os-offline-systemd-boot"
touch    "$EXTRACT_TMP_DIR/base-os-offline-systemd-boot/meta-data"
cp "$UBUNCH_DIR/os/base-os-offline-systemd-boot" "$EXTRACT_TMP_DIR/base-os-offline-systemd-boot/user-data"

mkdir -p "$EXTRACT_TMP_DIR/base-os-online-systemd-boot"
touch    "$EXTRACT_TMP_DIR/base-os-online-systemd-boot/meta-data"
cp "$UBUNCH_DIR/os/base-os-online-systemd-boot" "$EXTRACT_TMP_DIR/base-os-online-systemd-boot/user-data"

# ---------------------------------------------------------------------------
# 8. Partizione EFI (efi.img, 200MB)
#
#    efi-temp/EFI/boot/bootx64.efi  ← copiato dal passo 6 (stessa fonte)
#    efi.img  ← immagine FAT32, usata da xorriso come partizione EFI GPT
#    iso_extracted/EFI/boot/bootx64.efi ← per boot ISO9660/El Torito legacy
#
#    Entrambi i bootx64.efi sono identici perche' derivano dallo stesso file.
# ---------------------------------------------------------------------------
echo "[+] Building EFI partition image (200MB)..."
mkdir -p "$EFI_TEMP/EFI/boot"
cp "$EFI_DIR/bootx64.efi" "$EFI_TEMP/EFI/boot/"

dd if=/dev/zero of="$EFI_IMG" bs=1M count=200
mkfs.vfat -n "EFI_PART" "$EFI_IMG"
mcopy -i "$EFI_IMG" -s "$EFI_TEMP"/* ::

cp "$EFI_IMG" "$EXTRACT_TMP_DIR/"

# ---------------------------------------------------------------------------
# 9. Ripacchetta ISO
# ---------------------------------------------------------------------------
echo "[+] Repacking ISO -> $ISO_OUTPUT ..."
xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "$ISO_LABEL" \
    -output "$ISO_OUTPUT" \
    -eltorito-boot boot/grub/i386-pc/eltorito.img \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -eltorito-alt-boot -e efi.img -no-emul-boot \
    -isohybrid-gpt-basdat \
    "$EXTRACT_TMP_DIR"

echo "[+] ISO ready: $ISO_OUTPUT"

# ---------------------------------------------------------------------------
# 10. Boot in QEMU con UEFI + TPM2 (opzionale)
#
#     Modalita' rilevata automaticamente in base all'esistenza del disco:
#
#     DISK_IMG non esiste → prima installazione:
#       - crea disco virtuale
#       - monta ISO come cdrom
#       - OVMF_VARS_RUN creata fresca
#       - boota dall'ISO per avviare l'installer
#
#     DISK_IMG esiste → boot post-install:
#       - non ricrea il disco
#       - niente cdrom
#       - OVMF_VARS_RUN riutilizzata (contiene entry EFI scritte da bootctl)
#       - boota direttamente dal disco installato
#
#     OVMF_VARS_RUN non viene mai cancellata dal trap cleanup() ne' dalla
#     pulizia iniziale — vive quanto DISK_IMG. Per reinstallare da zero,
#     cancellare entrambi manualmente.
#
# ---------------------------------------------------------------------------
if [[ "$RUN_IN_QEMU" == true ]]; then

    if [[ ! -f "$OVMF_CODE" ]]; then
        echo "ERROR: OVMF firmware not found at $OVMF_CODE"
        exit 1
    fi

    if [[ ! -f "$OVMF_VARS_ORIG" ]]; then
        echo "ERROR: OVMF_VARS_4M.fd non trovato in $OVMF_DIR"
        echo "       Esegui: cp /usr/share/OVMF/OVMF_VARS_4M.fd $OVMF_DIR/"
        exit 1
    fi

    # ------------------------------------------------------------------
    # OVMF VARS — crea fresca solo al primo run
    # ------------------------------------------------------------------
    if [[ ! -f "$OVMF_VARS_RUN" ]]; then
        echo "[+] Fresh VARS copy (first run)..."
        cp "$OVMF_VARS_ORIG" "$OVMF_VARS_RUN"
    else
        echo "[+] Reusing existing VARS (post-install boot)..."
    fi

    OVMF_PFLASH_ARGS=(
        -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}"
        -drive "if=pflash,format=raw,file=${OVMF_VARS_RUN}"
    )

    # ------------------------------------------------------------------
    # Rileva modalita': install o boot
    # ------------------------------------------------------------------
    QEMU_EXTRA_ARGS=()

    if [[ ! -f "$DISK_IMG" ]]; then
        echo "[+] Disk not found — install mode (ISO + fresh disk)..."
        qemu-img create -f qcow2 -o preallocation=metadata "$DISK_IMG" 500G
        QEMU_EXTRA_ARGS=(
            -boot once=d
            -cdrom "$ISO_OUTPUT"
        )
    else
        echo "[+] Disk found — boot mode (no ISO, boot from disk)..."
        # Niente cdrom, niente -boot → UEFI boota dalla NVRAM
    fi

    # ------------------------------------------------------------------
    # TPM2
    # ------------------------------------------------------------------
    echo "[+] Starting TPM2 emulator..."
    mkdir -p "$TPM_STATE"

    swtpm socket \
        --tpmstate dir="$TPM_STATE" \
        --ctrl type=unixio,path="$TPM_STATE/swtpm-sock" \
        --log file="$TPM_STATE/swtpm.log",level=20 \
        --tpm2 \
        --pid file="$TPM_STATE/swtpm.pid" \
        --flags startup-clear \
        --daemon

    sleep 1
    SWTPM_PID="$(cat "$TPM_STATE/swtpm.pid")"
    echo "    swtpm started with PID $SWTPM_PID"

    # ------------------------------------------------------------------
    # QEMU
    # ------------------------------------------------------------------
    echo "[+] Booting QEMU (UEFI + TPM2)..."
    qemu-system-x86_64 \
        -m 4096 \
        -enable-kvm \
        -cpu host,-svm \
        -drive "file=${DISK_IMG},format=qcow2,if=virtio,cache=none,aio=threads,discard=unmap" \
        "${OVMF_PFLASH_ARGS[@]}" \
        "${QEMU_EXTRA_ARGS[@]+"${QEMU_EXTRA_ARGS[@]}"}" \
        -netdev user,id=n1 \
        -device e1000,netdev=n1 \
        -chardev socket,id=chrtpm,path="$TPM_STATE/swtpm-sock" \
        -tpmdev emulator,id=tpm0,chardev=chrtpm \
        -device tpm-crb,tpmdev=tpm0

    echo "[+] QEMU session ended."
    # Il trap cleanup() gestisce la terminazione di swtpm e il cleanup
fi