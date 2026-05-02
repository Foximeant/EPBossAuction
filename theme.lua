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
    }
}

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

    if button.Left then button.Left:SetAlpha(0) end
    if button.Middle then button.Middle:SetAlpha(0) end
    if button.Right then button.Right:SetAlpha(0) end
    for i = 1, button:GetNumRegions() do
        local region = select(i, button:GetRegions())
        if region and region:GetObjectType() == "Texture" then
            region:SetTexture(nil)
            region:SetAlpha(0)
        end
    end

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
    if not editBox then return end
    local c = self.theme.colors
    for i = 1, editBox:GetNumRegions() do
        local region = select(i, editBox:GetRegions())
        if region and region:GetObjectType() == "Texture" then
            region:SetTexture(nil)
            region:SetAlpha(0)
        end
    end
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
end

function auction:SkinDropdown(dropdown)
    if not dropdown then return end
    local c = self.theme.colors
    dropdown:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    dropdown:SetBackdropColor(c.inputBg[1], c.inputBg[2], c.inputBg[3], 0.95)
    dropdown:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], c.border[4])

    local left = _G[dropdown:GetName().."Left"]
    local mid = _G[dropdown:GetName().."Middle"]
    local right = _G[dropdown:GetName().."Right"]
    if left then left:SetAlpha(0) end
    if mid then mid:SetAlpha(0) end
    if right then right:SetAlpha(0) end

    local button = _G[dropdown:GetName().."Button"]
    if button then
        button:SetNormalTexture("")
        button:SetHighlightTexture("")
        button:SetPushedTexture("")
        if not button._epbaArrow then
            local arrow = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            arrow:SetPoint("CENTER", 0, -1)
            arrow:SetText("v")
            arrow:SetTextColor(c.accent[1], c.accent[2], c.accent[3], 1)
            button._epbaArrow = arrow
        end
    end
end

function auction:SkinCheckbox(check)
    if not check then return end
    local c = self.theme.colors
    for i = 1, check:GetNumRegions() do
        local region = select(i, check:GetRegions())
        if region and region:GetObjectType() == "Texture" then
            region:SetTexture(nil)
            region:SetAlpha(0)
        end
    end

    check:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    check:SetBackdropColor(c.inputBg[1], c.inputBg[2], c.inputBg[3], 1)
    check:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], c.border[4])

    if not check._epbaCheck then
        local mark = check:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        mark:SetPoint("CENTER", 0, 0)
        mark:SetText("X")
        mark:SetTextColor(c.accent[1], c.accent[2], c.accent[3], 1)
        check._epbaCheck = mark
    end
    local function UpdateMark(box)
        if box:GetChecked() then box._epbaCheck:Show() else box._epbaCheck:Hide() end
    end
    check:HookScript("OnClick", UpdateMark)
    check:HookScript("OnShow", UpdateMark)
    UpdateMark(check)
end
