local auction = EPBossAuction

-- ======================
-- Журнал ставок
-- ======================

function auction:CreateJournalFrame()
    if self.journalFrame then return end
    
    local frame = CreateFrame("Frame", "EPBossAuctionJournalFrame", UIParent)
    frame:SetSize(650, 500)
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
        if self.resizeTimer then
            if self.resizeTimer.Cancel then
                self.resizeTimer:Cancel()
            end
            self.resizeTimer = nil
        end
        self.resizeTimer = auction:ScheduleTimer(function()
            if self.journalFrame and self.journalFrame:IsShown() then
                self:UpdateJournalScroll()
            end
            self.resizeTimer = nil
        end, 0.1)
    end)
    frame:Hide()
    tinsert(UISpecialFrames, "EPBossAuctionJournalFrame")
    
    local title = frame:CreateFontString("EPBossAuctionJournalTitle", "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Журнал ставок")
    
    local close = CreateFrame("Button", "EPBossAuctionJournalCloseButton", frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function()
        frame:Hide()
    end)
    self.journalCloseButton = close
    
    local clearButton = CreateFrame("Button", "EPBossAuctionJournalClearButton", frame, "UIPanelButtonTemplate")
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
    self.journalClearButton = clearButton
    
    -- Кнопка для растягивания окна журнала
    local sizer = CreateFrame("Button", "EPBossAuctionJournalSizer", frame)
    sizer:SetSize(20, 20)
    sizer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    
    local sizerHighlight = sizer:CreateTexture(nil, "OVERLAY")
    sizerHighlight:SetTexture("Interface\\Buttons\\WHITE8x8")
    sizerHighlight:SetVertexColor(1, 0.8, 0, 0)
    sizerHighlight:SetAllPoints()
    sizer.highlight = sizerHighlight
    
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
    end)
    self.journalSizer = sizer
    
    -- Контейнер для скролла
    local scrollContainer = CreateFrame("Frame", "EPBossAuctionJournalScrollContainer", frame)
    scrollContainer:SetPoint("TOPLEFT", 16, -45)
    scrollContainer:SetPoint("BOTTOMRIGHT", -32, 50)
    scrollContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    scrollContainer:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    scrollContainer:SetBackdropBorderColor(0, 0, 0, 1)
    self.journalScrollContainer = scrollContainer
    
    -- Скролл-фрейм
    local scrollFrame = CreateFrame("ScrollFrame", "EPBossAuctionJournalScrollFrame", scrollContainer, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -4, 4)
    self.journalScrollFrame = scrollFrame
    
    -- Контент-фрейм (будет динамически менять высоту)
    local content = CreateFrame("Frame", "EPBossAuctionJournalContent", scrollFrame)
    scrollFrame:SetScrollChild(content)
    self.journalContent = content
    
    -- Текстовое поле для записей (белый цвет)
    local textWidget = content:CreateFontString("EPBossAuctionJournalText", "OVERLAY", "GameFontNormal")
    textWidget:SetPoint("TOPLEFT", 8, -4)
    textWidget:SetPoint("RIGHT", -8, 0)
    textWidget:SetJustifyH("LEFT")
    textWidget:SetJustifyV("TOP")
    textWidget:SetWordWrap(true)
    textWidget:SetTextColor(1, 1, 1)  -- Белый цвет
    self.journalTextWidget = textWidget
    
    self.journalFrame = frame
    
    self:BuildJournalText()
    self:ApplyJournalSkin()
    
    if self.Debug then
        self:Debug("Окно журнала создано")
    end
end

-- ======================
-- Построение текста журнала (ВСЕ записи, белый текст)
-- ======================
function auction:BuildJournalText()
    if not self.journalTextWidget then return end
    
    local entries = self.bidLog or {}
    if #entries == 0 then
        self.journalTextWidget:SetText("Нет записей в журнале.")
        self:UpdateJournalScroll()
        return
    end
    
    -- Строим текст для ВСЕХ записей (в обратном порядке - новые сверху)
    local textLines = {}
    for i = #entries, 1, -1 do
        local entry = entries[i]
        if entry then
            local playerName = entry.player or "Неизвестный игрок"
            local amount = entry.amount or 0
            local itemID = entry.itemID
            local bossName = entry.boss or "Неизвестный босс"
            local timeStr = entry.time or date("%Y-%m-%d %H:%M:%S")
            
            local itemName
            if itemID then
                itemName = GetItemInfo(itemID) or ("предмет "..tostring(itemID))
            else
                itemName = "неизвестный предмет"
            end
            
            -- Имя без цвета
            local amountStr
            if amount == 0 then
                amountStr = "отменил ставку"
            else
                local offspecMark = entry.isOffspec and " (O)" or ""
                amountStr = "поставил " .. auction:FormatNumber(amount) .. " EP" .. offspecMark
            end
            
            local line = string.format("%s %s %s на %s (%s)",
                timeStr, playerName, amountStr, itemName, bossName)
            
            table.insert(textLines, line)
        end
    end
    
    self.journalTextWidget:SetText(table.concat(textLines, "\n"))
    self:UpdateJournalScroll()
end

-- ======================
-- Обновление скролла (динамическая высота контента)
-- ======================
function auction:UpdateJournalScroll()
    if not self.journalTextWidget or not self.journalContent or not self.journalScrollFrame then return end
    
    -- Получаем ширину скролл-фрейма
    local scrollWidth = self.journalScrollFrame:GetWidth() - 28
    if scrollWidth < 100 then
        scrollWidth = 500
    end
    
    -- Устанавливаем ширину текста
    self.journalTextWidget:SetWidth(scrollWidth)
    
    -- Получаем реальную высоту текста
    local textHeight = self.journalTextWidget:GetStringHeight()
    if not textHeight or textHeight == 0 then
        textHeight = 400
    end
    
    -- Устанавливаем высоту контент-фрейма (текст + отступы)
    local contentHeight = textHeight + 20
    self.journalContent:SetSize(scrollWidth + 20, contentHeight)
    
    -- Сбрасываем скролл наверх
    self.journalScrollFrame:SetVerticalScroll(0)
    
    -- Показываем скроллбар если нужно
    local scrollBar = _G[self.journalScrollFrame:GetName().."ScrollBar"]
    if scrollBar then
        scrollBar:Show()
    end
end

-- ======================
-- Показать/скрыть журнал
-- ======================
function auction:ToggleJournal()
    if not self.journalFrame then
        self:CreateJournalFrame()
    end
    if self.journalFrame and self.journalFrame:IsShown() then
        self.journalFrame:Hide()
    elseif self.journalFrame then
        self:BuildJournalText()
        self.journalFrame:Show()
        -- Используем ScheduleTimer вместо C_Timer
        self:ScheduleTimer(function()
            if self.journalFrame and self.journalFrame:IsShown() then
                self:UpdateJournalScroll()
            end
        end, 0.1)
    end
end

-- ======================
-- Обновить журнал
-- ======================
function auction:RefreshJournal()
    if not self.journalTextWidget then return end
    self:BuildJournalText()
    if self.journalFrame and self.journalFrame:IsShown() then
        self:UpdateJournalScroll()
    end
end

-- ======================
-- Добавить запись в журнал
-- ======================
function auction:AddBidLogEntry(playerName, amount, itemID, bossName, isOffspec)
    if not playerName or amount == nil or not itemID or not bossName then 
        if self.Debug then
            self:Debug("Пропуск добавления в лог: недостаточно данных")
        end
        return 
    end
    
    -- Проверка на дублирование (последние 5 записей)
    for i = #self.bidLog, math.max(1, #self.bidLog - 5), -1 do
        local entry = self.bidLog[i]
        if entry and entry.player == playerName and entry.amount == amount and entry.itemID == itemID and entry.boss == bossName then
            return
        end
    end
    
    local entry = {
        time = date("%Y-%m-%d %H:%M:%S"),
        player = playerName,
        amount = amount,
        itemID = itemID,
        boss = bossName,
        isOffspec = isOffspec or false,
    }
    table.insert(self.bidLog, entry)
    
    -- Увеличиваем лимит до 2000 записей
    if #self.bidLog > 2000 then
        table.remove(self.bidLog, 1)
    end
    
    self:SaveBidLog()
    
    -- Обновляем журнал если открыт
    if self.journalFrame and self.journalFrame:IsShown() then
        self:RefreshJournal()
    end
end

-- ======================
-- Сохранение журнала
-- ======================
function auction:SaveBidLog()
    EPBossAuctionBidLog = self.bidLog
end

-- ======================
-- Загрузка журнала
-- ======================
function auction:LoadBidLog()
    if EPBossAuctionBidLog then
        self.bidLog = EPBossAuctionBidLog
    else
        self.bidLog = {}
    end
end

-- ======================
-- Очистка журнала
-- ======================
function auction:ClearBidLog()
    self.bidLog = {}
    self:SaveBidLog()
    if self.journalFrame and self.journalFrame:IsShown() then
        self:RefreshJournal()
    end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Журнал ставок очищен.")
    end
end

-- ======================
-- ElvUI Skin для журнала
-- ======================
function auction:ApplyJournalSkin()
    if not IsAddOnLoaded("ElvUI") then return end
    local E, L, V, P, G = unpack(ElvUI)
    local S = E:GetModule("Skins")
    if not S then return end
    
    if self.journalFrame then
        self.journalFrame:SetTemplate("Transparent")
    end
    
    if self.journalCloseButton then
        S:HandleCloseButton(self.journalCloseButton)
    end
    
    if self.journalClearButton then
        S:HandleButton(self.journalClearButton)
    end
    
    if self.journalSizer then
        self.journalSizer:SetTemplate("Default")
        self.journalSizer:SetBackdropBorderColor(0, 0, 0, 0)
        self.journalSizer:SetBackdropColor(0, 0, 0, 0)
    end
    
    if self.journalScrollFrame then
        local scrollBar = _G[self.journalScrollFrame:GetName().."ScrollBar"]
        if scrollBar then
            S:HandleScrollBar(scrollBar)
        end
    end
    
    if self.journalScrollContainer then
        self.journalScrollContainer:SetTemplate("Transparent")
    end
end