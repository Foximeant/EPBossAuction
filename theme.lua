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

function auction:SkinIconButton(button)
    if not button or button._epbaSkinned then return end
    local c = self.theme.colors
    button:SetNormalTexture("")
    button:SetHighlightTexture("")
    button:SetPushedTexture("")
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    button:SetBackdropColor(c.button[1], c.button[2], c.button[3], c.button[4])
    button:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], c.border[4])
    button:HookScript("OnEnter", function(btn) btn:SetBackdropColor(c.buttonHover[1], c.buttonHover[2], c.buttonHover[3], c.buttonHover[4]) end)
    button:HookScript("OnLeave", function(btn) btn:SetBackdropColor(c.button[1], c.button[2], c.button[3], c.button[4]) end)
    button._epbaSkinned = true
end

function auction:SkinInput(editBox)
    if not editBox then return end
    local c = self.theme.colors
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
    if not dropdown or dropdown._epbaSkinned then return end

    local c = self.theme.colors
    local left = _G[dropdown:GetName() .. "Left"]
    local middle = _G[dropdown:GetName() .. "Middle"]
    local right = _G[dropdown:GetName() .. "Right"]
    local button = _G[dropdown:GetName() .. "Button"]

    if left then left:Hide() end
    if middle then middle:Hide() end
    if right then right:Hide() end
    if left then left.Show = function() end end
    if middle then middle.Show = function() end end
    if right then right.Show = function() end end
    for _, region in ipairs({ dropdown:GetRegions() }) do
        if region and region:GetObjectType() == "Texture" then
            region:SetAlpha(0)
            region.Show = function() end
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

    if button then
        button:ClearAllPoints()
        button:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT", -16, -3)
        button:SetPoint("BOTTOMRIGHT", dropdown, "BOTTOMRIGHT", -16, 7)
        button:SetWidth(24)
        local normal = button:GetNormalTexture()
        if normal then
            normal:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
            normal:SetTexCoord(0, 1, 0, 1)
        end
        local pushed = button:GetPushedTexture()
        if pushed then pushed:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down") end
        local disabled = button:GetDisabledTexture()
        if disabled then disabled:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Disabled") end
        local highlight = button:GetHighlightTexture()
        if highlight then highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square") end
    end

    dropdown._epbaSkinned = true
end

function auction:SkinCheckbox(checkBox)
    if not checkBox or checkBox._epbaSkinned then return end

    local c = self.theme.colors
    local name = checkBox:GetName()
    local normal = name and _G[name .. "NormalTexture"]
    local pushed = name and _G[name .. "PushedTexture"]
    local highlight = name and _G[name .. "HighlightTexture"]
    local checked = name and _G[name .. "CheckedTexture"]
    local disabledChecked = name and _G[name .. "DisabledCheckedTexture"]

    if normal then normal:SetTexture("") end
    if pushed then pushed:SetTexture("") end
    if highlight then highlight:SetTexture("") end
    if normal then normal.Show = function() end end
    if pushed then pushed.Show = function() end end
    if highlight then highlight.Show = function() end end

    checkBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    checkBox:SetBackdropColor(c.inputBg[1], c.inputBg[2], c.inputBg[3], c.inputBg[4])
    checkBox:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], c.border[4])

    if checked then
        checked:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        checked:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        checked:ClearAllPoints()
        checked:SetPoint("CENTER", checkBox, "CENTER", 0, 0)
        checked:SetSize(14, 14)
    end
    if disabledChecked then
        disabledChecked:SetTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
        disabledChecked:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    checkBox:HookScript("OnEnter", function(box)
        box:SetBackdropBorderColor(c.accent[1], c.accent[2], c.accent[3], c.accent[4])
    end)
    checkBox:HookScript("OnLeave", function(box)
        box:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], c.border[4])
    end)

    checkBox._epbaSkinned = true
end

function auction:SkinScrollBar(scrollBar)
    if not scrollBar or scrollBar._epbaSkinned then return end
    local c = self.theme.colors
    local up = _G[scrollBar:GetName() .. "ScrollUpButton"]
    local down = _G[scrollBar:GetName() .. "ScrollDownButton"]
    local thumb = _G[scrollBar:GetName() .. "ThumbTexture"]
    local bg = _G[scrollBar:GetName() .. "BG"]

    if bg then
        bg:SetTexture("")
        bg:Hide()
        bg.Show = function() end
    end

    scrollBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    scrollBar:SetBackdropColor(c.inputBg[1], c.inputBg[2], c.inputBg[3], 0.7)
    scrollBar:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], c.border[4])

    if thumb then
        thumb:SetTexture("Interface\\Buttons\\WHITE8x8")
        thumb:SetVertexColor(c.accent[1], c.accent[2], c.accent[3], 0.85)
        thumb:SetWidth(8)
    end
    if up then
        self:SkinIconButton(up)
        local upNormal = up:GetNormalTexture()
        if upNormal then upNormal:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up") end
        local upPushed = up:GetPushedTexture()
        if upPushed then upPushed:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down") end
    end
    if down then
        self:SkinIconButton(down)
        local downNormal = down:GetNormalTexture()
        if downNormal then downNormal:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up") end
        local downPushed = down:GetPushedTexture()
        if downPushed then downPushed:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down") end
    end
    scrollBar._epbaSkinned = true
end
