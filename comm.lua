local auction = EPBossAuction

--[[
    Сетевой протокол EPBossAuction — клиент-серверная модель, где лутер
    (Loot Master) выступает сервером: хранит единственный авторитетный
    список ставок и рассылает его клиентам. Клиенты никогда не хранят
    ставки, которые не пришли от текущего лутера.

    Сообщения (7 типов на ядро аукциона):
      BID            клиент → LM     сделать/отменить ставку
      BID_RESULT     LM → клиент     результат конкретной ставки (ok/too_low/locked)
      REQUEST_STATE  клиент → LM     запросить текущее состояние (по боссу или всё)
      STATE          LM → клиент(ы) текущие ставки по боссу + статус блокировки
      LM_ANNOUNCE    LM → рейд       "я лутер"
      LOCK           LM → рейд       статус блокировки ставок изменился
      OFFSPEC_MULT   LM → рейд       коэффициент офф-спека изменился

    Раньше протокол состоял из 14 типов сообщений (BID/BIDOK/TOOLOW/SYNC/
    HELLO/HELLO_ACK/END/LM/LM_REQUEST/LM_RESPONSE/CHECK_VERSION/VERSIONS/
    LOCK/LOCKED) и отдельной системы номеров версий для решения, нужно ли
    досылать данные повторно. Теперь STATE всегда несёт полное состояние
    по боссу (включая явно пустые предметы), поэтому номера версий не нужны:
    новое сообщение просто заменяет собой старое.

    Очередь на токены (QUEUE_*, см. queue.lua) — отдельный протокол поверх
    того же транспорта, здесь не описан.
]]

local function GetSafeItemInfo(itemID)
    if not itemID then return "неизвестный предмет" end
    local name = GetItemInfo(itemID)
    if name and name ~= "" then return name end
    return "предмет "..tostring(itemID)
end

-- Проверяет sender напрямую через игровое API, а не через self.lastLM.
-- self.lastLM обновляется с задержкой (LM_ANNOUNCE, roster-бакет раз в
-- 2 сек) — если сравнивать только с ним, сообщение от реального лутера
-- в этом окне рассинхрона молча отбрасывается (это и была причина, из-за
-- которой "Очистить" и обычные ставки иногда не долетали до части рейда).
local function IsSenderCurrentLootMaster(sender)
    local method, partyIndex, raidIndex = GetLootMethod()
    if method ~= "master" or not raidIndex then return false end
    return GetRaidRosterInfo(raidIndex) == sender
end

-- Общая проверка для входящих LM->клиент сообщений (STATE/LOCK/BID_RESULT):
-- если sender совпадает с закэшированным self.lastLM — ок, как раньше.
-- Если не совпадает, но по факту является актуальным лутером по данным
-- игры — самоисправляемся (подтягиваем self.lastLM) вместо отбрасывания.
-- Возвращает true, если сообщению можно доверять.
function auction:ConfirmMessageFromLM(sender)
    if sender == self.lastLM then return true end
    if IsSenderCurrentLootMaster(sender) then
        self:Debug("self.lastLM был устаревшим ("..tostring(self.lastLM)..
            "), исправлено на актуального лутера "..tostring(sender))
        self.lastLM = sender
        return true
    end
    return false
end

-- ======================
-- Транспорт (AceComm-3.0 + AceSerializer-3.0)
-- ======================
-- cmd — имя команды (строка, например "BID"); data — любое сериализуемое
-- значение (таблица/строка/число/nil). AceComm сам нарезает сообщения
-- длиннее 255 байт на части и troттлит отправку через ChatThrottleLib.
-- prio: "ALERT" для задержко-чувствительных сообщений (по умолчанию
-- AceComm подставит "NORMAL", которая делит полосу со всем остальным
-- addon-трафиком в рейде и первые секунды после зонирования жёстко
-- зажимается самой библиотекой).
function auction:QueueAddonMessage(cmd, data, channel, target, prio)
    if not cmd or cmd == "" or not channel then return end
    local payload = self:Serialize(cmd, data)
    if target then
        self:SendCommMessage(self.prefix, payload, channel, target, prio)
    else
        self:SendCommMessage(self.prefix, payload, channel, nil, prio)
    end
end

-- Отправляет лутеру: whisper, если лутер уже известен, иначе broadcast в
-- рейд (например, самый первый запрос сразу после входа в группу).
function auction:SendToLootMaster(cmd, data, prio)
    if not cmd or cmd == "" then return false end

    local playerName = UnitName("player")
    if self.lastLM and self.lastLM ~= "" and self.lastLM ~= playerName then
        self:QueueAddonMessage(cmd, data, "WHISPER", self.lastLM, prio)
        return true
    end

    self:QueueAddonMessage(cmd, data, "RAID", nil, prio)
    return false
end

-- Вызывается AceComm при получении сообщения с нашим префиксом (регистрация
-- в events.lua:OnEnable через self:RegisterComm(self.prefix)).
function auction:OnCommReceived(prefix, payload, distribution, sender)
    if prefix ~= self.prefix then return end
    local ok, cmd, data = self:Deserialize(payload)
    if not ok or not cmd then
        self:Debug("Не удалось разобрать входящее сообщение от "..tostring(sender))
        return
    end
    local handler = self["Handle_"..cmd]
    if handler then
        handler(self, data, sender)
    else
        self:Debug("Неизвестная команда: "..tostring(cmd))
    end
end

-- ======================
-- Вход в мир / первичная синхронизация
-- ======================
function auction:HandleWorldEnter()
    self:Debug("=== ОБРАБОТКА ВХОДА В МИР ===")
    self:Debug("fullyLoaded = "..tostring(self.fullyLoaded))
    self:Debug("Текущий игрок: "..UnitName("player"))

    self:ScheduleTimer(function()
        if self:IsLootMaster() then
            self:Debug("Я ЛУТЕР")
            local bidCount = 0
            for bossName, bossBids in pairs(self.bids) do
                for itemID, bidsForItem in pairs(bossBids) do
                    bidCount = bidCount + #bidsForItem
                end
            end
            self:Debug("Ставок в памяти: "..bidCount)
            if self.selectedBoss then
                if self.bossDropdown then
                    UIDropDownMenu_SetText(self.bossDropdown, self.selectedBoss)
                end
                self:RequestRefresh()
            end
            if bidCount > 0 then
                self:ScheduleTimer(function()
                    self:SyncAllToRaid()
                end, 3)
            else
                self:Debug("НЕТ СТАВОК, просто сообщаем что мы лутер")
                self:QueueAddonMessage("LM_ANNOUNCE", nil, "RAID", nil, "ALERT")
            end
        else
            self:Debug("Я НЕ ЛУТЕР")
            if IsInRaid() or IsInGroup() then
                self:RequestDataFromLM()
            end
        end
        self:UpdateMyEP()
    end, 2)

    -- Автоматический запрос очередей
    if not self:IsLootMaster() and (IsInRaid() or IsInGroup()) then
        self:ScheduleTimer(function()
            self:RequestQueuesFromLM()
        end, 5)
    elseif self:IsLootMaster() then
        self:ScheduleTimer(function()
            self:SyncAllQueuesToRaid()
        end, 4)
    end

    -- Подхватываем локальные самозаписи в очередь (сделанные когда угодно,
    -- даже вне группы) и отправляем их лутеру / применяем у себя.
    self:ScheduleTimer(function()
        self:SyncMySignupsIfNeeded()
    end, 5)

    self:Debug("===============================")
end

function auction:RequestDataFromLM()
    if self:IsLootMaster() then
        self:Debug("Я лутер, запрос игнорируется")
        return
    end
    self:Debug("Запрос данных у лутера")
    self.receivedSync = false
    self:SendToLootMaster("REQUEST_STATE", { boss = self.selectedBoss }, "ALERT")
    self:ScheduleTimer(function()
        if not self.receivedSync then
            self:Debug("Не удалось получить данные от лутера")
        else
            self:Debug("Данные успешно получены")
        end
    end, 8)
end

-- ======================
-- Отправка состояния (LM → клиенты)
-- ======================
-- Собирает таблицу { [itemID] = { {player=,amount=,isOffspec=}, ... }, ... }
-- для ВСЕХ предметов босса (включая те, где ставок нет — пустым списком),
-- чтобы получатель мог полностью заменить своё локальное состояние по
-- боссу этим сообщением, не держа отдельной логики "какие предметы вообще
-- существуют у этого босса".
local function BuildFullBossItems(self, bossName)
    local items = {}
    local bossItems = self.bosses[bossName]
    if not bossItems then return items end
    local bossBids = self.bids[bossName] or {}
    for _, itemID in ipairs(bossItems) do
        local bidsForItem = bossBids[itemID] or {}
        local list = {}
        for _, bid in ipairs(bidsForItem) do
            table.insert(list, { player = bid.player, amount = bid.amount, isOffspec = bid.isOffspec and true or false })
        end
        items[itemID] = list
    end
    return items
end

-- full=true  — items содержит ВСЕ предметы босса, получатель заменяет
--              self.bids[bossName] целиком (используется для ответа на
--              REQUEST_STATE и при массовой синхронизации).
-- full=false — items содержит только изменившийся(еся) предмет(ы),
--              получатель обновляет только эти ключи, не трогая остальные
--              (используется для точечной рассылки после одной ставки).
function auction:SendBossState(bossName, channel, target, full, onlyItemID)
    if not self:IsLootMaster() then return false end
    if not bossName then return false end

    local items
    if full then
        items = BuildFullBossItems(self, bossName)
    else
        items = {}
        local bidsForItem = (self.bids[bossName] and self.bids[bossName][onlyItemID]) or {}
        local list = {}
        for _, bid in ipairs(bidsForItem) do
            table.insert(list, { player = bid.player, amount = bid.amount, isOffspec = bid.isOffspec and true or false })
        end
        items[onlyItemID] = list
    end

    local payload = { boss = bossName, items = items, full = full and true or false, locked = self.bidsLocked and true or false }
    self:QueueAddonMessage("STATE", payload, channel, target, "ALERT")
    return true
end

-- Точечное обновление одного предмета сразу после изменения ставки —
-- заменяет старый SendSyncImmediate/QueueSync/FlushSyncQueue троттлинг:
-- STATE теперь маленькое сообщение (один предмет), отдельный троттлер
-- поверх него не нужен, ALERT-приоритет AceComm уже достаточно быстрый.
function auction:SendSyncImmediate(bossName, itemID)
    if not bossName or not itemID then return end
    local itemName = GetSafeItemInfo(itemID)
    self:Debug("Отправка STATE для босса "..bossName..": "..itemName)
    self:SendBossState(bossName, "RAID", nil, false, itemID)
end

-- Совместимость: старый код (ui.lua/lootmaster.lua) вызывает QueueSync
-- после локального изменения ставки лутером. Раньше здесь была очередь
-- с троттлингом 0.2 сек на случай пачки изменений подряд; при новом
-- маленьком по размеру STATE-сообщении на предмет в этом уже нет нужды,
-- но сигнатуру вызова сохраняем, чтобы не трогать вызывающий код.
function auction:QueueSync(bossName, itemID)
    self:SendSyncImmediate(bossName, itemID)
end

-- Полная рассылка всем — при становлении лутером или по запросу без
-- указания конкретного босса. Одно сообщение STATE на босса (а не на
-- предмет, как раньше) — гораздо меньше сообщений при большом числе ставок.
function auction:SyncAllToRaid()
    if not self:IsLootMaster() then
        self:Debug("Не лутер, синхронизация отменена")
        return
    end
    self:QueueAddonMessage("LM_ANNOUNCE", nil, "RAID", nil, "ALERT")
    local sentCount = 0
    for bossName, bossBids in pairs(self.bids) do
        local hasBids = false
        for _, bidsForItem in pairs(bossBids) do
            if #bidsForItem > 0 then hasBids = true break end
        end
        if hasBids then
            self:SendBossState(bossName, "RAID", nil, true)
            sentCount = sentCount + 1
        end
    end
    self:Debug("Разослано состояние "..sentCount.." боссов в рейд")
end

-- Ответ на REQUEST_STATE конкретному игроку.
function auction:SendStateToPlayer(bossName, targetPlayer)
    if not bossName or not targetPlayer then return false end
    if not self.bosses[bossName] then
        self:Debug("Неизвестный босс в запросе состояния: "..tostring(bossName))
        return false
    end
    return self:SendBossState(bossName, "WHISPER", targetPlayer, true)
end

-- ======================
-- Обработчики сообщений
-- ======================
function auction:Handle_BID(data, sender)
    if not self:IsLootMaster() then
        self:Debug("Игнорируем BID, я не лутер")
        return
    end
    if type(data) ~= "table" then return end
    local bossName, itemID, amount, isOffspec = data.boss, data.item, data.amount, data.offspec
    local playerName = sender
    if not (bossName and itemID and amount ~= nil) then
        self:Debug("Ошибка данных BID от "..tostring(sender))
        return
    end
    amount = tonumber(amount) or 0
    isOffspec = isOffspec and true or false

    if self.bidsLocked then
        self:Debug("Блокировка активна, ставка отклонена")
        self:QueueAddonMessage("BID_RESULT", { boss = bossName, item = itemID, status = "locked" }, "WHISPER", sender, "ALERT")
        return
    end

    self:Debug("Обработка BID: "..playerName.." "..amount.." на "..bossName.." "..itemID.." (офф-спек: "..tostring(isOffspec)..")")

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
        self:AddBidLogEntry(playerName, 0, itemID, bossName, isOffspec)
        self:Debug("Отказ от ставки обработан")
        return
    end

    if amount < self.db.general.minBid then
        self:Debug("Ставка меньше минимальной ("..self.db.general.minBid.."), отклонена")
        self:QueueAddonMessage("BID_RESULT", { boss = bossName, item = itemID, status = "too_low", minBid = self.db.general.minBid }, "WHISPER", sender, "ALERT")
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
        existingBid.isOffspec = isOffspec
    else
        table.insert(self.bids[bossName][itemID], {player = playerName, amount = amount, isOffspec = isOffspec})
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
    self:AddBidLogEntry(playerName, amount, itemID, bossName, isOffspec)
    self:QueueAddonMessage("BID_RESULT", { boss = bossName, item = itemID, status = "ok" }, "WHISPER", sender, "ALERT")
    self:Debug("Ставка обработана, отправлен STATE")
end

function auction:Handle_BID_RESULT(data, sender)
    if type(data) ~= "table" then return end
    if not self:ConfirmMessageFromLM(sender) then return end
    if data.status == "too_low" then
        print(string.format("|cffff0000[EPBA]|r Ставка слишком мала. Минимум: %s EP", self:FormatNumber(data.minBid or 0)))
    elseif data.status == "locked" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[EPBA]|r Ставки заблокированы лутером!")
    end
    -- status == "ok": поле ставки уже очищено оптимистично в момент
    -- отправки (см. ui.lua:SendBidAfterConfirm), отдельного действия не нужно.
end

function auction:Handle_STATE(data, sender)
    if type(data) ~= "table" or not data.boss then return end
    if self:IsLootMaster() then
        self:Debug("Я лутер, игнорирую STATE от "..tostring(sender))
        return
    end
    if not self:ConfirmMessageFromLM(sender) then
        self:Debug("Игнорируем STATE от не-Loot Master: "..tostring(sender).." (ожидался "..tostring(self.lastLM)..")")
        return
    end

    self:Debug("Получен STATE для босса "..data.boss.." от "..sender.." (full="..tostring(data.full)..")")
    self.receivedSync = true

    if data.locked ~= nil then
        self:SetBidsLocked(data.locked and true or false)
    end

    local bossName = data.boss
    self.bids[bossName] = self.bids[bossName] or {}

    if data.full then
        -- Полная замена: любой предмет, отсутствующий в data.items (не
        -- должно случаться при full=true, но на всякий случай), не трогаем.
        local newBossBids = {}
        for itemID, newBids in pairs(data.items or {}) do
            local oldBids = self.bids[bossName][itemID] or {}
            self:LogBidChangesFromSync(oldBids, newBids, itemID, bossName)
            newBossBids[itemID] = newBids
            self:UpdateSortedBids(bossName, itemID)
        end
        self.bids[bossName] = newBossBids
        for itemID in pairs(data.items or {}) do
            self:UpdateBidCaches(bossName, itemID)
            self:CheckIfOutbid(bossName, itemID)
        end
    else
        for itemID, newBids in pairs(data.items or {}) do
            local oldBids = self.bids[bossName][itemID] or {}
            self:LogBidChangesFromSync(oldBids, newBids, itemID, bossName)
            self.bids[bossName][itemID] = newBids
            self:UpdateSortedBids(bossName, itemID)
            self:UpdateBidCaches(bossName, itemID)
            self:CheckIfOutbid(bossName, itemID)
        end
    end

    if self.selectedBoss == bossName then
        self:RequestRefresh()
    end
    self:RequestSaveData()
    self:Debug("STATE для босса "..bossName.." обработан")
end

function auction:Handle_REQUEST_STATE(data, sender)
    if not self:IsLootMaster() then
        self:Debug("Игнорируем REQUEST_STATE, я не лутер")
        return
    end
    local requestedBoss = (type(data) == "table" and data.boss) or nil
    self:Debug("Получен REQUEST_STATE от "..sender.." для босса "..(requestedBoss or "всех"))

    if requestedBoss then
        self:SendStateToPlayer(requestedBoss, sender)
    elseif self.selectedBoss then
        self:SendStateToPlayer(self.selectedBoss, sender)
    else
        local sentAny = false
        for bossName, _ in pairs(self.bids) do
            if self:SendStateToPlayer(bossName, sender) then
                sentAny = true
            end
        end
        if not sentAny then
            self:Debug("Нет данных для отправки "..sender)
        end
    end
end

function auction:Handle_LM_ANNOUNCE(data, sender)
    self:Debug("Получено LM_ANNOUNCE от "..sender)
    if self:IsLootMaster() then return end
    local isNewLM = (self.lastLM ~= sender)
    self.lastLM = sender
    if isNewLM then
        self:SendToLootMaster("REQUEST_STATE", { boss = self.selectedBoss }, "ALERT")
    end
end

function auction:Handle_LOCK(data, sender)
    if not self:ConfirmMessageFromLM(sender) then return end
    if self:IsLootMaster() then
        self:Debug("Я лутер, игнорирую свой LOCK")
        return
    end
    self:SetBidsLocked(data and true or false)
end

function auction:Handle_OFFSPEC_MULT(data, sender)
    if not self:ConfirmMessageFromLM(sender) then return end
    local multiplier = tonumber(data)
    if multiplier then
        self.offspecMultiplier = multiplier
        self.db.general.offspecMultiplier = multiplier
        self:SaveSettings()
        self:Debug("Получен новый коэффициент офф-спек: "..(multiplier * 100).."%")
        if self.myEP > 0 then
            self:UpdateMaxBidDisplay()
        end
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
