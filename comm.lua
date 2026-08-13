local auction = EPBossAuction

local function GetSafeItemInfo(itemID)
    if not itemID then return "неизвестный предмет" end
    local name = GetItemInfo(itemID)
    if name and name ~= "" then return name end
    return "предмет "..tostring(itemID)
end

function auction:SendToLootMaster(message)
    if not message or message == "" then return false end

    local playerName = UnitName("player")
    if self.lastLM and self.lastLM ~= "" and self.lastLM ~= playerName then
        SendAddonMessage(self.prefix, message, "WHISPER", self.lastLM)
        return true
    end

    SendAddonMessage(self.prefix, message, "RAID")
    return false
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
                    self:RequestRefresh()
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
                    self:SendSyncImmediate(bossName, itemID)
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
    self:QueueSync(bossName, itemID)
end

function auction:QueueSync(bossName, itemID)
    self.syncQueue = self.syncQueue or {}
    local key = bossName .. ":" .. itemID
    self.syncQueue[key] = true
    if not self.syncTimer then
        self.syncTimer = self:ScheduleTimer(function()
            self:FlushSyncQueue()
        end, 0.2)
    end
end

function auction:FlushSyncQueue()
    for key in pairs(self.syncQueue) do
        local bossName, itemID = key:match("([^:]+):(.+)")
        if bossName and itemID then
            self:SendSyncImmediate(bossName, tonumber(itemID))
        end
    end
    wipe(self.syncQueue)
    self.syncTimer = nil
end

function auction:SendSyncImmediate(bossName, itemID)
    if not bossName or not itemID then return end
    local bidsForItem = self.bids[bossName] and self.bids[bossName][itemID]
    if not bidsForItem then 
        self:Debug("Нет ставок для отправки: "..bossName.." "..itemID)
        return 
    end
    local currentVersion = self:IncrementDataVersion(bossName, itemID)
    local bidStrs = {}
    for _, bid in ipairs(bidsForItem) do
        local offspecFlag = bid.isOffspec and ":1" or ":0"
        table.insert(bidStrs, bid.player..":"..bid.amount..offspecFlag)
    end
    local itemName = GetSafeItemInfo(itemID)
    local message = "SYNC;"..bossName..";"..itemID..";"..table.concat(bidStrs, ",")..";"..currentVersion
    self:Debug("Отправка SYNC для босса "..bossName..": "..itemName.." ("..#bidsForItem.." ставок), версия "..currentVersion)
    SendAddonMessage(self.prefix, message, "RAID")
    -- Сохранение данных теперь только по таймеру, не здесь
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
            local currentVersion = self:GetDataVersion(bossName, itemID)
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
    self:SendToLootMaster("LM_REQUEST")
    self:SendToLootMaster("CHECK_VERSION")
    local bossParam = ""
    if self.selectedBoss then
        bossParam = ";"..self.selectedBoss
    end
    self:SendToLootMaster("HELLO"..bossParam)
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
        self:UpdateSortedBids(bossName, itemID)
        self:UpdateBidCaches(bossName, itemID)
        self:QueueSync(bossName, itemID)
        if bossName == self.selectedBoss then
            if not self:RefreshRowForItem(itemID) then
                self:RequestRefresh()
            end
        end
        self:CheckIfOutbid(bossName, itemID)
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
    self:UpdateSortedBids(bossName, itemID)
    self:UpdateBidCaches(bossName, itemID)
    self:QueueSync(bossName, itemID)
    if bossName == self.selectedBoss then
        if not self:RefreshRowForItem(itemID) then
            self:RequestRefresh()
        end
    end
    self:CheckIfOutbid(bossName, itemID)
    SendAddonMessage(self.prefix, "BIDOK;"..amount..";"..playerName..";"..bossName..";"..itemID, "WHISPER", sender)
    self:Debug("Ставка обработана, отправлен SYNC")
end

function auction:Handle_SYNC(rest, sender)
    local parts = { strsplit(";", rest) }
    local bossName = parts[1]
    local itemID = tonumber(parts[2])
    local bidsPart = parts[3] or ""
    local version = tonumber(parts[4]) or 0
    if not bossName or not itemID then
        self:Debug("Ошибка парсинга SYNC: "..rest)
        return 
    end
    self:Debug("Получен SYNC для босса "..bossName..": "..itemID.." версия "..version.." от "..sender)
    self.receivedSync = true
    local isLootMaster = self:IsLootMaster()
    local senderIsLM = (sender == self.lastLM)
    if isLootMaster then
        self:Debug("Я лутер, игнорирую SYNC от "..sender)
        return
    elseif not senderIsLM then
        self:Debug("Игнорируем SYNC от не-Loot Master: "..tostring(sender).." (ожидался "..tostring(self.lastLM)..")")
        return
    end
    local lastVersion = self:GetLastVersion(bossName, itemID)
    if version > lastVersion or senderIsLM then
        if version <= lastVersion and senderIsLM then
            self:Debug("Принимаем данные от лутера с версией "..version.." (моя версия "..lastVersion..")")
        end
        self:SetLastVersion(bossName, itemID, version)
        self.receivedItems[itemID] = true
        self.bids[bossName] = self.bids[bossName] or {}
        local oldBids = self.bids[bossName][itemID] or {}
        local newBids = {}
        if bidsPart and bidsPart ~= "" then
            for bidStr in bidsPart:gmatch("([^,]+)") do
                local p = { strsplit(":", bidStr) }
                local player = p[1]
                local amount = tonumber(p[2])
                local isOffspec = (p[3] == "1")
                if player and amount then
                    table.insert(newBids, {player = player, amount = amount, isOffspec = isOffspec})
                end
            end
        end
        self.bids[bossName][itemID] = newBids
        self:UpdateSortedBids(bossName, itemID)
        self:UpdateBidCaches(bossName, itemID)
        if self.selectedBoss == bossName then
            if not self:RefreshRowForItem(itemID) then
                self:RequestRefresh()
            end
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
        if not self:SendAllBidsForBoss(requestedBoss, playerName) then
            SendAddonMessage(self.prefix, "END;"..requestedBoss, "WHISPER", playerName)
        end
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
        self.lastLM = sender
        local bossParam = ""
        if self.selectedBoss then
            bossParam = ";"..self.selectedBoss
        end
        SendAddonMessage(self.prefix, "HELLO"..bossParam, "WHISPER", sender)
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
    self.lastLM = lmName ~= "" and lmName or sender
    self:Debug("Лутер найден: "..lmName)
end

function auction:Handle_CHECK_VERSION(rest, sender)
    self:Debug("Получен CHECK_VERSION от "..sender)
    if self:IsLootMaster() then
        local versionMsg = "VERSIONS"
        for versionKey, version in pairs(self.dataVersions) do
            versionMsg = versionMsg .. ";" .. versionKey .. ":" .. version
        end
        SendAddonMessage(self.prefix, versionMsg, "WHISPER", sender)
        self:Debug("Отправлены версии: "..versionMsg)
    end
end

function auction:Handle_VERSIONS(rest, sender)
    self:Debug("Получены версии от лутера: "..rest)
    local needUpdate = false
    for bossVersion in rest:gmatch("([^;]+)") do
        local bossName, itemID, version = bossVersion:match("^(.*):(%d+):(%d+)$")
        if bossName and itemID and version then
            itemID = tonumber(itemID)
            version = tonumber(version)
            local myVersion = self:GetLastVersion(bossName, itemID)
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
        self:SendToLootMaster("HELLO"..bossParam)
    end
end

function auction:Handle_BIDOK(rest, sender)
    local amount, playerName, bossName, itemID = rest:match("([^;]+);([^;]+);([^;]+);([^;]+)")
    if not amount then amount = rest end
    if not self:IsLootMaster() then
        --DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Ставка "..amount.." от "..playerName.." принята")
    end
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
    if self.bosses[bossName] then
        for _, itemID in ipairs(self.bosses[bossName]) do
            self:UpdateSortedBids(bossName, itemID)
            self:UpdateBidCaches(bossName, itemID)
            local key = self:GetVersionKey(bossName, itemID)
            if key then
                self.lastVersions[key] = nil
                if not self:IsLootMaster() then
                    self.dataVersions[key] = nil
                end
            end
        end
    end
    if self.selectedBoss == bossName then
        self:RequestRefresh()
    end
    self:RequestSaveData()
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
        auction:SaveSettings()
        auction:Debug("Получен новый коэффициент офф-спек: " .. (multiplier * 100) .. "%")
        if auction.myEP > 0 then
            auction:UpdateMaxBidDisplay()
        end
    end
end

function auction:Handle_LOCKED(rest, sender)
    if not self:IsLootMaster() then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[EPBA]|r Ставки заблокированы лутером!")
    end
end

-- ======================
-- Проверка, перебита ли ставка текущего игрока
-- ======================
function auction:CheckIfOutbid(bossName, itemID)
    local playerName = UnitName("player")
    if not playerName then return end
    
    local key = bossName .. ":" .. itemID
    local maxBid = self.maxBidCache[key] or 0
    local myBid = self.myBidCache[key] or 0

    if myBid == 0 or myBid >= maxBid then
        self.outbidNotified[key] = nil
        return
    end

    self.outbidThrottle = self.outbidThrottle or {}
    local now = GetTime()
    if self.outbidThrottle[key] and now - self.outbidThrottle[key] < 2 then
        return
    end
    self.outbidThrottle[key] = now

    if not self.outbidNotified[key] then
        self.outbidNotified[key] = true
        local itemName = self:GetCachedItemName(itemID)
        local topPlayer = "???"
        local bids = self.bids[bossName] and self.bids[bossName][itemID]
        if bids then
            for _, bid in ipairs(bids) do
                if bid.amount == maxBid then
                    topPlayer = bid.player
                    break
                end
            end
        end
        local message = string.format("Вашу ставку на %s перебил %s (%s EP)!", itemName, topPlayer, self:FormatNumber(maxBid))
        UIErrorsFrame:AddMessage(message, 1.0, 0.5, 0.0, 5)
        self:PlayOutbidSound()
    end
end
