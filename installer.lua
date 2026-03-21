-- Configuration
local GITHUB_USER = "MC-GGHJK"
local GITHUB_REPO = "computercraft-ota-server"
local BRANCH = "main"
local BASE_URL = "https://raw.githubusercontent.com/" .. GITHUB_USER .. "/" .. GITHUB_REPO .. "/" .. BRANCH .. "/"
local MANIFEST_FILE = "content.json"

-- Blacklist (skip update if exists)
local BLACKLIST = {
    ["config.lua"] = true,
    ["settings.json"] = true
}

-- UI Colors
local BG_COLOR = colors.blue
local TEXT_COLOR = colors.white
local HEADER_BG = colors.gray
local HEADER_TEXT = colors.white
local BAR_BG = colors.black
local BAR_FILL = colors.yellow
local ERROR_COLOR = colors.red

local w, h = term.getSize()

local function centerText(y, text, txtColor, bgColor)
    term.setCursorPos(math.floor((w - #text) / 2) + 1, y)
    if txtColor then term.setTextColor(txtColor) end
    if bgColor then term.setBackgroundColor(bgColor) end
    term.write(text)
end

local function drawUI(status, subStatus, percent)
    term.setBackgroundColor(BG_COLOR)
    term.clear()

    term.setCursorPos(1, 1)
    term.setBackgroundColor(HEADER_BG)
    term.setTextColor(HEADER_TEXT)
    term.clearLine()
    centerText(1, "System Update Installer", HEADER_TEXT, HEADER_BG)

    centerText(math.floor(h/2) - 2, status or "Initializing...", TEXT_COLOR, BG_COLOR)
    if subStatus then
        centerText(math.floor(h/2) - 1, subStatus, colors.lightGray, BG_COLOR)
    end

    if percent then
        local barWidth = w - 6
        local filled = math.floor(barWidth * percent)

        term.setCursorPos(4, math.floor(h/2) + 1)
        term.setBackgroundColor(BAR_BG)
        term.write(string.rep(" ", barWidth))

        if filled > 0 then
            term.setCursorPos(4, math.floor(h/2) + 1)
            term.setBackgroundColor(BAR_FILL)
            term.write(string.rep(" ", filled))
        end

        local pctText = math.floor(percent * 100) .. "%"
        centerText(math.floor(h/2) + 2, pctText, TEXT_COLOR, BG_COLOR)
    end
end

-- File helpers
local function readFile(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    local c = f.readAll()
    f.close()
    return c
end

local function saveFile(path, content)
    local dir = fs.getDir(path)
    if not fs.exists(dir) and dir ~= "" then
        fs.makeDir(dir)
    end
    local f = fs.open(path, "w")
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

-- Simple hash (must match manifest!)
local function simpleHash(str)
    local hash = 0
    for i = 1, #str do
        hash = (hash * 31 + string.byte(str, i)) % 2^32
    end
    return tostring(hash)
end

local function getFileHash(path)
    local content = readFile(path)
    if not content then return nil end
    return simpleHash(content)
end

local function update()
    drawUI("Fetching manifest...", "Connecting to GitHub...", 0)

    local manifestUrl = BASE_URL .. MANIFEST_FILE
    local newManifestJson = downloadUrl(manifestUrl)

    if not newManifestJson then
        drawUI("Error: Connection Failed", nil, 0)
        sleep(3)
        return
    end

    local newManifest = textutils.unserializeJSON(newManifestJson)
    if not newManifest then
        drawUI("Error: Invalid Manifest", nil, 0)
        sleep(3)
        return
    end

    drawUI("Analyzing files...", "Hashing local files...", 0)

    local filesToUpdate = {}

    for _, item in ipairs(newManifest) do
        local path = item.path
        local newHash = item.sha256

        local exists = fs.exists(path)
        local localHash = getFileHash(path)

        -- BLACKLIST LOGIC
        if BLACKLIST[path] and exists then
            -- skip
        else
            if (not exists) or (localHash ~= newHash) then
                table.insert(filesToUpdate, item)
            end
        end
    end

    local totalUpdates = #filesToUpdate

    if totalUpdates == 0 then
        saveFile(MANIFEST_FILE, newManifestJson)
        drawUI("System is up to date", "No changes detected", 1)
        sleep(2)
        return
    end

    for i, item in ipairs(filesToUpdate) do
        local progress = (i - 1) / totalUpdates
        drawUI("Updating system...", item.path, progress)

        local content = downloadUrl(item.url)
        if content then
            saveFile(item.path, content)
        else
            drawUI("Download failed", item.path, progress)
            sleep(1)
        end
    end

    saveFile(MANIFEST_FILE, newManifestJson)
    drawUI("Update Complete!", "Updated " .. totalUpdates .. " files", 1)
    sleep(3)
    os.reboot()
end

-- Main
term.setBackgroundColor(BG_COLOR)
term.clear()

if not http then
    centerText(h/2, "HTTP API disabled!", ERROR_COLOR, BG_COLOR)
    return
end

local ok, err = pcall(update)
if not ok then
    term.setBackgroundColor(colors.black)
    term.clear()
    printError("Fatal Error: " .. tostring(err))
end