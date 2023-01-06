-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local OnOff = clusters.OnOff
local PowerConfiguration = clusters.PowerConfiguration

local device_management = require "st.zigbee.device_management"
local button_utils = require "button_utils"
local lua_socket = require "socket"

local BUTTON_X_PRESS_TIME = "button_%d_pressed_time"
local TIMEOUT_THRESHOLD = 10

-- NOte the extra leading spaces - 1 in the manu, 3 in the model.
local ECHOSTAR_FINGERPRINTS = {
  { mfr = " Echostar", model = "   Bell" },
}

local is_echostar_doorbell = function(opts, driver, device)
  for _, fingerprint in ipairs(ECHOSTAR_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local do_configuration = function(self, device)
  -- Configure for a battery update every 6 hours.
  -- Note that battery results are ALWAYS returned as 0 on this device.  Bug in the firmware.
  -- So for now we bind to the cluster but don't request any reporting.
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  -- device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 60, 21600, 1))
end

-- Function to generate and filter out duplicate events
local handle_button_events = function(device, button_number)
  local last_press_time = device:get_field(string.format(BUTTON_X_PRESS_TIME, button_number))
  local now_press_time = lua_socket.gettime()
  local seconds_threshold = tonumber(device.preferences.timeBetweenPresses or 5)

  if last_press_time == nil or (now_press_time - last_press_time) >= seconds_threshold then
    -- generate the event
    device:set_field(string.format(BUTTON_X_PRESS_TIME, button_number), lua_socket.gettime())
    return true
  end
  return false
end

-- Button 1
local function attr_on_handler(driver, device, zb_rx)
  if handle_button_events(device, 1) then
    local doEvent = button_utils.build_button_handler("button1", capabilities.button.button.pushed)
    doEvent(driver, device, zb_rx)
  end
end

-- Button 2
local function attr_off_handler(driver, device, zb_rx)
  if handle_button_events(device, 2) then
    local doEvent = button_utils.build_button_handler("button2", capabilities.button.button.pushed)
    doEvent(driver, device, zb_rx)
  end
end

local echostar_device_handler = {
  NAME = "Echostar Bell",
  lifecycle_handlers = {
    doConfigure = do_configuration,
  },
  zigbee_handlers = {
    cluster = {
      [OnOff.ID] = {
        [OnOff.server.commands.Off.ID] = attr_off_handler,
        [OnOff.server.commands.On.ID] = attr_on_handler,
      }
    }
  },
  can_handle = is_echostar_doorbell
}

return echostar_device_handler
