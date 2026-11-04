# Wi-Fi notes for the Nokia "ATV R2"

Findings from one TV (firmware V8-T851TNF-LF2V287), 2026-11-04. Everything below is read-only diagnosis; no setting was changed.

## "It only connects on 2.4 GHz"

That is the hardware. The TV's Wi-Fi is a **USB module** driven by `rtl8192eu`:

```
adb shell readlink /sys/class/net/wlan0/device/driver
.../bus/usb/drivers/rtl8192eu
```

The RTL8192EU is an 802.11n chip for the 2.4 GHz band only. This matches what the TV reports: `Wi-Fi standard: 4` (802.11n), a link speed of 144 Mbps
(two streams on a 20 MHz channel), and a scan list (`adb shell cmd wifi list-scan-results`) in which all 8 networks seen were 2.4 GHz.
No setting can add 5 GHz. The TV's firmware also carries drivers for other USB Wi-Fi chips (`8812au`, `8822cu`), which are 5 GHz capable;
whether an external adapter works on this TV was **not** tested.

Options that should work (not tried on this TV): a **wired Ethernet** connection, if your TV has an Ethernet socket (this one lists an `eth0` interface), or a small **5 GHz Wi-Fi bridge** (a router or repeater in client mode) next to the TV, joined to it by an Ethernet cable.

The TV also reports **no Wi-Fi country code** (`adb shell dumpsys wifi | grep -i countrycode` shows `null`). That does not matter for a 2.4 GHz-only chip, and the setting is not changed here.

## "It keeps disconnecting"

Signal strength was not the problem: the TV sat at about -34 dBm (excellent) next to its router.
The TV's own network monitor was dropping the connection. In `dumpsys wifi` the pattern is:

```
CMD_IP_REACHABILITY_LOST ... NeighborEvent{... RTM_NEWNEIGH, <router IPv4>, NUD_FAILED ...}
NETWORK_DISCONNECTION_EVENT ... reason=3
... reconnected about 2-4 seconds later
```

In plain words: the TV sent ARP probes to the router's IPv4 address, got no answer (`NUD_FAILED`), concluded the router was gone, disconnected itself and reconnected.
Over about 26 hours, 12 of the 14 disconnects in the log were of this kind. When checked afterwards the router was reachable over IPv6, and no Wi-Fi hotspot start was logged,
so the cause is somewhere between the TV's USB Wi-Fi module and the router (the module missing the router's reply, or the router not sending it). It was **not** pinned down further.

Check your own TV (read-only):

```
adb shell dumpsys wifi | grep -c CMD_IP_REACHABILITY_LOST
adb shell dumpsys wifi | grep -E "NETWORK_DISCONNECTION_EVENT|CMD_IP_REACHABILITY_LOST"
adb shell cmd wifi status
```

Ideas, in order of how likely they are to help (none was tested on this TV):

1. **Use a cable** (or a bridge); this removes the problem instead of working around it.
2. In the router: give the TV a fixed address (DHCP reservation), set a fixed 2.4 GHz channel (1, 6 or 11) at 20 MHz, use plain WPA2, and switch off options such as IP-MAC binding, ARP protection or DoS protection if it has them.
3. Experiment: an app that holds a high-performance Wi-Fi lock to keep the module out of power-save. Compare the `CMD_IP_REACHABILITY_LOST` count before and after a day or two before believing it helps.
