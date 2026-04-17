local auction = EPBossAuction

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("RAID_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_LOGOUT")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("EPGP_UPDATE")
f:RegisterEvent("EPGP_DATA_CHANGED")

f:SetScript("OnEvent", function(selfF, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == "EPBossAuction" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r EPBossAuction "..auction.version.." загружен")
        auction:LoadSettings()
        auction:CreateUI()
        auction:CreateOptionsPanel()
        auction:Debug("=== ПРОВЕРКА СОХРАНЕННЫХ ДАННЫХ ===")
        if EPBossAuctionSavedBids then
            local savedCount = 0
            for bossName, bossBids in pairs(EPBossAuctionSavedBids) do
                for itemID, bidsForItem in pairs(bossBids) do
                    savedCount = savedCount + #bidsForItem
                end
            end
            auction:Debug("В сохранении: "..savedCount.." ставок")
            auction.bids = EPBossAuctionSavedBids
            auction.dataVersions = auction:NormalizeVersionTable(EPBossAuctionSavedVersions or {})
            auction.lastVersions = {}
            auction:RebuildBidData()

            if EPBossAuctionSavedSelectedBoss and auction.bosses[EPBossAuctionSavedSelectedBoss] then
                auction.selectedBoss = EPBossAuctionSavedSelectedBoss
                auction:Debug("Восстановлен босс: "..auction.selectedBoss)
            else
                auction.selectedBoss = nil
            end

            if auction.selectedBoss and EPBossAuctionSavedSelectedItem then
                local items = auction.bosses[auction.selectedBoss]
                local found = false
                for _, itemID in ipairs(items) do
                    if itemID == EPBossAuctionSavedSelectedItem then
                        found = true
                        break
                    end
                end
                if found then
                    auction.selectedItem = EPBossAuctionSavedSelectedItem
                    auction:Debug("Восстановлен предмет: "..auction.selectedItem)
                else
                    auction.selectedItem = nil
                end
            else
                auction.selectedItem = nil
            end

            if EPBossAuctionSavedScale then
                auction.windowScale = EPBossAuctionSavedScale
                auction.db.window.scale = EPBossAuctionSavedScale
            end

            if EPBossAuctionSavedMinimapPos then
                auction.minimapButtonPosition = EPBossAuctionSavedMinimapPos
                auction.db.minimap.position = EPBossAuctionSavedMinimapPos
            end

            if EPBossAuctionBidsLocked ~= nil then
                auction.bidsLocked = EPBossAuctionBidsLocked
            end

            if EPBossAuctionSavedOffspecMultiplier then
                auction.offspecMultiplier = EPBossAuctionSavedOffspecMultiplier
                auction.db.general.offspecMultiplier = EPBossAuctionSavedOffspecMultiplier
            end
        else
            auction:Debug("Нет сохраненных данных")
            auction.bids = {}
            auction.dataVersions = {}
            auction.lastVersions = {}
            auction.windowScale = 1.0
            auction.bidsLocked = false
            auction:RebuildBidData()
        end
        auction:ApplySettings()
        auction:InitAutoSave()
        auction:StartEPUpdates()
        auction:CreateMinimapButton()
        auction.fullyLoaded = true
        
        if auction and auction.ApplyElvUISkin then
            auction:ApplyElvUISkin()
        end

        if auction and auction.ApplyJournalSkin then
            auction:ApplyJournalSkin()
        end
        
        if auction.pendingWorldEnter then
            auction:HandleWorldEnter()
            auction.pendingWorldEnter = nil
        end
        auction:Debug("Аддон загружен")
        
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
        auction:ScheduleTimer(function()
            local playerName = UnitName("player")
            if not IsInRaid() and not IsInGroup() then
                if auction.lastLM or next(auction.lastVersions) or next(auction.dataVersions) then
                    auction:ResetVersionsOnGroupExit()
                end
                auction:UpdateLockCheckbox()
                auction:UpdateLMButtonsState()
                return
            end
            if auction:IsLootMaster() then
                if auction.lastLM ~= playerName then
                    auction.lastLM = playerName
                    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Вы теперь Loot Master")
                    auction:UpdateLockCheckbox()
                    if auction.selectedBoss then
                        auction:RefreshTable()
                    end
                    SendAddonMessage(auction.prefix, "LM", "RAID")
                    auction:ScheduleTimer(function()
                        auction:SyncAllToRaid()
                    end, 2)
                end
            else
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
                    auction:ScheduleTimer(function()
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

    elseif event == "PLAYER_LOGOUT" then
        if auction.fullyLoaded then
            auction:SaveData()
            auction:Debug("Сохранение при выходе")
        end

    elseif event == "EPGP_UPDATE" or event == "EPGP_DATA_CHANGED" then
        if auction.fullyLoaded then
            auction:Debug("Получено обновление от EPGP")
            auction:CheckAndUpdateEP()
        end
    end
end)
