local auction = EPBossAuction

local LOOT_ROW_WIDTH = 490
local LOOT_ROW_PADDING = 8
local BID_ROW_HEIGHT = 20
local LOOT_ICON_SIZE = 32

-- =====================================================
-- THEME
-- =====================================================
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
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1
    })
    frame:SetBackdropColor(c.panel[1], c.panel[2], c.panel[3], alpha or c.panel[4])
    frame:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], c.border[4])
end

-- =====================================================
-- CACHE (ГЛАВНОЕ ИЗМЕНЕНИЕ)
-- =====================================================
auction.lootCandidatesCache = auction.lootCandidatesCache or {}

function auction:CacheLootCandidates()
    wipe(self.lootCandidatesCache)

    local numItems = GetNumLootItems() or 0

    for slot = 1, numItems do
        self.lootCandidatesCache[slot] = {}

        for i = 1, 40 do
            local name = GetMasterLootCandidate(slot, i)
            if not name then break end

            self.lootCandidatesCache[slot][i] = {
                name = name,
                index = i,
                slot = slot
            }
        end
    end
end

-- =====================================================
-- HELPERS
-- =====================================================
local function GetItemIDFromLink(itemLink)
    if not itemLink then return nil end
    return tonumber(string.match(itemLink, "item:(%d+):"))
end

local function GetLootItemIcon(lootItem)
    if lootItem and lootItem.icon then return lootItem.icon end
    if lootItem and lootItem.itemID then
        local _, _, _, _, _, _, _, _, _, itemIcon = GetItemInfo(lootItem.itemID)
        return itemIcon
    end
    return nil
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
    return string.format(
        "%s — ставка %s EP%s / EP: %s",
        bid.player or "?",
        auction:FormatNumber(tonumber(bid.amount) or 0),
        offspecMark,
        epText
    )
end

-- =====================================================
-- BID SELECTION (INDEX BASED)
-- =====================================================
function auction:SetLootMasterSelectedBid(itemID, slot, index)
    self.lootMasterSelectedBids = self.lootMasterSelectedBids or {}

    local candidates = self.lootCandidatesCache[slot]
    if not candidates or not candidates[index] then return end

    self.lootMasterSelectedBids[GetBidKey(itemID)] = {
        player = candidates[index].name,
        index = index,
        slot = slot
    }

    self:RefreshLootMasterWindow()
end

function auction:GetLootMasterSelectedBid(itemID)
    self.lootMasterSelectedBids = self.lootMasterSelectedBids or {}
    return self.lootMasterSelectedBids[GetBidKey(itemID)]
end

-- =====================================================
-- EP CHARGE
-- =====================================================
function auction:ChargePlayerEP(playerName, amount, itemID, bossName)
    if not self:IsLootMaster() then return false end

    local value = tonumber(amount) or 0
    if value <= 0 then return false end

    local epgpTable = GetEPGP()
    if not (epgpTable and epgpTable.IncEPBy) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[EPBA]|r EPGP не найден.")
        return false
    end

    local reason = GetItemInfo(itemID) or ("item:" .. tostring(itemID))

    local success = epgpTable:IncEPBy(playerName, reason, -value) ~= false

    if success then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cff00ff00[EPBA]|r Списано %s EP с %s за %s.",
            self:FormatNumber(value),
            playerName,
            reason
        ))

        self.lootMasterAwarded = self.lootMasterAwarded or {}
        self.lootMasterAwarded[GetBidKey(itemID)] = {
            player = playerName,
            amount = value
        }

        self:ApplyBidChange(bossName, itemID, playerName, 0, false)
        self:CheckAndUpdateEP()
        self:RefreshLootMasterWindowIfShown()
    end

    return success
end

-- =====================================================
-- CONFIRM CHARGE
-- =====================================================
function auction:ConfirmChargeLootBid(itemID, bossName, bid)
    if not (bid and bid.player and bid.amount) then return end

    local itemName = GetItemInfo(itemID) or ("Предмет #" .. itemID)

    StaticPopupDialogs["EPBA_CONFIRM_CHARGE_LOOT"] = {
        text = string.format(
            "Списать %s EP с %s за %s?",
            self:FormatNumber(bid.amount),
            bid.player,
            itemName
        ),
        button1 = "Списать",
        button2 = "Отмена",
        OnAccept = function()
            auction:ChargePlayerEP(
                bid.player,
                bid.amount,
                itemID,
                bossName
            )
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    StaticPopup_Show("EPBA_CONFIRM_CHARGE_LOOT")
end

-- =====================================================
-- BID BUTTON
-- =====================================================
function auction:CreateLootBidButton(parent, row, itemID, slot, bid, isSelected, y)
    local button = CreateFrame("Button", nil, row)
    button:SetSize(335, BID_ROW_HEIGHT)
    button:SetPoint("TOPLEFT", row, "TOPLEFT", LOOT_ROW_PADDING + LOOT_ICON_SIZE + 8, y)

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
    label:SetText(GetBidderLabel(bid, ep))

    button:SetScript("OnClick", function()
        auction:SetLootMasterSelectedBid(itemID, slot, bid.index)
    end)

    return button
end

-- =====================================================
-- LOOT ROW
-- =====================================================
function auction:AddLootMasterRow(parent, index, lootItem, offsetY)
    local bossName, isKnownItem = self:GetLootBossForItem(lootItem.itemID)
    local _, bidsForItem = self:GetSortedBidsForLootItem(lootItem.itemID)

    local selectedBid = self:GetLootMasterSelectedBid(lootItem.itemID)

    local rowHeight = 92 + math.max(1, #bidsForItem) * BID_ROW_HEIGHT

    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(LOOT_ROW_WIDTH, rowHeight)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -offsetY)
    ApplyLootRowStyle(row, 0.88)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(LOOT_ICON_SIZE, LOOT_ICON_SIZE)
    icon:SetPoint("TOPLEFT", LOOT_ROW_PADDING, -8)
    icon:SetTexture(GetLootItemIcon(lootItem) or "Interface\\Icons\\INV_Misc_QuestionMark")

    local item = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    item:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 0)
    item:SetText(lootItem.link or lootItem.name or ("Item #" .. lootItem.itemID))

    -- GIVE
    local giveButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    giveButton:SetSize(170, 22)
    giveButton:SetPoint("BOTTOMLEFT", LOOT_ROW_PADDING, 8)
    giveButton:SetText("Выдать")

    giveButton:SetEnabled(selectedBid ~= nil and lootItem.slot ~= nil)

    giveButton:SetScript("OnClick", function()
        if not selectedBid then return end
        GiveMasterLoot(lootItem.slot, selectedBid.index)
    end)

    -- CHARGE
    local chargeButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    chargeButton:SetSize(170, 22)
    chargeButton:SetPoint("LEFT", giveButton, "RIGHT", 8, 0)
    chargeButton:SetText("Списать")

    chargeButton:SetEnabled(selectedBid ~= nil)

    chargeButton:SetScript("OnClick", function()
        auction:ConfirmChargeLootBid(
            lootItem.itemID,
            bossName,
            selectedBid
        )
    end)

    table.insert(self.lootMasterFrame.rows, row)

    return rowHeight + 8
end

-- =====================================================
-- LOOT OPEN HOOK
-- =====================================================
function auction:ShowLootMasterWindowFromLoot()
    if not self:IsLootMaster() then return end

    self:CacheLootCandidates()

    local lootItems = {}
    local numItems = GetNumLootItems() or 0

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
