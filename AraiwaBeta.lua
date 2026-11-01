#!/data/data/com.termux/files/usr/bin/lua

-- SENTINEL REJOIN v2.0
-- Termux Auto Discovery

local VERSION = "2.0"
local INTERVAL = 15

local BASE = os.getenv("HOME") .. "/.sentinel"
local LOG = BASE .. "/sentinel.log"

os.execute("mkdir -p " .. BASE)

local C = {
    RESET = "\27[0m",
    CYAN = "\27[36m",
    GREEN = "\27[32m",
    RED = "\27[31m",
    YELLOW = "\27[33m",
    WHITE = "\27[37m"
}

local function shell_quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function execute(cmd)
    local a, _, c = os.execute(cmd)
    return a == true or a == 0 or c == 0
end

local function command(cmd)
    local p = io.popen(cmd .. " 2>/dev/null")

    if not p then
        return ""
    end

    local result = p:read("*a") or ""
    p:close()

    return result
end

local function log(msg)
    local f = io.open(LOG, "a")

    if f then
        f:write(os.date("[%Y-%m-%d %H:%M:%S] ")
            .. msg .. "\n")
        f:close()
    end
end

local function header()
    os.execute("clear")

    print(C.CYAN .. [[
========================================
          SENTINEL REJOIN
             VERSION ]] .. VERSION .. [[
========================================
]] .. C.RESET)
end

-- ROOT CHECK
local function root_check()
    return command("id -u"):match("^0") ~= nil
end

-- FIND ROBLOX PACKAGES
local function find_packages()
    local result = command("pm list packages")
    local packages = {}

    for pkg in result:gmatch("package:([%w%._]+)") do
        local lower = pkg:lower()

        if lower:find("roblox", 1, true)
        or lower:find("delta", 1, true) then

            table.insert(packages, pkg)
        end
    end

    table.sort(packages)

    return packages
end

-- GET ALL PIDS
local function get_pids(pkg)
    local result = command(
        "pidof " .. shell_quote(pkg)
    )

    local pids = {}

    for pid in result:gmatch("%d+") do
        table.insert(pids, pid)
    end

    return pids
end

-- CHECK APPLICATION
local function check_app(pkg)
    local pids = get_pids(pkg)

    if #pids > 0 then
        print(C.GREEN .. "[ONLINE] " ..
            pkg .. C.RESET)

        for _, pid in ipairs(pids) do
            print("  PID: " .. pid)
        end

        return true
    end

    print(C.RED .. "[OFFLINE] " ..
        pkg .. C.RESET)

    log("OFFLINE: " .. pkg)

    return false
end

-- RESTART APPLICATION
local function restart_app(pkg)
    print(C.YELLOW ..
        "[RESTART] " .. pkg .. C.RESET)

    local cmd = "monkey -p " ..
        shell_quote(pkg) .. " 1"

    if root_check() then
        execute("su -c " .. shell_quote(cmd))
    else
        execute(cmd)
    end

    log("RESTART REQUESTED: " .. pkg)
end

-- MAIN LOOP
local function main()
    while true do
        header()

        print("ROOT: " ..
            (root_check() and
            C.GREEN .. "YES" or
            C.YELLOW .. "NO") .. C.RESET)

        print("----------------------------------------")

        local packages = find_packages()

        print("DISCOVERED: " .. #packages)
        print("----------------------------------------")

        if #packages == 0 then
            print(C.RED ..
                "No Roblox packages found." .. C.RESET)
        else
            for _, pkg in ipairs(packages) do
                local online = check_app(pkg)

                if not online then
                    restart_app(pkg)
                end

                print("----------------------------------------")
            end
        end

        print("NEXT SCAN: " .. INTERVAL .. " SECONDS")
        os.execute("sleep " .. INTERVAL)
    end
end

main()
