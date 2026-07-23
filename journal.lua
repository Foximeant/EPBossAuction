local auction = EPBossAuction

auction.bidLogLimit = 500
auction.journalDirty = true

local function shouldLogRaidActivity()
    return IsInRaid()
end

function auction:TrimBidLog()
    if type(self.bidLog) ~= "table" then
        self.bidLog = {}
        return
    end

    while #self.bidLog > (self.bidLogLimit or 500) do
        table.remove(self.bidLog, 1)
    end
end

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
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(110)
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
            auction:CancelTimer(self.resizeTimer)
            self.resizeTimer = nil
        end
        self.resizeTimer = auction:ScheduleTimer(function()
            if self.journalFrame and self.journalFrame:IsShown() then
                self:UpdateJournalScroll()
            end
            self.resizeTimer = nil
        end, 0.1)
    end)
    frame:SetScript("OnHide", function()
        if auction.journalRefreshTimer then
            auction:CancelTimer(auction.journalRefreshTimer)
            auction.journalRefreshTimer = nil
        end
        if auction.journalLayoutTimer then
            auction:CancelTimer(auction.journalLayoutTimer)
            auction.journalLayoutTimer = nil
        end
    end)
    frame:Hide()
    tinsert(UISpecialFrames, "EPBossAuctionJournalFrame")

    local title = frame:CreateFontString("EPBossAuctionJournalTitle", "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Журнал ставок")

    local close = CreateFrame("Button", "EPBossAuctionJournalCloseButton", frame)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetText("X")
    close:SetNormalFontObject(GameFontNormalLarge)
    close:SetScript("OnClick", function()
        frame:Hide()
    end)
    self.journalCloseButton = close

    local clearButton = CreateFrame("Button", "EPBossAuctionJournalClearButton", frame, "UIPanelButtonTemplate")
    clearButton:SetSize(80, 25)
    clearButton:SetPoint("BOTTOMLEFT", 16, 16)
    clearButton:SetText("Очистить")
    clearButton:SetScript("OnClick", function()
        StaticPopupDialogs["EPBA_CLEAR_LOG"] = {
            text = "Вы уверены?",
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
    end)
    self.journalClearButton = clearButton

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

    local scrollFrame = CreateFrame("ScrollFrame", "EPBossAuctionJournalScrollFrame", scrollContainer, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -4, 4)
    self.journalScrollFrame = scrollFrame

    local content = CreateFrame("Frame", "EPBossAuctionJournalContent", scrollFrame)
    scrollFrame:SetScrollChild(content)
    self.journalContent = content

    local textWidget = content:CreateFontString("EPBossAuctionJournalText", "OVERLAY", "GameFontNormal")
    textWidget:SetPoint("TOPLEFT", 8, -4)
    textWidget:SetPoint("RIGHT", -8, 0)
    textWidget:SetJustifyH("LEFT")
    textWidget:SetJustifyV("TOP")
    textWidget:SetWordWrap(true)
    textWidget:SetTextColor(1, 1, 1)
    self.journalTextWidget = textWidget

    self.journalFrame = frame

    self:BuildJournalText(true)
    self:ApplyJournalSkin()
end

function auction:BuildJournalText(force)
    if not self.journalTextWidget then return end
    if not force and not self.journalDirty then return end

    local entries = self.bidLog or {}
    if #entries == 0 then
        self.journalTextWidget:SetText("Журнал пуст >_<")
        self.journalDirty = false
        self:UpdateJournalScroll()
        return
    end

    local textLines = {}
    for i = #entries, 1, -1 do
        local entry = entries[i]
        if entry then
            local playerName = entry.player or "Игрок не найден"
            local amount = entry.amount or 0
            local itemName = entry.itemID and self:GetCachedItemName(entry.itemID) or "предмет не найден"
            local bossName = entry.boss or "босс не найден"
            local timeStr = entry.time or date("%Y-%m-%d %H:%M:%S")

            local amountStr
            if amount == 0 then
                amountStr = "отменил ставку "
            else
                local offspecMark = entry.isOffspec and " (O)" or ""
                amountStr = "поставил " .. self:FormatNumber(amount) .. " EP" .. offspecMark
            end

            textLines[#textLines + 1] = string.format("%s %s %s на %s (%s)", timeStr, playerName, amountStr, itemName, bossName)
        end
    end

    self.journalTextWidget:SetText(table.concat(textLines, "\n"))
    self.journalDirty = false
    self:UpdateJournalScroll()
end

function auction:UpdateJournalScroll()
    if not self.journalTextWidget or not self.journalContent or not self.journalScrollFrame then return end

    local scrollWidth = self.journalScrollFrame:GetWidth() - 28
    if scrollWidth < 100 then
        scrollWidth = 500
    end

    self.journalTextWidget:SetWidth(scrollWidth)

    local textHeight = self.journalTextWidget:GetStringHeight()
    if not textHeight or textHeight == 0 then
        textHeight = 400
    end

    self.journalContent:SetSize(scrollWidth + 20, textHeight + 20)

    local scrollBar = _G[self.journalScrollFrame:GetName() .. "ScrollBar"]
    if scrollBar then
        scrollBar:Show()
    end
end

function auction:ToggleJournal()
    if not self.journalFrame then
        self:CreateJournalFrame()
    end
    if self.journalFrame and self.journalFrame:IsShown() then
        self.journalFrame:Hide()
    elseif self.journalFrame then
        self:BuildJournalText(true)
        self.journalFrame:Show()
        if self.journalLayoutTimer then
            self:CancelTimer(self.journalLayoutTimer)
        end
        self.journalLayoutTimer = self:ScheduleTimer(function()
            self.journalLayoutTimer = nil
            if self.journalFrame and self.journalFrame:IsShown() then
                self:UpdateJournalScroll()
            end
        end, 0.1)
    end
end

function auction:RefreshJournal()
    self.journalDirty = true
    if not self.journalTextWidget then return end
    if self.journalFrame and self.journalFrame:IsShown() then
        if self.journalRefreshTimer then
            return
        end
        self.journalRefreshTimer = self:ScheduleTimer(function()
            self.journalRefreshTimer = nil
            if self.journalFrame and self.journalFrame:IsShown() then
                self:BuildJournalText(true)
            end
        end, 0.2)
    end
end

function auction:LogBidChangesFromSync(oldBids, newBids, itemID, bossName)
    if not shouldLogRaidActivity() then return end
    if not itemID or not bossName then return end

    local oldMap = {}
    local newMap = {}

    for _, bid in ipairs(oldBids or {}) do
        if bid and bid.player then
            oldMap[bid.player] = {
                amount = bid.amount or 0,
                isOffspec = bid.isOffspec and true or false,
            }
        end
    end

    for _, bid in ipairs(newBids or {}) do
        if bid and bid.player then
            newMap[bid.player] = {
                amount = bid.amount or 0,
                isOffspec = bid.isOffspec and true or false,
            }
        end
    end

    for playerName, oldBid in pairs(oldMap) do
        local newBid = newMap[playerName]
        if not newBid then
            self:AddBidLogEntry(playerName, 0, itemID, bossName, oldBid.isOffspec)
        elseif newBid.amount ~= oldBid.amount or newBid.isOffspec ~= oldBid.isOffspec then
            self:AddBidLogEntry(playerName, newBid.amount, itemID, bossName, newBid.isOffspec)
        end
    end

    for playerName, newBid in pairs(newMap) do
        if not oldMap[playerName] then
            self:AddBidLogEntry(playerName, newBid.amount, itemID, bossName, newBid.isOffspec)
        end
    end
end

function auction:AddBidLogEntry(playerName, amount, itemID, bossName, isOffspec)
    if not shouldLogRaidActivity() then return end
    if not playerName or amount == nil or not itemID or not bossName then return end

    self.bidLog = type(self.bidLog) == "table" and self.bidLog or {}

    local now = date("%Y-%m-%d %H:%M:%S")
    local lastEntry = self.bidLog[#self.bidLog]
    if lastEntry
        and lastEntry.time == now
        and lastEntry.player == playerName
        and lastEntry.amount == amount
        and lastEntry.itemID == itemID
        and lastEntry.boss == bossName
        and lastEntry.isOffspec == (isOffspec and true or false) then
        return
    end

    self.bidLog[#self.bidLog + 1] = {
        time = now,
        player = playerName,
        amount = amount,
        itemID = itemID,
        boss = bossName,
        isOffspec = isOffspec and true or false,
    }

    self:TrimBidLog()
    self:SaveBidLog()
    self:RefreshJournal()
end

function auction:SaveBidLog()
    self:TrimBidLog()
    EPBossAuctionBidLog = self.bidLog
end

function auction:LoadBidLog()
    if EPBossAuctionBidLog then
        self.bidLog = EPBossAuctionBidLog
    else
        self.bidLog = {}
    end
    self:TrimBidLog()
    self.journalDirty = true
end

function auction:ClearBidLog()
    self.bidLog = {}
    self:SaveBidLog()
    self:RefreshJournal()
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Журнал ставок очищен.")
    end
end

function auction:ApplyJournalSkin()
    if self.journalFrame then self:SkinPanel(self.journalFrame) end
    if self.journalCloseButton then self:SkinButton(self.journalCloseButton) end
    if self.journalClearButton then self:SkinButton(self.journalClearButton) end
    if self.journalSizer then
        self:SkinButton(self.journalSizer)
    end
    if self.journalScrollFrame then
        local scrollBar = _G[self.journalScrollFrame:GetName() .. "ScrollBar"]
        if scrollBar then self:SkinScrollBar(scrollBar) end
    end
    if self.journalScrollContainer then self:SkinPanel(self.journalScrollContainer) end
end
