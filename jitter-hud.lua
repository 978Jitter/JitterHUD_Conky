--[[
  JITTER HUD  //  live data layer
  Draws the live numbers, graphs and bars on top of ~/.config/conky/jitter-bg.png
  (the decorative art). Layout is in a layout space (see L.design), scaled to the window.

  Needs conky built with Lua + Cairo  ->  sudo apt install conky-all
]]

require 'cairo'
pcall(require, 'cairo_xlib')   -- newer conky splits xlib into its own module; older ones don't have it

-- ------------------------------------------------------------------ settings
local HOME     = os.getenv('HOME') or '/home/jitter'
local DIR      = HOME .. '/.config/conky/'
local BG_PNG   = DIR .. 'jitter-bg.png'
local SAMPLES  = 70               -- graph history length

-- user settings live in ~/.config/conky/jitter-hud.settings (never overwritten by the installer)
local CFG = {}
do
    local f = loadfile(DIR .. 'jitter-hud.settings')
    if f then
        local ok, t = pcall(f)
        if ok and type(t) == 'table' then CFG = t end
    end
end
local BG_ALPHA      = CFG.bg_alpha or 1.0
local SWEEP         = (CFG.scanline ~= false)
local WEATHER_LOC   = CFG.weather_location or ''
local WEATHER_UNITS = CFG.weather_units or 'u'      -- 'u' = F/mph, 'm' = C/km/h
local LABELS        = CFG.labels or {}
local USB_HIDE      = CFG.usb_hide or {}                -- e.g. { '1-1.1', 'Bluetooth' } to hide built-in devices
local FRAME_DT      = CFG.frame_seconds or 0.5      -- must equal update_interval in jitter.conf
local HIST_EVERY    = math.max(1, math.floor(1 / FRAME_DT + 0.5))   -- graphs advance once per second

-- ------------------------------------------------------------------ layout + colours (generated)
local L   = {design = 684, clock = {x = 660, y = 73, size = 60, sx = 0.78, align = 'r', col = 'RED', glow = true}, date = {x = 658, y = 97, size = 22, sx = 0.84, align = 'r', col = 'GRAYL'}, cpu_pct = {x = 66, y = 171, size = 18, sx = 0.82, col = 'CYANL'}, cpu_graph = {x = 26, y = 181, w = 166, h = 46}, ram_pct = {x = 64, y = 269, size = 18, sx = 0.82, col = 'WHITE'}, ram_size = {x = 190, y = 269, size = 15, sx = 0.66, align = 'r', col = 'GRAYL'}, ram_graph = {x = 26, y = 282, w = 166, h = 40}, root_pct = {x = 66, y = 388, size = 15, sx = 0.85, col = 'CYANL'}, root_size = {x = 24, y = 406, size = 15, sx = 0.74, col = 'GRAYL'}, root_bar = {x = 26, y = 418, w = 131, h = 7}, temp = {x = 58, y = 494, size = 26, sx = 0.78, col = 'RED', glow = true}, batt_txt = {x = 158, y = 521, size = 14, sx = 0.8}, batt_bar = {x = 26, y = 533, w = 131, h = 12}, host = {x = 82, y = 612, size = 15, sx = 0.76, col = 'RED'}, os = {x = 82, y = 632, size = 15, sx = 0.76, col = 'RED'}, uptime = {x = 82, y = 651, size = 15, sx = 0.76, col = 'RED'}, net_if = {x = 576, y = 197, size = 14, sx = 0.68, col = 'CYANL'}, net_ip = {x = 576, y = 218, size = 14, sx = 0.68, col = 'CYANL'}, net_wifi = {x = 576, y = 242, size = 14, sx = 0.68, col = 'CYANL'}, wifi_bars = {x = 622, y = 246, n = 8, bw = 3.6, step = 5.4, h0 = 3, dh = 2.4}, net_graph = {x = 506, y = 264, w = 158, h = 48}, rf_count = {x = 664, y = 396, size = 14, sx = 0.66, align = 'r', col = 'RED'}, rf_rows = {x1 = 524, x2 = 580, y = {418, 438, 458}, size = 14, sx = 0.72, col = 'GRAYL', maxlab = 12}, weather = {hx = 484, hy = 598, hx2 = 652, ix = 506, iy = 626, isize = 19, tx = 536, ty = 630, cy = 651, rx = 606, ry = {615, 626, 637}, hs = 17, ls = 14, ts = 28, cs = 12.5, rs = 10.5}, status = {x = 341, y = 531, size = 13, sx = 0.92, track = 2.2, maxw = 150}, glow = {period = 4.0, pts = {{340, 605, 42, 0.7, 0.8, 1.0, 0.0, 1.0}, {341.5, 341, 72, 1.0, 0.12, 0.08, 1.57, 0.55}}}, rf_head = {y = 396, size = 12, sx = 0.7}}
local HEX = {RED = 'ff2a2a', REDD = '6a0a0a', CYAN = '33d2f0', CYANL = 'a4e8f4', GRAYL = 'd8d2d2', WHITE = 'eef6f8', GREEN = '38ee50', AMBER = 'ffb020', DIM = '3a0808'}

local SCALE = 684 / (L.design or 684)             -- window width / layout width
local K = (L.design or 684) / 1254                -- line-width unit (the strokes below were tuned at 1254)
local function lw(v) return math.max(1, v * K) end

local function rgb(h)
    return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 }
end
local C = {}
for k, v in pairs(HEX) do C[k] = rgb(v) end

-- ------------------------------------------------------------------ font
local function have_font(name)
    local ok, p = pcall(io.popen, 'fc-list : family 2>/dev/null')
    if not ok or not p then return false end
    local s = p:read('*a') or ''
    p:close()
    return s:find(name, 1, true) ~= nil
end
local FONT = have_font('Fira Code') and 'Fira Code' or 'DejaVu Sans Mono'

-- ------------------------------------------------------------------ small helpers
local function ulen(s)
    if utf8 and utf8.len then return utf8.len(s) or #s end
    return #s
end

local function setc(cr, c, a)
    cairo_set_source_rgba(cr, c[1], c[2], c[3], a or 1)
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function trim(s)
    return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function num(s)
    return tonumber(tostring(s or ''):match('-?[%d%.]+')) or 0
end

-- "2.62GiB" -> "2.6G", "186GiB" -> "186G"
local function short(s)
    s = tostring(s or ''):gsub('%s', '')
    local n, u = s:match('^([%d%.]+)(%a)')
    if not n then return s end
    n = tonumber(n)
    if n >= 100 then return string.format('%d%s', math.floor(n + 0.5), u) end
    return string.format('%.1f%s', n, u)
end

local cache = {}
local function sh(key, interval, cmd)
    local now = os.time()
    local c = cache[key]
    if not c or now - c.t >= interval then
        local out = ''
        local ok, p = pcall(io.popen, cmd .. ' 2>/dev/null')
        if ok and p then
            out = p:read('*a') or ''
            p:close()
        end
        c = { t = now, v = out }
        cache[key] = c
    end
    return c.v
end

local function parse(expr)
    return conky_parse(expr) or ''
end

local function uptime_str()
    local f = io.open('/proc/uptime', 'r')
    if not f then return '--' end
    local line = f:read('*l') or ''
    f:close()
    local sec = math.floor(tonumber(line:match('^[%d%.]+')) or 0)
    local d = math.floor(sec / 86400)
    local h = math.floor((sec % 86400) / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    return string.format('%dd %02d:%02d:%02d', d, h, m, s)
end

-- ------------------------------------------------------------------ shell snippets
local NETCMD = [==[iface=$(ip route show default | awk 'NR==1{print $5; exit}'); addr=""; [ -n "$iface" ] && addr=$(ip -4 -o addr show "$iface" | awk 'NR==1{split($4,a,"/"); print a[1]}'); echo "${iface:-NONE}|${addr:-OFFLINE}"]==]

local BATCMD = CFG.battery_command or (HOME .. '/.local/bin/jitter-batt')   -- must print  percent  or  percent|status

local PORTCMD = HOME .. '/.local/bin/jitter-usb'

-- ------------------------------------------------------------------ drawing primitives
-- draws text; x is left edge (or right/centre edge with align), y is the baseline.
-- sx < 1 squeezes the glyphs horizontally for the condensed HUD look. Returns the right edge.
local function txt(cr, s, x, y, size, sx, col, align, bold, alpha)
    s = tostring(s or '')
    local w = ulen(s) * 0.6 * size * sx
    if align == 'r' then x = x - w elseif align == 'c' then x = x - w / 2 end
    cairo_save(cr)
    cairo_select_font_face(cr, FONT, 0, bold and 1 or 0)
    cairo_set_font_size(cr, size)
    cairo_translate(cr, x, y)
    cairo_scale(cr, sx, 1)
    cairo_move_to(cr, 0, 0)
    setc(cr, col, alpha or 1)
    cairo_show_text(cr, s)
    cairo_restore(cr)
    return x + w
end

-- same, with a soft red-ish halo behind it
local function glowtxt(cr, s, x, y, size, sx, col, align, bold)
    local r = (L.design or 684) * 0.00144
    local offs = { { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r }, { r, r }, { -r, -r }, { r, -r }, { -r, r } }
    for _, o in ipairs(offs) do
        txt(cr, s, x + o[1], y + o[2], size, sx, col, align, bold, 0.10)
    end
    return txt(cr, s, x, y, size, sx, col, align, bold, 1)
end

local function item(cr, key, s, col, bold)
    local d = L[key]
    local c = col or C[d.col or 'WHITE']
    if d.glow then
        return glowtxt(cr, s, d.x, d.y, d.size, d.sx, c, d.align, bold)
    end
    return txt(cr, s, d.x, d.y, d.size, d.sx, c, d.align, bold, 1)
end

local function graph(cr, g, hist, vmax, col)
    local x, y, w, h = g.x, g.y, g.w, g.h
    local n = #hist
    local dx = w / (n - 1)
    local function py(v)
        return y + h - clamp(v / vmax, 0, 1) * h
    end

    -- faint grid
    setc(cr, col, 0.14)
    cairo_set_line_width(cr, lw(1))
    for i = 1, 2 do
        local gy = y + h * i / 3
        cairo_move_to(cr, x, gy)
        cairo_line_to(cr, x + w, gy)
        cairo_stroke(cr)
    end

    -- filled area
    cairo_new_path(cr)
    cairo_move_to(cr, x, y + h)
    for i = 1, n do cairo_line_to(cr, x + (i - 1) * dx, py(hist[i])) end
    cairo_line_to(cr, x + w, y + h)
    cairo_close_path(cr)
    local pat = cairo_pattern_create_linear(0, y, 0, y + h)
    cairo_pattern_add_color_stop_rgba(pat, 0, col[1], col[2], col[3], 0.85)
    cairo_pattern_add_color_stop_rgba(pat, 1, col[1] * 0.4, col[2] * 0.4, col[3] * 0.4, 0.10)
    cairo_set_source(cr, pat)
    cairo_fill(cr)
    cairo_pattern_destroy(pat)

    -- glow pass + sharp line
    for pass = 1, 2 do
        cairo_new_path(cr)
        cairo_move_to(cr, x, py(hist[1]))
        for i = 2, n do cairo_line_to(cr, x + (i - 1) * dx, py(hist[i])) end
        if pass == 1 then
            setc(cr, col, 0.25)
            cairo_set_line_width(cr, lw(6))
        else
            setc(cr, col, 1)
            cairo_set_line_width(cr, lw(2))
        end
        cairo_set_line_join(cr, 1)   -- round
        cairo_stroke(cr)
    end
end

local function hbar(cr, b, frac, col)
    frac = clamp(frac, 0, 1)
    if frac <= 0 then return end
    local pat = cairo_pattern_create_linear(b.x, 0, b.x + b.w, 0)
    cairo_pattern_add_color_stop_rgba(pat, 0, col[1] * 0.65, col[2] * 0.65, col[3] * 0.65, 1)
    cairo_pattern_add_color_stop_rgba(pat, 1, col[1], col[2], col[3], 1)
    cairo_rectangle(cr, b.x, b.y, b.w * frac, b.h)
    cairo_set_source(cr, pat)
    cairo_fill(cr)
    cairo_pattern_destroy(pat)
end

local function wifibars(cr, wb, lit)
    for i = 0, wb.n - 1 do
        local h = wb.h0 + i * wb.dh
        local x = wb.x + i * wb.step
        if i < lit then setc(cr, C.RED, 1) else setc(cr, C.DIM, 1) end
        cairo_rectangle(cr, x, wb.y - h, wb.bw, h)
        cairo_fill(cr)
    end
end

local function battery(cr, b, frac, col, bright)
    setc(cr, col, 1)
    cairo_set_line_width(cr, lw(3))
    cairo_rectangle(cr, b.x, b.y, b.w, b.h)
    cairo_stroke(cr)
    cairo_rectangle(cr, b.x + b.w * 0.3, b.y - 6, b.w * 0.4, 6)
    cairo_fill(cr)
    local pad = 5
    local fh = (b.h - 2 * pad) * clamp(frac, 0, 1)
    cairo_rectangle(cr, b.x + pad, b.y + b.h - pad - fh, b.w - 2 * pad, fh)
    setc(cr, col, bright and 1 or 0.9)
    cairo_fill(cr)
end

-- ------------------------------------------------------------------ weather (fetched in the background via wttr.in)
local WEATHER_FILE = HOME .. '/.cache/jitter-weather.txt'
local weather = { last_try = 0, last_read = 0, data = nil }

local function urlenc(s)
    return (tostring(s):gsub('[^%w%-_%.~,]', function(c) return string.format('%%%02X', string.byte(c)) end))
end

local function weather_refresh()
    local now = os.time()
    local wait = weather.data and 900 or 90          -- 15 min when we have data, retry every 90 s when not
    if now - weather.last_try < wait then return end
    weather.last_try = now
    local url = 'https://wttr.in/' .. urlenc(WEATHER_LOC) .. '?format=%C%7C%t%7C%f%7C%h%7C%w%7C%l&' .. WEATHER_UNITS
    local tmp = WEATHER_FILE .. '.tmp'
    -- runs detached (&) so a slow or dead network never freezes the HUD
    os.execute('mkdir -p "' .. HOME .. '/.cache"; (curl -fsS -m 12 "' .. url .. '" -o "' .. tmp ..
               '" && [ -s "' .. tmp .. '" ] && mv "' .. tmp .. '" "' .. WEATHER_FILE .. '") >/dev/null 2>&1 &')
end

local function weather_read()
    local now = os.time()
    if now - weather.last_read < 20 then return end
    weather.last_read = now
    local f = io.open(WEATHER_FILE, 'r')
    if not f then return end
    local line = f:read('*l') or ''
    f:close()
    local p = {}
    for part in (line .. '|'):gmatch('([^|]*)|') do p[#p + 1] = part end
    if #p < 6 or not p[2]:match('%d') then return end          -- not a valid answer (error page, etc.)
    local function ascii(x) return (tostring(x):gsub('[\128-\255]', ''):gsub('^%s+', ''):gsub('%s+$', '')) end
    local feels = p[3]:match('([%-%+]?%d+)')
    weather.data = {
        cond  = ascii(p[1]):upper():sub(1, 16),
        temp  = (p[2]:gsub('^%s*%+', ''):gsub('%s+$', '')),
        feels = feels and ((feels:gsub('^%+', '')) .. '\194\176') or '--',
        hum   = ascii(p[4]),
        wind  = ascii(p[5]),
        loc   = (ascii(p[6]):match('^([^,]+)') or ascii(p[6])):upper():sub(1, 14),
    }
end

local function icon_kind(cond)
    local c = cond:lower()
    if c:find('thunder') then return 'storm' end
    if c:find('snow') or c:find('sleet') or c:find('blizzard') or c:find('ice') or c:find('freezing') then return 'snow' end
    if c:find('rain') or c:find('drizzle') or c:find('shower') then return 'rain' end
    if c:find('fog') or c:find('mist') or c:find('haze') or c:find('smoke') then return 'fog' end
    if c:find('partly') or c:find('patchy') then return 'partly' end
    if c:find('cloud') or c:find('overcast') then return 'cloud' end
    local h = tonumber(os.date('%H')) or 12
    if h < 6 or h >= 19 then return 'moon' end
    return 'sun'
end

local function ic_cloud(cr, cx, cy, s, col, solid)
    cairo_new_path(cr)
    cairo_arc(cr, cx - 0.55 * s, cy + 0.15 * s, 0.40 * s, math.pi * 0.5, math.pi * 1.5)
    cairo_arc(cr, cx - 0.10 * s, cy - 0.25 * s, 0.52 * s, math.pi * 1.0, math.pi * 1.85)
    cairo_arc(cr, cx + 0.55 * s, cy + 0.10 * s, 0.45 * s, math.pi * 1.5, math.pi * 2.5)
    cairo_close_path(cr)
    if solid then
        cairo_set_source_rgba(cr, 0.02, 0.02, 0.02, 1)     -- hides whatever is behind (the sun)
        cairo_fill_preserve(cr)
    end
    setc(cr, col, 1)
    cairo_set_line_width(cr, lw(3.2))
    cairo_set_line_join(cr, 1)
    cairo_stroke(cr)
end

local function ic_sun(cr, cx, cy, s, col)
    setc(cr, col, 1)
    cairo_set_line_width(cr, lw(3.2))
    cairo_new_path(cr)
    cairo_arc(cr, cx, cy, 0.42 * s, 0, 2 * math.pi)
    cairo_stroke(cr)
    for i = 0, 7 do
        local a = i * math.pi / 4
        cairo_move_to(cr, cx + math.cos(a) * 0.66 * s, cy + math.sin(a) * 0.66 * s)
        cairo_line_to(cr, cx + math.cos(a) * 0.92 * s, cy + math.sin(a) * 0.92 * s)
    end
    cairo_stroke(cr)
end

local function draw_icon(cr, kind, cx, cy, s)
    if kind == 'sun' then
        ic_sun(cr, cx, cy, s, C.AMBER)
    elseif kind == 'moon' then
        setc(cr, C.CYANL, 1)
        cairo_new_path(cr)
        cairo_arc(cr, cx, cy, 0.62 * s, 0, 2 * math.pi)
        cairo_fill(cr)
        cairo_set_source_rgba(cr, 0.02, 0.02, 0.02, 1)
        cairo_new_path(cr)
        cairo_arc(cr, cx + 0.32 * s, cy - 0.22 * s, 0.55 * s, 0, 2 * math.pi)
        cairo_fill(cr)
    elseif kind == 'partly' then
        ic_sun(cr, cx - 0.40 * s, cy - 0.34 * s, s * 0.62, C.AMBER)
        ic_cloud(cr, cx + 0.12 * s, cy + 0.14 * s, s * 0.80, C.CYAN, true)
    elseif kind == 'cloud' then
        ic_cloud(cr, cx, cy, s * 0.95, C.CYAN, false)
    elseif kind == 'rain' then
        ic_cloud(cr, cx, cy - 0.22 * s, s * 0.85, C.CYAN, false)
        setc(cr, C.CYAN, 1)
        cairo_set_line_width(cr, lw(3.2))
        for i = -1, 1 do
            local x = cx + i * 0.46 * s
            cairo_move_to(cr, x + 0.08 * s, cy + 0.50 * s)
            cairo_line_to(cr, x - 0.10 * s, cy + 0.86 * s)
        end
        cairo_stroke(cr)
    elseif kind == 'snow' then
        ic_cloud(cr, cx, cy - 0.22 * s, s * 0.85, C.CYAN, false)
        setc(cr, C.CYANL, 1)
        for i = -1, 1 do
            cairo_new_path(cr)
            cairo_arc(cr, cx + i * 0.46 * s, cy + 0.66 * s + ((i % 2 == 0) and 0 or 0.12 * s), 0.07 * s, 0, 2 * math.pi)
            cairo_fill(cr)
        end
    elseif kind == 'storm' then
        ic_cloud(cr, cx, cy - 0.22 * s, s * 0.85, C.CYAN, false)
        setc(cr, C.AMBER, 1)
        cairo_new_path(cr)
        cairo_move_to(cr, cx + 0.10 * s, cy + 0.38 * s)
        cairo_line_to(cr, cx - 0.22 * s, cy + 0.72 * s)
        cairo_line_to(cr, cx - 0.02 * s, cy + 0.72 * s)
        cairo_line_to(cr, cx - 0.16 * s, cy + 1.02 * s)
        cairo_line_to(cr, cx + 0.28 * s, cy + 0.62 * s)
        cairo_line_to(cr, cx + 0.06 * s, cy + 0.62 * s)
        cairo_close_path(cr)
        cairo_fill(cr)
    else -- fog
        setc(cr, C.CYAN, 1)
        cairo_set_line_width(cr, lw(3.2))
        for i = 0, 3 do
            local y = cy - 0.45 * s + i * 0.30 * s
            local off = (i % 2) * 0.18 * s
            cairo_move_to(cr, cx - 0.85 * s + off, y)
            cairo_line_to(cr, cx + 0.85 * s - (0.18 * s - off), y)
        end
        cairo_stroke(cr)
    end
end

local function draw_weather(cr)
    local W = L.weather
    txt(cr, 'WEATHER', W.hx, W.hy, W.hs, 0.72, C.RED, nil, true, 1)
    setc(cr, C.RED, 0.55)
    cairo_set_line_width(cr, lw(2))
    cairo_move_to(cr, W.hx, W.hy + W.hs * 0.27)
    cairo_line_to(cr, W.hx2, W.hy + W.hs * 0.27)
    cairo_stroke(cr)

    local w = weather.data
    if not w then
        txt(cr, 'NO DATA', (W.hx + W.hx2) / 2, W.ty, W.ts * 0.75, 0.80, C.DIM, 'c', true, 1)
        return
    end
    txt(cr, w.loc, W.hx2, W.hy, W.ls, 0.70, C.CYANL, 'r', false, 1)
    draw_icon(cr, icon_kind(w.cond), W.ix, W.iy, W.isize)
    glowtxt(cr, w.temp, W.tx, W.ty, W.ts, 0.74, C.RED, nil, true)
    txt(cr, w.cond, W.tx, W.cy, W.cs, 0.68, C.GRAYL, nil, false, 1)
    txt(cr, 'FEELS ' .. w.feels, W.rx, W.ry[1], W.rs, 0.66, C.GRAYL, nil, false, 1)
    txt(cr, 'HUM ' .. w.hum, W.rx, W.ry[2], W.rs, 0.66, C.GRAYL, nil, false, 1)
    txt(cr, 'WIND ' .. w.wind, W.rx, W.ry[3], W.rs, 0.66, C.GRAYL, nil, false, 1)
end

-- ------------------------------------------------------------------ status line + eyes
-- level 0 = nominal, 1 = elevated, 2 = critical
local function compute_status(cpu, memp, temp_c, bnum, charging)
    local lvl, why = 0, ''
    local function consider(level, label)
        if level > lvl then lvl, why = level, label end
    end
    if cpu >= 90 then consider(2, 'CPU ' .. math.floor(cpu + 0.5) .. '%')
    elseif cpu >= 70 then consider(1, 'CPU ' .. math.floor(cpu + 0.5) .. '%') end
    if temp_c then
        if temp_c >= 80 then consider(2, 'TEMP ' .. math.floor(temp_c + 0.5) .. 'C')
        elseif temp_c >= 70 then consider(1, 'TEMP ' .. math.floor(temp_c + 0.5) .. 'C') end
    end
    if memp >= 95 then consider(2, 'RAM ' .. math.floor(memp + 0.5) .. '%')
    elseif memp >= 85 then consider(1, 'RAM ' .. math.floor(memp + 0.5) .. '%') end
    if bnum and not charging then
        if bnum < 15 then consider(2, 'BATT ' .. math.floor(bnum + 0.5) .. '%')
        elseif bnum < 30 then consider(1, 'BATT ' .. math.floor(bnum + 0.5) .. '%') end
    end
    return lvl, why
end

local function spaced(cr, s, cx, y, size, sx, track, col, alpha, maxw)
    local adv = 0.6 * size * sx + track
    local total = #s * adv - track
    if maxw and total > maxw then               -- long messages shrink to fit the gap
        local f = maxw / total
        sx, track = sx * f, track * f
        adv = 0.6 * size * sx + track
    end
    local x = cx - (#s * adv - track) / 2
    for i = 1, #s do
        txt(cr, s:sub(i, i), x, y, size, sx, col, nil, true, alpha)
        x = x + adv
    end
end

local function draw_status(cr, lvl, why, t)
    local S = L.status
    if lvl == 0 then
        spaced(cr, 'SYSTEM NOMINAL', S.x, S.y, S.size, S.sx, S.track, C.RED, 0.85, S.maxw)
    elseif lvl == 1 then
        spaced(cr, 'ELEVATED // ' .. why, S.x, S.y, S.size, S.sx, S.track, C.AMBER, 1, S.maxw)
    else
        local k = 0.5 + 0.5 * math.sin(t * 2 * math.pi / 1.2)
        local a = 0.55 + 0.45 * k
        spaced(cr, 'CRITICAL // ' .. why, S.x + 1.5 * K, S.y, S.size, S.sx, S.track, C.RED, 0.18 * a, S.maxw)
        spaced(cr, 'CRITICAL // ' .. why, S.x - 1.5 * K, S.y, S.size, S.sx, S.track, C.RED, 0.18 * a, S.maxw)
        spaced(cr, 'CRITICAL // ' .. why, S.x, S.y, S.size, S.sx, S.track, C.RED, a, S.maxw)
    end
end

local function draw_glows(cr, lvl, t)
    local E = L.glow
    local period = (lvl == 2) and 1.2 or ((lvl == 1) and 2.6 or E.period)
    cairo_set_operator(cr, 12)                     -- ADD: light, not paint
    for _, e in ipairs(E.pts) do                   -- e = { x, y, radius, r, g, b, phase, strength }
        local k = 0.5 + 0.5 * math.sin(t * 2 * math.pi / period + (e[7] or 0))
        local s = e[8] or 1
        local pat = cairo_pattern_create_radial(e[1], e[2], 0, e[1], e[2], e[3])
        cairo_pattern_add_color_stop_rgba(pat, 0, e[4], e[5], e[6], (0.06 + 0.26 * k) * s)
        cairo_pattern_add_color_stop_rgba(pat, 0.4, e[4], e[5], e[6], (0.03 + 0.12 * k) * s)
        cairo_pattern_add_color_stop_rgba(pat, 1, e[4], e[5], e[6], 0)
        cairo_set_source(cr, pat)
        cairo_new_path(cr)
        cairo_arc(cr, e[1], e[2], e[3], 0, 2 * math.pi)
        cairo_fill(cr)
        cairo_pattern_destroy(pat)
    end
    cairo_set_operator(cr, 2)                      -- back to OVER
end

local function usb_hidden(s)
    s = tostring(s):lower()
    for _, h in ipairs(USB_HIDE) do
        if s:find(tostring(h):lower(), 1, true) then return true end
    end
    return false
end

local warned = {}
local function safe(name, cr, fn, ...)
    cairo_save(cr)
    local ok, err = pcall(fn, cr, ...)
    cairo_restore(cr)
    cairo_new_path(cr)
    if not ok and not warned[name] then
        warned[name] = true
        io.stderr:write('jitter-hud: ' .. name .. ' failed: ' .. tostring(err) .. '\n')
    end
end

-- ------------------------------------------------------------------ state
local function zeros(n)
    local t = {}
    for i = 1, n do t[i] = 0 end
    return t
end
local hist_cpu = zeros(SAMPLES)
local hist_ram = zeros(SAMPLES)
local hist_net = zeros(SAMPLES)
local net_max  = 50          -- KiB/s, grows with traffic
local function push(h, v)
    table.remove(h, 1)
    h[#h + 1] = v
end

local bg_surf, bg_failed = nil, false
local bg_scale = 1
local frame = 0

-- ------------------------------------------------------------------ main
function conky_main()
    if conky_window == nil then return end

    local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
                                         conky_window.visual, conky_window.width, conky_window.height)
    local cr = cairo_create(cs)

    -- ---- gather data
    local cpu   = num(parse('${cpu}'))
    local memp  = num(parse('${memperc}'))
    local memu  = short(parse('${mem}'))
    local memm  = short(parse('${memmax}'))
    local rootp = num(parse('${fs_used_perc /}'))
    local rootu = short(parse('${fs_used /}'))
    local roots = short(parse('${fs_size /}'))

    local netraw = trim(sh('net', 15, NETCMD))
    local iface, ip = netraw:match('^([^|]*)|(.*)$')
    iface = iface or 'NONE'
    ip = ip or 'OFFLINE'

    local down = 0
    if iface ~= 'NONE' and iface ~= '' then
        down = num(parse('${downspeedf ' .. iface .. '}'))
    end
    frame = frame + 1
    local t = frame * FRAME_DT                    -- seconds since the HUD started
    if frame % HIST_EVERY == 0 then               -- graphs advance once per second
        if down > net_max then net_max = down end
        net_max = math.max(50, net_max * 0.99)
        push(hist_cpu, cpu)
        push(hist_ram, memp)
        push(hist_net, down)
    end

    weather_refresh()
    weather_read()

    local wifi = trim(sh('wifi', 10, HOME .. '/.local/bin/jitter-wifi'))
    if wifi == '' then wifi = 'N/A' end
    local lit = 0
    local dbm = wifi:match('(-%d+)')
    local wpct = wifi:match('(%d+)%%')
    if dbm then
        lit = clamp(math.floor((tonumber(dbm) + 95) / 6.25 + 0.5), 0, 8)
    elseif wpct then
        lit = clamp(math.floor(tonumber(wpct) / 100 * 8 + 0.5), 0, 8)
    end

    local temp = trim(sh('temp', 10, HOME .. '/.local/bin/jitter-temp'))
    if temp == '' then temp = 'N/A' end
    if temp:match('^[%d%.]+$') then temp = temp .. '\194\176C' end   -- add the degree sign

    local batraw = trim(sh('bat', 30, BATCMD))
    local bcap, bstat = batraw:match('^([^|]*)|(.*)$')
    if not bcap then bcap, bstat = (batraw:match('(%d+)') or 'N/A'), 'Unknown' end
    local bnum = tonumber(bcap)

    local ports = {}
    for line in sh('ports', 10, PORTCMD):gmatch('[^\n]+') do
        local name, label = line:match('^([^|]*)|?(.*)$')
        if name and name ~= '' and not usb_hidden(name) and not usb_hidden(label or '') then
            label = LABELS[name] or label or ''
            ports[#ports + 1] = { name = name, label = label:upper():sub(1, L.rf_rows.maxlab or 12) }
        end
    end

    -- ---- overall status (drives the centre line and the eyes)
    local temp_c = nil
    if temp:match('%d') then
        temp_c = num(temp)
        if temp:find('F') then temp_c = (temp_c - 32) * 5 / 9 end
    end
    local charging = (bstat == 'Charging' or bstat == 'Full')
    local lvl, why = compute_status(cpu, memp, temp_c, bnum, charging)

    -- ---- art layer (unscaled, 684x684)
    if not bg_surf and not bg_failed then
        local ok, s = pcall(cairo_image_surface_create_from_png, BG_PNG)
        if ok and s ~= nil then
            local ok2, st = pcall(cairo_surface_status, s)
            if (not ok2) or st == 0 then
                bg_surf = s
                local okw, w = pcall(cairo_image_surface_get_width, s)
                if okw and type(w) == 'number' and w > 0 then bg_scale = 684 / w end
            else
                bg_failed = true
            end
        else
            bg_failed = true
        end
    end
    if bg_surf then
        cairo_save(cr)
        cairo_scale(cr, bg_scale, bg_scale)
        cairo_set_source_surface(cr, bg_surf, 0, 0)
        cairo_paint_with_alpha(cr, BG_ALPHA)
        cairo_restore(cr)
    end

    -- ---- everything below is in design space
    cairo_scale(cr, SCALE, SCALE)

    safe('glow', cr, draw_glows, lvl, t)

    -- clock + date (dark plate so the digits stay readable over the circuit art)
    local P = L.clock_plate
    if P then
        cairo_rectangle(cr, P.x, P.y, P.w, P.h)
        cairo_set_source_rgba(cr, 0, 0, 0, 0.62)
        cairo_fill(cr)
    end
    item(cr, 'clock', os.date('%H:%M:%S'))
    item(cr, 'date', os.date('%a // %b %d, %Y'))

    -- cpu
    local cpu_col = (cpu >= 85) and C.RED or C.CYANL
    item(cr, 'cpu_pct', string.format('%d%%', math.floor(cpu + 0.5)), cpu_col, true)
    graph(cr, L.cpu_graph, hist_cpu, 100, C.RED)

    -- ram
    item(cr, 'ram_pct', string.format('%d%%', math.floor(memp + 0.5)), nil, true)
    item(cr, 'ram_size', memu .. ' / ' .. memm)
    graph(cr, L.ram_graph, hist_ram, 100, C.RED)

    -- storage
    item(cr, 'root_pct', string.format('%d%% USED', math.floor(rootp + 0.5)))
    local d = L.root_size
    local ex = txt(cr, rootu, d.x, d.y, d.size, d.sx, C[d.col], nil, false, 1)
    txt(cr, ' / ' .. roots, ex, d.y, d.size, d.sx, C.CYANL, nil, false, 1)
    hbar(cr, L.root_bar, rootp / 100, C.RED)

    -- temperature
    item(cr, 'temp', temp, nil, true)

    -- battery: percentage + a live bar
    local bcol = C.GREEN
    local btxt = bcap
    if bnum then
        btxt = string.format('%d%%', math.floor(bnum + 0.5))
        if charging and bstat == 'Charging' then btxt = 'CHG ' .. btxt end
        if bnum < 15 then bcol = C.RED elseif bnum < 30 then bcol = C.AMBER end
    else
        bcol = C.DIM
    end
    local bt = L.batt_txt
    if not bnum then btxt = 'NOT FOUND'; bcol = C.GRAYL end
    txt(cr, btxt, bt.x, bt.y, bt.size, bt.sx, bcol, 'r', true, 1)
    hbar(cr, L.batt_bar, (bnum or 0) / 100, bcol)

    -- system
    item(cr, 'host', parse('${nodename}'))
    item(cr, 'os', parse('${machine}') .. ' / KALI')
    item(cr, 'uptime', uptime_str())

    -- network
    item(cr, 'net_if', iface)
    item(cr, 'net_ip', ip)
    item(cr, 'net_wifi', wifi)
    wifibars(cr, L.wifi_bars, lit)
    graph(cr, L.net_graph, hist_net, net_max, C.RED)

    -- rf / usb  (never more rows than the panel has room for)
    local rc = #ports
    item(cr, 'rf_count', rc .. ' DETECTED', (rc > 0) and C.RED or C.DIM)
    local rr = L.rf_rows
    local rh = L.rf_head
    txt(cr, 'CONNECTED', rr.x1, rh.y, rh.size, rh.sx, C.CYANL, nil, false, 0.85)
    local slots = #rr.y
    local shown = rc
    if rc > slots then shown = slots - 1 end
    for i = 1, shown do
        txt(cr, ports[i].name, rr.x1, rr.y[i], rr.size, rr.sx, C[rr.col], nil, false, 1)
        txt(cr, ports[i].label, rr.x2, rr.y[i], rr.size, rr.sx, C[rr.col], nil, false, 1)
    end
    if rc > slots then
        txt(cr, '+' .. (rc - shown) .. ' MORE', rr.x1, rr.y[slots], rr.size, rr.sx, C.RED, nil, false, 1)
    end

    -- weather panel + centre status line
    safe('weather', cr, draw_weather)
    safe('status', cr, draw_status, lvl, why, t)

    -- drifting scanline
    if SWEEP then
        local D = L.design or 684
        local sy = ((t % 8) / 8) * D
        local bh = D * 0.013
        local pat = cairo_pattern_create_linear(0, sy - bh, 0, sy + bh)
        cairo_pattern_add_color_stop_rgba(pat, 0, 1, 0.1, 0.1, 0)
        cairo_pattern_add_color_stop_rgba(pat, 0.5, 1, 0.1, 0.1, 0.10)
        cairo_pattern_add_color_stop_rgba(pat, 1, 1, 0.1, 0.1, 0)
        cairo_rectangle(cr, 0, sy - bh, D, 2 * bh)
        cairo_set_source(cr, pat)
        cairo_fill(cr)
        cairo_pattern_destroy(pat)
    end

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
