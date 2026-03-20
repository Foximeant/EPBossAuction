local auction = EPBossAuction

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
                --DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Вы лутер. Восстановлено "..bidCount.." ставок")
                if self.selectedBoss then
                    self:Debug("Восстанавливаем выбранного босса: "..self.selectedBoss)
                    if self.bossDropdown then
                        UIDropDownMenu_SetText(self.bossDropdown, self.selectedBoss)
                    end
                    self:RefreshTable()
                end
                self:ScheduleTimer(function()
                    self:SyncAllToRaid()
                    --DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Данные разосланы в рейд")
                end, 3)
            else
                self:Debug("НЕТ СТАВОК, просто сообщаем что мы лутер")
                --DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Вы лутер. Нет сохраненных ставок")
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
    --DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Синхронизация "..totalItems.." предметов с рейдом...")
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
            --DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Синхронизация завершена")
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
        table.insert(bidStrs, bid.player..":"..bid.amount)
    end
    local itemName = GetItemInfo(itemID) or ("item:"..itemID)
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
                table.insert(bidStrs, bid.player..":"..bid.amount)
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
    --DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Запрос данных у лутера...")
    self:ScheduleTimer(function()
        if not self.receivedSync and not self.receivedAck then
            --DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[EPBA]|r Нет ответа от лутера. Возможно, лутер не в рейде или нет новых ставок?")
        else
            self:Debug("Данные успешно получены")
        end
    end, 8)
end

-- ======================
-- Обработчик сообщений
-- ======================
function auction:HandleMessage(msg, sender)
    if not msg or msg == "" then return end
    if not msg:find(";") and msg ~= "LM" and msg ~= "SYNC_COMPLETE" then
        self:Debug("Странное сообщение без разделителя: "..msg)
        return
    end
    local cmd, rest = msg:match("^(%w+);?(.*)")
    if not cmd then 
        self:Debug("Не удалось определить команду из: "..msg)
        return 
    end
    self:Debug("Получено сообщение: "..cmd.." от "..sender.." ("..(rest or "")..")")

    if cmd == "BID" then
        self:HandleBidMessage(rest, sender)
    elseif cmd == "SYNC" then
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
                for bidStr in bidsPart:gmatch("([^,]+)") do
                    local player, amount = bidStr:match("([^:]+):([^:]+)")
                    if player and amount then
                        table.insert(self.bids[bossName][itemID], {
                            player = player,
                            amount = tonumber(amount)
                        })
                    end
                end
            end
            if self.selectedBoss == bossName then
                self:RefreshTable()
            end
            self:CheckIfOutbid(bossName, itemID)
            self:Debug("SYNC для босса "..bossName.." обработан, ставок: "..#(self.bids[bossName][itemID] or {}))
        else
            self:Debug("Игнорируем SYNC с версией "..version.." <= "..lastVersion)
        end
    elseif cmd == "HELLO" then
        if rest == "_ACK" then
            self:Debug("Получено HELLO_ACK, обрабатываем как подтверждение")
            self.receivedAck = true
            --DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Данные синхронизированы с лутером")
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
        -- Отправляем состояние блокировки
        SendAddonMessage(self.prefix, "LOCK;"..tostring(self.bidsLocked), "WHISPER", playerName)
        SendAddonMessage(self.prefix, "HELLO_ACK", "WHISPER", playerName)
    elseif cmd == "HELLO_ACK" then
        self.receivedAck = true
        --DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Данные синхронизированы с лутером")
        self:Debug("Получено подтверждение HELLO_ACK от "..sender)
    elseif cmd == "LM" then
        self:Debug("Получено LM от "..sender)
        if not self:IsLootMaster() then
            local bossParam = ""
            if self.selectedBoss then
                bossParam = ";"..self.selectedBoss
            end
            SendAddonMessage(self.prefix, "HELLO"..bossParam, "RAID")
        end
    elseif cmd == "LM_REQUEST" then
        self:Debug("Получен LM_REQUEST от "..sender)
        if self:IsLootMaster() then
            SendAddonMessage(self.prefix, "LM_RESPONSE;"..UnitName("player"), "WHISPER", sender)
            self:Debug("Отправлен LM_RESPONSE")
        end
    elseif cmd == "LM_RESPONSE" then
        local lmName = rest
        --DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Лутер в рейде: "..lmName)
        self:Debug("Лутер найден: "..lmName)
    elseif cmd == "CHECK_VERSION" or cmd == "CHECK" then
        self:Debug("Получен CHECK_VERSION от "..sender)
        if self:IsLootMaster() then
            local versionMsg = "VERSIONS"
            for bossName, version in pairs(self.dataVersions) do
                versionMsg = versionMsg .. ";" .. bossName .. ":" .. version
            end
            SendAddonMessage(self.prefix, versionMsg, "WHISPER", sender)
            self:Debug("Отправлены версии: "..versionMsg)
        end
    elseif cmd == "VERSION" then
        local serverVersion = tonumber(rest) or 0
        self:Debug("Получена старая версия от лутера: "..serverVersion)
    elseif cmd == "VERSIONS" then
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
            --DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Обновление данных...")
        end
    elseif cmd == "TOOLOW" then
        local amount, maxBid = rest:match("([^;]+);([^;]+)")
        --DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[EPBA]|r Ваша ставка "..amount.." меньше текущей максимальной ("..maxBid..")")
    elseif cmd == "BIDOK" then
        local amount, playerName = rest:match("([^;]+);([^;]+)")
        if not amount then amount = rest; playerName = "неизвестный" end
        --DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Ставка "..amount.." от "..playerName.." принята")
        auction.bidBox:SetText("")
    elseif cmd == "SYNC_COMPLETE" then
        self.receivedSync = true
        --DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Синхронизация завершена")
        self:Debug("Синхронизация завершена")
    elseif cmd == "END" then
        local bossName = rest
        self.bids[bossName] = {}
        self.dataVersions[bossName] = (self.dataVersions[bossName] or 0) + 1
        if self.selectedBoss == bossName then
            self:RefreshTable()
        end
        self:SaveData()
        --DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Аукцион для "..bossName.." завершён (Loot Master).")
    elseif cmd == "LOCK" then
        self:Debug("LOCK получен, rest='"..tostring(rest).."'")
        local cleanRest = rest:gsub("%s+", "")
        local state = (cleanRest == "true")
        self:Debug("state="..tostring(state))
        if self:IsLootMaster() then
            self:Debug("Я лутер, игнорирую свой LOCK")
            return
        end
        self:SetBidsLocked(state)
        --DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Лутер " .. (state and "заблокировал" or "разблокировал") .. " приём ставок.")
    elseif cmd == "LOCKED" then
        --DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[EPBA]|r Ставка отклонена: лутер заблокировал приём ставок.")
    else
        self:Debug("Неизвестная команда: "..cmd)
    end
end

-- ======================
-- Обработка входящей ставки (BID)
-- ======================
function auction:HandleBidMessage(rest, sender)
    if not self:IsLootMaster() then 
        self:Debug("Игнорируем BID, я не лутер")
        return 
    end
    if self.bidsLocked then
        self:Debug("Блокировка активна, ставка отклонена")
        SendAddonMessage(self.prefix, "LOCKED", "WHISPER", sender)
        return
    end
    local bossName, itemID, playerName, amount = rest:match("([^;]+);([^;]+);([^;]+);([^;]+)")
    if not (bossName and itemID and playerName and amount) then 
        self:Debug("Ошибка парсинга BID: "..rest)
        return 
    end
    itemID = tonumber(itemID)
    amount = tonumber(amount)
    self:Debug("Обработка BID: "..playerName.." "..amount.." на "..bossName.." "..itemID)
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
    else
        table.insert(self.bids[bossName][itemID], {
            player = playerName,
            amount = amount
        })
    end
    self:RefreshTable()
    self:SendSync(bossName, itemID)
    self:CheckIfOutbid(bossName, itemID)
    SendAddonMessage(self.prefix, "BIDOK;"..amount..";"..playerName, "RAID")
    self:Debug("Ставка обработана, отправлен SYNC")
end

-- ======================
-- Проверка, перебита ли ставка текущего игрока
-- ======================
function auction:CheckIfOutbid(bossName, itemID)
    if self:IsLootMaster() then return end   -- лутеру не нужны уведомления

    local playerName = UnitName("player")
    local bidsForItem = self.bids[bossName] and self.bids[bossName][itemID]
    if not bidsForItem then return end

    -- Находим ставку текущего игрока
    local myBid
    for _, bid in ipairs(bidsForItem) do
        if bid.player == playerName then
            myBid = bid.amount
            break
        end
    end
    if not myBid then return end   -- у игрока нет ставки на этот предмет

    -- Находим максимальную ставку и её владельца
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
        -- Ставка перебита
        if not self.outbidNotified[key] then
            self.outbidNotified[key] = true
            local itemName = GetItemInfo(itemID) or ("предмет "..itemID)
            local message = string.format("Вашу ставку на %s перебил %s (%s EP)!", itemName, topPlayer, self:FormatNumber(maxBid))

            -- Попробуем отправить через DBM (если он есть), иначе через стандартное рейд-уведомление
            if DBM and DBM.AddAnnounce then
                DBM:AddAnnounce(message, 2, 3)   -- 2 = звук, 3 = цвет
            elseif RaidWarningFrame then
                RaidWarningFrame:AddMessage(message, 1.0, 0.5, 0.0)
            else
                UIErrorsFrame:AddMessage(message, 1.0, 0.5, 0.0, 5)
            end
        end
    else
        -- Ставка снова лидирует – сбрасываем флаг
        self.outbidNotified[key] = nil
    end
end
