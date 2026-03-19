local auction = EPBossAuction

function auction:CreateOptionsPanel()
    -- Создаём панель
    local panel = CreateFrame("Frame", "EPBossAuctionOptionsPanel", UIParent)
    panel.name = "EP Boss Auction"
    panel:Hide()
    
    -- Заголовок
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("EP Boss Auction - Настройки")
    
    -- Создаём контейнер для вкладок
    local tabContainer = CreateFrame("Frame", nil, panel)
    tabContainer:SetPoint("TOPLEFT", 16, -50)
    tabContainer:SetSize(600, 25)
    
    -- Создаём контейнер для содержимого вкладок с прокруткой
    local contentContainer = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    contentContainer:SetPoint("TOPLEFT", tabContainer, "BOTTOMLEFT", 0, -10)
    contentContainer:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 50)
    contentContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    contentContainer:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    contentContainer:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    self.contentContainer = contentContainer   -- сохраняем для скина

    -- Дочерний фрейм для содержимого
    local contentChild = CreateFrame("Frame", nil, contentContainer)
    contentChild:SetSize(560, 800)
    contentContainer:SetScrollChild(contentChild)
    
    -- ----------------------------------------------
    -- Вкладка "Общие" 
    -- ----------------------------------------------
    local generalTab = CreateFrame("Frame", nil, contentChild)
    generalTab:SetPoint("TOPLEFT", 10, -10)
    generalTab:SetSize(540, 400)
    self.generalTab = generalTab   -- сохраняем для скина

    -- Отладка
    local debugCheck = CreateFrame("CheckButton", "EPBADebugCheck", generalTab, "UICheckButtonTemplate")
    debugCheck:SetPoint("TOPLEFT", 10, -10)
    debugCheck.text = _G[debugCheck:GetName() .. "Text"]
    debugCheck.text:SetText("Режим отладки")
    debugCheck:SetChecked(self.db.general.debug)
    debugCheck:SetScript("OnClick", function(self)
        auction.db.general.debug = self:GetChecked()
        auction:ApplySettings()
    end)
    
    -- Минимальная ставка (неактивная)
    local minBidText = generalTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    minBidText:SetPoint("TOPLEFT", debugCheck, "BOTTOMLEFT", 0, -15)
    minBidText:SetText("Минимальная ставка:")
    minBidText:SetWidth(120)
    
    local minBidEdit = CreateFrame("EditBox", nil, generalTab, "InputBoxTemplate")
    minBidEdit:SetSize(100, 25)
    minBidEdit:SetPoint("LEFT", minBidText, "RIGHT", 10, 0)
    minBidEdit:SetAutoFocus(false)
    minBidEdit:SetNumeric(true)
    minBidEdit:SetText(self.db.general.minBid)
    minBidEdit:Disable()
    minBidEdit:SetTextColor(0.5, 0.5, 0.5)
    minBidEdit:SetScript("OnEnterPressed", nil)
    minBidEdit:SetScript("OnEditFocusLost", nil)
    
    -- Автозапрос данных
    local autoRequestCheck = CreateFrame("CheckButton", "EPBAAutoRequestCheck", generalTab, "UICheckButtonTemplate")
    autoRequestCheck:SetPoint("TOPLEFT", minBidText, "BOTTOMLEFT", 0, -15)
    autoRequestCheck.text = _G[autoRequestCheck:GetName() .. "Text"]
    autoRequestCheck.text:SetText("Автоматически запрашивать данные при входе в рейд")
    autoRequestCheck:SetChecked(self.db.general.autoRequest)
    autoRequestCheck:SetScript("OnClick", function(self)
        auction.db.general.autoRequest = self:GetChecked()
        auction:ApplySettings()
    end)
    
    -- Подтверждение ставок
    local confirmBidCheck = CreateFrame("CheckButton", "EPBAConfirmBidCheck", generalTab, "UICheckButtonTemplate")
    confirmBidCheck:SetPoint("TOPLEFT", autoRequestCheck, "BOTTOMLEFT", 0, -5)
    confirmBidCheck.text = _G[confirmBidCheck:GetName() .. "Text"]
    confirmBidCheck.text:SetText("Подтверждать ставки")
    confirmBidCheck:SetChecked(self.db.general.confirmBid)
    confirmBidCheck:SetScript("OnClick", function(self)
        auction.db.general.confirmBid = self:GetChecked()
        auction:ApplySettings()
    end)
    
    -- Звук
    local soundCheck = CreateFrame("CheckButton", "EPBASoundCheck", generalTab, "UICheckButtonTemplate")
    soundCheck:SetPoint("TOPLEFT", confirmBidCheck, "BOTTOMLEFT", 0, -5)
    soundCheck.text = _G[soundCheck:GetName() .. "Text"]
    soundCheck.text:SetText("Включить звук при ставке")
    soundCheck:SetChecked(self.db.general.soundEnabled)
    soundCheck:SetScript("OnClick", function(self)
        auction.db.general.soundEnabled = self:GetChecked()
        auction:ApplySettings()
    end)
    
    -- ----------------------------------------------
    -- Вкладка "Таблица"
    -- ----------------------------------------------
    local tableTab = CreateFrame("Frame", nil, contentChild)
    tableTab:SetPoint("TOPLEFT", 10, -10)
    tableTab:SetSize(540, 400)
    tableTab:Hide()
    self.tableTab = tableTab

    -- Заголовок "Названия предметов"
    local itemTitle = tableTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemTitle:SetPoint("TOPLEFT", 10, -10)
    itemTitle:SetText("Названия предметов:")
    itemTitle:SetFontObject(GameFontNormalLarge)
    
    -- Размер шрифта предметов
    local itemFontSizeText = tableTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemFontSizeText:SetPoint("TOPLEFT", itemTitle, "BOTTOMLEFT", 0, -20)
    itemFontSizeText:SetText("Размер шрифта:")
    itemFontSizeText:SetWidth(100)
    
    local itemFontSizeSlider = CreateFrame("Slider", "EPBAItemFontSizeSlider", tableTab, "OptionsSliderTemplate")
    itemFontSizeSlider:SetPoint("LEFT", itemFontSizeText, "RIGHT", 10, 0)
    itemFontSizeSlider:SetSize(150, 15)
    itemFontSizeSlider:SetMinMaxValues(8, 16)
    itemFontSizeSlider:SetValueStep(1)
    itemFontSizeSlider:SetValue(self.db.table.itemFontSize)
    
    local sliderName = itemFontSizeSlider:GetName()
    local lowText = _G[sliderName .. "Low"]
    local highText = _G[sliderName .. "High"]
    local valueText = _G[sliderName .. "Text"]
    if lowText then lowText:SetText("8") end
    if highText then highText:SetText("16") end
    if valueText then valueText:SetText(self.db.table.itemFontSize) end
    
    itemFontSizeSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        local vt = _G[self:GetName() .. "Text"]
        if vt then vt:SetText(value) end
        auction.db.table.itemFontSize = value
        auction:ApplySettings()
    end)
    
    -- Ширина колонки предметов
    local itemWidthText = tableTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemWidthText:SetPoint("TOPLEFT", itemFontSizeText, "BOTTOMLEFT", 0, -20)
    itemWidthText:SetText("Ширина колонки:")
    itemWidthText:SetWidth(100)
    
    local itemWidthSlider = CreateFrame("Slider", "EPBAItemWidthSlider", tableTab, "OptionsSliderTemplate")
    itemWidthSlider:SetPoint("LEFT", itemWidthText, "RIGHT", 10, 0)
    itemWidthSlider:SetSize(150, 15)
    itemWidthSlider:SetMinMaxValues(150, 350)
    itemWidthSlider:SetValueStep(10)
    itemWidthSlider:SetValue(self.db.table.itemWidth)
    
    sliderName = itemWidthSlider:GetName()
    lowText = _G[sliderName .. "Low"]
    highText = _G[sliderName .. "High"]
    valueText = _G[sliderName .. "Text"]
    if lowText then lowText:SetText("150") end
    if highText then highText:SetText("350") end
    if valueText then valueText:SetText(self.db.table.itemWidth) end
    
    itemWidthSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        local vt = _G[self:GetName() .. "Text"]
        if vt then vt:SetText(value) end
        auction.db.table.itemWidth = value
        auction:ApplySettings()
    end)
    
    -- Заголовок "Ставки"
    local bidTitle = tableTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bidTitle:SetPoint("TOPLEFT", itemWidthText, "BOTTOMLEFT", 0, -30)
    bidTitle:SetText("Ставки:")
    bidTitle:SetFontObject(GameFontNormalLarge)
    
    -- Размер шрифта ставок
    local bidFontSizeText = tableTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bidFontSizeText:SetPoint("TOPLEFT", bidTitle, "BOTTOMLEFT", 0, -20)
    bidFontSizeText:SetText("Размер шрифта:")
    bidFontSizeText:SetWidth(100)
    
    local bidFontSizeSlider = CreateFrame("Slider", "EPBABidFontSizeSlider", tableTab, "OptionsSliderTemplate")
    bidFontSizeSlider:SetPoint("LEFT", bidFontSizeText, "RIGHT", 10, 0)
    bidFontSizeSlider:SetSize(150, 15)
    bidFontSizeSlider:SetMinMaxValues(8, 16)
    bidFontSizeSlider:SetValueStep(1)
    bidFontSizeSlider:SetValue(self.db.table.bidFontSize)
    
    sliderName = bidFontSizeSlider:GetName()
    lowText = _G[sliderName .. "Low"]
    highText = _G[sliderName .. "High"]
    valueText = _G[sliderName .. "Text"]
    if lowText then lowText:SetText("8") end
    if highText then highText:SetText("16") end
    if valueText then valueText:SetText(self.db.table.bidFontSize) end
    
    bidFontSizeSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        local vt = _G[self:GetName() .. "Text"]
        if vt then vt:SetText(value) end
        auction.db.table.bidFontSize = value
        auction:ApplySettings()
    end)
    
    -- Количество показываемых ставок
    local topBidsText = tableTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    topBidsText:SetPoint("TOPLEFT", bidFontSizeText, "BOTTOMLEFT", 0, -20)
    topBidsText:SetText("Показывать ставок:")
    topBidsText:SetWidth(120)
    
    local topBidsSlider = CreateFrame("Slider", "EPBATopBidsSlider", tableTab, "OptionsSliderTemplate")
    topBidsSlider:SetPoint("LEFT", topBidsText, "RIGHT", 10, 0)
    topBidsSlider:SetSize(150, 15)
    topBidsSlider:SetMinMaxValues(1, 5)
    topBidsSlider:SetValueStep(1)
    topBidsSlider:SetValue(self.db.table.showTopBids)
    
    sliderName = topBidsSlider:GetName()
    lowText = _G[sliderName .. "Low"]
    highText = _G[sliderName .. "High"]
    valueText = _G[sliderName .. "Text"]
    if lowText then lowText:SetText("1") end
    if highText then highText:SetText("5") end
    if valueText then valueText:SetText(self.db.table.showTopBids) end
    
    topBidsSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        local vt = _G[self:GetName() .. "Text"]
        if vt then vt:SetText(value) end
        auction.db.table.showTopBids = value
        auction:ApplySettings()
    end)

     -- Высота строки
    local rowHeightTitle = tableTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rowHeightTitle:SetPoint("TOPLEFT", topBidsText, "BOTTOMLEFT", 0, -30)
    rowHeightTitle:SetText("Высота строки:")
    rowHeightTitle:SetFontObject(GameFontNormalLarge)

    local rowHeightText = tableTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rowHeightText:SetPoint("TOPLEFT", rowHeightTitle, "BOTTOMLEFT", 0, -15)
    rowHeightText:SetText("Высота (пикс):")
    rowHeightText:SetWidth(100)

    local rowHeightSlider = CreateFrame("Slider", "EPBARowHeightSlider", tableTab, "OptionsSliderTemplate")
    rowHeightSlider:SetPoint("LEFT", rowHeightText, "RIGHT", 10, 0)
    rowHeightSlider:SetSize(150, 15)
    rowHeightSlider:SetMinMaxValues(20, 60)  -- от 20 до 60 пикселей
    rowHeightSlider:SetValueStep(2)
    rowHeightSlider:SetValue(self.db.table.rowHeight)

    local sliderName = rowHeightSlider:GetName()
    local lowText = _G[sliderName .. "Low"]
    local highText = _G[sliderName .. "High"]
    local valueText = _G[sliderName .. "Text"]
    if lowText then lowText:SetText("20") end
    if highText then highText:SetText("60") end
    if valueText then valueText:SetText(self.db.table.rowHeight) end

    rowHeightSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        local vt = _G[self:GetName() .. "Text"]
        if vt then vt:SetText(value) end
        auction.db.table.rowHeight = value
        auction:ApplySettings()
    end)
    
    -- Цвет названий предметов
    local colorTitle = tableTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colorTitle:SetPoint("TOPLEFT", rowHeightText, "BOTTOMLEFT", 0, -30)
    colorTitle:SetText("Цвет названий:")
    colorTitle:SetFontObject(GameFontNormalLarge)

    local colorModeText = tableTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colorModeText:SetPoint("TOPLEFT", colorTitle, "BOTTOMLEFT", 0, -15)
    colorModeText:SetText("Режим цвета:")
    colorModeText:SetWidth(80)

    local colorModeDropdown = CreateFrame("Frame", "EPBAColorModeDropdown", tableTab, "UIDropDownMenuTemplate")
    colorModeDropdown:SetPoint("LEFT", colorModeText, "RIGHT", 10, 0)
    UIDropDownMenu_SetWidth(colorModeDropdown, 100)
    local currentMode = self.db.table.itemColorMode or "gold"
    UIDropDownMenu_SetText(colorModeDropdown, currentMode == "gold" and "Золотой" or "По редкости")
    UIDropDownMenu_Initialize(colorModeDropdown, function()
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Золотой"
        info.func = function() auction.db.table.itemColorMode = "gold"; UIDropDownMenu_SetText(colorModeDropdown, "Золотой"); auction:ApplySettings() end
        info.checked = auction.db.table.itemColorMode == "gold"
        UIDropDownMenu_AddButton(info)
        info = UIDropDownMenu_CreateInfo()
        info.text = "По редкости"
        info.func = function() auction.db.table.itemColorMode = "quality"; UIDropDownMenu_SetText(colorModeDropdown, "По редкости"); auction:ApplySettings() end
        info.checked = auction.db.table.itemColorMode == "quality"
        UIDropDownMenu_AddButton(info)
    end)

        -- Привязка тултипа
    local tooltipTitle = tableTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tooltipTitle:SetPoint("TOPLEFT", colorModeText, "BOTTOMLEFT", -20, -30)
    tooltipTitle:SetText("Тултип:")
    tooltipTitle:SetFontObject(GameFontNormalLarge)

    local tooltipAnchorText = tableTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tooltipAnchorText:SetPoint("TOPLEFT", tooltipTitle, "BOTTOMLEFT", 0, -15)
    tooltipAnchorText:SetText("Привязка:")
    tooltipAnchorText:SetWidth(80)

    local tooltipAnchorDropdown = CreateFrame("Frame", "EPBATooltipAnchorDropdown", tableTab, "UIDropDownMenuTemplate")
    tooltipAnchorDropdown:SetPoint("LEFT", tooltipAnchorText, "RIGHT", 10, 0)
    UIDropDownMenu_SetWidth(tooltipAnchorDropdown, 120)

    -- Функция для получения локализованного названия
    local anchorNames = {
        CURSOR = "У курсора",
        RIGHT = "Справа",
        LEFT = "Слева",
        TOP = "Сверху",
        BOTTOM = "Снизу",
        TOPRIGHT = "Сверху справа",
        TOPLEFT = "Сверху слева",
        BOTTOMRIGHT = "Снизу справа",
        BOTTOMLEFT = "Снизу слева",
    }
    local currentAnchor = self.db.table.tooltipAnchor or "CURSOR"
    UIDropDownMenu_SetText(tooltipAnchorDropdown, anchorNames[currentAnchor] or "У курсора")

    UIDropDownMenu_Initialize(tooltipAnchorDropdown, function()
        for anchor, name in pairs(anchorNames) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.func = function()
                auction.db.table.tooltipAnchor = anchor
                UIDropDownMenu_SetText(tooltipAnchorDropdown, name)
                auction:ApplySettings()
            end
            info.checked = (auction.db.table.tooltipAnchor == anchor)
            UIDropDownMenu_AddButton(info)
        end
    end)
     
    -- ----------------------------------------------
    -- Вкладка "Кнопка миникарты"
    -- ----------------------------------------------
    local minimapTab = CreateFrame("Frame", nil, contentChild)
    minimapTab:SetPoint("TOPLEFT", 10, -10)
    minimapTab:SetSize(540, 400)
    minimapTab:Hide()
    self.minimapTab = minimapTab

    -- Показывать кнопку
    local showButtonCheck = CreateFrame("CheckButton", "EPBAShowMinimapCheck", minimapTab, "UICheckButtonTemplate")
    showButtonCheck:SetPoint("TOPLEFT", 10, -10)
    showButtonCheck.text = _G[showButtonCheck:GetName() .. "Text"]
    showButtonCheck.text:SetText("Показывать кнопку у миникарты")
    showButtonCheck:SetChecked(self.db.minimap.show)
    showButtonCheck:SetScript("OnClick", function(self)
        auction.db.minimap.show = self:GetChecked()
        auction:ApplySettings()
    end)
    
    -- Размер кнопки
    local buttonSizeText = minimapTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    buttonSizeText:SetPoint("TOPLEFT", showButtonCheck, "BOTTOMLEFT", 0, -20)
    buttonSizeText:SetText("Размер кнопки:")
    buttonSizeText:SetWidth(100)
    
    local buttonSizeSlider = CreateFrame("Slider", "EPBAButtonSizeSlider", minimapTab, "OptionsSliderTemplate")
    buttonSizeSlider:SetPoint("LEFT", buttonSizeText, "RIGHT", 10, 0)
    buttonSizeSlider:SetSize(150, 15)
    buttonSizeSlider:SetMinMaxValues(20, 40)
    buttonSizeSlider:SetValueStep(1)
    buttonSizeSlider:SetValue(self.db.minimap.size)
    
    sliderName = buttonSizeSlider:GetName()
    lowText = _G[sliderName .. "Low"]
    highText = _G[sliderName .. "High"]
    valueText = _G[sliderName .. "Text"]
    if lowText then lowText:SetText("20") end
    if highText then highText:SetText("40") end
    if valueText then valueText:SetText(self.db.minimap.size) end
    
    buttonSizeSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        local vt = _G[self:GetName() .. "Text"]
        if vt then vt:SetText(value) end
        auction.db.minimap.size = value
        auction:ApplySettings()
    end)
    
    -- Радиус от центра
    local radiusText = minimapTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    radiusText:SetPoint("TOPLEFT", buttonSizeText, "BOTTOMLEFT", 0, -20)
    radiusText:SetText("Радиус от центра:")
    radiusText:SetWidth(120)
    
    local radiusSlider = CreateFrame("Slider", "EPBARadiusSlider", minimapTab, "OptionsSliderTemplate")
    radiusSlider:SetPoint("LEFT", radiusText, "RIGHT", 10, 0)
    radiusSlider:SetSize(150, 15)
    radiusSlider:SetMinMaxValues(50, 100)
    radiusSlider:SetValueStep(5)
    radiusSlider:SetValue(self.db.minimap.radius)
    
    sliderName = radiusSlider:GetName()
    lowText = _G[sliderName .. "Low"]
    highText = _G[sliderName .. "High"]
    valueText = _G[sliderName .. "Text"]
    if lowText then lowText:SetText("50") end
    if highText then highText:SetText("100") end
    if valueText then valueText:SetText(self.db.minimap.radius) end
    
    radiusSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        local vt = _G[self:GetName() .. "Text"]
        if vt then vt:SetText(value) end
        auction.db.minimap.radius = value
        auction:ApplySettings()
    end)
    
    -- Сброс позиции
    local resetPosButton = CreateFrame("Button", nil, minimapTab, "UIPanelButtonTemplate")
    resetPosButton:SetSize(120, 25)
    resetPosButton:SetPoint("TOPLEFT", radiusText, "BOTTOMLEFT", 0, -30)
    resetPosButton:SetText("Сбросить позицию")
    resetPosButton:SetScript("OnClick", function()
        auction.db.minimap.position = { angle = 0 }
        auction:ApplySettings()
    end)
    
    -- ----------------------------------------------
    -- Вкладка "Окно"
    -- ----------------------------------------------
    local windowTab = CreateFrame("Frame", nil, contentChild)
    windowTab:SetPoint("TOPLEFT", 10, -10)
    windowTab:SetSize(540, 400)
    windowTab:Hide()
    self.windowTab = windowTab

    -- Прозрачность
    local alphaText = windowTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    alphaText:SetPoint("TOPLEFT", 10, -10)
    alphaText:SetText("Прозрачность окна:")
    alphaText:SetWidth(120)
    
    local alphaSlider = CreateFrame("Slider", "EPBAAlphaSlider", windowTab, "OptionsSliderTemplate")
    alphaSlider:SetPoint("LEFT", alphaText, "RIGHT", 10, 0)
    alphaSlider:SetSize(150, 15)
    alphaSlider:SetMinMaxValues(0.3, 1.0)
    alphaSlider:SetValueStep(0.1)
    alphaSlider:SetValue(self.db.window.alpha)
    
    sliderName = alphaSlider:GetName()
    lowText = _G[sliderName .. "Low"]
    highText = _G[sliderName .. "High"]
    valueText = _G[sliderName .. "Text"]
    if lowText then lowText:SetText("30%") end
    if highText then highText:SetText("100%") end
    if valueText then valueText:SetText(math.floor(self.db.window.alpha * 100) .. "%") end
    
    alphaSlider:SetScript("OnValueChanged", function(self, value)
        if value == self.lastValue then return end
        self.lastValue = value
        local vt = _G[self:GetName() .. "Text"]
        if vt then vt:SetText(math.floor(value * 100) .. "%") end
        auction.db.window.alpha = value
        auction:ApplySettings()
    end)
    
    -- Масштаб окна (кнопки + - сброс)
    local scaleTextLabel = windowTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scaleTextLabel:SetPoint("TOPLEFT", alphaText, "BOTTOMLEFT", 0, -25)
    scaleTextLabel:SetText("Масштаб окна:")
    scaleTextLabel:SetWidth(120)
    
    local scaleValue = windowTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scaleValue:SetPoint("LEFT", scaleTextLabel, "RIGHT", 10, 0)
    scaleValue:SetWidth(60)
    scaleValue:SetJustifyH("LEFT")
    scaleValue:SetText(string.format("%d%%", self.db.window.scale * 100))
    
    local zoomOutBtn = CreateFrame("Button", nil, windowTab, "UIPanelButtonTemplate")
    zoomOutBtn:SetSize(40, 25)
    zoomOutBtn:SetPoint("LEFT", scaleValue, "RIGHT", 10, 0)
    zoomOutBtn:SetText("-")
    zoomOutBtn:SetScript("OnClick", function()
        auction:ZoomOut()
        scaleValue:SetText(string.format("%d%%", auction.windowScale * 100))
        auction.db.window.scale = auction.windowScale
    end)
    
    local resetZoomBtn = CreateFrame("Button", nil, windowTab, "UIPanelButtonTemplate")
    resetZoomBtn:SetSize(50, 25)
    resetZoomBtn:SetPoint("LEFT", zoomOutBtn, "RIGHT", 5, 0)
    resetZoomBtn:SetText("100%")
    resetZoomBtn:SetScript("OnClick", function()
        auction:ResetZoom()
        scaleValue:SetText("100%")
        auction.db.window.scale = 1.0
    end)
    
    local zoomInBtn = CreateFrame("Button", nil, windowTab, "UIPanelButtonTemplate")
    zoomInBtn:SetSize(40, 25)
    zoomInBtn:SetPoint("LEFT", resetZoomBtn, "RIGHT", 5, 0)
    zoomInBtn:SetText("+")
    zoomInBtn:SetScript("OnClick", function()
        auction:ZoomIn()
        scaleValue:SetText(string.format("%d%%", auction.windowScale * 100))
        auction.db.window.scale = auction.windowScale
    end)
    
    -- Блокировка окна
    local lockWindowCheck = CreateFrame("CheckButton", "EPBALockWindowCheck", windowTab, "UICheckButtonTemplate")
    lockWindowCheck:SetPoint("TOPLEFT", scaleTextLabel, "BOTTOMLEFT", 0, -25)
    lockWindowCheck.text = _G[lockWindowCheck:GetName() .. "Text"]
    lockWindowCheck.text:SetText("Заблокировать окно (запретить перемещение)")
    lockWindowCheck:SetChecked(self.db.window.locked)
    lockWindowCheck:SetScript("OnClick", function(self)
        auction.db.window.locked = self:GetChecked()
        auction:ApplySettings()
    end)
    
    -- Сброс позиции окна
    local resetWindowPosButton = CreateFrame("Button", nil, windowTab, "UIPanelButtonTemplate")
    resetWindowPosButton:SetSize(150, 25)
    resetWindowPosButton:SetPoint("TOPLEFT", lockWindowCheck, "BOTTOMLEFT", 0, -30)
    resetWindowPosButton:SetText("Сбросить позицию окна")
    resetWindowPosButton:SetScript("OnClick", function()
        if auction.frame then
            auction.frame:ClearAllPoints()
            auction.frame:SetPoint("CENTER")
        end
    end)
    
    -- ----------------------------------------------
    -- Кнопки вкладок
    -- ----------------------------------------------
    local tabs = {
        { text = "Общие", frame = generalTab },
        { text = "Таблица", frame = tableTab },
        { text = "Миникарта", frame = minimapTab },
        { text = "Окно", frame = windowTab },
    }
    
    local tabWidth = 100
    local tabHeight = 25
    local tabGap = 10  -- расстояние между кнопками
    local tabButtons = {}
    
    for i, tabData in ipairs(tabs) do
        local tab = CreateFrame("Button", nil, tabContainer, "UIPanelButtonTemplate")
        tab:SetSize(tabWidth, tabHeight)
        tab:SetPoint("LEFT", (i-1) * (tabWidth + tabGap), 0)
        tab:SetText(tabData.text)
        tab.frame = tabData.frame
        
        tab:SetScript("OnClick", function(self)
            for _, btn in ipairs(tabButtons) do
                btn.frame:Hide()
            end
            self.frame:Show()
        end)
        
        table.insert(tabButtons, tab)
    end
    self.optionsTabButtons = tabButtons
    
    -- Показываем первую вкладку
    if tabButtons[1] then
        tabButtons[1]:GetScript("OnClick")(tabButtons[1])
    end
    
    -- Кнопки внизу панели
    local defaultsButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    self.optionsDefaultsBtn = defaultsButton
    defaultsButton:SetSize(120, 25)
    defaultsButton:SetPoint("BOTTOMLEFT", 16, 16)
    defaultsButton:SetText("По умолчанию")
    defaultsButton:SetScript("OnClick", function()
        auction.db = CopyTable(auction.defaults)
        auction:ApplySettings()
    end)
    
    local applyButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    self.optionsApplyBtn = applyButton
    applyButton:SetSize(120, 25)
    applyButton:SetPoint("BOTTOMRIGHT", -16, 16)
    applyButton:SetText("Применить")
    applyButton:SetScript("OnClick", function()
        auction:SaveSettings()
        auction:ApplySettings()
        print("|cff00ff00[EPBA]|r Настройки сохранены")
    end)
    
    local cancelButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    self.optionsCancelBtn = cancelButton
    cancelButton:SetSize(120, 25)
    cancelButton:SetPoint("RIGHT", applyButton, "LEFT", -10, 0)
    cancelButton:SetText("Отмена")
    cancelButton:SetScript("OnClick", function()
        HideUIPanel(panel)
    end)
    
    InterfaceOptions_AddCategory(panel)
    self.optionsPanel = panel
    self:Debug("Панель настроек создана")
    
    -- Применить ElvUI-скин к панели
    self:ApplyElvUISkinToOptions()
end

-- ======================
-- Скин ElvUI для окна настроек (исправленная версия)
-- ======================
function auction:ApplyElvUISkinToOptions()
    if not IsAddOnLoaded("ElvUI") then return end
    if not self.optionsPanel then return end

    local E, L, V, P, G = unpack(ElvUI)
    local S = E:GetModule("Skins")
    if not S then return end

    -- Применяем шаблон к фону панели
    self.optionsPanel:SetTemplate("Transparent")

    -- Обрабатываем скроллбар контейнера (с проверкой имени)
    if self.contentContainer then
        local name = self.contentContainer:GetName()
        if name then
            local scrollBar = _G[name.."ScrollBar"]
            if scrollBar and S.HandleScrollBar then
                S:HandleScrollBar(scrollBar)
            end
        end
    end

    -- Кнопки вкладок (табы сверху)
    if self.optionsTabButtons then
        for _, btn in ipairs(self.optionsTabButtons) do
            if S.HandleButton then S:HandleButton(btn) end
        end
    end

    -- Кнопки внизу панели
    if self.optionsDefaultsBtn and S.HandleButton then S:HandleButton(self.optionsDefaultsBtn) end
    if self.optionsApplyBtn and S.HandleButton then S:HandleButton(self.optionsApplyBtn) end
    if self.optionsCancelBtn and S.HandleButton then S:HandleButton(self.optionsCancelBtn) end

    -- Чекбоксы, эдитбоксы, слайдеры и дропдауны оставляем в стандартном виде,
    -- чтобы не ломать их отображение.
end
