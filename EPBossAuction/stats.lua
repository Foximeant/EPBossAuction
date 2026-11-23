local auction = EPBossAuction

-- ============================================================
-- stats.lua — статистика выдач и ЕП: данные и логика
-- ============================================================
-- Назначение: показать офицерам, кто что получил с рейдов и сколько ЕП
-- потрачено/начислено — по игрокам, по боссам и списком выдач.
--
-- Источник данных — журнал выдач EPBossAuctionDB.lootLog (его пишет окно
-- добычи, lootmaster.lua). Журнал ведёт клиент ЛМ: «Выдать» и «Списать ЕП»
-- через окно добычи. Предметы, которые забрали мимо аддона (стандартное окно
-- добычи), в журнал не попадают. У остальных офицеров журнал пока пуст
-- (синхронизации нет; см. поле id ниже — оно оставлено под неё).
--
-- Файлы статистики:
--   stats.lua     — ЭТОТ файл: доступ, журнал (добавление/очистка), подсчёт
--                   (чистые функции без WoW API, кроме date), текст отчёта;
--   stats_ui.lua  — вкладка «Статистика» главного окна, окно с текстом отчёта.
--
-- Записи журнала (список, по возрастанию времени; порядок подсчёт не требует):
--   Выдача предмета (kind = "item" или nil у старых записей):
--     { id, t, kind = "item", lm = "Имя ЛМ", boss, itemID, winner,
--       bid       = ставка победителя на момент выдачи (0 — «выдал себе» без ставки),
--       offspec   = true/false, bids = сколько ставок было на предмет,
--       charged   = true, если ЕП списан,
--       chargedAmount = сколько списано, main = с чьего мейна списано }
--   Массовое начисление ЕП рейду (кнопка «Начислить рейду»):
--     { id, t, kind = "mass", lm, boss, amount, n = число получателей или nil }
--   id — "время-случайное" (уникален, для будущей синхронизации); у записей,
--   сделанных до 3.6.0, его нет — подсчёт на него не опирается.
--
-- Что считается «потрачено»: только списанный ЕП (chargedAmount). Выданный, но
-- не списанный предмет считается выдачей без трат (в таблице помечается «*»).
-- Начисления (mass) не относятся к игрокам: ЕП получает весь список EPGP.
-- ============================================================

-- Сколько записей хранить (старые вытесняются).
auction.STATS_MAX_RECORDS = 2000
-- Сколько последних предметов игрока показывать в его тултипе.
auction.STATS_RECENT_ITEMS = 8
-- Периоды; days = 0 значит «без ограничения».
auction.STATS_PERIODS = {
    { days = 7,  label = "7 дней" },
    { days = 30, label = "30 дней" },
    { days = 90, label = "90 дней" },
    { days = 0,  label = "всё время" },
}
-- Состояние вкладки (только на время сессии).
auction.statsPeriodIndex = 2        -- индекс в STATS_PERIODS (30 дней)
auction.statsView = "players"       -- "players" | "items" | "bosses"
auction.statsBossFilter = nil       -- имя босса или nil («Все боссы»)
-- Растёт при любом изменении журнала (задел под кэши).
auction.statsRevision = 0

-- ======================
-- 1. Доступ и настройки
-- ======================

-- Вкладку видят те же, кто видит Attendance и Резерв (правило доступа — в
-- одном месте, attendance.lua:CanRecordAttendance). Хотите другое — правьте здесь.
function auction:HasStatsAccess()
    return self:HasAttendanceAccess()
end

-- Учёт по мейнам (чекбокс «По мейнам» на вкладке; по умолчанию да).
function auction:IsStatsByMain()
    local cfg = self.db and self.db.stats
    if cfg and cfg.byMain ~= nil then return cfg.byMain and true or false end
    return true
end

-- Функция «имя → мейн» для подсчёта по мейнам. Сначала смотрит мейна, записанного
-- при списании (rec.main), потом спрашивает EPGP-аддон (GetMainName, с кэшем).
-- Возвращает nil, если игрок не твинк.
function auction:GetStatsResolver()
    local cache = {}
    return function(name, rec)
        if rec and rec.main and rec.winner == name then
            if rec.main ~= name then return rec.main end
            return nil
        end
        local live = cache[name]
        if live == nil then
            live = self:GetMainName(name) or false
            cache[name] = live
        end
        return live or nil
    end
end

-- ======================
-- 2. Журнал
-- ======================

-- Таблица журнала (создаётся, если её нет).
function auction:GetLootLog()
    local db = self:GetDB()
    if type(db.lootLog) ~= "table" then db.lootLog = {} end
    return db.lootLog
end

-- Уникальный id записи: время и 16 бит случайности.
function auction:NewLootLogID()
    return string.format("%x-%04x", time(), math.random(0, 0xFFFF))
end

-- Что-то изменилось в журнале: обновляем вкладку (если открыта).
function auction:StatsChanged()
    self.statsRevision = (self.statsRevision or 0) + 1
    if self.RefreshStats then self:RefreshStats() end
end

-- Добавляет запись в конец журнала (проставляет id и ЛМ), обрезает до
-- STATS_MAX_RECORDS. Возвращает саму запись.
function auction:StatsAddRecord(rec)
    local log = self:GetLootLog()
    rec.id = rec.id or self:NewLootLogID()
    rec.lm = rec.lm or UnitName("player")
    log[#log + 1] = rec
    while #log > self.STATS_MAX_RECORDS do table.remove(log, 1) end
    self:StatsChanged()
    return rec
end

-- Массовое начисление ЕП рейду (зовёт lootmaster.lua после успешного IncMassEPBy).
-- Тестовый режим окна добычи в журнал не пишет.
function auction:LootJournalAddMass(boss, amount, n)
    if self.lootTest then return end
    self:StatsAddRecord({
        kind = "mass", t = time(), boss = boss,
        amount = tonumber(amount) or 0, n = tonumber(n),
    })
end

-- Полная очистка журнала на этом клиенте.
function auction:ClearLootLog()
    self:GetDB().lootLog = {}
    self:StatsChanged()
    self:AttendanceSay("Статистика: журнал выдач очищен")
end

-- Подтверждение очистки.
function auction:ConfirmClearLootLog()
    local n = #self:GetLootLog()
    StaticPopupDialogs["EPBA_CLEAR_LOOTLOG"] = {
        text = "Удалить журнал выдач на этом клиенте ("..n.." зап.)?\nСтатистика по ним пропадёт, вернуть её нельзя.",
        button1 = "Удалить", button2 = "Отмена",
        OnAccept = function() auction:ClearLootLog() end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    StaticPopup_Show("EPBA_CLEAR_LOOTLOG")
end

-- ======================
-- 3. Подсчёт (чистые функции — проверяются тестами вне игры)
-- ======================

local function IsMass(rec) return rec.kind == "mass" end

-- Записи за период (days <= 0 или nil — без ограничения) и по боссу (nil — все).
-- Пропускает мусор: не таблицы и записи без числового времени.
local function Filter(records, now, periodDays, bossFilter)
    local out = {}
    local cutoff = (periodDays and periodDays > 0) and (now - periodDays * 86400) or nil
    for _, r in ipairs(records or {}) do
        if type(r) == "table" and tonumber(r.t)
            and (not cutoff or r.t >= cutoff)
            and (not bossFilter or r.boss == bossFilter) then
            out[#out + 1] = r
        end
    end
    return out
end

-- Боссы, у которых есть записи за период, с числом записей — для фильтра «Босс».
-- Порядок как в аддоне (auction.bossOrder), неизвестные — в конце по алфавиту.
function auction:BuildStatsBossList(records, now, periodDays)
    local counts = {}
    for _, r in ipairs(Filter(records, now, periodDays, nil)) do
        if r.boss then counts[r.boss] = (counts[r.boss] or 0) + 1 end
    end
    local list = {}
    for boss, count in pairs(counts) do list[#list + 1] = { boss = boss, count = count } end
    local index = {}
    for i, boss in ipairs(self.bossOrder or {}) do index[boss] = i end
    table.sort(list, function(a, b)
        local ia, ib = index[a.boss] or 9999, index[b.boss] or 9999
        if ia ~= ib then return ia < ib end
        return a.boss < b.boss
    end)
    return list
end

-- Итоги за период (и по боссу): выдач, потрачено, выдач без списания, начислено
-- рейду (и сколько было начислений), уникальных получателей (по именам персонажей).
function auction:BuildStatsTotals(records, now, periodDays, bossFilter)
    local t = { items = 0, spent = 0, uncharged = 0, awarded = 0, awards = 0, winners = 0 }
    local seen = {}
    for _, r in ipairs(Filter(records, now, periodDays, bossFilter)) do
        if IsMass(r) then
            t.awards = t.awards + 1
            t.awarded = t.awarded + (tonumber(r.amount) or 0)
        elseif r.winner then
            t.items = t.items + 1
            if r.charged then
                t.spent = t.spent + (tonumber(r.chargedAmount) or 0)
            else
                t.uncharged = t.uncharged + 1
            end
            if not seen[r.winner] then
                seen[r.winner] = true
                t.winners = t.winners + 1
            end
        end
    end
    return t
end

-- Вид «Игроки»: по каждому получателю — предметов, потрачено ЕП, средняя ставка,
-- сколько на офф-спек, сколько выдач без списания, последняя выдача, последние
-- предметы. resolveMain(имя, запись) → имя мейна или nil: твинк считается вместе
-- с мейном (entry.chars — какими персонажами получено).
-- Возвращает { entries = {...}, totals = {...} }; entries по убыванию потраченного ЕП.
function auction:BuildStatsPlayers(records, now, periodDays, bossFilter, resolveMain)
    local byKey, list = {}, {}
    for _, r in ipairs(Filter(records, now, periodDays, bossFilter)) do
        if not IsMass(r) and r.winner then
            local main = resolveMain and resolveMain(r.winner, r) or nil
            local key = main or r.winner
            local e = byKey[key]
            if not e then
                e = { name = key, items = 0, spent = 0, offspec = 0, uncharged = 0,
                      bidSum = 0, bidCount = 0, last = 0, chars = {}, recent = {} }
                byKey[key] = e
                list[#list + 1] = e
            end
            e.items = e.items + 1
            if r.winner ~= key then e.chars[r.winner] = true end
            local bid = tonumber(r.bid) or 0
            if bid > 0 then
                e.bidSum = e.bidSum + bid
                e.bidCount = e.bidCount + 1
            end
            if r.offspec then e.offspec = e.offspec + 1 end
            if r.charged then
                e.spent = e.spent + (tonumber(r.chargedAmount) or 0)
            else
                e.uncharged = e.uncharged + 1
            end
            if r.t > e.last then e.last = r.t end
            e.recent[#e.recent + 1] = { t = r.t, itemID = r.itemID, bid = bid, boss = r.boss }
        end
    end

    for _, e in ipairs(list) do
        e.avgBid = e.bidCount > 0 and math.floor(e.bidSum / e.bidCount + 0.5) or nil
        local chars = {}
        for name in pairs(e.chars) do chars[#chars + 1] = name end
        table.sort(chars)
        e.charList = chars
        table.sort(e.recent, function(a, b) return a.t > b.t end)
        while #e.recent > (auction.STATS_RECENT_ITEMS or 8) do table.remove(e.recent) end
    end
    table.sort(list, function(a, b)
        if a.spent ~= b.spent then return a.spent > b.spent end
        if a.items ~= b.items then return a.items > b.items end
        return a.name < b.name
    end)

    return { entries = list, totals = self:BuildStatsTotals(records, now, periodDays, bossFilter) }
end

-- Вид «Боссы»: по каждому боссу — выдач, потрачено, начислено рейду (и сколько
-- раз), уникальных получателей (по мейнам, если resolveMain), последняя запись.
-- Сначала недавние.
function auction:BuildStatsBosses(records, now, periodDays, resolveMain)
    local byBoss, list = {}, {}
    for _, r in ipairs(Filter(records, now, periodDays, nil)) do
        if r.boss then
            local e = byBoss[r.boss]
            if not e then
                e = { boss = r.boss, drops = 0, spent = 0, uncharged = 0,
                      awards = 0, awarded = 0, players = {}, last = 0 }
                byBoss[r.boss] = e
                list[#list + 1] = e
            end
            if IsMass(r) then
                e.awards = e.awards + 1
                e.awarded = e.awarded + (tonumber(r.amount) or 0)
            elseif r.winner then
                e.drops = e.drops + 1
                if r.charged then
                    e.spent = e.spent + (tonumber(r.chargedAmount) or 0)
                else
                    e.uncharged = e.uncharged + 1
                end
                local main = resolveMain and resolveMain(r.winner, r) or nil
                e.players[main or r.winner] = true
            end
            if r.t > e.last then e.last = r.t end
        end
    end
    for _, e in ipairs(list) do
        local n = 0
        for _ in pairs(e.players) do n = n + 1 end
        e.uniquePlayers = n
    end
    table.sort(list, function(a, b)
        if a.last ~= b.last then return a.last > b.last end
        return a.boss < b.boss
    end)
    return list
end

-- Вид «Выдачи»: список выдач, сначала новые. Массовые начисления не входят.
function auction:BuildStatsItems(records, now, periodDays, bossFilter, resolveMain)
    local list = {}
    for i, r in ipairs(Filter(records, now, periodDays, bossFilter)) do
        if not IsMass(r) and r.winner then
            list[#list + 1] = {
                seq = i, t = r.t, boss = r.boss, itemID = r.itemID, winner = r.winner,
                main = resolveMain and resolveMain(r.winner, r) or nil,
                bid = tonumber(r.bid) or 0, offspec = r.offspec and true or false,
                bids = tonumber(r.bids) or 0, charged = r.charged and true or false,
                spent = r.charged and (tonumber(r.chargedAmount) or 0) or nil,
                lm = r.lm,
            }
        end
    end
    table.sort(list, function(a, b)
        if a.t ~= b.t then return a.t > b.t end
        return a.seq > b.seq
    end)
    return list
end

-- ======================
-- 4. Текст отчёта
-- ======================

-- ";" в названиях ломает CSV — заменяем.
local function Cell(s)
    return (tostring(s or ""):gsub(";", ","))
end

-- Отчёт в формате CSV с разделителем ";" под текущий вид вкладки.
--   view — "players" | "items" | "bosses";
--   data — результат BuildStatsPlayers (берётся .entries) / BuildStatsItems / BuildStatsBosses;
--   info — { periodLabel, bossFilter, byMain, itemName = function(itemID) → имя }.
function auction:BuildStatsReportText(view, data, info)
    info = info or {}
    local function ItemName(id)
        local name = info.itemName and info.itemName(id)
        return Cell(name or ("item:"..tostring(id)))
    end
    local lines = {}
    local head = "Статистика выдач — период: "..(info.periodLabel or "?")
    if info.bossFilter and view ~= "bosses" then head = head.."; босс: "..info.bossFilter end
    head = head.."; по мейнам: "..(info.byMain and "да" or "нет")
    lines[#lines + 1] = head

    if view == "players" then
        lines[#lines + 1] = "Игрок;Предметов;ЕП списано;Ср. ставка;Офф-спек;Без списания;Последняя выдача"
        for _, e in ipairs(data.entries) do
            lines[#lines + 1] = table.concat({
                Cell(e.name), e.items, e.spent, e.avgBid or "", e.offspec, e.uncharged,
                date("%d.%m.%Y", e.last),
            }, ";")
        end
    elseif view == "items" then
        lines[#lines + 1] = "Дата;Босс;Предмет;Победитель;Мейн;Ставка;Офф-спек;Списано"
        for _, e in ipairs(data) do
            lines[#lines + 1] = table.concat({
                date("%d.%m.%Y %H:%M", e.t), Cell(e.boss), ItemName(e.itemID), Cell(e.winner),
                Cell(e.main), e.bid, e.offspec and "да" or "", e.spent or "",
            }, ";")
        end
    else
        lines[#lines + 1] = "Босс;Выдач;ЕП списано;Начислено рейду;Начислений;Игроков;Последняя запись"
        for _, e in ipairs(data) do
            lines[#lines + 1] = table.concat({
                Cell(e.boss), e.drops, e.spent, e.awarded, e.awards, e.uniquePlayers,
                date("%d.%m.%Y", e.last),
            }, ";")
        end
    end
    return table.concat(lines, "\n")
end
