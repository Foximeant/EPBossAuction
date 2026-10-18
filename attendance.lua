local auction = EPBossAuction

-- ============================================================
-- attendance.lua — вкладка Attendance (посещаемость рейдов)
-- ============================================================
-- Назначение: показать ЛМ и офицерам, кто из игроков бывал на убийствах
-- боссов и какой процент киллов за выбранный период посетил каждый.
--
-- Откуда берутся данные (так решено владельцем аддона):
--   • запись ("снимок") делается в момент "Очистить таблицу" — это и есть
--     момент "босс убит, лут роздан". В снимок попадает: время, босс,
--     подземелье, все, кто сейчас в рейд-группе (имя → класс), и те из них,
--     кто был отмечен в явке на этого босса как "Хочу отдохнуть".
--   • записывают только ЛМ и офицеры (см. CanRecordAttendance), каждый на
--     своём клиенте: сообщения END/END_ALL приходят всему рейду, поэтому
--     офицер получает те же события, что и ЛМ, и отдельной синхронизации
--     истории между игроками НЕТ (у каждого офицера своя копия — только за
--     те киллы, при которых он сам был в рейде с загруженным аддоном).
--   • обычные рейдеры ничего не хранят и вкладку не видят.
--
-- Структура одной записи (auction.attendance — список, по возрастанию времени):
--   { t = <unix-время>, boss = "Имя босса" или nil, instance = "Подземелье" или nil,
--     players = { ["Имя"] = "CLASSTOKEN", ... },
--     rested  = { ["Имя"] = true, ... } }        -- подмножество players
--
-- Хранится в SavedVariable EPBossAuctionSavedAttendance (events.lua грузит,
-- core.lua:SaveData сохраняет). Лимит — ATTENDANCE_MAX_RECORDS последних записей.
--
-- В файле три части:
--   1) доступ и запись (CanRecordAttendance, RecordAttendance);
--   2) подсчёт (BuildAttendanceReport — чистая функция без обращений к
--      WoW API, её можно тестировать вне игры);
--   3) UI: вкладки главного окна ("Ставки" / "Attendance") и панель с таблицей.
-- ============================================================

-- Сколько последних записей хранить (старые вытесняются).
auction.ATTENDANCE_MAX_RECORDS = 600
-- Сколько последних киллов показывать колонками-датами в таблице.
auction.ATTENDANCE_COLUMNS = 10
-- Две записи по одному боссу ближе друг к другу, чем это число секунд, считаются
-- дублем (у ЛМ событие приходит дважды: локальная очистка + эхо сообщения END).
auction.ATTENDANCE_DEDUP_SECONDS = 15
-- Периоды для процента посещаемости; days = 0 значит "без ограничения".
auction.ATTENDANCE_PERIODS = {
    { days = 7,  label = "7 дней" },
    { days = 30, label = "30 дней" },
    { days = 0,  label = "всё время" },
}
-- Какой период выбран сейчас (индекс в ATTENDANCE_PERIODS), по умолчанию 30 дней.
auction.attendancePeriodIndex = 2
-- Сами записи; events.lua при загрузке заменяет на сохранённые.
auction.attendance = auction.attendance or {}

-- ======================
-- 1. Доступ и запись
-- ======================

-- Обрезает имя до первых n символов с учётом UTF-8 (кириллица — 2 байта на
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

-- Может ли этот клиент ЗАПИСЫВАТЬ посещаемость: ЛМ, лидер/ассистент рейда или
-- офицер гильдии (по праву видеть офицерские заметки). Единственное место, где
-- определяется, кто такие "офицеры" — хотите другое правило, правьте тут.
function auction:CanRecordAttendance()
    if self:IsLootMaster() then return true end
    if IsRaidLeader and IsRaidLeader() then return true end
    if IsRaidOfficer and IsRaidOfficer() then return true end
    if IsInGuild and IsInGuild() and CanViewOfficerNote and CanViewOfficerNote() then return true end
    return false
end

-- Показывать ли вкладку Attendance: если можешь записывать, либо уже есть
-- накопленные записи (ЛМ/офицер должен видеть историю и вне рейда, когда
-- IsLootMaster/IsRaidOfficer уже ложь).
function auction:HasAttendanceAccess()
    if self:CanRecordAttendance() then return true end
    return self.attendance ~= nil and #self.attendance > 0
end

-- Делает снимок состава рейда. Вызывается в моменты очистки таблицы:
--   • у ЛМ — из EndAuctionLocal/EndAuctionAllLocal (ui.lua), ДО очистки явки;
--   • у остальных — из Handle_END/Handle_END_ALL (comm.lua), с sender = отправитель.
-- bossName — босс, по которому раздавали лут (nil, если неизвестен).
-- sender — только для сетевого пути: принимаем событие лишь от текущего ЛМ
-- (self.lastLM) или от себя, чтобы посторонний сообщением END не мог засорить историю.
function auction:RecordAttendance(bossName, sender)
    if not self:CanRecordAttendance() then return end
    if not IsInRaid() then return end

    local me = UnitName("player")
    if sender and StripRealm(sender) ~= me and StripRealm(sender) ~= StripRealm(self.lastLM) then
        self:Debug("Attendance: сообщение от "..tostring(sender).." не от ЛМ, пропускаю")
        return
    end

    if bossName and not self.bosses[bossName] then bossName = nil end
    self.attendance = self.attendance or {}

    local now = time()
    local last = self.attendance[#self.attendance]
    if last and last.boss == bossName and (now - last.t) < self.ATTENDANCE_DEDUP_SECONDS then
        self:Debug("Attendance: дубль записи, пропускаю")
        return
    end

    local players = {}
    for i = 1, GetNumRaidMembers() do
        local name, _, _, _, _, class = GetRaidRosterInfo(i)
        if name then players[name] = class or "UNKNOWN" end
    end
    if next(players) == nil then return end

    local rested = {}
    if bossName then
        for name in pairs(self:GetSignupSet(bossName, "rest")) do
            if players[name] then rested[name] = true end
        end
    end

    table.insert(self.attendance, {
        t = now,
        boss = bossName,
        instance = bossName and self.bossToInstance[bossName] or nil,
        players = players,
        rested = rested,
    })
    while #self.attendance > self.ATTENDANCE_MAX_RECORDS do
        table.remove(self.attendance, 1)
    end
    self:Debug("Attendance: записан килл "..tostring(bossName))

    self:RequestSaveData()
    if self.UpdateMainTabs then self:UpdateMainTabs() end
    if self.RefreshAttendance then self:RefreshAttendance() end
end

-- Удаляет одну запись (ПКМ по дате в таблице) — на случай, если очистили
-- не после килла, а по ошибке.
function auction:DeleteAttendanceRecord(rec)
    for i, r in ipairs(self.attendance) do
        if r == rec then
            table.remove(self.attendance, i)
            break
        end
    end
    self:RequestSaveData()
    if self.UpdateMainTabs then self:UpdateMainTabs() end
    if self.RefreshAttendance then self:RefreshAttendance() end
end

-- ======================
-- 2. Подсчёт (чистая функция, без WoW API)
-- ======================

-- Считает отчёт по списку записей.
--   records     — записи (как в auction.attendance);
--   now         — текущее время (unix);
--   periodDays  — период в днях, 0/nil = все записи;
--   maxColumns  — сколько последних киллов вывести колонками.
-- Возвращает { total = число киллов за период, columns = последние записи
-- (по возрастанию времени, не больше maxColumns), players = список игроков }.
-- У каждого игрока: name, class, attended (в скольких киллах был в рейде),
-- rested (из них отмечен "хочу отдохнуть"), total, pct (0..100, округлено),
-- cells[i] = "P" (в рейде) / "R" (в рейде, но "хочу отдохнуть") / nil (не было)
-- для i-й колонки. Процент считается по КИЛЛАМ, а не по дням: опоздавший
-- или ушедший раньше не получает "полный день".
function auction:BuildAttendanceReport(records, now, periodDays, maxColumns)
    local cutoff = (periodDays and periodDays > 0) and (now - periodDays * 86400) or nil

    local inPeriod = {}
    for _, rec in ipairs(records) do
        if not cutoff or rec.t >= cutoff then
            inPeriod[#inPeriod + 1] = rec
        end
    end
    table.sort(inPeriod, function(a, b) return a.t < b.t end)

    local total = #inPeriod
    local firstColumn = math.max(1, total - maxColumns + 1)
    local columns = {}
    for i = firstColumn, total do
        columns[#columns + 1] = inPeriod[i]
    end

    local byName = {}
    for index, rec in ipairs(inPeriod) do
        for name, class in pairs(rec.players) do
            local entry = byName[name]
            if not entry then
                entry = { name = name, class = class, attended = 0, rested = 0, cells = {} }
                byName[name] = entry
            end
            entry.class = class or entry.class
            entry.attended = entry.attended + 1
            local isRested = rec.rested and rec.rested[name] or false
            if isRested then entry.rested = entry.rested + 1 end
            if index >= firstColumn then
                entry.cells[index - firstColumn + 1] = isRested and "R" or "P"
            end
        end
    end

    local players = {}
    for _, entry in pairs(byName) do
        entry.total = total
        entry.pct = total > 0 and math.floor(entry.attended * 100 / total + 0.5) or 0
        players[#players + 1] = entry
    end
    table.sort(players, function(a, b)
        if a.pct ~= b.pct then return a.pct > b.pct end
        if a.attended ~= b.attended then return a.attended > b.attended end
        return a.name < b.name
    end)

    return { total = total, columns = columns, players = players }
end

-- ======================
-- 3. UI
-- ======================

-- Геометрия таблицы (пиксели внутри панели): колонка игрока, колонка %, колонки-даты.
local ROW_HEIGHT = 18
local HEADER_HEIGHT = 32
local NAME_X, NAME_W = 6, 118
local PCT_X, PCT_W = 128, 44
local COL_X, COL_W = 176, 40

-- Цвета ячеек и процента.
local COLOR_PRESENT = { 0.30, 0.90, 0.30 }
local COLOR_RESTED  = { 0.90, 0.75, 0.20 }
local COLOR_ABSENT  = { 0.40, 0.40, 0.40 }

-- Цвет процента посещаемости: зелёный от 80, жёлтый от 50, иначе красный.
local function PercentColor(pct)
    if pct >= 80 then return 0.30, 0.90, 0.30 end
    if pct >= 50 then return 0.90, 0.75, 0.20 end
    return 0.90, 0.30, 0.30
end

-- Создаёт вкладки главного окна и панель Attendance. Вызывается один раз из
-- CreateUI (ui.lua), когда левая панель и таблица ставок уже созданы.
function auction:CreateAttendanceUI(frame)
    self:CreateMainTabs(frame)
    self:CreateAttendancePanel(frame)
    self.activeTab = "bids"
    self:UpdateMainTabs()
end

-- Две вкладки в левом верхнем углу заголовка окна. Скин свой (не SkinButton):
-- активная вкладка подсвечивается акцентным цветом, а общий OnLeave-хук
-- SkinButton сбрасывал бы эту подсветку (та же причина, что у кнопок явки).
function auction:CreateMainTabs(frame)
    local c = self.theme.colors
    self.mainTabs = {}
    local defs = {
        { key = "bids",       label = "Ставки" },
        { key = "attendance", label = "Attendance" },
    }
    local previous
    for i, def in ipairs(defs) do
        local tab = CreateFrame("Button", nil, frame)
        tab:SetSize(92, 22)
        if previous then
            tab:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            tab:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -10)
        end
        tab:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        tab:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], c.border[4])
        tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tab.text:SetPoint("CENTER", tab, "CENTER", 0, 0)
        tab.text:SetText(def.label)
        tab.key = def.key
        tab:SetScript("OnClick", function() auction:ShowMainTab(def.key) end)
        tab:SetScript("OnEnter", function()
            tab:SetBackdropColor(c.buttonHover[1], c.buttonHover[2], c.buttonHover[3], c.buttonHover[4])
        end)
        tab:SetScript("OnLeave", function() auction:UpdateMainTabs() end)
        self.mainTabs[i] = tab
        previous = tab
    end
end

-- Перекрашивает вкладки под активную и прячет весь ряд вкладок, если у этого
-- клиента нет доступа к Attendance (тогда окно выглядит как раньше).
-- Если доступ пропал, а открыта вкладка Attendance — возвращает на "Ставки".
function auction:UpdateMainTabs()
    if not self.mainTabs then return end
    local c = self.theme.colors
    local hasAccess = self:HasAttendanceAccess()

    if not hasAccess and self.activeTab == "attendance" then
        self:ShowMainTab("bids")
        return
    end

    for _, tab in ipairs(self.mainTabs) do
        if hasAccess then
            tab:Show()
            if tab.key == self.activeTab then
                tab:SetBackdropColor(c.accent[1], c.accent[2], c.accent[3], 0.9)
                tab.text:SetTextColor(0, 0, 0)
            else
                tab:SetBackdropColor(c.button[1], c.button[2], c.button[3], c.button[4])
                tab.text:SetTextColor(1, 1, 1)
            end
        else
            tab:Hide()
        end
    end
end

-- Переключает содержимое окна: "bids" (левая панель + таблица ставок) или
-- "attendance" (одна панель на всю ширину). На Attendance без доступа не пускает.
function auction:ShowMainTab(tab)
    if tab == "attendance" and not self:HasAttendanceAccess() then tab = "bids" end
    self.activeTab = tab

    if tab == "attendance" then
        self.leftPanel:Hide()
        self.scrollFrame:Hide()
        if self.scrollBG then self.scrollBG:Hide() end
        self.attendancePanel:Show()
        self:RefreshAttendance()
    else
        self.attendancePanel:Hide()
        self.leftPanel:Show()
        self.scrollFrame:Show()
        if self.scrollBG then self.scrollBG:Show() end
        if self.selectedBoss then self:RequestRefresh() end
    end
    self:UpdateMainTabs()
end

-- Строит панель Attendance: тулбар (период, счётчик), шапка с датами (кнопки,
-- ПКМ — удалить запись), прокручиваемый список игроков и легенда внизу.
-- Панель занимает ту же область, что левая панель + таблица ставок вместе.
function auction:CreateAttendancePanel(frame)
    local panel = CreateFrame("Frame", "EPBossAuctionAttendancePanel", frame)
    panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -45)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    panel:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    panel:SetBackdropBorderColor(0, 0, 0, 1)
    self:SkinPanel(panel)
    panel:Hide()
    self.attendancePanel = panel

    -- Тулбар: кнопка периода (по клику — следующий период по кругу) и счётчик киллов
    local periodBtn = CreateFrame("Button", nil, panel)
    periodBtn:SetSize(150, 22)
    periodBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -6)
    periodBtn:SetText("Период")
    periodBtn:SetNormalFontObject(GameFontNormal)
    self:SkinButton(periodBtn)
    periodBtn:SetScript("OnClick", function()
        auction.attendancePeriodIndex = (auction.attendancePeriodIndex % #auction.ATTENDANCE_PERIODS) + 1
        auction:RefreshAttendance()
    end)
    self.attendancePeriodBtn = periodBtn

    local info = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    info:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -11)
    info:SetJustifyH("RIGHT")
    info:SetTextColor(0.7, 0.7, 0.7)
    self.attendanceInfo = info

    -- Шапка таблицы: подписи "Игрок"/"%" и кнопки-даты (по одной на колонку)
    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -34)
    header:SetSize(COL_X + self.ATTENDANCE_COLUMNS * COL_W, HEADER_HEIGHT)

    local nameLabel = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLabel:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", NAME_X, 4)
    nameLabel:SetText("Игрок")
    local pctLabel = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pctLabel:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", PCT_X, 4)
    pctLabel:SetWidth(PCT_W)
    pctLabel:SetJustifyH("CENTER")
    pctLabel:SetText("%")

    self.attendanceHeaderButtons = {}
    for i = 1, self.ATTENDANCE_COLUMNS do
        local hb = CreateFrame("Button", nil, header)
        hb:SetSize(COL_W, HEADER_HEIGHT)
        hb:SetPoint("TOPLEFT", header, "TOPLEFT", COL_X + (i - 1) * COL_W, 0)
        hb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        hb.text = hb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hb.text:SetPoint("CENTER", hb, "CENTER", 0, 0)
        hb.text:SetWidth(COL_W)
        hb.text:SetJustifyH("CENTER")
        hb:SetScript("OnClick", function(_, button)
            if button == "RightButton" and hb.record then
                auction:ConfirmDeleteAttendanceRecord(hb.record)
            end
        end)
        hb:SetScript("OnEnter", function()
            auction:ShowAttendanceRecordTooltip(hb, hb.record)
        end)
        hb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.attendanceHeaderButtons[i] = hb
    end

    -- Прокручиваемый список игроков
    local scroll = CreateFrame("ScrollFrame", "EPBossAuctionAttendanceScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 26)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(COL_X + self.ATTENDANCE_COLUMNS * COL_W, 1)
    scroll:SetScrollChild(content)
    self.attendanceContent = content
    self.attendanceRows = {}

    local scrollBar = _G["EPBossAuctionAttendanceScrollScrollBar"]
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 22, -17)
        scrollBar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 22, 17)
        self:SkinScrollBar(scrollBar)
    end

    -- Текст для пустого состояния (пока нет ни одной записи за период)
    local empty = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    empty:SetPoint("CENTER", panel, "CENTER", 0, 10)
    empty:SetWidth(420)
    empty:SetJustifyH("CENTER")
    empty:SetTextColor(0.6, 0.6, 0.6)
    self.attendanceEmpty = empty

    -- Легенда
    local legend = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    legend:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 8)
    legend:SetText("|cff4de64d+|r в рейде    |cffe6bf33О|r в рейде, но «хочу отдохнуть»    |cff666666-|r не было    |cff888888ПКМ по дате — удалить запись|r")
end

-- Строка таблицы по номеру — создаётся при первом обращении и дальше
-- переиспользуется (как пул строк главной таблицы).
function auction:GetAttendanceRow(index)
    local row = self.attendanceRows[index]
    if row then return row end

    local content = self.attendanceContent
    row = CreateFrame("Frame", nil, content)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)
    row:EnableMouse(true)

    row.baseAlpha = (index % 2 == 0) and 0.05 or 0
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    row.bg:SetVertexColor(1, 1, 1, row.baseAlpha)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", row, "LEFT", NAME_X, 0)
    row.name:SetWidth(NAME_W)
    row.name:SetJustifyH("LEFT")

    row.pct = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.pct:SetPoint("LEFT", row, "LEFT", PCT_X, 0)
    row.pct:SetWidth(PCT_W)
    row.pct:SetJustifyH("CENTER")

    row.cells = {}
    for i = 1, self.ATTENDANCE_COLUMNS do
        local cell = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        cell:SetPoint("LEFT", row, "LEFT", COL_X + (i - 1) * COL_W, 0)
        cell:SetWidth(COL_W)
        cell:SetJustifyH("CENTER")
        row.cells[i] = cell
    end

    row:SetScript("OnEnter", function()
        row.bg:SetVertexColor(1, 1, 1, 0.12)
        auction:ShowAttendancePlayerTooltip(row, row.entry)
    end)
    row:SetScript("OnLeave", function()
        row.bg:SetVertexColor(1, 1, 1, row.baseAlpha)
        GameTooltip:Hide()
    end)

    self.attendanceRows[index] = row
    return row
end

-- Тултип по дате в шапке: когда, какой босс/подземелье, сколько человек было.
function auction:ShowAttendanceRecordTooltip(owner, rec)
    if not rec then return end
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    GameTooltip:SetText(date("%d.%m.%Y %H:%M", rec.t))
    GameTooltip:AddLine(rec.boss or "Босс не определён", 1, 1, 1)
    if rec.instance then GameTooltip:AddLine(rec.instance, 0.7, 0.7, 0.7) end
    local count, rested = 0, 0
    for _ in pairs(rec.players) do count = count + 1 end
    for _ in pairs(rec.rested or {}) do rested = rested + 1 end
    local line = "В рейде: "..count
    if rested > 0 then line = line.." (из них «хочу отдохнуть»: "..rested..")" end
    GameTooltip:AddLine(line, 0.6, 1, 0.6)
    GameTooltip:AddLine("ПКМ — удалить запись", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

-- Тултип по строке игрока: сколько киллов посетил из скольких, из них на "отдыхе".
function auction:ShowAttendancePlayerTooltip(owner, entry)
    if not entry then return end
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
    GameTooltip:SetText(entry.name)
    GameTooltip:AddLine("Был в рейде: "..entry.attended.." из "..entry.total.." ("..entry.pct.."%)", 1, 1, 1)
    if entry.rested > 0 then
        GameTooltip:AddLine("из них «хочу отдохнуть»: "..entry.rested, 0.9, 0.75, 0.2)
    end
    GameTooltip:Show()
end

-- Подтверждение удаления записи (StaticPopup, как и остальные подтверждения в аддоне).
function auction:ConfirmDeleteAttendanceRecord(rec)
    local title = (rec.boss or "босс не определён").." — "..date("%d.%m.%Y %H:%M", rec.t)
    StaticPopupDialogs["EPBA_DELETE_ATTENDANCE"] = {
        text = "Удалить запись посещаемости?\n"..title,
        button1 = "Удалить", button2 = "Отмена",
        OnAccept = function() auction:DeleteAttendanceRecord(rec) end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    StaticPopup_Show("EPBA_DELETE_ATTENDANCE")
end

-- Перерисовывает панель: считает отчёт (BuildAttendanceReport) и заполняет
-- шапку, строки и счётчик. Ничего не делает, если панель сейчас не открыта.
function auction:RefreshAttendance()
    local panel = self.attendancePanel
    if not panel or not panel:IsShown() then return end

    local period = self.ATTENDANCE_PERIODS[self.attendancePeriodIndex]
    self.attendancePeriodBtn:SetText("Период: "..period.label)

    local report = self:BuildAttendanceReport(self.attendance or {}, time(), period.days, self.ATTENDANCE_COLUMNS)
    self.attendanceReport = report
    self.attendanceInfo:SetText("Киллов за период: "..report.total)

    for i = 1, self.ATTENDANCE_COLUMNS do
        local hb = self.attendanceHeaderButtons[i]
        local rec = report.columns[i]
        hb.record = rec
        if rec then
            hb.text:SetText(date("%d.%m", rec.t).."\n"..(rec.boss and Utf8Prefix(rec.boss, 5) or "-"))
            hb:Show()
        else
            hb.text:SetText("")
            hb:Hide()
        end
    end

    local count = #report.players
    for i = 1, count do
        local entry = report.players[i]
        local row = self:GetAttendanceRow(i)
        row.entry = entry

        local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.class]
        if color then
            row.name:SetTextColor(color.r, color.g, color.b)
        else
            row.name:SetTextColor(1, 1, 1)
        end
        row.name:SetText(entry.name)

        row.pct:SetTextColor(PercentColor(entry.pct))
        row.pct:SetText(entry.pct.."%")

        for c = 1, self.ATTENDANCE_COLUMNS do
            local cell = row.cells[c]
            local state = entry.cells[c]
            if c > #report.columns then
                cell:SetText("")
            elseif state == "P" then
                cell:SetTextColor(COLOR_PRESENT[1], COLOR_PRESENT[2], COLOR_PRESENT[3])
                cell:SetText("+")
            elseif state == "R" then
                cell:SetTextColor(COLOR_RESTED[1], COLOR_RESTED[2], COLOR_RESTED[3])
                cell:SetText("О")
            else
                cell:SetTextColor(COLOR_ABSENT[1], COLOR_ABSENT[2], COLOR_ABSENT[3])
                cell:SetText("-")
            end
        end
        row:Show()
    end
    for i = count + 1, #self.attendanceRows do
        self.attendanceRows[i]:Hide()
    end
    self.attendanceContent:SetHeight(math.max(1, count * ROW_HEIGHT))

    if report.total == 0 then
        self.attendanceEmpty:SetText("За этот период записей нет.\nСостав рейда сохраняется при «Очистить таблицу»\n(только когда вы в рейде и вы ЛМ или офицер).")
        self.attendanceEmpty:Show()
    else
        self.attendanceEmpty:Hide()
    end
end
