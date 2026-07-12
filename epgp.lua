local auction = EPBossAuction

function auction:UpdateMyEP()
    self.myEP = 0
    local epgpTable = EPGP or EPGP_Auction or CEPGP or EPGPCore
    if not epgpTable then
        self:Debug("EPGP аддон не найден!")
        if self.frame and self.frame:IsShown() then
            self.myEPText:SetText("Ваш ЕП: EPGP не найден")
        end
        return
    end
    self:Debug("Найден EPGP аддон, получаем EP...")
    local playerName = UnitName("player")
    self:Debug("Игрок: "..playerName)
    if epgpTable.Update then
        epgpTable:Update()
        self:Debug("Принудительное обновление EPGP")
    end
    self:ScheduleTimer(function()
        self:DoUpdateMyEP(epgpTable, playerName)
    end, 1)
end

function auction:DoUpdateMyEP(epgpTable, playerName)
    if epgpTable.GetEPGP then
        self:Debug("Используем GetEPGP...")
        local ep, gp, main = epgpTable:GetEPGP(playerName)
        self:Debug("GetEPGP вернул: EP="..tostring(ep)..", GP="..tostring(gp)..", main="..tostring(main))
        if ep then
            if main then
                self:Debug("Это твин, мейн: "..main)
                local mainEP, mainGP, mainMain = epgpTable:GetEPGP(main)
                if mainEP then
                    self.myEP = tonumber(mainEP) or 0
                else
                    self.myEP = tonumber(ep) or 0
                end
            else
                self.myEP = tonumber(ep) or 0
            end
            self:Debug("ИТОГОВЫЙ EP: "..self.myEP)
            if self.frame and self.frame:IsShown() then
                self.myEPText:SetText("Ваш ЕП: "..self:FormatNumber(self.myEP))
            end
            return
        end
    end
    if epgpTable.db and epgpTable.db.profile and epgpTable.db.profile.players then
        self:Debug("Проверяем базу данных EPGP...")
        local playerData = epgpTable.db.profile.players[playerName]
        if playerData then
            self:Debug("Найден в базе: "..playerName..", EP="..tostring(playerData.EP))
            if playerData.main then
                local mainData = epgpTable.db.profile.players[playerData.main]
                if mainData and mainData.EP then
                    self.myEP = tonumber(mainData.EP) or 0
                else
                    self.myEP = tonumber(playerData.EP) or 0
                end
            else
                self.myEP = tonumber(playerData.EP) or 0
            end
            if self.frame and self.frame:IsShown() then
                self.myEPText:SetText("Ваш ЕП: "..self:FormatNumber(self.myEP))
            end
            return
        end
    end
    if epgpTable.GetEP then
        self:Debug("Пробуем GetEP...")
        local ep = epgpTable:GetEP(playerName)
        if ep then
            self.myEP = tonumber(ep) or 0
            if self.frame and self.frame:IsShown() then
                self.myEPText:SetText("Ваш ЕП: "..self:FormatNumber(self.myEP))
            end
            return
        end
    end
    self:Debug("НЕ УДАЛОСЬ НАЙТИ EP для игрока "..playerName)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[EPBA]|r Не удалось получить ваш EP. Проверьте работу EPGP.")
    if self.frame and self.frame:IsShown() then
        self.myEPText:SetText("Ваш ЕП: не найден")
    end
end

function auction:StartEPUpdates()
    if self.epUpdateTimer then
        self:CancelTimer(self.epUpdateTimer)
        self.epUpdateTimer = nil
    end
    -- ScheduleRepeatingTimer вместо самодельной рекурсии через ScheduleTimer:
    -- один хендл на весь цикл жизни таймера, не нужно вручную пересоздавать
    -- его на каждый тик (и нет риска словить дублирующийся хендл, если
    -- StartEPUpdates вызовут повторно между отменой старого и созданием
    -- нового таймера).
    self.epUpdateTimer = self:ScheduleRepeatingTimer("CheckAndUpdateEP", self.epUpdateInterval)
    self:Debug("Запущено периодическое обновление EP (интервал "..self.epUpdateInterval.." сек)")
end

function auction:CheckAndUpdateEP()
    if self.epUpdatePending then return end
    self.epUpdatePending = true

    local now = GetTime()
    if now - self.lastEPUpdate < 2 then
        self.epUpdatePending = false
        return
    end

    self:ForceEPUpdate(function(success, newEP)
        if success then
            self:UpdateEPDisplay()
            self:CheckCurrentBidAgainstEP()
        end
        self.lastEPUpdate = GetTime()
        self.epUpdatePending = false
    end)
end

function auction:UpdateEPDisplay()
    if self.frame and self.frame:IsShown() and self.myEPText then
        self.myEPText:SetText("Ваш ЕП: "..self:FormatNumber(self.myEP))
        self:UpdateMaxBidDisplay()
        
        local currentBid = tonumber(self.bidBox:GetText()) or 0
        local isOffspec = self.offspecCheckbox and self.offspecCheckbox:GetChecked() or false
        local maxBid = self:GetMaxBidAmount(isOffspec)
        
        if currentBid > 0 and currentBid > maxBid then
            self.myEPText:SetTextColor(1, 0, 0)
            self.bidBox:SetTextColor(1, 0, 0)
        else
            self.myEPText:SetTextColor(1, 1, 1)
            self.bidBox:SetTextColor(1, 1, 1)
        end
    end
end

function auction:CheckCurrentBidAgainstEP()
    local currentBid = tonumber(self.bidBox:GetText()) or 0
    if currentBid > 0 and currentBid > self.myEP then
        -- не выводим сообщение, только подсветка
    end
end

function auction:ForceEPUpdate(callback)
    if self.isUpdatingEP then
        -- Раньше здесь коллбэк вызывался с success=false и на этом всё —
        -- если это было обновление EP, запущенное из-под ставки игрока
        -- (SendBidLocal), ставка тихо терялась: пользователь жал "Сделать
        -- ставку" ровно в момент, когда параллельно уже шёл период. апдейт
        -- EP (раз в epUpdateInterval) или апдейт по EPGP_UPDATE/DATA_CHANGED
        -- (который как раз чаще всего прилетает во время самого рейда,
        -- когда офицеры начисляют EP — то есть именно когда люди бидают).
        -- Внешне это выглядело как "ставка регистрируется с задержкой":
        -- на самом деле она просто не уходила, и её приходилось повторять.
        -- Теперь вместо дропа — кладём коллбэк в очередь и выполняем его
        -- сразу по завершении уже идущего обновления, с тем же результатом,
        -- без действий со стороны игрока.
        self:Debug("ForceEPUpdate уже выполняется, коллбэк поставлен в очередь")
        self.pendingEPCallbacks = self.pendingEPCallbacks or {}
        if callback then
            table.insert(self.pendingEPCallbacks, callback)
        end
        return
    end
    self.isUpdatingEP = true
    
    self:Debug("Принудительное обновление EP...")
    local epgpTable = EPGP or EPGP_Auction or CEPGP or EPGPCore
    if not epgpTable then
        if callback then callback(false, 0) end
        self.isUpdatingEP = false
        return
    end
    if epgpTable.Update then
        epgpTable:Update()
    end
    local playerName = UnitName("player")
    self:ScheduleTimer(function()
        local newEP = 0
        if epgpTable.GetEPGP then
            local ep, gp, main = epgpTable:GetEPGP(playerName)
            if ep then
                if main then
                    local mainEP, mainGP, mainMain = epgpTable:GetEPGP(main)
                    newEP = tonumber(mainEP or ep) or 0
                else
                    newEP = tonumber(ep) or 0
                end
            end
        elseif epgpTable.db and epgpTable.db.profile and epgpTable.db.profile.players then
            local playerData = epgpTable.db.profile.players[playerName]
            if playerData then
                if playerData.main then
                    local mainData = epgpTable.db.profile.players[playerData.main]
                    newEP = tonumber(mainData and mainData.EP or playerData.EP) or 0
                else
                    newEP = tonumber(playerData.EP) or 0
                end
            end
        end
        auction.myEP = newEP
        auction.lastEPUpdate = GetTime()
        
        auction.offspecMultiplier = auction.db.general.offspecMultiplier or 0.5
        
        auction:RefreshPlayerEPCache()
        
        if auction.frame and auction.frame:IsShown() then
            auction.myEPText:SetText("Ваш ЕП: "..auction:FormatNumber(newEP))
            auction:UpdateMaxBidDisplay()
            auction:UpdateBidRowColors()
        end
        auction:Debug("Принудительное обновление завершено, EP="..newEP)
        if callback then callback(true, newEP) end

        -- Отдаём тот же свежий результат всем, кто "постучался" за время
        -- обновления (см. начало функции) — вместо тихой потери их ставок.
        if auction.pendingEPCallbacks and #auction.pendingEPCallbacks > 0 then
            local queued = auction.pendingEPCallbacks
            auction.pendingEPCallbacks = {}
            for _, queuedCallback in ipairs(queued) do
                queuedCallback(true, newEP)
            end
        end

        auction.isUpdatingEP = false
    end, 0.5)
end

function auction:FindEPGP()
    self:Debug("=== ПОИСК EPGP АДДОНА ===")
    local found = false
    for k, v in pairs(_G) do
        if type(k) == "string" and (k:find("EPGP") or k:find("Auction") or k:find("CEPGP")) then
            self:Debug("Найдена глобальная переменная: "..k)
            if type(v) == "table" then
                self:Debug("  Тип: таблица")
                if v.GetEPGP then
                    self:Debug("  Есть метод GetEPGP - ОСНОВНОЙ")
                    local playerName = UnitName("player")
                    local ep, gp, main = v:GetEPGP(playerName)
                    self:Debug("    Тест GetEPGP для "..playerName..": EP="..tostring(ep)..", GP="..tostring(gp)..", main="..tostring(main))
                end
                if v.GetEP then
                    self:Debug("  Есть метод GetEP")
                    local ep = v:GetEP(UnitName("player"))
                    self:Debug("    Тест GetEP: "..tostring(ep))
                end
                if v.db and v.db.profile and v.db.profile.players then
                    self:Debug("    Есть база данных игроков")
                end
                found = true
            end
        end
    end
    if not found then
        self:Debug("EPGP аддон не найден!")
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[EPBA]|r EPGP аддон не найден!")
    end
    self:Debug("========================")
end