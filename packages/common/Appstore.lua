local LIST_URL = "https://raw.githubusercontent.com/GGHJK-MC/CC-App-store/main/Github/list.json"

local function fetchJSON(url)
    local response = http.get(url)
    if not response then return nil end
    local content = response.readAll()
    response.close()
    return textutils.unserialiseJSON(content)
end

local function downloadFile(url, path)
    local response = http.get(url)
    if not response then return false end
    -- Ensure directory exists
    local dir = fs.getDir(path)
    if not fs.exists(dir) then
        fs.makeDir(dir)
    end

    local file = fs.open(path, "w")
    file.write(response.readAll())
    file.close()
    response.close()
    return true
end

local function drawHeader()
    term.clear()
    term.setCursorPos(1,1)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    print(" CC App Store - Click to Install")
    term.setBackgroundColor(colors.black)
end

local function showAppList(packages)
    drawHeader()
    for i, pkg in ipairs(packages) do
        term.setCursorPos(2, i + 2)
        term.setTextColor(colors.yellow)
        term.write(pkg.name)
        term.setCursorPos(20, i + 2)
        term.setTextColor(colors.lightGray)
        term.write("[" .. pkg.category .. "]")
    end

    term.setCursorPos(2, 18)
    term.setTextColor(colors.red)
    print("Press 'q' to exit")
end

local function installApp(pkg)
    term.setCursorPos(1, 15)
    term.clearLine()
    term.setTextColor(colors.cyan)
    print("Installing " .. pkg.name .. "...")

    local meta = fetchJSON(pkg.metadata)
    if not meta then
        term.setTextColor(colors.red)
        print("Error: Could not load metadata.")
        sleep(2)
        return
    end

    if downloadFile(meta.download, meta.run) then
        term.setTextColor(colors.green)
        print("Installed successfully!")
    else
        term.setTextColor(colors.red)
        print("Download failed.")
    end
    sleep(2)
end

-- Main Execution
if not http then
    print("Error: HTTP API is not enabled.")
    return
end

local data = fetchJSON(LIST_URL)
if not data then
    print("Error: Could not load store data.")
    return
end

while true do
    showAppList(data.packages)
    local event, button, x, y = os.pullEvent()

    if event == "mouse_click" then
        local index = y - 2
        if data.packages[index] then
            installApp(data.packages[index])
        end
    elseif event == "char" and button == "q" then
        term.clear()
        term.setCursorPos(1,1)
        break
    end
end
