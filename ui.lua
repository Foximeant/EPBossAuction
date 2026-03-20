local auction = EPBossAuction

-- ======================
-- Создание основного окна
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

    -- Заголовок
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Ruining System ставки EP")

    -- Кнопка закрытия
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    self.closeButton = close
    close:SetPoint("TOPRIGHT", -5, -5)

    -- Кнопка настроек
    local optionsBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
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

    -- Dropdown боссы
    local dropdown = CreateFrame("Frame", "EPBossDropdown", frame, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", 16, -40)
    UIDropDownMenu_SetWidth(dropdown, 200)
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

    -- ======================
    -- Чекбокс блокировки ставок
    -- ======================
    local lockCheckbox = CreateFrame("CheckButton", "EPBALockCheckbox", frame, "UICheckButtonTemplate")
    lockCheckbox:SetPoint("LEFT", dropdown, "RIGHT", 10, 0)
    lockCheckbox:SetSize(25, 25)
    lockCheckbox.text = lockCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lockCheckbox.text:SetPoint("LEFT", lockCheckbox, "RIGHT", 2, 0)
    lockCheckbox.text:SetText("Блокировка ставок")
    lockCheckbox:SetChecked(self.bidsLocked or false)

        if not self:IsLootMaster() then
        lockCheckbox:Disable()
        lockCheckbox:SetAlpha(0.5)
    else
        lockCheckbox:SetScript("OnClick", function(self)
            local checked = self:GetChecked()  -- 1 или nil
            local state = (checked == 1)       -- преобразуем в true/false
            auction:SetBidsLocked(state)
            -- Отправляем строку "true" или "false"
            SendAddonMessage(auction.prefix, "LOCK;"..(state and "true" or "false"), "RAID")
        end)
    end
    self.lockCheckbox = lockCheckbox

    -- Фон для скролла
    local scrollBG = CreateFrame("Frame", nil, frame)
    scrollBG:SetPoint("TOPLEFT", 16, -102)
    scrollBG:SetPoint("BOTTOMRIGHT", -30, 80)
    scrollBG:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    scrollBG:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    scrollBG:SetBackdropBorderColor(0,0,0,1)
    scrollBG:Show()

    -- ScrollFrame
    local scrollFrame = CreateFrame("ScrollFrame", "EPBossAuctionScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 16, -102)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 80)
    self.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(580, 300)
    scrollFrame:SetScrollChild(content)
    self.content = content

    -- Заголовки
    local header = CreateFrame("Frame", nil, frame)
    header:SetSize(580, 22)
    header:SetPoint("TOPLEFT", 16, -80)
    auction.header = header

    local headerItem = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    headerItem:SetPoint("TOPLEFT", 10, 0)
    headerItem:SetText("Предмет")
    headerItem:SetWidth(250)

    local headerBids = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    headerBids:SetPoint("TOPLEFT", 300, 0)
    headerBids:SetText("Топ 2 ставки")
    headerBids:SetWidth(250)

    -- Dropdown предметов
    local itemDrop = CreateFrame("Frame", "EPItemDropdown", frame, "UIDropDownMenuTemplate")
    itemDrop:SetPoint("BOTTOMLEFT", 16, 40)
    UIDropDownMenu_SetWidth(itemDrop, 220)
    UIDropDownMenu_SetText(itemDrop, "Выбрать предмет")
    self.itemDropdown = itemDrop

    -- EditBox (без изменений)
    local editBox = CreateFrame("EditBox", "EPBidEditBox", frame, "InputBoxTemplate")
    editBox:SetSize(100, 25)
    editBox:SetPoint("LEFT", itemDrop, "RIGHT", 10, 0)
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
        if amount > 0 and amount > auction.myEP then
            self:SetTextColor(1, 0, 0)
            auction.myEPText:SetTextColor(1, 0, 0)
        else
            self:SetTextColor(1, 1, 1)
            auction.myEPText:SetTextColor(1, 1, 1)
        end
    end)
    editBox:SetScript("OnEnterPressed", function()
        auction:SendBidLocal()
    end)
    self.bidBox = editBox

    -- Текст ЕП
    local epText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    epText:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", 0, -5)
    epText:SetText("Ваш ЕП: ...")
    auction.myEPText = epText

    -- Кнопка ставки
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.bidButton = button
    button:SetSize(140, 25)
    button:SetPoint("LEFT", editBox, "RIGHT", 10, 0)
    button:SetText("Сделать ставку")
    button:SetScript("OnClick", function()
        auction:SendBidLocal()
    end)

    -- Кнопка очистки
    local endButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    endButton:SetSize(140, 25)
    endButton:SetPoint("LEFT", editBox, "RIGHT", 10, -30)
    endButton:SetText("Очистить таблицу")
    endButton:SetScript("OnClick", function()
        if not auction:IsLootMaster() then
            --print("|cff00ff00[EPBA]|r Только Loot Master может завершать аукцион!")
            return
        end
        auction:EndAuctionLocal()
        if auction.selectedBoss then
            SendAddonMessage(auction.prefix, "END;"..auction.selectedBoss, "RAID")
        end
    end)
    self.endButton = endButton

    -- Кнопка в чат
    local chatButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    chatButton:SetSize(70, 25)
    chatButton:SetPoint("LEFT", endButton, "RIGHT", 10, 0)
    chatButton:SetText("В чат")
    chatButton:SetScript("OnClick", function()
        if not auction:IsLootMaster() then
            --print("|cff00ff00[EPBA]|r Только Loot Master может отправлять в чат!")
            return
        end
        if not auction.selectedBoss then
            --print("|cff00ff00[EPBA]|r Сначала выберите босса!")
            return
        end
        local bossBids = auction.bids[auction.selectedBoss]
        if not bossBids then
            --print("|cff00ff00[EPBA]|r На этом боссе ставок пока нет.")
            return
        end
        SendChatMessage("Ставки на "..auction.selectedBoss..":", "RAID")
        auction:ScheduleTimer(function()
            local sentCount = 0
            for itemID, bidsForItem in pairs(bossBids) do
                if type(bidsForItem) == "table" and #bidsForItem > 0 then
                    local itemName = GetItemInfo(itemID) or ("предмет "..itemID)
                    table.sort(bidsForItem, function(a,b) return a.amount>b.amount end)
                    local bidsText = {}
                    for _, bid in ipairs(bidsForItem) do
                        table.insert(bidsText, bid.player .. " - " .. auction:FormatNumber(bid.amount))
                    end
                    local message = itemName..": "..table.concat(bidsText, ", ")
                    SendChatMessage(message, "RAID")
                    sentCount = sentCount + 1
                end
            end
            --print("|cff00ff00[EPBA]|r Отправлено "..sentCount.." предметов в рейд")
        end, 1)
    end)
    self.chatButton = chatButton

    -- Кнопка "Запросить данные"
    local requestButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.requestButton = requestButton
    requestButton:SetSize(70, 25)
    requestButton:SetPoint("LEFT", button, "RIGHT", 10, 0)
    requestButton:SetText("Запросить")
    requestButton:SetScript("OnClick", function()
        auction:RequestDataFromLM()
    end)

    -- Устанавливаем начальное состояние кнопок (доступны только лутеру)
    self:UpdateLMButtonsState()

    -- Slash команды
    SLASH_EPBA1 = "/epba"
    SlashCmdList["EPBA"] = function()
        if frame:IsShown() then 
            frame:Hide() 
        else 
            frame:Show()
            auction:ForceEPUpdate()
        end
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
                print("|cff00ff00[EPBA]|r EP обновлен: "..auction:FormatNumber(ep))
            else
                print("|cffff0000[EPBA]|r Не удалось обновить EP")
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

    frame:SetScript("OnShow", function()
        auction:ForceClickable()
        auction:UpdateLMButtonsState()  -- обновляем состояние при открытии
    end)

    auction:ApplyElvUISkin()
end

-- ======================
-- Установка состояния блокировки (локально)
-- ======================
function auction:SetBidsLocked(state)
    self.bidsLocked = state
    if self.lockCheckbox then
        self.lockCheckbox:SetChecked(state)
    end
    -- Блокируем кнопку ставки для всех при включённой блокировке
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
-- Обновление состояния чекбокса при смене лутера
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
    -- обновление кнопки ставки остаётся без изменений
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
    if not self.endButton or not self.chatButton then return end
    local isLM = self:IsLootMaster()
    self.endButton:SetEnabled(isLM)
    self.chatButton:SetEnabled(isLM)
    
    -- Визуально затемняем кнопки, если они отключены
    if isLM then
        self.endButton:SetAlpha(1.0)
        self.chatButton:SetAlpha(1.0)
    else
        self.endButton:SetAlpha(0.5)
        self.chatButton:SetAlpha(0.5)
    end
end

-- ======================
-- Обновление таблицы (с защитой от nil)
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
    local itemWidth = dbTable.itemWidth or 250
    local bidFontSize = dbTable.bidFontSize or 12
    local bidWidth = dbTable.bidWidth or 250
    local rowHeight = dbTable.rowHeight or 20
    local showIcons = dbTable.showIcons ~= false
    local showTopBids = dbTable.showTopBids or 2
    local evenColor = dbTable.evenRowColor or {1,1,1,0.03}
    local oddColor = dbTable.oddRowColor or {0,0,0,0}
    local selectedColor = dbTable.selectedRowColor or {0.3,0.6,1,0.3}
    local hoverColor = dbTable.hoverRowColor or {0.2,0.2,0.2,0.5}

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

    if self.rowFrames then
        for _, t in ipairs(self.rowFrames) do
            if t.bg then t.bg:Hide() end
            if t.icon then t.icon:Hide() end
            if t.row then t.row:Hide() end
            if t.bidsStr then t.bidsStr:Hide() end
            if t.clickFrame then t.clickFrame:Hide() end
        end
    end

    self.rowFrames = {}
    local content = self.content
    content:SetHeight(rowHeight * #items)

    for i, itemID in ipairs(items) do
        local rowTable = {}

        local bg = content:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -rowHeight*(i-1))
        bg:SetSize(594, rowHeight)
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
            local iconSize = rowHeight - 2  -- иконка чуть меньше высоты строки для отступа
            icon:SetSize(iconSize, iconSize)
            icon:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -(rowHeight*(i-1) + 2)) -- центрируем по вертикали
            icon:SetTexture(GetItemIcon(itemID) or "Interface/Icons/INV_Misc_QuestionMark")
            rowTable.icon = icon
        end

        -- Название предмета
        local row = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        if showIcons then
            row:SetPoint("LEFT", rowTable.icon, "RIGHT", 5, 0)
        else
            row:SetPoint("LEFT", content, "LEFT", 0, 0)
        end
        row:SetWidth(itemWidth)
        row:SetJustifyH("LEFT")
        row:SetWordWrap(true)
        row:SetFont(GameFontNormal:GetFont(), itemFontSize)
        row:SetHeight(rowHeight)
        local itemName = GetItemInfo(itemID) or ("item:"..itemID)
        row:SetText(itemName)

        -- Установка цвета в зависимости от настройки
        local colorMode = self.db.table.itemColorMode or "gold"
        if colorMode == "gold" then
            row:SetTextColor(1, 0.8, 0)  -- золотой
        else
            -- Цвет редкости предмета
            local _, _, quality = GetItemInfo(itemID)
            if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
                local c = ITEM_QUALITY_COLORS[quality]
                row:SetTextColor(c.r, c.g, c.b)
            else
                row:SetTextColor(1, 1, 1)  -- белый, если не удалось определить
            end
        end

        rowTable.row = row

        -- Ставки
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
                if j == 1 then
                    topText = topText .. coloredName .. " - " .. formatted
                else
                    topText = topText .. " | " .. coloredName .. " - " .. formatted
                end
                topText = topText .. "|r"
            end
        end
        bidsStr:SetText(topText)
        rowTable.bidsStr = bidsStr

                -- Кликабельный фрейм
        local clickFrame = CreateFrame("Button", nil, content)
        clickFrame:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, 0)
        clickFrame:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)
        clickFrame:EnableMouse(true)
        clickFrame:SetFrameLevel(content:GetFrameLevel() + 20)
        local currentItemID = itemID
        local currentRow = i
        local currentBg = bg

        clickFrame:SetScript("OnClick", function(_, button)
            -- Если зажат Shift, линкуем предмет в чат
            if IsShiftKeyDown() then
                local itemLink = GetItemInfo(currentItemID)
                if itemLink then
                    ChatEdit_InsertLink(itemLink)
                else
                    print("|cffff0000[EPBA]|r Не удалось получить ссылку на предмет.")
                end
                return
            end
            -- Обычный клик – выбор предмета для ставки
            auction.selectedItem = currentItemID
            local itemName = GetItemInfo(currentItemID) or ("item:"..tostring(currentItemID))
            UIDropDownMenu_SetText(auction.itemDropdown, itemName)
            auction:HighlightSelectedRow(currentItemID)
            auction.bidBox:SetFocus()
        end)

        clickFrame:SetScript("OnEnter", function()
            local anchor = "ANCHOR_" .. (self.db.table.tooltipAnchor or "CURSOR")
            GameTooltip:SetOwner(clickFrame, anchor)
            -- Если зажат Shift, показываем сравнение с экипированным
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

        clickFrame:SetScript("OnLeave", function()
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

        rowTable.clickFrame = clickFrame
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
        if rowTable.clickFrame then
            rowTable.clickFrame:EnableMouse(true)
            rowTable.clickFrame:Show()
            rowTable.clickFrame:SetFrameLevel(self.content:GetFrameLevel() + 20)
        end
    end
end

-- ======================
-- Локальные функции ставок
-- ======================
function auction:ProcessBidLocally(bossName, itemID, playerName, amount)
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
        local coloredName = self:FormatColoredName(playerName)
        print("|cff00ff00[EPBA]|r "..coloredName.."|r отказался от ставки.")
        return
    end
    if amount < self.db.general.minBid then
        print("|cff00ff00[EPBA]|r Ставка не может быть меньше минимальной ("..self.db.general.minBid..")")
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
    else
        table.insert(self.bids[bossName][itemID], {
            player = playerName,
            amount = amount
        })
    end
    self:RefreshTable()
    self:SendSync(bossName, itemID)
    local coloredName = self:FormatColoredName(playerName)
    --print("|cff00ff00[EPBA]|r Ставка "..(existingBid and "изменена" or "принята").." от "..coloredName.."|r: "..amount)
end

function auction:SendBidLocal()
    -- Проверка блокировки ставок
    if self.bidsLocked then
        --print("|cffff0000[EPBA]|r Приём ставок временно заблокирован лутером.")
        return
    end

    if not self.selectedBoss or not self.selectedItem then
        --print("|cff00ff00[EPBA]|r Выберите босса и предмет!")
        return
    end
    local amount = tonumber(self.bidBox:GetText())
    if not amount or amount < 0 then
        --print("|cff00ff00[EPBA]|r Введите корректную ставку!")
        return
    end
    if amount ~= 0 and amount < self.db.general.minBid then
        print("|cff00ff00[EPBA]|r Минимальная ставка — "..self.db.general.minBid.." EP (0 = отмена ставки)")
        return
    end
    self:ForceEPUpdate(function(success, currentEP)
        if not success then
            print("|cffff0000[EPBA]|r Не удалось получить актуальный EP!")
            return
        end
        if amount > currentEP then
            --print("|cffff0000[EPBA]|r Ставка не может быть больше вашего ЕП ("..currentEP..")")
            return
        end
        if self.db.general.confirmBid and amount > 0 then
            StaticPopupDialogs["EPBA_CONFIRM_BID"] = {
                text = "Подтвердите ставку\nПредмет: "..GetItemInfo(self.selectedItem).."\nСумма: "..amount.." EP",
                button1 = "Да",
                button2 = "Нет",
                OnAccept = function()
                    auction:SendBidAfterConfirm(amount, currentEP)
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
            }
            StaticPopup_Show("EPBA_CONFIRM_BID")
        else
            self:SendBidAfterConfirm(amount, currentEP)
        end
    end)
end

function auction:SendBidAfterConfirm(amount, currentEP)
    local bossName = auction.selectedBoss
    local itemID = auction.selectedItem
    local playerName = UnitName("player")
    auction:Debug("Отправка ставки: "..playerName.." "..amount.." на "..bossName.." "..itemID)
    if auction:IsLootMaster() then
        auction:ProcessBidLocally(bossName, itemID, playerName, amount)
    else
        local msg = "BID;"..bossName..";"..itemID..";"..playerName..";"..amount
        SendAddonMessage(auction.prefix, msg, "RAID")
        --print("|cff00ff00[EPBA]|r Ставка отправлена лутеру: "..amount)
    end
    auction.bidBox:SetText("")
end

function auction:EndAuctionLocal()
    if not self.selectedBoss then return end
    self.bids[self.selectedBoss] = {}
    self.dataVersions[self.selectedBoss] = (self.dataVersions[self.selectedBoss] or 0) + 1
    self:RefreshTable()
    self:SaveData()
    --print("|cff00ff00[EPBA]|r Аукцион для "..self.selectedBoss.." завершён!")
end

-- ======================
-- ElvUI Skin (для главного окна) с поддержкой чекбокса
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
    if self.chatButton then S:HandleButton(self.chatButton) end
    if self.requestButton then S:HandleButton(self.requestButton) end
    if self.optionsBtn then S:HandleButton(self.optionsBtn) end
    -- Чекбокс блокировки не обрабатываем скином, чтобы избежать бага с галочкой
    -- (он останется стандартным, но будет правильно отображать состояние)
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
