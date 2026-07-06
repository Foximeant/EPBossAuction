local auction = EPBossAuction

-- ======================
-- Типы токенов и слоты
-- ======================
local TOKEN_TYPES = {
    "Охотник/Разбойник/Маг/Чернокнижник",
    "Воин/Жрец/Друид",
    "Паладин/Разбойник/Шаман",
}

local TOKEN_SLOTS = {
    "Голова",
    "Плечи",
    "Грудь",
    "Руки",
    "Ноги",
}

local function GetItemKey(tokenType, slot)
    if not tokenType or not slot then return nil end
    return tokenType.." — "..slot
end

local function FormatElapsedTime(timestamp)
    if not timestamp then return "" end
    local diff = time() - timestamp
    if diff < 0 then diff = 0 end
    if diff < 60 then
        return "только что"
    elseif diff < 3600 then
        return math.floor(diff / 60).." мин назад"
    elseif diff < 86400 then
        return math.floor(diff / 3600).." ч назад"
    else
        return math.floor(diff / 86400).." дн назад"
    end
end

function auction:CreateQueueFrame()
    if self.queueFrame then return end

    local frame = CreateFrame("Frame", "EPBossAuctionQueueFrame", UIParent)
    frame:SetSize(460, 460)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(110)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetMinResize(360, 340)
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
    local close = CreateFrame("Button", nil, frame)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetText("X")
    close:SetNormalFontObject(GameFontNormalLarge)
    close:SetScript("OnClick", function() frame:Hide() end)
    self.queueCloseButton = close

    -- Выпадающий список: тип токена
    local typeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    typeLabel:SetPoint("TOPLEFT", 16, -42)
    typeLabel:SetText("Тип:")
    local typeDropdown = CreateFrame("Frame", "EPBAQueueTypeDropdown", frame, "UIDropDownMenuTemplate")
    typeDropdown:SetPoint("LEFT", typeLabel, "RIGHT", 2, -2)
    UIDropDownMenu_SetWidth(typeDropdown, 260)
    self.queueTypeDropdown = typeDropdown

    -- Выпадающий список: слот
    local slotLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    slotLabel:SetPoint("TOPLEFT", 16, -72)
    slotLabel:SetText("Слот:")
    local slotDropdown = CreateFrame("Frame", "EPBAQueueSlotDropdown", frame, "UIDropDownMenuTemplate")
    slotDropdown:SetPoint("LEFT", slotLabel, "RIGHT", 2, -2)
    UIDropDownMenu_SetWidth(slotDropdown, 140)
    self.queueSlotDropdown = slotDropdown

    -- Контейнер для списка игроков
    local listContainer = CreateFrame("Frame", nil, frame)
    listContainer:SetPoint("TOPLEFT", 16, -104)
    listContainer:SetPoint("BOTTOMRIGHT", -16, 80)
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
    scrollFrame:SetPoint("BOTTOMRIGHT", -23, 4)
    self.queueScrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(content)
    self.queueListContent = content

    -- Строка самозаписи — доступна всем, не только лутеру
    local myQueueButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    myQueueButton:SetSize(170, 24)
    myQueueButton:SetPoint("BOTTOMRIGHT", -16, 50)
    myQueueButton:SetScript("OnClick", function() self:ToggleMySignup() end)
    self.queueMyButton = myQueueButton

    local myStatusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    myStatusText:SetPoint("BOTTOMLEFT", 16, 56)
    myStatusText:SetPoint("RIGHT", myQueueButton, "LEFT", -10, 0)
    myStatusText:SetJustifyH("LEFT")
    self.queueMyStatusText = myStatusText

    -- Кнопки управления (только лутер)
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

    -- Заполнение выпадающего списка типов
    UIDropDownMenu_Initialize(typeDropdown, function()
        for _, tokenType in ipairs(TOKEN_TYPES) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = tokenType
            info.func = function()
                self.selectedQueueType = tokenType
                UIDropDownMenu_SetText(typeDropdown, tokenType)
                self.selectedQueueItem = GetItemKey(self.selectedQueueType, self.selectedQueueSlot)
                self.queueSelectedIndex = nil
                self.db.tokenQueue.lastType = tokenType
                self:SaveSettings()
                self:RefreshQueueList()
            end
            info.checked = (self.selectedQueueType == tokenType)
            UIDropDownMenu_AddButton(info)
        end
    end)

    -- Заполнение выпадающего списка слотов
    UIDropDownMenu_Initialize(slotDropdown, function()
        for _, slot in ipairs(TOKEN_SLOTS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = slot
            info.func = function()
                self.selectedQueueSlot = slot
                UIDropDownMenu_SetText(slotDropdown, slot)
                self.selectedQueueItem = GetItemKey(self.selectedQueueType, self.selectedQueueSlot)
                self.queueSelectedIndex = nil
                self.db.tokenQueue.lastSlot = slot
                self:SaveSettings()
                self:RefreshQueueList()
            end
            info.checked = (self.selectedQueueSlot == slot)
            UIDropDownMenu_AddButton(info)
        end
    end)

    local function isValidType(v)
        for _, t in ipairs(TOKEN_TYPES) do if t == v then return true end end
        return false
    end
    local function isValidSlot(v)
        for _, s in ipairs(TOKEN_SLOTS) do if s == v then return true end end
        return false
    end

    self.selectedQueueType = isValidType(self.db.tokenQueue.lastType) and self.db.tokenQueue.lastType or TOKEN_TYPES[1]
    self.selectedQueueSlot = isValidSlot(self.db.tokenQueue.lastSlot) and self.db.tokenQueue.lastSlot or TOKEN_SLOTS[1]
    self.selectedQueueItem = GetItemKey(self.selectedQueueType, self.selectedQueueSlot)
    UIDropDownMenu_SetText(typeDropdown, self.selectedQueueType)
    UIDropDownMenu_SetText(slotDropdown, self.selectedQueueSlot)

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
    local width = scrollFrame:GetWidth() - 0
    if width < 50 then width = 300 end

    content:SetWidth(width)
    content:SetHeight(rowHeight * math.max(#queue, 1))

    for i, entry in ipairs(queue) do
        local row = CreateFrame("Button", nil, content)
        row:SetPoint("TOPLEFT", 0, -rowHeight*(i-1))
        row:SetSize(width, rowHeight)
        row:SetNormalFontObject(GameFontNormal)
        row:SetHighlightFontObject(GameFontHighlight)

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", 5, 0)
        text:SetPoint("RIGHT", -5, 0)
        text:SetJustifyH("LEFT")
        text:SetText(i..". "..entry.player.." |cff888888("..FormatElapsedTime(entry.time)..")|r")
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
    self:UpdateMyQueueButton()
    self:Debug("RefreshQueueList: "..itemKey..", строк: "..#queue..", ширина: "..width)
end

-- ======================
-- Ручное управление (лутер)
-- ======================
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
    if not itemKey or not self:IsLootMaster() then return end
    if not self.tokenQueues then self:LoadTokenQueues() end
    self:InsertQueueSignup(itemKey, playerName, time())
    local queue = self.tokenQueues[itemKey] or {}
    for i, entry in ipairs(queue) do
        if entry.player == playerName then
            self.queueSelectedIndex = i
            break
        end
    end
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
        local removedPlayer = queue[idx].player
        table.remove(queue, idx)
        self.queueSelectedIndex = nil
        self:RefreshQueueList()
        self:SaveTokenQueues()
        self:SendQueueUpdate(itemKey)

        if removedPlayer == UnitName("player") then
            self.db.mySignups = self.db.mySignups or {}
            self.db.mySignups[itemKey] = nil
            self:SaveSettings()
        end
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

-- ======================
-- Общие помощники очереди (сортировка по времени записи)
-- ======================
local function InsertQueueEntrySorted(queue, newEntry)
    local insertAt = #queue + 1
    for i, entry in ipairs(queue) do
        if newEntry.time < entry.time then
            insertAt = i
            break
        end
    end
    table.insert(queue, insertAt, newEntry)
end

-- Вставляет/обновляет запись игрока в очереди на itemKey. Если игрок уже
-- есть в очереди — сохраняется САМАЯ РАННЯЯ метка времени (повторная отправка
-- при переподключении не должна двигать игрока в очереди).
-- Возвращает true, если что-то реально изменилось (нужно разослать обновление).
function auction:InsertQueueSignup(itemKey, playerName, timestamp)
    if not (itemKey and playerName and timestamp) then return false end
    self.tokenQueues = self.tokenQueues or {}
    local queue = self.tokenQueues[itemKey]
    if not queue then
        queue = {}
        self.tokenQueues[itemKey] = queue
    end

    for i, entry in ipairs(queue) do
        if entry.player == playerName then
            if timestamp < entry.time then
                table.remove(queue, i)
                InsertQueueEntrySorted(queue, { player = playerName, time = timestamp })
                return true
            end
            return false
        end
    end

    InsertQueueEntrySorted(queue, { player = playerName, time = timestamp })
    return true
end

function auction:RemoveQueueEntryByPlayer(itemKey, playerName)
    local queue = self.tokenQueues and self.tokenQueues[itemKey]
    if not queue then return false end
    for i, entry in ipairs(queue) do
        if entry.player == playerName then
            table.remove(queue, i)
            return true
        end
    end
    return false
end

-- ======================
-- Самозапись (доступна всем, работает даже вне рейда)
-- ======================
function auction:UpdateMyQueueButton()
    if not (self.queueMyButton and self.queueMyStatusText) then return end
    local itemKey = self.selectedQueueItem
    if not itemKey then return end
    self.db.mySignups = self.db.mySignups or {}
    local ts = self.db.mySignups[itemKey]
    if ts then
        self.queueMyButton:SetText("Выйти из очереди")
        self.queueMyStatusText:SetText("Вы записаны ("..FormatElapsedTime(ts)..")")
    else
        self.queueMyButton:SetText("Записаться в очередь")
        self.queueMyStatusText:SetText("Вы не записаны на этот предмет")
    end
end

function auction:ToggleMySignup()
    local itemKey = self.selectedQueueItem
    if not itemKey then return end
    self.db.mySignups = self.db.mySignups or {}

    if self.db.mySignups[itemKey] then
        if self.db.general.confirmQueueLeave then
            StaticPopupDialogs["EPBA_CONFIRM_QUEUE_LEAVE"] = {
                text = "Выйти из очереди на \""..itemKey.."\"?",
                button1 = "Да",
                button2 = "Отмена",
                OnAccept = function()
                    auction:LeaveMySignup(itemKey)
                end,
                timeout = 0, whileDead = true, hideOnEscape = true,
            }
            StaticPopup_Show("EPBA_CONFIRM_QUEUE_LEAVE")
        else
            self:LeaveMySignup(itemKey)
        end
        return
    end

    -- Записаться
    local playerName = UnitName("player")
    local ts = time()
    self.db.mySignups[itemKey] = ts
    self:SaveSettings()
    if self:IsLootMaster() then
        if self:InsertQueueSignup(itemKey, playerName, ts) then
            self:SaveTokenQueues()
            self:SendQueueUpdate(itemKey)
        end
    elseif IsInRaid() or IsInGroup() then
        self:SendToLootMaster("QUEUE_JOIN;"..itemKey..":"..ts)
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Запись отправлена лутеру.")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Запись сохранена. Она уедет лутеру, как только вы окажетесь с ним в одной группе.")
    end

    self:RefreshQueueList()
end

-- Собственно выход из очереди (вынесено отдельно, чтобы можно было вызвать
-- как напрямую, так и после подтверждения через StaticPopup).
function auction:LeaveMySignup(itemKey)
    local playerName = UnitName("player")
    self.db.mySignups = self.db.mySignups or {}
    self.db.mySignups[itemKey] = nil
    self:SaveSettings()
    if self:IsLootMaster() then
        if self:RemoveQueueEntryByPlayer(itemKey, playerName) then
            self:SaveTokenQueues()
            self:SendQueueUpdate(itemKey)
        end
    elseif IsInRaid() or IsInGroup() then
        self:SendToLootMaster("QUEUE_LEAVE;"..itemKey)
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Вы вышли из очереди на \""..itemKey.."\".")
    self:RefreshQueueList()
end

-- Отправляет лутеру все свои текущие локальные записи одним сообщением.
function auction:SendMySignups()
    if self:IsLootMaster() then return end
    self.db.mySignups = self.db.mySignups or {}
    local parts = {}
    for itemKey, ts in pairs(self.db.mySignups) do
        table.insert(parts, itemKey..":"..ts)
    end
    if #parts == 0 then return end
    self:SendToLootMaster("QUEUE_JOIN;"..table.concat(parts, ","))
    self:Debug("Отправлены собственные записи в очередь ("..#parts..")")
end

-- Вызывается при входе в мир / изменении состава группы (см. comm.lua и
-- events.lua): подхватывает локальные записи (сделанные когда угодно, даже
-- вне группы) и либо применяет их у себя (если мы лутер), либо шлёт лутеру.
function auction:SyncMySignupsIfNeeded()
    if not (IsInRaid() or IsInGroup()) then return end
    self.db.mySignups = self.db.mySignups or {}
    if not next(self.db.mySignups) then return end

    if self:IsLootMaster() then
        local playerName = UnitName("player")
        local changed = {}
        for itemKey, ts in pairs(self.db.mySignups) do
            if self:InsertQueueSignup(itemKey, playerName, ts) then
                changed[itemKey] = true
            end
        end
        if next(changed) then
            self:SaveTokenQueues()
            for itemKey in pairs(changed) do
                self:SendQueueUpdate(itemKey)
            end
            if self.queueFrame and self.queueFrame:IsShown() then
                self:RefreshQueueList()
            end
        end
    elseif self.lastLM then
        self:SendMySignups()
    end
end

-- Если после синхронизации очереди нашего имени в ней больше нет (лутер
-- удалил вручную или выдал токен), снимаем локальный флаг "я записан" —
-- иначе при следующем входе в рейд мы бы снова отправили устаревшую запись.
function auction:ReconcileMySignup(itemKey, queue)
    self.db.mySignups = self.db.mySignups or {}
    if not self.db.mySignups[itemKey] then return end
    local playerName = UnitName("player")
    for _, entry in ipairs(queue) do
        if entry.player == playerName then
            return
        end
    end
    self.db.mySignups[itemKey] = nil
    self:SaveSettings()
    if self.queueFrame and self.queueFrame:IsShown() and self.selectedQueueItem == itemKey then
        self:UpdateMyQueueButton()
    end
end

-- ======================
-- Синхронизация с рейдом
-- ======================
function auction:SendQueueUpdate(itemKey)
    if not self:IsLootMaster() then return end
    local queue = self.tokenQueues[itemKey] or {}
    local parts = {}
    for _, entry in ipairs(queue) do
        table.insert(parts, entry.player..":"..entry.time)
    end
    local msg = "QUEUE_UPDATE;"..itemKey..";"..table.concat(parts, ",")
    self:QueueAddonMessage(msg, "RAID")
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
    end
    -- На всякий случай гарантируем, что все 15 комбинаций тип×слот существуют
    -- (например, после обновления аддона с добавлением новых слотов/типов).
    for _, tokenType in ipairs(TOKEN_TYPES) do
        for _, slot in ipairs(TOKEN_SLOTS) do
            local itemKey = GetItemKey(tokenType, slot)
            if not self.tokenQueues[itemKey] then
                self.tokenQueues[itemKey] = {}
            end
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
    self:QueueAddonMessage("QUEUE_REQUEST", "RAID")
end

function auction:SyncAllQueuesToRaid(target)
    if not self:IsLootMaster() then return end
    local recipient = target
    for itemKey, queue in pairs(self.tokenQueues) do
        local parts = {}
        for _, entry in ipairs(queue) do
            table.insert(parts, entry.player..":"..entry.time)
        end
        local msg = "QUEUE_SYNC;"..itemKey..";"..table.concat(parts, ",")
        if target then
            self:QueueAddonMessage(msg, "WHISPER", recipient)
        else
            self:QueueAddonMessage(msg, "RAID")
        end
    end
    self:Debug("Очереди отправлены "..(target and ("игроку "..target) or "в рейд"))
end

-- ======================
-- Обработчики сети
-- ======================
local function ParseQueueEntries(playersPart)
    local queue = {}
    if playersPart and playersPart ~= "" then
        for pair in playersPart:gmatch("([^,]+)") do
            local playerName, ts = pair:match("^(.+):(%d+)$")
            if playerName and ts then
                table.insert(queue, { player = playerName, time = tonumber(ts) })
            end
        end
    end
    return queue
end

function auction:Handle_QUEUE_UPDATE(rest, sender)
    local itemKey, playersPart = rest:match("([^;]+);(.*)")
    if not itemKey or not self.tokenQueues then return end
    local queue = ParseQueueEntries(playersPart)
    self.tokenQueues[itemKey] = queue
    self:ReconcileMySignup(itemKey, queue)
    if self.queueFrame and self.queueFrame:IsShown() and self.selectedQueueItem == itemKey then
        self:RefreshQueueList()
    end
    if not self:IsLootMaster() then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Очередь на \""..itemKey.."\" обновлена.")
    end
end

function auction:Handle_QUEUE_REQUEST(rest, sender)
    if not self:IsLootMaster() then return end
    self:SyncAllQueuesToRaid(sender)
end

function auction:Handle_QUEUE_SYNC(rest, sender)
    local itemKey, playersPart = rest:match("([^;]+);(.*)")
    if not itemKey then return end
    local queue = ParseQueueEntries(playersPart)
    self.tokenQueues[itemKey] = queue
    self:ReconcileMySignup(itemKey, queue)
    if self.queueFrame and self.queueFrame:IsShown() and self.selectedQueueItem == itemKey then
        self:RefreshQueueList()
    end
    self:Debug("Очередь синхронизирована: "..itemKey)
end

-- Игрок сам записался (в любой момент, даже вне рейда) — при входе в общую
-- группу с лутером это долетает сюда одним сообщением со всеми его записями.
function auction:Handle_QUEUE_JOIN(rest, sender)
    if not self:IsLootMaster() then return end
    local changed = {}
    for pair in rest:gmatch("([^,]+)") do
        local itemKey, ts = pair:match("^(.+):(%d+)$")
        if itemKey and ts then
            if self:InsertQueueSignup(itemKey, sender, tonumber(ts)) then
                changed[itemKey] = true
            end
        end
    end
    if next(changed) then
        self:SaveTokenQueues()
        for itemKey in pairs(changed) do
            self:SendQueueUpdate(itemKey)
        end
        if self.queueFrame and self.queueFrame:IsShown() and changed[self.selectedQueueItem] then
            self:RefreshQueueList()
        end
    end
end

function auction:Handle_QUEUE_LEAVE(rest, sender)
    if not self:IsLootMaster() then return end
    local itemKey = rest
    if not itemKey or itemKey == "" then return end
    if self:RemoveQueueEntryByPlayer(itemKey, sender) then
        self:SaveTokenQueues()
        self:SendQueueUpdate(itemKey)
        if self.queueFrame and self.queueFrame:IsShown() and self.selectedQueueItem == itemKey then
            self:RefreshQueueList()
        end
    end
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
    if self.queueMyButton then self:SkinButton(self.queueMyButton) end
    if self.queueTypeDropdown then self:SkinDropdown(self.queueTypeDropdown) end
    if self.queueSlotDropdown then self:SkinDropdown(self.queueSlotDropdown) end
    if self.queueListContainer then self:SkinPanel(self.queueListContainer) end
    if self.queueScrollFrame then
        local sb = _G[self.queueScrollFrame:GetName().."ScrollBar"]
        if sb then self:SkinScrollBar(sb) end
    end
end
