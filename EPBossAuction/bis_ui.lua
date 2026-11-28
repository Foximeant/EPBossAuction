local auction = EPBossAuction

-- ============================================================
-- bis_ui.lua — вкладка «BiS»: интерфейс конструктора
-- ============================================================
-- Данные, формат обмена и правила — в bis.lua. Вкладку видят все игроки.
--
-- Четыре экрана в одной панели (состояние — auction.bisState):
--   classes — 10 иконок классов;
--   specs   — три специализации выбранного класса;
--   lists   — списки этой специализации (свои и импортированные), «Новый список», «Импорт»;
--   editor  — слоты экипировки выбранного списка.
--
-- Редактор: клик по слоту выбирает его; предмет добавляется Shift+кликом по ссылке/предмету
-- (чат, окно лута и т.п.) или вводом itemID в поле. В слоте до 3 предметов: первый основной,
-- остальные запасные (ЛКМ по запасному — сделать основным, ПКМ по любому — убрать).
-- Заметки: к списку (полоса под панелью инструментов) и к каждому слоту. Слот с заметкой
-- подсвечен золотом и помечен значком, текст — в тултипе и в строке внизу.
-- ============================================================

local WHITE = "Interface\\Buttons\\WHITE8x8"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local NOTE_ICON = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up"
local CLASS_TEXTURE = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"

local CELL_W, CELL_H, ROW_H = 300, 40, 42
local COL_X = { 6, 312 }
local GRID_TOP = -104
-- Раскладка слотов как на окне персонажа: левая колонка — броня сверху вниз, затем оружие;
-- правая — перчатки, пояс, ноги, ступни, кольца, аксессуары. {колонка, строка}
local LAYOUT = {
    [1] = { 1, 0 }, [2] = { 1, 1 }, [3] = { 1, 2 }, [4] = { 1, 3 }, [5] = { 1, 4 }, [6] = { 1, 5 },
    [7] = { 2, 0 }, [8] = { 2, 1 }, [9] = { 2, 2 }, [10] = { 2, 3 }, [11] = { 2, 4 }, [12] = { 2, 5 },
    [13] = { 2, 6 }, [14] = { 2, 7 },
    [15] = { 1, 6 }, [16] = { 1, 7 }, [17] = { 1, 8 },
}
local LIST_ROW_H = 44
local LIST_CONTENT_W = 590
local RETRY_DELAY, MAX_RETRIES = 1.5, 12
local ITEMNAME_W = 176   -- ширина названия предмета в ячейке слота
local LISTNAME_W = 320

auction.bisState = auction.bisState or { screen = "classes" }
auction.bisListRows = auction.bisListRows or {}

-- ======================
-- Мелочи
-- ======================

local function Notice(text)
    UIErrorsFrame:AddMessage(text, 1.0, 0.5, 0.0, 3)
end

local function Backdrop(frame, bg, border)
    frame:SetBackdrop({
        bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

local function ClassRGB(token)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if c then return c.r, c.g, c.b end
    return 0.8, 0.8, 0.8
end

local function ClassHex(token)
    local r, g, b = ClassRGB(token)
    return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function SetClassIcon(tex, token)
    tex:SetTexture(CLASS_TEXTURE)
    local t = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
    if t then tex:SetTexCoord(t[1], t[2], t[3], t[4]) else tex:SetTexCoord(0, 1, 0, 1) end
end

local function Utf8Len(s)
    local n = 0
    for i = 1, #s do
        local b = s:byte(i)
        if b < 0x80 or b >= 0xC0 then n = n + 1 end
    end
    return n
end

local function Truncate(text, maxChars)
    if auction.Utf8Prefix(text, maxChars) == text then return text end
    return auction.Utf8Prefix(text, maxChars - 1).."..."
end

-- Подгоняет текст под ширину строки по её реальному размеру (а не по числу символов):
-- иначе длинное название переносится на вторую строку. prefix/suffix — цветовые коды.
local function FitText(fs, text, maxWidth, prefix, suffix)
    prefix, suffix = prefix or "", suffix or ""
    fs:SetText(prefix..text..suffix)
    if fs:GetStringWidth() <= maxWidth then return end
    local n = Utf8Len(text)
    while n > 1 do
        n = n - 1
        fs:SetText(prefix..auction.Utf8Prefix(text, n).."..."..suffix)
        if fs:GetStringWidth() <= maxWidth then return end
    end
end

-- Заметку — в одну строку для превью (переносы заменяем).
local function OneLine(text, maxChars)
    return Truncate((text or ""):gsub("\n", " / "), maxChars)
end

-- Кнопка тулбара с произвольной точкой привязки (H.MakeButton привязывает только к TOPLEFT).
local function MakeBtn(parent, text, width, point, x, y, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 22)
    b:SetPoint(point, parent, point, x, y)
    b:SetText(text)
    b:SetNormalFontObject(GameFontNormal)
    auction:SkinButton(b)
    b:SetScript("OnClick", onClick)
    return b
end

local function MakeEdit(parent, width, x, y, maxLetters, hintText)
    local edit = CreateFrame("EditBox", nil, parent)
    edit:SetSize(width, 22)
    edit:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    edit:SetAutoFocus(false)
    edit:SetFontObject(GameFontHighlightSmall)
    edit:SetTextInsets(6, 6, 0, 0)
    edit:SetMaxLetters(maxLetters)
    auction:SkinInput(edit)
    edit:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    if hintText then
        local hint = edit:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("LEFT", edit, "LEFT", 6, 0)
        hint:SetTextColor(0.5, 0.5, 0.5)
        hint:SetText(hintText)
        local function UpdateHint()
            if edit:GetText() == "" and not edit:HasFocus() then hint:Show() else hint:Hide() end
        end
        edit:HookScript("OnTextChanged", UpdateHint)
        edit:HookScript("OnEditFocusGained", UpdateHint)
        edit:HookScript("OnEditFocusLost", UpdateHint)
        edit.UpdateHint = UpdateHint
    end
    return edit
end

-- Многострочное поле ввода в рамке: видно, куда кликать. EditBox растянут на всю область
-- рамки, поэтому клик в любом её месте ставит курсор. Возвращает edit и scroll.
local function MakeMultilineBox(parent, scrollName, left, top, right, bottom, width, height, maxLetters)
    local c = auction.theme.colors
    local box = CreateFrame("Frame", nil, parent)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", left, top)
    box:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", right, bottom)
    Backdrop(box, c.inputBg, c.border)
    local scroll = CreateFrame("ScrollFrame", scrollName, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -24, 4)
    local scrollBar = _G[scrollName.."ScrollBar"]
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", box, "TOPRIGHT", -4, -20)
        scrollBar:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -4, 20)
        auction:SkinScrollBar(scrollBar)
    end
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetFontObject(ChatFontNormal)
    edit:SetTextInsets(4, 4, 2, 2)
    edit:SetWidth(width)
    edit:SetHeight(height)
    edit:SetAutoFocus(false)
    if maxLetters then edit:SetMaxLetters(maxLetters) end
    scroll:SetScrollChild(edit)
    -- Клик по рамке за пределами EditBox (отступы) тоже ставит курсор
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() edit:SetFocus() end)
    return edit, scroll
end

-- Большая кнопка-карточка (класс / специализация): иконка, название, счётчик списков.
local function MakePickButton(parent, w, h, iconSize)
    local c = auction.theme.colors
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    Backdrop(b, c.inputBg, c.border)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(iconSize, iconSize)
    b.icon:SetPoint("TOP", b, "TOP", 0, -10)
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.name:SetPoint("TOP", b.icon, "BOTTOM", 0, -6)
    b.name:SetWidth(w - 8)
    b.count = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.count:SetPoint("BOTTOM", b, "BOTTOM", 0, 8)
    b.count:SetTextColor(0.6, 0.6, 0.6)
    b:SetScript("OnEnter", function(self)
        local ac = auction.theme.colors.accent
        self:SetBackdropBorderColor(ac[1], ac[2], ac[3], 1)
    end)
    b:SetScript("OnLeave", function(self)
        local bc = auction.theme.colors.border
        self:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4])
    end)
    return b
end

local function CountText(n)
    if n == 0 then return "списков нет" end
    local m10, m100 = n % 10, n % 100
    local word = "списков"
    if m100 < 11 or m100 > 14 then
        if m10 == 1 then word = "список" elseif m10 >= 2 and m10 <= 4 then word = "списка" end
    end
    return n.." "..word
end

-- ======================
-- Состояние и навигация
-- ======================

function auction:BisShow(screen, class, spec, listId)
    local st = self.bisState
    st.screen = screen
    if class ~= nil then st.class = class end
    if spec ~= nil then st.spec = spec end
    if listId ~= nil then st.listId = listId end
    if screen ~= "editor" then st.slot = nil end
    self:RefreshBis()
end

local function CurrentList()
    local st = auction.bisState
    return st.listId and auction:BisGetList(st.listId) or nil
end

local function GoBack()
    local st = auction.bisState
    if st.screen == "editor" then auction:BisShow("lists")
    elseif st.screen == "lists" then auction:BisShow("specs")
    elseif st.screen == "specs" then auction:BisShow("classes") end
end

-- ======================
-- Панель
-- ======================

function auction:CreateBisPanel(frame)
    local c = self.theme.colors
    local panel = CreateFrame("Frame", "EPBossAuctionBisPanel", frame)
    panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -45)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
    panel:SetBackdrop({
        bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
    })
    panel:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    panel:SetBackdropBorderColor(0, 0, 0, 1)
    self:SkinPanel(panel)
    panel:Hide()
    self.bisPanel = panel

    -- Шапка: «Назад», хлебные крошки, «Импорт»
    self.bisBackBtn = MakeBtn(panel, "< Назад", 70, "TOPLEFT", 6, -6, GoBack)
    local crumb = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    crumb:SetPoint("LEFT", self.bisBackBtn, "RIGHT", 10, 0)
    crumb:SetTextColor(c.accent[1], c.accent[2], c.accent[3])
    self.bisCrumb = crumb
    self.bisImportBtn = MakeBtn(panel, "Импорт", 90, "TOPRIGHT", -6, -6, function()
        auction:BisShowTransfer("import")
    end)

    local function NewScreen()
        local s = CreateFrame("Frame", nil, panel)
        s:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -34)
        s:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
        s:Hide()
        return s
    end
    self.bisScreens = {
        classes = NewScreen(), specs = NewScreen(), lists = NewScreen(), editor = NewScreen(),
    }

    self:BuildBisClasses(self.bisScreens.classes)
    self:BuildBisSpecs(self.bisScreens.specs)
    self:BuildBisLists(self.bisScreens.lists)
    self:BuildBisEditor(self.bisScreens.editor)

    -- Shift+клик по ссылке на предмет добавляет его в выбранный слот редактора.
    -- hooksecurefunc безопасен для защищённого кода. Побочный эффект: при Shift+клике по
    -- стаку в сумке WoW может параллельно начать разделение стака — берите ссылки из чата.
    if hooksecurefunc and ChatEdit_InsertLink and not self._bisLinkHooked then
        self._bisLinkHooked = true
        hooksecurefunc("ChatEdit_InsertLink", function(link)
            if not link or not auction.bisPanel or not auction.bisPanel:IsVisible() then return end
            if auction.bisState.screen ~= "editor" then return end
            if not link:find("|Hitem:", 1, true) then return end
            local e = auction.bisItemEdit
            if e and e:HasFocus() then e:Insert(link); return end
            -- Активный чат: игрок делится ссылкой, а не собирает список.
            if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then return end
            auction:BisAddFromText(link)
        end)
    end
end

-- ======================
-- Экран 1: классы
-- ======================

function auction:BuildBisClasses(screen)
    local title = screen:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", screen, "TOP", 0, -18)
    title:SetText("Выберите класс")
    local hint = screen:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("BOTTOM", screen, "BOTTOM", 0, 12)
    hint:SetTextColor(0.6, 0.6, 0.6)
    hint:SetText("BiS-листы — ваши наброски комплектов: их можно составлять без предметов на руках и делиться строкой через «Экспорт» / «Импорт».")
    hint:SetWidth(580)

    self.bisClassButtons = {}
    for i, cls in ipairs(self.bisClasses) do
        local b = MakePickButton(screen, 104, 130, 64)
        local row = (i <= 5) and 0 or 1
        local col = (i - 1) % 5 + 1
        b:SetPoint("TOP", screen, "TOP", (col - 3) * 112, -56 - row * 142)
        SetClassIcon(b.icon, cls.token)
        b.name:SetText(cls.name)
        b.name:SetTextColor(ClassRGB(cls.token))
        b.cls = cls
        b:SetScript("OnClick", function(self)
            auction:BisShow("specs", self.cls.token)
        end)
        self.bisClassButtons[i] = b
    end
end

function auction:RefreshBisClasses()
    for _, b in ipairs(self.bisClassButtons) do
        local n = self:BisCountLists(b.cls.token)
        b.count:SetText(CountText(n))
        if n > 0 then b.count:SetTextColor(0.85, 0.85, 0.85) else b.count:SetTextColor(0.5, 0.5, 0.5) end
    end
end

-- ======================
-- Экран 2: специализации
-- ======================

function auction:BuildBisSpecs(screen)
    local title = screen:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", screen, "TOP", 0, -18)
    self.bisSpecTitle = title
    self.bisSpecButtons = {}
    for i = 1, 3 do
        local b = MakePickButton(screen, 150, 160, 64)
        b:SetPoint("TOP", screen, "TOP", (i - 2) * 166, -60)
        b.spec = i
        b:SetScript("OnClick", function(self)
            auction:BisShow("lists", nil, self.spec)
        end)
        self.bisSpecButtons[i] = b
    end
end

function auction:RefreshBisSpecs()
    local st = self.bisState
    local cls = self:BisClass(st.class)
    self.bisSpecTitle:SetText("Класс: "..ClassHex(cls.token)..cls.name.."|r. Выберите специализацию")
    for i, b in ipairs(self.bisSpecButtons) do
        local spec = cls.specs[i]
        b.icon:SetTexture(spec.icon)
        if not b.icon:GetTexture() then b.icon:SetTexture(QUESTION) end
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.name:SetText(spec.name)
        local n = self:BisCountLists(cls.token, i)
        b.count:SetText(CountText(n))
        if n > 0 then b.count:SetTextColor(0.85, 0.85, 0.85) else b.count:SetTextColor(0.5, 0.5, 0.5) end
    end
end

-- ======================
-- Экран 3: списки
-- ======================

function auction:BuildBisLists(screen)
    MakeBtn(screen, "Новый список", 130, "TOPLEFT", 6, 0, function()
        local st = auction.bisState
        local list, err = auction:BisCreateList(st.class, st.spec, "Новый список")
        if not list then Notice(err) return end
        auction:BisShow("editor", nil, nil, list.id)
        local e = auction.bisNameEdit
        if e then e:SetFocus(); e:HighlightText() end
    end)
    local info = screen:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    info:SetPoint("TOPRIGHT", screen, "TOPRIGHT", -8, -5)
    info:SetTextColor(0.7, 0.7, 0.7)
    self.bisListsInfo = info

    local scroll = CreateFrame("ScrollFrame", "EPBossAuctionBisListScroll", screen, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", screen, "TOPLEFT", 6, -32)
    scroll:SetPoint("BOTTOMRIGHT", screen, "BOTTOMRIGHT", -26, 8)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(LIST_CONTENT_W, 1)
    scroll:SetScrollChild(content)
    self.bisListContent = content
    local scrollBar = _G["EPBossAuctionBisListScrollScrollBar"]
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 22, -17)
        scrollBar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 22, 17)
        self:SkinScrollBar(scrollBar)
    end

    local empty = screen:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    empty:SetPoint("CENTER", screen, "CENTER", 0, 10)
    empty:SetWidth(420)
    empty:SetJustifyH("CENTER")
    empty:SetTextColor(0.6, 0.6, 0.6)
    empty:SetText("Списков пока нет.\nСоздайте свой кнопкой «Новый список» или импортируйте чужой.")
    self.bisListsEmpty = empty
end

local function CreateListRow(index)
    local c = auction.theme.colors
    local row = CreateFrame("Button", nil, auction.bisListContent)
    row:SetSize(LIST_CONTENT_W, LIST_ROW_H - 2)
    row:SetPoint("TOPLEFT", auction.bisListContent, "TOPLEFT", 0, -(index - 1) * LIST_ROW_H)
    Backdrop(row, c.inputBg, c.border)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -6)
    row.name:SetWidth(LISTNAME_W + 4)
    row.name:SetJustifyH("LEFT")
    row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.meta:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -23)
    row.meta:SetWidth(LISTNAME_W + 4)
    row.meta:SetJustifyH("LEFT")
    row.meta:SetTextColor(0.6, 0.6, 0.6)

    -- Заметка списка: значок + первые слова. Золотой штрих слева — тоже признак заметки.
    row.accent = row:CreateTexture(nil, "OVERLAY")
    row.accent:SetTexture(c.accent[1], c.accent[2], c.accent[3], 1)
    row.accent:SetPoint("TOPLEFT", 1, -1)
    row.accent:SetPoint("BOTTOMLEFT", 1, 1)
    row.accent:SetWidth(3)
    row.noteIcon = row:CreateTexture(nil, "ARTWORK")
    row.noteIcon:SetSize(14, 14)
    row.noteIcon:SetPoint("TOPLEFT", row, "TOPLEFT", 336, -6)
    row.noteIcon:SetTexture(NOTE_ICON)
    row.note = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.note:SetPoint("TOPLEFT", row, "TOPLEFT", 354, -6)
    row.note:SetSize(166, 30)
    row.note:SetJustifyH("LEFT")
    row.note:SetJustifyV("TOP")
    row.note:SetTextColor(1, 0.9, 0.55)

    row.copyBtn = MakeBtn(row, "Копия", 42, "TOPRIGHT", -24, -10, function(btn)
        local r = btn:GetParent()
        local copy, err = auction:BisCopyList(r.listId)
        if not copy then Notice(err or "Не удалось скопировать") return end
        auction:RefreshBis()
    end)
    row.delBtn = MakeBtn(row, "x", 18, "TOPRIGHT", -4, -10, function(btn)
        local r = btn:GetParent()
        local list = auction:BisGetList(r.listId)
        if list then StaticPopup_Show("EPBA_BIS_DELETE", list.name, nil, list.id) end
    end)

    row:SetScript("OnClick", function(self)
        auction:BisShow("editor", nil, nil, self.listId)
    end)
    row:SetScript("OnEnter", function(self)
        local ac = auction.theme.colors.accent
        self:SetBackdropBorderColor(ac[1], ac[2], ac[3], 1)
        local list = auction:BisGetList(self.listId)
        if not list then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(list.name)
        GameTooltip:AddLine("Автор: "..(list.author ~= "" and list.author or "—"), 0.7, 0.7, 0.7)
        if list.comment ~= "" then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Заметка:", 1, 0.82, 0)
            GameTooltip:AddLine(list.comment, 1, 1, 1, true)
        end
        local notes = auction:BisNoteCount(list)
        if notes > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Заметок к слотам: "..notes, 1, 0.82, 0)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        local bc = auction.theme.colors.border
        self:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4])
        GameTooltip:Hide()
    end)
    return row
end

function auction:RefreshBisLists()
    local st = self.bisState
    local lists = self:BisGetLists(st.class, st.spec)
    self.bisListsInfo:SetText("Списков: "..#lists)
    self.bisListsEmpty[#lists == 0 and "Show" or "Hide"](self.bisListsEmpty)
    for i, list in ipairs(lists) do
        local row = self.bisListRows[i]
        if not row then
            row = CreateListRow(i)
            self.bisListRows[i] = row
        end
        row.listId = list.id
        FitText(row.name, list.name, LISTNAME_W)
        local meta = "Автор: "..(list.author ~= "" and Truncate(list.author, 16) or "—")
            .."  ·  предметов: "..self:BisItemCount(list)
        if list.updated > 0 then meta = meta.."  ·  "..date("%d.%m.%y", list.updated) end
        FitText(row.meta, meta, LISTNAME_W)
        if list.comment ~= "" then
            row.note:SetText(OneLine(list.comment, 70))
            row.note:Show(); row.noteIcon:Show(); row.accent:Show()
        else
            row.note:Hide(); row.noteIcon:Hide(); row.accent:Hide()
        end
        row:Show()
    end
    for i = #lists + 1, #self.bisListRows do self.bisListRows[i]:Hide() end
    self.bisListContent:SetHeight(math.max(1, #lists * LIST_ROW_H))
end

StaticPopupDialogs["EPBA_BIS_DELETE"] = {
    text = "Удалить список «%s»?\nЭто нельзя отменить.",
    button1 = "Удалить", button2 = "Отмена",
    OnAccept = function(self, data)
        if data then auction:BisDeleteList(data) end
        if auction.bisState.listId == data then auction.bisState.listId = nil end
        auction:RefreshBis()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- ======================
-- Экран 4: редактор
-- ======================

local function SelectSlot(idx)
    auction.bisState.slot = idx
    auction:RefreshBisEditor()
end

local function ItemButtonClick(self, button)
    local cell = self.cell
    local list = CurrentList()
    if not list then return end
    auction.bisState.slot = cell.idx
    if self.itemID then
        if button == "RightButton" then
            auction:BisRemoveItem(list, cell.idx, self.pos)
        elseif self.pos > 1 then
            auction:BisPromoteItem(list, cell.idx, self.pos)
        end
    end
    auction:RefreshBisEditor()
end

local function ItemButtonEnter(self)
    local list = CurrentList()
    local cell = self.cell
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.itemID then
        GameTooltip:SetHyperlink("item:"..self.itemID)
        if GameTooltip:NumLines() == 0 then
            GameTooltip:AddLine("Предмет "..self.itemID, 1, 1, 1)
            GameTooltip:AddLine("Нет в кэше клиента — наведите ещё раз через пару секунд.", 1, 0.5, 0.5, true)
        end
        GameTooltip:AddLine(" ")
        if self.pos == 1 then
            GameTooltip:AddLine("Основной предмет слота", 0.5, 1, 0.5)
        else
            GameTooltip:AddLine("Запасной предмет. ЛКМ — сделать основным", 0.5, 1, 0.5)
        end
        GameTooltip:AddLine("ПКМ — убрать из слота", 0.5, 1, 0.5)
    else
        GameTooltip:AddLine(auction.bisSlots[cell.idx].name, 1, 1, 1)
        GameTooltip:AddLine("Пусто. Выберите слот и Shift+кликните по предмету или введите itemID.", 0.7, 0.7, 0.7, true)
    end
    local s = list and list.slots[cell.idx]
    if s and s.note and s.note ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Заметка к слоту:", 1, 0.82, 0)
        GameTooltip:AddLine(s.note, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function CreateItemButton(cell, size, x, y, pos)
    local b = CreateFrame("Button", nil, cell)
    b:SetSize(size, size)
    b:SetPoint("TOPLEFT", cell, "TOPLEFT", x, y)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b:SetBackdropColor(0, 0, 0, 1)
    b:SetBackdropBorderColor(0.1, 0.1, 0.1, 1)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("TOPLEFT", 1, -1)
    b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cell = cell
    b.pos = pos
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", ItemButtonClick)
    b:SetScript("OnEnter", ItemButtonEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function CreateCell(parent, idx)
    local c = auction.theme.colors
    local cell = CreateFrame("Button", nil, parent)
    cell:SetSize(CELL_W, CELL_H)
    local pos = LAYOUT[idx]
    cell:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_X[pos[1]], GRID_TOP - pos[2] * ROW_H)
    Backdrop(cell, c.inputBg, c.border)
    cell.idx = idx

    local ok, _, tex = pcall(GetInventorySlotInfo, auction.bisSlots[idx].slot)
    cell.slotTexture = (ok and tex) or QUESTION

    cell.accent = cell:CreateTexture(nil, "OVERLAY")
    cell.accent:SetTexture(c.accent[1], c.accent[2], c.accent[3], 1)
    cell.accent:SetPoint("TOPLEFT", 1, -1)
    cell.accent:SetPoint("BOTTOMLEFT", 1, 1)
    cell.accent:SetWidth(3)

    cell.main = CreateItemButton(cell, 36, 6, -2, 1)
    cell.alts = {
        CreateItemButton(cell, 24, 48, -8, 2),
        CreateItemButton(cell, 24, 76, -8, 3),
    }

    cell.label = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cell.label:SetPoint("TOPLEFT", cell, "TOPLEFT", 108, -6)
    cell.label:SetTextColor(0.6, 0.6, 0.6)
    cell.label:SetText(auction.bisSlots[idx].name)
    cell.itemName = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cell.itemName:SetPoint("TOPLEFT", cell, "TOPLEFT", 108, -22)
    cell.itemName:SetWidth(ITEMNAME_W + 4)
    cell.itemName:SetJustifyH("LEFT")

    cell.noteBtn = CreateFrame("Button", nil, cell)
    cell.noteBtn:SetSize(16, 16)
    cell.noteBtn:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -4, -4)
    cell.noteBtn.tex = cell.noteBtn:CreateTexture(nil, "ARTWORK")
    cell.noteBtn.tex:SetAllPoints()
    cell.noteBtn.tex:SetTexture(NOTE_ICON)
    cell.noteBtn:SetScript("OnClick", function()
        SelectSlot(idx)
        auction:BisEditSlotNote()
    end)
    cell.noteBtn:SetScript("OnEnter", function(self)
        local list = CurrentList()
        local s = list and list.slots[idx]
        if not s or not s.note or s.note == "" then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(auction.bisSlots[idx].name..": заметка", 1, 0.82, 0)
        GameTooltip:AddLine(s.note, 1, 1, 1, true)
        GameTooltip:AddLine("Клик — изменить", 0.5, 1, 0.5)
        GameTooltip:Show()
    end)
    cell.noteBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    cell:SetScript("OnClick", function() SelectSlot(idx) end)
    return cell
end

function auction:BuildBisEditor(screen)
    local c = self.theme.colors

    -- Ряд 1: название, автор, экспорт
    local nameEdit = MakeEdit(screen, 230, 6, 0, auction.BIS_NAME_LEN, "Название списка")
    local authorEdit = MakeEdit(screen, 130, 242, 0, auction.BIS_AUTHOR_LEN, "Автор")
    local function RevertFields()
        local list = CurrentList()
        if not list then return end
        nameEdit:SetText(list.name)
        authorEdit:SetText(list.author)
        if nameEdit.UpdateHint then nameEdit.UpdateHint(); authorEdit.UpdateHint() end
    end
    local function SaveFields()
        local list = CurrentList()
        if not list then return end
        auction:BisSetName(list, nameEdit:GetText())
        auction:BisSetAuthor(list, authorEdit:GetText())
        RevertFields()
        auction:RefreshBisCrumb()
    end
    for _, e in ipairs({ nameEdit, authorEdit }) do
        e:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
        e:HookScript("OnEditFocusLost", SaveFields)
        e:SetScript("OnEscapePressed", function(box) RevertFields(); box:ClearFocus() end)
    end
    self.bisNameEdit, self.bisAuthorEdit = nameEdit, authorEdit
    self.bisRevertFields = RevertFields

    MakeBtn(screen, "Экспорт", 90, "TOPLEFT", 378, 0, function()
        local list = CurrentList()
        if list then auction:BisShowTransfer("export", list) end
    end)

    -- Ряд 2: ввод предмета и заметки
    local itemEdit = MakeEdit(screen, 200, 6, -28, 500, "Shift+клик или itemID")
    itemEdit:SetScript("OnEnterPressed", function() auction:BisAddFromEdit() end)
    self.bisItemEdit = itemEdit
    self.bisAddBtn = MakeBtn(screen, "Добавить", 72, "TOPLEFT", 212, -28, function() auction:BisAddFromEdit() end)
    self.bisSlotNoteBtn = MakeBtn(screen, "Заметка слота", 112, "TOPLEFT", 290, -28, function() auction:BisEditSlotNote() end)
    self.bisListNoteBtn = MakeBtn(screen, "Заметка списка", 118, "TOPLEFT", 408, -28, function() auction:BisEditListNote() end)
    self.bisClearBtn = MakeBtn(screen, "Очистить", 80, "TOPLEFT", 532, -28, function()
        local list, slot = CurrentList(), auction.bisState.slot
        if list and slot then
            auction:BisClearSlot(list, slot)
            auction:RefreshBisEditor()
        end
    end)

    -- Полоса с заметкой списка
    local strip = CreateFrame("Button", nil, screen)
    strip:SetSize(606, 40)
    strip:SetPoint("TOPLEFT", screen, "TOPLEFT", 6, -58)
    Backdrop(strip, { 0.12, 0.10, 0.04, 1 }, c.border)
    strip.accent = strip:CreateTexture(nil, "OVERLAY")
    strip.accent:SetTexture(c.accent[1], c.accent[2], c.accent[3], 1)
    strip.accent:SetPoint("TOPLEFT", 1, -1)
    strip.accent:SetPoint("BOTTOMLEFT", 1, 1)
    strip.accent:SetWidth(3)
    strip.icon = strip:CreateTexture(nil, "ARTWORK")
    strip.icon:SetSize(16, 16)
    strip.icon:SetPoint("TOPLEFT", strip, "TOPLEFT", 10, -5)
    strip.icon:SetTexture(NOTE_ICON)
    strip.text = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    strip.text:SetPoint("TOPLEFT", strip, "TOPLEFT", 32, -4)
    strip.text:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", -8, 4)
    strip.text:SetJustifyH("LEFT")
    strip.text:SetJustifyV("TOP")
    strip:SetScript("OnClick", function() auction:BisEditListNote() end)
    strip:SetScript("OnEnter", function(self)
        local list = CurrentList()
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Заметка к списку", 1, 0.82, 0)
        if list and list.comment ~= "" then GameTooltip:AddLine(list.comment, 1, 1, 1, true) end
        GameTooltip:AddLine("Клик — изменить", 0.5, 1, 0.5)
        GameTooltip:Show()
    end)
    strip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.bisStrip = strip

    -- Сетка слотов
    self.bisCells = {}
    for i = 1, self.BIS_NUM_SLOTS do
        self.bisCells[i] = CreateCell(screen, i)
    end

    -- Строка внизу: подсказка или заметка выбранного слота
    local info = screen:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    info:SetPoint("BOTTOMLEFT", screen, "BOTTOMLEFT", 8, 4)
    info:SetWidth(596)
    info:SetJustifyH("LEFT")
    info:SetJustifyV("BOTTOM")
    info:SetTextColor(0.65, 0.65, 0.65)
    self.bisInfo = info
end

-- Добавляет предметы из текста (ссылки или id) в выбранный слот.
function auction:BisAddFromText(text)
    local list, slot = CurrentList(), self.bisState.slot
    if not list then return 0 end
    if not slot then Notice("Сначала выберите слот в списке") return 0 end
    local ids = self:BisExtractItemIDs(text)
    if #ids == 0 then Notice("Не нашёл itemID в «"..tostring(text).."»") return 0 end
    local added, lastWhy = 0, nil
    for _, id in ipairs(ids) do
        local ok, why = self:BisAddItem(list, slot, id)
        if ok then added = added + 1 else lastWhy = why end
    end
    if lastWhy and added < #ids then Notice(lastWhy) end
    self:RefreshBisEditor()
    return added
end

function auction:BisAddFromEdit()
    local e = self.bisItemEdit
    local text = e:GetText()
    if text == "" then return end
    if self:BisAddFromText(text) > 0 then
        e:SetText("")
        e:ClearFocus()
    end
end

function auction:BisEditSlotNote()
    local list, slot = CurrentList(), self.bisState.slot
    if not list or not slot then Notice("Сначала выберите слот") return end
    local s = list.slots[slot]
    self:BisShowNoteEditor("Заметка: "..self.bisSlots[slot].name, s and s.note or "", self.BIS_SLOT_NOTE_LEN, function(text)
        auction:BisSetSlotNote(list, slot, text)
        auction:RefreshBisEditor()
    end)
end

function auction:BisEditListNote()
    local list = CurrentList()
    if not list then return end
    self:BisShowNoteEditor("Заметка к списку «"..Truncate(list.name, 30).."»", list.comment, self.BIS_LIST_NOTE_LEN, function(text)
        auction:BisSetComment(list, text)
        auction:RefreshBisEditor()
    end)
end

local function ScheduleRetry()
    if auction._bisRetryTimer or (auction._bisRetries or 0) >= MAX_RETRIES then return end
    auction._bisRetries = (auction._bisRetries or 0) + 1
    auction._bisRetryTimer = auction:ScheduleTimer(function()
        auction._bisRetryTimer = nil
        if auction.bisPanel and auction.bisPanel:IsVisible() then auction:RefreshBis(true) end
    end, RETRY_DELAY)
end

local function QualityHex(quality)
    local col = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if not col then return "|cffffffff", 0.4, 0.4, 0.4 end
    return string.format("|cff%02x%02x%02x", math.floor(col.r * 255 + 0.5), math.floor(col.g * 255 + 0.5), math.floor(col.b * 255 + 0.5)),
        col.r, col.g, col.b
end

-- Рисует один слот. Возвращает true, если какие-то предметы ещё не пришли из кэша.
local function RenderCell(cell, list, selected)
    local c = auction.theme.colors
    local data = list.slots[cell.idx]
    local items = data and data.items or {}
    local note = data and data.note or ""
    local pending = false

    for pos = 1, auction.BIS_MAX_PER_SLOT do
        local btn = (pos == 1) and cell.main or cell.alts[pos - 1]
        local id = items[pos]
        btn.itemID = id
        if id then
            local name, quality, icon, known = auction:BisItemInfo(id)
            btn.tex:SetTexture(icon or QUESTION)
            btn.tex:SetDesaturated(false)
            btn.tex:SetAlpha(1)
            local hex, r, g, b = QualityHex(quality)
            btn:SetBackdropBorderColor(r, g, b, 1)
            btn:Show()
            if not known then pending = true end
            if pos == 1 then
                if known then
                    FitText(cell.itemName, name, ITEMNAME_W, hex, "|r")
                else
                    FitText(cell.itemName, "Предмет "..id.." (загрузка...)", ITEMNAME_W, "|cff888888", "|r")
                end
            end
        else
            if pos == 1 then
                btn.tex:SetTexture(cell.slotTexture)
                btn.tex:SetDesaturated(true)
                btn.tex:SetAlpha(0.45)
                btn:SetBackdropBorderColor(0.1, 0.1, 0.1, 1)
                btn:Show()
                cell.itemName:SetText("|cff666666— пусто —|r")
            elseif pos == #items + 1 then
                -- Свободное место под запасной предмет
                btn.tex:SetTexture(cell.slotTexture)
                btn.tex:SetDesaturated(true)
                btn.tex:SetAlpha(0.25)
                btn:SetBackdropBorderColor(0.1, 0.1, 0.1, 1)
                btn:Show()
            else
                btn:Hide()
            end
        end
    end

    -- Заметка: золотая полоска, значок и тёплый фон
    local hasNote = note ~= ""
    if hasNote then cell.accent:Show(); cell.noteBtn:Show() else cell.accent:Hide(); cell.noteBtn:Hide() end
    if selected then
        cell:SetBackdropColor(0.16, 0.13, 0.05, 1)
        cell:SetBackdropBorderColor(c.accent[1], c.accent[2], c.accent[3], 1)
    elseif hasNote then
        cell:SetBackdropColor(0.12, 0.10, 0.04, 1)
        cell:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], c.border[4])
    else
        cell:SetBackdropColor(c.inputBg[1], c.inputBg[2], c.inputBg[3], c.inputBg[4])
        cell:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], c.border[4])
    end
    return pending
end

function auction:RefreshBisEditor()
    local list = CurrentList()
    if not list then return end
    local st = self.bisState

    if not self.bisNameEdit:HasFocus() and not self.bisAuthorEdit:HasFocus() then
        self.bisRevertFields()
    end

    -- Полоса заметки списка
    local strip = self.bisStrip
    if list.comment ~= "" then
        strip.text:SetTextColor(1, 0.9, 0.55)
        strip.text:SetText(OneLine(list.comment, 280))
        strip.icon:SetAlpha(1)
        strip.accent:Show()
    else
        strip.text:SetTextColor(0.5, 0.5, 0.5)
        strip.text:SetText("Заметка к списку не задана — нажмите здесь или «Заметка списка».")
        strip.icon:SetAlpha(0.4)
        strip.accent:Hide()
    end

    local pending = false
    for i, cell in ipairs(self.bisCells) do
        if RenderCell(cell, list, st.slot == i) then pending = true end
    end
    if pending then ScheduleRetry() end

    local hasSlot = st.slot ~= nil
    for _, b in ipairs({ self.bisAddBtn, self.bisSlotNoteBtn, self.bisClearBtn }) do
        if hasSlot then b:Enable() else b:Disable() end
    end

    if hasSlot then
        local s = list.slots[st.slot]
        local note = s and s.note or ""
        self.bisInfo:SetText("|cffffd200Слот «"..self.bisSlots[st.slot].name.."»:|r "
            ..(note ~= "" and ("|cffffe58c"..OneLine(note, 150).."|r") or "заметки нет")
            .."   |cff888888Shift+клик по предмету — добавить.|r")
    else
        self.bisInfo:SetText("Клик по слоту выбирает его. ЛКМ по запасному предмету — сделать основным, ПКМ по предмету — убрать.")
    end
end

-- ======================
-- Общее обновление
-- ======================

function auction:RefreshBisCrumb()
    local st = self.bisState
    local parts = { "BiS-листы" }
    local cls = st.class and self:BisClass(st.class)
    if st.screen ~= "classes" and cls then
        parts[#parts + 1] = ClassHex(cls.token)..cls.name.."|r"
        if (st.screen == "lists" or st.screen == "editor") and st.spec and cls.specs[st.spec] then
            parts[#parts + 1] = cls.specs[st.spec].name
        end
        if st.screen == "editor" then
            local list = CurrentList()
            if list then parts[#parts + 1] = Truncate(list.name, 24) end
        end
    end
    self.bisCrumb:SetText(table.concat(parts, "  >  "))
end

function auction:RefreshBis(fromRetry)
    if not self.bisPanel then return end
    if not fromRetry then self._bisRetries = 0 end
    local st = self.bisState

    -- Состояние могло устареть (список удалён, данные очищены)
    if st.screen == "editor" and not CurrentList() then st.screen = "lists" end
    if st.screen ~= "classes" and not (st.class and self:BisClass(st.class)) then st.screen = "classes" end
    if (st.screen == "lists" or st.screen == "editor") and not st.spec then st.screen = "specs" end

    for key, screen in pairs(self.bisScreens) do
        if key == st.screen then screen:Show() else screen:Hide() end
    end
    if st.screen == "classes" then self.bisBackBtn:Hide() else self.bisBackBtn:Show() end
    self:RefreshBisCrumb()

    if st.screen == "classes" then self:RefreshBisClasses()
    elseif st.screen == "specs" then self:RefreshBisSpecs()
    elseif st.screen == "lists" then self:RefreshBisLists()
    else self:RefreshBisEditor() end
end

-- ======================
-- Окно заметки
-- ======================

function auction:BisShowNoteEditor(title, text, limit, onSave)
    local f = self.bisNoteFrame
    if not f then
        local c = self.theme.colors
        f = CreateFrame("Frame", "EPBossAuctionBisNoteFrame", UIParent)
        f:SetSize(440, 250)
        f:SetPoint("CENTER")
        self:SetupWindow(f)
        self:SkinPanel(f)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOP", 0, -14)
        f.title:SetTextColor(c.accent[1], c.accent[2], c.accent[3])

        -- Поле в рамке: 440 - отступы 16+16 - рамка/полоса прокрутки = 372 x 142
        local edit = MakeMultilineBox(f, "EPBossAuctionBisNoteScroll", 16, -46, -16, 54, 372, 140)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        f.edit = edit

        f.counter = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.counter:SetPoint("BOTTOMLEFT", 18, 24)
        f.counter:SetTextColor(0.6, 0.6, 0.6)
        edit:SetScript("OnTextChanged", function(box)
            f.counter:SetText(Utf8Len(box:GetText()).." / "..(f.limit or 0))
        end)

        local save = CreateFrame("Button", nil, f)
        save:SetSize(110, 24)
        save:SetPoint("BOTTOMRIGHT", -132, 16)
        save:SetText("Сохранить")
        save:SetNormalFontObject(GameFontNormal)
        self:SkinButton(save)
        save:SetScript("OnClick", function()
            local cb = f.onSave
            f:Hide()
            if cb then cb(f.edit:GetText()) end
        end)
        local cancel = CreateFrame("Button", nil, f)
        cancel:SetSize(110, 24)
        cancel:SetPoint("BOTTOMRIGHT", -16, 16)
        cancel:SetText("Отмена")
        cancel:SetNormalFontObject(GameFontNormal)
        self:SkinButton(cancel)
        cancel:SetScript("OnClick", function() f:Hide() end)

        self.bisNoteFrame = f
    end
    f.onSave = onSave
    f.limit = limit
    f.title:SetText(title)
    f.edit:SetMaxLetters(limit)
    f.edit:SetText(text or "")
    f:Show()
    f.edit:SetFocus()
end

-- ======================
-- Окно экспорта / импорта
-- ======================

function auction:BisShowTransfer(mode, list)
    local f = self.bisTransferFrame
    if not f then
        local c = self.theme.colors
        f = CreateFrame("Frame", "EPBossAuctionBisTransferFrame", UIParent)
        f:SetSize(560, 360)
        f:SetPoint("CENTER")
        self:SetupWindow(f)
        self:SkinPanel(f)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOP", 0, -14)
        f.title:SetTextColor(c.accent[1], c.accent[2], c.accent[3])
        f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.hint:SetPoint("TOP", f.title, "BOTTOM", 0, -4)
        f.hint:SetTextColor(0.7, 0.7, 0.7)

        -- 560 - 16*2 - рамка/полоса прокрутки = 492 x 196
        local edit = MakeMultilineBox(f, "EPBossAuctionBisTransferScroll", 16, -56, -16, 96, 492, 196, 200000)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        f.edit = edit

        f.status = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.status:SetPoint("BOTTOMLEFT", 18, 58)
        f.status:SetWidth(520)
        f.status:SetHeight(30)
        f.status:SetJustifyH("LEFT")
        f.status:SetJustifyV("TOP")

        edit:SetScript("OnTextChanged", function(box)
            if f.mode ~= "import" then return end
            local data, err = auction:BisParse(box:GetText())
            f.parsed = data
            if data then
                local cls = auction:BisClass(data.class)
                f.status:SetTextColor(0.3, 0.9, 0.3)
                f.status:SetText(ClassHex(data.class)..cls.name.."|r › "..cls.specs[data.spec].name
                    ..": «"..data.name.."», автор "..(data.author ~= "" and data.author or "—")
                    ..", предметов: "..data.items..(data.comment ~= "" and ", есть заметка" or ""))
                f.importBtn:Enable()
            else
                f.status:SetTextColor(0.9, 0.35, 0.3)
                f.status:SetText(err or "")
                f.importBtn:Disable()
            end
        end)

        f.importBtn = CreateFrame("Button", nil, f)
        f.importBtn:SetSize(130, 24)
        f.importBtn:SetPoint("BOTTOMRIGHT", -152, 16)
        f.importBtn:SetText("Импортировать")
        f.importBtn:SetNormalFontObject(GameFontNormal)
        self:SkinButton(f.importBtn)
        f.importBtn:SetScript("OnClick", function()
            if not f.parsed then return end
            local list2, err = auction:BisImport(f.parsed)
            if not list2 then Notice(err) return end
            f:Hide()
            DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[EPBA]|r BiS-список «"..list2.name.."» импортирован.")
            auction:BisShow("editor", list2.class, list2.spec, list2.id)
        end)

        local close = CreateFrame("Button", nil, f)
        close:SetSize(130, 24)
        close:SetPoint("BOTTOMRIGHT", -16, 16)
        close:SetText("Закрыть")
        close:SetNormalFontObject(GameFontNormal)
        self:SkinButton(close)
        close:SetScript("OnClick", function() f:Hide() end)

        self.bisTransferFrame = f
    end

    f.mode = mode
    f.parsed = nil
    if mode == "export" then
        f.title:SetText("Экспорт: "..Truncate(list.name, 30))
        f.hint:SetText("Текст выделен: Ctrl+C — скопировать, Esc — закрыть")
        f.status:SetTextColor(0.7, 0.7, 0.7)
        f.status:SetText("Отправьте эту строку другому игроку (Discord, форум, личное сообщение вне игры): он вставит её через «Импорт».")
        f.importBtn:Hide()
        f.edit:SetText(self:BisExport(list))
        f:Show()
        f.edit:HighlightText()
        f.edit:SetFocus()
    else
        f.title:SetText("Импорт BiS-листа")
        f.hint:SetText("Вставьте строку (Ctrl+V). Список появится новым, ваши списки не изменятся.")
        f.status:SetText("")
        f.importBtn:Show()
        f.importBtn:Disable()
        f.edit:SetText("")
        f:Show()
        f.edit:SetFocus()
    end
end
