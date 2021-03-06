local skynet = require "skynet"
local const = require "logger_const"
require "skynet.manager"

local command = {}
local logfile = nil
local openTime = nil
local logNameTag = nil
local logFilePath = nil

local logLevel = const.log_level.debug
local defaultLogFileSize = 1024*1024*1024
local maxLogFileSize = tonumber(skynet.getenv("MaxLogFileSize") or defaultLogFileSize)
print("MaxLogFileSize = ", maxLogFileSize)

local logPath = skynet.getenv("logpath") or "../../../log"
local logfilename = skynet.getenv("logfilename") or skynet.getenv("nodename") or "unknownsvr"

local function openlog(tag)
	openTime = os.time()
	logNameTag = tag or logfilename
	logFilePath = string.format("%s/%s.log", logPath, logNameTag)
	print("log file path is"..logFilePath)
	logfile = io.open(logFilePath, "a+")
end

local function closeLog()
	if logfile ~= nil then
		io.close(logfile)
	end
end

local function getFileSize()
	if not logfile then
		return 0
	end

	local s = logfile:seek()
	return s
end

local function isFileExists(filePath)
	local aFile = io.open(filePath, "r")
	if aFile then
		aFile:close()
		return true
	end

	return false
end

local function rollLog(savePath)
	if not savePath then
		return
	end

	if isFileExists(savePath) then
		return
	end

	io.close(logfile)
	logfile = nil

	local rst,errMsg = os.rename(logFilePath,savePath)
	if not rst then
		return
	end

	logfile = io.open(logFilePath, "a+")
	if not logfile then
	end

end

local function chooseSavePath(savePath,dataStr)
	local ret = nil 
	local pathFound = false

	for i=1,1000000 do
		ret = string.format("%s.%s.%d", savePath, dataStr, i)
        if not isFileExists(ret) then
        	pathFound = true
        	break
        end
	end

	if pathFound then
		return ret
	end

	return nil
end

local function checkForRename()
    local curTime = os.time()
    local curDate = os.date("*t", curTime)
    local openDate = os.date("*t", openTime)

    if curDate.day ~= openDate.day then
    	local dateStr = os.date("%Y%m%d", curTime)
    	local savePath = string.format("%s.%s", logFilePath, dataStr)
    	if isFileExists(savePath) then
    		savePath = chooseSavePath(logFilePath, dateStr)
    	end

    	if savePath then
    		rollLog(savePath)
    	end
        openTime = curTime
    end

    local fileSize = getFileSize()
    if fileSize >= maxLogFileSize then
        local dateStr = os.date("%Y%m%d", curTime)
    	local savePath = chooseSavePath(logFilePath, dateStr)

    	if savePath then
    		rollLog(savePath)
    	end
    end
end

local function setLogLevel(level)
	local before = logLevel
	if const.log_level[level] ~= nil then
        logLevel = const.log_level[level]
        skynet.error("logservice: setLoglevel as "..level)

        skynet.timeout(0, function() 
        	local ok,ret = pcall(skynet.call, "DATACENTER", "lua", "UPDATE", "loglevel", level)
        	if not ok then
                -- skynet.error("")
        	end
        end)
    else
    	-- skynet.error("")
	end

	return {before=const.log_lvlstr[before], after=const.log_lvlstr[logLevel]}
end

function command.log(source,level,msg)
	if level < logLevel then
		return 
	end

	checkForRename()

	if logfile ~= nil then
		local tmpMsg = string.format("[%08x]%s", source, msg)
		-- local cMsg = string.format("%s[:%08x]%s%s", const.log_color[level], msg, const.log_color[-1])
        
  --       print(cMsg)
		-- io.write(cMsg)
		-- io.flush()

		logfile:write(tmpMsg)
		logfile:flush()
	else
		skynet.error("logservice: log file name not set, msg = "..msg)
    end
end

function command.set_log_file(source,tag)
	openlog(tag)
	return {true}
end

function command.set_log_level(source,level)
	return setLogLevel(level)
end

function command.test_log()
    print("command.test_log")
    return {true}
end

skynet.start(function() 
    skynet.dispatch("lua", function(session, address, cmd, ...)
    	local f = command[string.lower(cmd)]
    	if f ~= nil then
            local ret = f(address,...)
            if ret ~= nil then
           	   skynet.ret(skynet.pack(ret))
            end
        else
        	skynet.error(".logservice unknown cmd:"..cmd)
    	end
    end)

    local level = skynet.getenv("loglevel")
    if level then
    	setLogLevel(level)
    else
    	setLogLevel(const.log_level.info)
    end


    skynet.register(".logservice")
end)
