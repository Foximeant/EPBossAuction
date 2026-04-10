local addonName = ...
EPBossAuction = {}
local auction = EPBossAuction

auction.debugCounters = {
    rowsCreated = 0,
    rowsDeleted = 0,
    currentRows = 0,
    totalFrames = 0
}

-- ======================
-- Настройки и переменные
-- ======================
auction.prefix = "EPBAUC"
auction.version = "1.6.2"
auction.debug = true
auction.fullyLoaded = false
auction.pendingWorldEnter = nil

auction.bosses = {
    ["Архимонд"] = {156148, 156149, 156151, 156154, 156155, 156168, 156169, 156170, 156171, 156172, 156173, 156174, 156175, 156176, 156177, 156178, 156179},
    ["Мурозонд"] = {139026, 139027, 139028, 139029, 139030, 139031, 139032, 139033, 139034, 139035, 139036, 139037, 139038, 139039, 139048, 139049, 139050, 139051, 139045, 139053, 139054, 139055, 139056, 139057, 139058},
    ["Верховный полководец Надж'ентус"] = {156181, 156182, 156183, 156184, 156185, 156186, 156187, 156188, 156189, 156190, 156191, 156192, 156193, 156194, 156195, 156196},
    ["Супремус"] = {156197, 156198, 156199, 156200, 156201, 156202, 156203, 156204, 156205, 156206, 156207, 156208, 156209, 156210, 156211, 156212},
    ["Реликварий душ"] = {156224, 156225, 156226, 156227, 156228, 156229, 156230, 156231, 156232, 156233},
    ["Гуртогг Кипящая Кровь"] = {156234, 156235, 156236, 156237, 156238, 156239, 156240, 156242, 156243, 156244, 156256},
    ["Терон Кровожад"] = {156245, 156246, 156247, 156248, 156249, 156250, 156251, 156252, 156253, 156254},
    ["Тень Акамы"] = {99898, 156213, 156214, 156215, 156216, 156217, 156218, 156220, 156221, 156222, 156223, 34853, 34854, 34855},
    ["Зорт"] = {97753, 97754, 97755, 97756, 97757, 97760, 97761, 97762, 97763, 97767, 97768, 97769},
    ["Т6 токены"] = {34848, 34851, 34852, 31097, 31095, 31096},
    ["Матушка Шахраз"] = {31101, 31102, 31103},
    ["Совет Иллидари"] = {31098, 31099, 31100},
    ["Иллидан Ярость Бури"] = {31089, 31090, 31091, 32837, 32838},
}
auction.bossOrder = {
    "Т6 токены",
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

-- Версии для каждого босса
auction.dataVersions = {}
auction.lastVersions = {}

auction.saveTimer = nil
auction.lastSaveTime = 0
auction.isLMMode = false
auction.receivedItems = {}
auction.receivedSync = false
auction.receivedAck = false

-- Переменные для динамического обновления EP
auction.updateTimer = nil
auction.lastEPUpdate = 0
auction.epUpdateInterval = 60
auction.epUpdatePending = false
auction.isUpdatingEP = false

-- Переменные для масштабирования
auction.windowScale = 1.0
auction.minScale = 0.7
auction.maxScale = 1.5
auction.scaleStep = 0.1

-- Переменные для кнопки миникарты
auction.minimapButton = nil
auction.minimapButtonPosition = { angle = 0 }

-- Переменная для блокировки ставок
auction.bidsLocked = false

-- Коэффициент офф-спек (устанавливается лутером)
auction.offspecMultiplier = 0.5

-- Лог ставок (хранит историю)
auction.bidLog = {}

-- Таблица для отслеживания уже показанных уведомлений
auction.outbidNotified = {}

-- Кэш EP игроков (для тултипа)
auction.playerEPCache = {}

-- Очередь на токены Т6
auction.tokenQueueText = ""
auction.receivedQueueParts = nil

-- Система настроек (базовые настройки, defaults)
auction.defaults = {
    general = {
        debug = false,
        minBid = 1000,
        autoRequest = true,
        confirmBid = false,
        soundEnabled = true,
        soundFile = "Sound\\Interface\\RaidWarning.wav",
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
        alternatingRows = true,
        evenRowColor = {1, 1, 1, 0.03},
        oddRowColor = {0, 0, 0, 0},
        selectedRowColor = {0.3, 0.6, 1, 0.3},
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
        width = 640,
        height = 450,
        alpha = 1.0,
        locked = false,
    },
    tokenQueue = {
        text = "",
    },
}

auction.db = {}

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

function auction:ScheduleTimer(func, delay)
    local frame = CreateFrame("Frame")
    local start = GetTime()
    frame:SetScript("OnUpdate", function()
        if GetTime() - start >= delay then
            func()
            frame:SetScript("OnUpdate", nil)
            frame:Hide()
            frame:SetParent(nil)
        end
    end)
    return frame
end

function auction:FormatNumber(n)
    if not n then return "0" end
    local left, num, right = tostring(n):match("^([^%d]*%d)(%d*)(.-)$")
    return left .. (num:reverse():gsub("(%d%d%d)", "%1 "):reverse()) .. right
end

function auction:GetClassColor(playerName)
    if not playerName then return "|cffffffff" end
    if playerName == UnitName("player") then
        local _, class = UnitClass("player")
        local color = RAID_CLASS_COLORS[class]
        if color then
            return string.format("|cff%02x%02x%02x", color.r*255, color.g*255, color.b*255)
        end
    end
    if IsInRaid() then
        for i = 1, GetNumRaidMembers() do
            local name, _, _, _, _, class = GetRaidRosterInfo(i)
            if name == playerName then
                if class and RAID_CLASS_COLORS[class] then
                    local color = RAID_CLASS_COLORS[class]
                    return string.format("|cff%02x%02x%02x", color.r*255, color.g*255, color.b*255)
                end
                break
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumPartyMembers() do
            local unit = "party"..i
            local name = UnitName(unit)
            if name == playerName then
                local _, class = UnitClass(unit)
                if class and RAID_CLASS_COLORS[class] then
                    local color = RAID_CLASS_COLORS[class]
                    return string.format("|cff%02x%02x%02x", color.r*255, color.g*255, color.b*255)
                end
                break
            end
        end
    end
    return "|cffffffff"
end

function auction:FormatColoredName(playerName)
    return self:GetClassColor(playerName) .. playerName
end

function auction:TableToString(t)
    local parts = {}
    for k, v in pairs(t or {}) do
        table.insert(parts, k.."="..v)
    end
    return "{"..table.concat(parts, ", ").."}"
end

-- ======================
-- Расчёт максимальной ставки с учётом офф-спек
-- ======================
function auction:GetMaxBidAmount(isOffspec)
    local currentEP = self.myEP or 0
    if isOffspec then
        return math.floor(currentEP * (self.offspecMultiplier or 0.5))
    end
    return currentEP
end

-- ======================
-- Воспроизведение звука перебитой ставки
-- ======================
function auction:PlayOutbidSound()
    if self.db and self.db.general and self.db.general.soundEnabled then
        local soundFile = self.db.general.soundFile or "Sound\\Interface\\RaidWarning.wav"
        PlaySoundFile(soundFile)
    end
end

-- ======================
-- Функции для работы с EP игроков (для тултипа)
-- ======================
function auction:GetPlayerEP(playerName, noCache)
    if not playerName then return 0 end
    
    if noCache then
        return self:FetchPlayerEP(playerName)
    end
    
    if self.playerEPCache[playerName] then
        return self.playerEPCache[playerName]
    end
    
    local ep = self:FetchPlayerEP(playerName)
    self.playerEPCache[playerName] = ep
    return ep
end

function auction:FetchPlayerEP(playerName)
    local ep = 0
    local epgpTable = EPGP or EPGP_Auction or CEPGP or EPGPCore
    
    if epgpTable and epgpTable.GetEPGP then
        local epVal, gp, main = epgpTable:GetEPGP(playerName)
        if epVal then
            if main then
                local mainEP, _, _ = epgpTable:GetEPGP(main)
                if mainEP then
                    ep = tonumber(mainEP) or 0
                else
                    ep = tonumber(epVal) or 0
                end
            else
                ep = tonumber(epVal) or 0
            end
        end
    elseif epgpTable and epgpTable.db and epgpTable.db.profile and epgpTable.db.profile.players then
        local playerData = epgpTable.db.profile.players[playerName]
        if playerData then
            if playerData.main then
                local mainData = epgpTable.db.profile.players[playerData.main]
                if mainData and mainData.EP then
                    ep = tonumber(mainData.EP) or 0
                else
                    ep = tonumber(playerData.EP) or 0
                end
            else
                ep = tonumber(playerData.EP) or 0
            end
        end
    end
    
    return ep
end

function auction:ClearPlayerEPCache()
    self.playerEPCache = {}
end

function auction:RefreshPlayerEPCache()
    if not self.rowFrames or not self.selectedBoss then return end
    
    local players = {}
    for idx, rowTable in ipairs(self.rowFrames) do
        local itemID = self.bosses[self.selectedBoss][idx]
        if itemID then
            local bidsForItem = self.bids[self.selectedBoss] and self.bids[self.selectedBoss][itemID] or {}
            for _, bid in ipairs(bidsForItem) do
                if bid and bid.player then
                    players[bid.player] = true
                end
            end
        end
    end
    
    for playerName, _ in pairs(players) do
        self.playerEPCache[playerName] = self:FetchPlayerEP(playerName)
    end
end

-- ======================
-- Функции для работы с логом ставок
-- ======================
function auction:SaveBidLog()
    EPBossAuctionBidLog = self.bidLog
end

function auction:LoadBidLog()
    if EPBossAuctionBidLog then
        self.bidLog = EPBossAuctionBidLog
    else
        self.bidLog = {}
    end
end

function auction:ClearBidLog()
    self.bidLog = {}
    self:SaveBidLog()
    if self.journalFrame and self.journalFrame:IsShown() then
        self:RefreshJournal()
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Журнал ставок очищен.")
end

-- ======================
-- Очистка устаревших уведомлений о перебитии
-- ======================
function auction:CleanOutbidNotified()
    for k, _ in pairs(self.outbidNotified) do
        self.outbidNotified[k] = nil
    end
end

-- ======================
-- Загрузка/сохранение настроек
-- ======================
function auction:LoadSettings()
    if EPBossAuctionSettings then
        self.db = EPBossAuctionSettings
    else
        self.db = self.defaults
    end
    self.debug = self.db.general.debug
    self.windowScale = self.db.window.scale
    self.minimapButtonPosition = self.db.minimap.position
    self:LoadBidLog()
    
    self.offspecMultiplier = self.db.general.offspecMultiplier or 0.5
    
    -- Загрузка очереди
    if self.db.tokenQueue then
        self.tokenQueueText = self.db.tokenQueue.text or ""
    else
        self.tokenQueueText = ""
    end
    
    self:Debug("Настройки загружены, офф-спек коэффициент: " .. (self.offspecMultiplier * 100) .. "%")
end

function auction:SaveSettings()
    EPBossAuctionSettings = self.db
    if not self.db.tokenQueue then self.db.tokenQueue = {} end
    self.db.tokenQueue.text = self.tokenQueueText
    self:SaveBidLog()
    self:Debug("Настройки сохранены")
end

function auction:SaveTokenQueue()
    if not self.db.tokenQueue then self.db.tokenQueue = {} end
    self.db.tokenQueue.text = self.tokenQueueText
    self:SaveSettings()
end

function auction:ApplySettings()
    self.debug = self.db.general.debug
    if self.frame then
        self.frame:SetScale(self.db.window.scale)
        self.frame:SetSize(self.db.window.width, self.db.window.height)
        self.frame:SetAlpha(self.db.window.alpha)
        self:UpdateScrollFrameSize()
        if self.selectedBoss then
            self:RefreshTable()
        end
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
    if self.lockCheckbox then
        self.lockCheckbox:SetChecked(self.bidsLocked)
        if not self:IsLootMaster() then
            self.lockCheckbox:Disable()
            self.lockCheckbox:SetAlpha(0.5)
        else
            self.lockCheckbox:Enable()
            self.lockCheckbox:SetAlpha(1.0)
        end
    end
    if self.bidBox then
        if self.bidsLocked then
            self.bidBox:Disable()
            self.bidBox:SetAlpha(0.5)
        else
            self.bidBox:Enable()
            self.bidBox:SetAlpha(1.0)
        end
    end
    if self.selectedBoss then
        self:RefreshTable()
    end
    self:Debug("Настройки применены")
end

-- ======================
-- Сохранение данных (ставки, версии и т.д.)
-- ======================
function auction:SaveData()
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
    self.lastSaveTime = GetTime()
    local bidCount = 0
    for bossName, bossBids in pairs(self.bids) do
        for itemID, bidsForItem in pairs(bossBids) do
            bidCount = bidCount + #bidsForItem
        end
    end
    self:Debug("=== СОХРАНЕНИЕ ===")
    self:Debug("Всего ставок: "..bidCount)
    self:Debug("Версии боссов: "..self:TableToString(self.dataVersions))
    self:Debug("Масштаб окна: "..self.windowScale)
    self:Debug("Позиция кнопки: угол "..(self.minimapButtonPosition.angle or 0))
    self:Debug("Блокировка ставок: "..tostring(self.bidsLocked))
    self:Debug("Офф-спек коэффициент: "..(self.offspecMultiplier * 100).."%")
    self:Debug("==================")
end

-- ======================
-- Автосохранение
-- ======================
function auction:InitAutoSave()
    if self.saveTimer then
        self.saveTimer:SetScript("OnUpdate", nil)
        self.saveTimer:Hide()
        self.saveTimer:SetParent(nil)
    end
    local frame = CreateFrame("Frame")
    local elapsed = 0
    local SAVE_INTERVAL = 10
    frame:SetScript("OnUpdate", function(self, e)
        elapsed = elapsed + e
        if elapsed >= SAVE_INTERVAL then
            elapsed = 0
            auction:SaveData()
        end
    end)
    self.saveTimer = frame
    self:Debug("Автосохранение запущено (интервал "..SAVE_INTERVAL.." сек)")
end

-- ======================
-- Масштабирование
-- ======================
function auction:SetWindowScale(scale)
    scale = math.max(self.minScale, math.min(self.maxScale, scale))
    if self.frame then
        self.windowScale = scale
        self.frame:SetScale(scale)
        self:SaveScale()
        self:Debug("Масштаб окна изменен на: "..scale)
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

function auction:SaveScale()
    EPBossAuctionSavedScale = self.windowScale
end

function auction:LoadScale()
    if EPBossAuctionSavedScale then
        self.windowScale = EPBossAuctionSavedScale
        if self.frame then
            self.frame:SetScale(self.windowScale)
        end
    end
end

-- ======================
-- Loot Master
-- ======================
function auction:IsLootMaster()
    local method, partyIndex, raidIndex = GetLootMethod()
    if method ~= "master" then return false end
    if raidIndex then
        local name = GetRaidRosterInfo(raidIndex)
        return name == UnitName("player")
    elseif partyIndex then
        return true
    end
    return false
end

function auction:ResetVersionsForNewLM()
    self:Debug("Сброс версий для нового лутера")
    self.lastVersions = {}
    if IsInRaid() or IsInGroup() then
        self:RequestDataFromLM()
    end
end

-- ======================
-- Принудительное сохранение
-- ======================
function auction:ForceSave()
    self:Debug("Принудительное сохранение")
    self:SaveData()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Данные сохранены")
end

-- ======================
-- Обновление размеров скролл-фрейма
-- ======================
function auction:UpdateScrollFrameSize()
    if not self.frame or not self.scrollFrame then return end
    
    local leftOffset = 16
    local topOffset = 102
    local rightOffset = 30
    local bottomOffset = 80
    
    self.scrollFrame:ClearAllPoints()
    self.scrollFrame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", leftOffset, -topOffset)
    self.scrollFrame:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -rightOffset, bottomOffset)
    
    if self.scrollBG then
        self.scrollBG:ClearAllPoints()
        self.scrollBG:SetPoint("TOPLEFT", self.frame, "TOPLEFT", leftOffset, -topOffset)
        self.scrollBG:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -rightOffset, bottomOffset)
    end
    
    if self.header then
        self.header:ClearAllPoints()
        self.header:SetPoint("TOPLEFT", self.frame, "TOPLEFT", leftOffset, -80)
        self.header:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -rightOffset, -80)
    end
    
    self.db.window.width = self.frame:GetWidth()
    self.db.window.height = self.frame:GetHeight()
end
