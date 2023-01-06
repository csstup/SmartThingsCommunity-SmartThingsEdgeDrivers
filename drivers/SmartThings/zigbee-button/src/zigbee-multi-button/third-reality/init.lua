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

-- Device sends several commands for each button action.
-- As per the original DTH, we'll use the Cluster 0x0012 (multistate) messages instead of the others.
-- 
-- Pressed:      On/Off Cluster, command On
--               Cluster 0x0012, Attribute 0x0055, value = 1
-- Double push:  On/Off Cluster, command Off
--               Cluster 0x0012, Attribute 0x0055, value = 2
-- Held:         Level, Current Level command, value increasing number (1 for the first hold, 2 for the next, etc)
--               Cluster 0x0012, Attribute 0x0055, value = 0
--
-- An event is sent for the hold release which we ignore. 0x0012/0x0055, value 0xFF.

-- Battery is sent (percentage remaining, 0x0021) but the reporting interval cannot be changed.
-- The device errors our request.

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"

local PowerConfiguration = clusters.PowerConfiguration

local do_configure = function(self, device, event)
  -- This device does not support reporting on the power cluster attributes.  We still 
  -- go ahead and bind to the cluster just in case.
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))

  -- We'll poll the device occasionally for battery updates via the default monitor.
  -- Request Gets for all our monitored attributes (including battery)
  device:refresh()
end

local multistate_handler = function(driver, device, zb_rx)
  local additional_fields = {
    state_change = true
  }
  local button_value = zb_rx.value

  if button_value == 0 then
    device:emit_event(capabilities.button.button.held(additional_fields))
  elseif button_value == 1 then
    device:emit_event(capabilities.button.button.pushed(additional_fields))
  elseif button_value == 2 then
    device:emit_event(capabilities.button.button.double(additional_fields))
  end
end

local third_reality = {
  NAME = "Third Reality",
  lifecycle_handlers = {
    doConfigure = do_configure,
  },
  zigbee_handlers = {
    attr = {
      [0x0012] = {  -- Multistate Input (Basic)
        [0x0055] = multistate_handler,   -- 0x0055 = Present Value
      },
    },
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "Third Reality, Inc"
  end
}

return third_reality