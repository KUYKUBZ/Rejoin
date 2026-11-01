#!/data/data/com.termux/files/usr/bin/lua

local VERSION = "3.0"
local INTERVAL = 15
local RETRY_DELAY = 5
local MAX_RETRIES = 3

local HOME = os.getenv("HOME")
local BASE = HOME .. "/.sentinel"
local LOG = BASE .. "/sentinel.log"

os.execute("mkdir -p " .. BASE)

local C = {
    RESET = "\27[0m",
    RED = "\27[31m",
    GREEN = "\27[32m",
    YELLOW = "\27[33m",
    CYAN = "\27[36m"
}

local function quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function command(cmd)
    local p = io.popen(cmd .. " 2>/dev/null")
    if not p then return "" end

    local result = p:read("*a") or ""
    p:close()

    return result
end

local function run(cmd)
    local a, _, c = os.execute(cmd .. " >/dev/null 2>&1")
    return a == true or a == 0 or c == 0
end

local function log(msg)
    local f = io.open(LOG, "a")
    if f then
        f:write(os.date("[%Y-%m-%d %H:%M:%S] ")
            .. msg .. "\n")
        f:close()
    end
end

local function root_available()
    return command("su -c id -u"):match("0") ~= nil
end

local ROOT = root_available()

local function adb(cmd)
    if ROOT then
        return command("su -c " .. quote(cmd))
    end
    return command(cmd)
end

local function execute_android(cmd)
    if ROOT then
        return run("su -c " .. quote(cmd))
    end
    return run(cmd)
end

-- Discover packages
local function discover()
    local result = command("pm list packages")
    local packages = {}

    for pkg in result:gmatch("package:([%w%._]+)") do
        local name = pkg:lower()

        if name:find("roblox", 1, true) then
            packages[#packages + 1] = pkg
        end
    end

    table.sort(packages)
    return packages
end

-- Get every PID
local function get_pids(pkg)
    local result = adb("pidof " .. quote(pkg))
    local pids = {}

    for pid in result:gmatch("%d+") do
        pids[#pids + 1] = pid
    end

    return pids
end

-- Check package installation
local function installed(pkg)
    local result = command(
        "pm path " .. quote(pkg)
    )

    return result:find("package:", 1, true) ~= nil
end

-- Resolve launcher activity
local function get_activity(pkg)
    local result = command(
        "cmd package resolve-activity --brief "
        .. quote(pkg)
    )

    for line in result:gmatch("[^\r\n]+") do
        if line:find("/", 1, true)
            and not line:find("No activity", 1, true) then
            return line
        end
    end

    return nil
end

-- Launch application
local function launch(pkg)
    if not installed(pkg) then
        log("Package unavailable: " .. pkg)
        return false
    end

    local activity = get_activity(pkg)

    if not activity then
        log("No launcher activity: " .. pkg)
        return false
    end

    print(C.YELLOW .. "[OPENING] " .. pkg .. C.RESET)

    local success = execute_android(
        "am start -W -n " .. quote(activity)
    )

    if success then
        log("Launch requested: " .. pkg)
        return true
    end

    log("Launch failed: " .. pkg)
    return false
end

-- Monitor
local function monitor(pkg)
    local pids = get_pids(pkg)

    if #pids > 0 then
        print(C.GREEN .. "[ONLINE] " .. pkg .. C.RESET)

        for _, pid in ipairs(pids) do
            print("  PID: " .. pid)
        end

        return
    end

    print(C.RED .. "[OFFLINE] " .. pkg .. C.RESET)
    log("Offline: " .. pkg)

    for attempt = 1, MAX_RETRIES do
        print(C.YELLOW ..
            "[ATTEMPT " .. attempt .. "/" .. MAX_RETRIES ..
            "] " .. pkg .. C.RESET)

        if launch(pkg) then
            os.execute("sleep " .. RETRY_DELAY)

            local new_pids = get_pids(pkg)

            if #new_pids > 0 then
                print(C.GREEN .. "[STARTED] " .. pkg .. C.RESET)
                log("Started: " .. pkg)
                return
            end
        end
    end

    print(C.RED .. "[FAILED] " .. pkg .. C.RESET)
    log("Unable to start: " .. pkg)
end

local function main()
    while true do
        os.execute("clear")

        print(C.CYAN ..
            "====================================")
        print("       SENTINEL REJOIN v" .. VERSION)
        print("====================================" .. C.RESET)

        print("ROOT: " ..
            (ROOT and C.GREEN .. "YES" or C.YELLOW .. "NO")
            .. C.RESET)

        local packages = discover()

        print("FOUND: " .. #packages)
        print("------------------------------------")

        if #packages == 0 then
            print(C.RED .. "No Roblox package found." .. C.RESET)
        else
            for _, pkg in ipairs(packages) do
                monitor(pkg)
                print("------------------------------------")
            end
        end

        print("NEXT SCAN: " .. INTERVAL .. " seconds")
        os.execute("sleep " .. INTERVAL)
    end
end

main()
