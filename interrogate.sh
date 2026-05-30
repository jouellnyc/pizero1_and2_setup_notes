#!/bin/bash

# Pi Zero 1 SD card interrogation and fix script
# Checks every relevant file and fixes what is broken
# Usage: sudo bash pizero1_interrogate.sh [bootfs_path] [rootfs_path]
#
# Example:
#   sudo bash pizero1_interrogate.sh /media/john/bootfs /media/john/rootfs

# ─── Config ───────────────────────────────────────────────────────────────────
SSID=""
WIFI_PASSWORD=""
COUNTRY="US"
PI_PASSWORD="ubuntu"
HOSTNAME="pizero1"
# ─────────────────────────────────────────────────────────────────────────────

BOOTFS="${1:-/media/john/bootfs}"
ROOTFS="${2:-/media/john/rootfs}"

PASS=0
FAIL=0

ok()   { echo "  [OK]  $1"; ((PASS++)); }
bad()  { echo "  [!!]  $1"; ((FAIL++)); }
fix()  { echo "  [FIX] $1"; }
info() { echo "  [..] $1"; }
hr()   { echo "────────────────────────────────────────────────────"; }

echo ""
hr
echo " Pi Zero 1 SD Card Interrogation"
hr
echo ""

# ─── Check mount points ───────────────────────────────────────────────────────
echo "[ Mount Points ]"
if [ -d "$BOOTFS" ]; then
    ok "Boot partition found at $BOOTFS"
else
    bad "Boot partition NOT found at $BOOTFS"
    echo "      Is the card mounted? Try: lsblk"
    exit 1
fi

if [ -d "$ROOTFS" ]; then
    ok "Root partition found at $ROOTFS"
else
    bad "Root partition NOT found at $ROOTFS"
    echo "      Is sda2 mounted? Try: sudo mount /dev/sda2 /mnt/rootfs"
    exit 1
fi
echo ""

# ─── Check SSH file ───────────────────────────────────────────────────────────
echo "[ SSH ]"
if [ -f "$BOOTFS/ssh" ]; then
    ok "ssh file exists"
else
    bad "ssh file MISSING"
    fix "Creating ssh file..."
    touch "$BOOTFS/ssh"
    ok "ssh file created"
fi
echo ""

# ─── Check wpa_supplicant.conf ────────────────────────────────────────────────
echo "[ WiFi — wpa_supplicant.conf ]"
WPA="$BOOTFS/wpa_supplicant.conf"
if [ -f "$WPA" ]; then
    ok "wpa_supplicant.conf exists"
    # Check contents
    if grep -q "$SSID" "$WPA"; then
        ok "SSID '$SSID' found in config"
    else
        bad "SSID '$SSID' NOT found in config"
        info "Current contents:"
        cat "$WPA" | sed 's/^/        /'
        fix "Rewriting wpa_supplicant.conf..."
        cat > "$WPA" << EOF
country=$COUNTRY
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="$SSID"
    psk="$WIFI_PASSWORD"
    key_mgmt=WPA-PSK
}
EOF
        ok "wpa_supplicant.conf rewritten"
    fi
    if grep -q "country=$COUNTRY" "$WPA"; then
        ok "Country code '$COUNTRY' set"
    else
        bad "Country code missing"
        fix "Adding country code..."
        sed -i "1s/^/country=$COUNTRY\n/" "$WPA"
        ok "Country code added"
    fi
else
    bad "wpa_supplicant.conf MISSING"
    fix "Creating wpa_supplicant.conf..."
    cat > "$WPA" << EOF
country=$COUNTRY
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="$SSID"
    psk="$WIFI_PASSWORD"
    key_mgmt=WPA-PSK
}
EOF
    ok "wpa_supplicant.conf created"
fi
echo ""
info "Final wpa_supplicant.conf:"
cat "$WPA" | sed 's/^/        /'
echo ""

# ─── Check hostname ───────────────────────────────────────────────────────────
echo "[ Hostname ]"
if [ -f "$ROOTFS/etc/hostname" ]; then
    CURRENT_HOSTNAME=$(cat "$ROOTFS/etc/hostname")
    info "Current hostname: '$CURRENT_HOSTNAME'"
    if [ "$CURRENT_HOSTNAME" = "$HOSTNAME" ]; then
        ok "Hostname is correct"
    else
        bad "Hostname is '$CURRENT_HOSTNAME', expected '$HOSTNAME'"
        fix "Setting hostname to '$HOSTNAME'..."
        echo "$HOSTNAME" > "$ROOTFS/etc/hostname"
        sed -i "s/$CURRENT_HOSTNAME/$HOSTNAME/g" "$ROOTFS/etc/hosts"
        ok "Hostname updated"
    fi
else
    bad "hostname file missing"
    fix "Creating hostname file..."
    echo "$HOSTNAME" > "$ROOTFS/etc/hostname"
    ok "Hostname set to '$HOSTNAME'"
fi
echo ""

# ─── Check /etc/shadow ────────────────────────────────────────────────────────
echo "[ Password — /etc/shadow ]"
SHADOW="$ROOTFS/etc/shadow"
if [ -f "$SHADOW" ]; then
    ok "shadow file exists"
    PI_LINE=$(grep "^pi:" "$SHADOW")
    if [ -n "$PI_LINE" ]; then
        ok "pi user found in shadow"
        info "Current pi shadow entry:"
        echo "        $PI_LINE"
        # Check if password is locked (* or !)
        PI_HASH=$(echo "$PI_LINE" | cut -d: -f2)
        if [ "$PI_HASH" = "*" ] || [ "$PI_HASH" = "!" ] || [ "$PI_HASH" = "!!" ]; then
            bad "pi password is LOCKED ('$PI_HASH') — login will fail"
            fix "Setting pi password to '$PI_PASSWORD'..."
            HASH=$(echo "$PI_PASSWORD" | openssl passwd -6 -stdin)
            sed -i "s|^pi:[^:]*:|pi:$HASH:|" "$SHADOW"
            ok "Password set"
            info "New pi shadow entry:"
            grep "^pi:" "$SHADOW" | sed 's/^/        /'
        else
            ok "pi password hash looks set (not locked)"
            info "Hash prefix: $(echo $PI_HASH | cut -c1-10)..."
            # Offer to reset anyway
            fix "Resetting pi password to '$PI_PASSWORD' to be sure..."
            HASH=$(echo "$PI_PASSWORD" | openssl passwd -6 -stdin)
            sed -i "s|^pi:[^:]*:|pi:$HASH:|" "$SHADOW"
            ok "Password reset"
            info "New pi shadow entry:"
            grep "^pi:" "$SHADOW" | sed 's/^/        /'
        fi
    else
        bad "pi user NOT found in shadow!"
        info "Users in shadow:"
        cut -d: -f1 "$SHADOW" | sed 's/^/        /'
    fi
else
    bad "shadow file NOT found at $SHADOW"
fi
echo ""

# ─── Check cmdline.txt ────────────────────────────────────────────────────────
echo "[ cmdline.txt ]"
CMDLINE="$BOOTFS/cmdline.txt"
if [ -f "$CMDLINE" ]; then
    ok "cmdline.txt exists"
    info "Contents: $(cat $CMDLINE)"
else
    bad "cmdline.txt MISSING — card may not boot"
fi
echo ""

# ─── Check config.txt ─────────────────────────────────────────────────────────
echo "[ config.txt ]"
CONFIG="$BOOTFS/config.txt"
if [ -f "$CONFIG" ]; then
    ok "config.txt exists"
else
    bad "config.txt MISSING — card may not boot"
fi
echo ""

# ─── Check kernel ─────────────────────────────────────────────────────────────
echo "[ Kernel ]"
if [ -f "$BOOTFS/kernel.img" ]; then
    ok "kernel.img found (32-bit ARMv6 — correct for Pi Zero 1)"
else
    bad "kernel.img NOT found — wrong image for Pi Zero 1?"
fi
if [ -f "$BOOTFS/kernel8.img" ]; then
    info "kernel8.img also present (64-bit — not used on Pi Zero 1)"
fi
echo ""

# ─── Summary ─────────────────────────────────────────────────────────────────
hr
echo " Summary"
hr
echo "  Passed : $PASS"
echo "  Fixed  : $FAIL"
echo ""

echo "==> Syncing writes to disk..."
sync
echo ""
echo "Now unmount both partitions:"
echo "  sudo umount $BOOTFS"
echo "  sudo umount $ROOTFS"
echo ""
echo "Insert card into Pi Zero 1 and power on."
echo "SSH with: ssh pi@$HOSTNAME.local"
echo "Password: $PI_PASSWORD"
echo ""


