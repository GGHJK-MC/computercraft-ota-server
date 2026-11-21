local GITHUB_USER = "cct"
local GITHUB_REPO = "os"
local BRANCHES = {
    { branch = 'latest-stable', description = 'Latest Stable(Best)' },
    { branch = 'latest',        description = 'Latest Version' },
    { branch = 'develop-2.0',   description = '2.x.x Development' },
    { branch = 'develop-2.0',   description = '2.x.x Stable' },
    { branch = 'master-1.0',    description = '1.x.x !Nedostává Aktualizace!' },
    { branch = 'develop-1.0',   description = '1.x.x !Nedostává Aktualizace!' },
}

local ARG_BRANCH = ...
if type(ARG_BRANCH) == 'string' then
    ARG_BRANCH = ARG_BRANCH:gsub('^-', '')
else
    ARG_BRANCH = nil
end
local FORCED_BRANCH
for _, option in ipairs(BRANCHES) do
    if option.branch == ARG_BRANCH then
        FORCED_BRANCH = option.branch
        break
    end
end

local BRANCH        = FORCED_BRANCH or BRANCHES[1].branch
local BASE_URL
local MANIFEST_FILE = "content.json"
local BOOT_URL
local HTTP_TIMEOUT  = 30

local function setBranch(branch)
    BRANCH   = branch
    BASE_URL = "https://cdn.gghjk.qzz.io/"..GITHUB_USER.."/"..GITHUB_REPO.."/"..BRANCH.."/"
    BOOT_URL = "https://cdn.gghjk.qzz.io/cct/os/boot.img"
end
setBranch(BRANCH)

local BLACKLIST = {
	["/sys/etc/fstab"]    = true,
	["/sys/etc/apps.db"]  = true,
    ["/.settings"]        = true,
    ["/usr/config/"]       = true,
}

local function isBlacklisted(path)
	path = tostring(path):gsub('^/', '')
	for blocked in pairs(BLACKLIST) do
		if path == blocked or path:sub(1, #blocked + 1) == blocked .. '/' then
			return true
		end
	end
	return false
end

local function djb2(data)
	local hash = 5381
	for i = 1, #data do
		hash = bit32.band(bit32.lshift(hash, 5) + hash + data:byte(i), 0xffffffff)
	end
	return string.format('%08x', hash)
end

local function localDjb2(path)
	if not fs.exists(path) or fs.isDir(path) then return nil end
	local file = fs.open(path, 'rb')
	if not file then return nil end
	local ok, data = pcall(file.readAll)
	file.close()
	if not ok or type(data) ~= 'string' then return nil end
	return djb2(data)
end

-- Pomocné funkce
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function now()
    if os.epoch then return os.epoch("utc") / 1000 end
    return os.clock()
end

local function fmtBytes(n)
    if n < 1024 then return string.format("%d B", floor(n)) end
    if n < 1048576 then return string.format("%.1f KB", n / 1024) end
    return string.format("%.2f MB", n / 1048576)
end

local function fmtTime(s)
    s = max(0, floor(s + 0.5))
    return string.format("%d:%02d", floor(s / 60), s % 60)
end


local function clip(s, n)
    s = tostring(s)
    if n <= 0 then return "" end
    if #s <= n then return s end
    if n <= 2 then return s:sub(1, n) end
    return s:sub(1, n - 2) .. ".."
end


local function clipPath(s, n)
    s = tostring(s)
    if n <= 0 then return "" end
    if #s <= n then return s end
    if n <= 2 then return s:sub(-n) end
    return ".." .. s:sub(-(n - 2))
end

local function wrap(s, width)
    local lines = {}
    for para in (tostring(s) .. "\n"):gmatch("(.-)\n") do
        local line = ""
        for token in para:gmatch("%S+") do
            local word = token
            while #word > width do
                if line ~= "" then lines[#lines + 1] = line; line = "" end
                lines[#lines + 1] = word:sub(1, width)
                word = word:sub(width + 1)
            end
            if line == "" then
                line = word
            elseif #line + 1 + #word <= width then
                line = line .. " " .. word
            else
                lines[#lines + 1] = line
                line = word
            end
        end
        lines[#lines + 1] = line
    end
    return lines
end


local hasColor   = (term.isColor and term.isColor()) and true or false
local canPalette = hasColor and term.setPaletteColor ~= nil and term.getPaletteColor ~= nil

local HEXCH = "0123456789abcdef"
local function blitOf(c)                       -- barva CC -> znak pro term.blit
    local n = floor(math.log(c) / math.log(2) + 0.5)
    return HEXCH:sub(n + 1, n + 1)
end

local PALETTE = {
    { colors.black,     0x0A0F1C },   -- pozadí
    { colors.gray,      0x131A2B },   -- panel
    { colors.brown,     0x2A3550 },   -- stopa progress baru, linky
    { colors.lightGray, 0x94A3B8 },   -- tlumený text
    { colors.white,     0xE2E8F0 },   -- hlavní text
    { colors.blue,      0x3B82F6 },   -- akcent
    { colors.lightBlue, 0x60A5FA },   -- světlý akcent
    { colors.green,     0x172A4D },   -- zvýrazněný řádek
    { colors.cyan,      0x22D3EE },   -- gradient loga
    { colors.purple,    0x8B5CF6 },
    { colors.magenta,   0xD946EF },
    { colors.pink,      0xF472B6 },
    { colors.lime,      0x4ADE80 },   -- úspěch
    { colors.red,       0xF87171 },   -- chyba
    { colors.yellow,    0xFBBF24 },   -- varování
}

local T, GRAD = {}, {}
local function buildTheme()
    local B = blitOf
    T.bg, T.dim, T.text = B(colors.black), B(colors.lightGray), B(colors.white)
    if not hasColor then
        T.panel, T.track = B(colors.black), B(colors.gray)
        T.accent, T.accent2 = B(colors.white), B(colors.white)
        T.selBg, T.selFg, T.selSub, T.hotFg = B(colors.white), B(colors.black), B(colors.black), B(colors.black)
        T.ok, T.err, T.warn = B(colors.white), B(colors.white), B(colors.white)
        GRAD = { B(colors.white) }
        return
    end
    T.accent, T.accent2 = B(colors.blue), B(colors.lightBlue)
    T.selFg, T.selSub, T.hotFg = B(colors.white), B(colors.lightBlue), B(colors.white)
    T.ok, T.err, T.warn = B(colors.lime), B(colors.red), B(colors.yellow)
    GRAD = { B(colors.cyan), B(colors.lightBlue), B(colors.blue),
             B(colors.purple), B(colors.magenta), B(colors.pink) }
    if canPalette then
        T.panel, T.track, T.selBg = B(colors.gray), B(colors.brown), B(colors.green)
    else
        T.panel, T.track, T.selBg = B(colors.black), B(colors.gray), B(colors.blue)
    end
end
buildTheme()

local ALLCOLORS = { colors.white, colors.orange, colors.magenta, colors.lightBlue,
    colors.yellow, colors.lime, colors.pink, colors.gray, colors.lightGray, colors.cyan,
    colors.purple, colors.blue, colors.brown, colors.green, colors.red, colors.black }

local function hexRGB(hex)
    return floor(hex / 65536) % 256 / 255, floor(hex / 256) % 256 / 255, hex % 256 / 255
end

local savedPalette
local function applyPalette()
    if not canPalette then return end
    if not savedPalette then
        savedPalette = {}
        for _, c in ipairs(ALLCOLORS) do
            local r, g, b = term.getPaletteColor(c)
            savedPalette[#savedPalette + 1] = { c, r, g, b }
        end
    end
    for _, e in ipairs(PALETTE) do
        local r, g, b = hexRGB(e[2])
        term.setPaletteColor(e[1], r, g, b)
    end
end

local function restorePalette()
    if not savedPalette then return end
    for _, e in ipairs(savedPalette) do term.setPaletteColor(e[1], e[2], e[3], e[4]) end
end

local function setFade(f)
    if not canPalette then return end
    local br, bgc, bb = hexRGB(PALETTE[1][2])
    for i = 2, #PALETTE do
        local r, g, b = hexRGB(PALETTE[i][2])
        term.setPaletteColor(PALETTE[i][1], br + (r - br) * f, bgc + (g - bgc) * f, bb + (b - bb) * f)
    end
end


local W, H = term.getSize()
local bch, bfg, bbg, lastRow = {}, {}, {}, {}

local function resetBuffer()
    W, H = term.getSize()
    bch, bfg, bbg, lastRow = {}, {}, {}, {}
    for y = 1, H do
        local c, f, b = {}, {}, {}
        for x = 1, W do c[x] = " "; f[x] = T.text; b[x] = T.bg end
        bch[y], bfg[y], bbg[y] = c, f, b
    end
end

local function clear()
    for y = 1, H do
        local c, f, b = bch[y], bfg[y], bbg[y]
        for x = 1, W do c[x] = " "; f[x] = T.text; b[x] = T.bg end
    end
end


local function put(x, y, s, fg, bg)
    if y < 1 or y > H then return end
    local c, f, b = bch[y], bfg[y], bbg[y]
    for i = 1, #s do
        local cx = x + i - 1
        if cx >= 1 and cx <= W then
            c[cx] = s:sub(i, i)
            if fg then f[cx] = fg end
            if bg then b[cx] = bg end
        end
    end
end

local function rect(x, y, w, h, bg)
    for yy = max(1, y), min(H, y + h - 1) do
        local c, b = bch[yy], bbg[yy]
        for xx = max(1, x), min(W, x + w - 1) do c[xx] = " "; b[xx] = bg end
    end
end

local function center(y, s, fg, bg)
    put(floor((W - #s) / 2) + 1, y, s, fg, bg)
end


local function flush()
    for y = 1, H do
        local a, f, b = table.concat(bch[y]), table.concat(bfg[y]), table.concat(bbg[y])
        local key = a .. f .. b
        if lastRow[y] ~= key then
            lastRow[y] = key
            term.setCursorPos(1, y)
            term.blit(a, f, b)
        end
    end
end


local WEIGHT = { 1, 2, 4, 8, 16, 32 }


local function encodeCell(p)
    local a, b = p[1], nil
    for i = 2, 6 do
        if p[i] ~= a then b = p[i]; break end
    end
    if not b then return " ", a, a end

    local seen, order = {}, {}
    for i = 1, 6 do
        local c = p[i]
        if not seen[c] then seen[c] = 0; order[#order + 1] = c end
        seen[c] = seen[c] + 1
    end
    if #order > 2 then
        table.sort(order, function(u, v)
            if seen[u] ~= seen[v] then return seen[u] > seen[v] end
            return u < v
        end)
        a, b = order[1], order[2]
    end

    local mask = 0
    for i = 1, 6 do
        if p[i] == a then mask = mask + WEIGHT[i] end
    end
    if mask >= 32 then
        return string.char(128 + 63 - mask), b, a
    end
    return string.char(128 + mask), a, b
end

local function setCell(x, y, chr, fg, bg)
    if x >= 1 and x <= W and y >= 1 and y <= H then
        bch[y][x], bfg[y][x], bbg[y][x] = chr, fg, bg
    end
end

local function paintPixels(cx, cy, bm, colorOf)
    local bw = 0
    for i = 1, #bm do if #bm[i] > bw then bw = #bm[i] end end
    local cols, rows = ceil(bw / 2), ceil(#bm / 3)
    for r = 0, rows - 1 do
        local y = cy + r
        if y >= 1 and y <= H then
            for c = 0, cols - 1 do
                local x = cx + c
                if x >= 1 and x <= W then
                    local under = bbg[y][x]
                    local p = {}
                    for i = 0, 5 do
                        local rowS = bm[r * 3 + floor(i / 2) + 1]
                        local px = c * 2 + (i % 2) + 1
                        local ch = rowS and rowS:sub(px, px) or ""
                        if ch == "" or ch == "." or ch == " " then
                            p[i + 1] = under
                        else
                            p[i + 1] = colorOf(c, r)
                        end
                    end
                    local chr, fg, bg = encodeCell(p)
                    bch[y][x], bfg[y][x], bbg[y][x] = chr, fg, bg
                end
            end
        end
    end
end

-- ============================================================
--  Grafické prvky
-- ============================================================

-- Panel se zaoblenými rohy (půl pixelu ze znaku 2x3)
local function panel(x, y, w, h, bg, outside)
    rect(x, y, w, h, bg)
    if w >= 2 and h >= 2 then
        setCell(x,         y,         "\129", outside, bg)
        setCell(x + w - 1, y,         "\130", outside, bg)
        setCell(x,         y + h - 1, "\144", outside, bg)
        setCell(x + w - 1, y + h - 1, "\159", bg, outside)
    end
end

-- Pilulka (štítek se zaoblenými konci); s = text včetně mezer, šířka = #s + 2
local function pill(x, y, s, fg, bg, outside)
    setCell(x, y, "\145", outside, bg)
    put(x + 1, y, s, fg, bg)
    setCell(x + #s + 1, y, "\157", bg, outside)
    return #s + 2
end

-- Klávesa + popisek; vrací použitou šířku
local function keycap(x, y, cap, label, hot)
    local w = pill(x, y, " " .. cap .. " ", hot and T.hotFg or T.text, hot and T.accent or T.track, T.bg)
    if label and label ~= "" then
        put(x + w + 1, y, label, T.dim, T.bg)
        w = w + 1 + #label
    end
    return w
end

-- items = { {klávesa, popisek, hot}, ... } -> x za posledním prvkem, oblasti pro myš
local function drawHints(items, y, x0)
    x0 = x0 or 2
    local avail = W - x0
    local function width(list, labels)
        local w = 0
        for i, it in ipairs(list) do
            w = w + #it[1] + 4
            if labels and it[2] and it[2] ~= "" then w = w + 1 + #it[2] end
            if i < #list then w = w + 2 end
        end
        return w
    end
    local labels = width(items, true) <= avail
    local list = items
    if not labels then
        while #list > 1 and width(list, false) > avail do
            local shorter = {}
            for i = 1, #list - 1 do shorter[i] = list[i] end
            list = shorter
        end
    end
    local x, spans = x0, {}
    for i, it in ipairs(list) do
        local w = keycap(x, y, it[1], labels and it[2] or nil, it[3])
        spans[#spans + 1] = { x, x + w - 1, i }
        x = x + w + 2
    end
    return x, spans
end

-- Cesta: adresář tlumeně, název souboru jasně; při nedostatku místa se zkrátí adresář
local function drawPath(x, y, n, path, dirFg, nameFg, bg)
    path = tostring(path or "")
    if n <= 0 then return end
    local dir, name = path:match("^(.*/)([^/]*)$")
    if not dir then dir, name = "", path end
    if #path > n then
        local room = n - #name
        if room <= 0 then
            dir, name = "", clipPath(name, n)
        elseif room < 3 then
            dir = ""
        else
            dir = ".." .. dir:sub(-(room - 2))
        end
    end
    put(x, y, dir, dirFg, bg)
    put(x + #dir, y, name, nameFg, bg)
end

-- Progress bar: 1 řádek, rozlišení půl znaku, zaoblené konce.
-- o: fill, track, out, hi, t, indet (neurčitý postup), shine (záblesk)
local function bar(x, y, wc, frac, o)
    if wc < 2 or y < 1 or y > H then return end
    local fillC, trackC = o.fill or T.accent, o.track or T.track
    local outC, hiC, t = o.out or T.bg, o.hi or T.accent2, o.t or 0
    local npx = wc * 2
    local filled = o.indet and 0 or floor(clamp(frac, 0, 1) * npx + 0.5)

    local headW, headPos = 0, 0
    if o.indet then
        headW = max(4, floor(npx / 4))
        local span = max(1, npx - headW)
        local ph = (t * 18) % (2 * span)
        headPos = floor(ph < span and ph or (2 * span - ph))
    end
    local shine
    if o.shine and not o.indet then
        shine = floor(t * 20) % (filled + 10) - 5
    end

    local function colAt(c)
        if o.indet then
            if c >= headPos and c < headPos + headW then return fillC end
            return trackC
        end
        if c < filled then
            if shine and c >= shine and c < shine + 4 then return hiC end
            return fillC
        end
        return trackC
    end

    for i = 0, wc - 1 do
        local a, b = colAt(2 * i), colAt(2 * i + 1)
        local p = { a, b, a, b, a, b }
        if a == b then                           -- zaoblené konce jen u jednobarevných buněk
            if i == 0 then p[1] = outC; p[5] = outC end
            if i == wc - 1 then p[2] = outC; p[6] = outC end
        end
        local chr, fg, bg = encodeCell(p)
        setCell(x + i, y, chr, fg, bg)
    end
end

-- Malý spinner (1 znak): dvě sousední tečky obíhají po obvodu
local RING = { 1, 2, 4, 6, 5, 3 }
local function spinner(x, y, t, color, bg)
    local k = floor(t * 10) % 6
    local p = { bg, bg, bg, bg, bg, bg }
    p[RING[k + 1]] = color
    p[RING[(k + 1) % 6 + 1]] = color
    local chr, fg, b = encodeCell(p)
    setCell(x, y, chr, fg, b)
end

-- Ikonky 4x3 pixely (2 znaky): hotovo / chyba
local SPR = {
    ok  = { "...#", "#.#.", ".#.." },
    err = { "#..#", ".##.", "#..#" },
}

-- Velká ikona 12x12 pixelů (6x4 znaky): kruh s vyříznutým symbolem
local function distSeg(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local l2 = dx * dx + dy * dy
    local t = l2 == 0 and 0 or clamp(((px - ax) * dx + (py - ay) * dy) / l2, 0, 1)
    local cx, cy = ax + t * dx, ay + t * dy
    return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
end

local ICON = {
    ok   = { r = 0.80, { 2.8, 6.4, 5.1, 8.7 }, { 5.1, 8.7, 9.4, 3.9 } },
    err  = { r = 0.65, { 3.6, 3.6, 8.4, 8.4 }, { 8.4, 3.6, 3.6, 8.4 } },
    warn = { r = 0.85, { 6.0, 2.6, 6.0, 6.0 }, { 6.0, 8.9, 6.0, 9.0 } },
}

local iconCache = {}
local function iconBitmap(kind)
    if iconCache[kind] then return iconCache[kind] end
    local def = ICON[kind] or ICON.err
    local bm = {}
    for y = 0, 11 do
        local row = {}
        for x = 0, 11 do
            local px, py = x + 0.5, y + 0.5
            local ch = "."
            if (px - 6) ^ 2 + (py - 6) ^ 2 <= 5.9 ^ 2 then
                ch = "#"
                for _, sg in ipairs(def) do
                    if distSeg(px, py, sg[1], sg[2], sg[3], sg[4]) <= def.r then ch = "." end
                end
            end
            row[#row + 1] = ch
        end
        bm[#bm + 1] = table.concat(row)
    end
    iconCache[kind] = bm
    return bm
end

-- ============================================================
--  Logo "GGHJK OTA": pixelový font 5x7, 25x3 znaků
-- ============================================================
local LOGO_TEXT = "GGHJK OTA"
local FONT = {
    G = { ".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###." },
    H = { "#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#" },
    J = { "..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.." },
    K = { "#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#" },
    O = { ".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###." },
    T = { "#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.." },
    A = { ".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#" },
}

local logoCache = {}
local function logoBitmap(scale)
    if logoCache[scale] then return logoCache[scale] end
    local rows = {}
    for r = 1, 9 do rows[r] = {} end
    local function addCols(spec)
        for r = 1, 9 do rows[r][#rows[r] + 1] = spec[r] end
    end
    for i = 1, #LOGO_TEXT do
        local g = FONT[LOGO_TEXT:sub(i, i)]
        if g then
            local spec = { "....." }
            for r = 1, 7 do spec[#spec + 1] = g[r] end
            spec[#spec + 1] = "....."
            addCols(spec)
            if i < #LOGO_TEXT then addCols({ ".", ".", ".", ".", ".", ".", ".", ".", "." }) end
        else
            addCols({ "...", "...", "...", "...", "...", "...", "...", "...", "..." })
        end
    end
    local out = {}
    for r = 1, 9 do
        local line = table.concat(rows[r])
        if scale > 1 then
            line = line:gsub(".", function(ch) return string.rep(ch, scale) end)
        end
        for _ = 1, scale do out[#out + 1] = line end
    end
    logoCache[scale] = out
    return out
end

-- glint = sloupec (v znacích), kterým právě probíhá záblesk
local function drawLogo(cx, cy, scale, glint)
    local cols = 25 * scale
    paintPixels(cx, cy, logoBitmap(scale), function(c)
        if glint and math.abs(c - glint) <= scale then return T.text end
        return GRAD[floor(c / cols * #GRAD) + 1]
    end)
end

local function textLogo(x, y)
    for i = 1, #LOGO_TEXT do
        local gi = floor((i - 1) / #LOGO_TEXT * #GRAD) + 1
        put(x + i - 1, y, LOGO_TEXT:sub(i, i), GRAD[gi], T.bg)
    end
end

-- Hlavička; vrací první volný řádek
local function header(showBranch)
    if H >= 17 and W >= 25 then
        drawLogo(floor((W - 25) / 2) + 1, 1, 1)
        if showBranch then
            local repo = GITHUB_USER .. "/" .. GITHUB_REPO
            local br = clip(BRANCH, max(4, W - 8))
            local total = #br + 4
            local withRepo = total + 1 + #repo <= W - 2
            if withRepo then total = total + 1 + #repo end
            local x = floor((W - total) / 2) + 1
            if withRepo then put(x, 4, repo, T.dim, T.bg); x = x + #repo + 1 end
            pill(x, 4, " " .. br .. " ", T.selSub, T.selBg, T.bg)
            return 6
        end
        return 5
    elseif H >= 9 then
        textLogo(2, 1)
        if showBranch then
            local br = clip(BRANCH, max(4, W - 18))
            local pw = #br + 4
            if 2 + #LOGO_TEXT + 2 + pw <= W then
                pill(W - pw, 1, " " .. br .. " ", T.selSub, T.selBg, T.bg)
            end
        end
        return 3
    end
    return 1
end

-- ============================================================
--  Události
-- ============================================================
local ACTIVE_LOG

local function pull()
    local e, a, b, c, d = os.pullEventRaw()
    if e == "terminate" then error("Terminated", 0) end
    if e == "term_resize" then resetBuffer() end

    if ACTIVE_LOG then
        if e == "char" and tostring(a):lower() == "d" then
            ACTIVE_LOG.showFullLog = not ACTIVE_LOG.showFullLog
            if not ACTIVE_LOG.showFullLog then ACTIVE_LOG.logScroll = 0 end
            return "log_view"
        elseif ACTIVE_LOG.showFullLog then
            local rows = max(1, H - 3)
            local top = ACTIVE_LOG.logScroll or 0
            local maxTop = max(1, #ACTIVE_LOG.logLines - rows + 1)
            if top == 0 then top = maxTop end
            if e == "key" then
                if a == keys.escape or a == keys.enter then
                    ACTIVE_LOG.showFullLog = false
                    ACTIVE_LOG.logScroll = 0
                elseif a == keys.up then
                    ACTIVE_LOG.logScroll = max(1, top - 1)
                elseif a == keys.down then
                    ACTIVE_LOG.logScroll = min(maxTop, top + 1)
                elseif a == keys.pageUp then
                    ACTIVE_LOG.logScroll = max(1, top - rows)
                elseif a == keys.pageDown then
                    ACTIVE_LOG.logScroll = min(maxTop, top + rows)
                elseif a == keys.home then
                    ACTIVE_LOG.logScroll = 1
                elseif a == keys["end"] then
                    ACTIVE_LOG.logScroll = 0
                end
                return "log_view"
            end
        end
    end
    return e, a, b, c, d
end

local function wait(sec, tick)
    local endT = now() + sec
    local timer = os.startTimer(0.05)
    while now() < endT do
        local e, a = pull()
        if e == "timer" and a == timer then
            timer = os.startTimer(0.05)
            if tick then tick() end
        elseif e == "term_resize" and tick then
            tick()
        end
    end
end

-- ============================================================
--  Splash obrazovka
-- ============================================================
local function splash()
    local DUR   = 2.4
    local scale = (W >= 52 and H >= 24) and 2 or 1
    local t0    = now()
    local repo  = GITHUB_USER .. "/" .. GITHUB_REPO

    local function frame()
        local t = now() - t0
        clear()
        local cols   = 25 * scale
        local useLogo = W >= cols
        local rows   = useLogo and 3 * scale or 1
        local y      = max(1, floor((H - (rows + 4)) / 2) + 1)

        if useLogo then
            local glint
            local gt = (t - 0.9) / 0.8
            if gt >= 0 and gt <= 1 then glint = floor(-2 + gt * (cols + 4)) end
            drawLogo(floor((W - cols) / 2) + 1, y, scale, glint)
        else
            textLogo(floor((W - #LOGO_TEXT) / 2) + 1, y)
        end

        local tag = "Over-the-air system updater"
        if #tag > W - 2 then tag = "System updater" end
        center(y + rows + 1, clip(tag, W - 2), T.dim, T.bg)

        local lw = min(21, W - 6)
        if lw >= 4 then
            local p  = clamp((t - 0.3) / (DUR - 0.7), 0, 1)
            local nf = floor(p * lw + 0.5)
            local x  = floor((W - lw) / 2) + 1
            for i = 1, lw do
                put(x + i - 1, y + rows + 3, "\140", i <= nf and T.accent2 or T.track, T.bg)
            end
        end

        if H >= 6 then
            put(2, H, clip(repo, W - 4), T.dim, T.bg)
            local hint = "any key to skip"
            if W >= #repo + #hint + 6 then put(W - #hint, H, hint, T.dim, T.bg) end
        end

        local f = min(clamp(t / 0.7, 0, 1), clamp((DUR - t) / 0.3, 0, 1))
        setFade(f * f * (3 - 2 * f))
        flush()
    end

    setFade(0)
    frame()
    local timer = os.startTimer(0.05)
    while now() - t0 < DUR do
        local e, a = pull()
        if e == "timer" and a == timer then
            timer = os.startTimer(0.05)
            frame()
        elseif e == "term_resize" then
            frame()
        elseif e == "key" or e == "char" or e == "mouse_click" then
            break
        end
    end
    setFade(1)
end

-- ============================================================
--  Výběr verze (šipky, W/S, 1-9, Enter, klik myší, kolečko)
-- ============================================================
local function selectBranch()
    local n = #BRANCHES
    local sel, top = 1, 1
    local hit = {}

    local function render()
        clear()
        hit = {}
        local y  = header(false)
        local pw = min(W - 2, 49)
        local px = floor((W - pw) / 2) + 1

        put(px, y, "Select version", T.text, T.bg)
        local repo = GITHUB_USER .. "/" .. GITHUB_REPO
        if pw >= #repo + 20 then put(px + pw - #repo, y, repo, T.dim, T.bg) end

        local listTop = y + 1
        local avail   = H - 1 - listTop
        local lines, pad
        if avail >= 2 * n + 2 then lines, pad = 2, 1
        elseif avail >= n + 2 then lines, pad = 1, 1
        else lines, pad = 1, 0 end
        local vis = clamp(floor((avail - 2 * pad) / lines), 1, n)

        if sel < top then top = sel end
        if sel > top + vis - 1 then top = sel - vis + 1 end
        top = clamp(top, 1, max(1, n - vis + 1))

        local ph = vis * lines + 2 * pad
        if pad > 0 then panel(px, listTop, pw, ph, T.panel, T.bg) else rect(px, listTop, pw, ph, T.panel) end

        for k = 0, vis - 1 do
            local i     = top + k
            local b     = BRANCHES[i]
            local ry    = listTop + pad + k * lines
            local isSel = (i == sel)
            local rowBg = isSel and T.selBg or T.panel
            local fg    = isSel and T.selFg or T.text
            local sub   = isSel and T.selSub or T.dim

            rect(px, ry, pw, lines, rowBg)
            if isSel then
                for l = 0, lines - 1 do setCell(px, ry + l, "\149", T.accent, T.selBg) end
            end
            local showNum = pw >= 30
            local textW   = showNum and (pw - 8) or (pw - 5)
            put(px + 3, ry, clip(b.description, textW), fg, rowBg)
            if showNum then put(px + pw - 3, ry, tostring(i), sub, rowBg) end
            if lines == 2 then
                put(px + 3, ry + 1, clip(b.branch, textW), sub, rowBg)
            elseif 3 + #b.description + 2 + #b.branch + 5 <= pw then
                put(px + pw - 5 - #b.branch, ry, b.branch, sub, rowBg)
            end
            hit[#hit + 1] = { ry, ry + lines - 1, i }
        end

        drawHints({ { "\24\25", "select" }, { "Enter", "confirm", true }, { "Q", "quit" } }, H)
        flush()
    end

    render()
    while true do
        local e, a, b, c = pull()
        if e == "key" then
            if a == keys.up then sel = (sel - 2) % n + 1; render()
            elseif a == keys.down then sel = sel % n + 1; render()
            elseif a == keys.home then sel = 1; render()
            elseif a == keys["end"] then sel = n; render()
            elseif a == keys.enter or a == keys.numPadEnter then return BRANCHES[sel].branch
            elseif a == keys.backspace then return nil
            end
        elseif e == "char" then
            local ch = tostring(a):lower()
            local num = tonumber(ch)
            if ch == "w" or ch == "k" then sel = (sel - 2) % n + 1; render()
            elseif ch == "s" or ch == "j" then sel = sel % n + 1; render()
            elseif ch == "q" then return nil
            elseif num and num >= 1 and num <= n then sel = floor(num); render()
            end
        elseif e == "mouse_scroll" then
            sel = clamp(sel + a, 1, n); render()
        elseif e == "mouse_click" then
            for _, h in ipairs(hit) do
                if c >= h[1] and c <= h[2] then
                    sel = h[3]; render()
                    return BRANCHES[sel].branch
                end
            end
        elseif e == "term_resize" then
            render()
        end
    end
end

-- ============================================================
--  Obrazovka s výsledkem (hotovo / chyba) + volitelný odpočet
--  r = { kind, title, lines, actions, countdown, countdownText, auto }
-- ============================================================
local function resultScreen(r)
    ACTIVE_LOG = nil
    local t0, spans = now(), {}
    local acts = r.actions or {}

    local function render()
        clear()
        local t  = now()
        local kc = (r.kind == "ok" and T.ok) or (r.kind == "err" and T.err) or T.warn
        local maxW = max(10, min(W - 4, 46))

        local lines = {}
        for i, l in ipairs(r.lines or {}) do
            if i > 1 and H >= 17 then lines[#lines + 1] = "" end
            for _, wl in ipairs(wrap(l, maxW)) do lines[#lines + 1] = wl end
        end

        local big   = H >= 15 and W >= 12
        local gapT  = (#lines > 0 and H >= 12) and 1 or 0
        local cd    = r.countdown and 3 or 0
        local fixed = (big and 5 or 0) + 1 + gapT + cd
        local maxLines = max(0, (H - 1) - fixed)
        if #lines > maxLines then
            local cut = {}
            for i = 1, maxLines do cut[i] = lines[i] end
            if maxLines > 0 then cut[maxLines] = clip(cut[maxLines], maxW - 1) .. "~" end
            lines = cut
        end

        local total = fixed + #lines
        local y = max(1, floor(((H - 1) - total) / 2) + 1)

        local title = clip(r.title or "", W - 2)
        if big then
            paintPixels(floor((W - 6) / 2) + 1, y, iconBitmap(r.kind), function() return kc end)
            y = y + 5
            center(y, title, T.text, T.bg)
        else
            local x = floor((W - (#title + 3)) / 2) + 1
            paintPixels(x, y, r.kind == "ok" and SPR.ok or SPR.err, function() return kc end)
            put(x + 3, y, title, T.text, T.bg)
        end
        y = y + 1 + gapT
        for i = 1, #lines do
            center(y, lines[i], T.dim, T.bg)
            y = y + 1
        end

        if r.countdown then
            local left = max(0, r.countdown - (t - t0))
            y = y + 1
            center(y, string.format(r.countdownText or "Closing in %ds", ceil(left)), T.dim, T.bg)
            local lw = min(21, W - 6)
            if lw >= 4 then
                local nf = floor(lw * left / r.countdown + 0.5)
                local x  = floor((W - lw) / 2) + 1
                for i = 1, lw do
                    put(x + i - 1, y + 1, "\140", i <= nf and T.accent2 or T.track, T.bg)
                end
            end
        end

        if H >= 3 then
            local items = {}
            for i, a in ipairs(acts) do items[i] = { a.cap, a.label, i == 1 } end
            local _, sp = drawHints(items, H)
            spans = sp
        end
        flush()
    end

    render()
    local timer = os.startTimer(0.1)
    while true do
        local e, a, b, c = pull()
        if e == "timer" and a == timer then
            if r.countdown and now() - t0 >= r.countdown then return r.auto end
            timer = os.startTimer(0.1)
            render()
        elseif e == "term_resize" then
            render()
        elseif e == "char" then
            local ch = tostring(a):lower()
            for _, act in ipairs(acts) do
                if act.chars and act.chars:find(ch, 1, true) then return act.ret end
            end
        elseif e == "key" then
            if (a == keys.enter or a == keys.numPadEnter or a == keys.space) and acts[1] then
                return acts[1].ret
            end
        elseif e == "mouse_click" then
            for _, s in ipairs(spans) do
                if c == H and b >= s[1] and b <= s[2] and acts[s[3]] then return acts[s[3]].ret end
            end
        end
    end
end

local A_RETRY = { cap = "R", label = "Retry",          ret = "retry", chars = "r" }
local A_BACK  = { cap = "B", label = "Change version", ret = "back",  chars = "b" }
local A_QUIT  = { cap = "Q", label = "Quit",           ret = "quit",  chars = "q" }

-- ============================================================
--  Obrazovka aktualizace
-- ============================================================
local function drawPhases(y, phase, t)
    local n    = 4
    local segW = floor((W - 4 - (n - 1)) / n)
    if segW < 2 then return end
    local x0 = floor((W - (n * segW + (n - 1))) / 2) + 1
    for i = 1, n do
        local col
        if i < phase then col = T.ok
        elseif i == phase then col = (floor(t * 2) % 2 == 0) and T.accent2 or T.accent
        else col = T.track end
        put(x0 + (i - 1) * (segW + 1), y, string.rep("\140", segW), col, T.bg)
    end
end

local function drawFullLog(S)
    local width = max(1, W - 2)
    if not S.logCache or S.logCache.count ~= #S.log or S.logCache.width ~= width then
        local lines = { }
        for _, entry in ipairs(S.log) do
            local label = entry.ok and '[OK] ' or '[ERR] '
            local value = label .. tostring(entry.path or '')
            if entry.info and entry.info ~= '' then value = value .. '  ' .. tostring(entry.info) end
            for i, line in ipairs(wrap(value, width)) do
                lines[#lines + 1] = {
                    text = line,
                    color = i == 1 and (entry.ok and T.ok or T.err) or T.dim,
                }
            end
        end
        S.logLines = lines
        S.logCache = { count = #S.log, width = width }
    end

    clear()
    center(1, 'FULL UPDATE LOG  ' .. #S.log .. ' entries', T.accent2)
    local rows = max(1, H - 3)
    local maxTop = max(1, #S.logLines - rows + 1)
    local top = S.logScroll == 0 and maxTop or clamp(S.logScroll, 1, maxTop)
    for row = 1, rows do
        local line = S.logLines[top + row - 1]
        if line then put(2, row + 1, line.text, line.color, T.bg) end
    end
    center(H, 'Up/Down scroll   Enter/Esc close', T.dim)
    flush()
end

local function drawUpdate(S)
    if S.showFullLog then
        drawFullLog(S)
        return
    end
    clear()
    local t = now()
    local y = header(true)

    local top = y + 2
    local ph  = H - 1 - top
    if ph >= 6 then
        drawPhases(y, S.phase, t)
    else
        top = y
        ph  = H - 1 - top
    end

    if ph >= 3 then
        local pw  = min(W - 2, 49)
        local px  = floor((W - pw) / 2) + 1
        local pad = ph >= 6 and 1 or 0
        panel(px, top, pw, ph, T.panel, T.bg)

        local ix, iw = px + 2, pw - 4
        if iw < 8 then ix, iw = px + 1, pw - 2 end
        local tx, tw = ix + 2, iw - 2

        -- rozvržení řádků panelu podle dostupné výšky
        local R = ph - 2 * pad
        local seq = {}
        if R >= 4 then seq[#seq + 1] = "title"; seq[#seq + 1] = "sub"
        elseif R >= 2 then seq[#seq + 1] = "title" end
        if R >= 5 then seq[#seq + 1] = "gap" end
        seq[#seq + 1] = "bar"
        if R >= 3 then seq[#seq + 1] = "stats" end
        local extra = R - #seq
        if extra >= 3 then seq[#seq + 1] = "gap"; extra = extra - 1 end
        local logRows = max(0, extra)
        for _ = 1, logRows do seq[#seq + 1] = "log" end

        local ry, logIdx = top + pad, 0
        for _, kind in ipairs(seq) do
            if kind == "title" then
                spinner(ix, ry, t, T.accent2, T.panel)
                local cnt = ""
                if S.phase == 2 and S.total > 0 then cnt = min(S.cur or 0, S.total) .. "/" .. S.total end
                local room  = tw - (#cnt > 0 and #cnt + 1 or 0)
                local title = S.title
                if #title > room and S.titleShort then title = S.titleShort end
                if #title > room and room < 9 then cnt = ""; room = tw end
                put(tx, ry, clip(title, room), T.text, T.panel)
                if #cnt > 0 then put(ix + iw - #cnt, ry, cnt, T.dim, T.panel) end
            elseif kind == "sub" then
                if S.isPath then
                    drawPath(tx, ry, tw, S.sub, T.dim, T.text, T.panel)
                else
                    put(tx, ry, clipPath(S.sub or "", tw), T.dim, T.panel)
                end
            elseif kind == "bar" then
                bar(ix, ry, iw, S.shown, {
                    indet = S.indet, shine = (S.phase == 2), t = t, out = T.panel,
                    fill = (S.bad > 0) and T.warn or T.accent,
                })
            elseif kind == "stats" then
                if S.indet then
                    put(ix, ry, clip(S.stats or "", iw), T.dim, T.panel)
                else
                    local pct = string.format("%d%%", floor(S.shown * 100 + 0.5))
                    put(ix, ry, pct, T.accent2, T.panel)
                    local right = ""
                    if S.t0 and S.frac > 0.02 and S.frac < 1 then
                        right = "ETA " .. fmtTime((t - S.t0) * (1 - S.frac) / S.frac)
                    end
                    local room = iw - #pct - 2 - (#right > 0 and #right + 2 or 0)
                    local mid  = fmtBytes(S.bytes)
                    if S.t0 and S.bytes > 0 and t - S.t0 >= 1 then
                        local full = mid .. "  " .. fmtBytes(S.bytes / (t - S.t0)) .. "/s"
                        if #full <= room then mid = full end
                    end
                    if #mid <= room then put(ix + #pct + 2, ry, mid, T.dim, T.panel) end
                    if #right > 0 and room >= 0 then put(ix + iw - #right, ry, right, T.dim, T.panel) end
                end
            elseif kind == "log" then
                logIdx = logIdx + 1
                local e = S.log[max(1, #S.log - logRows + 1) + logIdx - 1]
                if e then
                    setCell(ix, ry, "\132", e.ok and T.ok or T.err, T.panel)      -- tečka 3x3 px uprostřed
                    local info = clip(e.info or "", 18)
                    put(ix + iw - #info, ry, info, e.ok and T.dim or T.err, T.panel)
                    drawPath(ix + 2, ry, iw - 3 - #info, e.path, T.dim, e.ok and T.dim or T.err, T.panel)
                end
            end
            ry = ry + 1
        end
    end

    if H >= 3 then
        drawHints({ { "Ctrl+T", "hold to cancel" } }, H)
        local el = fmtTime(t - S.tStart)
        put(W - #el, H, el, T.dim, T.bg)
    end
    flush()
end

local function ease(S)
    local t  = now()
    local dt = min(0.5, t - (S.lastEase or t))
    S.lastEase = t
    S.shown = S.shown + (S.frac - S.shown) * (1 - math.exp(-dt * 8))
    if math.abs(S.frac - S.shown) < 0.002 then S.shown = S.frac end
end

local function settle(S, redraw)
    local deadline = now() + 0.8
    local timer = os.startTimer(0.05)
    while S.shown ~= S.frac and now() < deadline do
        local e, a = pull()
        if e == "timer" and a == timer then
            timer = os.startTimer(0.05)
            redraw()
        elseif e == "term_resize" then
            redraw()
        end
    end
    S.shown = S.frac
    redraw()
end

local function addLog(S, ok, path, info)
    S.log[#S.log + 1] = { ok = ok, path = path, info = info }
end

-- ============================================================
--  Síť a I/O
-- ============================================================
local function saveFile(path, content)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local f = fs.open(path, "w")
    if not f then error("cannot write " .. tostring(path), 0) end
    f.write(content)
    f.close()
end

-- Neblokující stahování: během čekání se překresluje UI (tick).
-- Vrací obsah, nebo nil + důvod chyby (HTTP kód / zpráva)
local function fetch(url, tick)
    local ok, rerr = pcall(http.request, url)
    if not ok then return nil, tostring(rerr) end
    local deadline = os.startTimer(HTTP_TIMEOUT)
    local anim     = os.startTimer(0.1)
    while true do
        local e, a, b, c = pull()
        if e == "http_success" and a == url then
            os.cancelTimer(deadline); os.cancelTimer(anim)
            local data = b.readAll()
            b.close()
            if not data or #data == 0 then return nil, "empty response" end
            return data
        elseif e == "http_failure" and a == url then
            os.cancelTimer(deadline); os.cancelTimer(anim)
            local code
            if c then
                if c.getResponseCode then code = c.getResponseCode() end
                if c.close then c.close() end
            end
            return nil, (code and ("HTTP " .. code .. ": ") or "") .. tostring(b)
        elseif e == "timer" and a == deadline then
            os.cancelTimer(anim)
            return nil, "timed out after " .. HTTP_TIMEOUT .. " s"
        elseif e == "timer" and a == anim then
            anim = os.startTimer(0.1)
            tick()
        elseif e == "term_resize" then
            tick()
        end
    end
end

local function hintFor(err)
    err = tostring(err):lower()
    if err:find("404", 1, true) then
        return "This version was not found on the server. Pick another one."
    elseif err:find("not permitted", 1, true) or err:find("disabled", 1, true) then
        return "Allow this domain in computercraft-server.toml (http rules)."
    elseif err:find("timed out", 1, true) then
        return "The server did not answer in time. Try again."
    end
    return "Check the connection, then try again or pick another version."
end

-- ============================================================
--  Hlavní update logika (DJB2 kontrola, stahují se jen změny)
-- ============================================================
local function runUpdate()
    local S = {
        phase = 1, title = "Connecting", sub = BASE_URL .. MANIFEST_FILE, isPath = false,
        stats = "Waiting for the server", frac = 0, shown = 0, indet = true,
        done = 0, bad = 0, total = 0, cur = 0, bytes = 0, log = {}, logLines = {}, logScroll = 0, tStart = now(),
    }
    ACTIVE_LOG = S
    local function redraw() ease(S); drawUpdate(S) end
    redraw()

    -- 1) manifest
    local manifestJson, manifestErr = fetch(BASE_URL .. MANIFEST_FILE, redraw)
    if not manifestJson then
        return resultScreen({ kind = "err", title = "Connection failed",
            lines = { tostring(manifestErr), hintFor(manifestErr) },
            actions = { A_RETRY, A_BACK, A_QUIT } })
    end

    local okJson, manifest = pcall(textutils.unserializeJSON, manifestJson)
    if not okJson or type(manifest) ~= "table" then
        return resultScreen({ kind = "err", title = "Invalid manifest",
            lines = { "JSON parse error in " .. MANIFEST_FILE .. ".",
                      "The server sent a broken file. Try again later or pick another version." },
            actions = { A_RETRY, A_BACK, A_QUIT } })
    end

    -- Seznam souborů ke stažení = vše mimo blacklist
    local pending = {}
    for _, item in ipairs(manifest) do
        -- Blacklist chrání jen soubory, které už existují; chybějící se doinstalují
        local exists = fs.exists(item.path)
        local protected = exists and isBlacklisted(item.path)
        local unchanged = exists and item.djb2 and localDjb2(item.path) == item.djb2
        if protected then
            addLog(S, true, item.path, 'blacklisted; kept local file')
        elseif unchanged then
            addLog(S, true, item.path, 'unchanged; skipped')
        else
            pending[#pending + 1] = item
        end
    end
    local total = #pending

    if total == 0 then
        saveFile(MANIFEST_FILE, manifestJson)
        saveFile("/version/branch.txt", BRANCH)
        return resultScreen({ kind = "ok", title = "Already up to date",
            lines = { "No files to update." },
            countdown = 3, countdownText = "Closing in %ds", auto = "quit",
            actions = { { cap = "Enter", label = "Close", ret = "quit", chars = "q" }, A_BACK } })
    end

    -- 2) stahování (každý soubor jednou; selhané lze zopakovat)
    S.phase, S.title, S.titleShort, S.indet, S.total, S.t0 = 2, "Downloading files", "Downloading", false, total, now()
    local failedItems
    while true do
        failedItems = {}
        local failLog, firstErr = {}, nil
        S.bad = 0

        for _, item in ipairs(pending) do
            S.sub, S.isPath = item.path, true
            S.cur  = S.done + S.bad + 1
            S.frac = (S.done + S.bad) / total
            redraw()

            local content, dlErr = fetch(item.url, redraw)
            local errMsg
            if content then
                local ok, err = pcall(saveFile, item.path, content)
                if ok then
                    S.done  = S.done + 1
                    S.bytes = S.bytes + #content
                    addLog(S, true, item.path, fmtBytes(#content))
                else
                    errMsg = tostring(err)
                end
            else
                errMsg = tostring(dlErr)
            end

            if errMsg then
                S.bad = S.bad + 1
                failedItems[#failedItems + 1] = item
                failLog[#failLog + 1] = tostring(item.path) .. " | " .. tostring(item.url) .. " | " .. errMsg
                firstErr = firstErr or (tostring(item.path) .. " - " .. errMsg)
                addLog(S, false, item.path, errMsg)
            end
            S.frac = (S.done + S.bad) / total
            redraw()
        end

        S.cur = total
        settle(S, redraw)
        if #failedItems == 0 then break end

        -- Něco se nepovedlo: nehlásit úspěch, nepatchovat boot, nerebootovat
        pcall(saveFile, "/ota_error.log", table.concat(failLog, "\n") .. "\n")
        local act = resultScreen({ kind = "warn",
            title = string.format("Update incomplete (%d failed)", #failedItems),
            lines = { firstErr, "Details saved to /ota_error.log." },
            actions = { A_RETRY, A_BACK, A_QUIT } })
        if act ~= "retry" then return act end
        pending = failedItems
    end

    -- 3) manifest + záplata boot image (původní boot.img logika zachována)
    S.phase, S.title, S.titleShort, S.sub, S.isPath = 3, "Patching boot image", "Patching boot", "boot.img", false
    S.stats, S.indet = "Fetching the latest boot image", true
    saveFile(MANIFEST_FILE, manifestJson)
    redraw()
    wait(0.6, redraw)
    while true do
        local bootData, bootErr = fetch(BOOT_URL, redraw)
        if bootData then
            saveFile("/boot.img", bootData)
            break
        end
        local act = resultScreen({ kind = "err", title = "Boot patch failed",
            lines = { tostring(bootErr), hintFor(bootErr) },
            actions = { A_RETRY, A_BACK, A_QUIT } })
        if act ~= "retry" then return act end
    end

    -- 4) hotovo -> restart
    saveFile("/version/branch.txt", BRANCH)
    S.phase = 4
    local summary = string.format("%d file%s updated, %s in %s",
        S.done, S.done == 1 and "" or "s", fmtBytes(S.bytes), fmtTime(now() - S.tStart))
    return resultScreen({ kind = "ok", title = "Update complete",
        lines = { summary, "Restarting to finish the update." },
        countdown = 4, countdownText = "Restarting in %ds", auto = "reboot",
        actions = { { cap = "Enter", label = "Restart now", ret = "reboot" } } })
end

-- ============================================================
--  Boot
-- ============================================================
local function initTerminal()
    applyPalette()
    resetBuffer()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorBlink(false)
end

local function restoreTerminal()
    restorePalette()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    term.setCursorBlink(false)
end

local function main()
    if not http then
        resultScreen({ kind = "err", title = "HTTP is disabled",
            lines = { "Enable http in computercraft-server.toml, then run the updater again." },
            actions = { { cap = "Enter", label = "Quit", ret = "quit", chars = "q" } } })
        return
    end

    splash()
    while true do
        local branch = FORCED_BRANCH or selectBranch()
        if not branch then return end
        setBranch(branch)

        local act
        repeat act = runUpdate() until act ~= "retry"

        if act == "reboot" then
            fs.delete("/installer.lua")
            restoreTerminal()
            os.reboot()
            return
        end
        if act ~= "back" or FORCED_BRANCH then return end
    end
end

initTerminal()
local ok, err = pcall(main)
if not ok then
    local msg = tostring(err)
    if msg == "Terminated" then
        restoreTerminal()
        print("Update cancelled.")
    else
        local shown = pcall(resultScreen, { kind = "err", title = "Fatal error", lines = { msg },
            actions = { { cap = "Enter", label = "Quit", ret = "quit", chars = "q" } } })
        restoreTerminal()
        if not shown then printError(msg) end
    end
else
    restoreTerminal()
end
