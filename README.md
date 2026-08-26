# SmartThings Edge Driver — Tuya Natural Gas Sensor (`_TZE284_chbyv06x` / TS0601)

![Natural Gas Sensor Zigbee — installed](https://github.com/user-attachments/assets/e01942a0-9fc7-4b9a-9ec2-528aba27a71b)

A working, **field-verified** SmartThings Edge driver for the Tuya Zigbee natural
gas sensor identified as manufacturer `_TZE284_chbyv06x`, model `TS0601`. This
device uses Tuya's proprietary `0xEF00` Zigbee cluster instead of any standard
Zigbee smoke/gas cluster, so it doesn't work with SmartThings' generic
"Zigbee Thing" fallback driver — every capability reads back `null`.

There was no existing public SmartThings driver for this exact manufacturer
ID at the time this was built (August 2026). This repo publishes it so nobody
else has to reverse-engineer it from scratch.

## Install it on your own hub

1. Accept the driver channel invite (one-time, links your SmartThings account to this channel):
   **https://bestow-regional.api.smartthings.com/invite/gV2qwyDydYj9**
2. On that page, select your hub to enroll it in the channel.
3. In the SmartThings app: your device's driver-selection screen (via the
   device's `...` menu → Driver) → pick **tuya-gas-detector-tze284-chbyv06x**.
4. If the device was previously stuck on the generic "Zigbee Thing" driver,
   it should now start reporting real data.

## How it works / what's actually verified

Unlike most published quirks for similar Tuya devices (which are usually
*inferred* from a related device family, never tested against the real
unit), this driver's datapoint mapping was **confirmed against live captured
Zigbee traffic** from this exact sensor, using a real trigger test
(a lighter, briefly, in a ventilated area) while streaming
`smartthings edge:drivers:logcat`:

| Tuya DP | What it actually is | Verified behavior |
|---|---|---|
| **DP 1** | Hardware alarm flag (0/1) | Only trips for a strong/sustained concentration — did **not** trip on a brief lighter test, by design (avoids false alarms on trivial sources) |
| **DP 2** | Real analog gas concentration reading | Idle baseline ~16–35. Spiked to **124** within ~4 seconds of the lighter test, then decayed back to baseline over about a minute — a textbook combustible-gas response curve |
| **DP 11** | Battery percentage | Present on some variants; harmless to ignore on mains-powered units |

The original guess (based on the closest documented device family,
[zigpy/zha-device-handlers#4107](https://github.com/zigpy/zha-device-handlers/issues/4107))
assumed DP1 alone was the detection signal. Real testing showed that's too
conservative — DP1 only flips for a serious/sustained event. This driver
therefore treats **either** DP1 tripping **or** DP2 crossing a threshold
(60, well above the observed idle ceiling, well below the confirmed real-event
peak) as a detection, mapped to the standard `smokeDetector` capability
(SmartThings has no separate "natural gas" capability, so this is the closest
correct fit — same pattern used by other published Tuya gas/smoke drivers).

A real-world test also confirmed the sensor's own hardware alarm (DP1) correctly
tripped and latched during a stronger/sustained exposure, matching the physical
unit's beeping — the driver reported "detected" in SmartThings at the same moment.

## Files

- `gas-detector/config.yml` — driver metadata, permissions, device type
- `gas-detector/fingerprints.yml` — maps this exact manufacturer/model to the profile
- `gas-detector/profiles/gas-detector.yml` — capabilities exposed (smokeDetector, battery, refresh)
- `gas-detector/src/init.lua` — the actual parsing/detection logic, fully commented

## Building/uploading it yourself (if you want your own channel instead)

Requires the official [SmartThings CLI](https://github.com/SmartThingsCommunity/smartthings-cli):

```
smartthings edge:channels:create
smartthings edge:drivers:package ./gas-detector --channel <your-channel-id>
smartthings edge:drivers:install --hub <your-hub-id> --channel <your-channel-id> <driver-id>
```

## The physical device

This driver targets the **DYGSM Alarm System** Tuya Zigbee natural gas sensor,
identifying itself over Zigbee as manufacturer `_TZE284_chbyv06x`, model
`TS0601`. Works with the Tuya/SmartLife app natively, but this repo gives it
a real dedicated SmartThings Edge driver instead of a generic fallback.

![DYGSM Zigbee Natural Gas Sensor listing](https://github.com/user-attachments/assets/76794772-c979-4266-a21b-ebe677334f4f)

**Buy it here:** [Tuya Zigbee Smart Natural Gas Sensor — DYGSM Smart Store (AliExpress)](https://a.aliexpress.com/_mtLwEFd)
(requires a Zigbee hub — SmartThings, Home Assistant + ZHA/Zigbee2MQTT, etc.)

## Disclaimer

This is a community-built driver, not official Tuya or SmartThings software.
It's a smart-home convenience layer on top of the sensor's own **built-in
hardware alarm**, which is still the actual life-safety mechanism (it beeps
locally regardless of any SmartThings integration). Don't rely on this
driver or its SmartThings automations as your sole means of gas detection.

## License

MIT — see [LICENSE](./LICENSE).
