local GITHUB_USER = "MC-GGHJK"
local GITHUB_REPO = "computercraft-ota-server"
local BRANCH = "main"
local BASE_URL = "https://raw.githubusercontent.com/"..GITHUB_USER.."/"..GITHUB_REPO.."/"..BRANCH.."/"
local MANIFEST_FILE = "content.json"

local BLACKLIST = {
    ["config.lua"] = true,
    ["settings.json"] = true
}

-- Vylepšená paleta barev (Moderní Dark Theme)
local THEME = {
    bg = colors.black,
    text = colors.white,
    headerBg = colors.cyan,
    headerText = colors.black,
    barBg = colors.gray,
    barFill = colors.lightBlue,
    subText = colors.lightGray,
    errorText = colors.red,
    successText = colors.lime
}

local w,h = term.getSize()

local function centerText(y, text, txtColor, bgColor)
    term.setCursorPos(math.floor((w-#text)/2)+1, y)
    if txtColor then term.setTextColor(txtColor) end
    if bgColor then term.setBackgroundColor(bgColor) end
    term.write(text)
end

local function drawUI(status, subStatus, percent, isError, isSuccess)
    term.setBackgroundColor(THEME.bg)
    term.clear()

    -- Hlavička
    term.setCursorPos(1,1)
    term.setBackgroundColor(THEME.headerBg)
    term.setTextColor(THEME.headerText)
    term.clearLine()
    centerText(1, " OTA System Update ", THEME.headerText, THEME.headerBg)

    -- Hlavní status text
    local statusColor = THEME.text
    if isError then statusColor = THEME.errorText end
    if isSuccess then statusColor = THEME.successText end
    
    centerText(math.floor(h/2)-3, status or "Initializing...", statusColor, THEME.bg)

    -- Detailní text pod statusem
    if subStatus then
        centerText(math.floor(h/2)-2, subStatus, THEME.subText, THEME.bg)
    end

    -- Progress bar
    if percent then
        local barWidth = w - 8 -- Větší okraje pro lepší vzhled
        local filled = math.floor(barWidth * percent)

        -- Pozadí baru
        term.setCursorPos(5, math.floor(h/2))
        term.setBackgroundColor(THEME.barBg)
        term.write(string.rep(" ", barWidth))

        -- Výplň baru
        if filled > 0 then
            term.setCursorPos(5, math.floor(h/2))
            term.setBackgroundColor(THEME.barFill)
            term.write(string.rep(" ", filled))
        end

        -- Procenta
        local pctText = math.floor(percent*100).." %"
        centerText(math.floor(h/2)+2, pctText, THEME.barFill, THEME.bg)
    end

    -- Patička
    term.setCursorPos(2, h)
    term.setBackgroundColor(THEME.bg)
    term.setTextColor(colors.gray)
    term.write("System: " .. GITHUB_REPO)
end

local function readFile(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path,"r")
    local c = f.readAll()
    f.close()
    return c
end

local function saveFile(path, content)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    local f = fs.open(path,"w")
    f.write(content)
    f.close()
end

local function downloadUrl(url)
    local r = http.get(url)
    if r then
        local c = r.readAll()
        r.close()
        return c
    end
    return nil
end

local function update()
    drawUI("Fetching manifest...", "Connecting to GitHub...", 0)

    local manifestUrl = BASE_URL .. MANIFEST_FILE
    local manifestJson = downloadUrl(manifestUrl)

    if not manifestJson then
        drawUI("Connection failed", "Check your internet or URL", 0, true)
        sleep(3)
        return
    end

    local manifest = textutils.unserializeJSON(manifestJson)

    if not manifest then
        drawUI("Invalid manifest", "Failed to parse JSON", 0, true)
        sleep(3)
        return
    end

    local filesToUpdate = {}
    drawUI("Preparing update...", "Checking files...", 0)

    for _, item in ipairs(manifest) do
        local path = item.path
        if not BLACKLIST[path] then
            table.insert(filesToUpdate, item)
        end
    end

    local total = #filesToUpdate

    if total == 0 then
        saveFile(MANIFEST_FILE, manifestJson)
        drawUI("Nothing to update", "System is up to date", 1, false, true)
        sleep(2)
        return
    end

    for i, item in ipairs(filesToUpdate) do
        local progress = (i-1)/total
        drawUI("Downloading files...", "/" .. item.path, progress)

        local content = downloadUrl(item.url)

        if content then
            saveFile(item.path, content)
        else
            drawUI("Download failed", "/" .. item.path, progress, true)
            sleep(1.5)
        end
    end

    saveFile(MANIFEST_FILE, manifestJson)
    drawUI("Update Complete!", total.." files updated successfully.", 1, false, true)
    sleep(3)
    
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1,1)
    os.reboot()
end

-- Hlavní spouštěcí logika
term.setBackgroundColor(THEME.bg)
term.clear()

if not http then
    drawUI("HTTP API disabled!", "Enable HTTP in ComputerCraft config", nil, true)
    sleep(4)
    return
end

local ok, err = pcall(update)

if not ok then
    drawUI("Fatal Error Occurred", tostring(err), nil, true)
    sleep(5)
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1,1)
end
