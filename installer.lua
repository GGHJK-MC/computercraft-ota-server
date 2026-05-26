local GITHUB_USER = "GGHJK-MC"
local GITHUB_REPO = "computercraft-ota-server"
local BRANCH      = "main"
local BASE_URL     = "https://raw.githubusercontent.com/"..GITHUB_USER.."/"..GITHUB_REPO.."/"..BRANCH.."/"
local MANIFEST_FILE = "content.json"

local BLACKLIST = {
    ["/sys/etc/fstab"]  = true,
    ["/sys/etc/apps.db"] = true,
    [".settings"]        = true,
}

-- ============================================================
--  SHA-256 (optimalizovaná verze)
-- ============================================================
local function sha256(msg)
    local band, bxor, bor, bnot   = bit32.band, bit32.bxor, bit32.bor, bit32.bnot
    local rshift, lshift, rrotate = bit32.rshift, bit32.lshift, bit32.rrotate
    local sbyte, srep, schar, sfmt = string.byte, string.rep, string.char, string.format
    local MASK = 0xFFFFFFFF

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
    local bitLen = msgLen * 8
    msg = msg
        .. "\x80"
        .. srep("\x00", (55 - msgLen % 64) % 64)
        .. schar(0, 0, 0, 0,
                 band(rshift(bitLen, 24), 0xFF),
                 band(rshift(bitLen, 16), 0xFF),
                 band(rshift(bitLen,  8), 0xFF),
                 band(bitLen, 0xFF))

    local blockCount = 0
    for blk = 1, #msg, 64 do
        blockCount = blockCount + 1
        if blockCount % 15 == 0 then sleep(0) end

        local W = {}
        for j = 1, 16 do
            local o = blk + (j - 1) * 4
            local b1, b2, b3, b4 = sbyte(msg, o, o + 3)
            W[j] = bor(bor(bor(lshift(b1, 24), lshift(b2, 16)), lshift(b3, 8)), b4)
        end
        for j = 17, 64 do
            local w15 = W[j - 15]; local w2 = W[j - 2]
            local s0  = bxor(bxor(rrotate(w15, 7), rrotate(w15, 18)), rshift(w15, 3))
            local s1  = bxor(bxor(rrotate(w2, 17), rrotate(w2,  19)), rshift(w2,  10))
            W[j] = band(W[j - 16] + s0 + W[j - 7] + s1, MASK)
        end

        local a,b,c,d,e,f,g,hh = H[1],H[2],H[3],H[4],H[5],H[6],H[7],H[8]
        for j = 1, 64 do
            local S1    = bxor(bxor(rrotate(e,6), rrotate(e,11)), rrotate(e,25))
            local ch    = bxor(band(e,f), band(bnot(e),g))
            local temp1 = band(hh + S1 + ch + K[j] + W[j], MASK)
            local S0    = bxor(bxor(rrotate(a,2), rrotate(a,13)), rrotate(a,22))
            local maj   = bxor(bxor(band(a,b), band(a,c)), band(b,c))
            local temp2 = band(S0 + maj, MASK)
            hh=g; g=f; f=e; e=band(d+temp1,MASK)
            d=c;  c=b; b=a; a=band(temp1+temp2,MASK)
        end
        H[1]=band(H[1]+a,MASK); H[2]=band(H[2]+b,MASK)
        H[3]=band(H[3]+c,MASK); H[4]=band(H[4]+d,MASK)
        H[5]=band(H[5]+e,MASK); H[6]=band(H[6]+f,MASK)
        H[7]=band(H[7]+g,MASK); H[8]=band(H[8]+hh,MASK)
    end

    local out = {}
    for i, v in ipairs(H) do out[i] = sfmt("%08x", v) end
    return table.concat(out)
end

-- ============================================================
--  UI – OpusOS styl
-- ============================================================
local w, h = term.getSize()

-- Pixel logo "OTA" – blit řádky: text / fg / bg
-- Barvy: c=cyan(3), 7=lightGray, 0=black, 8=gray, b=lightBlue, f=white
local LOGO = {
    --  text            fg              bg
    { " OTA ",  "33333", "00000" },
    { "     ",  "00000", "00000" },
}

local function cls()
    term.setBackgroundColor(colors.black)
    term.clear()
end

local function writeAt(x, y, text, fg, bg)
    term.setCursorPos(x, y)
    if bg  then term.setBackgroundColor(bg)  end
    if fg  then term.setTextColor(fg)        end
    term.write(text)
end

local function centerWrite(y, text, fg, bg)
    local x = math.floor((w - #text) / 2) + 1
    writeAt(x, y, text, fg, bg)
end

-- Kreslí pixel logo uprostřed obrazovky od řádku startY
local function drawLogo(startY)
    -- Malý ASCII blit banner
    local banner = {
        "  ___  _____ ___ ",
        " / _ \\|_   _/ _ \\",
        "| | | | | || | | |",
        "| |_| | | || |_| |",
        " \\___/  |_| \\___/ ",
    }
    local bannerW = #banner[1]
    local bx = math.floor((w - bannerW) / 2) + 1
    for i, line in ipairs(banner) do
        writeAt(bx, startY + i - 1, line, colors.cyan, colors.black)
    end
end

-- Tenká oddělovací čára
local function drawDivider(y, col)
    writeAt(1, y, string.rep("\140", w), col or colors.gray, colors.black)
end

-- Progress bar v Opus stylu (bez rámečku, jen bloky)
local function drawBar(y, percent)
    local barW  = w - 4
    local filled = math.floor(barW * percent)
    local empty  = barW - filled

    term.setCursorPos(3, y)
    term.setBackgroundColor(colors.black)

    -- Filled část – světle modrá
    if filled > 0 then
        term.setBackgroundColor(colors.lightBlue)
        term.setTextColor(colors.blue)
        term.write(string.rep("\127", filled))
    end
    -- Prázdná část – tmavě šedá
    if empty > 0 then
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.gray)
        term.write(string.rep("\127", empty))
    end

    term.setBackgroundColor(colors.black)
end

-- Hlavní funkce kreslení
local STATE_NORMAL  = 0
local STATE_ERROR   = 1
local STATE_SUCCESS = 2

local function drawUI(status, subStatus, percent, state)
    cls()

    -- Logo (řádky 1–5)
    drawLogo(1)

    -- Oddělovač pod logem
    drawDivider(7)

    -- Status zpráva
    local statusColor = colors.white
    if state == STATE_ERROR   then statusColor = colors.red  end
    if state == STATE_SUCCESS then statusColor = colors.lime end

    centerWrite(9, status or "Initializing...", statusColor, colors.black)

    -- Sub-status (zkrácení pokud je moc dlouhé)
    if subStatus then
        local sub = subStatus
        if #sub > w - 2 then
            sub = "\26 " .. sub:sub(#sub - (w - 5))
        end
        centerWrite(10, sub, colors.gray, colors.black)
    end

    -- Progress bar
    if percent then
        drawBar(12, percent)
        local pct = string.format("%3d%%", math.floor(percent * 100))
        centerWrite(13, pct, colors.lightBlue, colors.black)
    end

    -- Oddělovač nad footerem
    drawDivider(h - 1)

    -- Footer – repo a verze
    writeAt(2, h, GITHUB_REPO, colors.gray, colors.black)
    local ver = "github/" .. GITHUB_USER
    writeAt(w - #ver, h, ver, colors.gray, colors.black)
end

-- ============================================================
--  Pomocné I/O funkce
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
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
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
--  Splash obrazovka (Opus styl – čeká na timer nebo klávesu)
-- ============================================================
local function splash()
    cls()
    drawLogo(math.floor(h / 2) - 3)

    local hint = "System Update Starting..."
    centerWrite(math.floor(h / 2) + 3, hint, colors.gray, colors.black)

    drawDivider(h - 1)
    writeAt(2, h, GITHUB_REPO, colors.gray, colors.black)

    -- Animovaný spinner po dobu 1.5 s (jako Opus delay)
    local frames = { "|", "/", "-", "\\" }
    local timer  = os.startTimer(1.5)
    local frame  = 1
    local tick   = os.startTimer(0.15)

    while true do
        local e, id = os.pullEvent()
        if e == "timer" and id == timer then
            break
        elseif e == "timer" and id == tick then
            centerWrite(math.floor(h / 2) + 5, frames[frame], colors.cyan, colors.black)
            frame = (frame % #frames) + 1
            tick  = os.startTimer(0.15)
        elseif e == "key" or e == "char" then
            break
        end
    end
end

-- ============================================================
--  Hlavní update logika
-- ============================================================
local function update()
    drawUI("Connecting to GitHub...", BASE_URL .. MANIFEST_FILE, 0)

    local manifestJson = downloadUrl(BASE_URL .. MANIFEST_FILE)
    if not manifestJson then
        drawUI("Connection failed", "Cannot reach GitHub – check HTTP config", nil, STATE_ERROR)
        sleep(4)
        return
    end

    local manifest = textutils.unserializeJSON(manifestJson)
    if not manifest then
        drawUI("Invalid manifest", "JSON parse error in " .. MANIFEST_FILE, nil, STATE_ERROR)
        sleep(4)
        return
    end

    -- Fáze 1: porovnání hashů
    drawUI("Verifying files...", "Comparing SHA-256 checksums...", 0)
    sleep(0.05)

    local filesToUpdate = {}
    local total = #manifest
    for idx, item in ipairs(manifest) do
        drawUI("Verifying files...", item.path, idx / total)

        if not BLACKLIST[item.path] then
            local existing = readFile(item.path)
            if not existing or sha256(existing) ~= item.sha256 then
                table.insert(filesToUpdate, item)
            end
        end

        if idx % 3 == 0 then sleep(0) end
    end

    local updateCount = #filesToUpdate

    if updateCount == 0 then
        saveFile(MANIFEST_FILE, manifestJson)
        drawUI("Up to date", "No files need updating", 1, STATE_SUCCESS)
        sleep(2.5)
        return
    end

    -- Fáze 2: stahování
    local downloaded = 0
    for i, item in ipairs(filesToUpdate) do
        local prog = (i - 1) / updateCount
        drawUI(
            string.format("Downloading  %d / %d", i, updateCount),
            item.path,
            prog
        )

        local content = downloadUrl(item.url)
        if content then
            if sha256(content) == item.sha256 then
                saveFile(item.path, content)
                downloaded = downloaded + 1
            else
                drawUI("Hash mismatch", item.path, prog, STATE_ERROR)
                sleep(1.5)
            end
        else
            drawUI("Download failed", item.path, prog, STATE_ERROR)
            sleep(1.5)
        end

        sleep(0)
    end

    saveFile(MANIFEST_FILE, manifestJson)
    drawUI(
        string.format("Done  –  %d file%s updated", downloaded, downloaded == 1 and "" or "s"),
        "Patching boot image...",
        1,
        STATE_SUCCESS
    )
    sleep(1.5)

    -- --------------------------------------------------------
    --  Původní init_boot logika (zachována beze změny)
    -- --------------------------------------------------------
    cls()
    term.setCursorPos(1, 1)
    local httpget = http.get(
        "https://raw.githubusercontent.com/GGHJK-MC/computercraft-ota-server/refs/heads/main/init_boot"
    )
    local content = httpget.readAll()
    httpget.close()
    local bootimgd = fs.open("/init_boot", "w")
    bootimgd.write(content)
    bootimgd.close()
    os.reboot()
end

-- ============================================================
--  Boot
-- ============================================================
cls()

if not http then
    drawUI("HTTP Disabled", "Enable http in computercraft-server.toml", nil, STATE_ERROR)
    sleep(5)
    return
end

splash()

local ok, err = pcall(update)
if not ok then
    drawUI("Fatal Error", tostring(err), nil, STATE_ERROR)
    sleep(6)
    cls()
    term.setCursorPos(1, 1)
end