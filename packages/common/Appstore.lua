local LIST_URL = "https://raw.githubusercontent.com/GGHJK-MC/CC-App-store/main/Github/list.json"

local function fetchJSON(url)
    local response = http.get(url)
    if not response then return nil end
    local content = response.readAll()
    response.close()
    local ok, data = pcall(textutils.unserialiseJSON, content)
    return ok and data or nil
end

local function downloadFile(url, path)
    local response = http.get(url)
    if not response then return false end

    local dir = fs.getDir(path)
    if dir ~= "." and not fs.exists(dir) then
        fs.makeDir(dir)
    end

    local file = fs.open(path, "w")
    file.write(response.readAll())
    file.close()
    response.close()
    return true
end

local function drawHeader()
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.setCursorPos(1,1)
    term.clearLine()
    term.write(" CC App Store - Click to Install")
    term.setBackgroundColor(colors.black)
end

local function showAppList(packages)
    term.clear()
    drawHeader()
    if not packages or #packages == 0 then
        term.setCursorPos(2, 3)
        term.setTextColor(colors.red)
        term.write("No apps found.")
        return
    end

    for i, pkg in ipairs(packages) do
        term.setCursorPos(2, i + 2)
        term.setTextColor(colors.yellow)
        term.write(pkg.name or "Unknown")

        local category = pkg.category or "N/A"
        term.setCursorPos(20, i + 2)
        term.setTextColor(colors.lightGray)
        term.write("[" .. category .. "]")
    end

    term.setCursorPos(2, 18)
    term.setTextColor(colors.red)
    term.write("Press 'q' to exit")
end

local function installApp(pkg)
    if not pkg or not pkg.metadata then return end

    term.setCursorPos(1, 15)
    term.clearLine()
    term.setTextColor(colors.cyan)
    term.write("Installing " .. (pkg.name or "app") .. "...")

    local meta = fetchJSON(pkg.metadata)
    if not meta or not meta.download or not meta.run then
        term.setCursorPos(1, 16)
        term.setTextColor(colors.red)
        term.write("Error: Invalid metadata.")
        sleep(2)
        return
    end

    if downloadFile(meta.download, meta.run) then
        term.setCursorPos(1, 16)
        term.setTextColor(colors.green)
        term.write("Installed successfully!")
    else
        term.setCursorPos(1, 16)
        term.setTextColor(colors.red)
        term.write("Download failed.")
    end
    sleep(2)
end

-- Main Execution
if not http then
    print("Error: HTTP API is not enabled.")
    return
end

term.clear()
term.setCursorPos(1,1)
print("Loading data...")

local data = fetchJSON(LIST_URL)
if not data or not data.packages then
    print("Error: Could not load store data.")
    print("URL: " .. LIST_URL)
    return
end

while true do
    showAppList(data.packages)
    local event, button, x, y = os.pullEvent()

    if event == "mouse_click" and button == 1 then
        local index = y - 2
        if data.packages[index] then
            installApp(data.packages[index])
        end
    elseif event == "char" and button == "q" then
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.clear()
        term.setCursorPos(1,1)
        break
    end
end
