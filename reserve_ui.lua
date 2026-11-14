local auction = EPBossAuction

-- ============================================================
-- reserve_ui.lua — вкладка «Резерв»: интерфейс
-- ============================================================
-- Данные, правила и сеть — в reserve.lua. Вкладку (как и Attendance) видят только
-- те, кто может редактировать офицерскую заметку (HasReserveAccess).
--
-- Панель занимает ту же область, что левая панель и таблица ставок вместе.
-- Сверху два ряда:
--   ряд 1: выбор босса (подземелье → босс) | вид (босс / все резервы) | счётчик;
--   ряд 2: поле для ссылок + «Добавить» | Синхронизировать | Снять все.
-- Ниже таблица. Строка = предмет:
--   клик по названию — зарезервировать (1 копия) / снять;
--   «−» / «+» — число проданных копий (выдали покупателю — нажмите «−»;
--               на 0 резерв снимается и предмет снова открыт для ставок);
--   поле справа — заметка о покупателе (сохраняется по Enter или при уходе из поля);
--   «x» — снять резерв целиком.
-- Вид «босс» показывает все предметы выбранного босса, «все резервы» —
-- только зарезервированные, по всем боссам.
-- Хелперы стиля (кнопка/выпадающий список) берутся из attendance_ui.lua (auction.uiHelpers).
-- ============================================================

local ROW_H = 20
local HEADER_Y = -62
local CONTENT_WIDTH = 590
local NAME_X, NAME_W = 6, 262
local QTY_X = 276            -- «−» (16 px), число (28 px), «+» (16 px)
local NOTE_X, NOTE_W = 346, 170
local DEL_X = 524

local VIEW_LABELS = { boss = "Вид: босс", all = "Вид: все резервы" }

auction.reserveView = "boss"     -- "boss" | "all" (только на время сессии)
auction.reserveBoss = nil        -- босс для вида "boss"
auction.reserveRows = {}

-- Маленькая кнопка внутри строки (16 px высотой).
local function SmallButton(parent, text, width, x, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 16)
    b:SetPoint("LEFT", parent, "LEFT", x, 0)
    b:SetText(text)
    b:SetNormalFontObject(GameFontNormal)
    auction:SkinButton(b)
    b:SetScript("OnClick", onClick)
    return b
end

-- ======================
-- Панель
-- ======================

function auction:CreateReservePanel(frame)
    local H = self.uiHelpers
    local panel = CreateFrame("Frame", "EPBossAuctionReservePanel", frame)
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
    self.reservePanel = panel

    -- ---- Ряд 1 ----
    -- Выбор босса: Подземелье → Босс
    local bossDropdown = H.MakeDropdown(panel, "EPBossAuctionReserveBossDropdown", 190, 6, -5, "Выберите босса ...")
    UIDropDownMenu_Initialize(bossDropdown, function(_, level)
        H.LockDropdownHeight(bossDropdown)
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
                    auction.reserveBoss = bossName
                    auction.reserveView = "boss"
                    auction:RefreshReserve()
                end
                UIDropDownMenu_AddButton(info, 2)
            end
        end
    end)
    H.LockDropdownHeight(bossDropdown)
    self:SkinDropdown(bossDropdown)
    self.reserveBossDropdown = bossDropdown

    self.reserveViewBtn = H.MakeButton(self, panel, "Вид", 130, 270, -6, function()
        auction.reserveView = (auction.reserveView == "boss") and "all" or "boss"
        auction:RefreshReserve()
    end)

    local info = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    info:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -11)
    info:SetJustifyH("RIGHT")
    info:SetTextColor(0.7, 0.7, 0.7)
    self.reserveInfo = info

    -- ---- Ряд 2 ----
    -- Поле для ссылок: Shift+клик по предмету (из чата, окна лута и т.п.) вставляет ссылку,
    -- можно и просто набрать id предмета.
    local edit = CreateFrame("EditBox", "EPBossAuctionReserveLinkEdit", panel)
    edit:SetSize(230, 22)
    edit:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -33)
    edit:SetAutoFocus(false)
    edit:SetFontObject(GameFontHighlightSmall)
    edit:SetTextInsets(6, 6, 0, 0)
    edit:SetMaxLetters(500)
    self:SkinInput(edit)
    local hint = edit:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("LEFT", edit, "LEFT", 6, 0)
    hint:SetTextColor(0.5, 0.5, 0.5)
    hint:SetText("Shift+клик по предмету или id")
    local function UpdateHint()
        if edit:GetText() == "" and not edit:HasFocus() then hint:Show() else hint:Hide() end
    end
    edit:SetScript("OnTextChanged", UpdateHint)
    edit:HookScript("OnEditFocusGained", UpdateHint)
    edit:HookScript("OnEditFocusLost", UpdateHint)
    edit:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    self.reserveLinkEdit = edit

    local function DoAdd()
        local text = edit:GetText()
        if text == "" then return end
        if auction:AddReservesFromText(text, auction.reserveBoss) > 0 then
            edit:SetText("")
            edit:ClearFocus()
        end
    end
    edit:SetScript("OnEnterPressed", DoAdd)
    self.reserveAddBtn = H.MakeButton(self, panel, "Добавить", 78, 242, -34, DoAdd)

    -- Shift+клик по ссылке, пока курсор в нашем поле, вставляет её сюда.
    -- hooksecurefunc безопасен для защищённого кода. Побочный эффект: при Shift+клике по
    -- стаку в сумке WoW может параллельно начать разделение стака — берите ссылки из чата.
    if hooksecurefunc and ChatEdit_InsertLink and not self._reserveLinkHooked then
        self._reserveLinkHooked = true
        hooksecurefunc("ChatEdit_InsertLink", function(link)
            local e = auction.reserveLinkEdit
            if link and e and e:IsVisible() and e:HasFocus() then e:Insert(link) end
        end)
    end

    self.reserveSyncBtn = H.MakeButton(self, panel, "Синхронизировать", 118, 326, -34, function()
        auction:StartReserveSync(false)
    end)
    self.reserveClearBtn = H.MakeButton(self, panel, "Снять все", 80, 450, -34, function()
        auction:ConfirmClearReserves()
    end)

    -- ---- Таблица ----
    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, HEADER_Y)
    header:SetSize(CONTENT_WIDTH, 32)
    local function HeaderLabel(text, x, w, align)
        local l = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", x, 4)
        l:SetWidth(w)
        l:SetJustifyH(align or "LEFT")
        l:SetText(text)
    end
    HeaderLabel("Предмет", NAME_X, NAME_W)
    HeaderLabel("Копий", QTY_X, 60, "CENTER")
    HeaderLabel("Покупатель (заметка)", NOTE_X, NOTE_W)

    local scroll = CreateFrame("ScrollFrame", "EPBossAuctionReserveScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 26)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_WIDTH, 1)
    scroll:SetScrollChild(content)
    self.reserveContent = content
    local scrollBar = _G["EPBossAuctionReserveScrollScrollBar"]
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
    self.reserveEmpty = empty

    local legend = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    legend:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 8)
    legend:SetTextColor(0.6, 0.6, 0.6)
    legend:SetText("Клик по предмету — резерв вкл/выкл. Зарезервированное закрыто для ставок у всего рейда; список в рейд рассылает ЛМ.")
end

-- ======================
-- Строки
-- ======================

-- Строка по номеру: создаётся при первом обращении и переиспользуется.
function auction:GetReserveRow(index)
    local row = self.reserveRows[index]
    if row then return row end

    local content = self.reserveContent
    row = CreateFrame("Frame", nil, content)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(index - 1) * ROW_H)

    row.baseAlpha = (index % 2 == 0) and 0.05 or 0
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:SetTexture("Interface\\Buttons\\WHITE8x8")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", row, "LEFT", NAME_X, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.name:SetWidth(NAME_W - 26)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- Кликабельная область названия: клик — вкл/выкл резерв, наведение — тултип предмета
    local nameBtn = CreateFrame("Button", nil, row)
    nameBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    nameBtn:SetSize(NAME_X + NAME_W, ROW_H)
    nameBtn:SetScript("OnClick", function()
        if not row.boss then return end
        local qty = auction:GetReserveQty(row.boss, row.itemID)
        auction:SetReserve(row.boss, row.itemID, qty > 0 and 0 or 1)
    end)
    nameBtn:SetScript("OnEnter", function()
        if not row.itemID then return end
        GameTooltip:SetOwner(nameBtn, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:"..row.itemID)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Клик — зарезервировать / снять", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    nameBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.minus = SmallButton(row, "-", 16, QTY_X, function()
        local qty = auction:GetReserveQty(row.boss, row.itemID)
        if qty > 0 then auction:SetReserve(row.boss, row.itemID, qty - 1) end
    end)
    row.qty = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.qty:SetPoint("LEFT", row, "LEFT", QTY_X + 16, 0)
    row.qty:SetWidth(28)
    row.qty:SetJustifyH("CENTER")
    row.plus = SmallButton(row, "+", 16, QTY_X + 44, function()
        local qty = auction:GetReserveQty(row.boss, row.itemID)
        auction:SetReserve(row.boss, row.itemID, qty + 1)
    end)

    local edit = CreateFrame("EditBox", nil, row)
    edit:SetSize(NOTE_W, 16)
    edit:SetPoint("LEFT", row, "LEFT", NOTE_X, 0)
    edit:SetAutoFocus(false)
    edit:SetFontObject(GameFontHighlightSmall)
    edit:SetTextInsets(4, 4, 0, 0)
    edit:SetMaxLetters(auction.RESERVE_NOTE_LEN)
    auction:SkinInput(edit)
    local function Commit()
        if not row.boss then return end
        local e = auction:GetReserveEntry(row.boss, row.itemID)
        if not e or e.qty <= 0 then return end
        if auction.CleanReserveNote(edit:GetText()) ~= (e.note or "") then
            auction:SetReserve(row.boss, row.itemID, e.qty, edit:GetText())
        end
    end
    edit:SetScript("OnEnterPressed", function(box) Commit() box:ClearFocus() end)
    edit:SetScript("OnEscapePressed", function(box)
        local e = row.boss and auction:GetReserveEntry(row.boss, row.itemID)
        box:SetText(e and e.note or "")
        box:ClearFocus()
    end)
    edit:HookScript("OnEditFocusLost", Commit)
    row.note = edit

    row.del = SmallButton(row, "x", 18, DEL_X, function()
        auction:SetReserve(row.boss, row.itemID, 0)
    end)

    self.reserveRows[index] = row
    return row
end

-- Заполняет строку по (босс, предмет). Возвращает true, если данные предмета ещё не подгрузились.
function auction:FillReserveRow(row, boss, itemID, showBoss)
    row.boss, row.itemID = boss, itemID
    local qty = self:GetReserveQty(boss, itemID)
    local entry = self:GetReserveEntry(boss, itemID)

    local name, icon = self:GetCachedItemInfo(itemID)
    local pending = not name
    name = name or "Загрузка..."
    if showBoss then
        name = "|cff888888"..self.Utf8Prefix(boss, 12).."|r "..name
    end
    row.name:SetText(name)
    if icon then
        row.icon:SetTexture(icon)
        row.icon:Show()
    else
        row.icon:Hide()
    end

    if qty > 0 then
        row.name:SetTextColor(0.80, 0.62, 0.10)
        row.bg:SetVertexColor(0.80, 0.62, 0.10, 0.14)
        row.qty:SetText(tostring(qty))
        row.qty:SetTextColor(1, 1, 1)
        row.minus:Enable()
        row.del:Enable()
        row.note:Show()
        if not row.note:HasFocus() then row.note:SetText(entry and entry.note or "") end
    else
        row.name:SetTextColor(0.75, 0.75, 0.75)
        row.bg:SetVertexColor(1, 1, 1, row.baseAlpha)
        row.qty:SetText("-")
        row.qty:SetTextColor(0.4, 0.4, 0.4)
        row.minus:Disable()
        row.del:Disable()
        row.note:Hide()
    end
    row:Show()
    return pending
end

-- ======================
-- Обновление
-- ======================

-- Перерисовывает вкладку (ничего не делает, если она не открыта).
function auction:RefreshReserve()
    local panel = self.reservePanel
    if not panel or not panel:IsShown() then return end

    self.reserveViewBtn:SetText(VIEW_LABELS[self.reserveView])
    UIDropDownMenu_SetText(self.reserveBossDropdown, self.reserveBoss or "Выберите босса ...")

    -- Список (босс, предмет) по текущему виду
    local list = {}
    if self.reserveView == "boss" then
        if self.reserveBoss and self.bosses[self.reserveBoss] then
            local seen = {}
            for _, itemID in ipairs(self.bosses[self.reserveBoss]) do
                if not seen[itemID] then
                    seen[itemID] = true
                    list[#list + 1] = { boss = self.reserveBoss, itemID = itemID }
                end
            end
        end
    else
        for _, instanceName in ipairs(self.instanceOrder or {}) do
            for _, boss in ipairs(self.instances[instanceName] or {}) do
                local items = self.reserves[boss]
                if items and self.bosses[boss] then
                    local seen = {}
                    for _, itemID in ipairs(self.bosses[boss]) do
                        local e = items[itemID]
                        if e and e.qty > 0 and not seen[itemID] then
                            seen[itemID] = true
                            list[#list + 1] = { boss = boss, itemID = itemID }
                        end
                    end
                end
            end
        end
    end

    local needDelayed = false
    for i, entry in ipairs(list) do
        local row = self:GetReserveRow(i)
        if self:FillReserveRow(row, entry.boss, entry.itemID, self.reserveView == "all") then
            needDelayed = true
        end
    end
    for i = #list + 1, #self.reserveRows do
        self.reserveRows[i]:Hide()
        self.reserveRows[i].boss = nil
    end
    self.reserveContent:SetHeight(math.max(1, #list * ROW_H))

    if #list == 0 then
        if self.reserveView == "all" then
            self.reserveEmpty:SetText("Резервов пока нет.\nВыберите босса и кликните по предмету или вставьте ссылки в поле выше.")
        elseif not self.reserveBoss then
            self.reserveEmpty:SetText("Выберите босса в списке слева сверху.")
        else
            self.reserveEmpty:SetText("Для этого босса ещё не добавлены предметы.")
        end
        self.reserveEmpty:Show()
    else
        self.reserveEmpty:Hide()
    end

    local positions, copies = self:CountActiveReserves()
    self.reserveInfo:SetText("Резервов: "..positions.." (копий: "..copies..")")
    if positions > 0 then self.reserveClearBtn:Enable() else self.reserveClearBtn:Disable() end

    -- Предметы, которых клиент ещё не знает, подгружаются не сразу — перерисуем чуть позже.
    if needDelayed and not self.reserveInfoTimer then
        self.reserveInfoTimer = self:ScheduleTimer(function()
            self.reserveInfoTimer = nil
            self:RefreshReserve()
        end, 0.5)
    end
end

-- Подтверждение «Снять все».
function auction:ConfirmClearReserves()
    local positions = self:CountActiveReserves()
    StaticPopupDialogs["EPBA_CLEAR_RESERVES"] = {
        text = "Снять все резервы ("..positions.." поз.)?\nПредметы снова откроются для ставок.",
        button1 = "Снять", button2 = "Отмена",
        OnAccept = function() auction:ClearAllReserves() end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    StaticPopup_Show("EPBA_CLEAR_RESERVES")
end
