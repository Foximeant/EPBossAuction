local auction = EPBossAuction

-- ============================================================
-- contacts.lua — окно "Сообщить о проблеме" (контакты для обратной связи)
-- ============================================================
-- Показывает ссылку на GitHub Issues и ник в Discord в полях, из которых
-- можно скопировать текст по Ctrl+C (WoW не умеет открывать браузер из
-- аддона). Третье поле — строка диагностики (версия, клиент, роль, босс):
-- игрок вставляет её в сообщение о баге, и не приходится переспрашивать.
-- Открывается командой /epba bug (подсказка есть в тултипе кнопки миникарты).
-- ============================================================

-- Контакты, которые увидят игроки.
auction.contacts = {
    github  = "https://github.com/Foximeant/EPBossAuction/issues",
    discord = "lieline",
}

-- Короткая строка с состоянием аддона и клиента — для вставки в репорт.
function auction:GetDiagnosticsString()
    local clientVersion, clientBuild = GetBuildInfo()
    local group = "соло"
    if IsInRaid() then
        group = "рейд"
    elseif IsInGroup() then
        group = "группа"
    end
    return string.format("EPBA %s | клиент %s (%s) | %s | ЛМ: %s | офицер: %s | босс: %s",
        tostring(self.version),
        tostring(clientVersion), tostring(clientBuild),
        group,
        self:IsLootMaster() and "да" or "нет",
        self:CanRecordAttendance() and "да" or "нет",
        self.selectedBoss or "—")
end

-- Строка-метка + поле для копирования. Текст в поле нельзя изменить
-- (любая правка откатывается), но выделить и скопировать можно.
local function CreateCopyField(auction, parent, labelText, anchorTo, offsetY)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, offsetY)
    label:SetText(labelText)

    local box = CreateFrame("EditBox", nil, parent)
    box:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    box:SetSize(parent:GetWidth() - 40, 24)
    box:SetAutoFocus(false)
    box:SetFontObject(GameFontHighlight)
    box:SetTextInsets(6, 6, 0, 0)
    auction:SkinInput(box)

    box.SetValue = function(self, text)
        self._value = text or ""
        self:SetText(self._value)
        self:SetCursorPosition(0)
    end
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput and self:GetText() ~= self._value then
            self:SetText(self._value)
            self:HighlightText()
        end
    end)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    return label, box
end

-- Строит (один раз) и показывает/скрывает окно контактов.
function auction:ShowContactsWindow()
    if self.contactsFrame then
        if self.contactsFrame:IsShown() then
            self.contactsFrame:Hide()
            return
        end
    else
        local c = self.theme.colors
        local frame = CreateFrame("Frame", "EPBossAuctionContactsFrame", UIParent)
        frame:SetSize(440, 300)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        self:SkinPanel(frame)
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        tinsert(UISpecialFrames, "EPBossAuctionContactsFrame") -- закрытие по Esc

        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -16)
        title:SetText("Сообщить о проблеме")
        title:SetTextColor(c.accent[1], c.accent[2], c.accent[3])

        local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
        hint:SetText("Нажмите на поле и скопируйте текст (Ctrl+C)")

        -- Якорь-пустышка для первого поля
        local anchor = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        anchor:SetPoint("TOPLEFT", 20, -66)
        anchor:SetText("")

        local _, githubBox = CreateCopyField(self, frame, "GitHub (Issues):", anchor, 0)
        local _, discordBox = CreateCopyField(self, frame, "Discord:", githubBox, -12)
        local _, diagBox = CreateCopyField(self, frame, "Диагностика — вставьте в сообщение о баге:", discordBox, -12)

        frame.githubBox, frame.discordBox, frame.diagBox = githubBox, discordBox, diagBox

        local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        closeButton:SetSize(120, 24)
        closeButton:SetPoint("BOTTOM", 70, 16)
        closeButton:SetText("Закрыть")
        self:SkinButton(closeButton)
        closeButton:SetScript("OnClick", function() frame:Hide() end)

        -- Полная диагностика (diag.lua): сводка, проверки, журнал, сеть, ошибки, опрос рейда
        local diagButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        diagButton:SetSize(150, 24)
        diagButton:SetPoint("BOTTOM", -70, 16)
        diagButton:SetText("Полная диагностика")
        self:SkinButton(diagButton)
        diagButton:SetScript("OnClick", function()
            frame:Hide()
            if auction.DiagCommand then auction:DiagCommand("") end
        end)

        self.contactsFrame = frame
    end

    local frame = self.contactsFrame
    frame.githubBox:SetValue(self.contacts.github)
    frame.discordBox:SetValue(self.contacts.discord)
    frame.diagBox:SetValue(self:GetDiagnosticsString()) -- обновляем при каждом открытии
    frame:Show()
end
