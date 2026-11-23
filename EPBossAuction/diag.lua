local auction = EPBossAuction

-- ============================================================
-- diag.lua — диагностика аддона
-- ============================================================
-- Зачем: чтобы по одному отчёту от игрока было видно, где что сломалось,
-- без переспрашиваний. Всё, что здесь есть, ТОЛЬКО наблюдает за аддоном и
-- не меняет его поведение (кроме оборачивания в xpcall — ошибка в
-- таймере/обработчике сообщения теперь записывается, а не теряется).
--
-- Что внутри:
--   1) Журнал (кольцевой буфер) — в него пишет auction:Debug() ВСЕГДА, даже
--      когда auction.debug = false (в чат при этом не выводится).
--   2) Перехват ошибок Lua: xpcall вокруг таймеров и входящих сообщений +
--      обёртка глобального обработчика ошибок для остального (события,
--      OnUpdate, OnClick). Ошибки дедуплицируются, у каждой есть стек.
--   3) Трассировка сети: все исходящие (хук SendAddonMessage) и входящие
--      (обёртка HandleMessage) сообщения аддона, счётчики по командам,
--      пик частоты за 10 сек, превышения лимита 255, неизвестные команды,
--      время работы обработчиков.
--   4) Проверки (auction.diag.RunChecks): API клиента, роль ЛМ, целостность
--      ставок/явки/посещаемости/резерва/журнала выдач, EPGP-мост, таймеры.
--   5) Опрос рейда (DPING/DPONG): у кого какая версия аддона, кого он
--      считает ЛМ, совпадает ли контрольная сумма ставок с моей.
--   6) Окно «Диагностика» (вкладки: Сводка / Проверки / Лог / Сеть /
--      Ошибки / Рейд / Отчёт), команда /epba diag, сохранение ошибок и
--      хвоста журнала в EPBossAuctionSavedDiag.
--
-- Загружается ПОСЛЕ comm.lua, core.lua и contacts.lua (переопределяет
-- Debug/ScheduleTimer/HandleMessage/GetDiagnosticsString).
-- ============================================================

local diag = {}
auction.diag = diag

diag.LOG_MAX = 500
diag.NET_MAX = 250
diag.ERR_MAX = 40
local SAVED_LOG_TAIL = 150
local SAVED_ERR_MAX = 30
local SAVED_SESSIONS = 6
local MSG_LIMIT = 255                -- лимит SendAddonMessage в 3.x: префикс + \t + текст

local sessionStart = GetTime()
local sessionStartUnix = time()
local prof = (type(debugprofilestop) == "function") and debugprofilestop
    or function() return GetTime() * 1000 end

-- ======================
-- Утилиты
-- ======================
local function NewRing(max) return { max = max, n = 0, items = {} } end
local function RingPush(r, v)
    r.n = r.n + 1
    r.items[((r.n - 1) % r.max) + 1] = v
end
local function RingList(r, last)             -- от старых к новым, последние last
    local total = math.min(r.n, r.max)
    local count = last and math.min(last, total) or total
    local out = {}
    for i = r.n - count + 1, r.n do
        out[#out + 1] = r.items[((i - 1) % r.max) + 1]
    end
    return out
end
local function RingClear(r) r.n = 0; r.items = {} end

local function SortedKeys(t, cmp)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, cmp or function(a, b) return tostring(a) < tostring(b) end)
    return keys
end
local function NumCmp(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end

local function CountNodes(t, seen)
    if type(t) ~= "table" then return 0 end
    seen = seen or {}
    if seen[t] then return 0 end
    seen[t] = true
    local c = 0
    for _, v in pairs(t) do
        c = c + 1
        if type(v) == "table" then c = c + CountNodes(v, seen) end
    end
    return c
end

local function Clock(t) return date("%H:%M:%S", t or time()) end
local function Dur(sec)
    sec = math.floor(sec or 0)
    return string.format("%02d:%02d:%02d", math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60)
end
local function YesNo(v) return v and "да" or "нет" end
local function Trunc(s, n)
    s = tostring(s or "")
    if #s > n then return s:sub(1, n).."…" end
    return s
end
local function Safe(fn, ...)                  -- pcall, но возвращает только значения (или nil, err)
    local r = { pcall(fn, ...) }
    if r[1] then return unpack(r, 2) end
    return nil, r[2]
end

local function BossHasItem(boss, itemID)
    local list = auction.bosses[boss]
    if not list or not itemID then return false end
    for _, id in ipairs(list) do if id == itemID then return true end end
    return false
end

local function Hash(h, s)
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967291 end
    return h
end

-- ======================
-- 1. Журнал
-- ======================
diag.log = NewRing(diag.LOG_MAX)

function diag.Log(cat, msg)
    RingPush(diag.log, { GetTime(), time(), cat or "dbg", tostring(msg) })
end
function auction:DiagLog(cat, msg) diag.Log(cat, msg) end

-- Debug пишет в журнал всегда; в чат — только при auction.debug (как раньше).
function auction:Debug(msg, ...)
    msg = tostring(msg)
    if select("#", ...) > 0 then
        local ok, s = pcall(string.format, msg, ...)
        if ok then msg = s end
    end
    diag.Log("dbg", msg)
    if self.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff888888[EPBA DEBUG]|r "..msg)
    end
end

-- ======================
-- 2. Ошибки
-- ======================
diag.errors = {}
diag.errorTotal = 0
diag.currentCmd = nil

function diag.RecordError(msg, stack, src)
    msg = tostring(msg)
    diag.errorTotal = diag.errorTotal + 1
    for _, e in ipairs(diag.errors) do
        if e.msg == msg then
            e.count = e.count + 1
            e.last = time()
            return
        end
    end
    if #diag.errors >= diag.ERR_MAX then table.remove(diag.errors, 1) end
    table.insert(diag.errors, {
        msg = msg, stack = stack, src = src, count = 1,
        first = time(), last = time(), ver = auction.version,
    })
    diag.Log("err", (src and (src..": ") or "")..msg)
end

local function MakeHandler(srcFn)
    return function(e)
        local ok, stack = pcall(debugstack, 3, 8, 0)
        local src = type(srcFn) == "function" and srcFn() or srcFn
        diag.RecordError(e, ok and stack or nil, src)
        return e
    end
end

-- Глобальный обработчик: ловит ошибки событий/OnUpdate/OnClick, если в тексте
-- есть "EPBossAuction" (путь к файлу). Ставим один раз после входа в игру,
-- чтобы встать ПОВЕРХ BugGrabber/Swatter и передавать ошибку дальше им.
local downstream
local function ErrWrapper(msg)
    local s = tostring(msg)
    if s:find("EPBossAuction", 1, true) then
        local ok, stack = pcall(debugstack, 2, 8, 0)
        diag.RecordError(s, ok and stack or nil, "lua")
    end
    if downstream then return downstream(msg) end
end
local function InstallErrorHook()
    if type(geterrorhandler) ~= "function" or type(seterrorhandler) ~= "function" then return false end
    local cur = geterrorhandler()
    if cur == ErrWrapper then diag.hookActive = true; return true end
    downstream = cur
    seterrorhandler(ErrWrapper)
    diag.hookActive = (geterrorhandler() == ErrWrapper)
    return diag.hookActive
end

-- Таймеры: оборачиваем callback в xpcall (core.lua ловил pcall-ом и писал только в чат при debug).
diag.timerStats = { scheduled = 0, fired = 0 }
local origSchedule = auction.ScheduleTimer
local timerHandler = MakeHandler("timer")
function auction:ScheduleTimer(callback, delay)
    diag.timerStats.scheduled = diag.timerStats.scheduled + 1
    local function wrapped()
        diag.timerStats.fired = diag.timerStats.fired + 1
        xpcall(callback, timerHandler)
    end
    return origSchedule(self, wrapped, delay)
end

-- ======================
-- 3. Сеть
-- ======================
diag.net = { inN = 0, inB = 0, outN = 0, outB = 0, oversize = 0, unknown = 0,
    handlerErrors = 0, longest = 0, peak10 = 0, peak10At = nil, cmds = {}, outTimes = {} }
diag.netLog = NewRing(diag.NET_MAX)

local function CmdOf(msg) return (msg and tostring(msg):match("^([%w_]+)")) or "?" end
local function CmdStat(cmd)
    local s = diag.net.cmds[cmd]
    if not s then
        s = { inN = 0, inB = 0, outN = 0, outB = 0, maxMs = 0, totMs = 0, errs = 0, oversize = 0, unknown = 0 }
        diag.net.cmds[cmd] = s
    end
    return s
end

local function OnSend(prefix, msg, chan, target)
    if prefix ~= auction.prefix then return end
    msg = tostring(msg or "")
    local n, len = diag.net, #msg
    n.outN = n.outN + 1
    n.outB = n.outB + len
    local cmd = CmdOf(msg)
    local s = CmdStat(cmd)
    s.outN = s.outN + 1
    s.outB = s.outB + len
    if len + #prefix + 1 > MSG_LIMIT then
        n.oversize = n.oversize + 1
        s.oversize = s.oversize + 1
        diag.Log("net", string.format("ЛИМИТ %d превышен: %s, %d байт, канал %s", MSG_LIMIT, cmd, len + #prefix + 1, tostring(chan)))
    end
    if len > n.longest then n.longest = len end
    local now = GetTime()
    local ot = n.outTimes
    ot[#ot + 1] = now
    while ot[1] and now - ot[1] > 10 do table.remove(ot, 1) end
    if #ot > n.peak10 then n.peak10 = #ot; n.peak10At = time() end
    RingPush(diag.netLog, { now, time(), "out", cmd, len, tostring(chan), target and tostring(target) or "", Trunc(msg, 120) })
end
if type(hooksecurefunc) == "function" and type(SendAddonMessage) == "function" then
    hooksecurefunc("SendAddonMessage", function(...) pcall(OnSend, ...) end)
end

local origHandle = auction.HandleMessage
local msgHandler = MakeHandler(function() return "msg:"..tostring(diag.currentCmd) end)
function auction:HandleMessage(msg, sender)
    local n = diag.net
    local len = msg and #tostring(msg) or 0
    local cmd = CmdOf(msg)
    local s = CmdStat(cmd)
    n.inN = n.inN + 1
    n.inB = n.inB + len
    s.inN = s.inN + 1
    s.inB = s.inB + len
    local known = (cmd == "?") or type(self["Handle_"..cmd]) == "function"
    if not known then
        n.unknown = n.unknown + 1
        s.unknown = s.unknown + 1
        diag.Log("net", "неизвестная команда "..cmd.." от "..tostring(sender))
    end
    diag.currentCmd = cmd
    local t0 = prof()
    local ok = xpcall(function() origHandle(self, msg, sender) end, msgHandler)
    local ms = prof() - t0
    diag.currentCmd = nil
    s.totMs = s.totMs + ms
    if ms > s.maxMs then s.maxMs = ms end
    if not ok then
        n.handlerErrors = n.handlerErrors + 1
        s.errs = s.errs + 1
    end
    if ms > 50 then diag.Log("slow", string.format("обработчик %s занял %.0f мс", cmd, ms)) end
    RingPush(diag.netLog, { GetTime(), time(), "in", cmd, len, known and "" or "?", tostring(sender), Trunc(msg, 120), ms, ok })
end

-- ======================
-- 4. Контрольные суммы ставок (для сравнения у разных игроков)
-- ======================
function diag.BidsChecksum(onlyBoss)
    local bids = auction.bids
    local count, h = 0, 5381
    if type(bids) ~= "table" then return 0, 0 end
    local bosses = onlyBoss and { onlyBoss } or SortedKeys(bids)
    for _, boss in ipairs(bosses) do
        local items = bids[boss]
        if type(items) == "table" then
            for _, itemID in ipairs(SortedKeys(items, NumCmp)) do
                local list = items[itemID]
                if type(list) == "table" and #list > 0 then
                    h = Hash(h, tostring(boss)..":"..tostring(itemID))
                    for _, b in ipairs(list) do
                        count = count + 1
                        h = Hash(h, tostring(b.player)..","..tostring(b.amount)..","..(b.isOffspec and "1" or "0"))
                    end
                end
            end
        end
    end
    return count, h
end

-- ======================
-- 5. Состояние клиента / группы / ЛМ
-- ======================
local function GroupInfo()
    local g = {}
    g.nRaid = (type(GetNumRaidMembers) == "function" and GetNumRaidMembers()) or 0
    g.nParty = (type(GetNumPartyMembers) == "function" and GetNumPartyMembers()) or 0
    g.isInRaid = (type(IsInRaid) == "function") and (IsInRaid() and true or false) or nil
    g.isInGroup = (type(IsInGroup) == "function") and (IsInGroup() and true or false) or nil
    if g.nRaid > 0 then g.kind = "рейд"
    elseif g.nParty > 0 then g.kind = "группа"
    else g.kind = "соло" end
    return g
end

local function LootInfo()
    local l = {}
    if type(GetLootMethod) ~= "function" then return l end
    local method, partyIndex, raidIndex = GetLootMethod()
    l.method, l.partyIndex, l.raidIndex = method, partyIndex, raidIndex
    local me = UnitName("player")
    if method == "master" then
        if raidIndex and raidIndex > 0 and type(GetRaidRosterInfo) == "function" then
            l.masterName = (GetRaidRosterInfo(raidIndex))
        elseif partyIndex == 0 then
            l.masterName = me
        elseif partyIndex then
            l.masterName = UnitName("party"..partyIndex)
        end
        l.expectedIsMe = (l.masterName == me)
    end
    return l
end

local function FindEPGP()
    for _, nm in ipairs({ "EPGP", "EPGP_Auction", "CEPGP", "EPGPCore" }) do
        local t = _G[nm]
        if type(t) == "table" then return nm, t end
    end
end

local function AddonMemoryKB()
    if type(UpdateAddOnMemoryUsage) == "function" and type(GetAddOnMemoryUsage) == "function" then
        UpdateAddOnMemoryUsage()
        diag.lastMemKB = GetAddOnMemoryUsage("EPBossAuction")
    end
    return diag.lastMemKB
end

local function Latency()
    if type(GetNetStats) ~= "function" then return nil end
    local _, _, lat, lat2 = GetNetStats()
    return lat, lat2
end

-- Функции/глобалы, которые вызывает аддон (получено статически из исходников).
-- Если чего-то нет на клиенте — аддон упадёт ровно там, где это вызывается.
diag.API_USED = {
    "CanEditOfficerNote", "CloseDropDownMenus", "CreateFrame", "GetAddOnMetadata", "GetBuildInfo",
    "GetCursorPosition", "GetItemIcon", "GetItemInfo", "GetLootMethod", "GetLootSlotInfo",
    "GetLootSlotLink", "GetLootThreshold", "GetMasterLootCandidate", "GetNumLootItems",
    "GetNumPartyMembers", "GetNumRaidMembers", "GetRaidRosterInfo", "GetTime", "GiveMasterLoot",
    "HideUIPanel", "InCombatLockdown", "InterfaceOptionsFrame_OpenToCategory",
    "InterfaceOptions_AddCategory", "IsControlKeyDown", "IsInGroup", "IsInGuild", "IsInRaid",
    "IsRaidLeader", "IsRaidOfficer", "LootSlotIsItem", "PlaySoundFile", "SendAddonMessage",
    "SendChatMessage", "StaticPopup_Show", "UIDropDownMenu_AddButton", "UIDropDownMenu_CreateInfo",
    "UIDropDownMenu_Initialize", "UIDropDownMenu_Refresh", "UIDropDownMenu_SetText",
    "UIDropDownMenu_SetWidth", "UnitAffectingCombat", "UnitClass", "UnitName",
    "date", "hooksecurefunc", "strlower", "strsplit", "strtrim", "time", "tinsert", "wipe",
    -- нужны самой диагностике
    "debugstack", "geterrorhandler", "seterrorhandler", "GetNetStats", "GetFramerate", "GetNumAddOns",
    "GetAddOnInfo", "IsAddOnLoaded", "GetRealmName", "GetLocale", "UnitLevel", "ScrollingEdit_OnTextChanged",
}
diag.GLOBALS_USED = { "UIParent", "DEFAULT_CHAT_FRAME", "SlashCmdList", "StaticPopupDialogs",
    "UISpecialFrames", "RAID_CLASS_COLORS", "GameTooltip", "ChatFontNormal", "GameFontHighlightSmall" }
-- Эти вызовы в аддоне НЕ защищены проверкой на nil — на клиенте без них будет ошибка Lua.
diag.NOT_IN_3_3_5 = { IsInRaid = true, IsInGroup = true }

function diag.MissingAPI()
    local missing = {}
    for _, name in ipairs(diag.API_USED) do
        if type(_G[name]) ~= "function" then missing[#missing + 1] = name end
    end
    if auction.apiShims then
        for name in pairs(auction.apiShims) do missing[#missing + 1] = name end
    end
    for _, name in ipairs(diag.GLOBALS_USED) do
        if _G[name] == nil then missing[#missing + 1] = name end
    end
    return missing
end

-- ======================
-- 6. Проверки
-- ======================
local STATUS_TEXT = { ok = "[ OK ]", warn = "[ ВНИМАНИЕ ]", fail = "[ ОШИБКА ]", info = "[ инфо ]" }
diag.checkDefs = {}
local function Check(name, fn) table.insert(diag.checkDefs, { name = name, fn = fn }) end

Check("API клиента: всё ли существует", function()
    local missing = diag.MissingAPI()
    if #missing == 0 then return "ok", "все "..(#diag.API_USED + #diag.GLOBALS_USED).." используемых имён найдены" end
    local lines, unguarded = {}, false
    for _, n in ipairs(missing) do
        if auction.apiShims and auction.apiShims[n] then
            lines[#lines + 1] = n.." — нет в клиенте, подставлена заглушка из core.lua (на 3.3.5 это норма)"
        elseif diag.NOT_IN_3_3_5[n] then
            unguarded = true
            lines[#lines + 1] = n.." — НЕТ, вызывается без проверки (в 3.3.5 такой функции не было)"
        else
            lines[#lines + 1] = n.." — нет"
        end
    end
    local onlyShims = true
    for _, n in ipairs(missing) do if not (auction.apiShims and auction.apiShims[n]) then onlyShims = false end end
    if onlyShims then return "info", table.concat(lines, "\n") end
    return unguarded and "fail" or "warn", table.concat(lines, "\n")
end)

Check("Группа: IsInRaid/IsInGroup против GetNum*Members", function()
    local g = GroupInfo()
    if g.isInRaid == nil or g.isInGroup == nil then
        return "warn", "IsInRaid/IsInGroup не существуют на этом клиенте; код аддона их вызывает"
    end
    if auction.apiShims and (auction.apiShims.IsInRaid or auction.apiShims.IsInGroup) then
        return "info", string.format("используются заглушки core.lua (IsInRaid/IsInGroup через GetNum*Members): %s: рейд=%d, группа=%d", g.kind, g.nRaid, g.nParty)
    end
    local bad = {}
    if g.isInRaid ~= (g.nRaid > 0) then
        bad[#bad + 1] = string.format("IsInRaid()=%s, а GetNumRaidMembers()=%d", tostring(g.isInRaid), g.nRaid)
    end
    local inGroup = (g.nRaid > 0) or (g.nParty > 0)
    if g.isInGroup ~= inGroup then
        bad[#bad + 1] = string.format("IsInGroup()=%s, а рейд=%d группа=%d", tostring(g.isInGroup), g.nRaid, g.nParty)
    end
    if #bad > 0 then return "fail", table.concat(bad, "\n") end
    return "ok", string.format("%s: рейд=%d, группа=%d", g.kind, g.nRaid, g.nParty)
end)

Check("Роль ЛМ: IsLootMaster() против GetLootMethod()", function()
    if type(GetLootMethod) ~= "function" then return "fail", "GetLootMethod отсутствует" end
    local l = LootInfo()
    local ok, res = pcall(auction.IsLootMaster, auction)
    if not ok then return "fail", "IsLootMaster() падает: "..tostring(res) end
    local detail = string.format("метод=%s, partyIndex=%s, raidIndex=%s, мастер=%s; IsLootMaster()=%s",
        tostring(l.method), tostring(l.partyIndex), tostring(l.raidIndex), tostring(l.masterName), tostring(res))
    if l.method ~= "master" then
        if res then return "fail", detail.."\nметод не master, а IsLootMaster()=true" end
        return "info", detail
    end
    if l.expectedIsMe ~= nil and l.expectedIsMe ~= (res and true or false) then
        return "fail", detail.."\nрасхождение: по данным клиента я "..(l.expectedIsMe and "ЛМ" or "не ЛМ")..", аддон считает наоборот"
    end
    return "ok", detail
end)

Check("Роль ЛМ: что аддон помнит по сети (lastLM)", function()
    local g = GroupInfo()
    local l = LootInfo()
    local me = UnitName("player")
    local last = auction.lastLM
    local detail = string.format("lastLM=%s, мастер по клиенту=%s, группа=%s", tostring(last), tostring(l.masterName), g.kind)
    if g.kind == "соло" then
        if last then return "warn", detail.."\nвне группы lastLM должен сбрасываться" end
        return "ok", detail
    end
    if l.method ~= "master" then
        if last then return "warn", detail.."\nметод добычи не master, а lastLM задан" end
        return "info", detail
    end
    if l.masterName and last and l.masterName ~= last then
        return "warn", detail.."\nlastLM не совпадает с реальным мастер-лутом (ждите пересинхронизации или это баг сброса)"
    end
    if l.masterName == me and last ~= me then
        return "warn", detail.."\nя мастер-лут, но lastLM — не я (SyncAllToRaid/LM не отработали?)"
    end
    if not last and l.masterName then return "warn", detail.."\nlastLM не задан при действующем мастер-луте" end
    return "ok", detail
end)

Check("Таймеры", function()
    local n = #auction.timers
    local now = GetTime()
    local overdue = 0
    for _, t in ipairs(auction.timers) do if t.expires < now - 5 then overdue = overdue + 1 end end
    local detail = string.format("в очереди %d; запланировано за сессию %d, сработало %d, просрочено >5с: %d",
        n, diag.timerStats.scheduled, diag.timerStats.fired, overdue)
    if overdue > 0 then return "fail", detail.."\nOnUpdate-фрейм таймеров не работает или завис" end
    if n > 60 then return "warn", detail.."\nочередь растёт — возможна утечка таймеров" end
    return "ok", detail
end)

Check("Данные: боссы и предметы (core.lua)", function()
    local problems, empty, total = {}, 0, 0
    for _, boss in ipairs(SortedKeys(auction.bosses)) do
        local list, seen = auction.bosses[boss], {}
        if #list == 0 then empty = empty + 1 end
        for _, id in ipairs(list) do
            total = total + 1
            if type(id) ~= "number" then
                problems[#problems + 1] = boss..": нечисловой itemID "..tostring(id)
            elseif seen[id] then
                problems[#problems + 1] = boss..": itemID "..id.." указан дважды"
            end
            seen[id] = true
        end
    end
    local detail = string.format("боссов %d (пустых %d), предметов %d", #SortedKeys(auction.bosses), empty, total)
    if #problems > 0 then return "warn", detail.."\n"..table.concat(problems, "\n") end
    return "ok", detail
end)

Check("Данные: меню подземелий (instances)", function()
    if type(auction.instances) ~= "table" then return "fail", "auction.instances не таблица" end
    local problems, inMenu = {}, {}
    for inst, list in pairs(auction.instances) do
        for _, boss in ipairs(list) do
            inMenu[boss] = true
            if not auction.bosses[boss] then problems[#problems + 1] = inst..": босс «"..boss.."» отсутствует в auction.bosses" end
        end
    end
    for boss in pairs(auction.bosses) do
        if not inMenu[boss] then problems[#problems + 1] = "босс «"..boss.."» не попал ни в одно подземелье (его нет в меню)" end
    end
    if #problems > 0 then return "warn", table.concat(problems, "\n") end
    return "ok", "все боссы сопоставлены подземельям"
end)

Check("Данные: ставки (auction.bids)", function()
    if type(auction.bids) ~= "table" then return "fail", "auction.bids не таблица: "..type(auction.bids) end
    local problems, total, items = {}, 0, 0
    for boss, byItem in pairs(auction.bids) do
        if not auction.bosses[boss] then
            problems[#problems + 1] = "ставки на неизвестного босса «"..tostring(boss).."»"
        elseif type(byItem) ~= "table" then
            problems[#problems + 1] = boss..": не таблица"
        else
            for itemID, list in pairs(byItem) do
                items = items + 1
                local numID = tonumber(itemID)
                if not numID then
                    problems[#problems + 1] = boss..": нечисловой ключ предмета "..tostring(itemID)
                elseif not BossHasItem(boss, numID) then
                    problems[#problems + 1] = boss..": предмет "..numID.." не из лута этого босса"
                end
                if type(list) ~= "table" then
                    problems[#problems + 1] = boss.."/"..tostring(itemID)..": список не таблица"
                else
                    local seenPlayers = {}
                    for i, b in ipairs(list) do
                        total = total + 1
                        if type(b) ~= "table" then
                            problems[#problems + 1] = boss.."/"..tostring(itemID).." #"..i..": запись не таблица"
                        else
                            if type(b.player) ~= "string" or b.player == "" then
                                problems[#problems + 1] = boss.."/"..tostring(itemID).." #"..i..": нет имени игрока"
                            elseif seenPlayers[b.player] then
                                problems[#problems + 1] = boss.."/"..tostring(itemID)..": игрок "..b.player.." в списке дважды"
                            end
                            seenPlayers[b.player or "?"] = true
                            if type(b.amount) ~= "number" then
                                problems[#problems + 1] = boss.."/"..tostring(itemID)..": ставка "..tostring(b.player).." типа "..type(b.amount).." ("..tostring(b.amount)..") — сравнения сломаются"
                            elseif b.amount < 0 then
                                problems[#problems + 1] = boss.."/"..tostring(itemID)..": отрицательная ставка "..tostring(b.player)
                            end
                            if b.isOffspec ~= nil and type(b.isOffspec) ~= "boolean" then
                                problems[#problems + 1] = boss.."/"..tostring(itemID)..": isOffspec типа "..type(b.isOffspec)
                            end
                        end
                    end
                end
            end
        end
    end
    local detail = string.format("ставок %d на %d предметах", total, items)
    if #problems > 0 then
        if #problems > 25 then
            local n = #problems
            for i = n, 26, -1 do problems[i] = nil end
            problems[#problems + 1] = "... и ещё (показаны первые 25)"
        end
        return "fail", detail.."\n"..table.concat(problems, "\n")
    end
    return "ok", detail
end)

Check("Данные: версии данных (dataVersions)", function()
    if type(auction.dataVersions) ~= "table" then return "fail", "dataVersions не таблица" end
    local problems, n = {}, 0
    for key, v in pairs(auction.dataVersions) do
        n = n + 1
        local boss, id = tostring(key):match("^(.+):(%d+)$")
        if not boss then
            problems[#problems + 1] = "ключ «"..tostring(key).."» не вида босс:itemID"
        elseif not auction.bosses[boss] then
            problems[#problems + 1] = "версия для неизвестного босса «"..boss.."»"
        end
        if type(v) ~= "number" then problems[#problems + 1] = tostring(key)..": версия типа "..type(v) end
    end
    local lv = 0
    for _ in pairs(auction.lastVersions or {}) do lv = lv + 1 end
    local detail = string.format("dataVersions: %d, lastVersions: %d", n, lv)
    if #problems > 0 then return "warn", detail.."\n"..table.concat(problems, "\n", 1, math.min(#problems, 15)) end
    return "ok", detail
end)

Check("Данные: явка (signups)", function()
    local s = auction.signups
    if s == nil then return "info", "ещё не создана (создаётся при первой отметке)" end
    if type(s) ~= "table" then return "fail", "signups не таблица" end
    local valid = {}
    for _, c in ipairs(auction.SIGNUP_CATEGORIES or {}) do valid[c.key] = true end
    local problems, n = {}, 0
    for boss, cats in pairs(s) do
        if not auction.bosses[boss] then problems[#problems + 1] = "явка на неизвестного босса «"..tostring(boss).."»" end
        if type(cats) == "table" then
            for cat, players in pairs(cats) do
                if not valid[cat] then problems[#problems + 1] = boss..": устаревшая категория «"..tostring(cat).."»" end
                if type(players) == "table" then for _ in pairs(players) do n = n + 1 end end
            end
        else
            problems[#problems + 1] = boss..": не таблица"
        end
    end
    if #problems > 0 then return "warn", "отметок "..n.."\n"..table.concat(problems, "\n", 1, math.min(#problems, 15)) end
    return "ok", "отметок "..n
end)

Check("Данные: посещаемость (attendance)", function()
    local a = auction.attendance
    if type(a) ~= "table" then return "fail", "auction.attendance не таблица" end
    if #a == 0 then return "info", "записей нет" end
    local problems, ids, dupIds = {}, {}, 0
    local sameKill = auction.ATTENDANCE_SAME_KILL_SECONDS or 300
    local prev
    for i, r in ipairs(a) do
        if type(r) ~= "table" then
            problems[#problems + 1] = "#"..i..": не таблица"
        else
            if type(r.t) ~= "number" then problems[#problems + 1] = "#"..i..": нет времени t" end
            if type(r.players) ~= "table" then
                problems[#problems + 1] = "#"..i..": нет players"
            else
                local c = 0
                for _ in pairs(r.players) do c = c + 1 end
                if c == 0 then problems[#problems + 1] = "#"..i..": пустой состав" end
                if type(r.rested) == "table" then
                    for name in pairs(r.rested) do
                        if not r.players[name] then problems[#problems + 1] = "#"..i..": «отдыхающий» "..tostring(name).." не в составе" end
                    end
                end
            end
            if r.id ~= nil then
                if ids[r.id] then dupIds = dupIds + 1 end
                ids[r.id] = true
            end
            if prev and type(r.t) == "number" and type(prev.t) == "number" then
                if r.t < prev.t then
                    problems[#problems + 1] = "#"..i..": нарушен порядок по времени (список должен идти по возрастанию)"
                elseif auction.IsSameKill and auction:IsSameKill(prev.boss, prev.t, prev.players, r.boss, r.t, r.players) then
                    problems[#problems + 1] = "#"..i..": дубль килла «"..tostring(r.boss).."» (тот же босс и почти тот же состав в пределах "..sameKill.." с)"
                end
            end
            prev = r
        end
    end
    if dupIds > 0 then problems[#problems + 1] = "повторяющихся id записей: "..dupIds end
    local max = auction.ATTENDANCE_MAX_RECORDS or 600
    local detail = string.format("записей %d из %d", #a, max)
    if #a > max then problems[#problems + 1] = "записей больше лимита" end
    if #problems > 0 then return "warn", detail.."\n"..table.concat(problems, "\n", 1, math.min(#problems, 15)) end
    return "ok", detail
end)

Check("Данные: резерв предметов", function()
    local r = auction.reserves
    if type(r) ~= "table" then return "fail", "auction.reserves не таблица" end
    local problems, live, tomb = {}, 0, 0
    for boss, items in pairs(r) do
        if not auction.bosses[boss] then problems[#problems + 1] = "резерв на неизвестного босса «"..tostring(boss).."»" end
        if type(items) == "table" then
            for id, e in pairs(items) do
                if type(e) ~= "table" or type(e.qty) ~= "number" then
                    problems[#problems + 1] = boss.."/"..tostring(id)..": некорректная запись"
                else
                    if e.qty > 0 then live = live + 1 else tomb = tomb + 1 end
                    if not BossHasItem(boss, tonumber(id)) then problems[#problems + 1] = boss.."/"..tostring(id)..": предмет не из лута босса" end
                end
            end
        end
    end
    local pub = 0
    if type(auction.reservePublic) == "table" then
        for _, items in pairs(auction.reservePublic) do if type(items) == "table" then for _ in pairs(items) do pub = pub + 1 end end end
    end
    local detail = string.format("активных %d, «надгробий» %d, публичных (от ЛМ) %d", live, tomb, pub)
    if #problems > 0 then return "warn", detail.."\n"..table.concat(problems, "\n", 1, math.min(#problems, 15)) end
    return "ok", detail
end)

Check("Данные: журнал выдач", function()
    local log = EPBossAuctionSavedLootLog
    if log == nil then return "info", "журнала нет" end
    if type(log) ~= "table" then return "fail", "EPBossAuctionSavedLootLog не таблица" end
    local problems, ids, dup = {}, {}, 0
    for i, e in ipairs(log) do
        if type(e) ~= "table" then
            problems[#problems + 1] = "#"..i..": не таблица"
        else
            if type(e.t) ~= "number" then problems[#problems + 1] = "#"..i..": нет времени" end
            local kind = e.kind or "item"
            if kind == "item" then
                if type(e.winner) ~= "string" then problems[#problems + 1] = "#"..i..": нет победителя" end
                if e.charged and type(e.chargedAmount) ~= "number" then problems[#problems + 1] = "#"..i..": charged без chargedAmount" end
            elseif kind == "mass" then
                if type(e.amount) ~= "number" then problems[#problems + 1] = "#"..i..": mass без amount" end
            else
                problems[#problems + 1] = "#"..i..": неизвестный kind «"..tostring(kind).."»"
            end
            if e.id then if ids[e.id] then dup = dup + 1 end ids[e.id] = true end
        end
    end
    if dup > 0 then problems[#problems + 1] = "повторяющихся id: "..dup end
    local max = auction.STATS_MAX_RECORDS or 2000
    local detail = string.format("записей %d из %d", #log, max)
    if #problems > 0 then return "warn", detail.."\n"..table.concat(problems, "\n", 1, math.min(#problems, 15)) end
    return "ok", detail
end)

Check("SavedVariables: объём", function()
    local sv = {
        Bids = EPBossAuctionSavedBids, Signups = EPBossAuctionSavedSignups,
        Attendance = EPBossAuctionSavedAttendance, Reserves = EPBossAuctionSavedReserves,
        LootLog = EPBossAuctionSavedLootLog, Settings = EPBossAuctionSettings,
    }
    local lines, total = {}, 0
    for _, k in ipairs(SortedKeys(sv)) do
        local n = CountNodes(sv[k])
        total = total + n
        lines[#lines + 1] = k..": "..n.." узлов"
    end
    local detail = "всего "..total.." узлов ("..table.concat(lines, ", ")..")"
    if total > 150000 then return "warn", detail.."\nмного: вход/выход из игры станет медленнее" end
    return "ok", detail
end)

Check("EPGP-мост (epgp.lua)", function()
    local name, t = FindEPGP()
    if not name then return "fail", "ни EPGP, ни EPGP_Auction, ни CEPGP, ни EPGPCore не найдены — EP получить нельзя" end
    local me = UnitName("player")
    local lines = { string.format("найден: %s (GetEPGP=%s, GetEP=%s, Update=%s, db=%s)", name,
        type(t.GetEPGP), type(t.GetEP), type(t.Update), type(t.db)) }
    local status = "ok"
    if type(t.GetEPGP) == "function" then
        local ok, ep, gp, main = pcall(t.GetEPGP, t, me)
        if not ok then
            status = "fail"; lines[#lines + 1] = "GetEPGP(я) падает: "..tostring(ep)
        else
            lines[#lines + 1] = string.format("GetEPGP(%s) -> EP=%s GP=%s main=%s", me, tostring(ep), tostring(gp), tostring(main))
            if ep == nil then status = "warn"; lines[#lines + 1] = "EP игрока не получен (нет в гильдии/в базе EPGP?)" end
        end
    elseif type(t.GetEP) ~= "function" and not (t.db and t.db.profile) then
        status = "fail"; lines[#lines + 1] = "ни один из трёх способов получения EP не доступен"
    end
    lines[#lines + 1] = "мой EP в аддоне: "..tostring(auction.myEP)
    return status, table.concat(lines, "\n")
end)

Check("Сеть: здоровье протокола", function()
    local n = diag.net
    local lines = { string.format("исходящих %d (%d Б), входящих %d (%d Б), пик исходящих за 10 с: %d, самое длинное: %d Б",
        n.outN, n.outB, n.inN, n.inB, n.peak10, n.longest) }
    local status = "ok"
    if n.oversize > 0 then status = "fail"; lines[#lines + 1] = "сообщений сверх лимита "..MSG_LIMIT..": "..n.oversize.." (сервер их режет — данные теряются)" end
    if n.handlerErrors > 0 then status = "fail"; lines[#lines + 1] = "ошибок в обработчиках входящих: "..n.handlerErrors end
    if n.unknown > 0 then
        if status == "ok" then status = "warn" end
        lines[#lines + 1] = "неизвестных команд получено: "..n.unknown.." (у кого-то другая версия аддона)"
    end
    if n.peak10 >= 20 then
        if status == "ok" then status = "warn" end
        lines[#lines + 1] = "пик "..n.peak10.." сообщений за 10 с — риск троттлинга сервером"
    end
    return status, table.concat(lines, "\n")
end)

Check("Ошибки Lua с начала сессии", function()
    if diag.errorTotal == 0 then return "ok", "ошибок нет" end
    local lines = { string.format("всего %d, уникальных %d (см. вкладку «Ошибки»)", diag.errorTotal, #diag.errors) }
    for i = math.max(1, #diag.errors - 2), #diag.errors do
        lines[#lines + 1] = "• "..Trunc(diag.errors[i].msg, 160).." ×"..diag.errors[i].count
    end
    return "fail", table.concat(lines, "\n")
end)

Check("Перехват ошибок", function()
    if diag.hookActive then return "ok", "глобальный обработчик установлен" end
    return "warn", "глобальный обработчик не установлен (ошибки из событий/кнопок могут не попасть в отчёт; ошибки таймеров и сообщений ловятся всегда)"
end)

Check("Режим отладки", function()
    if auction.debug then
        return "warn", "auction.debug = true: все игроки видят серые [EPBA DEBUG] строки в чате (журнал пишется и без этого)"
    end
    return "ok", "вывод отладки в чат выключен"
end)

Check("Окна: позиция и масштаб", function()
    local f = auction.frame
    if not f then return "info", "главное окно не создано" end
    local lines, status = {}, "ok"
    local scale = f:GetScale() or 1
    if scale < 0.5 or scale > 2.5 then status = "warn"; lines[#lines + 1] = "странный масштаб "..string.format("%.2f", scale) end
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    if l and r and t and b then
        local s = f:GetEffectiveScale()
        local sw, sh = UIParent:GetWidth() * UIParent:GetEffectiveScale(), UIParent:GetHeight() * UIParent:GetEffectiveScale()
        if r * s < 40 or l * s > sw - 40 or t * s < 40 or b * s > sh - 40 then
            status = "warn"; lines[#lines + 1] = "главное окно почти целиком за пределами экрана"
        end
        lines[#lines + 1] = string.format("главное окно: x=%.0f..%.0f y=%.0f..%.0f масштаб %.2f", l, r, b, t, scale)
    end
    return status, table.concat(lines, "\n")
end)

Check("Версия и «Что нового?»", function()
    local toc = GetAddOnMetadata and GetAddOnMetadata("EPBossAuction", "Version")
    local lines, status = { "toc: "..tostring(toc)..", аддон: "..tostring(auction.version) }, "ok"
    if toc ~= auction.version then status = "warn"; lines[#lines + 1] = "версия в toc и в аддоне расходятся" end
    if type(auction.changelog) == "table" and not auction.changelog[auction.version] then
        status = "warn"; lines[#lines + 1] = "в changelog.lua нет записи для версии "..tostring(auction.version)
    end
    return status, table.concat(lines, "\n")
end)

Check("Кэш предметов выбранного босса", function()
    local boss = auction.selectedBoss
    if not boss or not auction.bosses[boss] then return "info", "босс не выбран" end
    local miss = {}
    for _, id in ipairs(auction.bosses[boss]) do
        if not GetItemInfo(id) then miss[#miss + 1] = id end
    end
    local detail = string.format("«%s»: предметов %d, не в кэше клиента %d", boss, #auction.bosses[boss], #miss)
    if #miss > 0 then return "warn", detail.."\nне прогружены: "..table.concat(miss, ", ", 1, math.min(#miss, 12)).."\n(на таких предметах в таблице покажется «предмет N»; если не прогружаются сутками — itemID не существует на сервере)" end
    return "ok", detail
end)

function diag.RunChecks()
    local results = {}
    for _, def in ipairs(diag.checkDefs) do
        local ok, status, detail = pcall(def.fn)
        if not ok then
            status, detail = "fail", "сама проверка упала: "..tostring(status)
        end
        results[#results + 1] = { name = def.name, status = status or "info", detail = detail or "" }
    end
    return results
end

function diag.CheckSummary(results)
    local c = { ok = 0, warn = 0, fail = 0, info = 0 }
    for _, r in ipairs(results) do c[r.status] = (c[r.status] or 0) + 1 end
    return c
end

-- ======================
-- 7. Отчёты (текст)
-- ======================
local function AddonList()
    local out, loaded, total = {}, 0, GetNumAddOns and GetNumAddOns() or 0
    for i = 1, total do
        local name = GetAddOnInfo(i)
        if name and IsAddOnLoaded(i) then
            loaded = loaded + 1
            if not name:find("^Blizzard_") then
                local v = GetAddOnMetadata and GetAddOnMetadata(name, "Version")
                out[#out + 1] = v and (name.." "..v) or name
            end
        end
    end
    return out, loaded, total
end

function diag.BuildSummary()
    local L = {}
    local function add(fmt, ...) L[#L + 1] = (select("#", ...) > 0) and string.format(fmt, ...) or fmt end
    local clientVersion, clientBuild = GetBuildInfo()
    local g, l = GroupInfo(), LootInfo()
    local lat, lat2 = Latency()
    local mem = AddonMemoryKB()
    local me = UnitName("player")
    local _, class = UnitClass("player")

    add("EPBossAuction %s — диагностика", tostring(auction.version))
    add("Время: %s %s, сессия %s", date("%Y-%m-%d"), Clock(), Dur(GetTime() - sessionStart))
    add("Клиент: %s (%s), локаль %s, реалм %s", tostring(clientVersion), tostring(clientBuild), tostring(GetLocale()), tostring(GetRealmName()))
    add("Игрок: %s, %s, ур. %s, в гильдии: %s", tostring(me), tostring(class), tostring(UnitLevel("player")), YesNo(IsInGuild and IsInGuild()))
    add("Производительность: FPS %.0f, задержка %s мс, память аддона %s КБ",
        GetFramerate and GetFramerate() or 0, lat and (lat..(lat2 and ("/"..lat2) or "")) or "?", mem and string.format("%.0f", mem) or "?")
    add("")
    add("== Состояние ==")
    add("Группа: %s (рейд %d, группа %d) | IsInRaid=%s IsInGroup=%s", g.kind, g.nRaid, g.nParty, tostring(g.isInRaid), tostring(g.isInGroup))
    add("Метод добычи: %s (partyIndex=%s, raidIndex=%s), мастер по клиенту: %s", tostring(l.method), tostring(l.partyIndex), tostring(l.raidIndex), tostring(l.masterName))
    local okLM, isLM = pcall(auction.IsLootMaster, auction)
    add("Я ЛМ (IsLootMaster): %s | lastLM: %s | ставки заблокированы: %s | офф-спек: x%s",
        okLM and YesNo(isLM) or ("ОШИБКА: "..tostring(isLM)), tostring(auction.lastLM), YesNo(auction.bidsLocked), tostring(auction.offspecMultiplier))
    add("Выбран босс: %s | предмет: %s", tostring(auction.selectedBoss), tostring(auction.selectedItem))
    local epName = FindEPGP()
    add("EPGP: %s | мой EP: %s", epName or "НЕ НАЙДЕН", tostring(auction.myEP))
    add("Доступ офицера (Attendance/Резерв/Статистика): %s", YesNo(auction.CanRecordAttendance and auction:CanRecordAttendance()))
    add("Полностью загружен: %s | таймеров в очереди: %d", YesNo(auction.fullyLoaded), #auction.timers)
    add("")
    add("== Данные ==")
    local cnt, cs = diag.BidsChecksum()
    add("Ставок: %d, контрольная сумма: %d", cnt, cs)
    if auction.selectedBoss then
        local bc, bcs = diag.BidsChecksum(auction.selectedBoss)
        add("Ставок на выбранном боссе: %d, сумма: %d", bc, bcs)
    end
    add("Посещаемость: %d зап. | журнал выдач: %d зап. | версий данных: %d",
        auction.attendance and #auction.attendance or 0, EPBossAuctionSavedLootLog and #EPBossAuctionSavedLootLog or 0, CountNodes(auction.dataVersions))
    add("")
    add("== Сеть и ошибки ==")
    local n = diag.net
    add("Сообщений: исходящих %d, входящих %d | пик за 10 с: %d | сверх лимита: %d | неизвестных: %d | ошибок обработчиков: %d",
        n.outN, n.inN, n.peak10, n.oversize, n.unknown, n.handlerErrors)
    add("Ошибок Lua за сессию: %d (уникальных %d) | перехват ошибок: %s", diag.errorTotal, #diag.errors, diag.hookActive and "активен" or "нет")
    local results = diag.RunChecks()
    local c = diag.CheckSummary(results)
    add("Проверки: OK %d, внимание %d, ошибки %d (подробно — вкладка «Проверки»)", c.ok, c.warn, c.fail)
    add("")
    local addons, loaded, total = AddonList()
    add("== Аддоны (загружено %d из %d, без Blizzard_*) ==", loaded, total)
    add(table.concat(addons, ", "))
    return table.concat(L, "\n")
end

function diag.BuildChecks(onlyProblems)
    local results = diag.RunChecks()
    local c = diag.CheckSummary(results)
    local L = { string.format("Проверки: OK %d, внимание %d, ошибки %d", c.ok, c.warn, c.fail), "" }
    for _, r in ipairs(results) do
        if not onlyProblems or r.status == "warn" or r.status == "fail" then
            L[#L + 1] = STATUS_TEXT[r.status].." "..r.name
            if r.detail ~= "" then
                for line in (r.detail.."\n"):gmatch("(.-)\n") do L[#L + 1] = "      "..line end
            end
        end
    end
    if onlyProblems and #L == 2 then L[#L + 1] = "(проблем не найдено)" end
    return table.concat(L, "\n")
end

function diag.BuildLog(lastN, filter)
    local L = {}
    local list = RingList(diag.log)
    filter = filter and filter ~= "" and strlower(filter) or nil
    for _, e in ipairs(list) do
        local line = string.format("%s [%s] %s", Clock(e[2]), e[3], e[4])
        if not filter or strlower(line):find(filter, 1, true) then L[#L + 1] = line end
    end
    if lastN and #L > lastN then
        local cut = {}
        for i = #L - lastN + 1, #L do cut[#cut + 1] = L[i] end
        L = cut
    end
    local head = string.format("Журнал: %d из %d записей%s (старые вытесняются, всего за сессию %d)",
        #L, math.min(diag.log.n, diag.log.max), filter and (", фильтр «"..filter.."»") or "", diag.log.n)
    return head.."\n\n"..table.concat(L, "\n")
end

function diag.BuildNet(lastN, filter)
    local n = diag.net
    local L = {}
    L[#L + 1] = string.format("Исходящих %d (%d Б) | входящих %d (%d Б) | пик исходящих за 10 с: %d%s",
        n.outN, n.outB, n.inN, n.inB, n.peak10, n.peak10At and (" в "..Clock(n.peak10At)) or "")
    L[#L + 1] = string.format("Сверх лимита %d: %d | неизвестных команд: %d | ошибок обработчиков: %d | самое длинное: %d Б",
        MSG_LIMIT, n.oversize, n.unknown, n.handlerErrors, n.longest)
    L[#L + 1] = ""
    L[#L + 1] = "По командам: команда | исх. шт/Б | вх. шт/Б | обработка макс/сред мс | ошибок | неизв. | >лимита"
    for _, cmd in ipairs(SortedKeys(n.cmds)) do
        local s = n.cmds[cmd]
        local avg = s.inN > 0 and (s.totMs / s.inN) or 0
        L[#L + 1] = string.format("  %s | %d/%d | %d/%d | %.1f/%.1f | %d | %d | %d", cmd, s.outN, s.outB, s.inN, s.inB, s.maxMs, avg, s.errs, s.unknown, s.oversize)
    end
    L[#L + 1] = ""
    L[#L + 1] = "Последние сообщения (-> исходящее, <- входящее):"
    filter = filter and filter ~= "" and strlower(filter) or nil
    local lines = {}
    for _, e in ipairs(RingList(diag.netLog)) do
        local line
        if e[3] == "out" then
            line = string.format("%s -> %s [%s%s] %dБ: %s", Clock(e[2]), e[4], e[6], e[7] ~= "" and (" "..e[7]) or "", e[5], e[8])
        else
            line = string.format("%s <- %s от %s %dБ %.1fмс%s%s: %s", Clock(e[2]), e[4], e[7], e[5], e[9] or 0, e[10] == false and " ОШИБКА" or "", e[6] == "?" and " НЕИЗВ" or "", e[8])
        end
        if not filter or strlower(line):find(filter, 1, true) then lines[#lines + 1] = line end
    end
    local from = lastN and math.max(1, #lines - lastN + 1) or 1
    for i = from, #lines do L[#L + 1] = lines[i] end
    return table.concat(L, "\n")
end

function diag.BuildErrors()
    local L = {}
    if #diag.errors == 0 then
        L[#L + 1] = "Ошибок Lua в этой сессии нет."
    else
        L[#L + 1] = string.format("Ошибок за сессию: %d (уникальных %d)", diag.errorTotal, #diag.errors)
        for i, e in ipairs(diag.errors) do
            L[#L + 1] = ""
            L[#L + 1] = string.format("#%d ×%d [%s] первая %s, последняя %s, версия %s", i, e.count, tostring(e.src), Clock(e.first), Clock(e.last), tostring(e.ver))
            L[#L + 1] = e.msg
            if e.stack and e.stack ~= "" then L[#L + 1] = e.stack end
        end
    end
    local saved = diag.saved and diag.saved.errors
    if type(saved) == "table" and #saved > 0 then
        L[#L + 1] = ""
        L[#L + 1] = "=== Из прошлых сессий (сохранено при выходе) ==="
        for i, e in ipairs(saved) do
            L[#L + 1] = ""
            L[#L + 1] = string.format("#%d ×%s [%s] %s %s версия %s", i, tostring(e.count), tostring(e.src), date("%Y-%m-%d", e.last or 0), Clock(e.last), tostring(e.ver))
            L[#L + 1] = tostring(e.msg)
            if e.stack and e.stack ~= "" then L[#L + 1] = e.stack end
        end
    end
    return table.concat(L, "\n")
end

-- Короткий отчёт для вставки в баг-репорт (Discord/GitHub): сводка + проблемы + хвост журнала.
function diag.BuildReport()
    local parts = {
        diag.BuildSummary(), "", "=== ПРОБЛЕМЫ ПО ПРОВЕРКАМ ===", diag.BuildChecks(true), "",
        "=== ОШИБКИ LUA ===", Trunc(diag.BuildErrors(), 3500), "",
        "=== ЖУРНАЛ (последние 40) ===", diag.BuildLog(40), "",
        "=== СЕТЬ (последние 25) ===", diag.BuildNet(25),
    }
    return table.concat(parts, "\n")
end

-- Короткая строка для окна контактов (заменяет версию из contacts.lua).
function auction:GetDiagnosticsString()
    local ok, res = pcall(function()
        local v, b = GetBuildInfo()
        local g, l = GroupInfo(), LootInfo()
        local cnt, cs = diag.BidsChecksum()
        local lat = Latency()
        local missing = diag.MissingAPI()
        local isLM = Safe(auction.IsLootMaster, auction)
        return string.format("EPBA %s | клиент %s (%s) %s | %s %d | ЛМ: %s (мастер: %s, lastLM: %s) | офицер: %s | босс: %s | ставок %d [%d] | ош. %d | сеть %d/%d | lag %s | нет API: %d%s",
            tostring(auction.version), tostring(v), tostring(b), tostring(GetLocale()),
            g.kind, math.max(g.nRaid, g.nParty),
            isLM == nil and "ОШИБКА" or YesNo(isLM), tostring(l.masterName), tostring(auction.lastLM),
            YesNo(auction.CanRecordAttendance and auction:CanRecordAttendance()),
            tostring(auction.selectedBoss or "—"), cnt, cs, diag.errorTotal, diag.net.outN, diag.net.inN,
            lat and tostring(lat) or "?", #missing, #missing > 0 and (" ("..table.concat(missing, ",", 1, math.min(#missing, 4))..")") or "")
    end)
    return ok and res or ("EPBA "..tostring(auction.version).." | диагностика не собралась: "..tostring(res))
end

-- ======================
-- 8. Опрос рейда (DPING / DPONG)
-- ======================
diag.raid = nil
local lastPongAt = 0

function auction:Handle_DPING(rest, sender)
    if sender == UnitName("player") then return end
    local now = GetTime()
    if now - lastPongAt < 2 then return end            -- не даём устроить спам-опросом
    lastPongAt = now
    local id, boss = strsplit(";", rest or "")
    if not id or id == "" then return end
    local cnt, cs = diag.BidsChecksum()
    local bcnt, bcs = 0, 0
    if boss and boss ~= "" then bcnt, bcs = diag.BidsChecksum(boss) end
    local isLM = Safe(self.IsLootMaster, self)
    local _, build = GetBuildInfo()
    local msg = string.format("DPONG;%s;%s;%s;%d;%d;%d;%d;%d;%d;%s", id, tostring(self.version), tostring(self.lastLM or "-"),
        isLM and 1 or 0, cnt, cs, bcnt, bcs, diag.errorTotal, tostring(build))
    SendAddonMessage(self.prefix, msg, "WHISPER", sender)
end

function auction:Handle_DPONG(rest, sender)
    local r = diag.raid
    if not r then return end
    local id, ver, lm, isLM, cnt, cs, bcnt, bcs, errs, build = strsplit(";", rest or "")
    if id ~= r.id then return end
    r.replies[sender] = {
        ver = ver, lm = lm, isLM = (isLM == "1"), cnt = tonumber(cnt), cs = tonumber(cs),
        bcnt = tonumber(bcnt), bcs = tonumber(bcs), errs = tonumber(errs), build = build,
        ms = math.floor((GetTime() - r.started) * 1000),
    }
    if diag.frame and diag.frame:IsShown() and diag.tab == "raid" then diag.Refresh() end
end

function diag.StartRaidPing()
    local g = GroupInfo()
    local channel = (g.nRaid > 0 and "RAID") or (g.nParty > 0 and "PARTY") or nil
    if not channel then
        diag.raid = nil
        diag.raidError = "Вы не в группе и не в рейде — опрашивать некого."
        return false
    end
    diag.raidError = nil
    local id = tostring(math.random(1000, 9999))
    local boss = auction.selectedBoss or ""
    local bcnt, bcs = 0, 0
    if boss ~= "" then bcnt, bcs = diag.BidsChecksum(boss) end
    local cnt, cs = diag.BidsChecksum()
    local me = UnitName("player")
    local isLM = Safe(auction.IsLootMaster, auction)
    local _, build = GetBuildInfo()
    diag.raid = { id = id, started = GetTime(), at = time(), boss = boss, channel = channel, replies = {} }
    diag.raid.replies[me] = { ver = tostring(auction.version), lm = tostring(auction.lastLM or "-"), isLM = isLM and true or false,
        cnt = cnt, cs = cs, bcnt = bcnt, bcs = bcs, errs = diag.errorTotal, build = tostring(build), ms = 0, self = true }
    SendAddonMessage(auction.prefix, "DPING;"..id..";"..boss, channel)
    diag.Log("net", "опрос рейда "..id.." по каналу "..channel)
    auction:ScheduleTimer(function()
        if diag.frame and diag.frame:IsShown() and diag.tab == "raid" then diag.Refresh() end
    end, 5)
    return true
end

function diag.BuildRaid()
    local r = diag.raid
    if not r then
        return (diag.raidError or "Опрос ещё не запускался.").."\n\nНажмите «Опросить рейд»: каждый участник с аддоном EPBA версии с диагностикой ответит приватным сообщением (версия аддона, кого он считает ЛМ, число ставок и контрольная сумма ставок). Так видно, у кого данные разошлись с ЛМ."
    end
    local L = {}
    local lmEntry, lmName
    for name, e in pairs(r.replies) do if e.isLM then lmEntry, lmName = e, name end end
    local ref = lmEntry or r.replies[UnitName("player")]
    local refName = lmEntry and ("ЛМ "..lmName) or "мои данные"
    local roster = {}
    if type(GetRaidRosterInfo) == "function" then
        for i = 1, (GetNumRaidMembers() or 0) do
            local name = GetRaidRosterInfo(i)
            if name then roster[#roster + 1] = name end
        end
    else
        for i = 1, (GetNumPartyMembers() or 0) do local nm = UnitName("party"..i); if nm then roster[#roster + 1] = nm end end
    end
    local answered = 0
    for _ in pairs(r.replies) do answered = answered + 1 end
    L[#L + 1] = string.format("Опрос %s в %s по каналу %s, босс для сравнения: %s", r.id, Clock(r.at), r.channel, r.boss ~= "" and r.boss or "—")
    L[#L + 1] = string.format("Ответили: %d, в составе: %d. Эталон для сравнения сумм: %s", answered, #roster, refName)
    L[#L + 1] = "Игрок | версия | кого считает ЛМ | ЛМ? | ставок (всего/босс) | сумма босса | ошибок | мс"
    L[#L + 1] = ""
    local myVer = tostring(auction.version)
    local expectedLM = lmName or auction.lastLM
    for _, name in ipairs(SortedKeys(r.replies)) do
        local e = r.replies[name]
        local flags = {}
        if e.ver ~= myVer then flags[#flags + 1] = "другая версия" end
        if expectedLM and e.lm ~= "-" and e.lm ~= expectedLM and not e.isLM then flags[#flags + 1] = "считает ЛМ другого: "..e.lm end
        if expectedLM and e.lm == "-" and not e.isLM then flags[#flags + 1] = "не знает ЛМ" end
        if ref and r.boss ~= "" and e.bcs ~= ref.bcs then flags[#flags + 1] = "ставки на боссе РАСХОДЯТСЯ" end
        if e.errs and e.errs > 0 then flags[#flags + 1] = "есть ошибки Lua" end
        L[#L + 1] = string.format("%s%s | %s | %s | %s | %s/%s | %s | %s | %s%s", name, e.self and " (я)" or "", e.ver, e.lm, e.isLM and "ДА" or "-",
            tostring(e.cnt), tostring(e.bcnt), tostring(e.bcs), tostring(e.errs), tostring(e.ms),
            #flags > 0 and ("  <== "..table.concat(flags, "; ")) or "")
    end
    local silent = {}
    for _, name in ipairs(roster) do if not r.replies[name] then silent[#silent + 1] = name end end
    L[#L + 1] = ""
    if #silent > 0 then
        L[#L + 1] = "Не ответили ("..#silent.."): "..table.concat(silent, ", ")
        L[#L + 1] = "(нет аддона, версия без диагностики, не успели за "..math.floor(GetTime() - r.started).." с, либо отключён)"
    else
        L[#L + 1] = "Ответили все из состава."
    end
    return table.concat(L, "\n")
end

-- ======================
-- 9. Окно «Диагностика»
-- ======================
local TABS = {
    { key = "summary", label = "Сводка" },
    { key = "checks",  label = "Проверки" },
    { key = "log",     label = "Лог" },
    { key = "net",     label = "Сеть" },
    { key = "errors",  label = "Ошибки" },
    { key = "raid",    label = "Рейд" },
    { key = "report",  label = "Отчёт" },
}
diag.tab = "summary"

function diag.GetTabText(tab, filter)
    if tab == "summary" then return diag.BuildSummary()
    elseif tab == "checks" then return diag.BuildChecks(false)
    elseif tab == "log" then return diag.BuildLog(nil, filter)
    elseif tab == "net" then return diag.BuildNet(nil, filter)
    elseif tab == "errors" then return diag.BuildErrors()
    elseif tab == "raid" then return diag.BuildRaid()
    elseif tab == "report" then return diag.BuildReport() end
    return ""
end

function diag.Refresh()
    local f = diag.frame
    if not f then return end
    local filter = f.filterBox and f.filterBox:GetText() or ""
    local ok, text = pcall(diag.GetTabText, diag.tab, filter)
    if not ok then text = "Не удалось собрать вкладку: "..tostring(text) end
    local eb = f.editBox
    eb._value = text
    eb:SetText(text)
    if diag.tab == "log" or diag.tab == "net" then
        eb:SetCursorPosition(#text)      -- к самым свежим записям
    else
        eb:SetCursorPosition(0)
    end
    for _, tb in ipairs(f.tabButtons) do
        if tb.key == diag.tab then
            tb:LockHighlight()
        else
            tb:UnlockHighlight()
        end
    end
    -- Region:SetShown появился позже 3.3.5, поэтому Show/Hide вручную
    local function Toggle(w, on) if on then w:Show() else w:Hide() end end
    local isFilterTab = (diag.tab == "log" or diag.tab == "net")
    Toggle(f.filterBox, isFilterTab)
    Toggle(f.filterLabel, isFilterTab)
    Toggle(f.raidButton, diag.tab == "raid")
end

local function BuildWindow()
    local c = auction.theme.colors
    local f = CreateFrame("Frame", "EPBossAuctionDiagFrame", UIParent)
    f:SetSize(760, 580)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    auction:SkinPanel(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "EPBossAuctionDiagFrame")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Диагностика EPBossAuction")
    title:SetTextColor(c.accent[1], c.accent[2], c.accent[3])

    f.tabButtons = {}
    local tabW = 100
    for i, tab in ipairs(TABS) do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(tabW, 22)
        b:SetPoint("TOPLEFT", 16 + (i - 1) * (tabW + 4), -42)
        b:SetText(tab.label)
        auction:SkinButton(b)
        b.key = tab.key
        b:SetScript("OnClick", function()
            diag.tab = tab.key
            diag.Refresh()
        end)
        f.tabButtons[#f.tabButtons + 1] = b
    end

    f.filterLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.filterLabel:SetPoint("TOPLEFT", 16, -72)
    f.filterLabel:SetText("Фильтр:")
    f.filterBox = CreateFrame("EditBox", nil, f)
    f.filterBox:SetPoint("LEFT", f.filterLabel, "RIGHT", 6, 0)
    f.filterBox:SetSize(240, 20)
    f.filterBox:SetAutoFocus(false)
    f.filterBox:SetFontObject(GameFontHighlight)
    f.filterBox:SetTextInsets(6, 6, 0, 0)
    auction:SkinInput(f.filterBox)
    f.filterBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.filterBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); diag.Refresh() end)
    f.filterBox:SetScript("OnTextChanged", function(self, userInput) if userInput then diag.Refresh() end end)

    local sf = CreateFrame("ScrollFrame", "EPBossAuctionDiagScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 16, -96)
    sf:SetSize(698, 432)
    pcall(auction.SkinScrollBar, auction, _G["EPBossAuctionDiagScrollScrollBar"])

    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(0)
    eb:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    eb:SetWidth(690)
    eb:SetTextInsets(4, 4, 2, 2)
    eb._value = ""
    -- Текст нельзя править (откатывается), но можно выделить и скопировать (Ctrl+A, Ctrl+C).
    eb:SetScript("OnTextChanged", function(self, userInput)
        if userInput and self:GetText() ~= self._value then
            self:SetText(self._value)
            return
        end
        if type(ScrollingEdit_OnTextChanged) == "function" then pcall(ScrollingEdit_OnTextChanged, self, sf) end
    end)
    eb:SetScript("OnCursorChanged", function(self, x, y, w, h)
        if type(ScrollingEdit_OnCursorChanged) == "function" then pcall(ScrollingEdit_OnCursorChanged, self, x, y, w, h) end
    end)
    eb:SetScript("OnUpdate", function(self, elapsed)
        if type(ScrollingEdit_OnUpdate) == "function" then pcall(ScrollingEdit_OnUpdate, self, elapsed, sf) end
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    sf:SetScrollChild(eb)
    f.editBox, f.scroll = eb, sf

    local function MakeButton(text, w, anchorPoint, x, onClick)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(w, 24)
        b:SetPoint(anchorPoint, x, 14)
        b:SetText(text)
        auction:SkinButton(b)
        b:SetScript("OnClick", onClick)
        return b
    end
    MakeButton("Обновить", 90, "BOTTOMLEFT", 16, function() diag.Refresh() end)
    MakeButton("Выделить всё", 110, "BOTTOMLEFT", 112, function()
        f.editBox:SetFocus()
        f.editBox:HighlightText()
    end)
    MakeButton("В чат", 80, "BOTTOMLEFT", 228, function() diag.PrintLines(diag.GetTabText(diag.tab, f.filterBox:GetText())) end)
    MakeButton("Очистить", 90, "BOTTOMLEFT", 314, function()
        diag.ClearAll()
        diag.Refresh()
    end)
    f.raidButton = MakeButton("Опросить рейд", 120, "BOTTOMLEFT", 410, function()
        diag.StartRaidPing()
        diag.Refresh()
    end)
    MakeButton("Закрыть", 90, "BOTTOMRIGHT", -16, function() f:Hide() end)

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", 0, 44)
    hint:SetText("Нажмите «Выделить всё», затем Ctrl+C — и вставьте отчёт в сообщение о баге")
    return f
end

function diag.ShowWindow(tab)
    if tab then diag.tab = tab end
    if not diag.frame then
        local ok, f = pcall(BuildWindow)
        if not ok then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4040[EPBA]|r не удалось создать окно диагностики: "..tostring(f))
            diag.PrintLines(diag.GetTabText(diag.tab))
            return
        end
        diag.frame = f
    end
    diag.frame:Show()
    diag.Refresh()
end

function diag.PrintLines(text)
    for line in (tostring(text).."\n"):gmatch("(.-)\n") do
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r "..line)
    end
end

function diag.ClearAll()
    RingClear(diag.log)
    RingClear(diag.netLog)
    diag.errors, diag.errorTotal = {}, 0
    local n = diag.net
    n.inN, n.inB, n.outN, n.outB, n.oversize, n.unknown, n.handlerErrors, n.longest, n.peak10, n.peak10At = 0, 0, 0, 0, 0, 0, 0, 0, 0, nil
    n.cmds, n.outTimes = {}, {}
    diag.raid = nil
end

-- /epba diag [вкладка|chat|clear|debug|ping]
function auction:DiagCommand(arg)
    arg = strlower(strtrim(arg or ""))
    local cmd, rest = arg:match("^(%S*)%s*(.*)$")
    if cmd == "" or cmd == "window" or cmd == "summary" then
        diag.ShowWindow("summary")
    elseif cmd == "chat" or cmd == "print" then
        diag.PrintLines(diag.BuildSummary())
    elseif cmd == "check" or cmd == "checks" then
        diag.ShowWindow("checks")
    elseif cmd == "log" then
        diag.ShowWindow("log")
        if diag.frame and rest ~= "" then diag.frame.filterBox:SetText(rest); diag.Refresh() end
    elseif cmd == "net" then
        diag.ShowWindow("net")
    elseif cmd == "err" or cmd == "errors" then
        diag.ShowWindow("errors")
    elseif cmd == "raid" or cmd == "ping" then
        diag.ShowWindow("raid")
        diag.StartRaidPing()
        diag.Refresh()
    elseif cmd == "report" or cmd == "full" then
        diag.ShowWindow("report")
    elseif cmd == "clear" then
        diag.ClearAll()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r журнал, сеть и ошибки очищены")
    elseif cmd == "debug" then
        if rest == "on" then self.debug = true elseif rest == "off" then self.debug = false else self.debug = not self.debug end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r вывод отладки в чат: "..(self.debug and "включён" or "выключен").." (журнал пишется всегда)")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r /epba diag [chat | checks | log [текст] | net | errors | raid | report | clear | debug on/off]")
    end
end

SLASH_EPBADIAG1 = "/epbadiag"
SlashCmdList["EPBADIAG"] = function(msg) auction:DiagCommand(msg) end

-- ======================
-- 10. События жизненного цикла + сохранение
-- ======================
diag.eventCounts = {}
local lastEventLog = {}
local ef = CreateFrame("Frame")
local EVENTS = {
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "RAID_ROSTER_UPDATE",
    "PARTY_MEMBERS_CHANGED", "PARTY_LOOT_METHOD_CHANGED", "PARTY_CONVERTED_TO_RAID", "LOOT_OPENED",
    "LOOT_CLOSED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}
for _, e in ipairs(EVENTS) do ef:RegisterEvent(e) end

local function SaveToSV()
    local merged, seen = {}, {}
    local function take(list)
        for _, e in ipairs(list or {}) do
            if type(e) == "table" and e.msg and not seen[e.msg] then
                seen[e.msg] = true
                merged[#merged + 1] = { msg = Trunc(e.msg, 400), stack = e.stack and Trunc(e.stack, 1200) or nil,
                    src = e.src, count = e.count, first = e.first, last = e.last, ver = e.ver }
            end
        end
    end
    take(diag.errors)
    take(diag.saved and diag.saved.errors)
    while #merged > SAVED_ERR_MAX do table.remove(merged) end

    local tail = {}
    for _, e in ipairs(RingList(diag.log, SAVED_LOG_TAIL)) do
        tail[#tail + 1] = string.format("%s [%s] %s", Clock(e[2]), e[3], Trunc(e[4], 200))
    end
    local sessions = (diag.saved and type(diag.saved.sessions) == "table") and diag.saved.sessions or {}
    local n = diag.net
    table.insert(sessions, { t = sessionStartUnix, dur = math.floor(GetTime() - sessionStart), ver = auction.version,
        errors = diag.errorTotal, out = n.outN, ["in"] = n.inN, peak10 = n.peak10, oversize = n.oversize, unknown = n.unknown })
    while #sessions > SAVED_SESSIONS do table.remove(sessions, 1) end
    EPBossAuctionSavedDiag = { saved = time(), version = auction.version, errors = merged, logTail = tail, sessions = sessions }
end

ef:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "EPBossAuction" then
            diag.saved = (type(EPBossAuctionSavedDiag) == "table") and EPBossAuctionSavedDiag or nil
            diag.Log("evt", "ADDON_LOADED, версия "..tostring(auction.version))
        end
        return
    end
    local cnt = (diag.eventCounts[event] or 0) + 1
    diag.eventCounts[event] = cnt
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        InstallErrorHook()
    end
    if event == "PLAYER_LOGOUT" then
        pcall(SaveToSV)
        return
    end
    -- частые события логируем не чаще раза в секунду, остальное — счётчиком
    local now = GetTime()
    local last = lastEventLog[event]
    if not last or now - last.t >= 1 then
        local skipped = last and last.skipped or 0
        lastEventLog[event] = { t = now, skipped = 0 }
        diag.Log("evt", event..(skipped > 0 and (" (+"..skipped.." с прошлого раза)") or ""))
    else
        last.skipped = last.skipped + 1
    end
end)
