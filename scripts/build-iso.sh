#!/bin/bash
set -e

# ─────────────────────────────────────────────
# Vizoure NMS — ISO Builder
# Usage: bash build-iso.sh [version]
# ─────────────────────────────────────────────

VERSION="${1:-7.4.9}"
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

curl -sSL "https://raw.githubusercontent.com/sadiqawan/Vizoure/main/packer/http/user-data" \
    -o "$WORK_DIR/source-files/vizoure/user-data"
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
