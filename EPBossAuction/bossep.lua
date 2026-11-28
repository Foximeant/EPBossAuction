local auction = EPBossAuction

-- ============================================================
-- bossep.lua — окно «ЕП за боссов» (только для Loot Master)
-- ============================================================
-- Список всех боссов (по рейдам, в порядке auction.instanceOrder) с полем
-- ввода: сколько ЕП рейд получает за босса. Число подставляется в окно добычи
-- в блок «Массовое начисление» (lootmaster.lua) сразу при выборе босса — там
-- его можно поправить перед начислением, а кнопки x1 / x1.25 / x2 умножают его.
--
-- Хранится в auction.db.lootmaster.bossEP[имя босса] = число (пусто/0 — босс
-- не задан и поле в окне добычи остаётся пустым). Читают/пишут только
-- auction:GetBossEP / auction:SetBossEP (lootmaster.lua).
--
-- Открывается из настроек: раздел «ЕП за боссов», кнопка «Настроить»
-- (options.lua; раздел виден только ЛМ). Tab в поле — к следующему боссу.
-- ============================================================

local WIN_W, WIN_H = 440, 560
local ROW_H = 26
local INST_H = 30        -- высота заголовка рейда
local NAME_W = 290
local CONTENT_W = 360

local function Say(msg, isError)
    DEFAULT_CHAT_FRAME:AddMessage((isError and "|cffff0000[EPBA]|r " or "|cff00ff00[EPBA]|r ") .. msg)
end

-- Строит содержимое списка один раз: заголовки рейдов и строки «босс — поле».
local function BuildRows(frame)
    local c = auction.theme.colors
    local content = frame.content
    local boxes = {}
    local y = 0

    local function Commit(box)
        local value = tonumber(box:GetText())
        auction:SetBossEP(box.boss, value)
        box:SetText(auction:GetBossEP(box.boss) and tostring(auction:GetBossEP(box.boss)) or "")
    end

    for _, instanceName in ipairs(auction.instanceOrder or {}) do
        local bosses = auction.instances[instanceName]
        if bosses and #bosses > 0 then
            local header = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            header:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(y + 8))
            header:SetText(instanceName)
            header:SetTextColor(c.accent[1], c.accent[2], c.accent[3])
            local line = content:CreateTexture(nil, "ARTWORK")
            line:SetTexture(c.accent[1], c.accent[2], c.accent[3], 0.35)
            line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)
            line:SetSize(CONTENT_W - 8, 1)
            y = y + INST_H

            for _, bossName in ipairs(bosses) do
                local label = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                label:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -(y + 5))
                label:SetWidth(NAME_W - 10)
                label:SetHeight(14)
                label:SetJustifyH("LEFT")
                label:SetText(bossName)

                local box = CreateFrame("EditBox", nil, content)
                box:SetSize(80, 20)
                box:SetPoint("TOPLEFT", content, "TOPLEFT", NAME_W + 4, -(y + 2))
                box:SetAutoFocus(false)
                box:SetNumeric(true)
                box:SetMaxLetters(6)
                box:SetFontObject(GameFontHighlight)
                box:SetTextInsets(6, 6, 0, 0)
                auction:SkinInput(box)
                box.boss = bossName
                box.index = #boxes + 1
                box:SetScript("OnEnterPressed", function(b) b:ClearFocus() end)
                box:SetScript("OnEscapePressed", function(b)
                    local v = auction:GetBossEP(b.boss)
                    b:SetText(v and tostring(v) or "")
                    b:ClearFocus()
                end)
                box:SetScript("OnEditFocusLost", function(b) Commit(b) end)
                -- Tab — к следующему боссу, Shift+Tab — к предыдущему
                box:SetScript("OnTabPressed", function(b)
                    local step = IsShiftKeyDown() and -1 or 1
                    local nextBox = boxes[b.index + step]
                    if nextBox then nextBox:SetFocus() else b:ClearFocus() end
                end)
                table.insert(boxes, box)
                y = y + ROW_H
            end
        end
    end

    content:SetSize(CONTENT_W, math.max(y + 8, 1))
    frame.boxes = boxes
end

-- Подставляет сохранённые значения в поля (при каждом открытии окна).
local function RefreshValues(frame)
    for _, box in ipairs(frame.boxes or {}) do
        local v = auction:GetBossEP(box.boss)
        box:SetText(v and tostring(v) or "")
    end
end

function auction:CreateBossEPWindow()
    if self.bossEPFrame then return self.bossEPFrame end
    local c = self.theme.colors

    local f = CreateFrame("Frame", "EPBossAuctionBossEPFrame", UIParent)
    f:SetSize(WIN_W, WIN_H)
    f:SetPoint("CENTER")
    auction:SetupWindow(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    self:SkinPanel(f)
    f:Hide()
    tinsert(UISpecialFrames, "EPBossAuctionBossEPFrame")   -- закрытие по Esc

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("ЕП за боссов")
    title:SetTextColor(c.accent[1], c.accent[2], c.accent[3])

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
    hint:SetWidth(WIN_W - 40)
    hint:SetText("Сколько ЕП рейд получает за босса. Число подставляется в окне добычи в блок «Массовое начисление». Пусто или 0 — не подставлять.")

    local scroll = CreateFrame("ScrollFrame", "EPBossAuctionBossEPScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -78)
    scroll:SetPoint("BOTTOMRIGHT", -34, 52)
    local scrollBar = _G["EPBossAuctionBossEPScrollScrollBar"]
    if scrollBar then self:SkinScrollBar(scrollBar) end
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_W, 1)
    scroll:SetScrollChild(content)
    f.scroll, f.content = scroll, content

    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetSize(120, 24)
    close:SetPoint("BOTTOM", 0, 16)
    close:SetText("Закрыть")
    self:SkinButton(close)
    close:SetScript("OnClick", function() f:Hide() end)

    BuildRows(f)
    f:SetScript("OnShow", function() RefreshValues(f) end)

    self.bossEPFrame = f
    return f
end

-- Открывает/закрывает окно. Только для Loot Master.
function auction:ShowBossEPWindow()
    if not self:IsLootMaster() then
        Say("Список «ЕП за боссов» доступен только Loot Master.", true)
        return
    end
    local f = self:CreateBossEPWindow()
    if f:IsShown() then f:Hide() else f:Show() end
end
