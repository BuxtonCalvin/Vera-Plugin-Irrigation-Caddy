--[[
    IrrigationCaddy
    Written by a-lurker (c) copyright 2 June 2013.

    Refer to: http://irrigationcaddy.com/blog/?p=55
    http://irrigationcaddy

    This plugin assumes you are using irrigationcaddy firmware version: 'ICEthS1-1.3.223' or better
    Note that the irrigationcaddy API could be changed at any time by the manufacturer

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    version 3 (GPLv3) as published by the Free Software Foundation;

    In addition to the GPLv3 License, this software is only for private
    or home usage. Commercial utilisation is not authorized.

    The above copyright notice and this permission notice shall be included
    in all copies or substantial portions of the Software.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
]]

--[[
-- handling any json would require a json parser
-- http://code.mios.com/trac/mios_genericutils/wiki/JSONLua
-- http://json.luaforge.net/
local JSON_LIB = 'json-dm'  -- use the json parser installed by dataMine

    Example json useage - not tested

    -- get the json library
    local json = require(JSON_LIB)
    if not json.decode then
        debug('No json library available')
        return false, 'Failed to find a json library'
    end

    local success, result = getIcStatus()
    if success then
        local icStatus = json.decode(result)
        if (icStatus == nil) then
            debug('No status')
            return false, 'Failed to get status'
        end
    else
        debug('No response')
        return false, 'Failed to get a response from device'
    end
]]

--[[
    Example calls:
    local success, result = getIcSettings()
    local success, result = getIcPrograms()
    local success, result = getIcSystemTime()
    local success, result = getIcZoneNames()
    local success, result = getIcBootTime()
    local success, result = setIcClock()
    local success, result = setIcSystemOn()
    local success, result = getIcCalendar()
    local success, result = enableDisableIcProgram(1, false)
]]

local PLUGIN_NAME     = 'IrrigationCaddy'
local PLUGIN_SID      = 'urn:a-lurker-com:serviceId:'..PLUGIN_NAME..'1'
local PLUGIN_VERSION  = '0.54'
local THIS_LUL_DEVICE = nil

local SWP_SID = 'urn:upnp-org:serviceId:SwitchPower1'

local icIpAddress  = ''

local ltn12 = require('ltn12')

-- You can turn on Verbose Logging - refer to: Vera-->U15-->SETUP-->Logs-->Verbose_Logging
-- http://vera_ip_address/cgi-bin/cmh/log_level.sh?command=enable&log=VERBOSE
-- http://vera_ip_address/cgi-bin/cmh/log_level.sh?command=disable&log=VERBOSE

-- don't change this, it won't do anything. Use the debugEnabled flag instead
local DEBUG_MODE = false

local function debug(textParm, logLevel)
    if DEBUG_MODE then
        local text = ''
        local theType = type(textParm)
        if (theType == 'string') then
            text = textParm
        else
            text = 'type = '..theType..', value = '..tostring(textParm)
        end
        luup.log(PLUGIN_NAME..' debug: '..text,50)

    elseif (logLevel) then
        local text = ''
        if (type(textParm) == 'string') then text = textParm end
        luup.log(PLUGIN_NAME..' debug: '..text, logLevel)
    end
end

-- If non existent, create the variable.
-- Update the variable only if needs to be.
local function updateVariable(varK, varV, sid, id)
    if (sid == nil) then sid = PLUGIN_SID      end
    if (id  == nil) then  id = THIS_LUL_DEVICE end

    if ((varK == nil) or (varV == nil)) then
        luup.log(PLUGIN_NAME..' debug: '..'Error: updateVariable was supplied with a nil value', 1)
        return
    end

    local newValue = tostring(varV)
    --debug(varK..' = '..newValue)
    debug(newValue..' --> '..varK)

    local currentValue = luup.variable_get(sid, varK, id)
    if ((currentValue ~= newValue) or (currentValue == nil)) then
        luup.variable_set(sid, varK, newValue, id)
    end
end

-- IC uses 'time=unixTime' to randomise some calls
-- we will use 'rand=unixTime' to randomise all calls
-- refer also to: http://w3.impa.br/~diego/software/luasocket/http.html
local function urlRequest(urlPart, request_body)
    local http = require('socket.http')
    http.TIMEOUT = 5

    local response_body = {}
    local timeStr = os.time()  -- randomise the URL
    local theURL = 'http://'..icIpAddress..'/'..urlPart..'?rand='..timeStr
    debug('URL: '..theURL)
    debug('Posted: '..request_body)

    -- site not found: r is nil, c is the error status eg (as a string) 'No route to host' and h is nil
    -- site is found:  r is 1, c is the return status (as a number) and h are the returned headers in a table variable
    local r, c, h = http.request {
          url = theURL,
          method = 'POST',
          headers = {
            ['Content-Type']   = 'application/x-www-form-urlencoded',
            ['Content-Length'] = string.len(request_body)
          },
          source = ltn12.source.string(request_body),
          sink   = ltn12.sink.table(response_body)
    }

    debug('URL request result: r = '..tostring(r))
    debug('URL request result: c = '..tostring(c))
    debug('URL request result: h = '..tostring(h))

    local page = ''
	if (r == nil) then return false, page end

    if ((c == 200) and (type(response_body) == 'table')) then
        page = table.concat(response_body)
        debug('Returned web page data is: '..page)
		return true, page
    end

    if (c == 400) then
        debug('HTTP 400 Bad Request')
        return false, page
    end

    return false, page
end

-- returns the device status as json
local function getIcStatus()
    return urlRequest('status.json', '')
end

-- NOT USED
-- returns the device settings as json
local function getIcSettings()
    return urlRequest('settingsVars.json', '')
end

-- NOT USED
-- returns the users sprinkler programs as json
local function getIcPrograms()
    return urlRequest('programData.json', '')
end

-- NOT USED
-- returns the device time as json
local function getIcSystemTime()
    return urlRequest('dateTime.json', '')
end

-- NOT USED
-- returns the friendly names of the zones as json
local function getIcZoneNames()
    return urlRequest('zoneNames.json', '')
end

-- NOT USED
-- returns the time when the device was first booted up as json
local function getIcBootTime()
    return urlRequest('bootTime.json', '')
end

-- NOT USED
-- returns the calendar info as json
-- you supply a the Start and End UNIX timestamps and the sprinkler
-- program information between those two times will be returned
local function getIcCalendar(timeStart, timeEnd)
    return urlRequest('calendar.json?start='..timeStart..'&end='..timeEnd, '')
end

-- NOT USED
-- set the clock to match the Vera date
local function setIcClock()
    -- eg day=3&date=03&month=06&year=13&hr=14&min=36&sec=25
    local timeStr = os.date('day=%w&date=%d&month=%m&year=%y&hr=%H&min=%M&sec=%S')

    -- days are numbered 1 to 7, where 1 is Sunday
    -- total hack: add one to the UNIX weekday to make an IrrigationCaddy weekday
    local temp = timeStr:match('^day=(%d)')
    timeStr = timeStr:gsub('^day='..temp, 'day='..tostring(tonumber(temp)+1))
    debug('timeStr = '..timeStr)

    return urlRequest('setClock.htm', timeStr)
end

-- NOT USED
-- enable or disable a program - equates to the program's on/off radio buttons
local function enableDisableIcProgram(programNumber, programOn)

-- Method appears to be:
--    check for the presence of a json parser
--    call getIcPrograms()
--    parse the returned json
--    change variable 'allowRun' to true/false as required
--    reformat as suitable parameters for 'program.htm'
--    post all parms back to 'program.htm'
--    hope it all works and doesn't destroy all your sprinkler programs
--    If you know how to do this more easily, let me know!

end

-- executes the 'Run Now' button for sprinkler programs 1 to 3
local function runNowZoneSequencerInIcProgram(programNumber)
    local pNumber = tonumber(programNumber)
    if (pNumber < 1) or (pNumber > 3) then return false, 'programNumber invalid' end
    return urlRequest('runProgram.htm', 'doProgram=1&pgmNum='..programNumber..'&runNow=true')
end

-- enable all programs;  eg garden is dry and needs water
local function setIcSystemOn()
    return urlRequest('runSprinklers.htm', 'run=run')
end

-- disable all programs and turn off all valves;  eg it's raining
local function setIcSystemOff()
    return urlRequest('stopSprinklers.htm', 'stop=off')
end

local function initVars(THIS_LUL_DEVICE)
    local ipa = luup.devices[THIS_LUL_DEVICE].ip

    local ipAddress = string.match(ipa, '^(%d%d?%d?%.%d%d?%d?%.%d%d?%d?%.%d%d?%d?)')
    local ipPort    = string.match(ipa, ':(%d+)$')

    if (ipAddress == nil) then return false, 'Please configure the IP Address' end
    if (ipPort == nil) then ipPort = '80' end

    icIpAddress = ipAddress..':'..ipPort

    local linkToDeviceWebPage = "<a href='http://"..icIpAddress.."/' target='_blank'>IrrigationCaddy web page</a>"
    updateVariable('LinkToDeviceWebPage', linkToDeviceWebPage)

    local success, result = getIcStatus()
    if not success then return false, 'Status not available' end

    -- examine the allowRun flag
    local str = string.match(result, '"allowRun":true')
    local allowRun = (str ~= nil)

    if allowRun then
        luup.variable_set(SWP_SID, 'Status','1', THIS_LUL_DEVICE)
    else
        luup.variable_set(SWP_SID, 'Status','0', THIS_LUL_DEVICE)
    end

    return true, 'Ready'
end

--[[
a Vera action
refer to: I_IrrigationCaddy1.xml
http://wiki.micasaverde.com/index.php/Luup_Declarations
function SetTarget(lul_device, lul_settings)
    setTarget(lul_settings.newTargetValue)
end
]]
local function setTarget(newTargetValue)
    debug('setTarget running')
    debug('newTargetValue: '..newTargetValue)

    if (newTargetValue == '1') then
        setIcSystemOn()
        luup.variable_set(SWP_SID, 'Status','1', THIS_LUL_DEVICE)
    else
        setIcSystemOff()
        luup.variable_set(SWP_SID, 'Status','0', THIS_LUL_DEVICE)
    end
end

--[[
a Vera action
refer to: I_IrrigationCaddy1.xml
http://wiki.micasaverde.com/index.php/Luup_Declarations
function RunZoneSequencer(lul_device, lul_settings)
    runZoneSequencer(lul_settings.newInThisProgram)
end
]]
local function runZoneSequencer(newInThisProgram)
    debug('runZoneSequencer running')
    debug('newInThisProgram: '..newInThisProgram)
    runNowZoneSequencerInIcProgram(newInThisProgram)
end

-- Start up the plugin
-- Refer to: I_IrrigationCaddy1.xml
-- <startup>luaStartUp</startup>
-- function needs to be global
function luaStartUp(lul_device)
    THIS_LUL_DEVICE = lul_device
    debug('luaStartUp running')

    -- set up some defaults:
    updateVariable('PluginVersion', PLUGIN_VERSION)

    local debugEnabled = luup.variable_get(PLUGIN_SID, 'DebugEnabled', THIS_LUL_DEVICE)
    if ((debugEnabled == nil) or (debugEnabled == '')) then
	    debugEnabled = '0'
        updateVariable('DebugEnabled', debugEnabled)
    end
	DEBUG_MODE = (debugEnabled == '1')

    local success, message = initVars(THIS_LUL_DEVICE)
    if not success then return false, message, PLUGIN_NAME end

    -- required for UI7. UI5 uses true or false for the passed parameter.
    -- UI7 uses 0 or 1 or 2 for the parameter. This works for both UI5 and UI7
    luup.set_failure(false)

    return true, 'All OK', PLUGIN_NAME
end
