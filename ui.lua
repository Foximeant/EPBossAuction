local auction = EPBossAuction

-- ======================
-- Создание основного окна (НОВЫЙ МАКЕТ: левая панель + таблица справа)
-- ======================
function auction:CreateUI()
    local frame = CreateFrame("Frame", "EPBossAuctionFrame", UIParent)
    frame:SetSize(self.db.window.width, self.db.window.height)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        tile=true, tileSize=32, edgeSize=32,
        insets={left=8, right=8, top=8, bottom=8}
    })
    frame:SetBackdropColor(0,0,0,1)
    frame:SetAlpha(self.db.window.alpha)
    frame:SetMovable(not self.db.window.locked)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(self, delta)
        if IsControlKeyDown() then
            if delta > 0 then
                auction:ZoomIn()
            else
                auction:ZoomOut()
            end
        end
    end)
    frame:Hide()
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    tinsert(UISpecialFrames, "EPBossAuctionFrame")
    self.frame = frame

    -- Заголовок окна
    local title = frame:CreateFontString("EPBossAuctionTitle", "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("RS EPBossAuction 1.5.3")

    -- Кнопка закрытия
    local close = CreateFrame("Button", "EPBossAuctionCloseButton", frame, "UIPanelCloseButton")
    self.closeButton = close
    close:SetPoint("TOPRIGHT", -5, -5)

    -- Кнопка настроек
    local optionsBtn = CreateFrame("Button", "EPBossAuctionOptionsButton", frame, "UIPanelButtonTemplate")
    optionsBtn:SetSize(18, 18)
    optionsBtn:SetPoint("TOPRIGHT", close, "TOPLEFT", -5, -7)
    local tex = optionsBtn:CreateTexture(nil, "OVERLAY")
    tex:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    tex:SetSize(20, 20)
    tex:SetPoint("CENTER")
    optionsBtn:SetScript("OnClick", function()
        InterfaceOptionsFrame_OpenToCategory("EP Boss Auction")
    end)
    optionsBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(optionsBtn, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Настройки")
        GameTooltip:AddLine("Открыть окно настроек аддона", 0.5, 1, 0.5)
        GameTooltip:Show()
    end)
    optionsBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    self.optionsBtn = optionsBtn

    -- ======================
    -- ЛЕВАЯ ПАНЕЛЬ УПРАВЛЕНИЯ
    -- ======================
    local leftPanel = CreateFrame("Frame", "EPBossAuctionLeftPanel", frame)
    leftPanel:SetWidth(160)
    leftPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -45)
    leftPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 16)
    leftPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    leftPanel:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    leftPanel:SetBackdropBorderColor(0,0,0,1)
    self.leftPanel = leftPanel

    -- 1. Выбор босса
    local bossLabel = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bossLabel:SetPoint("TOPLEFT", 10, -10)
    bossLabel:SetText("Босс:")
    local dropdown = CreateFrame("Frame", "EPBossDropdown", leftPanel, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", bossLabel, "BOTTOMLEFT", -26, -5)
    UIDropDownMenu_SetWidth(dropdown, 140)
    UIDropDownMenu_SetText(dropdown, "Выбрать босса")
    UIDropDownMenu_Initialize(dropdown, function(selfDD, level)
        for _, bossName in ipairs(auction.bossOrder) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = bossName
            info.func = function()
                auction.selectedBoss = bossName
                auction.selectedItem = nil
                UIDropDownMenu_SetText(dropdown, bossName)
                UIDropDownMenu_SetText(auction.itemDropdown, "Выбрать предмет")
                auction:RefreshTable()
            end
            info.checked = (auction.selectedBoss == bossName)
            UIDropDownMenu_AddButton(info)
        end
    end)
    self.bossDropdown = dropdown

    -- 2. Выбор предмета
    local itemLabel = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemLabel:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 26, -15)
    itemLabel:SetText("Предмет:")
    local itemDrop = CreateFrame("Frame", "EPItemDropdown", leftPanel, "UIDropDownMenuTemplate")
    itemDrop:SetPoint("TOPLEFT", itemLabel, "BOTTOMLEFT", -26, -5)
    UIDropDownMenu_SetWidth(itemDrop, 140)
    UIDropDownMenu_SetText(itemDrop, "Выбрать предмет")
    self.itemDropdown = itemDrop

    -- 3. Поле ввода ставки
    local bidLabel = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bidLabel:SetPoint("TOPLEFT", itemDrop, "BOTTOMLEFT", 26, -15)
    bidLabel:SetText("Сумма ставки:")
    local editBox = CreateFrame("EditBox", "EPBidEditBox", leftPanel, "InputBoxTemplate")
    editBox:SetSize(135, 25)
    editBox:SetPoint("TOPLEFT", bidLabel, "BOTTOMLEFT", 5, -5)
    editBox:SetAutoFocus(false)
    editBox:SetNumeric(true)
    editBox:SetMaxLetters(6)
    editBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        if #text > 6 then
            self:SetText(string.sub(text, 1, 6))
            self:SetCursorPosition(6)
        end
        local amount = tonumber(text) or 0
        local isOffspec = auction.offspecCheckbox and auction.offspecCheckbox:GetChecked() or false
        local maxBid = auction:GetMaxBidAmount(isOffspec)
        if amount > 0 and amount > maxBid then
            self:SetTextColor(1, 0, 0)
            auction.myEPText:SetTextColor(1, 0, 0)
            if auction.maxBidText then
                auction.maxBidText:SetTextColor(1, 0, 0)
            end
        else
            self:SetTextColor(1, 1, 1)
            auction.myEPText:SetTextColor(1, 1, 1)
            if auction.maxBidText then
                auction.maxBidText:SetTextColor(0.7, 0.7, 0.7)
            end
        end
    end)
    editBox:SetScript("OnEnterPressed", function()
        auction:SendBidLocal()
    end)
    self.bidBox = editBox

    -- 4. Кнопка "Сделать ставку"
    local button = CreateFrame("Button", "EPBossAuctionBidButton", leftPanel, "UIPanelButtonTemplate")
    self.bidButton = button
    button:SetSize(140, 25)
    button:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", -5, -8)
    button:SetText("Сделать ставку")
    button:SetScript("OnClick", function()
        auction:SendBidLocal()
    end)

    -- 5. Чекбоксы
    local lockCheckbox = CreateFrame("CheckButton", "EPBossAuctionLockCheckbox", leftPanel, "UICheckButtonTemplate")
    lockCheckbox:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -12)
    lockCheckbox:SetSize(20, 20)
    local lockText = lockCheckbox:CreateFontString("EPBossAuctionLockCheckboxText", "OVERLAY", "GameFontNormal")
    lockText:SetPoint("LEFT", lockCheckbox, "RIGHT", 2, 0)
    lockText:SetText("Блок")
    lockCheckbox:SetChecked(self.bidsLocked or false)
    lockCheckbox.text = lockText
    if not self:IsLootMaster() then
        lockCheckbox:Disable()
        lockCheckbox:SetAlpha(0.5)
    else
        lockCheckbox:SetScript("OnClick", function(self)
            local checked = self:GetChecked()
            local state = (checked == 1)
            auction:SetBidsLocked(state)
            SendAddonMessage(auction.prefix, "LOCK;"..(state and "true" or "false"), "RAID")
        end)
    end
    self.lockCheckbox = lockCheckbox

    local offspecCheckbox = CreateFrame("CheckButton", "EPBossAuctionOffspecCheckbox", leftPanel, "UICheckButtonTemplate")
    offspecCheckbox:SetPoint("LEFT", lockCheckbox, "RIGHT", 35, 0)
    offspecCheckbox:SetSize(20, 20)
    local offspecText = offspecCheckbox:CreateFontString("EPBossAuctionOffspecCheckboxText", "OVERLAY", "GameFontNormal")
    offspecText:SetPoint("LEFT", offspecCheckbox, "RIGHT", 2, 0)
    offspecText:SetText("Офф-спек")
    offspecCheckbox:SetChecked(false)
    offspecCheckbox:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        if auction.myEP > 0 then
            auction:UpdateMaxBidDisplay()
        end
        local amount = tonumber(auction.bidBox:GetText()) or 0
        local maxBid = auction:GetMaxBidAmount(checked)
        if amount > 0 and amount > maxBid then
            auction.bidBox:SetTextColor(1, 0, 0)
        else
            auction.bidBox:SetTextColor(1, 1, 1)
        end
    end)
    self.offspecCheckbox = offspecCheckbox

    -- 6. Кнопка "Запросить"
    local requestButton = CreateFrame("Button", "EPBossAuctionRequestButton", leftPanel, "UIPanelButtonTemplate")
    self.requestButton = requestButton
    requestButton:SetSize(140, 25)
    requestButton:SetPoint("TOPLEFT", lockCheckbox, "BOTTOMLEFT", 0, -12)
    requestButton:SetText("Запросить данные")
    requestButton:SetScript("OnClick", function()
        auction:RequestDataFromLM()
    end)

    -- 7. Кнопка "Очистить таблицу"
    local endButton = CreateFrame("Button", "EPBossAuctionEndButton", leftPanel, "UIPanelButtonTemplate")
    endButton:SetSize(140, 25)
    endButton:SetPoint("TOPLEFT", requestButton, "BOTTOMLEFT", 0, -8)
    endButton:SetText("Очистить таблицу")
    endButton:SetScript("OnClick", function()
        if not auction:IsLootMaster() then return end
        auction:EndAuctionLocal()
        if auction.selectedBoss then
            SendAddonMessage(auction.prefix, "END;"..auction.selectedBoss, "RAID")
        end
    end)
    self.endButton = endButton

    -- 8. Кнопка "Журнал"
    local journalButton = CreateFrame("Button", "EPBossAuctionJournalButton", leftPanel, "UIPanelButtonTemplate")
    journalButton:SetSize(140, 25)
    journalButton:SetPoint("TOPLEFT", endButton, "BOTTOMLEFT", 0, -8)
    journalButton:SetText("Журнал ставок")
    journalButton:SetScript("OnClick", function()
        auction:ToggleJournal()
    end)
    self.journalButton = journalButton

    -- 9. Текст "Ваш ЕП"
    local epText = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    epText:SetPoint("TOPLEFT", journalButton, "BOTTOMLEFT", 0, -15)
    epText:SetText("Ваш ЕП: ...")
    auction.myEPText = epText

    -- 10. Текст максимальной ставки
    local maxBidText = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    maxBidText:SetPoint("TOPLEFT", epText, "BOTTOMLEFT", 0, -2)
    maxBidText:SetText("Макс. ставка: ...")
    maxBidText:SetTextColor(0.7, 0.7, 0.7)
    auction.maxBidText = maxBidText

    -- ======================
    -- ПРАВАЯ ОБЛАСТЬ – ТАБЛИЦА (скроллфрейм) с фоном
    -- ======================
    local scrollBG = CreateFrame("Frame", "EPBossAuctionScrollBG", frame)
    scrollBG:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    scrollBG:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    scrollBG:SetBackdropBorderColor(0,0,0,1)
    self.scrollBG = scrollBG

    local scrollFrame = CreateFrame("ScrollFrame", "EPBossAuctionScrollFrame", frame, "UIPanelScrollFrameTemplate")
    self.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(content)
    self.content = content

    -- Кнопка для растягивания окна
    local sizer = CreateFrame("Button", "EPBossAuctionSizer", frame)
    sizer:SetSize(20, 20)
    sizer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    local sizerHighlight = sizer:CreateTexture(nil, "OVERLAY")
    sizerHighlight:SetTexture("Interface\\Buttons\\WHITE8x8")
    sizerHighlight:SetVertexColor(1, 0.8, 0, 0)
    sizerHighlight:SetAllPoints()
    sizer.highlight = sizerHighlight
    local sizerTexture = sizer:CreateTexture(nil, "BACKGROUND")
    sizerTexture:SetSize(16, 16)
    sizerTexture:SetPoint("CENTER")
    sizerTexture:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
    sizerTexture:SetTexCoord(0.05, 0.5, 0.05, 0.5, 0.05, 0.5, 0.5, 0.5)
    sizer:SetScript("OnEnter", function(self)
        if self.highlight then
            self.highlight:SetVertexColor(1, 0.8, 0, 0.3)
        end
    end)
    sizer:SetScript("OnLeave", function(self)
        if self.highlight then
            self.highlight:SetVertexColor(1, 0.8, 0, 0)
        end
    end)
    sizer:SetScript("OnMouseDown", function(self)
        self:GetParent():StartSizing("BOTTOMRIGHT")
        if self.highlight then
            self.highlight:SetVertexColor(1, 0.5, 0, 0.5)
        end
    end)
    sizer:SetScript("OnMouseUp", function(self)
        self:GetParent():StopMovingOrSizing()
        if self.highlight then
            self.highlight:SetVertexColor(1, 0.8, 0, 0.3)
        end
        local frame = self:GetParent()
        auction.db.window.width = frame:GetWidth()
        auction.db.window.height = frame:GetHeight()
        auction:SaveSettings()
        auction:RefreshTable()
    end)
    self.sizer = sizer

    frame:SetResizable(true)
    frame:SetMinResize(650, 450)
    frame:SetMaxResize(1200, 900)

    frame:SetScript("OnSizeChanged", function()
        if auction.resizeTimer then
            auction.resizeTimer:Cancel()
            auction.resizeTimer = nil
        end
        auction.resizeTimer = auction:ScheduleTimer(function()
            if auction.frame and auction.frame:IsShown() then
                auction:UpdateScrollFrameSize()
                auction:RefreshTable()
            end
            auction.resizeTimer = nil
        end, 0.05)
    end)

    -- Обновляем позиционирование левой панели и скроллфрейма
    local function updateLayout()
        if not auction.frame then return end
        -- скроллфрейм привязываем к правой стороне левой панели и к низу окна
        auction.scrollFrame:ClearAllPoints()
        auction.scrollFrame:SetPoint("TOPLEFT", auction.leftPanel, "TOPRIGHT", 10, 0)
        auction.scrollFrame:SetPoint("BOTTOMRIGHT", auction.frame, "BOTTOMRIGHT", -16, 16)
        -- фон скроллфрейма занимает ту же область
        auction.scrollBG:ClearAllPoints()
        auction.scrollBG:SetPoint("TOPLEFT", auction.scrollFrame, "TOPLEFT", -2, 2)
        auction.scrollBG:SetPoint("BOTTOMRIGHT", auction.scrollFrame, "BOTTOMRIGHT", 2, -2)
        auction:RefreshTable()
    end

    frame:HookScript("OnSizeChanged", updateLayout)
    updateLayout()
    -- Корректировка положения скроллбара
    local scrollBar = _G["EPBossAuctionScrollFrameScrollBar"]
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", self.scrollFrame, "TOPRIGHT", 2, -17)
        scrollBar:SetPoint("BOTTOMRIGHT", self.scrollFrame, "BOTTOMRIGHT", 2, 17)
    end
    self:UpdateLMButtonsState()

    -- Slash команды
    SLASH_EPBA1 = "/epba"
    SlashCmdList["EPBA"] = function()
        if frame:IsShown() then frame:Hide() else frame:Show(); auction:ForceEPUpdate() end
    end
    SLASH_EPGP_FIND1 = "/epgpfind"
    SlashCmdList["EPGP_FIND"] = function()
        auction:FindEPGP()
    end
    SLASH_EPBA_SAVE1 = "/epbasave"
    SlashCmdList["EPBA_SAVE"] = function()
        auction:ForceSave()
    end
    SLASH_EPBA_UPDATE1 = "/epbaupdate"
    SlashCmdList["EPBA_UPDATE"] = function()
        auction:ForceEPUpdate(function(success, ep)
            if success then
                --print("|cff00ff00[EPBA]|r EP обновлен: "..auction:FormatNumber(ep))
            else
                --print("|cffff0000[EPBA]|r Не удалось обновить EP")
            end
        end)
    end
    SLASH_EPBA_ZOOM_IN1 = "/epbazoom+"
    SlashCmdList["EPBA_ZOOM_IN"] = function()
        auction:ZoomIn()
        print("|cff00ff00[EPBA]|r Масштаб: "..math.floor(auction.windowScale * 100).."%")
    end
    SLASH_EPBA_ZOOM_OUT1 = "/epbazoom-"
    SlashCmdList["EPBA_ZOOM_OUT"] = function()
        auction:ZoomOut()
        print("|cff00ff00[EPBA]|r Масштаб: "..math.floor(auction.windowScale * 100).."%")
    end
    SLASH_EPBA_ZOOM_RESET1 = "/epbazoomreset"
    SlashCmdList["EPBA_ZOOM_RESET"] = function()
        auction:ResetZoom()
        print("|cff00ff00[EPBA]|r Масштаб сброшен до 100%")
    end
    SLASH_EPBA_OPTIONS1 = "/epbaoptions"
    SlashCmdList["EPBA_OPTIONS"] = function()
        InterfaceOptionsFrame_OpenToCategory("EP Boss Auction")
    end
    SLASH_EPBA_OFFSPEC1 = "/epbaoffspec"
    SlashCmdList["EPBA_OFFSPEC"] = function(value)
        if not auction:IsLootMaster() then
            print("|cffff0000[EPBA]|r Только Loot Master может изменять коэффициент офф-спек.")
            return
        end
        local multiplier = tonumber(value)
        if not multiplier or multiplier < 0.1 or multiplier > 1.0 then
            print("|cffff0000[EPBA]|r Использование: /epbaoffspec <0.1-1.0> (например: /epbaoffspec 0.5)")
            return
        end
        auction.offspecMultiplier = multiplier
        print("|cff00ff00[EPBA]|r Коэффициент офф-спек установлен на " .. (multiplier * 100) .. "%")
        SendAddonMessage(auction.prefix, "OFFSPEC_MULT;" .. multiplier, "RAID")
    end

    frame:SetScript("OnShow", function()
        auction:ForceClickable()
        auction:UpdateLMButtonsState()
		auction:ForceEPUpdate()
    end)

    self:ApplyElvUISkin()
    self:UpdateScrollFrameSize()
end

-- ======================
-- Обновление размеров скролл-фрейма
-- ======================
function auction:UpdateScrollFrameSize()
    if not self.frame or not self.scrollFrame then return end
    if self.scrollBG then
        self.scrollBG:ClearAllPoints()
        self.scrollBG:SetPoint("TOPLEFT", self.scrollFrame, "TOPLEFT", -2, 2)
        self.scrollBG:SetPoint("BOTTOMRIGHT", self.scrollFrame, "BOTTOMRIGHT", 2, -2)
    end
end

-- ======================
-- Обновление отображения максимальной ставки
-- ======================
function auction:UpdateMaxBidDisplay()
    if not self.maxBidText then return end
    
    local isOffspec = self.offspecCheckbox and self.offspecCheckbox:GetChecked() or false
    local maxBid = self:GetMaxBidAmount(isOffspec)
    local currentBid = tonumber(self.bidBox:GetText()) or 0
    
    if isOffspec then
        self.maxBidText:SetText(string.format("Макс. ставка: %s", self:FormatNumber(maxBid)))
    else
        self.maxBidText:SetText(string.format("Макс. ставка: %s", self:FormatNumber(maxBid)))
    end
    
    if currentBid > 0 and currentBid > maxBid then
        self.maxBidText:SetTextColor(1, 0, 0)
    else
        self.maxBidText:SetTextColor(0.7, 0.7, 0.7)
    end
end

-- ======================
-- Установка состояния блокировки
-- ======================
function auction:SetBidsLocked(state)
    self.bidsLocked = state
    if self.lockCheckbox then
        self.lockCheckbox:SetChecked(state)
    end
    if self.bidButton then
        if state then
            self.bidButton:Disable()
            self.bidButton:SetAlpha(0.5)
        else
            self.bidButton:Enable()
            self.bidButton:SetAlpha(1.0)
        end
    end
    self:Debug("Блокировка ставок: "..tostring(state))
end

-- ======================
-- Обновление состояния чекбокса
-- ======================
function auction:UpdateLockCheckbox()
    if not self.lockCheckbox then return end
    local isLM = self:IsLootMaster()
    if isLM then
        self.lockCheckbox:Enable()
        self.lockCheckbox:SetAlpha(1.0)
        self.lockCheckbox:SetScript("OnClick", function(self)
            local checked = self:GetChecked()
            local state = (checked == 1)
            auction:SetBidsLocked(state)
            SendAddonMessage(auction.prefix, "LOCK;"..(state and "true" or "false"), "RAID")
        end)
    else
        self.lockCheckbox:Disable()
        self.lockCheckbox:SetAlpha(0.5)
        self.lockCheckbox:SetScript("OnClick", nil)
    end
    if self.bidButton then
        if self.bidsLocked then
            self.bidButton:Disable()
            self.bidButton:SetAlpha(0.5)
        else
            self.bidButton:Enable()
            self.bidButton:SetAlpha(1.0)
        end
    end
end

-- ======================
-- Обновление состояния кнопок для лутера
-- ======================
function auction:UpdateLMButtonsState()
    if not self.endButton or not self.journalButton then return end
    local isLM = self:IsLootMaster()
    self.endButton:SetEnabled(isLM)
    if isLM then
        self.endButton:SetAlpha(1.0)
        self.journalButton:SetAlpha(1.0)
    else
        self.endButton:SetAlpha(0.5)
        self.journalButton:SetAlpha(1.0)
    end
end

-- ======================
-- Обновление таблицы (с правильным отступом для скроллбара)
-- ======================
function auction:RefreshTable()
    if not self.selectedBoss then return end
    local items = self.bosses[self.selectedBoss]
    if not items then
        self:Debug("Ошибка: нет предметов для босса "..tostring(self.selectedBoss))
        self.selectedBoss = nil
        return
    end
    local dbTable = self.db and self.db.table or {}
    local itemFontSize = dbTable.itemFontSize or 12
    local bidFontSize = dbTable.bidFontSize or 12
    local rowHeight = dbTable.rowHeight or 20
    local showIcons = dbTable.showIcons ~= false
    local showTopBids = dbTable.showTopBids or 2
    local evenColor = dbTable.evenRowColor or {1,1,1,0.03}
    local oddColor = dbTable.oddRowColor or {0,0,0,0}
    local selectedColor = dbTable.selectedRowColor or {0.3,0.6,1,0.3}
    local hoverColor = dbTable.hoverRowColor or {0.2,0.2,0.2,0.5}

    -- Получаем ширину скролл-фрейма
    local scrollWidth = self.scrollFrame:GetWidth()
    if scrollWidth < 100 then
        scrollWidth = 580
    end
    -- Устанавливаем ширину контента равной ширине скролл-фрейма
    self.content:SetWidth(scrollWidth)

    -- Ширина строки: полная ширина контента минус отступ справа для скроллбара (обычно 25)
    local scrollBarWidth = 16
    local availableWidth = scrollWidth - scrollBarWidth
    if availableWidth < 100 then
        availableWidth = scrollWidth - 30
    end

    -- Динамически распределяем ширину колонок (50/50)
    local itemWidth = math.floor(availableWidth / 2)
    local bidWidth = availableWidth - itemWidth - 10

    -- Инициализация выпадающего списка предметов
    UIDropDownMenu_Initialize(self.itemDropdown, function(selfDD, level)
        for _, itemID in ipairs(items) do
            local info = UIDropDownMenu_CreateInfo()
            local itemName = GetItemInfo(itemID) or ("item:"..tostring(itemID))
            info.text = itemName
            info.func = function()
                auction.selectedItem = itemID
                UIDropDownMenu_SetText(auction.itemDropdown, itemName)
                auction:HighlightSelectedRow(itemID)
                auction.bidBox:SetFocus()
            end
            info.checked = (auction.selectedItem == itemID)
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(self.itemDropdown, "Выбрать предмет")

    -- Очистка старых строк
    if self.rowFrames then
        for _, t in ipairs(self.rowFrames) do
            if t.bg then t.bg:Hide() end
            if t.icon then t.icon:Hide() end
            if t.row then t.row:Hide() end
            if t.bidsStr then t.bidsStr:Hide() end
            if t.leftClickFrame then t.leftClickFrame:Hide() end
            if t.rightClickFrame then t.rightClickFrame:Hide() end
        end
    end

    self.rowFrames = {}
    local content = self.content
    content:SetHeight(rowHeight * #items)

    for i, itemID in ipairs(items) do
        local rowTable = {}

        -- Фон строки (ширина availableWidth)
        local bg = content:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -rowHeight*(i-1))
        bg:SetSize(availableWidth, rowHeight)
        if itemID == self.selectedItem then
            bg:SetTexture(selectedColor[1], selectedColor[2], selectedColor[3], selectedColor[4])
        else
            if i % 2 == 0 then
                bg:SetTexture(evenColor[1], evenColor[2], evenColor[3], evenColor[4])
            else
                bg:SetTexture(oddColor[1], oddColor[2], oddColor[3], oddColor[4])
            end
        end
        rowTable.bg = bg

        if showIcons then
            local icon = content:CreateTexture(nil, "ARTWORK")
            local iconSize = rowHeight - 2
            icon:SetSize(iconSize, iconSize)
            icon:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -(rowHeight*(i-1) + 2))
            icon:SetTexture(GetItemIcon(itemID) or "Interface/Icons/INV_Misc_QuestionMark")
            rowTable.icon = icon
        end

        -- Название предмета
        local row = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        if showIcons then
            row:SetPoint("LEFT", rowTable.icon, "RIGHT", 5, 0)
        else
            row:SetPoint("LEFT", content, "LEFT", 5, 0)
        end
        row:SetWidth(itemWidth)
        row:SetJustifyH("LEFT")
        row:SetWordWrap(true)
        row:SetFont(GameFontNormal:GetFont(), itemFontSize)
        row:SetHeight(rowHeight)
        local itemName = GetItemInfo(itemID) or ("item:"..itemID)
        row:SetText(itemName)

        local colorMode = self.db.table.itemColorMode or "gold"
        if colorMode == "gold" then
            row:SetTextColor(1, 0.8, 0)
        else
            local _, _, quality = GetItemInfo(itemID)
            if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
                local c = ITEM_QUALITY_COLORS[quality]
                row:SetTextColor(c.r, c.g, c.b)
            else
                row:SetTextColor(1, 1, 1)
            end
        end
        rowTable.row = row

        -- Текст ставок
        local bidsStr = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        bidsStr:SetPoint("LEFT", row, "LEFT", itemWidth + 10, 0)
        bidsStr:SetWidth(bidWidth)
        bidsStr:SetJustifyH("LEFT")
        bidsStr:SetWordWrap(true)
        bidsStr:SetFont(GameFontNormal:GetFont(), bidFontSize)
        bidsStr:SetHeight(rowHeight)
        
        local bidsForItem = self.bids[self.selectedBoss] and self.bids[self.selectedBoss][itemID] or {}
        table.sort(bidsForItem, function(a,b) return a.amount>b.amount end)
        
        local topText = ""
        for j = 1, showTopBids do
            if bidsForItem[j] then
                local formatted = self:FormatNumber(bidsForItem[j].amount)
                local playerName = bidsForItem[j].player
                local coloredName = self:FormatColoredName(playerName)
                local offspecMark = bidsForItem[j].isOffspec and " (O)" or ""
                if j == 1 then
                    topText = topText .. coloredName .. " - " .. formatted .. offspecMark
                else
                    topText = topText .. " | " .. coloredName .. " - " .. formatted .. offspecMark
                end
                topText = topText .. "|r"
            end
        end
        bidsStr:SetText(topText)
        rowTable.bidsStr = bidsStr

        -- Левая часть (название предмета)
        local leftClickFrame = CreateFrame("Button", nil, content)
        leftClickFrame:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, 0)
        leftClickFrame:SetPoint("BOTTOMRIGHT", bg, "TOPLEFT", itemWidth + 10, -rowHeight)
        leftClickFrame:EnableMouse(true)
        
        -- Правая часть (ставки)
        local rightClickFrame = CreateFrame("Button", nil, content)
        rightClickFrame:SetPoint("TOPLEFT", bg, "TOPLEFT", itemWidth + 10, 0)
        rightClickFrame:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)
        rightClickFrame:EnableMouse(true)
        
        local currentItemID = itemID
        local currentRow = i
        local currentBg = bg

        leftClickFrame:SetScript("OnClick", function()
            auction.selectedItem = currentItemID
            local itemName = GetItemInfo(currentItemID) or ("item:"..tostring(currentItemID))
            UIDropDownMenu_SetText(auction.itemDropdown, itemName)
            auction:HighlightSelectedRow(currentItemID)
            auction.bidBox:SetFocus()
        end)
        
        leftClickFrame:SetScript("OnEnter", function()
            local anchor = "ANCHOR_" .. (self.db.table.tooltipAnchor or "CURSOR")
            GameTooltip:SetOwner(leftClickFrame, anchor)
            if IsShiftKeyDown() then
                GameTooltip:SetHyperlinkCompareItem("item:"..currentItemID)
            else
                GameTooltip:SetHyperlink("item:"..currentItemID)
            end
            GameTooltip:Show()
            
            if currentItemID ~= auction.selectedItem then
                currentBg:SetTexture(hoverColor[1], hoverColor[2], hoverColor[3], hoverColor[4])
            end
        end)
        
        leftClickFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
            if currentItemID == auction.selectedItem then
                currentBg:SetTexture(selectedColor[1], selectedColor[2], selectedColor[3], selectedColor[4])
            else
                if currentRow % 2 == 0 then
                    currentBg:SetTexture(evenColor[1], evenColor[2], evenColor[3], evenColor[4])
                else
                    currentBg:SetTexture(oddColor[1], oddColor[2], oddColor[3], oddColor[4])
                end
            end
        end)
        
        rightClickFrame:SetScript("OnClick", function()
            auction.selectedItem = currentItemID
            local itemName = GetItemInfo(currentItemID) or ("item:"..tostring(currentItemID))
            UIDropDownMenu_SetText(auction.itemDropdown, itemName)
            auction:HighlightSelectedRow(currentItemID)
            auction.bidBox:SetFocus()
        end)
        
        rightClickFrame:SetScript("OnEnter", function()
            local anchor = "ANCHOR_" .. (self.db.table.tooltipAnchor or "CURSOR")
            GameTooltip:SetOwner(rightClickFrame, anchor)
            
            local bidsForItem = self.bids[self.selectedBoss] and self.bids[self.selectedBoss][currentItemID] or {}
            table.sort(bidsForItem, function(a,b) return a.amount > b.amount end)
            
            if #bidsForItem > 0 then
                GameTooltip:AddLine("Ставки на предмет", 1, 0.8, 0)
                GameTooltip:AddLine(" ")
                
                for _, bid in ipairs(bidsForItem) do
                    local coloredName = self:FormatColoredName(bid.player)
                    local ep = self:GetPlayerEP(bid.player, true)
                    local epColor = (ep >= bid.amount) and "|cff00ff00" or "|cffff0000"
                    local offspecMark = bid.isOffspec and " (O)" or ""
                    
                    GameTooltip:AddLine(string.format("%s|r - %s EP%s", coloredName, self:FormatNumber(bid.amount), offspecMark), 1, 1, 1)
                    GameTooltip:AddLine(string.format("  EP: %s%s|r", epColor, self:FormatNumber(ep)), 0.8, 0.8, 0.8)
                    GameTooltip:AddLine(" ")
                end
            else
                GameTooltip:SetText("Нет ставок на этот предмет")
            end
            
            GameTooltip:Show()
            
            if currentItemID ~= auction.selectedItem then
                currentBg:SetTexture(hoverColor[1], hoverColor[2], hoverColor[3], hoverColor[4])
            end
        end)
        
        rightClickFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
            if currentItemID == auction.selectedItem then
                currentBg:SetTexture(selectedColor[1], selectedColor[2], selectedColor[3], selectedColor[4])
            else
                if currentRow % 2 == 0 then
                    currentBg:SetTexture(evenColor[1], evenColor[2], evenColor[3], evenColor[4])
                else
                    currentBg:SetTexture(oddColor[1], oddColor[2], oddColor[3], oddColor[4])
                end
            end
        end)
        
        rowTable.leftClickFrame = leftClickFrame
        rowTable.rightClickFrame = rightClickFrame
        table.insert(self.rowFrames, rowTable)
    end
    self:ForceClickable()
end

-- ======================
-- Подсветка выбранной строки
-- ======================
function auction:HighlightSelectedRow(selectedItemID)
    if not self.rowFrames or not self.selectedBoss then return end
    local dbTable = self.db and self.db.table or {}
    local evenColor = dbTable.evenRowColor or {1,1,1,0.03}
    local oddColor = dbTable.oddRowColor or {0,0,0,0}
    local selectedColor = dbTable.selectedRowColor or {0.3,0.6,1,0.3}
    for i, rowTable in ipairs(self.rowFrames) do
        local itemID = self.bosses[self.selectedBoss][i]
        if itemID == selectedItemID then
            rowTable.bg:SetTexture(selectedColor[1], selectedColor[2], selectedColor[3], selectedColor[4])
        else
            if i % 2 == 0 then
                rowTable.bg:SetTexture(evenColor[1], evenColor[2], evenColor[3], evenColor[4])
            else
                rowTable.bg:SetTexture(oddColor[1], oddColor[2], oddColor[3], oddColor[4])
            end
        end
    end
end

-- ======================
-- Принудительное обновление кликабельности
-- ======================
function auction:ForceClickable()
    if not self.rowFrames then return end
    for _, rowTable in ipairs(self.rowFrames) do
        if rowTable.leftClickFrame then
            rowTable.leftClickFrame:EnableMouse(true)
            rowTable.leftClickFrame:Show()
            rowTable.leftClickFrame:SetFrameLevel(self.content:GetFrameLevel() + 20)
        end
        if rowTable.rightClickFrame then
            rowTable.rightClickFrame:EnableMouse(true)
            rowTable.rightClickFrame:Show()
            rowTable.rightClickFrame:SetFrameLevel(self.content:GetFrameLevel() + 20)
        end
    end
end

-- ======================
-- Локальные функции ставок
-- ======================
function auction:ProcessBidLocally(bossName, itemID, playerName, amount, isOffspec)
    self.bids[bossName] = self.bids[bossName] or {}
    self.bids[bossName][itemID] = self.bids[bossName][itemID] or {}
    if amount == 0 then
        for i, bid in ipairs(self.bids[bossName][itemID]) do
            if bid.player == playerName then
                table.remove(self.bids[bossName][itemID], i)
                break
            end
        end
        self:RefreshTable()
        self:SendSync(bossName, itemID)
        self:CheckIfOutbid(bossName, itemID)
        local coloredName = self:FormatColoredName(playerName)
        --print("|cff00ff00[EPBA]|r "..coloredName.."|r отказался от ставки.")
        return
    end
    if amount < self.db.general.minBid then
        --print("|cff00ff00[EPBA]|r Ставка не может быть меньше минимальной ("..self.db.general.minBid..")")
        return
    end
    local existingBid
    for _, bid in ipairs(self.bids[bossName][itemID]) do
        if bid.player == playerName then
            existingBid = bid
            break
        end
    end
    if existingBid then
        existingBid.amount = amount
        existingBid.isOffspec = isOffspec or false
    else
        table.insert(self.bids[bossName][itemID], {
            player = playerName,
            amount = amount,
            isOffspec = isOffspec or false
        })
    end
    self:RefreshTable()
    self:SendSync(bossName, itemID)
    self:CheckIfOutbid(bossName, itemID)
end

function auction:SendBidLocal()
    if self.bidsLocked then
        return
    end

    if not self.selectedBoss or not self.selectedItem then
        return
    end
    local amount = tonumber(self.bidBox:GetText())
    if not amount or amount < 0 then
        return
    end
    if amount ~= 0 and amount < self.db.general.minBid then
        print("|cff00ff00[EPBA]|r Минимальная ставка — "..self.db.general.minBid.." EP (0 = отмена ставки)")
        return
    end
    
    local isOffspec = self.offspecCheckbox and self.offspecCheckbox:GetChecked() or false
    
    self:ForceEPUpdate(function(success, currentEP)
        if not success then
            --print("|cffff0000[EPBA]|r Не удалось получить актуальный EP!")
            return
        end
        
        local maxBid = self:GetMaxBidAmount(isOffspec)
        
        if amount > maxBid then
            local modeText = isOffspec and " (офф-спек)" or ""
            print(string.format("|cffff0000[EPBA]|r Недостаточно EP%s для ставки! Максимум: %s EP", 
                modeText, self:FormatNumber(maxBid)))
            return
        end
        
        if self.db.general.confirmBid and amount > 0 then
            local maxBidText = self:FormatNumber(maxBid)
            StaticPopupDialogs["EPBA_CONFIRM_BID"] = {
                text = "Подтвердите ставку\nПредмет: "..GetItemInfo(self.selectedItem).."\nСумма: "..amount.." EP" .. 
                       (isOffspec and "\n(Офф-спек, максимум: "..maxBidText.." EP)" or ""),
                button1 = "Да",
                button2 = "Нет",
                OnAccept = function()
                    auction:SendBidAfterConfirm(amount, currentEP, isOffspec)
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
            }
            StaticPopup_Show("EPBA_CONFIRM_BID")
        else
            self:SendBidAfterConfirm(amount, currentEP, isOffspec)
        end
    end)
end

function auction:SendBidAfterConfirm(amount, currentEP, isOffspec)
    local bossName = auction.selectedBoss
    local itemID = auction.selectedItem
    local playerName = UnitName("player")
    auction:Debug("Отправка ставки: "..playerName.." "..amount.." на "..bossName.." "..itemID.." (офф-спек: "..tostring(isOffspec)..")")
    
    auction:AddBidLogEntry(playerName, amount, itemID, bossName, isOffspec)
    
    if auction:IsLootMaster() then
        auction:ProcessBidLocally(bossName, itemID, playerName, amount, isOffspec)
    else
        local offspecStr = isOffspec and "true" or "false"
        local msg = "BID;"..bossName..";"..itemID..";"..playerName..";"..amount..";"..offspecStr
        SendAddonMessage(auction.prefix, msg, "RAID")
    end
    auction.bidBox:SetText("")
end

function auction:EndAuctionLocal()
    if not self.selectedBoss then return end
    self.bids[self.selectedBoss] = {}
    self.dataVersions[self.selectedBoss] = (self.dataVersions[self.selectedBoss] or 0) + 1
    self:RefreshTable()
    self:SaveData()
end

-- ======================
-- ElvUI Skin
-- ======================
function auction:ApplyElvUISkin()
    if not IsAddOnLoaded("ElvUI") then return end
    local E, L, V, P, G = unpack(ElvUI)
    local S = E:GetModule("Skins")
    if not S then return end
    
    if self.frame then
        self.frame:SetTemplate("Transparent")
    end
    
    if self.bidButton then S:HandleButton(self.bidButton) end
    if self.endButton then S:HandleButton(self.endButton) end
    if self.journalButton then S:HandleButton(self.journalButton) end
    if self.requestButton then S:HandleButton(self.requestButton) end
    if self.optionsBtn then S:HandleButton(self.optionsBtn) end
    if self.sizer then
        self.sizer:SetTemplate("Default")
        self.sizer:SetBackdropBorderColor(0, 0, 0, 0)
        self.sizer:SetBackdropColor(0, 0, 0, 0)
    end
    
    if self.bidBox then
        self.bidBox:StripTextures()
        S:HandleEditBox(self.bidBox)
        self.bidBox:HookScript("OnEditFocusGained", function(box)
            box.backdrop:SetBackdropBorderColor(1, 0.8, 0)
        end)
        self.bidBox:HookScript("OnEditFocusLost", function(box)
            box.backdrop:SetBackdropBorderColor(unpack(E.media.bordercolor))
        end)
    end
    
    if self.closeButton then S:HandleCloseButton(self.closeButton) end
    
    if self.scrollFrame then
        local scrollBar = _G[self.scrollFrame:GetName().."ScrollBar"]
        if scrollBar then S:HandleScrollBar(scrollBar) end
    end
    
    if self.bossDropdown then S:HandleDropDownBox(self.bossDropdown) end
    if self.itemDropdown then S:HandleDropDownBox(self.itemDropdown) end
end

-- ======================
-- Обновление цветов строк ставок
-- ======================
function auction:UpdateBidRowColors()
    if not self.rowFrames or not self.selectedBoss then return end
    
    local showTopBids = self.db.table.showTopBids or 2
    
    for i, rowTable in ipairs(self.rowFrames) do
        local itemID = self.bosses[self.selectedBoss][i]
        local bidsForItem = self.bids[self.selectedBoss] and self.bids[self.selectedBoss][itemID] or {}
        table.sort(bidsForItem, function(a,b) return a.amount>b.amount end)
        
        local topText = ""
        for j = 1, showTopBids do
            if bidsForItem[j] then
                local formatted = self:FormatNumber(bidsForItem[j].amount)
                local playerName = bidsForItem[j].player
                local ep = self:GetPlayerEP(playerName, false)
                local coloredName
                if ep >= bidsForItem[j].amount then
                    coloredName = self:FormatColoredName(playerName)
                else
                    coloredName = "|cffff0000" .. playerName .. "|r"
                end
                local offspecMark = bidsForItem[j].isOffspec and " (O)" or ""
                if j == 1 then
                    topText = topText .. coloredName .. " - " .. formatted .. offspecMark
                else
                    topText = topText .. " | " .. coloredName .. " - " .. formatted .. offspecMark
                end
            end
        end
        
        if rowTable.bidsStr then
            rowTable.bidsStr:SetText(topText)
        end
    end
end
