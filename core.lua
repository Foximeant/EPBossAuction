local addonName = ...
EPBossAuction = {}
local auction = EPBossAuction

-- ======================
-- Настройки и переменные
-- ======================
auction.prefix = "EPBAUC"
auction.version = "3.0.13"
auction.debug = true
auction.fullyLoaded = false
auction.pendingWorldEnter = nil

auction.bosses = {
   -- ["TEST"] = {45024, 38164, 65015, 72898, 77996, 119260, 119272, 31257, 78486},
    ["Лютый Хлад"] = {156100, 156101, 156102, 156103, 156104, 156105, 156106, 156107, 156108, 156109, 156110, 156111, 156160, 156161},
    ["Анетерон"] = {156112, 156113, 156114, 156115, 156116, 156117, 156118, 156119, 156120, 156121, 156122, 156123, 156162, 156163, 156180, 154664, 154672, 154720, 154728, 154784, 154792, 154800, 154808, 154824, 154832, 154864},
    ["Каз'рогал"] = {31092, 31093, 31094, 59495, 101395, 156124, 156125, 156126, 156128, 156129, 156130, 156131, 156132, 156133, 156134, 156135, 156164, 156165},
    ["Азгалор"] = {156136, 156137, 156138, 156139, 156140, 156141, 156142, 156143, 156144, 156145, 156146, 156137, 156166, 156167, 154655, 154671, 154679, 154711, 154719, 154727, 154743, 154751, 154767, 154783, 154799, 154807},
    ["Архимонд"] = {156148, 156149, 156151, 156154, 156155, 156168, 156169, 156170, 156171, 156172, 156173, 156174, 156175, 156176, 156177, 156178, 156179, 31097, 31095, 31096},
    ["Мурозонд"] = {139026, 139027, 139028, 139029, 139030, 139031, 139032, 139033, 139034, 139035, 139036, 139037, 139038, 139039, 139048, 139049, 139050, 139051, 139045, 139053, 139054, 139055, 139056, 139057, 139058},
    ["Верховный полководец Надж'ентус"] = {156181, 156182, 156183, 156184, 156185, 156186, 156187, 156188, 156189, 156190, 156191, 156192, 156193, 156194, 156195, 156196},
    ["Супремус"] = {156197, 156198, 156199, 156200, 156201, 156202, 156203, 156204, 156205, 156206, 156207, 156208, 156209, 156210, 156211, 156212},
    ["Реликварий душ"] = {102225, 156224, 156225, 156226, 156227, 156228, 156229, 156230, 156231, 156232, 156233},
    ["Гуртогг Кипящая Кровь"] = {102223, 104265, 156234, 156235, 156236, 156237, 156238, 156239, 156240, 156242, 156243, 156244, 156256},
    ["Терон Кровожад"] = {104266, 156245, 156246, 156247, 156248, 156249, 156250, 156251, 156252, 156253, 156254},
    ["Тень Акамы"] = {99898, 102221,  102224, 102220, 156213, 156214, 156215, 156216, 156217, 156218, 156220, 156221, 156222, 156223},
    ["Зорт"] = {97753, 97754, 97755, 97756, 97757, 97760, 97761, 97762, 97763, 97767, 97768, 97769},
    ["Матушка Шахраз"] = {102229, 156267, 156258, 156259, 156260, 156262, 156264, 156265, 156266, 156276, 156284, 31101, 31102, 31103},
    ["Совет Иллидари"] = {102222, 102226, 102227, 156261, 156263, 156274, 156275, 156277, 156278, 156280, 156281, 156282, 31098, 31099, 31100},
    ["Иллидан Ярость Бури"] = {102228, 156268, 156269, 156285, 156286, 156287, 156288, 156289, 156290, 156291, 156292, 156293, 156294, 156295, 156296, 156297, 31089, 31090, 31091, 119287, 119288},
}
auction.bossOrder = {
  --  "TEST",
    "Лютый Хлад",
    "Анетерон",
    "Каз'рогал",
    "Азгалор",
    "Архимонд",
    "Мурозонд",
    "Зорт",
    "Верховный полководец Надж'ентус",
    "Супремус",
    "Реликварий душ",
    "Гуртогг Кипящая Кровь",
    "Терон Кровожад",
    "Тень Акамы",
    "Матушка Шахраз",
    "Совет Иллидари",
    "Иллидан Ярость Бури",
}
auction.bids = {}
auction.selectedBoss = nil
auction.selectedItem = nil
auction.lastLM = nil
auction.myEP = 0

auction.dataVersions = {}
auction.lastVersions = {}
auction.sortedBids = {}
auction.maxBidCache = {}
auction.myBidCache = {}

auction.saveTimer = nil
auction.pendingSaveTimer = nil
auction.dataDirty = false
auction.lastSaveTime = 0
auction.isLMMode = false
auction.receivedItems = {}
auction.receivedSync = false
auction.receivedAck = false

auction.updateTimer = nil
auction.lastEPUpdate = 0
auction.epUpdateInterval = 300
auction.epUpdatePending = false
auction.isUpdatingEP = false

auction.windowScale = 1.0
auction.minScale = 0.7
auction.maxScale = 1.5
auction.scaleStep = 0.1

auction.minimapButton = nil
auction.minimapButtonPosition = { angle = 0 }

auction.bidsLocked = false
auction.offspecMultiplier = 0.5

auction.outbidNotified = {}
auction.outbidThrottle = {}

auction.playerEPCache = {}
auction.playerEPCacheTime = {}
auction.playerClassCache = {}

auction.defaults = {
    general = {
        debug = false,
        minBid = 100,
        confirmBid = false,
        soundEnabled = true,
        soundFile = "Interface\\AddOns\\EPBossAuction\\sounds\\bid.ogg",
        offspecMultiplier = 0.5,
    },
    table = {
        itemFontSize = 12,
        itemFont = "GameFontNormal",
        itemColor = {1, 1, 1},
        itemWidth = 250,
        bidFontSize = 12,
        bidFont = "GameFontNormal",
        bidColor = {1, 1, 1},
        bidWidth = 250,
        rowHeight = 20,
        showIcons = true,
        showTopBids = 2,
        hideNoBids = false,
        alternatingRows = true,
        evenRowColor = {1, 1, 1, 0.03},
        oddRowColor = {0, 0, 0, 0},
        selectedRowColor = {0.80, 0.62, 0.10, 0.30},
        hoverRowColor = {0.2, 0.2, 0.2, 0.5},
        itemColorMode = "gold",
        tooltipAnchor = "CURSOR",
        columnSplit = 40,
    },
    minimap = {
        show = true,
        radius = 70,
        size = 32,
        strata = "MEDIUM",
        tooltip = true,
        position = { angle = 0 },
    },
    window = {
        scale = 1.0,
        width = 650,
        height = 515,
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 0,
        alpha = 1.0,
        locked = false,
    },
}

auction.db = {}

-- ======================
-- Таймеры (оптимизированные, без сортировки)
-- ======================
auction.timerFrame = CreateFrame("Frame")
auction.timerId = 0
auction.timers = {}

auction.timerFrame:SetScript("OnUpdate", function()
    local now = GetTime()
    local i = 1
    while i <= #auction.timers do
        local timer = auction.timers[i]
        if timer.expires <= now then
            table.remove(auction.timers, i)
            local ok, err = pcall(timer.cb)
            if not ok and auction.Debug then
                auction:Debug("Timer error: " .. tostring(err))
            end
        else
            i = i + 1
        end
    end
end)

function auction:ScheduleTimer(callback, delay)
    self.timerId = self.timerId + 1
    local id = tostring(self.timerId)
    local expires = GetTime() + delay
    table.insert(self.timers, { id = id, cb = callback, expires = expires })
    return id
end

function auction:CancelTimer(id)
    for i, timer in ipairs(self.timers) do
        if timer.id == id then
            table.remove(self.timers, i)
            break
        end
    end
end

-- ======================
-- Утилиты
-- ======================
function auction:Debug(msg, ...)
    if not self.debug then return end
    if select('#', ...) > 0 then
        msg = string.format(msg, ...)
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff888888[EPBA DEBUG]|r "..msg)
end

function auction:DeepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = self:DeepCopy(v)
    end
    return copy
end

function auction:MergeDefaults(saved, defaults)
    local merged = self:DeepCopy(defaults)
    if type(saved) ~= "table" then return merged end
    for k, v in pairs(saved) do
        if type(v) == "table" and type(merged[k]) == "table" then
            merged[k] = self:MergeDefaults(v, merged[k])
        else
            merged[k] = v
        end
    end
    return merged
end

function auction:FormatNumber(n)
    if not n then return "0" end
    local sign = ""
    if n < 0 then
        sign = "-"
        n = -n
    end
    local int_part, frac_part = math.modf(n)
    local formatted = tostring(int_part):reverse():gsub("(%d%d%d)", "%1 "):reverse()
    if frac_part > 0 then
        formatted = formatted .. string.format("%.2f", frac_part):sub(2)
    end
    return sign .. formatted
end

function auction:CacheRaidClasses()
    local newCache = {}
    if IsInRaid() then
        for i = 1, GetNumRaidMembers() do
            local name, _, _, _, _, class = GetRaidRosterInfo(i)
            if name then
                newCache[name] = class or "UNKNOWN"
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumPartyMembers() do
            local unit = "party"..i
            local name = UnitName(unit)
            local _, class = UnitClass(unit)
            if name then
                newCache[name] = class or "UNKNOWN"
            end
        end
    end
    local _, playerClass = UnitClass("player")
    newCache[UnitName("player")] = playerClass
    self.playerClassCache = newCache
end

function auction:GetClassColor(playerName)
    if not playerName then return "|cffffffff" end
    local class = self.playerClassCache[playerName]
    if class and RAID_CLASS_COLORS[class] then
        local c = RAID_CLASS_COLORS[class]
        return string.format("|cff%02x%02x%02x", c.r*255, c.g*255, c.b*255)
    end
    if playerName == UnitName("player") then
        local _, playerClass = UnitClass("player")
        local color = RAID_CLASS_COLORS[playerClass]
        if color then
            return string.format("|cff%02x%02x%02x", color.r*255, color.g*255, color.b*255)
        end
    end
    return "|cffffffff"
end

function auction:FormatColoredName(playerName)
    return self:GetClassColor(playerName) .. playerName
end

function auction:GetCachedItemName(itemID)
    if not self.itemNameCache then self.itemNameCache = {} end
    if self.itemNameCache[itemID] then return self.itemNameCache[itemID] end
    local name = GetItemInfo(itemID)
    if name then
        self.itemNameCache[itemID] = name
        return name
    end
    return "item:" .. itemID
end

function auction:ClearPlayerEPCache()
    self.playerEPCache = {}
    self.playerEPCacheTime = {}
end

function auction:SetCachedPlayerEP(playerName, ep)
    self.playerEPCache[playerName] = ep
    self.playerEPCacheTime[playerName] = GetTime()
end

function auction:GetCachedPlayerEP(playerName)
    local ep = self.playerEPCache[playerName]
    if ep and (GetTime() - (self.playerEPCacheTime[playerName] or 0)) < 300 then
        return ep
    end
    return nil
end

function auction:GetMaxBidAmount(isOffspec)
    local currentEP = self.myEP or 0
    if isOffspec then
        return math.floor(currentEP * (self.offspecMultiplier or 0.5))
    end
    return currentEP
end

function auction:PlayOutbidSound()
    if self.db and self.db.general and self.db.general.soundEnabled then
        local soundFile = self.db.general.soundFile or "Sound\\Interface\\RaidWarning.wav"
        PlaySoundFile(soundFile)
    end
end

function auction:UpdateSortedBids(bossName, itemID)
    self.sortedBids[bossName] = self.sortedBids[bossName] or {}
    local bids = self.bids[bossName] and self.bids[bossName][itemID]
    if bids then
        local sorted = {}
        for _, bid in ipairs(bids) do
            table.insert(sorted, bid)
        end
        table.sort(sorted, function(a,b) return a.amount > b.amount end)
        self.sortedBids[bossName][itemID] = sorted
    else
        self.sortedBids[bossName][itemID] = {}
    end
end

function auction:UpdateBidCaches(bossName, itemID)
    local bids = self.bids[bossName] and self.bids[bossName][itemID]
    local key = bossName .. ":" .. itemID
    local playerName = UnitName("player")
    local maxBid = 0
    local myBid = 0
    if bids then
        for _, bid in ipairs(bids) do
            if bid.amount > maxBid then maxBid = bid.amount end
            if bid.player == playerName then myBid = bid.amount end
        end
    end
    self.maxBidCache[key] = maxBid
    self.myBidCache[key] = myBid
end

function auction:GetVersionKey(bossName, itemID)
    if not bossName or not itemID then return nil end
    return tostring(bossName) .. ":" .. tostring(itemID)
end

function auction:NormalizeVersionTable(versionTable)
    local normalized = {}
    if type(versionTable) ~= "table" then
        return normalized
    end

    for key, version in pairs(versionTable) do
        if type(version) == "number" then
            local keyStr = tostring(key)
            if keyStr:find(":", 1, true) then
                normalized[keyStr] = version
            elseif self.bosses[keyStr] then
                for _, itemID in ipairs(self.bosses[keyStr]) do
                    normalized[self:GetVersionKey(keyStr, itemID)] = version
                end
            end
        end
    end

    return normalized
end

function auction:GetDataVersion(bossName, itemID)
    local key = self:GetVersionKey(bossName, itemID)
    return (key and self.dataVersions[key]) or 0
end

function auction:IncrementDataVersion(bossName, itemID)
    local key = self:GetVersionKey(bossName, itemID)
    if not key then return 0 end
    self.dataVersions[key] = (self.dataVersions[key] or 0) + 1
    return self.dataVersions[key]
end

function auction:GetLastVersion(bossName, itemID)
    local key = self:GetVersionKey(bossName, itemID)
    return (key and self.lastVersions[key]) or 0
end

function auction:SetLastVersion(bossName, itemID, version)
    local key = self:GetVersionKey(bossName, itemID)
    if key and version and version > 0 then
        self.lastVersions[key] = version
    end
end

function auction:ResetVersionsForNewLM()
    self.lastVersions = {}
    self.receivedItems = {}
    self.receivedSync = false
    self.receivedAck = false
    self:Debug("Сброшены версии ставок для нового Loot Master")
end

function auction:ResetVersionsOnGroupExit()
    self.dataVersions = {}
    self.lastVersions = {}
    self.lastLM = nil
    self.receivedItems = {}
    self.receivedSync = false
    self.receivedAck = false
    self:Debug("Сброшены версии ставок после выхода из группы/рейда")
    if self.fullyLoaded then
        self:SaveData()
    end
end

function auction:RebuildBidData()
    wipe(self.sortedBids)
    wipe(self.maxBidCache)
    wipe(self.myBidCache)
    for bossName, bossBids in pairs(self.bids or {}) do
        for itemID, _ in pairs(bossBids) do
            self:UpdateSortedBids(bossName, itemID)
            self:UpdateBidCaches(bossName, itemID)
        end
    end
end

function auction:GetPlayerEP(playerName, forceRefresh)
    if not playerName or playerName == "" then
        return 0
    end

    if playerName == UnitName("player") then
        return tonumber(self.myEP) or 0
    end

    if not forceRefresh then
        local cached = self:GetCachedPlayerEP(playerName)
        if cached ~= nil then
            return cached
        end
    end

    local epgpTable = EPGP or EPGP_Auction or CEPGP or EPGPCore
    if not epgpTable then
        return self:GetCachedPlayerEP(playerName) or 0
    end

    local resolvedEP = nil

    if epgpTable.GetEPGP then
        local ep, gp, main = epgpTable:GetEPGP(playerName)
        if ep then
            if main and main ~= "" then
                local mainEP = epgpTable:GetEPGP(main)
                resolvedEP = tonumber(mainEP) or tonumber(ep) or 0
            else
                resolvedEP = tonumber(ep) or 0
            end
        end
    end

    if resolvedEP == nil and epgpTable.db and epgpTable.db.profile and epgpTable.db.profile.players then
        local playerData = epgpTable.db.profile.players[playerName]
        if playerData then
            if playerData.main then
                local mainData = epgpTable.db.profile.players[playerData.main]
                resolvedEP = tonumber(mainData and mainData.EP or playerData.EP) or 0
            else
                resolvedEP = tonumber(playerData.EP) or 0
            end
        end
    end

    if resolvedEP == nil and epgpTable.GetEP then
        resolvedEP = tonumber(epgpTable:GetEP(playerName)) or 0
    end

    if resolvedEP == nil then
        resolvedEP = self:GetCachedPlayerEP(playerName) or 0
    end

    self:SetCachedPlayerEP(playerName, resolvedEP)
    return resolvedEP
end

function auction:RefreshPlayerEPCache()
    self:ClearPlayerEPCache()

    local playerName = UnitName("player")
    if playerName then
        self:SetCachedPlayerEP(playerName, tonumber(self.myEP) or 0)
    end

    if IsInRaid() then
        for i = 1, GetNumRaidMembers() do
            local name = GetRaidRosterInfo(i)
            if name then
                self:GetPlayerEP(name, true)
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumPartyMembers() do
            local name = UnitName("party"..i)
            if name then
                self:GetPlayerEP(name, true)
            end
        end
    end
end

function auction:GetRaidKey()
    if not IsInRaid() then return "solo" end
    local names = {}
    for i = 1, GetNumRaidMembers() do
        local name = GetRaidRosterInfo(i)
        if name then table.insert(names, name) end
    end
    table.sort(names)
    return table.concat(names, ",")
end

function auction:IsLootMaster()
    local method, partyIndex, raidIndex = GetLootMethod()
    if method ~= "master" then return false end
    if raidIndex then
        local name = GetRaidRosterInfo(raidIndex)
        return name == UnitName("player")
    elseif partyIndex then
        return UnitIsGroupLeader("player")
    end
    return false
end

function auction:PrecacheItems()
    for boss, itemList in pairs(self.bosses) do
        for _, itemID in ipairs(itemList) do
            GetItemInfo(itemID)
        end
    end
end

function auction:LoadSettings()
    self.db = self:MergeDefaults(EPBossAuctionSettings, self.defaults)
    if self.db.general.minBid == 1000 then
        self.db.general.minBid = 100
    end
    self.db.window.width = math.max(650, self.db.window.width or 650)
    self.db.window.height = math.max(515, self.db.window.height or 515)
    self.debug = self.db.general.debug
    self.windowScale = self.db.window.scale
    self.minimapButtonPosition = self.db.minimap.position
    self.offspecMultiplier = self.db.general.offspecMultiplier or 0.5
end

function auction:SaveSettings()
    EPBossAuctionSettings = self.db
end

function auction:RequestSaveData(delay)
    self.dataDirty = true

    if self.pendingSaveTimer then
        self:CancelTimer(self.pendingSaveTimer)
        self.pendingSaveTimer = nil
    end

    self.pendingSaveTimer = self:ScheduleTimer(function()
        self.pendingSaveTimer = nil
        if self.dataDirty then
            self:SaveData(true)
        end
    end, delay or 1)
end

function auction:ApplySettings()
    self.debug = self.db.general.debug
    self.windowScale = self.db.window.scale
    self.minimapButtonPosition = self.db.minimap.position
    if self.frame then
        self.frame:SetScale(self.db.window.scale)
        self.db.window.width = math.max(650, self.db.window.width or 650)
        self.db.window.height = math.max(515, self.db.window.height or 515)
        self.frame:SetSize(self.db.window.width, self.db.window.height)
        self.frame:SetAlpha(self.db.window.alpha)
        if self.db.window.locked then
            self.frame:SetMovable(false)
            self.frame:RegisterForDrag()
        else
            self.frame:SetMovable(true)
            self.frame:RegisterForDrag("LeftButton")
        end
    end
    if self.minimapButton then
        if self.db.minimap.show then
            self.minimapButton:Show()
            self.minimapButton:SetSize(self.db.minimap.size, self.db.minimap.size)
            self.minimapButton:SetFrameStrata(self.db.minimap.strata)
            local angle = self.db.minimap.position.angle or 0
            local x = self.db.minimap.radius * math.cos(math.rad(angle))
            local y = self.db.minimap.radius * math.sin(math.rad(angle))
            self.minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
        else
            self.minimapButton:Hide()
        end
    end
    if self.selectedBoss then
        self:RequestRefresh()
    end
end

function auction:SaveData(force)
    if self.pendingSaveTimer then
        self:CancelTimer(self.pendingSaveTimer)
        self.pendingSaveTimer = nil
    end

    self.db.window.scale = self.windowScale
    self.db.general.offspecMultiplier = self.offspecMultiplier
    self.db.minimap.position = self.minimapButtonPosition
    EPBossAuctionSavedBids = self.bids
    EPBossAuctionSavedVersions = self.dataVersions
    EPBossAuctionSavedTime = GetTime()
    EPBossAuctionSavedLM = UnitName("player")
    EPBossAuctionSavedSelectedBoss = self.selectedBoss
    EPBossAuctionSavedSelectedItem = self.selectedItem
    EPBossAuctionSavedScale = self.windowScale
    EPBossAuctionSavedMinimapPos = self.minimapButtonPosition
    EPBossAuctionBidsLocked = self.bidsLocked
    EPBossAuctionSavedOffspecMultiplier = self.offspecMultiplier
    self:SaveSettings()
    self.dataDirty = false
    self.lastSaveTime = GetTime()
end

function auction:InitAutoSave()
    if self.saveTimer then self:CancelTimer(self.saveTimer) end
    local function saveFunc()
        if auction.dataDirty then
            auction:SaveData(true)
        end
        auction.saveTimer = auction:ScheduleTimer(saveFunc, 10)
    end
    self.saveTimer = self:ScheduleTimer(saveFunc, 10)
end

function auction:SaveWindowPosition()
    if not self.frame then return end
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    self.db.window.point = point or "CENTER"
    self.db.window.relativePoint = relativePoint or self.db.window.point
    self.db.window.x = x or 0
    self.db.window.y = y or 0
end

function auction:GetTooltipAnchor()
    local anchor = self.db and self.db.table and self.db.table.tooltipAnchor or "CURSOR"
    if anchor == "CURSOR" then return "ANCHOR_CURSOR" end
    return "ANCHOR_" .. anchor
end

function auction:SetWindowScale(scale)
    scale = math.max(self.minScale, math.min(self.maxScale, scale))
    if self.frame then
        self.windowScale = scale
        self.db.window.scale = scale
        self.frame:SetScale(scale)
    end
end

function auction:CleanOutbidNotified()
    self.outbidNotified = {}
    self.outbidThrottle = {}
    self:Debug("Очищены уведомления о перебитых ставках")
    if self.fullyLoaded then
        self:ScheduleTimer(function()
            auction:CleanOutbidNotified()
        end, 300)
    end
end

function auction:ZoomIn()
    self:SetWindowScale(self.windowScale + self.scaleStep)
end

function auction:ZoomOut()
    self:SetWindowScale(self.windowScale - self.scaleStep)
end

function auction:ResetZoom()
    self:SetWindowScale(1.0)
end

function auction:ForceSave()
    self:SaveData()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Данные сохранены")
end

function auction:UpdateScrollFrameSize()
    if not self.frame or not self.scrollFrame then return end
    self.scrollFrame:SetPoint("TOPLEFT", self.leftPanel, "TOPRIGHT", 10, 0)
    self.scrollFrame:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -16, 16)
    if self.scrollBG then
        self.scrollBG:SetPoint("TOPLEFT", self.scrollFrame, "TOPLEFT", -2, 2)
        self.scrollBG:SetPoint("BOTTOMRIGHT", self.scrollFrame, "BOTTOMRIGHT", 2, -2)
    end
end

function auction:RequestRefresh()
    if self.refreshTimer then
        self:CancelTimer(self.refreshTimer)
        self.refreshTimer = nil
    end

    self.refreshPending = true
    self.refreshTimer = self:ScheduleTimer(function()
        self.refreshTimer = nil
        self.refreshPending = false
        if self.frame and self.frame:IsShown() and self.selectedBoss then
            self:RefreshTable()
        end
    end, 0.1)
end

