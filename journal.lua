local auction = EPBossAuction

-- ======================
-- Журнал ставок
-- ======================

-- Создание окна журнала
function auction:CreateJournalFrame()
    if self.journalFrame then return end
    
    local frame = CreateFrame("Frame", "EPBossAuctionJournalFrame", UIParent)
    frame:SetSize(550, 400)
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
    frame:SetMinResize(400, 300)
    frame:SetMaxResize(900, 600)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnSizeChanged", function()
        -- Используем отложенный вызов для предотвращения множественных обновлений
        if self.resizeTimer then
            self.resizeTimer:Cancel()
        end
        self.resizeTimer = C_Timer.NewTimer(0.1, function()
            if self.journalFrame and self.journalFrame:IsShown() then
                self:UpdateJournalScroll()
            end
            self.resizeTimer = nil
        end)
    end)
    frame:Hide()
    tinsert(UISpecialFrames, "EPBossAuctionJournalFrame")
    
    -- Заголовок
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Журнал ставок")
    
    -- Кнопка закрытия
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function()
        frame:Hide()
    end)
    
    -- Кнопка очистки (только для лутера)
    local clearButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearButton:SetSize(80, 25)
    clearButton:SetPoint("BOTTOMLEFT", 16, 16)
    clearButton:SetText("Очистить")
    clearButton:SetScript("OnClick", function()
        if auction:IsLootMaster() then
            StaticPopupDialogs["EPBA_CLEAR_LOG"] = {
                text = "Очистить журнал ставок?",
                button1 = "Да",
                button2 = "Нет",
                OnAccept = function()
                    auction:ClearBidLog()
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
            }
            StaticPopup_Show("EPBA_CLEAR_LOG")
        else
            print("|cffff0000[EPBA]|r Только Loot Master может очищать журнал.")
        end
    end)
    
    -- Кнопка растягивания (правый нижний угол)
    local sizer = CreateFrame("Button", nil, frame)
    sizer:SetHeight(16)
    sizer:SetWidth(16)
    sizer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    sizer:SetScript("OnMouseDown", function(self)
        self:GetParent():StartSizing("BOTTOMRIGHT")
    end)
    sizer:SetScript("OnMouseUp", function(self)
        self:GetParent():StopMovingOrSizing()
    end)
    
    -- Текстура для уголка растягивания
    local line1 = sizer:CreateTexture(nil, "BACKGROUND")
    line1:SetWidth(14)
    line1:SetHeight(14)
    line1:SetPoint("BOTTOMRIGHT", -8, 8)
    line1:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
    local x = 0.1 * 14 / 17
    line1:SetTexCoord(0.05 - x, 0.5, 0.05, 0.5 + x, 0.05, 0.5 - x, 0.5 + x, 0.5)
    
    local line2 = sizer:CreateTexture(nil, "BACKGROUND")
    line2:SetWidth(8)
    line2:SetHeight(8)
    line2:SetPoint("BOTTOMRIGHT", -8, 8)
    line2:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
    local x2 = 0.1 * 8 / 17
    line2:SetTexCoord(0.05 - x2, 0.5, 0.05, 0.5 + x2, 0.05, 0.5 - x2, 0.5 + x2, 0.5)
    
    -- Создаем контейнер для ScrollFrame
    local scrollContainer = CreateFrame("Frame", nil, frame)
    scrollContainer:SetPoint("TOPLEFT", 16, -45)
    scrollContainer:SetPoint("BOTTOMRIGHT", -16, 50)
    scrollContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    scrollContainer:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    scrollContainer:SetBackdropBorderColor(0, 0, 0, 1)
    
    -- Создаем ScrollFrame
    local scrollFrame = CreateFrame("ScrollFrame", nil, scrollContainer, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -4, 4)
    
    -- Создаем дочерний фрейм для содержимого
    local content = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(content)
    
    -- Создаем FontString для текста (будем обновлять его)
    local textWidget = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    textWidget:SetPoint("TOPLEFT", 8, -4)
    textWidget:SetPoint("RIGHT", -8, 0)
    textWidget:SetJustifyH("LEFT")
    textWidget:SetJustifyV("TOP")
    textWidget:SetWordWrap(true)
    
    -- Сохраняем кэшированный текст и высоту для оптимизации
    self.journalCachedText = nil
    self.journalCachedTextHeight = nil
    
    self.journalFrame = frame
    self.journalScrollFrame = scrollFrame
    self.journalContent = content
    self.journalTextWidget = textWidget
    self.journalClearButton = clearButton
    self.journalSizer = sizer
    self.journalScrollContainer = scrollContainer
    
    -- Инициализируем содержимое
    self:BuildJournalText()
    self:UpdateJournalScroll()
    
    if self.Debug then
        self:Debug("Окно журнала создано")
    end
end

-- Построение текста журнала (вызывается только при изменении данных)
function auction:BuildJournalText()
    if not self.journalTextWidget then return end
    
    local entries = self.bidLog or {}
    if #entries == 0 then
        self.journalCachedText = "Нет записей в журнале."
        self.journalTextWidget:SetText(self.journalCachedText)
        self.journalCachedTextHeight = nil
        return
    end
    
    -- Формируем текст с новыми записями сверху
    local textLines = {}
    for i = #entries, 1, -1 do
        local entry = entries[i]
        if entry then
            -- Защита от nil значений
            local playerName = entry.player or "Неизвестный игрок"
            local amount = entry.amount or 0
            local itemID = entry.itemID
            local bossName = entry.boss or "Неизвестный босс"
            local timeStr = entry.time or date("%Y-%m-%d %H:%M:%S")
            
            -- Получаем название предмета
            local itemName
            if itemID then
                itemName = GetItemInfo(itemID) or ("предмет "..tostring(itemID))
            else
                itemName = "неизвестный предмет"
            end
            
            -- Форматируем имя игрока с цветом класса
            local coloredName = self:FormatColoredName(playerName)
            
            -- Форматируем сумму ставки
            local amountStr
            if amount == 0 then
                amountStr = "отменил ставку"
            else
                amountStr = "поставил " .. self:FormatNumber(amount) .. " EP"
            end
            
            -- Формируем строку
            local line = string.format("%s %s %s на %s (%s)",
                timeStr, coloredName, amountStr, itemName, bossName)
            
            table.insert(textLines, line)
        end
    end
    
    -- Объединяем строки с переносами
    self.journalCachedText = table.concat(textLines, "\n")
    self.journalTextWidget:SetText(self.journalCachedText)
    self.journalCachedTextHeight = nil -- Сброс кэша высоты
end

-- Обновление высоты контента и прокрутки (оптимизированная версия)
function auction:UpdateJournalScroll()
    if not self.journalTextWidget or not self.journalContent or not self.journalScrollFrame then return end
    
    -- Получаем текущую ширину ScrollFrame для расчета переноса
    local scrollWidth = self.journalScrollFrame:GetWidth() - 20
    if scrollWidth < 100 then return end
    
    -- Устанавливаем ширину текста для правильного переноса
    self.journalTextWidget:SetWidth(scrollWidth)
    
    -- Получаем высоту текста (с кэшированием)
    local textHeight
    if self.journalCachedTextHeight then
        textHeight = self.journalCachedTextHeight
    else
        textHeight = self.journalTextWidget:GetStringHeight()
        -- Кэшируем только если текст не пустой
        if textHeight > 0 then
            self.journalCachedTextHeight = textHeight
        end
    end
    
    -- Вычисляем высоту контента с отступами
    local contentHeight = math.max(textHeight + 20, self.journalScrollFrame:GetHeight())
    
    -- Обновляем размер контента только если он изменился
    local currentHeight = self.journalContent:GetHeight()
    if math.abs(currentHeight - contentHeight) > 1 then
        self.journalContent:SetSize(scrollWidth + 20, contentHeight)
    end
    
    -- Сохраняем позицию прокрутки перед обновлением
    local currentScroll = self.journalScrollFrame:GetVerticalScroll()
    
    -- Если мы в начале списка или список только открыт, прокручиваем к началу
    if currentScroll == 0 or not self.journalScrollInitialized then
        self.journalScrollFrame:SetVerticalScroll(0)
        self.journalScrollInitialized = true
    end
end

-- Показать/скрыть журнал
function auction:ToggleJournal()
    if not self.journalFrame then
        self:CreateJournalFrame()
    end
    if self.journalFrame and self.journalFrame:IsShown() then
        self.journalFrame:Hide()
        self.journalScrollInitialized = false
    elseif self.journalFrame then
        -- При открытии обновляем текст (на случай если данные изменились)
        self:BuildJournalText()
        self:UpdateJournalScroll()
        self.journalFrame:Show()
        self.journalScrollInitialized = false
    end
end

-- Обновление содержимого журнала (вызывается только при изменении данных)
function auction:RefreshJournal()
    if not self.journalTextWidget then return end
    
    -- Перестраиваем текст только если данные изменились
    self:BuildJournalText()
    
    -- Обновляем прокрутку
    if self.journalFrame and self.journalFrame:IsShown() then
        self:UpdateJournalScroll()
    end
end

-- Добавление записи в лог
function auction:AddBidLogEntry(playerName, amount, itemID, bossName)
    -- Защита от недостающих данных
    if not playerName or amount == nil or not itemID or not bossName then 
        if self.Debug then
            self:Debug("Пропуск добавления в лог: недостаточно данных (player="..tostring(playerName)..", amount="..tostring(amount)..", itemID="..tostring(itemID)..", boss="..tostring(bossName)..")")
        end
        return 
    end
    
    -- Защита от дублирования (проверяем последнюю запись)
    local lastEntry = self.bidLog[#self.bidLog]
    if lastEntry and lastEntry.player == playerName and lastEntry.amount == amount and lastEntry.itemID == itemID and lastEntry.boss == bossName then
        return
    end
    
    local entry = {
        time = date("%Y-%m-%d %H:%M:%S"),
        player = playerName,
        amount = amount,
        itemID = itemID,
        boss = bossName,
    }
    table.insert(self.bidLog, entry)
    
    -- Ограничиваем размер лога
    if #self.bidLog > 500 then
        table.remove(self.bidLog, 1)
    end
    
    self:SaveBidLog()
    
    -- Обновляем кэш текста
    self.journalCachedText = nil
    self.journalCachedTextHeight = nil
    
    -- Обновляем окно, если оно открыто
    if self.journalFrame and self.journalFrame:IsShown() then
        self:RefreshJournal()
    end
end

-- Сохранение лога
function auction:SaveBidLog()
    EPBossAuctionBidLog = self.bidLog
end

-- Загрузка лога
function auction:LoadBidLog()
    if EPBossAuctionBidLog then
        self.bidLog = EPBossAuctionBidLog
    else
        self.bidLog = {}
    end
    -- Сбрасываем кэш при загрузке
    self.journalCachedText = nil
    self.journalCachedTextHeight = nil
end

-- Очистка лога
function auction:ClearBidLog()
    self.bidLog = {}
    self:SaveBidLog()
    -- Сбрасываем кэш
    self.journalCachedText = nil
    self.journalCachedTextHeight = nil
    if self.journalFrame and self.journalFrame:IsShown() then
        self:RefreshJournal()
    end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Журнал ставок очищен.")
    end
end