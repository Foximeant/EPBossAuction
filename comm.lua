local auction = EPBossAuction

local function GetSafeItemInfo(itemID)
    if not itemID then return "неизвестный предмет" end
    local name = GetItemInfo(itemID)
    if name and name ~= "" then return name end
    return "предмет "..tostring(itemID)
end

function auction:HandleWorldEnter()
    self:Debug("=== ОБРАБОТКА ВХОДА В МИР ===")
    self:Debug("fullyLoaded = "..tostring(self.fullyLoaded))
    self:Debug("Текущий игрок: "..UnitName("player"))
    local bidCount = 0
    for bossName, bossBids in pairs(self.bids) do
        for itemID, bidsForItem in pairs(bossBids) do
            bidCount = bidCount + #bidsForItem
        end
    end
    self:Debug("Текущие ставки в памяти: "..bidCount)
    self:ScheduleTimer(function()
        self:Debug("=== ТАЙМЕР СРАБОТАЛ ===")
        if self:IsLootMaster() then
            self:Debug("Я ЛУТЕР")
            local bidCount = 0
            for bossName, bossBids in pairs(self.bids) do
                for itemID, bidsForItem in pairs(bossBids) do
                    bidCount = bidCount + #bidsForItem
                end
            end
            self:Debug("Ставок в памяти: "..bidCount)
            if bidCount > 0 then
                if self.selectedBoss then
                    self:Debug("Восстанавливаем выбранного босса: "..self.selectedBoss)
                    if self.bossDropdown then
                        UIDropDownMenu_SetText(self.bossDropdown, self.selectedBoss)
                    end
                    self:RefreshTable()
                end
                self:ScheduleTimer(function()
                    self:SyncAllToRaid()
                end, 3)
            else
                self:Debug("НЕТ СТАВОК, просто сообщаем что мы лутер")
                SendAddonMessage(self.prefix, "LM", "RAID")
            end
        else
            self:Debug("Я НЕ ЛУТЕР")
            if IsInRaid() or IsInGroup() then
                self:RequestDataFromLM()
            end
        end
        self:UpdateMyEP()
    end, 2)
    self:Debug("===============================")
end

function auction:SyncAllToRaid()
    if not self:IsLootMaster() then 
        self:Debug("Не лутер, синхронизация отменена")
        return 
    end
    SendAddonMessage(self.prefix, "LM", "RAID")
    local syncCount = 0
    local totalItems = 0
    for bossName, bossBids in pairs(self.bids) do
        for itemID, bidsForItem in pairs(bossBids) do
            if #bidsForItem > 0 then
                totalItems = totalItems + 1
            end
        end
    end
    if totalItems == 0 then
        self:Debug("Нет ставок для синхронизации")
        return
    end
    self:Debug("Начинаем синхронизацию "..totalItems.." предметов с рейдом")
    local delay = 0
    for bossName, bossBids in pairs(self.bids) do
        for itemID, bidsForItem in pairs(bossBids) do
            if #bidsForItem > 0 then
                self:ScheduleTimer(function()
                    self:SendSync(bossName, itemID, true)
                end, delay)
                delay = delay + 0.3
                syncCount = syncCount + 1
            end
        end
    end
    if syncCount > 0 then
        self:Debug("Запланирована отправка "..syncCount.." предметов")
        self:ScheduleTimer(function()
            SendAddonMessage(self.prefix, "SYNC_COMPLETE", "RAID")
        end, delay + 1)
    end
end

function auction:SendSync(bossName, itemID, force)
    if not bossName or not itemID then return end
    local bidsForItem = self.bids[bossName] and self.bids[bossName][itemID]
    if not bidsForItem then 
        self:Debug("Нет ставок для отправки: "..bossName.." "..itemID)
        return 
    end
    self.dataVersions[bossName] = (self.dataVersions[bossName] or 0) + 1
    local currentVersion = self.dataVersions[bossName]
    local bidStrs = {}
    for _, bid in ipairs(bidsForItem) do
        local offspecFlag = bid.isOffspec and ":1" or ":0"
        table.insert(bidStrs, bid.player..":"..bid.amount..offspecFlag)
    end
    local itemName = GetSafeItemInfo(itemID)
    local message = "SYNC;"..bossName..";"..itemID..";"..table.concat(bidStrs, ",")..";"..currentVersion
    self:Debug("Отправка SYNC для босса "..bossName..": "..itemName.." ("..#bidsForItem.." ставок), версия "..currentVersion)
    SendAddonMessage(self.prefix, message, "RAID")
    self:SaveData()
end

function auction:SendAllBidsForBoss(bossName, targetPlayer)
    if not bossName or not targetPlayer then return false end
    local bossBids = self.bids[bossName]
    if not bossBids then 
        self:Debug("Нет ставок для босса "..bossName.." игроку "..targetPlayer)
        return false
    end
    local sentCount = 0
    self:Debug("Отправка ставок для "..bossName.." игроку "..targetPlayer)
    for itemID, bidsForItem in pairs(bossBids) do
        if #bidsForItem > 0 then
            local bidStrs = {}
            for _, bid in ipairs(bidsForItem) do
                local offspecFlag = bid.isOffspec and ":1" or ":0"
                table.insert(bidStrs, bid.player..":"..bid.amount..offspecFlag)
            end
            local currentVersion = self.dataVersions[bossName] or 0
            local message = "SYNC;"..bossName..";"..itemID..";"..table.concat(bidStrs, ",")..";"..currentVersion
            SendAddonMessage(self.prefix, message, "WHISPER", targetPlayer)
            sentCount = sentCount + 1
            self:Debug("Отправлен предмет "..itemID.." ("..#bidsForItem.." ставок)")
        end
    end
    if sentCount > 0 then
        SendAddonMessage(self.prefix, "SYNC_COMPLETE", "WHISPER", targetPlayer)
        return true
    end
    return false
end

function auction:RequestDataFromLM()
    if self:IsLootMaster() then 
        self:Debug("Я лутер, запрос игнорируется")
        return 
    end
    self:Debug("Запрос данных у лутера")
    self.receivedItems = {}
    self.receivedSync = false
    self.receivedAck = false
    SendAddonMessage(self.prefix, "LM_REQUEST", "RAID")
    SendAddonMessage(self.prefix, "CHECK_VERSION", "RAID")
    local bossParam = ""
    if self.selectedBoss then
        bossParam = ";"..self.selectedBoss
    end
    SendAddonMessage(self.prefix, "HELLO"..bossParam, "RAID")
    self:ScheduleTimer(function()
        if not self.receivedSync and not self.receivedAck then
            self:Debug("Не удалось получить данные от лутера")
        else
            self:Debug("Данные успешно получены")
        end
    end, 8)
end

-- ======================
-- Обработчики сообщений
-- ======================
function auction:HandleMessage(msg, sender)
    if not msg or msg == "" then return end
    local cmd, rest = msg:match("^([%w_]+);?(.*)")
    if not cmd then
        self:Debug("Не удалось определить команду из: "..msg)
        return
    end
    local handler = self["Handle_"..cmd]
    if handler then
        handler(self, rest, sender)
    else
        self:Debug("Неизвестная команда: "..cmd)
    end
end

function auction:Handle_BID(rest, sender)
    if not self:IsLootMaster() then 
        self:Debug("Игнорируем BID, я не лутер")
        return 
    end
    if self.bidsLocked then
        self:Debug("Блокировка активна, ставка отклонена")
        SendAddonMessage(self.prefix, "LOCKED", "WHISPER", sender)
        return
    end
    local bossName, itemID, playerName, amount, isOffspec = rest:match("([^;]+);([^;]+);([^;]+);([^;]+);(.*)")
    if not (bossName and itemID and playerName and amount) then 
        bossName, itemID, playerName, amount = rest:match("([^;]+);([^;]+);([^;]+);([^;]+)")
        isOffspec = "false"
    end
    if not (bossName and itemID and playerName and amount) then 
        self:Debug("Ошибка парсинга BID: "..rest)
        return 
    end
    itemID = tonumber(itemID)
    amount = tonumber(amount)
    local isOffspecBool = (isOffspec == "true")
    
    self:Debug("Обработка BID: "..playerName.." "..amount.." на "..bossName.." "..itemID.." (офф-спек: "..tostring(isOffspecBool)..")")
    if amount == 0 then
        if self.bids[bossName] and self.bids[bossName][itemID] then
            for i, bid in ipairs(self.bids[bossName][itemID]) do
                if bid.player == playerName then
                    table.remove(self.bids[bossName][itemID], i)
                    break
                end
            end
        end
        self:RefreshTable()
        self:SendSync(bossName, itemID)
        self:CheckIfOutbid(bossName, itemID)
        self:AddBidLogEntry(playerName, 0, itemID, bossName, isOffspecBool)
        self:Debug("Отказ от ставки обработан")
        return
    end
    if amount < self.db.general.minBid then
        self:Debug("Ставка меньше минимальной ("..self.db.general.minBid.."), игнорируем")
        SendAddonMessage(self.prefix, "TOOLOW;"..amount..";"..self.db.general.minBid, "WHISPER", sender)
        return
    end
    self.bids[bossName] = self.bids[bossName] or {}
    self.bids[bossName][itemID] = self.bids[bossName][itemID] or {}
    local existingBid
    for _, bid in ipairs(self.bids[bossName][itemID]) do
        if bid.player == playerName then
            existingBid = bid
            break
        end
    end
    if existingBid then
        existingBid.amount = amount
        existingBid.isOffspec = isOffspecBool
    else
        table.insert(self.bids[bossName][itemID], {player = playerName, amount = amount, isOffspec = isOffspecBool})
    end
    self:RefreshTable()
    self:SendSync(bossName, itemID)
    self:CheckIfOutbid(bossName, itemID)
    self:AddBidLogEntry(playerName, amount, itemID, bossName, isOffspecBool)
    SendAddonMessage(self.prefix, "BIDOK;"..amount..";"..playerName..";"..bossName..";"..itemID, "RAID")
    self:Debug("Ставка обработана, отправлен SYNC")
end

function auction:Handle_SYNC(rest, sender)
    local bossName, itemID, bidsPart, version = rest:match("([^;]+);([^;]+);(.*);(%d+)")
    if not bossName or not itemID then
        bossName, itemID, bidsPart = rest:match("([^;]+);([^;]+);(.*)")
        version = 0
    end
    if not bossName or not itemID then
        self:Debug("Ошибка парсинга SYNC: "..rest)
        return 
    end
    itemID = tonumber(itemID)
    version = tonumber(version) or 0
    self:Debug("Получен SYNC для босса "..bossName..": "..itemID.." версия "..version.." от "..sender)
    self.receivedSync = true
    local isLootMaster = self:IsLootMaster()
    local senderIsLM = false
    if isLootMaster then
        self:Debug("Я лутер, игнорирую SYNC от "..sender)
        return
    else
        senderIsLM = true
    end
    local lastVersion = self.lastVersions[bossName] or 0
    if version > lastVersion or senderIsLM then
        if version <= lastVersion and senderIsLM then
            self:Debug("Принимаем данные от лутера с версией "..version.." (моя версия "..lastVersion..")")
        end
        if version > 0 then
            self.lastVersions[bossName] = version
        end
        self.receivedItems[itemID] = true
        self.bids[bossName] = self.bids[bossName] or {}
        self.bids[bossName][itemID] = {}
        if bidsPart and bidsPart ~= "" then
            local newBids = {}
            for bidStr in bidsPart:gmatch("([^,]+)") do
                local parts = {}
                for part in string.gmatch(bidStr, "[^:]+") do
                    table.insert(parts, part)
                end
                if #parts >= 2 then
                    local player = parts[1]
                    local amount = tonumber(parts[2])
                    local isOffspec = (#parts >= 3 and parts[3] == "1")
                    if player and amount then
                        table.insert(newBids, {player = player, amount = amount, isOffspec = isOffspec})
                    end
                end
            end
            self.bids[bossName][itemID] = newBids
        end
        if self.selectedBoss == bossName then
            self:RefreshTable()
        end
        self:CheckIfOutbid(bossName, itemID)
        self:Debug("SYNC для босса "..bossName.." обработан, ставок: "..#(self.bids[bossName][itemID] or {}))
    else
        self:Debug("Игнорируем SYNC с версией "..version.." <= "..lastVersion)
    end
end

function auction:Handle_HELLO(rest, sender)
    if rest == "_ACK" then
        self:Debug("Получено HELLO_ACK, обрабатываем как подтверждение")
        self.receivedAck = true
        return
    end
    local requestedBoss = rest
    if requestedBoss == "" then requestedBoss = nil end
    local playerName = sender
    self:Debug("Получен HELLO от "..playerName.." для босса "..(requestedBoss or "всех"))
    if not self:IsLootMaster() then 
        self:Debug("Игнорируем HELLO, я не лутер")
        return 
    end
    if requestedBoss then
        self:SendAllBidsForBoss(requestedBoss, playerName)
    else
        if self.selectedBoss then
            self:SendAllBidsForBoss(self.selectedBoss, playerName)
        else
            local sentAny = false
            for bossName, _ in pairs(self.bids) do
                if self:SendAllBidsForBoss(bossName, playerName) then
                    sentAny = true
                end
            end
            if not sentAny then
                self:Debug("Нет данных для отправки "..playerName)
            end
        end
    end
    SendAddonMessage(self.prefix, "LOCK;"..tostring(self.bidsLocked), "WHISPER", playerName)
    SendAddonMessage(self.prefix, "HELLO_ACK", "WHISPER", playerName)
end

function auction:Handle_HELLO_ACK(rest, sender)
    self.receivedAck = true
    self:Debug("Получено подтверждение HELLO_ACK от "..sender)
end

function auction:Handle_LM(rest, sender)
    self:Debug("Получено LM от "..sender)
    if not self:IsLootMaster() then
        local bossParam = ""
        if self.selectedBoss then
            bossParam = ";"..self.selectedBoss
        end
        SendAddonMessage(self.prefix, "HELLO"..bossParam, "RAID")
    end
end

function auction:Handle_LM_REQUEST(rest, sender)
    self:Debug("Получен LM_REQUEST от "..sender)
    if self:IsLootMaster() then
        SendAddonMessage(self.prefix, "LM_RESPONSE;"..UnitName("player"), "WHISPER", sender)
        self:Debug("Отправлен LM_RESPONSE")
    end
end

function auction:Handle_LM_RESPONSE(rest, sender)
    local lmName = rest
    self:Debug("Лутер найден: "..lmName)
end

function auction:Handle_CHECK_VERSION(rest, sender)
    self:Debug("Получен CHECK_VERSION от "..sender)
    if self:IsLootMaster() then
        local versionMsg = "VERSIONS"
        for bossName, version in pairs(self.dataVersions) do
            versionMsg = versionMsg .. ";" .. bossName .. ":" .. version
        end
        SendAddonMessage(self.prefix, versionMsg, "WHISPER", sender)
        self:Debug("Отправлены версии: "..versionMsg)
    end
end

function auction:Handle_VERSIONS(rest, sender)
    self:Debug("Получены версии от лутера: "..rest)
    local needUpdate = false
    local bossVersions = {}
    for bossVersion in rest:gmatch("([^;]+)") do
        local bossName, version = bossVersion:match("([^:]+):(%d+)")
        if bossName and version then
            version = tonumber(version)
            bossVersions[bossName] = version
            local myVersion = self.lastVersions[bossName] or 0
            if version > myVersion then
                needUpdate = true
                self:Debug("Босс "..bossName..": версия лутера "..version.." > моей "..myVersion)
            end
        end
    end
    if needUpdate then
        local bossParam = ""
        if self.selectedBoss then
            bossParam = ";"..self.selectedBoss
        end
        SendAddonMessage(self.prefix, "HELLO"..bossParam, "RAID")
    end
end

function auction:Handle_BIDOK(rest, sender)
    local amount, playerName, bossName, itemID = rest:match("([^;]+);([^;]+);([^;]+);([^;]+)")
    if not amount then amount = rest end
    if bossName and itemID and self:IsLootMaster() then
        auction:AddBidLogEntry(playerName, tonumber(amount), tonumber(itemID), bossName)
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Ставка "..amount.." от "..playerName.." принята")
    if auction.bidBox then
        auction.bidBox:SetText("")
    end
end

function auction:Handle_SYNC_COMPLETE(rest, sender)
    self.receivedSync = true
    self:Debug("Синхронизация завершена")
end

function auction:Handle_END(rest, sender)
    local bossName = rest
    self.bids[bossName] = {}
    self.dataVersions[bossName] = (self.dataVersions[bossName] or 0) + 1
    if self.selectedBoss == bossName then
        self:RefreshTable()
    end
    self:SaveData()
end

function auction:Handle_LOCK(rest, sender)
    self:Debug("LOCK получен, rest='"..tostring(rest).."'")
    local cleanRest = rest:gsub("%s+", "")
    local state = (cleanRest == "true")
    self:Debug("state="..tostring(state))
    if self:IsLootMaster() then
        self:Debug("Я лутер, игнорирую свой LOCK")
        return
    end
    self:SetBidsLocked(state)
end

function auction:Handle_OFFSPEC_MULT(rest, sender)
    local multiplier = tonumber(rest)
    if multiplier then
        auction.offspecMultiplier = multiplier
        auction.db.general.offspecMultiplier = multiplier
        auction:Debug("Получен новый коэффициент офф-спек: " .. (multiplier * 100) .. "%")
        if auction.myEP > 0 then
            auction:UpdateMaxBidDisplay()
        end
    end
end

function auction:Handle_LOCKED(rest, sender)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[EPBA]|r Ставки заблокированы лутером!")
end

function auction:Handle_QUEUE_REQUEST(rest, sender)
    if self:IsLootMaster() then
        self:SendQueueToRaid()
    end
end

function auction:Handle_QUEUE_TEXT(rest, sender)
    DEFAULT_CHAT_FRAME:AddMessage("|cff888888[DEBUG]|r QUEUE_TEXT received, length=" .. #rest)
    self.tokenQueueText = rest
    self:SaveTokenQueue()
    if self.queueEditBox then
        self.queueEditBox:SetText(rest)
        DEFAULT_CHAT_FRAME:AddMessage("|cff888888[DEBUG]|r queueEditBox updated")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff888888[DEBUG]|r queueEditBox is nil, text saved to tokenQueueText")
    end
    if rest == "" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Очередь очищена лутером.")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Очередь обновлена лутером.")
    end
end

-- ======================
-- Проверка, перебита ли ставка текущего игрока
-- ======================
function auction:CheckIfOutbid(bossName, itemID)
    local playerName = UnitName("player")
    if not playerName then return end
    
    local bidsForItem = self.bids[bossName] and self.bids[bossName][itemID]
    if not bidsForItem then return end

    local myBid
    for _, bid in ipairs(bidsForItem) do
        if bid.player == playerName then
            myBid = bid.amount
            break
        end
    end
    if not myBid then return end

    local maxBid = 0
    local topPlayer
    for _, bid in ipairs(bidsForItem) do
        if bid.amount > maxBid then
            maxBid = bid.amount
            topPlayer = bid.player
        end
    end

    local key = bossName .. ":" .. itemID
    if myBid < maxBid then
        if not self.outbidNotified[key] then
            self.outbidNotified[key] = true
            local itemName = GetSafeItemInfo(itemID)
            local message = string.format("Вашу ставку на %s перебил %s (%s EP)!", itemName, topPlayer, self:FormatNumber(maxBid))
            UIErrorsFrame:AddMessage(message, 1.0, 0.5, 0.0, 5)
            self:PlayOutbidSound()
            if self:IsLootMaster() then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[EPBA]|r " .. message)
            end
        end
    else
        self.outbidNotified[key] = nil
    end
end