local auction = EPBossAuction

auction.theme = {
    colors = {
        panel = {0.07, 0.09, 0.12, 0.95},
        border = {0.18, 0.22, 0.30, 1},
        button = {0.16, 0.20, 0.28, 0.95},
        buttonHover = {0.22, 0.30, 0.42, 1},
        buttonDisabled = {0.10, 0.12, 0.16, 0.8},
        accent = {0.35, 0.65, 1.0, 1},
        inputBg = {0.05, 0.06, 0.09, 1},
    },
    symbols = {
        font = "Interface\\AddOns\\EPBossAuction\\fonts\\DejaVuSans.ttf",
        check = "✓",
        arrowDown = "▼",
    },
}

function auction:HideDefaultTextures(frame)
    if not frame then return end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region and region.GetObjectType and region:GetObjectType() == "Texture" then
            region:SetTexture(nil)
            region:SetAlpha(0)
            region:Hide()
        end
    end
end

function auction:SkinPanel(frame)
    if not frame then return end
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    local c = self.theme.colors
    frame:SetBackdropColor(c.panel[1], c.panel[2], c.panel[3], c.panel[4])
    frame:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], c.border[4])
end

function auction:SkinButton(button)
    if not button or button._epbaSkinned then return end
    local c = self.theme.colors
    button:SetNormalTexture("")
    button:SetHighlightTexture("")
    button:SetPushedTexture("")
    button:SetDisabledTexture("")
    self:HideDefaultTextures(button)

    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    button:SetBackdropColor(c.button[1], c.button[2], c.button[3], c.button[4])
    button:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], c.border[4])

    button:HookScript("OnEnter", function(btn)
        if btn:IsEnabled() then
            btn:SetBackdropColor(c.buttonHover[1], c.buttonHover[2], c.buttonHover[3], c.buttonHover[4])
        end
    end)
    button:HookScript("OnLeave", function(btn)
        if btn:IsEnabled() then
            btn:SetBackdropColor(c.button[1], c.button[2], c.button[3], c.button[4])
        else
            btn:SetBackdropColor(c.buttonDisabled[1], c.buttonDisabled[2], c.buttonDisabled[3], c.buttonDisabled[4])
        end
    end)
    button:HookScript("OnDisable", function(btn)
        btn:SetBackdropColor(c.buttonDisabled[1], c.buttonDisabled[2], c.buttonDisabled[3], c.buttonDisabled[4])
    end)
    button:HookScript("OnEnable", function(btn)
        btn:SetBackdropColor(c.button[1], c.button[2], c.button[3], c.button[4])
    end)

    button._epbaSkinned = true
end

function auction:SkinInput(editBox)
    if not editBox or editBox._epbaSkinned then return end
    local c = self.theme.colors
    self:HideDefaultTextures(editBox)
    editBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    editBox:SetBackdropColor(c.inputBg[1], c.inputBg[2], c.inputBg[3], c.inputBg[4])
    editBox:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], c.border[4])
    editBox:HookScript("OnEditFocusGained", function(box)
        box:SetBackdropBorderColor(c.accent[1], c.accent[2], c.accent[3], c.accent[4])
    end)
    editBox:HookScript("OnEditFocusLost", function(box)
        box:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], c.border[4])
    end)
    editBox._epbaSkinned = true
end


function auction:SkinCheckbox(checkbox)
    if not checkbox or checkbox._epbaSkinned then return end
    local c = self.theme.colors
    self:HideDefaultTextures(checkbox)

    checkbox:SetNormalTexture("")
    checkbox:SetPushedTexture("")
    checkbox:SetHighlightTexture("")
    checkbox:SetCheckedTexture("")
    checkbox:SetDisabledCheckedTexture("")

    checkbox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    checkbox:SetBackdropColor(c.inputBg[1], c.inputBg[2], c.inputBg[3], c.inputBg[4])
    checkbox:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], c.border[4])

    local mark = checkbox:CreateFontString(nil, "OVERLAY")
    mark:SetPoint("CENTER", 0, -1)
    local symbolFont = (self.theme.symbols and self.theme.symbols.font) or ""
    local ok = symbolFont ~= "" and mark:SetFont(symbolFont, 14, "OUTLINE")
    if ok then
        mark:SetText((self.theme.symbols and self.theme.symbols.check) or "✓")
    else
        mark = checkbox:CreateTexture(nil, "OVERLAY")
        mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        mark:SetPoint("CENTER", 0, 0)
        mark:SetSize(14, 14)
    end
    mark:Hide()
    checkbox._epbaMark = mark

    local function RefreshState(box)
        if box:GetChecked() then
            box._epbaMark:Show()
            box:SetBackdropBorderColor(c.accent[1], c.accent[2], c.accent[3], c.accent[4])
        else
            box._epbaMark:Hide()
            box:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], c.border[4])
        end
    end

    checkbox:HookScript("OnClick", RefreshState)
    checkbox:HookScript("OnShow", RefreshState)
    checkbox:HookScript("OnDisable", function(box)
        box:SetBackdropColor(c.buttonDisabled[1], c.buttonDisabled[2], c.buttonDisabled[3], c.buttonDisabled[4])
    end)
    checkbox:HookScript("OnEnable", function(box)
        box:SetBackdropColor(c.inputBg[1], c.inputBg[2], c.inputBg[3], c.inputBg[4])
        RefreshState(box)
    end)

    RefreshState(checkbox)
    checkbox._epbaSkinned = true
end

function auction:SkinDropdown(dropdown)
    if not dropdown or dropdown._epbaSkinned then return end
    local c = self.theme.colors
    self:HideDefaultTextures(dropdown)

    local name = dropdown.GetName and dropdown:GetName()
    if name then
        local left = _G[name .. "Left"]
        local middle = _G[name .. "Middle"]
        local right = _G[name .. "Right"]
        if left then left:Hide() end
        if middle then middle:Hide() end
        if right then right:Hide() end

        local button = _G[name .. "Button"]
        if button then
            self:HideDefaultTextures(button)
            self:SkinButton(button)
            button:ClearAllPoints()
            button:SetPoint("RIGHT", dropdown, "RIGHT", -2, 0)
            button:SetSize(20, 20)
            local arrow = button:CreateFontString(nil, "OVERLAY")
            arrow:SetPoint("CENTER", 0, -1)
            local symbolFont = (self.theme.symbols and self.theme.symbols.font) or ""
            local ok = symbolFont ~= "" and arrow:SetFont(symbolFont, 14, "OUTLINE")
            if ok then
                arrow:SetText((self.theme.symbols and self.theme.symbols.arrowDown) or "▼")
            else
                arrow = button:CreateTexture(nil, "OVERLAY")
                arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
                arrow:SetPoint("CENTER", 0, 0)
                arrow:SetSize(14, 14)
            end
        end
    end

    dropdown:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    dropdown:SetBackdropColor(c.inputBg[1], c.inputBg[2], c.inputBg[3], c.inputBg[4])
    dropdown:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], c.border[4])

    local text = name and _G[name .. "Text"]
    if text then
        text:ClearAllPoints()
        text:SetPoint("LEFT", dropdown, "LEFT", 8, 1)
        text:SetPoint("RIGHT", dropdown, "RIGHT", -24, 1)
        text:SetJustifyH("LEFT")
    end

    dropdown._epbaSkinned = true
end
