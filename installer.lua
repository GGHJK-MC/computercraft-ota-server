local GITHUB_USER = "GGHJK-MC"
local GITHUB_REPO = "computercraft-ota-server"
local BRANCH = "main"
local BASE_URL = "https://raw.githubusercontent.com/"..GITHUB_USER.."/"..GITHUB_REPO.."/"..BRANCH.."/"
local MANIFEST_FILE = "content.json"

local BLACKLIST = {
    ["/sys/etc/fstab"] = true,
    ["/sys/etc/apps.db"] = true,
    [".settings"] = true
}

-- ============================================================
--  SHA-256 (Optimalizováno o yieldy pro dlouhé soubory)
-- ============================================================
local function sha256(msg)
    local band, bxor, bor, bnot = bit32.band, bit32.bxor, bit32.bor, bit32.bnot
    local rshift, lshift, rrotate = bit32.rshift, bit32.lshift, bit32.rrotate
    local function badd(...)
        local s = 0
        for _, v in ipairs({...}) do s = band(s + v, 0xFFFFFFFF) end
        return s
    end
    local K = {
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
    }
    local H = {
        0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
        0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19,
    }
    local msgLen = #msg
    msg = msg .. "\x80"
    while #msg % 64 ~= 56 do msg = msg .. "\x00" end
    local bitLen = msgLen * 8
    for s = 56, 0, -8 do msg = msg .. string.char(band(rshift(bitLen, s), 0xFF)) end

    local blockCount = 0
    for blk = 1, #msg, 64 do
        blockCount = blockCount + 1
        -- Každých 15 bloků (necelý 1 KB) uvolníme CPU, aby ComputerCraft nepadal
        if blockCount % 15 == 0 then
            sleep(0)
        end

        local W = {}
        for j = 1, 16 do
            local o = blk + (j-1)*4
            W[j] = bor(bor(bor(lshift(msg:byte(o),24),lshift(msg:byte(o+1),16)),lshift(msg:byte(o+2),8)),msg:byte(o+3))
        end
        for j = 17, 64 do
            local s0 = bxor(bxor(rrotate(W[j-15],7),rrotate(W[j-15],18)),rshift(W[j-15],3))
            local s1 = bxor(bxor(rrotate(W[j-2],17),rrotate(W[j-2],19)),rshift(W[j-2],10))
            W[j] = badd(W[j-16], s0, W[j-7], s1)
        end
        local a,b,c,d,e,f,g,hh = H[1],H[2],H[3],H[4],H[5],H[6],H[7],H[8]
        for j = 1, 64 do
            local S1    = bxor(bxor(rrotate(e,6),rrotate(e,11)),rrotate(e,25))
            local ch    = bxor(band(e,f),band(bnot(e),g))
            local temp1 = badd(hh,S1,ch,K[j],W[j])
            local S0    = bxor(bxor(rrotate(a,2),rrotate(a,13)),rrotate(a,22))
            local maj   = bxor(bxor(band(a,b),band(a,c)),band(b,c))
            local temp2 = badd(S0,maj)
            hh=g; g=f; f=e; e=badd(d,temp1)
            d=c; c=b; b=a; a=badd(temp1,temp2)
        end
        H[1]=badd(H[1],a); H[2]=badd(H[2],b); H[3]=badd(H[3],c); H[4]=badd(H[4],d)
        H[5]=badd(H[5],e); H[6]=badd(H[6],f); H[7]=badd(H[7],g); H[8]=badd(H[8],hh)
    end
    local result = ""
    for _, v in ipairs(H) do result = result .. string.format("%08x", v) end
    return result
end

-- ============================================================
--  Téma a UI
-- ============================================================
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

local w, h = term.getSize()

local function centerText(y, text, txtColor, bgColor)
    term.setCursorPos(math.floor((w - #text) / 2) + 1, y)
    if txtColor then term.setTextColor(txtColor) end
    if bgColor then term.setBackgroundColor(bgColor) end
    term.write(text)
end

local function drawUI(status, subStatus, percent, isError, isSuccess)
    term.setBackgroundColor(THEME.bg)
    term.clear()

    term.setCursorPos(1, 1)
    term.setBackgroundColor(THEME.headerBg)
    term.setTextColor(THEME.headerText)
    term.clearLine()
    centerText(1, " OTA System Update ", THEME.headerText, THEME.headerBg)

    local statusColor = THEME.text
    if isError   then statusColor = THEME.errorText   end
    if isSuccess then statusColor = THEME.successText end

    centerText(math.floor(h/2) - 3, status or "Initializing...", statusColor, THEME.bg)

    if subStatus then
        -- Pokud je cesta k souboru moc dlouhá, ořízneme ji, aby se nerozbíjelo UI
        local displaySub = subStatus
        if #displaySub > w - 4 then
            displaySub = "..." .. string.sub(displaySub, #displaySub - (w - 8))
        end
        centerText(math.floor(h/2) - 2, displaySub, THEME.subText, THEME.bg)
    end

    if percent then
        local barWidth = w - 8
        local filled   = math.floor(barWidth * percent)

        term.setCursorPos(5, math.floor(h/2))
        term.setBackgroundColor(THEME.barBg)
        term.write(string.rep(" ", barWidth))

        if filled > 0 then
            term.setCursorPos(5, math.floor(h/2))
            term.setBackgroundColor(THEME.barFill)
            term.write(string.rep(" ", filled))
        end

        local pctText = math.floor(percent * 100) .. " %"
        centerText(math.floor(h/2) + 2, pctText, THEME.barFill, THEME.bg)
    end

    term.setCursorPos(2, h)
    term.setBackgroundColor(THEME.bg)
    term.setTextColor(colors.gray)
    term.write("System: " .. GITHUB_REPO)
end

-- ============================================================
--  Pomocné funkce
-- ============================================================
local function readFile(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    local c = f.readAll()
    f.close()
    return c
end

local function saveFile(path, content)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then
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

-- ============================================================
--  Hlavní update logika
-- ============================================================
local function update()
    drawUI("Fetching manifest...", "Connecting to GitHub...", 0)

    local manifestJson = downloadUrl(BASE_URL .. MANIFEST_FILE)
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

    drawUI("Checking files...", "Comparing hashes...", 0)
    sleep(0.1)

    local filesToUpdate = {}
    for idx, item in ipairs(manifest) do
        local path = item.path

        -- Průběžně aktualizujeme UI, ať uživatel vidí, co se kontroluje
        drawUI("Checking files...", path, idx / #manifest)

        if not BLACKLIST[path] then
            local existing = readFile(path)
            if not existing or sha256(existing) ~= item.sha256 then
                table.insert(filesToUpdate, item)
            end
        end

        -- OCHRANA: Každé 3 soubory vydechneme, aby se resetoval watch-dog časovač
        if idx % 3 == 0 then
            sleep(0)
        end
    end

    local total = #filesToUpdate

    if total == 0 then
        saveFile(MANIFEST_FILE, manifestJson)
        drawUI("Nothing to update", "System is up to date", 1, false, true)
        sleep(2)
        return
    end

    local downloaded = 0
    for i, item in ipairs(filesToUpdate) do
        drawUI("Downloading files...", item.path, (i - 1) / total)

        local content = downloadUrl(item.url)
        if content then
            if sha256(content) == item.sha256 then
                saveFile(item.path, content)
                downloaded = downloaded + 1
            else
                drawUI("Hash mismatch!", item.path, (i - 1) / total, true)
                sleep(1.5)
            end
        else
            drawUI("Download failed", item.path, (i - 1) / total, true)
            sleep(1.5)
        end

        -- Pauza mezi stahováním (síťové operace sice yieldují samy, ale jistota je jistota)
        sleep(0)
    end

    saveFile(MANIFEST_FILE, manifestJson)
    drawUI("Update Complete!", downloaded .. " files updated.", 1, false, true)
    sleep(3)

    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    local httpget = http.get("https://raw.githubusercontent.com/GGHJK-MC/computercraft-ota-server/refs/heads/main/init_boot")
    local content = httpget.readAll()
    local bootimgd = fs.open("/init_boot", "w")
    bootimgd.write(content)
    os.reboot()
end

-- ============================================================
--  Spuštění
-- ============================================================
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
    term.setCursorPos(1, 1)
end