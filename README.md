# Raspberry Pi Zero 1 & 2W — Setup Guide

A real-world account of getting two different Pi Zero generations booted, configured, and on the network.

I feel like I do this every 6 months or so ("Hey!, I'll just boot that pizero real quick!")... and never fully, properly document for future me...

---

## Quick Reference

| | Pi Zero 2W | Pi Zero 1 |
|---|---|---|
| CPU | ARM Cortex-A53, quad core | ARM1176, single core |
| Architecture | ARMv8 (64-bit capable) | ARMv6 |
| RAM | 512MB | 512MB |
| WiFi | BCM43436 onboard | BCM43438 onboard |
| USB | micro-USB OTG | micro-USB OTG |
| Recommended OS | Pi OS Lite 64-bit (Trixie) | Pi OS Lite 32-bit (Bullseye) |
| Default user | `ubuntu` | `pi` |
| Config method | cloud-init `user-data` + `network-config` | `wpa_supplicant.conf` + `ssh` file |
| Boot time | Moderate (~1-2 min first boot) | Slow (~2-3 min first boot) |
| Power needed | 5V / 2.5A recommended | 5V / 1A minimum |

---

## Step 1 — Flash the Card

Use **Raspberry Pi Imager**.

### Pi Zero 1
- Device: `Raspberry Pi Zero`
- OS: `Raspberry Pi OS (other)` and then `Raspberry Pi OS Lite Legacy (32-bit)`

### Pi Zero 2W
- Device: `Raspberry Pi Zero 2 W`
- OS: `Raspberry Pi OS Lite (64-bit)`

### Imager Customisation Screen
When prompted **"Would you like to apply OS customisation?"** click **Edit Settings** and configure:
- Hostname
- Username / password
- WiFi SSID, password, and country code
- Enable SSH

**Do not trust that it worked.** Always verify the card contents after flashing (see Step 2).

### After Imager Finishes
Imager auto-unmounts — wait for the **"Remove the SD card"** message before touching it.

---

## Step 2 — Verify the Card

Mount the card and check contents before inserting in the Pi.

```bash
ls /media/user/bootfs/
```

### Pi Zero 1 — what you need:
```
ssh                    # empty file, enables SSH
wpa_supplicant.conf    # WiFi credentials
kernel.img             # 32-bit ARMv6 kernel (must exist)
cmdline.txt
config.txt
```

### Pi Zero 2W — what you need:
```
user-data              # cloud-init user/SSH config
network-config         # cloud-init WiFi config
kernel8.img            # 64-bit kernel (must exist)
cmdline.txt
config.txt
```

---

## Step 3 — Manual Fixes (Pi Zero 1)

Imager often skips writing WiFi/SSH config. Do it manually.

### Enable SSH
```bash
touch /media/user/bootfs/ssh
```

### WiFi Config
```bash
sudo nano /media/user/bootfs/wpa_supplicant.conf
```
```
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="YourSSID"
    psk="YourPassword"
    key_mgmt=WPA-PSK
}
```

### Set Password via /etc/shadow

The `pi` user has no default password on Bullseye. Set it directly:

```bash
# Generate hash (will look different every time due to random salting — that is normal)
echo 'yourpassword' | openssl passwd -6 -stdin

# Edit shadow
sudo nano /media/user/rootfs/etc/shadow
```

Find the `pi:` line and replace the field between the first and second `:` with your hash:
```
pi:$6$<your hash here>:19000:0:99999:7:::
```

### Set Hostname
```bash
echo "pizero1" | sudo tee /media/user/rootfs/etc/hostname
sudo sed -i "s/raspberrypi/pizero1/g" /media/user/rootfs/etc/hosts
```

---

## Step 3 — Manual Fixes (Pi Zero 2W)

### Verify cloud-init files are not all commented out
```bash
cat /media/user/bootfs/network-config
cat /media/user/bootfs/user-data
```

If everything is commented out, rewrite them:

```bash
sudo nano /media/user/bootfs/network-config
```
```yaml
network:
  version: 2
  wifis:
    wlan0:
      dhcp4: true
      optional: true
      access-points:
        "YourSSID":
          password: "YourPassword"
      regulatory-domain: US
```

```bash
sudo nano /media/user/bootfs/user-data
```
```yaml
#cloud-config
hostname: pizero2w
ssh_pwauth: true
chpasswd:
  list: |
    ubuntu:ubuntu
  expire: false
```

---

## Step 4 — Sync and Unmount

Always do this before pulling the card:

```bash
sync
sudo umount /media/user/bootfs
sudo umount /media/user/rootfs
```

Never pull the card without syncing — unclean unmount causes filesystem corruption and boot failures.

---

## Step 5 — Boot and Connect

Insert card, connect power. HDMI must be plugged in before power if using a display — Pi Zero does not hotplug HDMI.

### Power Requirements
- 5V / 1A minimum (Pi Zero 1)
- 5V / 2.5A recommended (Pi Zero 2W)
- Use a proper wall adapter — USB hub ports (500mA) are not enough
- Cable quality matters — cheap thin cables cause voltage drop

### LED Blink Codes

| Pattern | Meaning |
|---------|---------|
| 3 blinks | General boot failure |
| 7 blinks | Kernel not found (wrong image for board) |
| Constant | Booted successfully |

7 blinks on Pi Zero 1 with a 64-bit image means the 64-bit kernel (`kernel8.img`) will not run on ARMv6. Always use 32-bit image on Pi Zero 1. Easy to fat-finger and flash the wrong image.

### First Boot is Slow
- Pi Zero 1: 2-3 minutes
- Pi Zero 2W: 1-2 minutes

Wait the full time before concluding it is not working.

### Rainbow Screen on HDMI (Pi Zero 2W)
Not a failure. The 64-bit image with cloud-init takes time to initialize the display. SSH is often already working while HDMI still shows the rainbow. Check the network before panicking.

### Find the Pi on the Network
```bash
# mDNS
ping pizero1.local

# Scan subnet
nmap -sn 192.168.0.0/24

# If using Pi-hole DHCP — check the admin panel leases
```

### SSH In
```bash
# Pi Zero 1
ssh pi@pizero1.local

# Pi Zero 2W
ssh ubuntu@pizero2w.local
```

---

## Step 6 — Post-Boot Setup

### Change Hostname Permanently
```bash
sudo hostnamectl set-hostname <newhostname>
sudo nano /etc/hosts
# update the 127.0.1.1 line
sudo reboot
```

If using Pi-hole DHCP, the new hostname will appear in the leases panel after reboot.

### Update Packages
```bash
sudo apt update && sudo apt upgrade -y
```

Pi Zero 1 is slow — this can take 10-15 minutes. Let it run.

### Regenerate SSH Host Keys (after cloning)
If you cloned a card, regenerate keys so each Pi has a unique identity:
```bash
sudo rm /etc/ssh/ssh_host_*
sudo dpkg-reconfigure openssh-server
sudo reboot
```

---

## Automation — Interrogation Script

Use `pizero1_interrogate.sh` to verify and fix a Pi Zero 1 card automatically:

```bash
sudo bash pizero1_interrogate.sh /media/user/bootfs /media/user/rootfs
```

Checks and fixes: SSH file, WiFi config, hostname, password hash, kernel, cmdline.txt, config.txt. Prints verbose pass/fail for each item. Run with `bash`, not `sh`.

---

## Cloning Cards

Always shut down the Pi cleanly before pulling the card:
```bash
sudo shutdown -h now
```

Card-to-card clone, no gzip:
```bash
sudo dd if=/dev/sda of=/dev/sdb bs=4M status=progress conv=noerror
sync
```

- Destination card must be same size or larger than source
- Never pipe through gzip for a card-to-card clone — it writes a compressed stream, not a bootable image
- After cloning, change the hostname on the second Pi to avoid conflicts

---

## Common Gotchas

| Problem | Cause | Fix |
|---------|-------|-----|
| Rainbow screen stuck | Normal on 2W during cloud-init | SSH in, ignore rainbow |
| 7 LED blinks | Wrong kernel for board | Use 32-bit OS on Zero 1, 64-bit on Zero 2W |
| Can't SSH | SSH not enabled | Add empty `ssh` file to boot partition |
| Can't login | Password locked in shadow | Edit `/etc/shadow` directly |
| Not on network | WiFi config not written | Check/rewrite `wpa_supplicant.conf` or `network-config` |
| nmtui shows no connections | NM uses netplan files, not its own store | Edit `/etc/netplan/` directly |
| Filesystem corruption | Card pulled without sync/umount | Always `sync` + `umount` before pulling |
| Clone won't boot | Destination card slightly smaller | Reflash from scratch instead of cloning |

---

## OS Choice — Trixie vs Bullseye on Pi Zero 1

Raspberry Pi OS Trixie (current) did not work reliably on Pi Zero 1:
- Cloud-init WiFi config (`network-config`) was ignored
- `wpa_supplicant.conf` method also failed intermittently

Raspberry Pi OS Bullseye (Legacy 32-bit) worked:
- Available in Pi Imager under "Raspberry Pi OS (other)" and then "Raspberry Pi OS Lite Legacy (32-bit)"
- Uses older, simpler boot config — more compatible with the BCM43438 WiFi chip
- Recommended for Pi Zero 1

---

## Serial Console Debugging

When SSH and HDMI both fail.

### Hardware
- USB-to-TTL serial adapter (3.3V only — 5V will damage the Pi)
- Common chipsets: PL2303, CP2102, CH340, FTDI

### Wiring (Pi Zero GPIO)
```
Pi Pin 6  (GND)  adapter GND
Pi Pin 8  (TXD)  adapter RX
Pi Pin 10 (RXD)  adapter TX
```

Do NOT connect adapter 5V/VCC — power the Pi separately.

### Enable UART
Add to `/media/user/bootfs/config.txt`:
```
enable_uart=1
dtoverlay=disable-bt
```

### Connect from Desktop
```bash
# Find the adapter
dmesg | tail -10
# Look for ttyUSB0 or ttyACM0

# Connect
screen /dev/ttyUSB0 115200
# or
sudo minicom -D /dev/ttyUSB0 -b 115200
# In minicom: Ctrl+A Z  O  Serial port setup  Hardware FC: No, Software FC: No
```

---

## Dual WiFi Failover (Pi Zero 2W)

See [pizero2w_dual_wifi](https://github.com/jouellnyc/pizero2w_dual_wifi) for the full setup with RTL8188FU USB adapter and automatic metric-based failover between `wlan0` and `wlan1`.

---

## Key Lessons

- Always verify card contents after flashing — Pi Imager can silently skip customisation
- Pi Zero 1 and 2W are not compatible — different CPU architecture, different kernels, different OS requirements
- Trixie + Pi Zero 1 = trouble — use Bullseye Legacy for Zero 1
- Rainbow screen is not always failure on 2W — check the network before panicking
- Card cloning — never pipe through gzip when doing card-to-card clone; use plain `dd`
- Power — use a real 5V/2.5A wall adapter, not a hub port
- `/etc/shadow` direct edit is more reliable than `userconf.txt` for setting passwords on Bullseye
- Salted password hashes look different every time but all work — this is normal and correct

