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
    self.journalCloseButton = close
    
    -- Кнопка очистки
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
    self.journalClearButton = clearButton
    
    -- Кнопка растягивания (правый нижний угол)
	local sizer = CreateFrame("Button", "EPBossAuctionJournalSizer", frame)
	sizer:SetHeight(20)
	sizer:SetWidth(20)
	sizer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)

	-- Создаем фон для подсветки (светлый квадрат)
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

	-- Текстура для уголка растягивания
	local line1 = sizer:CreateTexture(nil, "BACKGROUND")
	line1:SetWidth(14)
	line1:SetHeight(14)
	line1:SetPoint("BOTTOMRIGHT", -8, 8)
	line1:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
	local x = 0.1 * 14 / 17
	if x then
		line1:SetTexCoord(0.05 - x, 0.5, 0.05, 0.5 + x, 0.05, 0.5 - x, 0.5 + x, 0.5)
	end

	local line2 = sizer:CreateTexture(nil, "BACKGROUND")
	line2:SetWidth(8)
	line2:SetHeight(8)
	line2:SetPoint("BOTTOMRIGHT", -8, 8)
	line2:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
	local x2 = 0.1 * 8 / 17
	if x2 then
		line2:SetTexCoord(0.05 - x2, 0.5, 0.05, 0.5 + x2, 0.05, 0.5 - x2, 0.5 + x2, 0.5)
	end

	self.journalSizer = sizer
    
    -- Контейнер для ScrollFrame
    local scrollContainer = CreateFrame("Frame", nil, frame)
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
    
    -- ScrollFrame
    local scrollFrame = CreateFrame("ScrollFrame", "EPBossAuctionJournalScrollFrame", scrollContainer, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -4, 4)
    self.journalScrollFrame = scrollFrame
    
    -- Контент
    local content = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(content)
    self.journalContent = content
    
    -- Текст
    local textWidget = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    textWidget:SetPoint("TOPLEFT", 8, -4)
    textWidget:SetPoint("RIGHT", -8, 0)
    textWidget:SetJustifyH("LEFT")
    textWidget:SetJustifyV("TOP")
    textWidget:SetWordWrap(true)
    self.journalTextWidget = textWidget
    
    -- Кэш
    self.journalCachedText = nil
    self.journalCachedTextHeight = nil
    
    self.journalFrame = frame
    
    self:BuildJournalText()
    self:UpdateJournalScroll()
    
    self:ApplyJournalSkin()
    
    if self.Debug then
        self:Debug("Окно журнала создано")
    end
end

-- Построение текста журнала
function auction:BuildJournalText()
    if not self.journalTextWidget then return end
    
    local entries = self.bidLog or {}
    if #entries == 0 then
        self.journalCachedText = "Нет записей в журнале."
        self.journalTextWidget:SetText(self.journalCachedText)
        self.journalCachedTextHeight = nil
        return
    end
    
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
            
            local coloredName = self:FormatColoredName(playerName)
            
            local amountStr
            if amount == 0 then
                amountStr = "отменил ставку"
            else
                amountStr = "поставил " .. self:FormatNumber(amount) .. " EP"
            end
            
            local line = string.format("%s %s %s на %s (%s)",
                timeStr, coloredName, amountStr, itemName, bossName)
            
            table.insert(textLines, line)
        end
    end
    
    self.journalCachedText = table.concat(textLines, "\n")
    self.journalTextWidget:SetText(self.journalCachedText)
    self.journalCachedTextHeight = nil
end

-- Обновление высоты контента и прокрутки
function auction:UpdateJournalScroll()
    if not self.journalTextWidget or not self.journalContent or not self.journalScrollFrame then return end
    
    local scrollWidth = self.journalScrollFrame:GetWidth() - 28
    if scrollWidth < 100 then return end
    
    self.journalTextWidget:SetWidth(scrollWidth)
    
    local textHeight = self.journalTextWidget:GetStringHeight()
    if not textHeight then return end
    
    local contentHeight = math.max(textHeight + 20, self.journalScrollFrame:GetHeight())
    
    self.journalContent:SetSize(scrollWidth + 20, contentHeight)
    
    if not self.journalScrollInitialized then
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
        self:BuildJournalText()
        self:UpdateJournalScroll()
        self.journalFrame:Show()
        self.journalScrollInitialized = false
    end
end

-- Обновление содержимого журнала
function auction:RefreshJournal()
    if not self.journalTextWidget then return end
    self:BuildJournalText()
    if self.journalFrame and self.journalFrame:IsShown() then
        self:UpdateJournalScroll()
    end
end

-- Добавление записи в лог
function auction:AddBidLogEntry(playerName, amount, itemID, bossName)
    if not playerName or amount == nil or not itemID or not bossName then 
        if self.Debug then
            self:Debug("Пропуск добавления в лог: недостаточно данных")
        end
        return 
    end
    
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
    
    if #self.bidLog > 500 then
        table.remove(self.bidLog, 1)
    end
    
    self:SaveBidLog()
    
    self.journalCachedText = nil
    self.journalCachedTextHeight = nil
    
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
    self.journalCachedText = nil
    self.journalCachedTextHeight = nil
end

-- Очистка лога
function auction:ClearBidLog()
    self.bidLog = {}
    self:SaveBidLog()
    self.journalCachedText = nil
    self.journalCachedTextHeight = nil
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
    
    -- Скин окна журнала
    if self.journalFrame then
        self.journalFrame:SetTemplate("Transparent")
    end
    
    -- Кнопка закрытия
    if self.journalCloseButton then
        if S.HandleCloseButton then
            S:HandleCloseButton(self.journalCloseButton)
        end
    end
    
    -- Кнопка очистки
    if self.journalClearButton then
        if S.HandleButton then
            S:HandleButton(self.journalClearButton)
        end
    end
    
    -- Скроллбар журнала - с проверкой
    if self.journalScrollFrame then
        local scrollBar = _G[self.journalScrollFrame:GetName().."ScrollBar"]
        if scrollBar then
            if S.HandleScrollBar then
                S:HandleScrollBar(scrollBar)
            elseif scrollBar.SetTemplate then
                scrollBar:SetTemplate("Transparent")
            end
        end
    end
    
    -- Контейнер скролла
    if self.journalScrollContainer then
        self.journalScrollContainer:SetTemplate("Transparent")
    end
end