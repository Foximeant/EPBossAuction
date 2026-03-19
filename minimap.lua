local auction = EPBossAuction

function auction:CreateMinimapButton()
    if self.minimapButton then return end

    local button = CreateFrame("Button", "EPBAMinimapButton", Minimap)
    button:SetSize(self.db.minimap.size, self.db.minimap.size)
    button:SetFrameStrata(self.db.minimap.strata)
    button:SetMovable(true)
    button:EnableMouse(true)
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

    -- Текстура (замените на свою при необходимости)
    local texture = button:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    texture:SetTexture("Interface\\AddOns\\EPBossAuction\\icon.tga") -- путь к иконке

    -- Обработчик клика
    button:SetScript("OnClick", function()
        if auction.frame:IsShown() then
            auction.frame:Hide()
        else
            auction.frame:Show()
        end
    end)

    -- Перетаскивание
    local isDragging = false
    button:SetScript("OnDragStart", function(self)
        isDragging = true
        self:SetScript("OnUpdate", function(self)
            if not isDragging then return end
            local cursorX, cursorY = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            cursorX = cursorX / scale
            cursorY = cursorY / scale
            local minimapCenterX, minimapCenterY = Minimap:GetCenter()
            local newX = cursorX - minimapCenterX
            local newY = cursorY - minimapCenterY
            local maxDist = auction.db.minimap.radius
            local dist = math.sqrt(newX*newX + newY*newY)
            if dist > maxDist then
                newX = newX / dist * maxDist
                newY = newY / dist * maxDist
            end
            self:SetPoint("CENTER", Minimap, "CENTER", newX, newY)
            local angle = math.deg(math.atan2(newY, newX))
            auction.db.minimap.position.angle = angle
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        isDragging = false
        self:SetScript("OnUpdate", nil)
        auction:SaveSettings()
    end)

    -- Тултип
    if self.db.minimap.tooltip then
        button:SetScript("OnEnter", function()
            GameTooltip:SetOwner(button, "ANCHOR_LEFT")
            GameTooltip:AddLine("EP Boss Auction")
            GameTooltip:AddLine("Нажмите для открытия окна", 0.5, 1, 0.5)
            if auction:IsLootMaster() then
                GameTooltip:AddLine("Вы Loot Master", 1, 1, 0)
            else
                GameTooltip:AddLine("Вы не Loot Master", 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    -- Установка позиции
    local angle = self.db.minimap.position.angle or 0
    local x = self.db.minimap.radius * math.cos(math.rad(angle))
    local y = self.db.minimap.radius * math.sin(math.rad(angle))
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)

    if not self.db.minimap.show then
        button:Hide()
    end

    self.minimapButton = button
    self:Debug("Кнопка миникарты создана")
end