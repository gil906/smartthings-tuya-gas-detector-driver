-- Tuya Gas Detector driver for _TZE284_chbyv06x / TS0601
--
-- This device uses Tuya's proprietary Zigbee cluster 0xEF00 instead of the
-- standard Zigbee smoke/gas clusters, so a generic driver can't decode it.
--
-- VERIFIED 2026-08-25 against this exact unit's real Zigbee traffic (lighter
-- test, live logcat capture) — the original DP mapping guessed from a related
-- device family (zigpy/zha-device-handlers #4107) was WRONG about what DP2
-- actually is:
--   DP 1  -> binary alarm flag (0 = clear). Only ever observed as 0 in
--            testing, even at the test's peak reading — this device's
--            built-in hardware alarm threshold needs a much higher/more
--            sustained concentration than a lighter produces (by design,
--            so it doesn't false-alarm on small transient sources).
--   DP 2  -> REAL analog gas concentration reading, confirmed by direct
--            observation: idle baseline sits around 16-35, and it spiked
--            sharply to 124 within ~4 seconds of a lighter test, then decayed
--            back to baseline over about a minute — a textbook combustible-
--            gas concentration curve, not a static "alarm/self-test" flag as
--            originally guessed.
--   DP 11 -> battery percentage (present on some variants; safe to ignore
--            if this device is mains-powered, which most gas detectors are)
--
-- Since DP1 alone proved too conservative to reflect a real detection event
-- in testing, this driver now ALSO treats a DP2 reading clearly above the
-- observed idle baseline as a detection, in addition to trusting DP1 if the
-- hardware alarm ever does trip on its own. Threshold chosen well above the
-- ~35 idle ceiling seen in testing but well below the 124 peak, to avoid
-- false positives from normal baseline drift.

local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"
local ZigbeeDriver = require "st.zigbee"

local TUYA_CLUSTER = 0xEF00
local TUYA_DP_ALARM_FLAG = 1     -- hardware binary alarm flag
local TUYA_DP_GAS_LEVEL = 2      -- real analog gas concentration reading
local TUYA_DP_BATTERY = 11
local GAS_LEVEL_DETECTED_THRESHOLD = 60  -- idle baseline observed ~16-35; test peak was 124

local function parse_tuya_dp_report(driver, device, zb_rx)
  -- Tuya 0xEF00 "data report" payloads are a custom binary format:
  -- byte 0-1: seq number, byte 2: dp id, byte 3: dp type, byte 4-5: dp len,
  -- byte 6..: dp value (big-endian).
  local bytes = zb_rx.body.zcl_body.body_bytes
  if bytes == nil or #bytes < 7 then
    device.log.warn("Tuya DP report too short to parse: " .. tostring(bytes))
    return
  end

  local dp_id = bytes:byte(3)
  local dp_len = bytes:byte(5) * 256 + bytes:byte(6)
  local value = 0
  for i = 1, dp_len do
    value = value * 256 + bytes:byte(6 + i)
  end

  device.log.info(string.format("Tuya DP report: dp_id=%d len=%d value=%d (raw=%s)",
    dp_id, dp_len, value, bytes:gsub(".", function(c) return string.format("%02X", c:byte()) end)))

  if dp_id == TUYA_DP_ALARM_FLAG then
    if value == 1 then
      device:emit_event(capabilities.smokeDetector.smoke.detected())
    else
      device:emit_event(capabilities.smokeDetector.smoke.clear())
    end
  elseif dp_id == TUYA_DP_GAS_LEVEL then
    device.log.info("Gas concentration reading: " .. tostring(value))
    if value >= GAS_LEVEL_DETECTED_THRESHOLD then
      device:emit_event(capabilities.smokeDetector.smoke.detected())
    else
      device:emit_event(capabilities.smokeDetector.smoke.clear())
    end
  elseif dp_id == TUYA_DP_BATTERY then
    device:emit_event(capabilities.battery.battery(value))
  else
    device.log.info("Unhandled Tuya DP id " .. tostring(dp_id) .. " = " .. tostring(value))
  end
end

local function device_added(driver, device)
  device:emit_event(capabilities.smokeDetector.smoke.clear())
end

local function do_refresh(driver, device)
  -- Tuya EF00 devices generally push data on their own schedule rather than
  -- responding to a standard Zigbee read-attribute; there isn't a reliable
  -- generic "refresh" command for this cluster, so this is a no-op placeholder.
  device.log.info("Refresh requested (Tuya EF00 devices report asynchronously; no explicit poll available)")
end

local tuya_gas_driver_template = {
  supported_capabilities = {
    capabilities.smokeDetector,
    capabilities.battery,
    capabilities.refresh,
  },
  lifecycle_handlers = {
    added = device_added,
  },
  zigbee_handlers = {
    cluster = {
      [TUYA_CLUSTER] = {
        [0x01] = parse_tuya_dp_report, -- command id 0x01 = data report
        [0x02] = parse_tuya_dp_report, -- some firmwares use 0x02 for reports
      },
    },
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    },
  },
}

local driver = ZigbeeDriver("tuya-gas-detector-tze284-chbyv06x", tuya_gas_driver_template)
driver:run()
