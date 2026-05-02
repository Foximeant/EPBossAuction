local auction = EPBossAuction

-- Список предметов (токенов) для очереди
local ITEM_ORDER = {
    "ВЖД ГОЛОВА",
    "ПРШ ГОЛОВА",
    "ОРМЧ ГОЛОВА",
    "ВЖД ЗАПЯСТЬЯ",
    "ПРШ ЗАПЯСТЬЯ",
    "ОРМЧ ЗАПЯСТЬЯ",
    "ВЖД ПОЯС",
    "ПРШ ПОЯС",
    "ОРМЧ ПОЯС",
}

function auction:CreateQueueFrame()
    if self.queueFrame then return end
    
    local frame = CreateFrame("Frame", "EPBossAuctionQueueFrame", UIParent)
    frame:SetSize(450, 420)  -- чуть увеличили для запаса
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetMinResize(350, 300)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    tinsert(UISpecialFrames, "EPBossAuctionQueueFrame")
    self.queueFrame = frame
    
    -- Заголовок
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Очередь на токены")
    
    -- Кнопка закрытия
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() frame:Hide() end)
    self.queueCloseButton = close

    -- Выпадающий список для выбора предмета
    local itemLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemLabel:SetPoint("TOPLEFT", 16, -45)
    itemLabel:SetText("Предмет:")
    local itemDropdown = CreateFrame("Frame", "EPBAQueueItemDropdown", frame, "UIDropDownMenuTemplate")
    itemDropdown:SetPoint("LEFT", itemLabel, "RIGHT", 10, 0)
    UIDropDownMenu_SetWidth(itemDropdown, 180)
    self.queueItemDropdown = itemDropdown

    -- Контейнер для списка игроков
    local listContainer = CreateFrame("Frame", nil, frame)
    listContainer:SetPoint("TOPLEFT", 16, -80)
    listContainer:SetPoint("BOTTOMRIGHT", -16, 55)  -- освобождаем место под кнопки
    listContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    listContainer:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    listContainer:SetBackdropBorderColor(0,0,0,1)
    self.queueListContainer = listContainer

    local scrollFrame = CreateFrame("ScrollFrame", "EPBAQueueScrollFrame", listContainer, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 6, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -23, 4)  -- отступы внутри контейнера
    self.queueScrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(content)
    self.queueListContent = content

    -- Кнопки управления
    local addBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addBtn:SetSize(70, 25)
    addBtn:SetPoint("BOTTOMLEFT", 16, 16)
    addBtn:SetText("Добавить")
    addBtn:SetScript("OnClick", function() self:QueueAddPlayer() end)
    self.queueAddBtn = addBtn

    local removeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    removeBtn:SetSize(70, 25)
    removeBtn:SetPoint("LEFT", addBtn, "RIGHT", 10, 0)
    removeBtn:SetText("Удалить")
    removeBtn:SetScript("OnClick", function() self:QueueRemoveSelected() end)
    self.queueRemoveBtn = removeBtn

    local upBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    upBtn:SetSize(60, 25)
    upBtn:SetPoint("LEFT", removeBtn, "RIGHT", 15, 0)
    upBtn:SetText("Вверх")
    upBtn:SetScript("OnClick", function() self:QueueMoveUp() end)
    self.queueUpBtn = upBtn

    local downBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    downBtn:SetSize(60, 25)
    downBtn:SetPoint("LEFT", upBtn, "RIGHT", 5, 0)
    downBtn:SetText("Вниз")
    downBtn:SetScript("OnClick", function() self:QueueMoveDown() end)
    self.queueDownBtn = downBtn

    -- Кнопка обновления
    local refreshBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refreshBtn:SetSize(90, 25)
    refreshBtn:SetPoint("BOTTOMRIGHT", -16, 16)
    refreshBtn:SetText("Обновить")
    refreshBtn:SetScript("OnClick", function() self:RequestQueuesFromLM() end)
    self.queueRefreshBtn = refreshBtn

    -- Инициализация данных
    if not self.tokenQueues then
        self:LoadTokenQueues()
    end

    -- Заполнение выпадающего списка
    UIDropDownMenu_Initialize(itemDropdown, function()
        for _, name in ipairs(ITEM_ORDER) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.func = function()
                self.selectedQueueItem = name
                UIDropDownMenu_SetText(itemDropdown, name)
                self:RefreshQueueList()
            end
            info.checked = (self.selectedQueueItem == name)
            UIDropDownMenu_AddButton(info)
        end
    end)
    self.selectedQueueItem = ITEM_ORDER[1]
    UIDropDownMenu_SetText(itemDropdown, self.selectedQueueItem)

    self:UpdateQueueButtonsState()
    self:RefreshQueueList()
    self:ApplyQueueSkin()
    
    self:Debug("Окно очереди создано")
end

function auction:ToggleQueue()
    if not self.queueFrame then
        self:CreateQueueFrame()
    end
    if self.queueFrame:IsShown() then
        self.queueFrame:Hide()
    else
        self:RefreshQueueList()
        self.queueFrame:Show()
    end
end

function auction:RefreshQueueList()
    local content = self.queueListContent
    local scrollFrame = self.queueScrollFrame
    if not content or not scrollFrame then return end

    -- Удаляем все дочерние элементы из content
    for _, child in ipairs({content:GetChildren()}) do
        local objType = child:GetObjectType()
        if objType == "Frame" or objType == "Button" then
            child:SetParent(nil)
        end
        child:Hide()
    end

    local itemKey = self.selectedQueueItem
    if not itemKey then return end

    local queue = self.tokenQueues and self.tokenQueues[itemKey] or {}
    local rowHeight = 24
    -- Ширина = ширина скролл-фрейма минус ширина скроллбара (обычно ~18) и небольшие отступы
    local width = scrollFrame:GetWidth() - 0
    if width < 50 then width = 300 end

    content:SetWidth(width)
    content:SetHeight(rowHeight * math.max(#queue, 1))

    for i, playerName in ipairs(queue) do
        local row = CreateFrame("Button", nil, content)
        row:SetPoint("TOPLEFT", 0, -rowHeight*(i-1))
        row:SetSize(width, rowHeight)
        row:SetNormalFontObject(GameFontNormal)
        row:SetHighlightFontObject(GameFontHighlight)

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", 5, 0)
        text:SetText(i..". "..playerName)
        text:SetTextColor(1, 1, 1)
        row.text = text

        row:SetScript("OnClick", function()
            self.queueSelectedIndex = i
            self:RefreshQueueList()
        end)

        if self.queueSelectedIndex == i then
            local highlight = row:CreateTexture(nil, "BACKGROUND")
            highlight:SetAllPoints()
            highlight:SetTexture(0.3, 0.6, 1, 0.3)
            row.highlight = highlight
        end

        row:SetScript("OnEnter", function()
            if self.queueSelectedIndex ~= i then
                if not row.hover then
                    local hover = row:CreateTexture(nil, "BACKGROUND")
                    hover:SetAllPoints()
                    hover:SetTexture(0.2, 0.2, 0.2, 0.5)
                    row.hover = hover
                else
                    row.hover:Show()
                end
            end
        end)
        row:SetScript("OnLeave", function()
            if row.hover then
                row.hover:Hide()
            end
        end)
    end

    scrollFrame:SetVerticalScroll(0)
    scrollFrame:UpdateScrollChildRect()

    self:UpdateQueueButtonsState()
    self:Debug("RefreshQueueList: "..itemKey..", строк: "..#queue..", ширина: "..width)
end

function auction:QueueAddPlayer()
    if not self:IsLootMaster() then return end
    StaticPopupDialogs["EPBA_ADD_TO_QUEUE"] = {
        text = "Введите имя игрока для добавления в очередь:",
        button1 = "Добавить",
        button2 = "Отмена",
        hasEditBox = true,
        OnAccept = function(selfPopup)
            local name = selfPopup.editBox:GetText()
            if name and name ~= "" then
                auction:QueueAddPlayerByName(auction.selectedQueueItem, name)
            end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    StaticPopup_Show("EPBA_ADD_TO_QUEUE")
end

function auction:QueueAddPlayerByName(itemKey, playerName)
    if not itemKey then return end
    if not self.tokenQueues then self:LoadTokenQueues() end
    if not self.tokenQueues[itemKey] then self.tokenQueues[itemKey] = {} end
    local queue = self.tokenQueues[itemKey]
    for _, v in ipairs(queue) do
        if v == playerName then return end
    end
    table.insert(queue, playerName)
    self.queueSelectedIndex = #queue
    self:RefreshQueueList()
    self:SaveTokenQueues()
    self:SendQueueUpdate(itemKey)
end

function auction:QueueRemoveSelected()
    if not self:IsLootMaster() then return end
    local idx = self.queueSelectedIndex
    if not idx then return end
    local itemKey = self.selectedQueueItem
    local queue = self.tokenQueues[itemKey]
    if queue and queue[idx] then
        table.remove(queue, idx)
        self.queueSelectedIndex = nil
        self:RefreshQueueList()
        self:SaveTokenQueues()
        self:SendQueueUpdate(itemKey)
    end
end

function auction:QueueMoveUp()
    if not self:IsLootMaster() then return end
    local idx = self.queueSelectedIndex
    if not idx or idx <= 1 then return end
    local itemKey = self.selectedQueueItem
    local queue = self.tokenQueues[itemKey]
    queue[idx], queue[idx-1] = queue[idx-1], queue[idx]
    self.queueSelectedIndex = idx - 1
    self:RefreshQueueList()
    self:SaveTokenQueues()
    self:SendQueueUpdate(itemKey)
end

function auction:QueueMoveDown()
    if not self:IsLootMaster() then return end
    local idx = self.queueSelectedIndex
    local itemKey = self.selectedQueueItem
    local queue = self.tokenQueues[itemKey]
    if not idx or idx >= #queue then return end
    queue[idx], queue[idx+1] = queue[idx+1], queue[idx]
    self.queueSelectedIndex = idx + 1
    self:RefreshQueueList()
    self:SaveTokenQueues()
    self:SendQueueUpdate(itemKey)
end

function auction:UpdateQueueButtonsState()
    local isLM = self:IsLootMaster()
    local alpha = isLM and 1 or 0.5
    if self.queueAddBtn then self.queueAddBtn:SetEnabled(isLM); self.queueAddBtn:SetAlpha(alpha) end
    if self.queueRemoveBtn then self.queueRemoveBtn:SetEnabled(isLM); self.queueRemoveBtn:SetAlpha(alpha) end
    if self.queueUpBtn then self.queueUpBtn:SetEnabled(isLM); self.queueUpBtn:SetAlpha(alpha) end
    if self.queueDownBtn then self.queueDownBtn:SetEnabled(isLM); self.queueDownBtn:SetAlpha(alpha) end
    if self.queueRefreshBtn then self.queueRefreshBtn:SetEnabled(true); self.queueRefreshBtn:SetAlpha(1) end
end

function auction:SendQueueUpdate(itemKey)
    if not self:IsLootMaster() then return end
    local queue = self.tokenQueues[itemKey] or {}
    local msg = "QUEUE_UPDATE;"..itemKey..";"..table.concat(queue, ",")
    SendAddonMessage(self.prefix, msg, "RAID")
end

function auction:SaveTokenQueues()
    if not self.db.tokenQueues then self.db.tokenQueues = {} end
    self.db.tokenQueues = self.tokenQueues
    self:SaveSettings()
end

function auction:LoadTokenQueues()
    if self.db and self.db.tokenQueues then
        self.tokenQueues = self.db.tokenQueues
    else
        self.tokenQueues = {}
        for _, name in ipairs(ITEM_ORDER) do
            self.tokenQueues[name] = {}
        end
    end
    self:Debug("LoadTokenQueues выполнено")
end

function auction:RequestQueuesFromLM()
    if self:IsLootMaster() then
        self:SyncAllQueuesToRaid()
        return
    end
    self:Debug("Запрос очередей у лутера")
    SendAddonMessage(self.prefix, "QUEUE_REQUEST", "RAID")
end

function auction:SyncAllQueuesToRaid(target)
    if not self:IsLootMaster() then return end
    local recipient = target
    for itemKey, queue in pairs(self.tokenQueues) do
        local msg = "QUEUE_SYNC;"..itemKey..";"..table.concat(queue, ",")
        if target then
            SendAddonMessage(self.prefix, msg, "WHISPER", recipient)
        else
            SendAddonMessage(self.prefix, msg, "RAID")
        end
    end
    self:Debug("Очереди отправлены "..(target and ("игроку "..target) or "в рейд"))
end

function auction:Handle_QUEUE_UPDATE(rest, sender)
    local itemKey, players = rest:match("([^;]+);(.*)")
    if not itemKey or not self.tokenQueues then return end
    local queue = {}
    if players ~= "" then
        for name in players:gmatch("([^,]+)") do
            table.insert(queue, name)
        end
    end
    self.tokenQueues[itemKey] = queue
    if self.queueFrame and self.queueFrame:IsShown() and self.selectedQueueItem == itemKey then
        self:RefreshQueueList()
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Очередь на "..itemKey.." обновлена.")
end

function auction:Handle_QUEUE_REQUEST(rest, sender)
    if not self:IsLootMaster() then return end
    self:SyncAllQueuesToRaid(sender)
end

function auction:Handle_QUEUE_SYNC(rest, sender)
    local itemKey, players = rest:match("([^;]+);(.*)")
    if not itemKey then return end
    local queue = {}
    if players ~= "" then
        for name in players:gmatch("([^,]+)") do
            table.insert(queue, name)
        end
    end
    self.tokenQueues[itemKey] = queue
    if self.queueFrame and self.queueFrame:IsShown() and self.selectedQueueItem == itemKey then
        self:RefreshQueueList()
    end
    self:Debug("Очередь синхронизирована: "..itemKey)
end

function auction:ApplyQueueSkin()
    if not self.queueFrame then return end
    self:SkinPanel(self.queueFrame)
    if self.queueCloseButton then self:SkinButton(self.queueCloseButton) end
    if self.queueAddBtn then self:SkinButton(self.queueAddBtn) end
    if self.queueRemoveBtn then self:SkinButton(self.queueRemoveBtn) end
    if self.queueUpBtn then self:SkinButton(self.queueUpBtn) end
    if self.queueDownBtn then self:SkinButton(self.queueDownBtn) end
    if self.queueRefreshBtn then self:SkinButton(self.queueRefreshBtn) end
    if self.queueItemDropdown then self:SkinDropdown(self.queueItemDropdown) end
    if self.queueListContainer then self:SkinPanel(self.queueListContainer) end
    if self.queueScrollFrame then
        local sb = _G[self.queueScrollFrame:GetName().."ScrollBar"]
        if sb then self:SkinScrollBar(sb) end
    end
end
