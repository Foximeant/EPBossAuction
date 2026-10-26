local auction = EPBossAuction

-- ============================================================
-- attendance.lua — посещаемость рейдов: данные и логика
-- ============================================================
-- Назначение: показать офицерам (тем, кто может редактировать офицерскую заметку), кто из игроков бывал на убийствах
-- боссов и какой процент киллов за выбранный период посетил каждый.
--
-- Файлы Attendance:
--   attendance.lua       — ЭТОТ файл: доступ, запись, удаление/очистка, слияние,
--                          подсчёт (чистые функции без WoW API), текст отчёта;
--   attendance_sync.lua  — синхронизация истории между офицерами (сеть);
--   attendance_ui.lua    — вкладки главного окна, панель, окно с текстом отчёта.
--
-- Откуда берутся данные (так решено для тестов):
--   • запись ("снимок") делается при ПКМ по "Очистить таблицу" (очистка одного
--     босса) — это момент "босс убит, лут роздан". После подтверждения очистки ЛМ
--     каждый раз спрашивают, записывать ли килл (ClearBossWithAttendanceChoice);
--     ответ "не записывать" действует и на офицеров (сообщение ATT_SKIP). ЛКМ
--     (очистка всех боссов) посещаемость не пишет. Если килл не сопровождался
--     очисткой (например, с босса ничего не упало), его можно записать вручную
--     кнопкой "Записать килл".
--   • в снимок попадает: время, босс, подземелье, все, кто сейчас в рейд-группе
--     (имя → класс), те из них, кто отмечен в явке на этого босса как "Хочу
--     отдохнуть", и мейны твинков (если стоит EPGP-аддон, см. GetMainName в epgp.lua).
--   • вкладку видит и посещаемость записывает только тот, кто может РЕДАКТИРОВАТЬ
--     офицерскую заметку гильдии (см. CanRecordAttendance — единственное место
--     правила), каждый на своём клиенте: сообщение END приходит всему рейду,
--     поэтому такой офицер получает те же события, что и ЛМ. Пропуски в истории
--     (офицера не было в рейде) закрывает синхронизация (attendance_sync.lua).
--   • остальные ничего не хранят и вкладку не видят.
--
-- Структура одной записи (auction.attendance — список, по возрастанию времени):
--   { t = <unix-время>, boss = "Имя босса" (у записей до 3.2.1 мог быть nil),
--     instance = "Подземелье" или nil,
--     players = { ["Имя"] = "CLASSTOKEN", ... },
--     rested  = { ["Имя"] = true, ... },          -- подмножество players
--     mains   = { ["Твинк"] = "Мейн", ... },       -- необязательно
--     manual  = true }                             -- необязательно: записано вручную
--
-- Хранится в SavedVariables: EPBossAuctionSavedAttendance (список) и
-- EPBossAuctionSavedAttendanceMeta (метки удаления для синхронизации, см.
-- attendanceMeta ниже). events.lua грузит, core.lua:SaveData сохраняет.
-- ============================================================

-- Сколько последних записей хранить (старые вытесняются).
auction.ATTENDANCE_MAX_RECORDS = 600
-- Сколько последних киллов показывать колонками-датами в таблице игроков.
auction.ATTENDANCE_COLUMNS = 10
-- Две записи по одному боссу ближе друг к другу, чем это число секунд, считаются
-- ОДНИМ киллом: так отсекаются дубли (эхо собственного END у ЛМ, повторный клик,
-- запись того же килла, пришедшая по синхронизации от другого офицера).
auction.ATTENDANCE_SAME_KILL_SECONDS = 300
-- За сколько дней считать процент посещаемости в тултипе ставок.
auction.ATTENDANCE_TOOLTIP_DAYS = 30
-- Периоды для процента посещаемости; days = 0 значит "без ограничения".
auction.ATTENDANCE_PERIODS = {
    { days = 7,  label = "7 дней" },
    { days = 30, label = "30 дней" },
    { days = 0,  label = "всё время" },
}
-- Состояние вкладки (только на время сессии): период, вид и фильтр по боссу.
auction.attendancePeriodIndex = 2           -- индекс в ATTENDANCE_PERIODS (30 дней)
auction.attendanceView = "players"          -- "players" | "bosses" | "days"
auction.attendanceBossFilter = nil          -- имя босса или nil ("Все боссы")

-- Сами записи; events.lua при загрузке заменяет на сохранённые.
auction.attendance = auction.attendance or {}
-- Метки для синхронизации: удалённое/очищенное не должно вернуться от других офицеров.
--   clearedBefore — момент "Очистить" (записи с t <= этого значения игнорируются);
--   deleted       — список { boss, t } удалённых вручную записей (не больше 200).
auction.attendanceMeta = auction.attendanceMeta or { clearedBefore = 0, deleted = {} }
-- Растёт при любом изменении истории: по нему сбрасывается кэш процентов для тултипа ставок.
auction.attendanceRevision = 0

-- ======================
-- Вспомогательное
-- ======================

-- Обрезает строку до первых n символов с учётом UTF-8 (кириллица — 2 байта на
-- символ, обычный string.sub порвал бы символ посередине).
local function Utf8Prefix(s, n)
    local i, count, len = 1, 0, #s
    while i <= len and count < n do
        local c = s:byte(i)
        if c < 0x80 then i = i + 1
        elseif c < 0xE0 then i = i + 2
        elseif c < 0xF0 then i = i + 3
        else i = i + 4 end
        count = count + 1
    end
    return s:sub(1, i - 1)
end
auction.Utf8Prefix = Utf8Prefix

-- Имя без суффикса "-Реалм" (на случай, если клиент когда-нибудь начнёт его добавлять).
local function StripRealm(name)
    return name and name:match("^[^-]+") or name
end
auction.StripRealm = StripRealm

-- Локализованное название класса по токену (для текстового отчёта); без локализации — сам токен.
local function ClassLabel(class)
    local names = LOCALIZED_CLASS_NAMES_MALE
    if type(names) == "table" and names[class] then return names[class] end
    return class or ""
end

-- Сообщение игроку в чат (одинаковый стиль для всех сообщений Attendance).
function auction:AttendanceSay(text, isError)
    local color = isError and "|cffff9900" or "|cff00ff00"
    DEFAULT_CHAT_FRAME:AddMessage(color.."[EPBA]|r "..text)
end

-- ======================
-- 1. Доступ
-- ======================

-- Единое правило доступа к Attendance: вкладку видит, посещаемость записывает и
-- на запросы синхронизации отвечает только тот, кто может РЕДАКТИРОВАТЬ
-- офицерскую заметку в гильдии (CanEditOfficerNote). Это не зависит от того, в
-- рейде ли игрок и ЛМ ли он, поэтому история доступна и вне рейда. Хотите другое
-- правило — правьте только эту функцию.
function auction:CanRecordAttendance()
    return (IsInGuild and IsInGuild() and CanEditOfficerNote and CanEditOfficerNote()) and true or false
end

-- Показывать ли вкладку Attendance — то же правило (отдельное имя оставлено для
-- читаемости мест, где речь о просмотре, а не о записи).
function auction:HasAttendanceAccess()
    return self:CanRecordAttendance()
end

-- Включён ли учёт по мейнам (чекбокс "По мейнам" на вкладке; по умолчанию да).
function auction:IsAttendanceByMain()
    local cfg = self.db and self.db.attendance
    if cfg and cfg.byMain ~= nil then return cfg.byMain and true or false end
    return true
end

-- Функция "имя персонажа → имя мейна" для подсчёта по мейнам. Сначала смотрит
-- мейна, сохранённого в самой записи (rec.mains), потом спрашивает EPGP-аддон
-- (GetMainName, с кэшем) — так считаются и старые записи, и записи, пришедшие
-- по синхронизации от офицера без EPGP. Возвращает nil, если это не твинк.
function auction:GetAttendanceResolver()
    local cache = {}
    return function(name, rec)
        local saved = rec and rec.mains and rec.mains[name]
        if saved then return saved end
        local live = cache[name]
        if live == nil then
            live = self:GetMainName(name) or false
            cache[name] = live
        end
        return live or nil
    end
end

-- ======================
-- 2. Запись, удаление, очистка
-- ======================

-- Что произошло с историей: учитываем изменение (кэш процентов, сохранение,
-- вкладки, перерисовка). Вызывается после любого добавления/удаления/слияния.
function auction:AttendanceChanged()
    self.attendanceRevision = (self.attendanceRevision or 0) + 1
    self:RequestSaveData()
    if self.UpdateMainTabs then self:UpdateMainTabs() end
    if self.RefreshAttendance then self:RefreshAttendance() end
end

-- Вставляет запись в список с сохранением порядка по времени и обрезает историю
-- до ATTENDANCE_MAX_RECORDS. Уведомления (AttendanceChanged) — на вызывающем.
function auction:InsertAttendanceRecord(rec)
    self.attendance = self.attendance or {}
    local list = self.attendance
    local pos = #list + 1
    while pos > 1 and list[pos - 1].t > rec.t do pos = pos - 1 end
    table.insert(list, pos, rec)
    while #list > self.ATTENDANCE_MAX_RECORDS do
        table.remove(list, 1)
    end
end

-- Есть ли уже запись того же килла (тот же босс, время в пределах
-- ATTENDANCE_SAME_KILL_SECONDS). Возвращает найденную запись или nil.
function auction:FindAttendanceDuplicate(boss, t)
    for _, rec in ipairs(self.attendance or {}) do
        if rec.boss == boss and math.abs(rec.t - t) <= self.ATTENDANCE_SAME_KILL_SECONDS then
            return rec
        end
    end
    return nil
end

-- Делает снимок текущего рейда и добавляет запись. manual = true для записи
-- вручную (кнопка на вкладке). Возвращает true и число игроков в рейде либо
-- false и причину: "not_raid", "no_boss", "duplicate", "no_roster".
function auction:AddAttendanceRecord(bossName, manual)
    if not IsInRaid() then return false, "not_raid" end
    if not bossName or not self.bosses[bossName] then return false, "no_boss" end

    local now = time()
    if self:FindAttendanceDuplicate(bossName, now) then return false, "duplicate" end

    local players, mains, count = {}, {}, 0
    for i = 1, GetNumRaidMembers() do
        local name, _, _, _, _, class = GetRaidRosterInfo(i)
        if name then
            players[name] = class or "UNKNOWN"
            count = count + 1
            local main = self:GetMainName(name)
            if main then mains[name] = main end
        end
    end
    if count == 0 then return false, "no_roster" end

    local rested = {}
    for name in pairs(self:GetSignupSet(bossName, "rest")) do
        if players[name] then rested[name] = true end
    end

    local rec = {
        t = now,
        boss = bossName,
        instance = self.bossToInstance[bossName],
        players = players,
        rested = rested,
    }
    if next(mains) then rec.mains = mains end
    if manual then rec.manual = true end

    self:InsertAttendanceRecord(rec)
    self:AttendanceChanged()
    return true, count
end

-- Автоматическая запись при ПКМ-очистке одного босса. Вызывается:
--   • у ЛМ — из EndAuctionLocal (ui.lua), ДО очистки явки;
--   • у остальных — из Handle_END (comm.lua), с sender = отправитель.
-- bossName — очищаемый босс; обязателен. sender — только для сетевого пути:
-- принимаем событие лишь от текущего ЛМ (self.lastLM) или от себя, чтобы
-- посторонний сообщением END не мог засорить историю.
function auction:RecordAttendance(bossName, sender)
    if not self:CanRecordAttendance() then return false end

    local me = UnitName("player")
    if sender and StripRealm(sender) ~= me and StripRealm(sender) ~= StripRealm(self.lastLM) then
        self:Debug("Attendance: сообщение от "..tostring(sender).." не от ЛМ, пропускаю")
        return false
    end

    -- ЛМ ответил "не записывать" (ATT_SKIP перед END, у самого ЛМ — SkipNextAttendance):
    -- решение действует 15 секунд и расходуется первой же попыткой записи этого босса
    local skip = self.attSkip
    if skip and skip.boss == bossName then
        self.attSkip = nil
        if GetTime() - skip.t < 15 then
            self:Debug("Attendance: ЛМ решил не записывать килл "..tostring(bossName))
            return false
        end
    end

    local ok, info = self:AddAttendanceRecord(bossName, false)
    self:Debug("Attendance: "..(ok and ("записан килл "..tostring(bossName)) or ("не записано: "..tostring(info))))
    return ok
end

-- Запоминает решение ЛМ "килл не записывать" для ближайшего END по этому боссу:
-- у себя (иначе эхо собственного END всё равно записало бы килл) и у офицеров
-- (сообщение ATT_SKIP, его нужно отправить ПЕРЕД END).
function auction:SkipNextAttendance(bossName)
    self.attSkip = { boss = bossName, t = GetTime() }
    SendAddonMessage(self.prefix, "ATT_SKIP;"..bossName, "RAID")
end

-- ATT_SKIP от ЛМ: запоминаем, что ближайшую запись этого босса делать не нужно.
-- Принимаем только от текущего ЛМ (или от себя).
function auction:Handle_ATT_SKIP(rest, sender)
    local me = UnitName("player")
    if StripRealm(sender) ~= me and StripRealm(sender) ~= StripRealm(self.lastLM) then return end
    self.attSkip = { boss = rest, t = GetTime() }
end

-- ПКМ "Очистить таблицу", шаг 2 (после подтверждения самой очистки): если мы в
-- рейде и можем записывать посещаемость — спрашивает, делать ли снимок рейда по
-- этому килле. "Записать" — снимок и очистка; "Не записывать" или Esc — очистка
-- без снимка (саму очистку ЛМ уже подтвердил). Очистку выполняет FinishBossClear (ui.lua).
function auction:ClearBossWithAttendanceChoice(bossName)
    if not (IsInRaid() and self:CanRecordAttendance()) then
        self:FinishBossClear(bossName, nil)
        return
    end
    StaticPopupDialogs["EPBA_ATTENDANCE_SNAPSHOT"] = {
        text = "Записать килл «"..bossName.."» в Attendance?\nВ рейде сейчас: "..GetNumRaidMembers().." чел.\n\n«Не записывать» или Esc — очистить ставки без записи.",
        button1 = "Записать", button2 = "Не записывать",
        OnAccept = function() auction:FinishBossClear(bossName, true) end,
        OnCancel = function() auction:FinishBossClear(bossName, false) end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    StaticPopup_Show("EPBA_ATTENDANCE_SNAPSHOT")
end

-- Ручная запись килла (кнопка "Записать килл" на вкладке): тот же снимок, но по
-- явному выбору босса, с сообщением о результате.
function auction:RecordAttendanceManual(bossName)
    if not self:CanRecordAttendance() then
        self:AttendanceSay("Attendance: записывать посещаемость могут только те, кто может редактировать офицерскую заметку", true)
        return false
    end
    local ok, info = self:AddAttendanceRecord(bossName, true)
    if ok then
        self:AttendanceSay("Attendance: записан килл «"..bossName.."» (в рейде: "..info..")")
    elseif info == "not_raid" then
        self:AttendanceSay("Attendance: вы не в рейде — записывать нечего", true)
    elseif info == "duplicate" then
        self:AttendanceSay("Attendance: килл «"..bossName.."» уже записан за последние "..math.floor(self.ATTENDANCE_SAME_KILL_SECONDS / 60).." мин.", true)
    elseif info == "no_roster" then
        self:AttendanceSay("Attendance: не удалось получить состав рейда", true)
    else
        self:AttendanceSay("Attendance: неизвестный босс", true)
    end
    return ok
end

-- Удаляет одну запись (ПКМ по дате в таблице) — на случай, если очистили
-- не после килла, а по ошибке. Запоминает метку удаления, чтобы синхронизация
-- не вернула запись от другого офицера.
function auction:DeleteAttendanceRecord(rec)
    for i, r in ipairs(self.attendance) do
        if r == rec then
            table.remove(self.attendance, i)
            break
        end
    end
    if rec.boss then
        local meta = self.attendanceMeta
        table.insert(meta.deleted, { boss = rec.boss, t = rec.t })
        while #meta.deleted > 200 do table.remove(meta.deleted, 1) end
    end
    self:AttendanceChanged()
end

-- Полностью очищает историю на ЭТОМ клиенте (кнопка "Очистить" на вкладке).
-- Всё, что старше момента очистки, синхронизация больше не принимает; копии
-- у других офицеров не затрагиваются.
function auction:ClearAttendance()
    self.attendance = {}
    self.attendanceMeta = { clearedBefore = time(), deleted = {} }
    self:AttendanceChanged()
end

-- Подтверждение очистки всей истории (StaticPopup, как и остальные подтверждения).
function auction:ConfirmClearAttendance()
    local count = #(self.attendance or {})
    if count == 0 then return end
    StaticPopupDialogs["EPBA_CLEAR_ATTENDANCE"] = {
        text = "Удалить ВСЮ историю посещаемости (записей: "..count..")?\nЭто нельзя отменить.",
        button1 = "Удалить", button2 = "Отмена",
        OnAccept = function() auction:ClearAttendance() end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    StaticPopup_Show("EPBA_CLEAR_ATTENDANCE")
end

-- ======================
-- 3. Слияние записей (для синхронизации)
-- ======================

-- Удалена ли запись такого килла вручную или очисткой истории (метки в attendanceMeta).
function auction:IsAttendanceTombstoned(boss, t)
    local meta = self.attendanceMeta
    if t <= (meta.clearedBefore or 0) then return true end
    for _, d in ipairs(meta.deleted) do
        if d.boss == boss and math.abs(d.t - t) <= self.ATTENDANCE_SAME_KILL_SECONDS then
            return true
        end
    end
    return false
end

-- Добавляет запись, пришедшую от другого офицера. Возвращает "added", "duplicate"
-- (такой килл уже есть — у нашей записи лишь дополняются мейны, если их не было),
-- "tombstoned" (мы это удаляли/очищали) или "invalid". noNotify = true — не
-- обновлять интерфейс и не сохранять (синхронизация делает это один раз в конце).
function auction:MergeAttendanceRecord(rec, noNotify)
    if type(rec) ~= "table" or type(rec.t) ~= "number" or not rec.boss
       or not self.bosses[rec.boss] or type(rec.players) ~= "table" then
        return "invalid"
    end
    if self:IsAttendanceTombstoned(rec.boss, rec.t) then return "tombstoned" end

    local existing = self:FindAttendanceDuplicate(rec.boss, rec.t)
    if existing then
        if not existing.mains and rec.mains then
            existing.mains = rec.mains
            if not noNotify then self:AttendanceChanged() end
        end
        return "duplicate"
    end

    self:InsertAttendanceRecord(rec)
    if not noNotify then self:AttendanceChanged() end
    return "added"
end

-- ======================
-- 4. Подсчёт (чистые функции, без WoW API кроме date)
-- ======================

-- Порядок боссов как в аддоне: по подземельям (instanceOrder), внутри — по
-- порядку в подземелье. Возвращает таблицу boss → номер (неизвестные боссы без номера).
local function BossOrderIndex(self)
    local orderIndex, n = {}, 0
    for _, instanceName in ipairs(self.instanceOrder or {}) do
        for _, bossName in ipairs((self.instances or {})[instanceName] or {}) do
            n = n + 1
            orderIndex[bossName] = n
        end
    end
    return orderIndex
end

-- Сортировка по порядку боссов; неизвестные — в конце по алфавиту.
local function SortByBossOrder(list, orderIndex, bossField)
    table.sort(list, function(a, b)
        local ia, ib = orderIndex[a[bossField]], orderIndex[b[bossField]]
        if ia and ib then return ia < ib end
        if ia then return true end
        if ib then return false end
        return a[bossField] < b[bossField]
    end)
end

-- Кто (по "личностям") был на одном килле. resolveMain необязателен: если задан,
-- твинк и мейн в одном килле считаются ОДНИМ человеком. Возвращает таблицу
-- личность → { class, active, chars }, где active = false, если все персонажи
-- этой личности отмечены "Хочу отдохнуть".
local function ResolveIdentities(rec, resolveMain)
    local seen = {}
    for name, class in pairs(rec.players) do
        local id = name
        if resolveMain then
            local main = resolveMain(name, rec)
            if main and main ~= "" then id = main end
        end
        local slot = seen[id]
        if not slot then
            slot = { class = class, active = false, chars = {} }
            seen[id] = slot
        end
        if name == id then slot.class = class end    -- класс мейна приоритетнее класса твинка
        if not (rec.rested and rec.rested[name]) then slot.active = true end
        slot.chars[name] = true
    end
    return seen
end

-- Записи за период (и по боссу, если задан bossFilter), по возрастанию времени.
local function FilterRecords(records, now, periodDays, bossFilter)
    local cutoff = (periodDays and periodDays > 0) and (now - periodDays * 86400) or nil
    local list = {}
    for _, rec in ipairs(records) do
        if (not cutoff or rec.t >= cutoff) and (not bossFilter or rec.boss == bossFilter) then
            list[#list + 1] = rec
        end
    end
    table.sort(list, function(a, b) return a.t < b.t end)
    return list
end

-- Считает отчёт по игрокам.
--   records     — записи (как в auction.attendance);
--   now         — текущее время (unix);
--   periodDays  — период в днях, 0/nil = все записи;
--   maxColumns  — сколько последних киллов вывести колонками;
--   bossFilter  — необязательно: учитывать только киллы этого босса;
--   resolveMain — необязательно: функция (имя, запись) → мейн или nil; если
--                 задана, твинки считаются вместе со своим мейном.
-- Возвращает { total = число киллов за период, columns = последние записи
-- (по возрастанию времени, не больше maxColumns), players = список игроков }.
-- У каждого игрока: name (при подсчёте по мейнам — имя мейна), class, attended
-- (в скольких киллах был в рейде), rested (из них отмечен "хочу отдохнуть"),
-- total, pct (0..100, округлено), cells[i] = "P" (в рейде) / "R" (в рейде, но
-- "хочу отдохнуть") / nil (не было) для i-й колонки, charList — список
-- персонажей, если их больше одного. Процент считается по КИЛЛАМ, а не по дням:
-- опоздавший или ушедший раньше не получает "полный день".
function auction:BuildAttendanceReport(records, now, periodDays, maxColumns, bossFilter, resolveMain)
    local inPeriod = FilterRecords(records, now, periodDays, bossFilter)

    local total = #inPeriod
    local firstColumn = math.max(1, total - maxColumns + 1)
    local columns = {}
    for i = firstColumn, total do
        columns[#columns + 1] = inPeriod[i]
    end

    local byName = {}
    for index, rec in ipairs(inPeriod) do
        for id, slot in pairs(ResolveIdentities(rec, resolveMain)) do
            local entry = byName[id]
            if not entry then
                entry = { name = id, class = slot.class, attended = 0, rested = 0, cells = {}, chars = {} }
                byName[id] = entry
            end
            if not entry.mainSeen then entry.class = slot.class end
            if slot.chars[id] then entry.mainSeen = true; entry.class = slot.class end
            entry.attended = entry.attended + 1
            if not slot.active then entry.rested = entry.rested + 1 end
            for charName in pairs(slot.chars) do entry.chars[charName] = true end
            if index >= firstColumn then
                entry.cells[index - firstColumn + 1] = slot.active and "P" or "R"
            end
        end
    end

    local players = {}
    for _, entry in pairs(byName) do
        entry.total = total
        entry.pct = total > 0 and math.floor(entry.attended * 100 / total + 0.5) or 0
        local names = {}
        for charName in pairs(entry.chars) do names[#names + 1] = charName end
        if #names > 1 or (names[1] and names[1] ~= entry.name) then
            table.sort(names)
            entry.charList = names
        end
        entry.chars = nil
        entry.mainSeen = nil
        players[#players + 1] = entry
    end
    table.sort(players, function(a, b)
        if a.pct ~= b.pct then return a.pct > b.pct end
        if a.attended ~= b.attended then return a.attended > b.attended end
        return a.name < b.name
    end)

    return { total = total, columns = columns, players = players }
end

-- Боссы для выпадающего списка фильтра: те, у кого есть хотя бы один килл за
-- период (periodDays, 0/nil = всё время). Возвращает список { boss, count },
-- упорядоченный как в аддоне; неизвестные боссы идут в конце по алфавиту.
-- Записи без босса (старые) в список не попадают.
function auction:BuildAttendanceBossList(records, now, periodDays)
    local cutoff = (periodDays and periodDays > 0) and (now - periodDays * 86400) or nil

    local counts = {}
    for _, rec in ipairs(records) do
        if rec.boss and (not cutoff or rec.t >= cutoff) then
            counts[rec.boss] = (counts[rec.boss] or 0) + 1
        end
    end

    local list = {}
    for boss, count in pairs(counts) do
        list[#list + 1] = { boss = boss, count = count }
    end
    SortByBossOrder(list, BossOrderIndex(self), "boss")
    return list
end

-- Сводка по боссам: для каждого босса число киллов, средний состав рейда
-- (уникальных игроков на килл, одна цифра после запятой), число уникальных
-- игроков за период и время последнего килла. Фильтр по боссу не применяется.
-- Возвращает список { boss, kills, avgPlayers, uniquePlayers, lastT }.
function auction:BuildBossSummary(records, now, periodDays, resolveMain)
    local byBoss = {}
    for _, rec in ipairs(FilterRecords(records, now, periodDays, nil)) do
        if rec.boss then
            local entry = byBoss[rec.boss]
            if not entry then
                entry = { boss = rec.boss, kills = 0, sum = 0, unique = {}, lastT = 0 }
                byBoss[rec.boss] = entry
            end
            local count = 0
            for id in pairs(ResolveIdentities(rec, resolveMain)) do
                count = count + 1
                entry.unique[id] = true
            end
            entry.kills = entry.kills + 1
            entry.sum = entry.sum + count
            if rec.t > entry.lastT then entry.lastT = rec.t end
        end
    end

    local list = {}
    for _, entry in pairs(byBoss) do
        local unique = 0
        for _ in pairs(entry.unique) do unique = unique + 1 end
        list[#list + 1] = {
            boss = entry.boss,
            kills = entry.kills,
            avgPlayers = math.floor(entry.sum / entry.kills * 10 + 0.5) / 10,
            uniquePlayers = unique,
            lastT = entry.lastT,
        }
    end
    SortByBossOrder(list, BossOrderIndex(self), "boss")
    return list
end

-- Сводка по рейд-дням: для каждой даты число киллов, список боссов в порядке
-- киллов, сколько разных игроков было хотя бы на одном килле в этот день и
-- средний состав. Фильтр по боссу (bossFilter) оставляет только дни, когда
-- этот босс убивали. Новые дни — первыми. Возвращает список
-- { day = "ГГГГ-ММ-ДД", t = время первого килла дня, kills, bosses = {…},
-- uniquePlayers, avgPlayers }.
function auction:BuildDaySummary(records, now, periodDays, bossFilter, resolveMain)
    local byDay, order = {}, {}
    for _, rec in ipairs(FilterRecords(records, now, periodDays, bossFilter)) do
        local day = date("%Y-%m-%d", rec.t)
        local entry = byDay[day]
        if not entry then
            entry = { day = day, t = rec.t, kills = 0, sum = 0, bosses = {}, unique = {} }
            byDay[day] = entry
            order[#order + 1] = entry
        end
        local count = 0
        for id in pairs(ResolveIdentities(rec, resolveMain)) do
            count = count + 1
            entry.unique[id] = true
        end
        entry.kills = entry.kills + 1
        entry.sum = entry.sum + count
        entry.bosses[#entry.bosses + 1] = rec.boss or "-"
    end

    local list = {}
    for _, entry in ipairs(order) do
        local unique = 0
        for _ in pairs(entry.unique) do unique = unique + 1 end
        list[#list + 1] = {
            day = entry.day,
            t = entry.t,
            kills = entry.kills,
            bosses = entry.bosses,
            uniquePlayers = unique,
            avgPlayers = math.floor(entry.sum / entry.kills * 10 + 0.5) / 10,
        }
    end
    table.sort(list, function(a, b) return a.day > b.day end)
    return list
end

-- Процент посещаемости игрока за ATTENDANCE_TOOLTIP_DAYS дней — для тултипа
-- ставок (ShowBidsTooltip в ui.lua). Возвращает число 0..100 или nil, если
-- истории нет или нет доступа. Результат кэшируется до изменения истории,
-- смены режима "по мейнам" или 60 секунд.
function auction:GetAttendancePercentFor(playerName)
    if not playerName or not self:HasAttendanceAccess() then return nil end
    if not self.attendance or #self.attendance == 0 then return nil end

    local now = time()
    local byMain = self:IsAttendanceByMain()
    local cache = self.attendancePctCache
    if not cache or cache.rev ~= self.attendanceRevision or cache.byMain ~= byMain or now - cache.t > 60 then
        local resolver = byMain and self:GetAttendanceResolver() or nil
        local report = self:BuildAttendanceReport(self.attendance, now, self.ATTENDANCE_TOOLTIP_DAYS, 0, nil, resolver)
        local pct = {}
        for _, entry in ipairs(report.players) do pct[entry.name] = entry.pct end
        cache = { rev = self.attendanceRevision, byMain = byMain, t = now, total = report.total, pct = pct, resolver = resolver }
        self.attendancePctCache = cache
    end

    if cache.total == 0 then return nil end
    local id = playerName
    if cache.resolver then
        local main = cache.resolver(playerName, nil)
        if main then id = main end
    end
    return cache.pct[id] or 0
end

-- ======================
-- 5. Текстовый отчёт (для копирования)
-- ======================

-- Дробное число с запятой (для русского Excel): 12.5 → "12,5".
local function DecimalComma(x)
    return (string.format("%.1f", x):gsub("%.", ","))
end

-- Собирает текст отчёта в формате CSV с разделителем ";" под текущий вид вкладки.
--   view — "players" | "bosses" | "days";
--   data — результат BuildAttendanceReport / BuildBossSummary / BuildDaySummary;
--   info — { periodLabel, bossFilter, byMain, total } для строки-заголовка.
function auction:BuildAttendanceReportText(view, data, info)
    local lines = {}
    local head = "Attendance — период: "..(info.periodLabel or "?")
    if info.bossFilter and view ~= "bosses" then head = head.."; босс: "..info.bossFilter end
    if view == "players" then
        head = head.."; киллов: "..(info.total or 0).."; по мейнам: "..(info.byMain and "да" or "нет")
    end
    lines[#lines + 1] = head

    if view == "players" then
        lines[#lines + 1] = "Игрок;Класс;Был;Из;%;Отдых"
        for _, e in ipairs(data.players) do
            lines[#lines + 1] = table.concat({ e.name, ClassLabel(e.class), e.attended, e.total, e.pct, e.rested }, ";")
        end
    elseif view == "bosses" then
        lines[#lines + 1] = "Босс;Киллов;Ср. состав;Игроков;Последний килл"
        for _, e in ipairs(data) do
            lines[#lines + 1] = table.concat({ e.boss, e.kills, DecimalComma(e.avgPlayers), e.uniquePlayers, date("%d.%m.%Y", e.lastT) }, ";")
        end
    else
        lines[#lines + 1] = "Дата;Киллов;Игроков;Ср. состав;Боссы"
        for _, e in ipairs(data) do
            lines[#lines + 1] = table.concat({ date("%d.%m.%Y", e.t), e.kills, e.uniquePlayers, DecimalComma(e.avgPlayers), table.concat(e.bosses, ", ") }, ";")
        end
    end
    return table.concat(lines, "\n")
end
