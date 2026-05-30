
# Raspberry Pi Zero 1 & 2W — Setup Adventure

A real-world account of getting two different Pi Zero generations booted, configured, and on the network. 

I feel like I do this every 6 months or so ('Hey!, I'll just boot that pizero real quick!")... and never fully, properly document for future me...

## Hardware

| | Pi Zero 2W | Pi Zero 1 |
|---|---|---|
| CPU | ARM Cortex-A53, quad core | ARM1176, single core |
| Architecture | ARMv8 (64-bit capable) | ARMv6 |
| RAM | 512MB | 512MB |
| WiFi | BCM43436 onboard | BCM43438 onboard |
| USB | micro-USB OTG | micro-USB OTG |
| OS | Pi OS Lite 64-bit (Trixie) | Pi OS Lite 32-bit (Bullseye) |

---

## Pi Zero 2W

### What Worked
- Flashed **Raspberry Pi OS Lite 64-bit** via Pi Imager
- Pi Imager customisation screen set WiFi, SSH, username/password
- Booted first try, SSH accessible via `ubuntu@pizero2w.local`

### Gotchas

**Rainbow screen on HDMI** — not actually a failure. The 64-bit image with cloud-init takes time to initialize display. SSH was working fine while HDMI showed rainbow. Don't panic.

**HDMI must be connected before power** — Pi Zero doesn't hotplug HDMI. Plug display in first, then power.

**Power supply matters** — USB hub ports (500mA) are not enough. Pi Zero 2W needs 5V/1A minimum, 5V/2.5A recommended. 

**nmtui couldn't see WiFi connections** — Pi OS uses netplan-generated config files in `/etc/netplan/90-NM-*.yaml` rather than `/etc/NetworkManager/system-connections/`. nmtui reads NM's on-disk store which is empty. The configs are there, just not where nmtui looks.

**Cloud-init `user-data` all commented out** — Pi Imager silently skipped writing customisation. Always verify after flashing:
```bash
cat /media/user/bootfs/user-data
cat /media/user/bootfs/network-config
```

If everything is commented out, write them manually before booting.

### Manual Cloud-Init Fix

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

```bash
sync
sudo umount /media/user/bootfs
sudo umount /media/user/rootfs
```

---

## Pi Zero 2W — Dual WiFi Failover

See [README.md](https://github.com/jouellnyc/pizero2w_dual_wifi) for the full dual WiFi setup with RTL8188FU USB adapter and automatic metric-based failover.

---

## Pi Zero 1

### OS Choice — Trixie (Current) vs Bullseye (Legacy)

**Raspberry Pi OS Trixie (current) — did not work reliably on Pi Zero 1:**
- Cloud-init WiFi config (`network-config`) was ignored
- `wpa_supplicant.conf` method also failed
- Not recommended for Pi Zero 1

**Raspberry Pi OS Bullseye (Legacy 32-bit) — worked:**
- Available in Pi Imager under "Raspberry Pi OS (other)" → "Raspberry Pi OS Lite Legacy (32-bit)"
- Uses older, simpler boot config — more compatible with BCM43438 WiFi chip
- Recommended for Pi Zero 1

### LED Blink Codes

The Pi Zero uses LED blinks to report boot failures:

| Blinks | Meaning |
|--------|---------|
| 3 | General boot failure / memory error |
| 7 | Kernel image not found |
| Constant | Booted successfully |

**7 blinks on Pi Zero 1 with 64-bit image** — the 64-bit kernel (`kernel8.img`) will not run on ARMv6. Always use 32-bit image on Pi Zero 1. I fat fingered and tried to boot a Pizero 1 with a pizero 2 image...Oops

### Password Setup — Bullseye

Bullseye no longer has a default `pi` password. Pi Imager customisation is supposed to set it but can't always be trusted. The reliable method is editing `/etc/shadow` directly on the mounted card:

```bash
# Generate a password hash
echo 'yourpassword' | openssl passwd -6 -stdin
```

Note: the hash will look different every time due to random salting — this is normal. Any generated hash for the same password will work.

```bash
# Mount the root partition and edit shadow
sudo nano /media/user/rootfs/etc/shadow
```

Find the `pi:` line and replace `*` or `!` with your hash:
```
pi:$6$<your hash here>:19000:0:99999:7:::
```

Also ensure SSH and WiFi are configured on the boot partition:
```bash
# Enable SSH
touch /media/user/bootfs/ssh

# WiFi config
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

```bash
sync
sudo umount /media/user/bootfs
sudo umount /media/user/rootfs
```

### Cloning a Working Card

Once the first Pi Zero 1 is configured and updated, clone it to the second card:

```bash
# Shut down the Pi cleanly first
sudo shutdown -h now

# Straight card-to-card clone — no gzip
sudo dd if=/dev/sda of=/dev/sdb bs=4M status=progress conv=noerror
sync
```

**Important:** destination card must be same size or larger than source. Raw `dd` does not skip empty space — it copies the full card size byte for byte.

---

## Serial Console Debugging

Useful when SSH isn't working and HDMI shows nothing useful.

### Hardware
- USB-to-TTL serial adapter (3.3V — **not 5V**)
- Common chipsets: PL2303, CP2102, CH340, FTDI

### Wiring (Pi Zero GPIO)
```
Pi Pin 6  (GND) → adapter GND
Pi Pin 8  (TXD) → adapter RX
Pi Pin 10 (RXD) → adapter TX
```
Do NOT connect adapter 5V/VCC — power the Pi separately.

### Enable UART in config.txt
```bash
# Add to /media/user/bootfs/config.txt
enable_uart=1
dtoverlay=disable-bt
```

### Connect from desktop
```bash
# Find the adapter
dmesg | tail -10
# Look for ttyUSB0 or ttyACM0

# Connect
screen /dev/ttyUSB0 115200
# or
sudo minicom -D /dev/ttyUSB0 -b 115200
# In minicom: Ctrl+A Z  O  Serial port setup → Hardware FC: No, Software FC: No
```

---

## Key Lessons (What worked for me for a scrappy project / Anecdotal / Not saying it's the Law)

- **Always verify card contents after flashing** — Pi Imager can silently skip customisation
- **Pi Zero 1 and 2W are not compatible** — different CPU architecture, different kernels, different OS requirements
- **Trixie + Pi Zero 1 = trouble** — use Bullseye Legacy for Zero 1
- **Rainbow screen is not always failure** on 2W — check the network before panicking
- **Card cloning** — never pipe through gzip when doing card-to-card clone; use plain `dd`
- **Power** — use a real 5V/2.5A wall adapter, not a hub port
- **`/etc/shadow` direct edit** is more reliable than `userconf.txt` for setting passwords on Bullseye
- **Salted password hashes** look different every time but all work — this is normal and correct

