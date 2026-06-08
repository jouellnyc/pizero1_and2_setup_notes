# Raspberry Pi Zero 2W Troubleshooting Guide for Console Setup

## Trixie (Debian 13) — USB Gadget, Serial Console, and USB Hub

This documents real-world troubleshooting steps for getting a Pi Zero 2W running Raspberry Pi OS Trixie connected via USB gadget (g_ether) and serial console. Spoiler: Trixie makes both harder than they should be.

---

## Table of Contents

1. [USB Hub — Per-Port Power Switching](#usb-hub--per-port-power-switching)
2. [USB Gadget (g_ether) Setup](#usb-gadget-g_ether-setup)
3. [Serial Console via PL2303 Cable](#serial-console-via-pl2303-cable)

---

## USB Hub — Per-Port Power Switching

### Problem
Devices connected to a powered USB hub stay powered (LEDs lit) even after disabling the port with `uhubctl`.

### Explanation
Most powered hubs (with AC adapter) keep VBUS (5V) hot on all ports continuously regardless of software commands. `uhubctl` sends the disable command, the hub ACKs it, but ignores it at the hardware level.

- **Port disabled** = hub stops enumerating devices, ignores data traffic
- **Port powered off** = VBUS physically cut — most consumer hubs don't support this

### Verify your hub supports per-port power switching
```bash
lsusb -v | grep -i "PerPortPower\|portpower\|gang"
```
No output = no per-port power switching. All ports are ganged.

### Solutions
- **Hardware**: Use an Acroname or Yepkit YKUSH hub — purpose-built for per-port switching (~$50+)
- **Cheap hack**: USB cable with an inline physical power switch
- **Software**: `uhubctl` port reset forces re-enumeration even if it can't cut power

---

## USB Gadget (g_ether) Setup

### Goal
Make the Pi Zero 2W appear as a USB Ethernet device so you can SSH into it over USB.

### Install the package
```bash
sudo apt install rpi-usb-gadget
```

### Enable gadget mode
```bash
sudo rpi-usb-gadget on
sudo reboot
```

### Verify status after reboot
```bash
sudo rpi-usb-gadget status
```

Expected output:
```
USB Gadget mode is on
:: NetworkManager:
  iface:        usb0
  link:         connected
  active prof:  USB Gadget (shared)
  IPv4:         10.12.194.1/24
```

---

### Troubleshooting g_ether

#### Problem: `dr_mode=host` blocking gadget mode

Check config.txt:
```bash
grep dwc2 /boot/firmware/config.txt
```

If you see `dtoverlay=dwc2,dr_mode=host`, change it:
```bash
sudo nano /boot/firmware/config.txt
```
Change to:
```
dtoverlay=dwc2,dr_mode=peripheral
```

#### Problem: `g_ether: couldn't find an available UDC`

Check dmesg:
```bash
dmesg | grep -i "dwc\|udc\|gadget"
```

If you see `dwc_otg` loading instead of `dwc2`, the old Broadcom downstream driver is taking over. On Trixie, `dwc2` should load alongside it. Verify:
```bash
lsmod | grep dwc
```

Force load dwc2 and g_ether:
```bash
sudo modprobe dwc2
sudo modprobe g_ether
dmesg | tail -10
```

#### Problem: `modules-load=dwc2,g_ether` marked as unknown kernel parameter

Check cmdline.txt:
```bash
cat /boot/firmware/cmdline.txt
```

The line should contain `modules-load=dwc2,g_ether` after `rootwait`. If missing, add it:
```bash
sudo nano /boot/firmware/cmdline.txt
```

On Trixie this parameter gets flagged as unknown but still works.

---

### Connecting from the host (desktop/laptop)

After plugging in the OTG cable, check dmesg on the host:
```bash
sudo dmesg -T | tail -20
```

Look for:
```
usb X-X: Product: Raspberry Pi USB Gadget
cdc_ether X-X:1.0 usb0: register 'cdc_ether'
cdc_ether X-X:1.0 enxXXXXXXXXXXXX: renamed from usb0
```

Note the interface name (e.g. `enx7e1d4165d2eb`) — it changes on every reboot because g_ether randomizes the MAC.

#### Check what IP the Pi assigned itself
```bash
# on Pi
ip addr show usb0
```

The `rpi-usb-gadget` package assigns `10.12.194.1/28` by default and runs dnsmasq as a DHCP server.

#### Get an IP on the host
NetworkManager should handle this automatically. If it doesn't:
```bash
sudo dhclient -v enxXXXXXXXXXXXX
```

#### Verify traffic with tcpdump
On the Pi:
```bash
sudo tcpdump -i usb0 -n -e
```

On the host:
```bash
sudo tcpdump -i enxXXXXXXXXXXXX -n -e
```

---

### Known Issue: TX queue timeouts on host (Trixie + cdc_ether + kernel 6.8)

Symptom in host dmesg:
```
cdc_ether X-X:1.0 enxXXX: NETDEV WATCHDOG: CPU: 0: transmit queue 0 timed out 5XXX ms
```

Frames leave the host kernel but never complete transmission over USB. This is a known bug with `cdc_ether` on Ubuntu 24 / kernel 6.8 with `g_ether`.

Attempted workarounds (partial relief only):
```bash
sudo ethtool -K enxXXXXXXXXXXXX tx off
sudo ethtool -K enxXXXXXXXXXXXX sg off gso off gro off
sudo ip link set enxXXXXXXXXXXXX txqueuelen 1000
```

**Workaround**: Use a direct motherboard USB port instead of a hub. The TX stall is worse through hub chains.

**Bottom line**: USB gadget on Trixie is unreliable as of June 2026. Use SSH over WiFi instead:
```bash
ssh root@<wlan0-ip>
```

Check the Pi's WiFi IP:
```bash
# on Pi
ip addr show wlan0
```

---

## Serial Console via PL2303 Cable

### Why
When USB gadget doesn't work and you need a direct console connection.

### Hardware
- PL2303, CP2102, or CH340 USB-to-serial adapter
- 3 dupont wires (GND, TX, RX)
- **Do NOT connect the red 5V wire**

### Verify the adapter is detected on the host
```bash
dmesg | tail -5
```
Look for:
```
pl2303 X-X:1.0: pl2303 converter detected
usb X-X: pl2303 converter now attached to ttyUSB0
```

### Pin connections (Pi Zero 2W)

Using physical pin numbers, counting from the end nearest the micro USB ports:

| Pin | Function | Wire color (typical) |
|-----|----------|----------------------|
| 6   | GND      | Black                |
| 8   | TX (BCM 14) | White (connect to RX on adapter) |
| 10  | RX (BCM 15) | Green (connect to TX on adapter) |

**Note**: TX on Pi → RX on adapter, and RX on Pi → TX on adapter.

### Connect
```bash
screen /dev/ttyUSB0 115200
# or
minicom -b 115200 -D /dev/ttyUSB0
```

To exit minicom: `Ctrl+A` then `X`

---

### Troubleshooting Serial Console

#### Problem: No output in minicom/screen

**Step 1: Test the cable with loopback**

Before touching the Pi, verify the adapter itself works. Short the TX and RX pins together **on the adapter end** (dupont pins), with GND also connected on the adapter. Type in minicom — you should see what you type echoed back.

> ⚠️ Test every cable before assuming a config problem. In this session, 2 out of 3 cables appeared dead during testing but later worked fine — the loopback test itself may not be reliable if the serial console isn't fully configured yet on the Pi side. Don't throw out cables based on a failed loopback alone; get the Pi config right first, then test.

**Step 2: Check serial hardware is enabled**
```bash
raspi-config nonint get_serial_hw    # 0 = enabled, 1 = disabled
raspi-config nonint get_serial_cons  # 0 = enabled
```

If disabled:
```bash
raspi-config nonint do_serial_hw 0
sudo reboot
```

If `raspi-config` doesn't update config.txt (Trixie bug), add manually:
```bash
echo "enable_uart=1" >> /boot/firmware/config.txt
sudo reboot
```

Verify it wrote:
```bash
grep enable_uart /boot/firmware/config.txt
```

**Step 3: Disable Bluetooth (it steals the UART)**

On Pi Zero 2W, Bluetooth shares the hardware UART. Disable it:
```bash
sudo systemctl disable bluetooth
echo "dtoverlay=disable-bt" >> /boot/firmware/config.txt
sudo reboot
```

**Step 4: Remove plymouth serial suppression**

Check cmdline.txt:
```bash
cat /boot/firmware/cmdline.txt
```

Remove `plymouth.ignore-serial-consoles` and `quiet splash` so you get full boot output:
```bash
sudo nano /boot/firmware/cmdline.txt
```

**Step 5: Verify serial getty is running**
```bash
systemctl status serial-getty@ttyAMA0
```

Should show `active (running)`. If not:
```bash
sudo systemctl enable --now serial-getty@ttyAMA0
```

**Step 6: Verify serial device**
```bash
ls -la /dev/serial*
```

Should show:
```
/dev/serial0 -> ttyAMA0
```

`ttyAMA0` is the full hardware UART. If it points to `ttyS0` instead, Bluetooth is still stealing the UART — revisit Step 3.

---

### Pin conflicts

If you have other hardware on the GPIO header, check for conflicts:

| Device | Pins used |
|--------|-----------|
| OLED (I2C) | Pin 3 (SDA), Pin 5 (SCL) |
| LED Green (BCM 16) | Pin 36 |
| LED Yellow (BCM 12) | Pin 32 |
| LED Red (BCM 13) | Pin 33 |
| UART TX (BCM 14) | Pin 8 ✓ free |
| UART RX (BCM 15) | Pin 10 ✓ free |

Use [pinout.xyz](https://pinout.xyz) as reference.

---

## Summary

| Goal | Status on Trixie | Solution |
|------|-----------------|----------|
| USB gadget (g_ether) | Unreliable — TX stall bug | Use WiFi SSH instead |
| Serial console | Works after manual config | Enable UART, disable BT, fix cmdline.txt |
| Per-port USB power | Not supported on consumer hubs | YKUSH hub or inline switch |

