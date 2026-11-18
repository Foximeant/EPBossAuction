local auction = EPBossAuction

-- ============================================================
-- stats_ui.lua — вкладка «Статистика»: интерфейс
-- ============================================================
-- Данные и подсчёт — в stats.lua. Панель занимает ту же область, что левая
-- панель и таблица ставок вместе (как Attendance и Резерв). Сверху два ряда:
--   ряд 1: Период | Вид (Игроки / Выдачи / Боссы) | фильтр «Босс»;
--   ряд 2: Отчёт | Очистить | «По мейнам» | итоги за период.
-- Виды:
--   Игроки — кто сколько предметов получил и потратил ЕП («*» — есть выданные
--            предметы без списания ЕП); тултип — персонажи и последние предметы;
--   Выдачи — список выдач, сначала новые; тултип — предмет и детали;
--   Боссы  — выдачи и ЕП по боссам, включая начисления рейду.
-- Вкладку видят только те, у кого есть доступ (HasStatsAccess).
-- Хелперы стиля (кнопка/выпадающий список) — из auction.uiHelpers (attendance_ui.lua).
-- ============================================================

local ROW_HEIGHT = 18
local HEADER_HEIGHT = 32
local HEADER_Y = -62
local CONTENT_WIDTH = 590
local MAX_COLS = 6

-- Колонки видов: x, ширина, выравнивание (без align — по центру).
local LAYOUT = {
    players = {
        { title = "Игрок",      x = 6,   w = 150, align = "LEFT" },
        { title = "Предметов",  x = 160, w = 62 },
        { title = "ЕП списано", x = 226, w = 96 },
        { title = "Ср. ставка", x = 326, w = 82 },
        { title = "Офф-спек",   x = 412, w = 62 },
        { title = "Последний",  x = 478, w = 100 },
    },
    items = {
        { title = "Дата",       x = 6,   w = 76,  align = "LEFT" },
        { title = "Босс",       x = 86,  w = 112, align = "LEFT" },
        { title = "Предмет",    x = 202, w = 176, align = "LEFT" },
        { title = "Победитель", x = 382, w = 100, align = "LEFT" },
        { title = "Ставка",     x = 486, w = 52 },
        { title = "Списано",    x = 540, w = 50 },
    },
    bosses = {
        { title = "Босс",            x = 6,   w = 196, align = "LEFT" },
        { title = "Выдач",           x = 206, w = 52 },
        { title = "ЕП списано",      x = 262, w = 92 },
        { title = "Начислено рейду", x = 358, w = 116 },
        { title = "Игроков",         x = 478, w = 48 },
        { title = "Последний",       x = 530, w = 58 },
    },
}
local VIEW_ORDER = { "players", "items", "bosses" }
local VIEW_LABELS = { players = "Игроки", items = "Выдачи", bosses = "Боссы" }

local GRAY = "|cff888888"
local GOLD = "|cffffd200"

local function Num(n) return auction:FormatNumber(n or 0) end

-- ======================
-- Панель
-- ======================

function auction:CreateStatsPanel(frame)
    local H = self.uiHelpers
    local panel = CreateFrame("Frame", "EPBossAuctionStatsPanel", frame)
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
    self.statsPanel = panel

    -- ---- Ряд 1 ----
    self.statsPeriodBtn = H.MakeButton(self, panel, "Период", 150, 6, -6, function()
        auction.statsPeriodIndex = (auction.statsPeriodIndex % #auction.STATS_PERIODS) + 1
        auction:RefreshStats()
    end)

    self.statsViewBtn = H.MakeButton(self, panel, "Вид", 120, 162, -6, function()
        local index = 1
        for i, key in ipairs(VIEW_ORDER) do
            if key == auction.statsView then index = i end
        end
        auction.statsView = VIEW_ORDER[(index % #VIEW_ORDER) + 1]
        auction:RefreshStats()
    end)

    -- Фильтр по боссу: список строится при каждом открытии (боссы с записями за период).
    local bossDropdown = H.MakeDropdown(panel, "EPBossAuctionStatsBossDropdown", 130, 288, -5, "Все боссы")
    UIDropDownMenu_Initialize(bossDropdown, function()
        H.LockDropdownHeight(bossDropdown)
        local period = auction.STATS_PERIODS[auction.statsPeriodIndex]
        local allInfo = UIDropDownMenu_CreateInfo()
        allInfo.text = "Все боссы"
        allInfo.checked = (auction.statsBossFilter == nil)
        allInfo.func = function()
            auction.statsBossFilter = nil
            auction:RefreshStats()
        end
        UIDropDownMenu_AddButton(allInfo)
        for _, item in ipairs(auction:BuildStatsBossList(auction:GetLootLog(), time(), period.days)) do
            local boss = item.boss
            local info = UIDropDownMenu_CreateInfo()
            info.text = boss.." "..GRAY.."("..item.count..")|r"
            info.checked = (auction.statsBossFilter == boss)
            info.func = function()
                auction.statsBossFilter = boss
                auction:RefreshStats()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    H.LockDropdownHeight(bossDropdown)
    self:SkinDropdown(bossDropdown)
    self.statsBossDropdown = bossDropdown

    -- ---- Ряд 2 ----
    self.statsReportBtn = H.MakeButton(self, panel, "Отчёт", 80, 6, -34, function()
        auction:ShowStatsReportWindow()
    end)
    self.statsClearBtn = H.MakeButton(self, panel, "Очистить", 90, 92, -34, function()
        auction:ConfirmClearLootLog()
    end)

    local check = CreateFrame("CheckButton", "EPBossAuctionStatsByMainCheck", panel, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", panel, "TOPLEFT", 190, -32)
    check.text = _G["EPBossAuctionStatsByMainCheckText"]
    check.text:SetText(" По мейнам")
    self:SkinCheckbox(check)
    check:HookScript("OnClick", function(button)
        local state = button:GetChecked() and true or false
        H.SetCheckboxChecked(button, state)
        auction.db.stats = auction.db.stats or {}
        auction.db.stats.byMain = state
        auction:SaveSettings()
        auction:RefreshStats()
    end)
    H.SetCheckboxChecked(check, self:IsStatsByMain())
    self.statsByMainCheck = check

    local info = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    info:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -39)
    info:SetJustifyH("RIGHT")
    info:SetTextColor(0.7, 0.7, 0.7)
    self.statsInfo = info

    -- ---- Таблица ----
    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, HEADER_Y)
    header:SetSize(CONTENT_WIDTH, HEADER_HEIGHT)
    header.labels = {}
    for i = 1, MAX_COLS do
        header.labels[i] = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    end
    self.statsHeader = header

    local scroll = CreateFrame("ScrollFrame", "EPBossAuctionStatsScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 26)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_WIDTH, 1)
    scroll:SetScrollChild(content)
    self.statsContent = content
    self.statsRows = {}
    local scrollBar = _G["EPBossAuctionStatsScrollScrollBar"]
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 22, -17)
        scrollBar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 22, 17)
        self:SkinScrollBar(scrollBar)
    end

    local empty = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    empty:SetPoint("CENTER", panel, "CENTER", 0, 10)
    empty:SetWidth(420)
    empty:SetJustifyH("CENTER")
    empty:SetTextColor(0.6, 0.6, 0.6)
    self.statsEmpty = empty

    local legend = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    legend:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 8)
    legend:SetTextColor(0.6, 0.6, 0.6)
    legend:SetText("Журнал ведёт клиент ЛМ (выдачи через окно добычи EPBA). «*» — есть выдачи без списания ЕП. Наведите на строку — подробности.")
    self.statsLegend = legend
end

-- ======================
-- Строки
-- ======================

function auction:GetStatsRow(index)
    local row = self.statsRows[index]
    if row then return row end

    local content = self.statsContent
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

    row.cells = {}
    for i = 1, MAX_COLS do
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetWordWrap(false)
        row.cells[i] = fs
    end

    row:SetScript("OnEnter", function()
        row.bg:SetVertexColor(1, 1, 1, 0.12)
        if row.tip then row.tip(row) end
    end)
    row:SetScript("OnLeave", function()
        row.bg:SetVertexColor(1, 1, 1, row.baseAlpha)
        GameTooltip:Hide()
    end)

    self.statsRows[index] = row
    return row
end

-- Заполняет строку: cells — тексты колонок, tip — функция тултипа (или nil).
local function FillRow(self, row, layout, cells, tip)
    for i = 1, MAX_COLS do
        local spec, fs = layout[i], row.cells[i]
        if spec and cells[i] then
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", row, "LEFT", spec.x, 0)
            fs:SetWidth(spec.w)
            fs:SetJustifyH(spec.align or "CENTER")
            fs:SetText(cells[i])
            fs:Show()
        else
            fs:Hide()
        end
    end
    row.tip = tip
    row:Show()
end

-- ======================
-- Тултипы
-- ======================

local function Tooltip(owner, title)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(title, 1, 1, 1)
end

local function ItemLabel(itemID)
    local name, link = GetItemInfo(itemID)
    return link or name or ("item:"..tostring(itemID)), (name == nil)
end

function auction:ShowStatsPlayerTooltip(owner, e)
    Tooltip(owner, self:FormatColoredName(e.name))
    if #e.charList > 0 then
        GameTooltip:AddLine("Получено персонажами: "..table.concat(e.charList, ", "), 0.7, 0.8, 1, true)
    end
    GameTooltip:AddLine("Предметов: "..e.items..(e.offspec > 0 and (" (офф-спек: "..e.offspec..")") or ""), 0.9, 0.9, 0.9)
    GameTooltip:AddLine("ЕП списано: "..Num(e.spent), 0.9, 0.9, 0.9)
    if e.uncharged > 0 then
        GameTooltip:AddLine("Выдач без списания ЕП: "..e.uncharged, 1, 0.82, 0)
    end
    if #e.recent > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Последние предметы:", 0.6, 0.6, 0.6)
        for _, r in ipairs(e.recent) do
            local label = ItemLabel(r.itemID)
            GameTooltip:AddDoubleLine(date("%d.%m", r.t).."  "..label, r.bid > 0 and (Num(r.bid).." ЕП") or "—", 1, 1, 1, 0.8, 0.8, 0.8)
        end
    end
    GameTooltip:Show()
end

function auction:ShowStatsItemTooltip(owner, e)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if e.itemID and GameTooltip.SetHyperlink then GameTooltip:SetHyperlink("item:"..e.itemID) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(date("%d.%m.%Y %H:%M", e.t)..(e.boss and ("  ·  "..e.boss) or ""), 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Получил: "..self:FormatColoredName(e.winner)..(e.main and (" |cff999999(мейн: "..e.main..")|r") or ""), 1, 1, 1)
    local bid = e.bid > 0 and (Num(e.bid).." ЕП"..(e.offspec and " (офф-спек)" or "")) or "без ставки"
    GameTooltip:AddLine("Ставка: "..bid..(e.bids > 0 and (", всего ставок: "..e.bids) or ""), 0.9, 0.9, 0.9)
    if e.charged then
        GameTooltip:AddLine("Списано: "..Num(e.spent).." ЕП", 0.3, 0.9, 0.3)
    else
        GameTooltip:AddLine("ЕП не списан", 1, 0.82, 0)
    end
    if e.lm then GameTooltip:AddLine("Выдал: "..e.lm, 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

function auction:ShowStatsBossTooltip(owner, e)
    Tooltip(owner, e.boss)
    GameTooltip:AddLine("Выдач: "..e.drops.."  ·  получателей: "..e.uniquePlayers, 0.9, 0.9, 0.9)
    GameTooltip:AddLine("ЕП списано: "..Num(e.spent), 0.9, 0.9, 0.9)
    if e.uncharged > 0 then GameTooltip:AddLine("Выдач без списания ЕП: "..e.uncharged, 1, 0.82, 0) end
    GameTooltip:AddLine("Начислено рейду: "..Num(e.awarded)..(e.awards > 0 and (" ("..e.awards.." раз)") or ""), 0.9, 0.9, 0.9)
    GameTooltip:AddLine("Последняя запись: "..date("%d.%m.%Y %H:%M", e.last), 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

-- ======================
-- Обновление
-- ======================

-- Перерисовывает вкладку (ничего не делает, если она не открыта).
function auction:RefreshStats()
    local panel = self.statsPanel
    if not panel or not panel:IsShown() then return end

    local H = self.uiHelpers
    local period = self.STATS_PERIODS[self.statsPeriodIndex]
    local view = self.statsView
    local log = self:GetLootLog()
    local byMain = self:IsStatsByMain()
    local now = time()

    self.statsPeriodBtn:SetText("Период: "..period.label)
    self.statsViewBtn:SetText("Вид: "..VIEW_LABELS[view])
    H.SetCheckboxChecked(self.statsByMainCheck, byMain)
    if #log > 0 then self.statsClearBtn:Enable() else self.statsClearBtn:Disable() end

    -- Выбранного босса больше нет в журнале (очистили) — сбрасываем фильтр
    if self.statsBossFilter then
        local found = false
        for _, r in ipairs(log) do
            if r.boss == self.statsBossFilter then found = true break end
        end
        if not found then self.statsBossFilter = nil end
    end
    UIDropDownMenu_SetText(self.statsBossDropdown, self.statsBossFilter or "Все боссы")
    if view == "bosses" then self.statsBossDropdown:Hide() else self.statsBossDropdown:Show() end
    local filter = (view ~= "bosses") and self.statsBossFilter or nil

    -- Шапка
    local layout = LAYOUT[view]
    for i, label in ipairs(self.statsHeader.labels) do
        local spec = layout[i]
        if spec then
            label:ClearAllPoints()
            label:SetPoint("BOTTOMLEFT", self.statsHeader, "BOTTOMLEFT", spec.x, 4)
            label:SetWidth(spec.w)
            label:SetJustifyH(spec.align or "CENTER")
            label:SetText(spec.title)
            label:Show()
        else
            label:Hide()
        end
    end

    local resolver = byMain and self:GetStatsResolver() or nil
    local rows, report = {}, nil
    local needDelayed = false

    if view == "players" then
        local data = self:BuildStatsPlayers(log, now, period.days, filter, resolver)
        report = data
        for _, e in ipairs(data.entries) do
            rows[#rows + 1] = {
                cells = {
                    self:FormatColoredName(e.name), tostring(e.items),
                    Num(e.spent)..(e.uncharged > 0 and (" "..GOLD.."*|r") or ""),
                    e.avgBid and Num(e.avgBid) or "-", e.offspec > 0 and tostring(e.offspec) or "-",
                    date("%d.%m.%y", e.last),
                },
                tip = function(row) auction:ShowStatsPlayerTooltip(row, e) end,
            }
        end
    elseif view == "items" then
        local data = self:BuildStatsItems(log, now, period.days, filter, resolver)
        report = data
        for _, e in ipairs(data) do
            local label, pending = ItemLabel(e.itemID)
            if pending then needDelayed = true end
            rows[#rows + 1] = {
                cells = {
                    date("%d.%m %H:%M", e.t), H.Truncate(e.boss or "?", 16), label,
                    self:FormatColoredName(e.winner),
                    e.bid > 0 and (Num(e.bid)..(e.offspec and " о" or "")) or "-",
                    e.spent and Num(e.spent) or (GRAY.."—|r"),
                },
                tip = function(row) auction:ShowStatsItemTooltip(row, e) end,
            }
        end
    else
        local data = self:BuildStatsBosses(log, now, period.days, resolver)
        report = data
        for _, e in ipairs(data) do
            rows[#rows + 1] = {
                cells = {
                    H.Truncate(e.boss, 28), tostring(e.drops),
                    Num(e.spent)..(e.uncharged > 0 and (" "..GOLD.."*|r") or ""),
                    e.awarded > 0 and Num(e.awarded) or "-", tostring(e.uniquePlayers),
                    date("%d.%m", e.last),
                },
                tip = function(row) auction:ShowStatsBossTooltip(row, e) end,
            }
        end
    end

    for i, r in ipairs(rows) do
        FillRow(self, self:GetStatsRow(i), layout, r.cells, r.tip)
    end
    for i = #rows + 1, #self.statsRows do
        self.statsRows[i]:Hide()
        self.statsRows[i].tip = nil
    end
    self.statsContent:SetHeight(math.max(1, #rows * ROW_HEIGHT))

    -- Итоги и пустое состояние
    local t = self:BuildStatsTotals(log, now, period.days, filter)
    self.statsInfo:SetText(string.format("Выдач: %d  |  ЕП списано: %s  |  Начислено рейду: %s", t.items, Num(t.spent), Num(t.awarded)))
    if #rows == 0 then
        if filter then
            self.statsEmpty:SetText("За этот период нет записей по боссу «"..filter.."».\nВыберите другой период или «Все боссы».")
        else
            self.statsEmpty:SetText("За этот период записей нет.\nЖурнал пополняется, когда ЛМ выдаёт предметы кнопкой «Выдать» в окне добычи EPBA и списывает ЕП.")
        end
        self.statsEmpty:Show()
    else
        self.statsEmpty:Hide()
    end

    self.statsViewData = {
        view = view, data = report,
        info = {
            periodLabel = period.label, bossFilter = filter, byMain = byMain,
            itemName = function(id) return (GetItemInfo(id)) end,
        },
    }

    -- Названия предметов подгружаются не сразу — перерисуем чуть позже
    if needDelayed and not self.statsInfoTimer then
        self.statsInfoTimer = self:ScheduleTimer(function()
            auction.statsInfoTimer = nil
            auction:RefreshStats()
        end, 0.5)
    end
end

-- ======================
-- Окно с текстом отчёта
-- ======================

-- Текст по текущему виду (CSV с «;»): выделен, остаётся нажать Ctrl+C.
function auction:ShowStatsReportWindow()
    local d = self.statsViewData
    if not d then return end
    local text = self:BuildStatsReportText(d.view, d.data, d.info)

    local frame = self.statsReportFrame
    if not frame then
        local c = self.theme.colors
        frame = CreateFrame("Frame", "EPBossAuctionStatsReportFrame", UIParent)
        frame:SetSize(560, 400)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        self:SkinPanel(frame)
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        tinsert(UISpecialFrames, "EPBossAuctionStatsReportFrame")

        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -14)
        title:SetText("Отчёт: статистика выдач")
        title:SetTextColor(c.accent[1], c.accent[2], c.accent[3])

        local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
        hint:SetText("Текст выделен: Ctrl+C — скопировать, Esc — закрыть")
        hint:SetTextColor(0.7, 0.7, 0.7)

        local scroll = CreateFrame("ScrollFrame", "EPBossAuctionStatsReportScroll", frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -56)
        scroll:SetPoint("BOTTOMRIGHT", -34, 50)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(500)
        edit:SetAutoFocus(false)
        edit:SetMaxLetters(200000)
        edit:SetScript("OnEscapePressed", function() frame:Hide() end)
        scroll:SetScrollChild(edit)
        frame.edit = edit

        local close = CreateFrame("Button", nil, frame)
        close:SetSize(120, 24)
        close:SetPoint("BOTTOM", 0, 16)
        close:SetText("Закрыть")
        close:SetNormalFontObject(GameFontNormal)
        self:SkinButton(close)
        close:SetScript("OnClick", function() frame:Hide() end)

        self.statsReportFrame = frame
    end

    frame.edit:SetText(text)
    frame:Show()
    frame.edit:HighlightText()
    frame.edit:SetFocus()
end
