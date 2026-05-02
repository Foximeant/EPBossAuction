local auction = EPBossAuction

-- ======================
-- Создание основного окна (левая панель)
-- ======================
function auction:CreateUI()
    -- Инициализация пула строк (чтобы избежать nil в OnHide)
    self.rowPool = {}
    self.activeRows = {}
    self.itemInfoCache = {}

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
            if delta > 0 then auction:ZoomIn() else auction:ZoomOut() end
        end
    end)
	frame:SetScript("OnHide", function()
		auction:ReturnRowsToPool()
        if auction.refreshTimer then
            auction:CancelTimer(auction.refreshTimer)
            auction.refreshTimer = nil
            auction.refreshPending = false
        end
        if auction.resizeTimer then
            auction:CancelTimer(auction.resizeTimer)
            auction.resizeTimer = nil
        end
        if auction.itemInfoRefreshTimer then
            auction:CancelTimer(auction.itemInfoRefreshTimer)
            auction.itemInfoRefreshTimer = nil
        end
	end)
    frame:Hide()
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    tinsert(UISpecialFrames, "EPBossAuctionFrame")
    self.frame = frame
    self:SkinPanel(frame)

    -- Заголовок окна
    local title = frame:CreateFontString("EPBossAuctionTitle", "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("RS EPBossAuction "..self.version)

    -- Кнопка закрытия
    local close = CreateFrame("Button", "EPBossAuctionCloseButton", frame)
    self.closeButton = close
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetText("×")
    close:SetNormalFontObject(GameFontNormalLarge)
    close:SetScript("OnClick", function() frame:Hide() end)
    self:SkinButton(close)

    -- Кнопка настроек
    local optionsBtn = CreateFrame("Button", "EPBossAuctionOptionsButton", frame)
    optionsBtn:SetSize(20, 20)
    optionsBtn:SetPoint("TOPRIGHT", close, "TOPLEFT", -4, 0)
    optionsBtn:SetText("O")
    optionsBtn:SetNormalFontObject(GameFontNormal)
    self:SkinButton(optionsBtn)
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
    self:SkinPanel(leftPanel)

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
            local boss = bossName
            local info = UIDropDownMenu_CreateInfo()
            info.text = boss
            info.func = function()
                auction.selectedBoss = boss
                auction.selectedItem = nil
                UIDropDownMenu_SetText(dropdown, boss)
                UIDropDownMenu_SetText(auction.itemDropdown, "Выбрать предмет")
                if auction.itemDropdown then
                    UIDropDownMenu_Refresh(auction.itemDropdown)
                end
                auction:RequestRefresh()
            end
            info.checked = (auction.selectedBoss == boss)
            UIDropDownMenu_AddButton(info)
        end
    end)
    self.bossDropdown = dropdown
    self:SkinDropdown(dropdown)

    -- 2. Выбор предмета
    local itemLabel = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemLabel:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 26, -15)
    itemLabel:SetText("Предмет:")
    local itemDrop = CreateFrame("Frame", "EPItemDropdown", leftPanel, "UIDropDownMenuTemplate")
    itemDrop:SetPoint("TOPLEFT", itemLabel, "BOTTOMLEFT", -26, -5)
    UIDropDownMenu_SetWidth(itemDrop, 140)
    UIDropDownMenu_SetText(itemDrop, "Выбрать предмет")
    UIDropDownMenu_Initialize(itemDrop, function(selfDD, level)
        if not auction.selectedBoss then return end
        local items = auction.bosses[auction.selectedBoss]
        if not items then return end
        for _, itemID in ipairs(items) do
            local id = itemID
            local itemName = auction:GetCachedItemName(id)
            local info = UIDropDownMenu_CreateInfo()
            info.text = itemName
            info.func = function()
                auction.selectedItem = id
                UIDropDownMenu_SetText(auction.itemDropdown, itemName)
                auction:HighlightSelectedRow(id)
                auction.bidBox:SetFocus()
            end
            info.checked = (auction.selectedItem == id)
            UIDropDownMenu_AddButton(info)
        end
    end)
    self.itemDropdown = itemDrop
    self:SkinDropdown(itemDrop)

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
    self:SkinInput(editBox)

    -- 4. Кнопка "Сделать ставку"
    local button = CreateFrame("Button", "EPBossAuctionBidButton", leftPanel, "UIPanelButtonTemplate")
    self.bidButton = button
    button:SetSize(140, 25)
    button:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", -5, -8)
    button:SetText("Сделать ставку")
    button:SetScript("OnClick", function()
        auction:SendBidLocal()
    end)
    self:SkinButton(button)

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
    self:SkinButton(requestButton)

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
    self:SkinButton(endButton)

    -- 8. Кнопка "Журнал"
    local journalButton = CreateFrame("Button", "EPBossAuctionJournalButton", leftPanel, "UIPanelButtonTemplate")
    journalButton:SetSize(140, 25)
    journalButton:SetPoint("TOPLEFT", endButton, "BOTTOMLEFT", 0, -8)
    journalButton:SetText("Журнал ставок")
    journalButton:SetScript("OnClick", function()
        auction:ToggleJournal()
    end)
    self.journalButton = journalButton
    self:SkinButton(journalButton)

    -- 9. Кнопка "Очередь"
    local queueButton = CreateFrame("Button", "EPBossAuctionQueueButton", leftPanel, "UIPanelButtonTemplate")
    queueButton:SetSize(140, 25)
    queueButton:SetPoint("TOPLEFT", journalButton, "BOTTOMLEFT", 0, -8)
    queueButton:SetText("Очередь")
    queueButton:SetScript("OnClick", function()
        auction:ToggleQueue()
    end)
    self.queueButton = queueButton
    self:SkinButton(queueButton)

    -- 10. Текст "Ваш ЕП"
    local epText = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    epText:SetPoint("TOPLEFT", queueButton, "BOTTOMLEFT", 0, -15)
    epText:SetText("Ваш ЕП: ...")
    auction.myEPText = epText

    -- 11. Текст максимальной ставки
    local maxBidText = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    maxBidText:SetPoint("TOPLEFT", epText, "BOTTOMLEFT", 0, -2)
    maxBidText:SetText("Макс. ставка: ...")
    maxBidText:SetTextColor(0.7, 0.7, 0.7)
    auction.maxBidText = maxBidText

    -- ======================
    -- ПРАВАЯ ОБЛАСТЬ – ТАБЛИЦА
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
    self:SkinPanel(scrollBG)

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
        auction:RequestRefresh()
    end)
    self.sizer = sizer

    frame:SetResizable(true)
    frame:SetMinResize(650, 450)
    frame:SetMaxResize(1200, 900)

    frame:SetScript("OnSizeChanged", function()
        if auction.resizeTimer then
            auction:CancelTimer(auction.resizeTimer)
            auction.resizeTimer = nil
        end
        local now = GetTime()
        auction.lastResize = now
        auction.resizeTimer = auction:ScheduleTimer(function()
            if GetTime() - (auction.lastResize or 0) > 0.25 then
                if auction.frame and auction.frame:IsShown() then
                    auction:UpdateScrollFrameSize()
                    auction:RequestRefresh()
                end
            end
            auction.resizeTimer = nil
        end, 0.25)
    end)

    self:UpdateScrollFrameSize()

    local scrollBar = _G["EPBossAuctionScrollFrameScrollBar"]
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", self.scrollFrame, "TOPRIGHT", 2, -17)
        scrollBar:SetPoint("BOTTOMRIGHT", self.scrollFrame, "BOTTOMRIGHT", 2, 17)
    end

    self:UpdateLMButtonsState()
    self:ApplyElvUISkin()

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
        auction:ForceEPUpdate(function(success, ep) end)
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
        auction.db.general.offspecMultiplier = multiplier
        auction:SaveSettings()
        print("|cff00ff00[EPBA]|r Коэффициент офф-спек установлен на " .. (multiplier * 100) .. "%")
        SendAddonMessage(auction.prefix, "OFFSPEC_MULT;" .. multiplier, "RAID")
    end

    frame:SetScript("OnShow", function()
        auction:ForceClickable()
        auction:UpdateLMButtonsState()
        auction:ForceEPUpdate()
    end)

    self:ApplyElvUISkin()
end

-- ======================
-- Обновление размеров скролл-фрейма
-- ======================
function auction:UpdateScrollFrameSize()
    if not self.frame or not self.scrollFrame then return end
    self.scrollFrame:SetPoint("TOPLEFT", self.leftPanel, "TOPRIGHT", 10, 0)
    self.scrollFrame:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -16, 16)
    if self.scrollBG then
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
    
    self.maxBidText:SetText(string.format("Макс. ставка: %s", self:FormatNumber(maxBid)))
    
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
-- Кэширование информации о предмете
-- ======================
function auction:GetCachedItemInfo(itemID)
    if not itemID then return nil, nil end
    if self.itemInfoCache[itemID] then
        return self.itemInfoCache[itemID].name, self.itemInfoCache[itemID].icon
    end
    local name = GetItemInfo(itemID)
    local icon = GetItemIcon(itemID)
    if name then
        self.itemInfoCache[itemID] = { name = name, icon = icon }
    end
    return name, icon
end

function auction:GetCachedItemName(itemID)
    local name = self:GetCachedItemInfo(itemID)
    return name or ("item:"..tostring(itemID))
end

-- ======================
-- Пул строк и создание шаблона
-- ======================
function auction:CreateRowTemplate()
    local row = CreateFrame("Button", nil, self.content)
    row:SetSize(100, 20)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    row.bg = bg

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", row, "LEFT", 5, 0)
    icon:Hide()
    row.icon = icon

    local itemName = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemName:SetPoint("LEFT", 5, 0)
    itemName:SetJustifyH("LEFT")
    itemName:SetWordWrap(false)
    row.itemName = itemName

    local bidsStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bidsStr:SetPoint("LEFT", row, "LEFT", 250, 0)
    bidsStr:SetJustifyH("LEFT")
    bidsStr:SetWordWrap(false)
    row.bidsStr = bidsStr

    -- Левая кликабельная область (выбор предмета)
    local leftClick = CreateFrame("Button", nil, row)
    leftClick:SetPoint("TOPLEFT")
    leftClick:SetPoint("BOTTOMRIGHT", row, "BOTTOMLEFT", 250, 0)
    leftClick:SetScript("OnClick", function()
        if not row.itemID then return end
        auction.selectedItem = row.itemID
        UIDropDownMenu_SetText(auction.itemDropdown, auction:GetCachedItemName(row.itemID))
        auction:HighlightSelectedRow(row.itemID)
        auction.bidBox:SetFocus()
    end)
    leftClick:SetScript("OnEnter", function()
        if not row.itemID then return end
        GameTooltip:SetOwner(leftClick, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink("item:"..row.itemID)
        GameTooltip:Show()
        if row.itemID ~= auction.selectedItem then
            row.bg:SetTexture(auction.db.table.hoverRowColor[1], auction.db.table.hoverRowColor[2], auction.db.table.hoverRowColor[3], auction.db.table.hoverRowColor[4])
        end
    end)
    leftClick:SetScript("OnLeave", function()
        GameTooltip:Hide()
        auction:RestoreRowBackground(row)
    end)
    row.leftClick = leftClick

    -- Правая область (тултип ставок)
    local rightClick = CreateFrame("Button", nil, row)
    rightClick:SetPoint("TOPLEFT", row, "TOPLEFT", 250, 0)
    rightClick:SetPoint("BOTTOMRIGHT")
    rightClick:SetScript("OnClick", function()
        if not row.itemID then return end
        auction.selectedItem = row.itemID
        UIDropDownMenu_SetText(auction.itemDropdown, auction:GetCachedItemName(row.itemID))
        auction:HighlightSelectedRow(row.itemID)
        auction.bidBox:SetFocus()
    end)
    rightClick:SetScript("OnEnter", function()
        if not row.itemID then return end
        GameTooltip:SetOwner(rightClick, "ANCHOR_CURSOR")
        auction:ShowBidsTooltip(row.itemID)
        if row.itemID ~= auction.selectedItem then
            row.bg:SetTexture(auction.db.table.hoverRowColor[1], auction.db.table.hoverRowColor[2], auction.db.table.hoverRowColor[3], auction.db.table.hoverRowColor[4])
        end
    end)
    rightClick:SetScript("OnLeave", function()
        GameTooltip:Hide()
        auction:RestoreRowBackground(row)
    end)
    row.rightClick = rightClick

    return row
end

function auction:GetRowFromPool()
    if #self.rowPool > 0 then
        return table.remove(self.rowPool, 1)
    end
    return self:CreateRowTemplate()
end

function auction:ReturnRowsToPool()
    if not self.activeRows then return end
    for _, row in ipairs(self.activeRows) do
        row:Hide()
        row.itemID = nil
        row:SetScript("OnUpdate", nil)
        row.bg:SetTexture(0,0,0,0)
        row.itemName:SetText("")
        row.bidsStr:SetText("")
        row.icon:Hide()
        table.insert(self.rowPool, row)
    end
    wipe(self.activeRows)
    self.lastHighlightedRow = nil
end

function auction:RestoreRowBackground(row)
    if not row or not row.bg or not row.index then return end

    local dbTable = self.db.table
    local evenColor = dbTable.evenRowColor or {1, 1, 1, 0.03}
    local oddColor = dbTable.oddRowColor or {0, 0, 0, 0}
    local selectedColor = dbTable.selectedRowColor or {0.3, 0.6, 1, 0.3}

    if row.itemID and row.itemID == self.selectedItem then
        row.bg:SetTexture(selectedColor[1], selectedColor[2], selectedColor[3], selectedColor[4])
        return
    end

    local color = (row.index % 2 == 0) and evenColor or oddColor
    row.bg:SetTexture(color[1], color[2], color[3], color[4])
end

function auction:GetTableLayoutMetrics()
    local dbTable = self.db.table
    local scrollWidth = self.scrollFrame and self.scrollFrame:GetWidth() or 0
    if scrollWidth < 100 then scrollWidth = 580 end

    local availableWidth = scrollWidth - 16

    return {
        dbTable = dbTable,
        rowHeight = dbTable.rowHeight or 20,
        showIcons = dbTable.showIcons ~= false,
        showTopBids = dbTable.showTopBids or 2,
        evenColor = dbTable.evenRowColor or {1, 1, 1, 0.03},
        oddColor = dbTable.oddRowColor or {0, 0, 0, 0},
        selectedColor = dbTable.selectedRowColor or {0.3, 0.6, 1, 0.3},
        itemFontSize = dbTable.itemFontSize or 12,
        bidFontSize = dbTable.bidFontSize or 12,
        colorMode = dbTable.itemColorMode or "gold",
        availableWidth = availableWidth,
        itemWidth = math.floor(availableWidth / 2),
    }
end

function auction:RenderItemRow(row, itemID, index, metrics)
    if not row or not itemID or not metrics then return false end

    local yOffset = -metrics.rowHeight * (index - 1)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, yOffset)
    row:SetSize(metrics.availableWidth, metrics.rowHeight)

    row.itemID = itemID
    row.index = index

    if itemID == self.selectedItem then
        row.bg:SetTexture(metrics.selectedColor[1], metrics.selectedColor[2], metrics.selectedColor[3], metrics.selectedColor[4])
    else
        local color = (index % 2 == 0) and metrics.evenColor or metrics.oddColor
        row.bg:SetTexture(color[1], color[2], color[3], color[4])
    end

    local itemName, itemIcon = self:GetCachedItemInfo(itemID)
    local hasPendingItemInfo = not itemName
    if not itemName then
        itemName = "Р—Р°РіСЂСѓР·РєР°..."
    end

    row.itemName:SetText(itemName)
    row.itemName:SetFont(GameFontNormal:GetFont(), metrics.itemFontSize)
    row.itemName:SetWidth(metrics.itemWidth - (metrics.showIcons and 30 or 10))
    row.itemName:ClearAllPoints()

    if metrics.colorMode == "gold" then
        row.itemName:SetTextColor(1, 0.8, 0)
    else
        local _, _, quality = GetItemInfo(itemID)
        if quality and ITEM_QUALITY_COLORS[quality] then
            local c = ITEM_QUALITY_COLORS[quality]
            row.itemName:SetTextColor(c.r, c.g, c.b)
        else
            row.itemName:SetTextColor(1, 1, 1)
        end
    end

    if metrics.showIcons and itemIcon then
        row.icon:SetTexture(itemIcon)
        row.icon:Show()
        row.itemName:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    else
        row.icon:Hide()
        row.itemName:SetPoint("LEFT", row, "LEFT", 5, 0)
    end

    local bidsForItem = self.sortedBids[self.selectedBoss] and self.sortedBids[self.selectedBoss][itemID] or {}
    local topText = ""
    for j = 1, metrics.showTopBids do
        if bidsForItem[j] then
            local coloredName = self:FormatColoredName(bidsForItem[j].player)
            local offspecMark = bidsForItem[j].isOffspec and " (O)" or ""
            local formatted = self:FormatNumber(bidsForItem[j].amount)
            if j == 1 then
                topText = coloredName .. " - " .. formatted .. offspecMark
            else
                topText = topText .. " | " .. coloredName .. " - " .. formatted .. offspecMark
            end
        end
    end

    row.bidsStr:SetText(topText)
    row.bidsStr:SetFont(GameFontNormal:GetFont(), metrics.bidFontSize)
    row.bidsStr:ClearAllPoints()
    row.bidsStr:SetPoint("LEFT", row, "LEFT", metrics.itemWidth + 10, 0)
    row.bidsStr:SetWidth(math.max(10, metrics.availableWidth - metrics.itemWidth - 16))

    row.leftClick:ClearAllPoints()
    row.leftClick:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.leftClick:SetPoint("BOTTOMRIGHT", row, "BOTTOMLEFT", metrics.itemWidth, 0)

    row.rightClick:ClearAllPoints()
    row.rightClick:SetPoint("TOPLEFT", row, "TOPLEFT", metrics.itemWidth, 0)
    row.rightClick:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)

    row:Show()
    return hasPendingItemInfo
end

function auction:FindActiveRowByItemID(itemID)
    if not self.activeRows or not itemID then return nil end
    for _, row in ipairs(self.activeRows) do
        if row.itemID == itemID then
            return row
        end
    end
    return nil
end

function auction:RefreshRowForItem(itemID)
    if not self.frame or not self.frame:IsShown() then return false end
    if not self.selectedBoss or not itemID then return false end

    local items = self.bosses[self.selectedBoss]
    if not items then return false end

    local row = self:FindActiveRowByItemID(itemID)
    if not row then return false end

    local index
    for i, currentItemID in ipairs(items) do
        if currentItemID == itemID then
            index = i
            break
        end
    end

    if not index then return false end

    local needsDelayedRefresh = self:RenderItemRow(row, itemID, index, self:GetTableLayoutMetrics())
    if needsDelayedRefresh and not self.itemInfoRefreshTimer then
        self.itemInfoRefreshTimer = self:ScheduleTimer(function()
            self.itemInfoRefreshTimer = nil
            if self.frame and self.frame:IsShown() and self.selectedBoss then
                self:RefreshTable()
            end
        end, 0.5)
    end

    return true
end

function auction:ShowBidsTooltip(itemID)
    local bids = self.sortedBids[self.selectedBoss] and self.sortedBids[self.selectedBoss][itemID] or {}
    if #bids == 0 then
        GameTooltip:SetText("Нет ставок")
        return
    end
    GameTooltip:AddLine("Ставки на предмет", 1, 0.8, 0)
    GameTooltip:AddLine(" ")
    for _, bid in ipairs(bids) do
        local coloredName = self:FormatColoredName(bid.player)
        local ep = self:GetPlayerEP(bid.player, false)
        local epColor = (ep >= bid.amount) and "|cff00ff00" or "|cffff0000"
        local offspecMark = bid.isOffspec and " (O)" or ""
        GameTooltip:AddLine(string.format("%s|r - %s EP%s", coloredName, self:FormatNumber(bid.amount), offspecMark))
        GameTooltip:AddLine(string.format("  EP: %s%s|r", epColor, self:FormatNumber(ep)), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(" ")
    end
    GameTooltip:Show()
end

-- ======================
-- Обновление таблицы (переработано с пулом)
-- ======================
function auction:RefreshTable()
    if not self.selectedBoss then return end
    local items = self.bosses[self.selectedBoss]
    if not items then
        self:Debug("Ошибка: нет предметов для босса "..tostring(self.selectedBoss))
        self.selectedBoss = nil
        return
    end

    -- === ВАЖНО: возвращаем текущие активные строки в пул ===
    self:ReturnRowsToPool()

    local dbTable = self.db.table
    local rowHeight = dbTable.rowHeight or 20
    local showIcons = dbTable.showIcons ~= false
    local showTopBids = dbTable.showTopBids or 2
    local evenColor = dbTable.evenRowColor or {1,1,1,0.03}
    local oddColor = dbTable.oddRowColor or {0,0,0,0}
    local selectedColor = dbTable.selectedRowColor or {0.3,0.6,1,0.3}
    local itemFontSize = dbTable.itemFontSize or 12
    local bidFontSize = dbTable.bidFontSize or 12
    local colorMode = dbTable.itemColorMode or "gold"

    local scrollWidth = self.scrollFrame:GetWidth()
    if scrollWidth < 100 then scrollWidth = 580 end
    local availableWidth = scrollWidth - 16
    local itemWidth = math.floor(availableWidth / 2)

    self.content:SetHeight(rowHeight * #items)
    self.content:SetWidth(availableWidth)

    -- Обновляем выпадающий список предметов
    if self.itemDropdown then
        UIDropDownMenu_Refresh(self.itemDropdown)
    end

    local needDelayedRefresh = false

    for i, itemID in ipairs(items) do
        local row = self:GetRowFromPool()
        local yOffset = -rowHeight * (i-1)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, yOffset)
        row:SetSize(availableWidth, rowHeight)

        local bg = row.bg
        if itemID == self.selectedItem then
            bg:SetTexture(selectedColor[1], selectedColor[2], selectedColor[3], selectedColor[4])
        else
            if i % 2 == 0 then
                bg:SetTexture(evenColor[1], evenColor[2], evenColor[3], evenColor[4])
            else
                bg:SetTexture(oddColor[1], oddColor[2], oddColor[3], oddColor[4])
            end
        end

        local itemName, itemIcon = self:GetCachedItemInfo(itemID)
        if not itemName then
            itemName = "Загрузка..."
            needDelayedRefresh = true
        end
        row.itemName:SetText(itemName)
        row.itemName:SetFont(GameFontNormal:GetFont(), itemFontSize)
        row.itemName:SetWidth(itemWidth - (showIcons and 30 or 10))
        row.itemName:ClearAllPoints()

        if colorMode == "gold" then
            row.itemName:SetTextColor(1, 0.8, 0)
        else
            local _, _, quality = GetItemInfo(itemID)
            if quality and ITEM_QUALITY_COLORS[quality] then
                local c = ITEM_QUALITY_COLORS[quality]
                row.itemName:SetTextColor(c.r, c.g, c.b)
            else
                row.itemName:SetTextColor(1, 1, 1)
            end
        end

        if showIcons and itemIcon then
            row.icon:SetTexture(itemIcon)
            row.icon:Show()
            row.itemName:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
        else
            row.icon:Hide()
            row.itemName:SetPoint("LEFT", row, "LEFT", 5, 0)
        end

        local bidsForItem = self.sortedBids[self.selectedBoss] and self.sortedBids[self.selectedBoss][itemID] or {}
        local topText = ""
        for j = 1, showTopBids do
            if bidsForItem[j] then
                local coloredName = self:FormatColoredName(bidsForItem[j].player)
                local offspecMark = bidsForItem[j].isOffspec and " (O)" or ""
                local formatted = self:FormatNumber(bidsForItem[j].amount)
                if j == 1 then
                    topText = coloredName .. " - " .. formatted .. offspecMark
                else
                    topText = topText .. " | " .. coloredName .. " - " .. formatted .. offspecMark
                end
            end
        end
        row.bidsStr:SetText(topText)
        row.bidsStr:SetFont(GameFontNormal:GetFont(), bidFontSize)
        row.bidsStr:ClearAllPoints()
        row.bidsStr:SetPoint("LEFT", row, "LEFT", itemWidth + 10, 0)
        row.bidsStr:SetWidth(math.max(10, availableWidth - itemWidth - 16))

        row.leftClick:ClearAllPoints()
        row.leftClick:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        row.leftClick:SetPoint("BOTTOMRIGHT", row, "BOTTOMLEFT", itemWidth, 0)

        row.rightClick:ClearAllPoints()
        row.rightClick:SetPoint("TOPLEFT", row, "TOPLEFT", itemWidth, 0)
        row.rightClick:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)

        row.itemID = itemID
        row.index = i
        row:Show()
        table.insert(self.activeRows, row)
    end

    self:UpdateScrollFrameSize()

    if needDelayedRefresh and not self.itemInfoRefreshTimer then
        -- Если какие-то предметы не загружены, запланируем повторное обновление через 0.5 сек
        self.itemInfoRefreshTimer = self:ScheduleTimer(function()
            self.itemInfoRefreshTimer = nil
            if self.frame and self.frame:IsShown() and self.selectedBoss then
                self:RefreshTable()
            end
        end, 0.5)
    end
end

function auction:HighlightSelectedRow(selectedItemID)
    if not self.activeRows then return end
    local dbTable = self.db.table
    local evenColor = dbTable.evenRowColor or {1,1,1,0.03}
    local oddColor = dbTable.oddRowColor or {0,0,0,0}
    local selectedColor = dbTable.selectedRowColor or {0.3,0.6,1,0.3}

    -- Снимаем подсветку с предыдущей строки
    if self.lastHighlightedRow and self.lastHighlightedRow:IsShown() then
        self:RestoreRowBackground(self.lastHighlightedRow)
    end

    -- Находим новую строку
    local newRow
    for i, row in ipairs(self.activeRows) do
        if row.itemID == selectedItemID then
            newRow = row
            break
        end
    end

    if newRow then
        newRow.bg:SetTexture(selectedColor[1], selectedColor[2], selectedColor[3], selectedColor[4])
        self.lastHighlightedRow = newRow
    else
        self.lastHighlightedRow = nil
    end
end

function auction:ForceClickable()
    -- больше не нужно, кнопки уже есть
end

-- ======================
-- Локальные функции ставок
-- ======================
function auction:SendBidLocal()
    if self.bidsLocked then return end
    if not self.selectedBoss or not self.selectedItem then return end
    local amount = tonumber(self.bidBox:GetText())
    if not amount or amount < 0 then return end
    if amount ~= 0 and amount < self.db.general.minBid then
        print("|cff00ff00[EPBA]|r Минимальная ставка — "..self.db.general.minBid.." EP (0 = отмена ставки)")
        return
    end
    local isOffspec = self.offspecCheckbox and self.offspecCheckbox:GetChecked() or false
    self:ForceEPUpdate(function(success, currentEP)
        if not success then return end
        local maxBid = self:GetMaxBidAmount(isOffspec)
        if amount > maxBid then
            local modeText = isOffspec and " (офф-спек)" or ""
            print(string.format("|cffff0000[EPBA]|r Недостаточно EP%s для ставки! Максимум: %s EP", modeText, self:FormatNumber(maxBid)))
            return
        end
        if self.db.general.confirmBid and amount > 0 then
            StaticPopupDialogs["EPBA_CONFIRM_BID"] = {
                text = "Подтвердите ставку\nПредмет: "..GetItemInfo(self.selectedItem).."\nСумма: "..amount.." EP" .. (isOffspec and "\n(Офф-спек, максимум: "..self:FormatNumber(maxBid).." EP)" or ""),
                button1 = "Да", button2 = "Нет",
                OnAccept = function() auction:SendBidAfterConfirm(amount, currentEP, isOffspec) end,
                timeout = 0, whileDead = true, hideOnEscape = true,
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
    if auction:IsLootMaster() then
        auction:ApplyBidChange(bossName, itemID, playerName, amount, isOffspec)
    else
        local offspecStr = isOffspec and "true" or "false"
        auction:SendToLootMaster("BID;"..bossName..";"..itemID..";"..playerName..";"..amount..";"..offspecStr)
    end
    auction.bidBox:SetText("")
end

function auction:EndAuctionLocal()
    if not self.selectedBoss then return end
    local bossName = self.selectedBoss
    self.bids[bossName] = {}
    if self.bosses[bossName] then
        for _, itemID in ipairs(self.bosses[bossName]) do
            self:IncrementDataVersion(self.selectedBoss, itemID)
            self:UpdateSortedBids(bossName, itemID)
            self:UpdateBidCaches(bossName, itemID)
        end
    end
    self:RequestRefresh()
    self:RequestSaveData()
end

-- ======================
-- ElvUI Skin
-- ======================
function auction:ApplyElvUISkin()
    if not IsAddOnLoaded("ElvUI") then return end
    local E, L, V, P, G = unpack(ElvUI)
    local S = E:GetModule("Skins")
    if not S then return end
    if self.frame then self.frame:SetTemplate("Transparent") end
    if self.bidButton then S:HandleButton(self.bidButton) end
    if self.endButton then S:HandleButton(self.endButton) end
    if self.journalButton then S:HandleButton(self.journalButton) end
    if self.queueButton then S:HandleButton(self.queueButton) end
    if self.requestButton then S:HandleButton(self.requestButton) end
    if self.optionsBtn then S:HandleButton(self.optionsBtn) end
    if self.sizer then self.sizer:SetTemplate("Default"); self.sizer:SetBackdropBorderColor(0,0,0,0); self.sizer:SetBackdropColor(0,0,0,0) end
    if self.bidBox then self.bidBox:StripTextures(); S:HandleEditBox(self.bidBox); self.bidBox:HookScript("OnEditFocusGained", function(box) box.backdrop:SetBackdropBorderColor(1,0.8,0) end); self.bidBox:HookScript("OnEditFocusLost", function(box) box.backdrop:SetBackdropBorderColor(unpack(E.media.bordercolor)) end) end
    if self.closeButton then S:HandleCloseButton(self.closeButton) end
    if self.scrollFrame then local sb = _G[self.scrollFrame:GetName().."ScrollBar"]; if sb then S:HandleScrollBar(sb) end end
    if self.bossDropdown then S:HandleDropDownBox(self.bossDropdown) end
    if self.itemDropdown then S:HandleDropDownBox(self.itemDropdown) end
end

function auction:UpdateBidRowColors()
    if not self.activeRows or not self.selectedBoss then return end
    local showTopBids = self.db.table.showTopBids or 2
    for i, row in ipairs(self.activeRows) do
        local itemID = row.itemID
        local bidsForItem = self.sortedBids[self.selectedBoss] and self.sortedBids[self.selectedBoss][itemID] or {}
        local topText = ""
        for j = 1, showTopBids do
            if bidsForItem[j] then
                local formatted = self:FormatNumber(bidsForItem[j].amount)
                local playerName = bidsForItem[j].player
                local ep = self:GetPlayerEP(playerName, false)
                local coloredName = (ep >= bidsForItem[j].amount) and self:FormatColoredName(playerName) or ("|cffff0000"..playerName.."|r")
                local offspecMark = bidsForItem[j].isOffspec and " (O)" or ""
                if j == 1 then topText = topText .. coloredName .. " - " .. formatted .. offspecMark
                else topText = topText .. " | " .. coloredName .. " - " .. formatted .. offspecMark end
            end
        end
        if row.bidsStr then row.bidsStr:SetText(topText) end
    end
end

function auction:ApplyBidChange(bossName, itemID, playerName, amount, isOffspec)
    if not bossName or not itemID or not playerName then
        return
    end

    if self:IsLootMaster() and playerName == UnitName("player") then
        self:AddBidLogEntry(playerName, amount, itemID, bossName, isOffspec)
    end

    self.bids[bossName] = self.bids[bossName] or {}
    self.bids[bossName][itemID] = self.bids[bossName][itemID] or {}

    local bids = self.bids[bossName][itemID]
    local existingBidIndex = nil

    for i, bid in ipairs(bids) do
        if bid.player == playerName then
            existingBidIndex = i
            break
        end
    end

    if amount == 0 then
        if existingBidIndex then
            table.remove(bids, existingBidIndex)
        end
    elseif existingBidIndex then
        bids[existingBidIndex].amount = amount
        bids[existingBidIndex].isOffspec = isOffspec and true or false
    else
        table.insert(bids, {
            player = playerName,
            amount = amount,
            isOffspec = isOffspec and true or false,
        })
    end

    self:UpdateSortedBids(bossName, itemID)
    self:UpdateBidCaches(bossName, itemID)
    self:CheckIfOutbid(bossName, itemID)
    if bossName == self.selectedBoss then
        if not self:RefreshRowForItem(itemID) then
            self:RequestRefresh()
        end
    end
    self:RequestSaveData()

    if self:IsLootMaster() then
        self:QueueSync(bossName, itemID)
    end
end
