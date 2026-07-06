local auction = EPBossAuction

-- ======================
-- AceAddon lifecycle
-- ======================
-- OnInitialize срабатывает один раз при загрузке аддона — раньше это была
-- ветка ADDON_LOADED с ручной проверкой имени аддона, теперь AceAddon сам
-- гарантирует, что это вызовется ровно для EPBossAuction и ровно один раз.
function auction:OnInitialize()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r EPBossAuction "..self.version.." загружен")
    self:LoadSettings()
    self:CreateUI()
    self:CreateOptionsPanel()
    self:Debug("=== ПРОВЕРКА СОХРАНЕННЫХ ДАННЫХ ===")
    if EPBossAuctionSavedBids then
        local savedCount = 0
        for bossName, bossBids in pairs(EPBossAuctionSavedBids) do
            for itemID, bidsForItem in pairs(bossBids) do
                savedCount = savedCount + #bidsForItem
            end
        end
        self:Debug("В сохранении: "..savedCount.." ставок")
        self.bids = EPBossAuctionSavedBids
        self.dataVersions = self:NormalizeVersionTable(EPBossAuctionSavedVersions or {})
        self.lastVersions = {}
        self:RebuildBidData()

        if EPBossAuctionSavedSelectedBoss and self.bosses[EPBossAuctionSavedSelectedBoss] then
            self.selectedBoss = EPBossAuctionSavedSelectedBoss
            self:Debug("Восстановлен босс: "..self.selectedBoss)
        else
            self.selectedBoss = nil
        end

        if self.selectedBoss and EPBossAuctionSavedSelectedItem then
            local items = self.bosses[self.selectedBoss]
            local found = false
            for _, itemID in ipairs(items) do
                if itemID == EPBossAuctionSavedSelectedItem then
                    found = true
                    break
                end
            end
            if found then
                self.selectedItem = EPBossAuctionSavedSelectedItem
                self:Debug("Восстановлен предмет: "..self.selectedItem)
            else
                self.selectedItem = nil
            end
        else
            self.selectedItem = nil
        end

        if EPBossAuctionSavedScale then
            self.windowScale = EPBossAuctionSavedScale
            self.db.window.scale = EPBossAuctionSavedScale
        end

        if EPBossAuctionSavedMinimapPos then
            self.minimapButtonPosition = EPBossAuctionSavedMinimapPos
            self.db.minimap.position = EPBossAuctionSavedMinimapPos
        end

        if EPBossAuctionBidsLocked ~= nil then
            self.bidsLocked = EPBossAuctionBidsLocked
        end

        if EPBossAuctionSavedOffspecMultiplier then
            self.offspecMultiplier = EPBossAuctionSavedOffspecMultiplier
            self.db.general.offspecMultiplier = EPBossAuctionSavedOffspecMultiplier
        end
    else
        self:Debug("Нет сохраненных данных")
        self.bids = {}
        self.dataVersions = {}
        self.lastVersions = {}
        self.windowScale = 1.0
        self.bidsLocked = false
        self:RebuildBidData()
    end
    self:ApplySettings()
    self:InitAutoSave()
    self:StartEPUpdates()
    self:CreateMinimapButton()
    self.fullyLoaded = true

    if self.ApplyJournalSkin then
        self:ApplyJournalSkin()
    end

    if self.pendingWorldEnter then
        self:HandleWorldEnter()
        self.pendingWorldEnter = nil
    end
    self:Debug("Аддон загружен")

    -- Периодическая очистка устаревших уведомлений (раз в 5 минут)
    self:ScheduleTimer(function()
        self:CleanOutbidNotified()
    end, 300)
end

-- OnEnable вызывается сразу после OnInitialize (и при повторном /reload)
-- — здесь регистрируем все игровые события через AceEvent.
function auction:OnEnable()
    self:RegisterComm(self.prefix)
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("LOOT_OPENED")
    self:RegisterEvent("LOOT_CLOSED")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRosterUpdate")
    self:RegisterEvent("RAID_ROSTER_UPDATE", "OnRosterUpdate")
    self:RegisterEvent("PLAYER_LOGOUT")
    self:RegisterEvent("EPGP_UPDATE", "OnEPGPUpdate")
    self:RegisterEvent("EPGP_DATA_CHANGED", "OnEPGPUpdate")
    -- CHAT_MSG_ADDON больше не регистрируем вручную: приём сообщений по
    -- каналу аддона теперь полностью на AceComm-3.0 (см. comm.lua, там же
    -- self:RegisterComm(self.prefix)).
end

-- ======================
-- Обработчики событий
-- ======================
function auction:PLAYER_ENTERING_WORLD()
    self:Debug("PLAYER_ENTERING_WORLD (pending)")
    if not self.fullyLoaded then
        self.pendingWorldEnter = true
        return
    end
    self:HandleWorldEnter()
end

function auction:LOOT_OPENED()
    if self.fullyLoaded and self.IsLootMaster and self:IsLootMaster() then
        self:ScheduleTimer(function()
            self:ShowLootMasterWindowFromLoot()
        end, 0.1)
    end
end

function auction:LOOT_CLOSED()
    if self.lootMasterFrame then
        self.lootMasterFrame:Hide()
    end
end

function auction:OnRosterUpdate()
    if not self.fullyLoaded then return end
    self:CacheRaidClasses()
    if self.groupRosterTimer then
        self:CancelTimer(self.groupRosterTimer)
        self.groupRosterTimer = nil
    end
    self.groupRosterTimer = self:ScheduleTimer(function()
        self.groupRosterTimer = nil
        local playerName = UnitName("player")
        if not IsInRaid() and not IsInGroup() then
            if self.lastLM or next(self.lastVersions) or next(self.dataVersions) then
                self:ResetVersionsOnGroupExit()
            end
            self:UpdateLockCheckbox()
            self:UpdateLMButtonsState()
            return
        end
        if self:IsLootMaster() then
            if self.lastLM ~= playerName then
                self.lastLM = playerName
                self:UpdateLockCheckbox()
                if self.selectedBoss then
                    self:RefreshTable()
                end
                self:QueueAddonMessage("LM", "RAID")
                if self.syncAllTimer then
                    self:CancelTimer(self.syncAllTimer)
                end
                self.syncAllTimer = self:ScheduleTimer(function()
                    self.syncAllTimer = nil
                    self:SyncAllToRaid()
                end, 2)
            end
        else
            local currentLM = nil
            local method, partyIndex, raidIndex = GetLootMethod()
            if method == "master" and raidIndex then
                currentLM = GetRaidRosterInfo(raidIndex)
            end
            if currentLM and currentLM ~= self.lastLM then
                self:ResetVersionsForNewLM()
                self.lastLM = currentLM
            elseif IsInRaid() or IsInGroup() then
                self:SendToLootMaster("CHECK_VERSION")
                if self.groupHelloTimer then
                    self:CancelTimer(self.groupHelloTimer)
                    self.groupHelloTimer = nil
                end
                self.groupHelloTimer = self:ScheduleTimer(function()
                    self.groupHelloTimer = nil
                    local bossParam = ""
                    if self.selectedBoss then
                        bossParam = ";"..self.selectedBoss
                    end
                    self:SendToLootMaster("HELLO"..bossParam)
                    self:Debug("Отправлен HELLO после GROUP_ROSTER_UPDATE")
                end, 1)
            end
            self:UpdateLockCheckbox()
        end
        self:UpdateLMButtonsState()
        self:SyncMySignupsIfNeeded()

        if self.optionsPanel and self.optionsPanel:IsShown() then
            local slider = _G["EPBAOffspecMultiplierSlider"]
            if slider then
                if self:IsLootMaster() then
                    slider:Enable()
                    slider:SetAlpha(1.0)
                else
                    slider:Disable()
                    slider:SetAlpha(0.5)
                end
            end
        end
    end, 2)
end

function auction:PLAYER_LOGOUT()
    if self.fullyLoaded then
        self:SaveData()
        self:Debug("Сохранение при выходе")
    end
end

function auction:OnEPGPUpdate()
    if self.fullyLoaded then
        self:Debug("Получено обновление от EPGP")
        self:CheckAndUpdateEP()
    end
end
