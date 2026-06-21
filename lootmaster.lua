local auction = EPBossAuction

local LOOT_ROW_WIDTH = 490
local LOOT_ROW_PADDING = 8
local BID_ROW_HEIGHT = 20

local function GetThemeColors()
    return auction.theme and auction.theme.colors or {
        panel = {0.07, 0.09, 0.12, 0.95},
        border = {0.18, 0.22, 0.30, 1},
        buttonHover = {0.22, 0.30, 0.42, 1},
        accent = {0.35, 0.65, 1.0, 1},
    }
end

local function ApplyLootRowStyle(frame, alpha)
    local c = GetThemeColors()
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    frame:SetBackdropColor(c.panel[1], c.panel[2], c.panel[3], alpha or c.panel[4])
    frame:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], c.border[4])
end

local function GetItemIDFromLink(itemLink)
    if not itemLink then return nil end
    return tonumber(string.match(itemLink, "item:(%d+):"))
end

local function GetEPGP()
    return EPGP or EPGP_Auction or CEPGP or EPGPCore
end

local function GetBidKey(itemID)
    return tostring(itemID or 0)
end

local function GetBidderLabel(bid, ep)
    local offspecMark = bid.isOffspec and " (офф)" or ""
    local epText = ep and auction:FormatNumber(ep) or "?"
    return string.format("%s — ставка %s EP%s / EP: %s", bid.player or "?", auction:FormatNumber(tonumber(bid.amount) or 0), offspecMark, epText)
end

function auction:GetLootBossForItem(itemID)
    if not itemID then return nil end

    if self.selectedBoss and self.bosses[self.selectedBoss] then
        for _, bossItemID in ipairs(self.bosses[self.selectedBoss]) do
            if bossItemID == itemID then
                return self.selectedBoss, true
            end
        end
    end

    for bossName, items in pairs(self.bosses or {}) do
        for _, bossItemID in ipairs(items) do
            if bossItemID == itemID then
                return bossName, true
            end
        end
    end

    return self.selectedBoss, false
end

function auction:GetSortedBidsForLootItem(itemID)
    local bossName = self:GetLootBossForItem(itemID)
    if not bossName then return nil, {} end

    if not (self.sortedBids[bossName] and self.sortedBids[bossName][itemID]) then
        self:UpdateSortedBids(bossName, itemID)
    end

    return bossName, (self.sortedBids[bossName] and self.sortedBids[bossName][itemID]) or {}
end

function auction:GetMasterLootCandidateIndex(slot, playerName)
    if not (slot and playerName and GetMasterLootCandidate) then return nil end

    for i = 1, 40 do
        local name = GetMasterLootCandidate(slot, i)
        if not name then break end
        if name == playerName then
            return i
        end
    end

    return nil
end

function auction:CreateLootMasterWindow()
    if self.lootMasterFrame then return end

    local frame = CreateFrame("Frame", "EPBossAuctionLootMasterFrame", UIParent)
    frame:SetSize(560, 460)
    frame:SetPoint("CENTER", UIParent, "CENTER", 260, 0)
    frame:SetBackdrop({
        bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        tile=true, tileSize=32, edgeSize=32,
        insets={left=8, right=8, top=8, bottom=8}
    })
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(110)
    frame:Hide()
    tinsert(UISpecialFrames, "EPBossAuctionLootMasterFrame")
    self:SkinPanel(frame)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("EPBA: добыча босса")

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetText("X")
    close:SetNormalFontObject(GameFontNormalLarge)
    close:SetScript("OnClick", function() frame:Hide() end)
    self:SkinButton(close)

    local massLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    massLabel:SetPoint("TOPLEFT", 18, -42)
    massLabel:SetText("EP за босса:")

    local massAmount = CreateFrame("EditBox", "EPBALootMassEPAmount", frame, "InputBoxTemplate")
    massAmount:SetSize(80, 22)
    massAmount:SetPoint("LEFT", massLabel, "RIGHT", 8, 0)
    massAmount:SetAutoFocus(false)
    massAmount:SetNumeric(true)
    self:SkinInput(massAmount)

    local massReason = CreateFrame("EditBox", "EPBALootMassEPReason", frame, "InputBoxTemplate")
    massReason:SetSize(170, 22)
    massReason:SetPoint("LEFT", massAmount, "RIGHT", 8, 0)
    massReason:SetAutoFocus(false)
    massReason:SetText(self.selectedBoss or "Убийство босса")
    self:SkinInput(massReason)

    local massButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    massButton:SetSize(150, 24)
    massButton:SetPoint("LEFT", massReason, "RIGHT", 8, 0)
    massButton:SetText("Начислить рейду")
    self:SkinButton(massButton)
    massButton:SetScript("OnClick", function()
        auction:ConfirmMassBossEP(tonumber(massAmount:GetText()) or 0, massReason:GetText())
    end)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 18, -72)
    hint:SetPoint("RIGHT", -18, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("Выберите победителя ставки. Можно выдать предмет, списать ставку через EPGP:IncEPBy или сделать оба действия.")

    local scrollFrame = CreateFrame("ScrollFrame", "EPBossAuctionLootMasterScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 18, -102)
    scrollFrame:SetPoint("BOTTOMRIGHT", -34, 18)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(LOOT_ROW_WIDTH, 1)
    scrollFrame:SetScrollChild(content)

    frame.massAmount = massAmount
    frame.massReason = massReason
    frame.content = content
    frame.rows = {}
    self.lootMasterSelectedBids = self.lootMasterSelectedBids or {}
    self.lootMasterAwarded = self.lootMasterAwarded or {}
    self.lootMasterFrame = frame
end

function auction:ClearLootMasterRows()
    if not (self.lootMasterFrame and self.lootMasterFrame.rows) then return end
    for _, row in ipairs(self.lootMasterFrame.rows) do
        row:Hide()
        row:SetParent(nil)
    end
    self.lootMasterFrame.rows = {}
end

function auction:SetLootMasterSelectedBid(itemID, playerName)
    self.lootMasterSelectedBids = self.lootMasterSelectedBids or {}
    self.lootMasterSelectedBids[GetBidKey(itemID)] = playerName
    self:RefreshLootMasterWindow()
end

function auction:GetLootMasterSelectedBid(itemID, bidsForItem)
    local selectedPlayer = self.lootMasterSelectedBids and self.lootMasterSelectedBids[GetBidKey(itemID)]
    for _, bid in ipairs(bidsForItem or {}) do
        if bid.player == selectedPlayer then
            return bid
        end
    end
    return bidsForItem and bidsForItem[1] or nil
end

function auction:CreateLootBidButton(parent, row, itemID, bid, isSelected, y)
    local button = CreateFrame("Button", nil, row)
    button:SetSize(335, BID_ROW_HEIGHT)
    button:SetPoint("TOPLEFT", row, "TOPLEFT", LOOT_ROW_PADDING + 20, y)
    local c = GetThemeColors()
    button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    if isSelected then
        button:SetBackdropColor(c.accent[1], c.accent[2], c.accent[3], 0.35)
    else
        button:SetBackdropColor(0, 0, 0, 0)
    end

    local ep = self:GetPlayerEP(bid.player, false)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 4, 0)
    label:SetPoint("RIGHT", -4, 0)
    label:SetJustifyH("LEFT")
    label:SetText(GetBidderLabel(bid, ep))
    if ep < (tonumber(bid.amount) or 0) then
        label:SetTextColor(1, 0.25, 0.25)
    elseif bid.isOffspec then
        label:SetTextColor(1, 0.85, 0.35)
    else
        label:SetTextColor(1, 1, 1)
    end

    button:SetScript("OnClick", function()
        auction:SetLootMasterSelectedBid(itemID, bid.player)
    end)
    button:SetScript("OnEnter", function(selfButton)
        local c = GetThemeColors()
        selfButton:SetBackdropColor(c.buttonHover[1], c.buttonHover[2], c.buttonHover[3], 0.55)
    end)
    button:SetScript("OnLeave", function(selfButton)
        if isSelected then
            local c = GetThemeColors()
            selfButton:SetBackdropColor(c.accent[1], c.accent[2], c.accent[3], 0.35)
        else
            selfButton:SetBackdropColor(0, 0, 0, 0)
        end
    end)

    return button
end

function auction:AddLootMasterRow(parent, index, lootItem, offsetY)
    local bossName, isKnownItem = self:GetLootBossForItem(lootItem.itemID)
    local _, bidsForItem = self:GetSortedBidsForLootItem(lootItem.itemID)
    local selectedBid = self:GetLootMasterSelectedBid(lootItem.itemID, bidsForItem)
    local bidCount = #bidsForItem
    local rowHeight = 92 + math.max(1, bidCount) * BID_ROW_HEIGHT
    local itemKey = GetBidKey(lootItem.itemID)
    local awarded = self.lootMasterAwarded and self.lootMasterAwarded[itemKey]

    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(LOOT_ROW_WIDTH, rowHeight)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -offsetY)
    ApplyLootRowStyle(row, 0.88)

    local item = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    item:SetPoint("TOPLEFT", LOOT_ROW_PADDING, -8)
    item:SetPoint("RIGHT", -8, 0)
    item:SetJustifyH("LEFT")
    item:SetText((lootItem.link or lootItem.name or ("Предмет #"..lootItem.itemID)) .. (lootItem.quantity and lootItem.quantity > 1 and (" x"..lootItem.quantity) or ""))

    local info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", item, "BOTTOMLEFT", 0, -4)
    info:SetJustifyH("LEFT")
    local status = awarded and (" | |cff00ff00выдано: "..awarded.player..", "..self:FormatNumber(awarded.amount).." EP|r") or ""
    info:SetText(string.format("%s%s", bossName or "Босс не выбран", isKnownItem and status or " | |cffff5555предмет не найден в таблице босса|r"))

    if bidCount == 0 then
        local noBids = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        noBids:SetPoint("TOPLEFT", row, "TOPLEFT", LOOT_ROW_PADDING + 20, -42)
        noBids:SetText("Ставок нет")
    else
        for i, bid in ipairs(bidsForItem) do
            self:CreateLootBidButton(parent, row, lootItem.itemID, bid, selectedBid and selectedBid.player == bid.player, -38 - ((i - 1) * BID_ROW_HEIGHT))
        end
    end

    local giveButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    giveButton:SetSize(118, 22)
    giveButton:SetPoint("BOTTOMLEFT", LOOT_ROW_PADDING, 8)
    giveButton:SetText("Выдать")
    self:SkinButton(giveButton)
    giveButton:SetEnabled(selectedBid ~= nil and lootItem.slot ~= nil)
    giveButton:SetAlpha((selectedBid ~= nil and lootItem.slot ~= nil) and 1 or 0.45)
    giveButton:SetScript("OnClick", function()
        auction:ConfirmAwardLoot(lootItem, bossName, selectedBid, false)
    end)

    local chargeButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    chargeButton:SetSize(118, 22)
    chargeButton:SetPoint("LEFT", giveButton, "RIGHT", 8, 0)
    chargeButton:SetText("Списать")
    self:SkinButton(chargeButton)
    chargeButton:SetEnabled(selectedBid ~= nil)
    chargeButton:SetAlpha(selectedBid ~= nil and 1 or 0.45)
    chargeButton:SetScript("OnClick", function()
        auction:ConfirmChargeLootBid(lootItem.itemID, bossName, selectedBid)
    end)

    local bothButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    bothButton:SetSize(138, 22)
    bothButton:SetPoint("LEFT", chargeButton, "RIGHT", 8, 0)
    bothButton:SetText("Выдать + списать")
    self:SkinButton(bothButton)
    bothButton:SetEnabled(selectedBid ~= nil and lootItem.slot ~= nil)
    bothButton:SetAlpha((selectedBid ~= nil and lootItem.slot ~= nil) and 1 or 0.45)
    bothButton:SetScript("OnClick", function()
        auction:ConfirmAwardLoot(lootItem, bossName, selectedBid, true)
    end)

    table.insert(self.lootMasterFrame.rows, row)
    return rowHeight + 8
end

function auction:RefreshLootMasterWindow(lootItems)
    self:CreateLootMasterWindow()
    if lootItems then
        self.currentLootMasterItems = lootItems
    end
    lootItems = lootItems or self.currentLootMasterItems or {}

    if self.lootMasterFrame.massReason and self.selectedBoss and self.lootMasterFrame.massReason:GetText() == "" then
        self.lootMasterFrame.massReason:SetText(self.selectedBoss)
    end

    self:ClearLootMasterRows()

    local content = self.lootMasterFrame.content
    local offsetY = 0
    if #lootItems == 0 then
        local holder = CreateFrame("Frame", nil, content)
        holder:SetSize(LOOT_ROW_WIDTH, 40)
        holder:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        ApplyLootRowStyle(holder, 0.88)
        local empty = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        empty:SetPoint("TOPLEFT", 8, -8)
        empty:SetText("Нет предметов в окне добычи или предметы не распознаны.")
        table.insert(self.lootMasterFrame.rows, holder)
        offsetY = 48
    else
        for i, lootItem in ipairs(lootItems) do
            offsetY = offsetY + self:AddLootMasterRow(content, i, lootItem, offsetY)
        end
    end

    content:SetHeight(math.max(1, offsetY))
    self.lootMasterFrame:Show()
end

function auction:ShowLootMasterWindowFromLoot()
    if not self:IsLootMaster() then return end
    local lootItems = {}
    local numItems = GetNumLootItems and GetNumLootItems() or 0

    for slot = 1, numItems do
        local link = GetLootSlotLink(slot)
        local itemID = GetItemIDFromLink(link)
        if itemID then
            local icon, name, quantity, quality = GetLootSlotInfo(slot)
            table.insert(lootItems, {
                slot = slot,
                itemID = itemID,
                link = link,
                name = name,
                quantity = quantity,
                quality = quality,
                icon = icon,
            })
        end
    end

    self:RefreshLootMasterWindow(lootItems)
end

function auction:RefreshLootMasterWindowIfShown()
    if self.lootMasterFrame and self.lootMasterFrame:IsShown() then
        self:RefreshLootMasterWindow()
    end
end

function auction:ConfirmChargeLootBid(itemID, bossName, bid)
    if not (bossName and bid and bid.player and bid.amount) then return end
    local itemName = GetItemInfo(itemID) or ("Предмет #"..itemID)
    StaticPopupDialogs["EPBA_CONFIRM_CHARGE_LOOT"] = {
        text = string.format("Списать %s EP с %s за %s?", self:FormatNumber(bid.amount), bid.player, itemName),
        button1 = "Списать",
        button2 = "Отмена",
        OnAccept = function()
            auction:ChargePlayerEP(bid.player, bid.amount, itemID, bossName)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("EPBA_CONFIRM_CHARGE_LOOT")
end

function auction:ConfirmAwardLoot(lootItem, bossName, bid, chargeEP)
    if not (lootItem and bossName and bid and bid.player) then return end
    local actionText = chargeEP and "выдать предмет и списать EP" or "выдать предмет"
    StaticPopupDialogs["EPBA_CONFIRM_AWARD_LOOT"] = {
        text = string.format("%s игроку %s?\n%s", actionText, bid.player, lootItem.link or lootItem.name or "Предмет"),
        button1 = "Да",
        button2 = "Отмена",
        OnAccept = function()
            auction:AwardLootToBidder(lootItem, bossName, bid, chargeEP)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("EPBA_CONFIRM_AWARD_LOOT")
end

function auction:AwardLootToBidder(lootItem, bossName, bid, chargeEP)
    if not self:IsLootMaster() then return false end
    if not (lootItem and lootItem.slot and bid and bid.player) then return false end

    local candidateIndex = self:GetMasterLootCandidateIndex(lootItem.slot, bid.player)
    if not candidateIndex then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[EPBA]|r Игрок "..bid.player.." не найден среди кандидатов на этот предмет.")
        return false
    end

    if GiveMasterLoot then
        GiveMasterLoot(lootItem.slot, candidateIndex)
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[EPBA]|r Предмет %s выдан игроку %s.", lootItem.link or lootItem.name or lootItem.itemID, bid.player))
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[EPBA]|r GiveMasterLoot недоступен в этом клиенте.")
        return false
    end

    if chargeEP then
        return self:ChargePlayerEP(bid.player, bid.amount, lootItem.itemID, bossName)
    end

    self.lootMasterAwarded = self.lootMasterAwarded or {}
    self.lootMasterAwarded[GetBidKey(lootItem.itemID)] = { player = bid.player, amount = tonumber(bid.amount) or 0 }
    self:RefreshLootMasterWindowIfShown()
    return true
end

function auction:ChargePlayerEP(playerName, amount, itemID, bossName)
    if not self:IsLootMaster() then return false end
    local value = tonumber(amount) or 0
    if value <= 0 then return false end

    local reason = (GetItemInfo(itemID) or ("item:"..tostring(itemID)))
    local epgpTable = GetEPGP()
    if not (epgpTable and epgpTable.IncEPBy) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[EPBA]|r Не удалось списать EP: не найден EPGP:IncEPBy.")
        return false
    end

    local success = epgpTable:IncEPBy(playerName, -value, reason) ~= false
    if success then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[EPBA]|r Списано %s EP с %s за %s.", self:FormatNumber(value), playerName, reason))
        self.lootMasterAwarded = self.lootMasterAwarded or {}
        self.lootMasterAwarded[GetBidKey(itemID)] = { player = playerName, amount = value }
        self:ApplyBidChange(bossName, itemID, playerName, 0, false)
        self:CheckAndUpdateEP()
        self:RefreshLootMasterWindowIfShown()
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[EPBA]|r EPGP:IncEPBy вернул ошибку при списании EP.")
    end

    return success
end

function auction:ConfirmMassBossEP(amount, reason)
    if not self:IsLootMaster() then return end
    amount = tonumber(amount) or 0
    if amount <= 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[EPBA]|r Укажите положительное количество EP для рейда.")
        return
    end
    reason = reason and reason ~= "" and reason or (self.selectedBoss or "Убийство босса")

    StaticPopupDialogs["EPBA_CONFIRM_MASS_EP"] = {
        text = string.format("Начислить рейду %s EP?\nПричина: %s", self:FormatNumber(amount), reason),
        button1 = "Начислить",
        button2 = "Отмена",
        OnAccept = function()
            auction:AwardMassBossEP(amount, reason)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("EPBA_CONFIRM_MASS_EP")
end

function auction:AwardMassBossEP(amount, reason)
    if not self:IsLootMaster() then return false end
    local epgpTable = GetEPGP()
    if not (epgpTable and epgpTable.IncMassEPBy) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[EPBA]|r Не удалось начислить EP: не найден EPGP:IncMassEPBy.")
        return false
    end

    local success = epgpTable:IncMassEPBy(amount, reason) ~= false
    if success then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[EPBA]|r Рейду начислено %s EP за: %s.", self:FormatNumber(amount), reason))
        self:CheckAndUpdateEP()
        self:RefreshLootMasterWindowIfShown()
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[EPBA]|r EPGP:IncMassEPBy вернул ошибку при начислении EP.")
    end

    return success
end
