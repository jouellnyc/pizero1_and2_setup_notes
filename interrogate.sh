#!/bin/bash

# Pi Zero SD card interrogation and fix script
# Supports Pi Zero 1 (Bullseye 32-bit) and Pi Zero 2W (Trixie 64-bit)
#
# Usage:
#   sudo bash pizero_interrogate.sh --zero1  [bootfs_path] [rootfs_path]
#   sudo bash pizero_interrogate.sh --zero2w [bootfs_path] [rootfs_path]
#
# Examples:
#   sudo bash pizero_interrogate.sh --zero1
#   sudo bash pizero_interrogate.sh --zero2w /media/user/bootfs /media/user/rootfs

# ─── Bail out if run with sh ──────────────────────────────────────────────────
if [ -z "$BASH_VERSION" ]; then
    echo "ERROR: Run this script with bash, not sh"
    echo "  sudo bash $0 --zero1|--zero2w"
    exit 1
fi

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
    echo ""
    echo "Usage: sudo bash $0 --zero1|--zero2w [bootfs_path] [rootfs_path]"
    echo ""
    echo "  --zero1   Pi Zero 1 (Bullseye 32-bit, pi user, wpa_supplicant)"
    echo "  --zero2w  Pi Zero 2W (Trixie 64-bit, ubuntu user, cloud-init)"
    echo ""
    echo "Defaults:"
    echo "  bootfs_path : /media/user/bootfs"
    echo "  rootfs_path : /media/user/rootfs"
    echo ""
    exit 1
}

# ─── Parse args ───────────────────────────────────────────────────────────────
BOARD=""
case "$1" in
    --zero1)  BOARD="zero1";  shift ;;
    --zero2w) BOARD="zero2w"; shift ;;
    *) usage ;;
esac

BOOTFS="${1:-/media/user/bootfs}"
ROOTFS="${2:-/media/user/rootfs}"

# ─── Config — edit these ──────────────────────────────────────────────────────
SSID="YourSSID"
WIFI_PASSWORD="YourPassword"
COUNTRY="US"

# Pi Zero 1
PI_USER="pi"
PI_PASSWORD="ubuntu"
PI_HOSTNAME="pizero1"

# Pi Zero 2W
ZW_USER="ubuntu"
ZW_PASSWORD="ubuntu"
ZW_HOSTNAME="pizero2w"
# ─────────────────────────────────────────────────────────────────────────────

PASS=0
FIXED=0
ERRORS=0

ok()   { echo "  [OK]  $1"; ((PASS++)); }
bad()  { echo "  [!!]  $1"; ((ERRORS++)); }
fix()  { echo "  [FIX] $1"; ((FIXED++)); }
info() { echo "  [..] $1"; }
hr()   { echo "────────────────────────────────────────────────────"; }

if [ "$BOARD" = "zero1" ]; then
    BOARD_LABEL="Pi Zero 1 (Bullseye 32-bit)"
    USERNAME="$PI_USER"
    PASSWORD="$PI_PASSWORD"
    HOSTNAME="$PI_HOSTNAME"
else
    BOARD_LABEL="Pi Zero 2W (Trixie 64-bit)"
    USERNAME="$ZW_USER"
    PASSWORD="$ZW_PASSWORD"
    HOSTNAME="$ZW_HOSTNAME"
fi

echo ""
hr
echo " $BOARD_LABEL SD Card Interrogation"
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

# ─── Check SSH ────────────────────────────────────────────────────────────────
echo "[ SSH ]"
if [ "$BOARD" = "zero1" ]; then
    if [ -f "$BOOTFS/ssh" ]; then
        ok "ssh file exists"
    else
        bad "ssh file MISSING"
        fix "Creating ssh file..."
        touch "$BOOTFS/ssh"
        ok "ssh file created"
    fi
else
    # 2W uses cloud-init user-data for SSH
    if [ -f "$BOOTFS/user-data" ]; then
        ok "user-data exists"
        if grep -q "ssh_pwauth: true" "$BOOTFS/user-data"; then
            ok "ssh_pwauth is enabled"
        else
            bad "ssh_pwauth not set to true in user-data"
            fix "Adding ssh_pwauth to user-data..."
            sed -i '/^#cloud-config/a ssh_pwauth: true' "$BOOTFS/user-data"
            ok "ssh_pwauth added"
        fi
        if grep -qE "^#" "$BOOTFS/user-data" | grep -q "chpasswd"; then
            bad "user-data appears to be all comments — customisation may not have written"
            info "Check user-data manually:"
            cat "$BOOTFS/user-data" | sed 's/^/        /'
        fi
    else
        bad "user-data MISSING"
    fi
fi
echo ""

# ─── Check WiFi ───────────────────────────────────────────────────────────────
echo "[ WiFi ]"
if [ "$BOARD" = "zero1" ]; then
    WPA="$BOOTFS/wpa_supplicant.conf"
    if [ -f "$WPA" ]; then
        ok "wpa_supplicant.conf exists"
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
else
    NC="$BOOTFS/network-config"
    if [ -f "$NC" ]; then
        ok "network-config exists"
        if grep -q "$SSID" "$NC"; then
            ok "SSID '$SSID' found in network-config"
        else
            bad "SSID '$SSID' NOT found — network-config may be all comments"
            info "Current contents:"
            cat "$NC" | sed 's/^/        /'
            fix "Rewriting network-config..."
            cat > "$NC" << EOF
network:
  version: 2
  wifis:
    wlan0:
      dhcp4: true
      optional: true
      access-points:
        "$SSID":
          password: "$WIFI_PASSWORD"
      regulatory-domain: $COUNTRY
EOF
            ok "network-config rewritten"
        fi
        if grep -q "regulatory-domain" "$NC"; then
            ok "regulatory-domain set"
        else
            bad "regulatory-domain missing from network-config"
        fi
    else
        bad "network-config MISSING"
    fi
    echo ""
    info "Final network-config:"
    cat "$NC" | sed 's/^/        /'
fi
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

# ─── Check password ───────────────────────────────────────────────────────────
echo "[ Password — /etc/shadow ]"
SHADOW="$ROOTFS/etc/shadow"
if [ -f "$SHADOW" ]; then
    ok "shadow file exists"
    USER_LINE=$(grep "^${USERNAME}:" "$SHADOW")
    if [ -n "$USER_LINE" ]; then
        ok "$USERNAME user found in shadow"
        info "Current shadow entry:"
        echo "        $USER_LINE"
        USER_HASH=$(echo "$USER_LINE" | cut -d: -f2)
        if [ "$USER_HASH" = "*" ] || [ "$USER_HASH" = "!" ] || [ "$USER_HASH" = "!!" ]; then
            bad "$USERNAME password is LOCKED ('$USER_HASH') — login will fail"
            fix "Setting $USERNAME password to '$PASSWORD'..."
            HASH=$(echo "$PASSWORD" | openssl passwd -6 -stdin)
            sed -i "s|^${USERNAME}:[^:]*:|${USERNAME}:$HASH:|" "$SHADOW"
            ok "Password set"
            info "New shadow entry:"
            grep "^${USERNAME}:" "$SHADOW" | sed 's/^/        /'
        else
            ok "$USERNAME password hash is set and not locked — leaving as-is"
            info "Hash prefix: $(echo $USER_HASH | cut -c1-10)..."
        fi
    else
        bad "$USERNAME user NOT found in shadow!"
        info "Users in shadow:"
        cut -d: -f1 "$SHADOW" | sed 's/^/        /'
    fi
else
    bad "shadow file NOT found at $SHADOW"
fi
echo ""

# ─── Check cmdline.txt ────────────────────────────────────────────────────────
echo "[ cmdline.txt ]"
if [ -f "$BOOTFS/cmdline.txt" ]; then
    ok "cmdline.txt exists"
    info "Contents: $(cat $BOOTFS/cmdline.txt)"
else
    bad "cmdline.txt MISSING — card may not boot"
fi
echo ""

# ─── Check config.txt ─────────────────────────────────────────────────────────
echo "[ config.txt ]"
if [ -f "$BOOTFS/config.txt" ]; then
    ok "config.txt exists"
else
    bad "config.txt MISSING — card may not boot"
fi
echo ""

# ─── Check kernel ─────────────────────────────────────────────────────────────
echo "[ Kernel ]"
if [ "$BOARD" = "zero1" ]; then
    if [ -f "$BOOTFS/kernel.img" ]; then
        ok "kernel.img found (32-bit ARMv6 — correct for Pi Zero 1)"
    else
        bad "kernel.img NOT found — wrong image for Pi Zero 1?"
    fi
    if [ -f "$BOOTFS/kernel8.img" ]; then
        info "kernel8.img also present (64-bit — not used on Pi Zero 1)"
    fi
else
    if [ -f "$BOOTFS/kernel8.img" ]; then
        ok "kernel8.img found (64-bit — correct for Pi Zero 2W)"
    else
        bad "kernel8.img NOT found — wrong image for Pi Zero 2W?"
    fi
    if [ -f "$BOOTFS/kernel.img" ]; then
        info "kernel.img also present (32-bit — not used on Pi Zero 2W)"
    fi
fi
echo ""

# ─── Summary ─────────────────────────────────────────────────────────────────
hr
echo " Summary"
hr
echo "  Passed : $PASS"
echo "  Fixed  : $FIXED"
echo "  Errors : $ERRORS"
echo ""

echo "==> Syncing writes to disk..."
sync
echo ""
echo "Now unmount both partitions:"
echo "  sudo umount $BOOTFS"
echo "  sudo umount $ROOTFS"
echo ""
echo "Insert card into $BOARD_LABEL and power on."
echo "SSH with: ssh ${USERNAME}@<ip>"
echo "          ssh ${USERNAME}@$HOSTNAME.local  (mDNS, may not work with Pi-hole DHCP)"
echo "Password: $PASSWORD"
echo ""

