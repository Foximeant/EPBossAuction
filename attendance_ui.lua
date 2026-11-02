local auction = EPBossAuction

-- ============================================================
-- attendance_ui.lua — вкладка Attendance: интерфейс
-- ============================================================
-- Что здесь: вкладки главного окна ("Ставки" / "Attendance"), панель вкладки
-- Attendance, окно с текстом отчёта. Данные и подсчёт — в attendance.lua,
-- сеть — в attendance_sync.lua.
--
-- Панель Attendance занимает ту же область, что левая панель и таблица ставок
-- вместе (они прячутся при переключении вкладки). Сверху два ряда кнопок:
--   ряд 1: Период | Вид (Игроки / Боссы / Дни) | фильтр "Босс" | счётчик киллов;
--   ряд 2: "Записать килл" | Синхронизировать | Отчёт | Очистить | "По мейнам".
-- Ниже — шапка и прокручиваемая таблица. Что в таблице, зависит от вида:
--   Игроки — игрок, % посещаемости, колонки-даты последних киллов (+ / О / -);
--   Боссы  — по каждому боссу: киллов, средний состав, игроков, последний килл
--            (клик по строке — открыть посещаемость по этому боссу);
--   Дни    — по каждому рейд-дню: киллов, игроков, средний состав, боссы.
-- Вкладки и панель видны только тем, у кого есть доступ (HasAttendanceAccess).
-- ============================================================

-- Геометрия (пиксели внутри панели).
local ROW_HEIGHT = 18
local HEADER_HEIGHT = 32
local HEADER_Y = -62                       -- шапка таблицы под двумя рядами кнопок
local CONTENT_WIDTH = 590                  -- ширина прокручиваемого содержимого
local NAME_X, NAME_W = 6, 118              -- вид "Игроки": колонка игрока
local PCT_X, PCT_W = 128, 44               --               колонка процента
local COL_X, COL_W = 176, 40               --               колонки-даты

-- Колонки сводных видов (x, ширина, выравнивание; без align — по центру).
local SUMMARY_LAYOUT = {
    bosses = {
        { title = "Босс",       x = 6,   w = 210, align = "LEFT" },
        { title = "Киллов",     x = 222, w = 60 },
        { title = "Ср. состав", x = 286, w = 84 },
        { title = "Игроков",    x = 374, w = 70 },
        { title = "Последний",  x = 448, w = 90 },
    },
    days = {
        { title = "Дата",       x = 6,   w = 80, align = "LEFT" },
        { title = "Киллов",     x = 90,  w = 56 },
        { title = "Игроков",    x = 150, w = 70 },
        { title = "Ср. состав", x = 224, w = 84 },
        { title = "Боссы",      x = 314, w = 272, align = "LEFT" },
    },
}
local VIEW_ORDER = { "players", "bosses", "days" }
local VIEW_LABELS = { players = "Игроки", bosses = "Боссы", days = "Дни" }

-- Высота выпадающих списков тулбара (как у кнопок). UIDropDownMenu_Initialize
-- сама ставит рамке 32 px при КАЖДОМ открытии списка, поэтому высоту приходится
-- возвращать: в функции построения пунктов и по событию смены размера.
local DROPDOWN_HEIGHT = 22

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

-- Обрезает текст до maxChars символов с многоточием (FontString сам не обрезает —
-- длинный текст переносился бы на вторую строку и налезал на соседнюю строку таблицы).
local function Truncate(text, maxChars)
    if auction.Utf8Prefix(text, maxChars) == text then return text end
    return auction.Utf8Prefix(text, maxChars - 3).."..."
end

-- ======================
-- Вкладки главного окна
-- ======================

-- Создаёт вкладки и панель Attendance. Вызывается один раз из CreateUI (ui.lua),
-- когда левая панель и таблица ставок уже созданы.
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

-- ======================
-- Панель Attendance
-- ======================

-- Кнопка тулбара в стиле остальных кнопок аддона (SkinButton).
local function MakeButton(self, parent, text, width, x, y, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width, 22)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    btn:SetText(text)
    btn:SetNormalFontObject(GameFontNormal)
    self:SkinButton(btn)
    btn:SetScript("OnClick", onClick)
    return btn
end

-- Выпадающий список в стиле остальных списков аддона. Ширина рамки = innerWidth + 50
-- (так считает UIDropDownMenu_SetWidth). Initialize, LockDropdownHeight и SkinDropdown
-- вызывает вызывающий код (после того, как задана функция построения пунктов).
local function MakeDropdown(parent, name, innerWidth, x, y, text)
    local dropdown = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    UIDropDownMenu_SetWidth(dropdown, innerWidth)
    UIDropDownMenu_SetText(dropdown, text)
    return dropdown
end

-- Фиксирует высоту выпадающего списка: ставит DROPDOWN_HEIGHT сейчас и возвращает её
-- каждый раз, когда Blizzard меняет размер рамки (открытие списка).
local function LockDropdownHeight(dropdown)
    dropdown:SetHeight(DROPDOWN_HEIGHT)
    if not dropdown._epbaHeightLocked then
        dropdown._epbaHeightLocked = true
        dropdown:HookScript("OnSizeChanged", function(box, _, height)
            if height and math.abs(height - DROPDOWN_HEIGHT) > 0.5 then
                box:SetHeight(DROPDOWN_HEIGHT)
            end
        end)
    end
end

-- Ставит состояние чекбокса и обновляет галочку SkinCheckbox (на SetChecked она
-- сама не реагирует).
local function SetCheckboxChecked(box, state)
    box:SetChecked(state and true or false)
    if box._epbaRefresh then box._epbaRefresh(box) end
end

-- Строит панель: тулбар (два ряда), шапки таблицы, прокручиваемый список,
-- пустое состояние и легенду. Панель занимает область левой панели + таблицы ставок.
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

    self:CreateAttendanceToolbar(panel)
    self:CreateAttendanceTable(panel)

    -- Текст для пустого состояния (нет записей за период)
    local empty = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    empty:SetPoint("CENTER", panel, "CENTER", 0, 10)
    empty:SetWidth(420)
    empty:SetJustifyH("CENTER")
    empty:SetTextColor(0.6, 0.6, 0.6)
    self.attendanceEmpty = empty

    -- Легенда (текст зависит от вида, см. RefreshAttendance)
    local legend = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    legend:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 8)
    self.attendanceLegend = legend
end

-- Два ряда кнопок над таблицей. Подробности — в шапке файла.
function auction:CreateAttendanceToolbar(panel)
    -- ---- Ряд 1 ----
    self.attendancePeriodBtn = MakeButton(self, panel, "Период", 150, 6, -6, function()
        auction.attendancePeriodIndex = (auction.attendancePeriodIndex % #auction.ATTENDANCE_PERIODS) + 1
        auction:RefreshAttendance()
    end)

    -- Вид: по клику переключается Игроки → Боссы → Дни → Игроки
    self.attendanceViewBtn = MakeButton(self, panel, "Вид", 120, 162, -6, function()
        local index = 1
        for i, key in ipairs(VIEW_ORDER) do
            if key == auction.attendanceView then index = i end
        end
        auction.attendanceView = VIEW_ORDER[(index % #VIEW_ORDER) + 1]
        auction:RefreshAttendance()
    end)

    -- Фильтр по боссу: "Все боссы" или босс из записей (с числом киллов за период).
    -- Список строится при каждом открытии, поэтому всегда актуален.
    local bossDropdown = MakeDropdown(panel, "EPBossAuctionAttendanceBossDropdown", 130, 288, -5, "Все боссы")
    UIDropDownMenu_Initialize(bossDropdown, function()
        LockDropdownHeight(bossDropdown)
        local period = auction.ATTENDANCE_PERIODS[auction.attendancePeriodIndex]
        local allInfo = UIDropDownMenu_CreateInfo()
        allInfo.text = "Все боссы"
        allInfo.checked = (auction.attendanceBossFilter == nil)
        allInfo.func = function()
            auction.attendanceBossFilter = nil
            auction:RefreshAttendance()
        end
        UIDropDownMenu_AddButton(allInfo)
        for _, item in ipairs(auction:BuildAttendanceBossList(auction.attendance or {}, time(), period.days)) do
            local boss = item.boss
            local info = UIDropDownMenu_CreateInfo()
            info.text = boss.." |cff888888("..item.count..")|r"
            info.checked = (auction.attendanceBossFilter == boss)
            info.func = function()
                auction.attendanceBossFilter = boss
                auction:RefreshAttendance()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    LockDropdownHeight(bossDropdown)
    self:SkinDropdown(bossDropdown)
    self.attendanceBossDropdown = bossDropdown

    local info = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    info:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -11)
    info:SetJustifyH("RIGHT")
    info:SetTextColor(0.7, 0.7, 0.7)
    self.attendanceInfo = info

    -- ---- Ряд 2 ----
    -- "Записать килл": двухуровневое меню Подземелье → Босс; выбор босса запрашивает подтверждение
    local recordDropdown = MakeDropdown(panel, "EPBossAuctionAttendanceRecordDropdown", 125, 6, -33, "Записать килл ...")
    UIDropDownMenu_Initialize(recordDropdown, function(_, level)
        LockDropdownHeight(recordDropdown)
        level = level or 1
        if level == 1 then
            for _, instanceName in ipairs(auction.instanceOrder) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = instanceName
                info.value = instanceName
                info.hasArrow = true
                info.notCheckable = true
                UIDropDownMenu_AddButton(info, 1)
            end
        else
            for _, bossName in ipairs(auction.instances[UIDROPDOWNMENU_MENU_VALUE] or {}) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = bossName
                info.notCheckable = true
                info.func = function()
                    CloseDropDownMenus()
                    UIDropDownMenu_SetText(recordDropdown, "Записать килл ...")
                    auction:ConfirmManualAttendance(bossName)
                end
                UIDropDownMenu_AddButton(info, 2)
            end
        end
    end)
    LockDropdownHeight(recordDropdown)
    self:SkinDropdown(recordDropdown)
    self.attendanceRecordDropdown = recordDropdown

    self.attendanceSyncBtn = MakeButton(self, panel, "Синхронизировать", 130, 180, -34, function()
        auction:StartAttendanceSync(false)
    end)
    self.attendanceReportBtn = MakeButton(self, panel, "Отчёт", 80, 316, -34, function()
        auction:ShowAttendanceReportWindow()
    end)
    self.attendanceClearBtn = MakeButton(self, panel, "Очистить", 90, 402, -34, function()
        auction:ConfirmClearAttendance()
    end)

    -- Учёт по мейнам (сохраняется в настройках: auction.db.attendance.byMain)
    local check = CreateFrame("CheckButton", "EPBossAuctionAttendanceByMainCheck", panel, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", panel, "TOPLEFT", 498, -32)
    check.text = _G["EPBossAuctionAttendanceByMainCheckText"]
    check.text:SetText(" По мейнам")
    self:SkinCheckbox(check)
    -- HookScript, а не SetScript: так сохраняются и стандартный звук галочки, и
    -- обновление галочки SkinCheckbox
    check:HookScript("OnClick", function(button)
        local state = button:GetChecked() and true or false
        SetCheckboxChecked(button, state)
        auction.db.attendance = auction.db.attendance or {}
        auction.db.attendance.byMain = state
        auction:SaveSettings()
        auction.attendanceRevision = (auction.attendanceRevision or 0) + 1
        auction:RefreshAttendance()
    end)
    SetCheckboxChecked(check, self:IsAttendanceByMain())
    self.attendanceByMainCheck = check
end

-- Шапки таблицы (для вида "Игроки" и для сводных видов) и прокручиваемое содержимое.
function auction:CreateAttendanceTable(panel)
    -- Шапка вида "Игроки": подписи "Игрок"/"%" и кнопки-даты (по одной на колонку)
    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, HEADER_Y)
    header:SetSize(COL_X + self.ATTENDANCE_COLUMNS * COL_W, HEADER_HEIGHT)
    self.attendanceHeader = header

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

    -- Шапка сводных видов (Боссы / Дни): подписи колонок задаются при обновлении
    local summaryHeader = CreateFrame("Frame", nil, panel)
    summaryHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, HEADER_Y)
    summaryHeader:SetSize(CONTENT_WIDTH, HEADER_HEIGHT)
    summaryHeader:Hide()
    self.attendanceSummaryHeader = summaryHeader
    summaryHeader.labels = {}
    for i = 1, 5 do
        local label = summaryHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        summaryHeader.labels[i] = label
    end

    -- Прокручиваемый список (строки игроков или сводные строки — зависит от вида)
    local scroll = CreateFrame("ScrollFrame", "EPBossAuctionAttendanceScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 26)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_WIDTH, 1)
    scroll:SetScrollChild(content)
    self.attendanceContent = content
    self.attendanceRows = {}
    self.attendanceSummaryRows = {}

    local scrollBar = _G["EPBossAuctionAttendanceScrollScrollBar"]
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 22, -17)
        scrollBar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 22, 17)
        self:SkinScrollBar(scrollBar)
    end
end

-- ======================
-- Строки таблицы
-- ======================

-- Строка вида "Игроки" по номеру — создаётся при первом обращении и дальше
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

-- Сводная строка (виды "Боссы" и "Дни") по номеру: до 5 текстовых колонок,
-- расположение которых задаёт SUMMARY_LAYOUT для текущего вида.
function auction:GetAttendanceSummaryRow(index)
    local row = self.attendanceSummaryRows[index]
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

    row.cells = {}
    for i = 1, 5 do
        row.cells[i] = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    end

    row:SetScript("OnEnter", function()
        row.bg:SetVertexColor(1, 1, 1, 0.12)
        if row.tooltipLines then
            GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
            GameTooltip:SetText(row.tooltipLines[1])
            for i = 2, #row.tooltipLines do
                GameTooltip:AddLine(row.tooltipLines[i], 0.8, 0.8, 0.8, true)
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function()
        row.bg:SetVertexColor(1, 1, 1, row.baseAlpha)
        GameTooltip:Hide()
    end)
    -- Клик по строке босса открывает посещаемость по этому боссу
    row:SetScript("OnMouseUp", function()
        if row.bossName then
            auction.attendanceBossFilter = row.bossName
            auction.attendanceView = "players"
            auction:RefreshAttendance()
        end
    end)

    self.attendanceSummaryRows[index] = row
    return row
end

-- Заполняет сводную строку значениями по раскладке вида (values — массив текстов).
local function FillSummaryRow(row, view, values)
    local layout = SUMMARY_LAYOUT[view]
    for i = 1, 5 do
        local cell = row.cells[i]
        local spec = layout[i]
        if spec then
            cell:ClearAllPoints()
            cell:SetPoint("LEFT", row, "LEFT", spec.x, 0)
            cell:SetWidth(spec.w)
            cell:SetJustifyH(spec.align or "CENTER")
            cell:SetTextColor(1, 1, 1)
            cell:SetText(values[i] or "")
            cell:Show()
        else
            cell:Hide()
        end
    end
end

-- Прячет строки пула начиная с номера from.
local function HideRowsFrom(rows, from)
    for i = from, #rows do rows[i]:Hide() end
end

-- ======================
-- Тултипы и подтверждения
-- ======================

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
    if rec.manual then GameTooltip:AddLine("Записано вручную", 0.6, 0.8, 1) end
    GameTooltip:AddLine("ПКМ — удалить запись", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

-- Тултип по строке игрока: сколько киллов посетил из скольких, из них на "отдыхе",
-- а при подсчёте по мейнам — какие персонажи учтены.
function auction:ShowAttendancePlayerTooltip(owner, entry)
    if not entry then return end
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
    GameTooltip:SetText(entry.name)
    GameTooltip:AddLine("Был в рейде: "..entry.attended.." из "..entry.total.." ("..entry.pct.."%)", 1, 1, 1)
    if entry.rested > 0 then
        GameTooltip:AddLine("из них «хочу отдохнуть»: "..entry.rested, 0.9, 0.75, 0.2)
    end
    if self.attendanceBossFilter then
        GameTooltip:AddLine("Босс: "..self.attendanceBossFilter, 0.7, 0.7, 0.7)
    end
    if entry.charList then
        GameTooltip:AddLine("Персонажи: "..table.concat(entry.charList, ", "), 0.7, 0.8, 1, true)
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

-- Подтверждение ручной записи килла выбранного босса (с числом игроков в рейде сейчас).
function auction:ConfirmManualAttendance(bossName)
    if not IsInRaid() then
        self:AttendanceSay("Attendance: вы не в рейде — записывать нечего", true)
        return
    end
    StaticPopupDialogs["EPBA_RECORD_ATTENDANCE"] = {
        text = "Записать килл «"..bossName.."» вручную?\nВ рейде сейчас: "..GetNumRaidMembers().." чел.",
        button1 = "Записать", button2 = "Отмена",
        OnAccept = function() auction:RecordAttendanceManual(bossName) end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    StaticPopup_Show("EPBA_RECORD_ATTENDANCE")
end

-- ======================
-- Обновление панели
-- ======================

-- Перерисовывает панель под текущий период, вид, фильтр и режим "по мейнам".
-- Ничего не делает, если панель сейчас не открыта.
function auction:RefreshAttendance()
    local panel = self.attendancePanel
    if not panel or not panel:IsShown() then return end

    local period = self.ATTENDANCE_PERIODS[self.attendancePeriodIndex]
    local view = self.attendanceView

    self.attendancePeriodBtn:SetText("Период: "..period.label)
    self.attendanceViewBtn:SetText("Вид: "..VIEW_LABELS[view])
    SetCheckboxChecked(self.attendanceByMainCheck, self:IsAttendanceByMain())

    -- "Очистить" доступна, только если есть что очищать
    if #(self.attendance or {}) > 0 then
        self.attendanceClearBtn:Enable()
    else
        self.attendanceClearBtn:Disable()
    end

    -- Если выбранного в фильтре босса больше нет ни в одной записи (удалили/очистили) — сбрасываем фильтр
    if self.attendanceBossFilter then
        local found = false
        for _, rec in ipairs(self.attendance or {}) do
            if rec.boss == self.attendanceBossFilter then found = true break end
        end
        if not found then self.attendanceBossFilter = nil end
    end
    UIDropDownMenu_SetText(self.attendanceBossDropdown, self.attendanceBossFilter or "Все боссы")

    -- Фильтр по боссу не имеет смысла в сводке по боссам
    if view == "bosses" then
        self.attendanceBossDropdown:Hide()
    else
        self.attendanceBossDropdown:Show()
    end

    -- Шапка: для "Игроки" — своя, для сводных видов — общая с подписями из раскладки
    if view == "players" then
        self.attendanceHeader:Show()
        self.attendanceSummaryHeader:Hide()
    else
        self.attendanceHeader:Hide()
        self.attendanceSummaryHeader:Show()
        local layout = SUMMARY_LAYOUT[view]
        for i, label in ipairs(self.attendanceSummaryHeader.labels) do
            local spec = layout[i]
            if spec then
                label:ClearAllPoints()
                label:SetPoint("BOTTOMLEFT", self.attendanceSummaryHeader, "BOTTOMLEFT", spec.x, 4)
                label:SetWidth(spec.w)
                label:SetJustifyH(spec.align or "CENTER")
                label:SetText(spec.title)
                label:Show()
            else
                label:Hide()
            end
        end
    end

    local resolver = self:IsAttendanceByMain() and self:GetAttendanceResolver() or nil
    local now = time()
    local isEmpty
    if view == "players" then
        isEmpty = self:RefreshAttendancePlayers(period, now, resolver)
    elseif view == "bosses" then
        isEmpty = self:RefreshAttendanceBosses(period, now, resolver)
    else
        isEmpty = self:RefreshAttendanceDays(period, now, resolver)
    end

    if isEmpty and self.attendanceBossFilter and view ~= "bosses" then
        self.attendanceEmpty:SetText("За этот период нет киллов босса «"..self.attendanceBossFilter.."».\nВыберите другой период или «Все боссы».")
        self.attendanceEmpty:Show()
    elseif isEmpty then
        self.attendanceEmpty:SetText("За этот период записей нет.\nКилл записывается при ПКМ по «Очистить таблицу»\n(ответ «Записать») или кнопкой «Записать килл».")
        self.attendanceEmpty:Show()
    else
        self.attendanceEmpty:Hide()
    end
end

-- Вид "Игроки". Возвращает true, если за период нет киллов.
function auction:RefreshAttendancePlayers(period, now, resolver)
    local report = self:BuildAttendanceReport(self.attendance or {}, now, period.days, self.ATTENDANCE_COLUMNS, self.attendanceBossFilter, resolver)
    self.attendanceReport = report
    self.attendanceViewData = {
        view = "players", data = report,
        info = { periodLabel = period.label, bossFilter = self.attendanceBossFilter, byMain = resolver ~= nil, total = report.total },
    }
    self.attendanceInfo:SetText("Киллов: "..report.total)
    self.attendanceLegend:SetText("|cff4de64d+|r в рейде    |cffe6bf33О|r в рейде, но «хочу отдохнуть»    |cff666666-|r не было    |cff888888ПКМ по дате — удалить запись|r")

    for i = 1, self.ATTENDANCE_COLUMNS do
        local hb = self.attendanceHeaderButtons[i]
        local rec = report.columns[i]
        hb.record = rec
        if rec then
            hb.text:SetText(date("%d.%m", rec.t).."\n"..(rec.boss and self.Utf8Prefix(rec.boss, 5) or "-"))
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
    HideRowsFrom(self.attendanceRows, count + 1)
    HideRowsFrom(self.attendanceSummaryRows, 1)
    self.attendanceContent:SetHeight(math.max(1, count * ROW_HEIGHT))
    return report.total == 0
end

-- Вид "Боссы": по строке на босса. Возвращает true, если данных нет.
function auction:RefreshAttendanceBosses(period, now, resolver)
    local list = self:BuildBossSummary(self.attendance or {}, now, period.days, resolver)
    self.attendanceViewData = {
        view = "bosses", data = list,
        info = { periodLabel = period.label, byMain = resolver ~= nil },
    }
    self.attendanceInfo:SetText("Боссов: "..#list)
    self.attendanceLegend:SetText("|cff888888Клик по строке — посещаемость по этому боссу|r")

    for i, item in ipairs(list) do
        local row = self:GetAttendanceSummaryRow(i)
        row.bossName = item.boss
        row.tooltipLines = nil
        FillSummaryRow(row, "bosses", {
            Truncate(item.boss, 30), item.kills, string.format("%.1f", item.avgPlayers),
            item.uniquePlayers, date("%d.%m.%Y", item.lastT),
        })
        row:Show()
    end
    HideRowsFrom(self.attendanceSummaryRows, #list + 1)
    HideRowsFrom(self.attendanceRows, 1)
    self.attendanceContent:SetHeight(math.max(1, #list * ROW_HEIGHT))
    return #list == 0
end

-- Вид "Дни": по строке на рейд-день (новые сверху), с учётом фильтра по боссу.
-- Возвращает true, если данных нет.
function auction:RefreshAttendanceDays(period, now, resolver)
    local list = self:BuildDaySummary(self.attendance or {}, now, period.days, self.attendanceBossFilter, resolver)
    self.attendanceViewData = {
        view = "days", data = list,
        info = { periodLabel = period.label, bossFilter = self.attendanceBossFilter, byMain = resolver ~= nil },
    }
    self.attendanceInfo:SetText("Дней: "..#list)
    self.attendanceLegend:SetText("|cff888888Игроков — сколько разных людей было хотя бы на одном килле в этот день|r")

    for i, item in ipairs(list) do
        local row = self:GetAttendanceSummaryRow(i)
        row.bossName = nil
        row.tooltipLines = { date("%d.%m.%Y", item.t), table.concat(item.bosses, ", ") }
        FillSummaryRow(row, "days", {
            date("%d.%m.%Y", item.t), item.kills, item.uniquePlayers,
            string.format("%.1f", item.avgPlayers), Truncate(table.concat(item.bosses, ", "), 38),
        })
        row:Show()
    end
    HideRowsFrom(self.attendanceSummaryRows, #list + 1)
    HideRowsFrom(self.attendanceRows, 1)
    self.attendanceContent:SetHeight(math.max(1, #list * ROW_HEIGHT))
    return #list == 0
end

-- ======================
-- Окно с текстом отчёта
-- ======================

-- Показывает окно с текстом отчёта по текущему виду (CSV с разделителем ";"):
-- текст сразу выделен, остаётся нажать Ctrl+C и вставить в Discord/Excel/форум.
function auction:ShowAttendanceReportWindow()
    local d = self.attendanceViewData
    if not d then return end
    local text = self:BuildAttendanceReportText(d.view, d.data, d.info)

    local frame = self.attendanceReportFrame
    if not frame then
        local c = self.theme.colors
        frame = CreateFrame("Frame", "EPBossAuctionAttendanceReportFrame", UIParent)
        frame:SetSize(560, 400)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        self:SkinPanel(frame)
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -14)
        title:SetText("Отчёт Attendance")
        title:SetTextColor(c.accent[1], c.accent[2], c.accent[3])

        local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
        hint:SetText("Текст выделен: Ctrl+C — скопировать, Esc — закрыть")
        hint:SetTextColor(0.7, 0.7, 0.7)

        local scroll = CreateFrame("ScrollFrame", "EPBossAuctionAttendanceReportScroll", frame, "UIPanelScrollFrameTemplate")
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

        self.attendanceReportFrame = frame
    end

    frame.edit:SetText(text)
    frame:Show()
    frame.edit:HighlightText()
    frame.edit:SetFocus()
end
