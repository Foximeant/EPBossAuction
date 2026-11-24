local auction = EPBossAuction

-- ============================================================
-- events.lua — точка входа аддона
-- ============================================================
-- Один фрейм, один OnEvent-обработчик на все события WoW, которые
-- нужны аддону. Порядок при запуске: ADDON_LOADED → LoadSettings/
-- CreateUI → восстановление SavedVariables → ApplySettings →
-- auction.fullyLoaded = true → (если WoW уже прислал
-- PLAYER_ENTERING_WORLD до этого момента) HandleWorldEnter() из
-- comm.lua, которая и запускает поиск ЛМ/синхронизацию.
--
-- GROUP_ROSTER_UPDATE/RAID_ROSTER_UPDATE — самая частая и самая
-- "тяжёлая" ветка: дергается при любом изменении состава пати/рейда,
-- поэтому обёрнута в debounce-таймер (auction.groupRosterTimer, 2 сек),
-- чтобы не спамить сеть при быстрых цепочках инвайтов/выходов.
-- ============================================================

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("RAID_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_LOGOUT")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("EPGP_UPDATE")
f:RegisterEvent("EPGP_DATA_CHANGED")

f:SetScript("OnEvent", function(selfF, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == "EPBossAuction" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r EPBossAuction "..auction.version.." загружен")
        auction:LoadSettings()
        auction:CreateUI()
        auction:CreateOptionsPanel()
        auction:Debug("=== ПРОВЕРКА СОХРАНЕННЫХ ДАННЫХ ===")
        -- Сохранённые данные (EPBossAuctionDB, см. core.lua:GetDB). Пустая база
        -- (первый запуск или после смены схемы) даёт пустые таблицы — отдельной
        -- ветки "нет данных" нет.
        local db = auction:GetDB()
        local savedCount = 0
        if type(db.bids) == "table" then
            for bossName, bossBids in pairs(db.bids) do
                for itemID, bidsForItem in pairs(bossBids) do
                    savedCount = savedCount + #bidsForItem
                end
            end
        end
        auction:Debug("В сохранении: "..savedCount.." ставок")
        auction.bids = (type(db.bids) == "table") and db.bids or {}
        auction.dataVersions = auction:NormalizeVersionTable(db.versions or {})
        auction.lastVersions = {}
        auction.signups = (type(db.signups) == "table") and db.signups or {}
        auction:PurgeObsoleteSignups() -- убираем категории, которых больше нет (напр. "валик")
        -- История посещаемости (вкладка Attendance, attendance.lua)
        auction.attendance = (type(db.attendance) == "table") and db.attendance or {}
        -- Метки удалений/очистки для синхронизации посещаемости (attendance.lua)
        auction.attendanceMeta = { clearedBefore = 0, deleted = {} }
        if type(db.attendanceMeta) == "table" then
            auction.attendanceMeta.clearedBefore = tonumber(db.attendanceMeta.clearedBefore) or 0
            if type(db.attendanceMeta.deleted) == "table" then auction.attendanceMeta.deleted = db.attendanceMeta.deleted end
        end
        auction:RebuildBidData()

        if db.selectedBoss and auction.bosses[db.selectedBoss] then
            auction.selectedBoss = db.selectedBoss
            auction.selectedInstance = auction.bossToInstance[auction.selectedBoss]
            auction:Debug("Восстановлен босс: "..auction.selectedBoss)
        else
            auction.selectedBoss = nil
            auction.selectedInstance = nil
        end
        auction:UpdateBossDropdownText()

        auction.selectedItem = nil
        if auction.selectedBoss and db.selectedItem then
            for _, itemID in ipairs(auction.bosses[auction.selectedBoss]) do
                if itemID == db.selectedItem then
                    auction.selectedItem = db.selectedItem
                    auction:Debug("Восстановлен предмет: "..auction.selectedItem)
                    break
                end
            end
        end

        if db.windowScale then
            auction.windowScale = db.windowScale
            auction.db.window.scale = db.windowScale
        end
        if db.minimapPos then
            auction.minimapButtonPosition = db.minimapPos
            auction.db.minimap.position = db.minimapPos
        end
        auction.bidsLocked = (db.bidsLocked == true)
        if db.offspecMultiplier then
            auction.offspecMultiplier = db.offspecMultiplier
            auction.db.general.offspecMultiplier = db.offspecMultiplier
        end
        auction:ApplySettings()
        auction:LoadReserves()   -- резерв предметов (reserve.lua), не зависит от наличия сохранённых ставок
        auction:InitAutoSave()
        auction:StartEPUpdates()
        auction:CreateMinimapButton()
        auction.fullyLoaded = true

        -- Справка: новому пользователю (нет EPBossAuctionDB.lastSeenVersion — аддон
        -- ставят впервые) показываем автоматически один раз. Тем, кто обновился с
        -- прошлой версии, не навязываем (у них свой экран "Что нового?"; справка
        -- доступна по кнопке "Меню" и /epba help). Проверка — до записи LastSeenVersion ниже.
        if not db.helpSeen then
            db.helpSeen = true
            if not db.lastSeenVersion then
                auction:ScheduleTimer(function()
                    auction:ShowHelpWindow()
                end, 3)
            end
        end

        -- "Что нового?": показываем, если аддон обновился с прошлого входа
        if db.lastSeenVersion and auction:CompareVersions(auction.version, db.lastSeenVersion) > 0 then
            auction.pendingWhatsNew = db.lastSeenVersion
        end
        db.lastSeenVersion = auction.version

        if auction.pendingWorldEnter then
            auction:HandleWorldEnter()
            auction.pendingWorldEnter = nil
        end
        auction:Debug("Аддон загружен")

        if auction.pendingWhatsNew then
            auction:ScheduleTimer(function()
                auction:ShowWhatsNewWindow()
            end, 2)
        end

        -- Периодическая очистка устаревших уведомлений (раз в 5 минут)
        auction:ScheduleTimer(function()
            auction:CleanOutbidNotified()
        end, 300)

    elseif event == "PLAYER_ENTERING_WORLD" then
        auction:Debug("PLAYER_ENTERING_WORLD (pending)")
        if not auction.fullyLoaded then
            auction.pendingWorldEnter = true
            return
        end
        auction:HandleWorldEnter()

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = arg1, ...
        if prefix == auction.prefix then
            auction:HandleMessage(msg, sender)
        end

    elseif event == "GROUP_ROSTER_UPDATE" or event == "RAID_ROSTER_UPDATE" then
        if not auction.fullyLoaded then return end
        auction:CacheRaidClasses()
        if auction.groupRosterTimer then
            auction:CancelTimer(auction.groupRosterTimer)
            auction.groupRosterTimer = nil
        end
        auction.groupRosterTimer = auction:ScheduleTimer(function()
            auction.groupRosterTimer = nil
            local playerName = UnitName("player")
            if not IsInRaid() and not IsInGroup() then
                if auction.lastLM or next(auction.lastVersions) or next(auction.dataVersions) then
                    auction:ResetVersionsOnGroupExit()
                end
                auction:UpdateLockCheckbox()
                auction:UpdateLMButtonsState()
                return
            end
            -- Я стал/остаюсь ЛМ — если это смена (lastLM был другим), объявляю
            -- себя в рейд и планирую полную пересинхронизацию через 2 сек.
            if auction:IsLootMaster() then
                if auction.lastLM ~= playerName then
                    auction.lastLM = playerName
                    auction:UpdateLockCheckbox()
                    if auction.selectedBoss then
                        auction:RefreshTable()
                    end
                    auction:Send("LM", "RAID", nil, 0, "LM")
                    auction:OnBecameLootMaster()   -- резерв: подтянуть правки офицеров и разослать список в рейд
                    if auction.syncAllTimer then
                        auction:CancelTimer(auction.syncAllTimer)
                    end
                    auction.syncAllTimer = auction:ScheduleTimer(function()
                        auction.syncAllTimer = nil
                        auction:SyncAllToRaid()
                    end, 2)
                end
            else
                -- Я не ЛМ — определяю текущего через GetLootMethod у раид-ростера
                -- (не по сети). Если ЛМ реально сменился — сбрасываю версии и
                -- заново запрашиваю данные (CHECK_VERSION/HELLO) через 1 сек.
                local currentLM = nil
                local method, partyIndex, raidIndex = GetLootMethod()
                if method == "master" and raidIndex then
                    currentLM = GetRaidRosterInfo(raidIndex)
                end
                if currentLM and currentLM ~= auction.lastLM then
                    auction:ResetVersionsForNewLM()
                    auction.lastLM = currentLM
                elseif IsInRaid() or IsInGroup() then
                    auction:SendToLootMaster("CHECK_VERSION")
                    if auction.groupHelloTimer then
                        auction:CancelTimer(auction.groupHelloTimer)
                        auction.groupHelloTimer = nil
                    end
                    auction.groupHelloTimer = auction:ScheduleTimer(function()
                        auction.groupHelloTimer = nil
                        local bossParam = ""
                        if auction.selectedBoss then
                            bossParam = ";"..auction.selectedBoss
                        end
                        auction:SendToLootMaster("HELLO"..bossParam)
                        auction:Debug("Отправлен HELLO после GROUP_ROSTER_UPDATE")
                    end, 1)
                end
                auction:UpdateLockCheckbox()
            end
            auction:UpdateLMButtonsState()
            
            if auction.optionsPanel and auction.optionsPanel:IsShown() then
                local slider = _G["EPBAOffspecMultiplierSlider"]
                if slider then
                    if auction:IsLootMaster() then
                        slider:Enable()
                        slider:SetAlpha(1.0)
                    else
                        slider:Disable()
                        slider:SetAlpha(0.5)
                    end
                end
            end
        end, 2)

    -- Финальное сохранение перед выходом — подстраховка на случай, если
    -- автосейв (InitAutoSave, раз в 10 сек) не успел сработать.
    elseif event == "PLAYER_LOGOUT" then
        if auction.fullyLoaded then
            auction:SaveData()
            auction:Debug("Сохранение при выходе")
        end

    -- Вышли из боя — показываем отложенное уведомление о новой версии (comm.lua)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if auction.fullyLoaded then
            auction:FlushPendingUpdatePopup()
        end

    -- Внешний EPGP-аддон сам сообщил об изменении данных — не ждём следующего
    -- цикла периодического опроса (epgp.lua StartEPUpdates), обновляемся сразу.
    elseif event == "EPGP_UPDATE" or event == "EPGP_DATA_CHANGED" then
        if auction.fullyLoaded then
            auction:Debug("Получено обновление от EPGP")
            auction:CheckAndUpdateEP()
        end
    end
end)
