#!/bin/bash
set -e

# ─────────────────────────────────────────────
# Vizoure NMS — ISO Builder
# Usage: bash build-iso.sh [version]
# ─────────────────────────────────────────────

VERSION="${1:-7.4.9}"
# Branch/tag baked into the ISO's GitHub fallback (ISS-34); default main.
VIZOURE_REF="${VIZOURE_REF:-main}"
REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
UBUNTU_ISO="packer/ubuntu-24.04.4-live-server-amd64.iso"
OUTPUT_ISO="dist/vizoure-nms-${VERSION}.iso"
WORK_DIR="/tmp/vizoure-iso"

echo "========================================="
echo "  Vizoure NMS ISO Builder"
echo "  Version: ${VERSION}"
echo "========================================="

mkdir -p "$WORK_DIR/source-files" dist

echo "[1/4] Extracting Ubuntu ISO..."
xorriso -osirrox on \
    -indev "$UBUNTU_ISO" \
    -extract / "$WORK_DIR/source-files" \
    2>/dev/null

echo "[2/4] Injecting Vizoure autoinstall config..."
mkdir -p "$WORK_DIR/source-files/vizoure"

# Local-first (Rule B): use this checkout's user-data; fall back to GitHub (-f: fail on 404).
if [ -f "$REPO_DIR/packer/http/user-data" ]; then
    cp "$REPO_DIR/packer/http/user-data" "$WORK_DIR/source-files/vizoure/user-data"
else
    curl -fsSL "https://raw.githubusercontent.com/sadiqawan/Vizoure/${VIZOURE_REF}/packer/http/user-data" \
        -o "$WORK_DIR/source-files/vizoure/user-data"
fi
# Pin the ref used by the autoinstall's GitHub fallback.
sed -i "s/VIZOURE_REF:-main/VIZOURE_REF:-${VIZOURE_REF}/" "$WORK_DIR/source-files/vizoure/user-data"

# Ship scripts/ + branding/ (incl. branding/header/*) ON the ISO so the install is
# local-first and does not depend on GitHub for branding. Fail the build if the
# manifest and branding/ disagree or the header files are missing.
bash "$REPO_DIR/scripts/dev/check-manifest.sh"
test -s "$REPO_DIR/branding/header/top-header.css" && test -s "$REPO_DIR/branding/header/top-header.js"
rm -rf "$WORK_DIR/source-files/vizoure/repo"
mkdir -p "$WORK_DIR/source-files/vizoure/repo"
cp -r "$REPO_DIR/scripts" "$REPO_DIR/branding" "$WORK_DIR/source-files/vizoure/repo/"
rm -rf "$WORK_DIR/source-files/vizoure/repo/scripts/dev"
touch "$WORK_DIR/source-files/vizoure/meta-data"

echo "[3/4] Customizing boot menu..."
cat > "$WORK_DIR/source-files/boot/grub/grub.cfg" << GRUBEOF
set timeout=10
loadfont unicode
set menu_color_normal=white/black
set menu_color_highlight=black/light-gray

menuentry "Install Vizoure NMS (Automated)" {
        set gfxpayload=keep
        linux   /casper/vmlinuz quiet autoinstall ds=nocloud\;s=/cdrom/vizoure/ ---
        initrd  /casper/initrd
}
menuentry "Install Vizoure NMS (Manual)" {
        set gfxpayload=keep
        linux   /casper/vmlinuz  ---
        initrd  /casper/initrd
}
grub_platform
if [ "\$grub_platform" = "efi" ]; then
menuentry 'Boot from next volume' {
        exit 1
}
menuentry 'UEFI Firmware Settings' {
        fwsetup
}
else
menuentry 'Test memory' {
        linux16 /boot/memtest86+x64.bin
}
fi
GRUBEOF

echo "[4/4] Building ISO..."
dd if="$UBUNTU_ISO" bs=1 count=432 of="$WORK_DIR/boot.mbr" 2>/dev/null

xorriso -as mkisofs \
    -r \
    -V "Vizoure NMS ${VERSION}" \
    -o "$OUTPUT_ISO" \
    --grub2-mbr "$WORK_DIR/boot.mbr" \
    --protective-msdos-label \
    -partition_cyl_align off \
    -partition_offset 16 \
    --mbr-force-bootable \
    -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b \
        "$WORK_DIR/source-files/boot/grub/i386-pc/eltorito.img" \
    -appended_part_as_gpt \
    -iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7 \
    -c '/boot.catalog' \
    -b '/boot/grub/i386-pc/eltorito.img' \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    --grub2-boot-info \
    -eltorito-alt-boot \
    -e '--interval:appended_partition_2:::' \
    -no-emul-boot \
    "$WORK_DIR/source-files" 2>&1 | tail -5

ls -lh "$OUTPUT_ISO"
echo ""
echo "========================================="
echo "  ISO built: $OUTPUT_ISO"
echo "========================================="
