local auction = EPBossAuction

-- ============================================================
-- options.lua — вкладка «Настройки» главного окна
-- ============================================================
-- Настройки живут во вкладке окна аддона (шестерёнка в колонке вкладок слева
-- от окна; то же: «Меню» → «Настройки», /epbaoptions). Все изменения
-- применяются сразу и сохраняются — кнопок «Применить»/«Закрыть» нет.
-- Панель Interface Options осталась как «заглушка» с кнопкой, которая
-- открывает эту вкладку (чтобы настройки находились и там).
--
-- Разделы (две колонки):
--   слева   «Окно», «Миникарта», «Таблица ставок»
--   справа  «Ставки и звук», «Мои предметы» (белый список, watchlist.lua),
--           «ЕП за боссов» (виден только Loot Master, окно bossep.lua)
--   внизу   «Режим отладки» и «Сбросить настройки»
-- Минимальная ставка и коэффициент офф-спека здесь не выводятся: это
-- константы в core.lua (auction.MIN_BID, auction.OFFSPEC_MULTIPLIER),
-- их проверяет клиент каждого игрока.
--
-- Только выпадающие списки, галочки и кнопки — без ползунков. Ползунок
-- масштаба внутри масштабируемого окна дёргается под курсором, а таблицу
-- ставок удобнее настраивать готовыми вариантами («Компактная/Обычная/
-- Крупная»), чем четырьмя числами.
--
-- Как добавить настройку:
--   1. ключ и значение по умолчанию — в auction.defaults (core.lua);
--   2. виджет — в CreateSettingsPanel ниже (Check / Dropdown / Button):
--      каждая функция сама регистрирует виджет в auction.settingsControls, поэтому значение подхватится при открытии
--      вкладки и после «Сбросить настройки»;
--   3. если настройка меняет вид окна на лету — допиши применение в
--      auction:ApplySettings (core.lua).
-- ============================================================

-- ======================
-- Справочники значений
-- ======================
local COL_W = 286            -- ширина колонки
local LEFT_X, RIGHT_X = 14, 322
local LABEL_W = 112          -- ширина подписи слева от выпадающего списка
local ROW_CHECK = 24         -- высота строки с галочкой
local ROW_DROP = 28          -- высота строки с выпадающим списком / полем
local SECTION_GAP = 12       -- промежуток перед заголовком следующего раздела

local SCALE_VALUES   = { 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5 }       -- как minScale..maxScale
local ALPHA_VALUES   = { 1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3 }
local TOP_BIDS_VALUES = { 1, 2, 3, 4, 5 }

-- Готовые размеры таблицы: высота строки и размер шрифта (имён и ставок).
local TABLE_SIZES = {
    { key = "compact", text = "Компактная", rowHeight = 18, fontSize = 11 },
    { key = "normal",  text = "Обычная",    rowHeight = 20, fontSize = 12 },
    { key = "large",   text = "Крупная",    rowHeight = 26, fontSize = 14 },
}

local COLOR_MODES = {
    { value = "gold",    text = "Золотой" },
    { value = "quality", text = "По редкости" },
}

-- Привязка тултипа в таблице. В списке — самые полезные варианты; остальные
-- значения (из старых настроек) остаются рабочими и показываются по имени.
local ANCHOR_NAMES = {
    CURSOR = "У курсора", RIGHT = "Справа", LEFT = "Слева", TOP = "Сверху", BOTTOM = "Снизу",
    TOPRIGHT = "Сверху справа", TOPLEFT = "Сверху слева",
    BOTTOMRIGHT = "Снизу справа", BOTTOMLEFT = "Снизу слева",
}
local ANCHORS = {
    { value = "CURSOR", text = ANCHOR_NAMES.CURSOR },
    { value = "RIGHT",  text = ANCHOR_NAMES.RIGHT },
    { value = "LEFT",   text = ANCHOR_NAMES.LEFT },
    { value = "TOP",    text = ANCHOR_NAMES.TOP },
    { value = "BOTTOM", text = ANCHOR_NAMES.BOTTOM },
}

-- Звук при перебитой ставке. Первый — файл из папки аддона (значение по
-- умолчанию), остальные — стандартные звуки клиента.
local SOUNDS = {
    { value = "Interface\\AddOns\\EPBossAuction\\sounds\\bid.ogg", text = "Звук аддона" },
    { value = "Sound\\Interface\\RaidWarning.wav",                 text = "Рейд-предупреждение" },
    { value = "Sound\\Interface\\ReadyCheck.wav",                  text = "Проверка готовности" },
    { value = "Sound\\Interface\\AlarmClockWarning3.wav",          text = "Будильник" },
}

-- ======================
-- Мелкие помощники
-- ======================

-- Процент для подписи: 0.5 → "50%".
local function Pct(value)
    return math.floor((tonumber(value) or 0) * 100 + 0.5) .. "%"
end

-- Ближайшее к value значение из списка чисел (текущий масштаб после Ctrl+колесо
-- может быть 0.8999999 — в списке он должен отметиться как 0.9).
local function Near(list, value)
    value = tonumber(value) or list[1]
    local best, bestDiff = list[1], math.huge
    for _, v in ipairs(list) do
        local diff = math.abs(v - value)
        if diff < bestDiff then best, bestDiff = v, diff end
    end
    return best
end

-- Сохраняет и применяет настройки к открытым фреймам (общая точка выхода
-- любого изменения на этой вкладке).
local function Commit()
    auction:ApplySettings()
    auction:SaveSettings()
end

-- Текущий размер таблицы: ключ готового варианта или "custom" (значения из
-- старых ползунков, которых нет в списке).
local function CurrentTableSize()
    local t = auction.db.table
    for _, size in ipairs(TABLE_SIZES) do
        if t.rowHeight == size.rowHeight and t.itemFontSize == size.fontSize and t.bidFontSize == size.fontSize then
            return size.key
        end
    end
    return "custom"
end

-- ======================
-- Сброс настроек
-- ======================
StaticPopupDialogs["EPBA_RESET_SETTINGS"] = {
    text = "Сбросить все настройки EPBA к значениям по умолчанию?\n\nСписок «Мои предметы» и данные аддона не затрагиваются.",
    button1 = "Да", button2 = "Отмена",
    OnAccept = function() auction:ResetSettingsToDefaults() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- Возвращает окно, таблицу, миникарту и звук к значениям по умолчанию.
-- Остальное в auction.db (окно добычи db.lootmaster, учёт «по мейнам» на
-- вкладках Attendance/Статистика, список db.watchlist) не трогает — прежняя
-- кнопка «По умолчанию» заменяла auction.db целиком и стирала и их.
function auction:ResetSettingsToDefaults()
    local db = self.db
    for _, group in ipairs({ "general", "table", "minimap", "window" }) do
        db[group] = self:DeepCopy(self.defaults[group])
    end
    self.minimapButtonPosition = db.minimap.position
    if self.frame then
        self.frame:ClearAllPoints()
        self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    self:ApplySettings()
    if self.UpdateScrollFrameSize then self:UpdateScrollFrameSize() end
    self:SaveSettings()
    self:RefreshSettings()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPBA]|r Настройки сброшены к значениям по умолчанию")
end

-- Перечитывает auction.db и выставляет текущие значения во все виджеты
-- вкладки. Вызывается при открытии вкладки (OnShow), при сбросе и когда
-- масштаб поменялся не из этой вкладки (Ctrl+колесо, /epbazoom+).
-- Виджеты при этом НЕ вызывают свои обработчики (SetChecked/SetText их не
-- запускают), поэтому ничего не рассылается в рейд.
function auction:RefreshSettings()
    if not self.settingsControls then return end
    for _, control in ipairs(self.settingsControls) do
        if control.refresh then control.refresh() end
    end
end

-- ======================
-- Открытие вкладки
-- ======================
-- Открывает главное окно сразу на вкладке «Настройки» (кнопка «Меню» →
-- «Настройки», /epbaoptions, кнопка в Interface Options).
function auction:OpenOptions()
    if not self.frame then return end
    if not self.frame:IsShown() then self.frame:Show() end
    self:ShowMainTab("settings")
end

-- ======================
-- Построение вкладки
-- ======================
-- Строит вкладку «Настройки» в главном окне и «заглушку» в Interface Options.
-- Вызывается один раз из events.lua (ADDON_LOADED) после CreateUI.
function auction:CreateOptionsPanel()
    if self.settingsPanel then return end
    self:CreateSettingsPanel(self.frame)
    self:CreateInterfaceOptionsStub()
    self:Debug("Вкладка настроек создана")
end

function auction:CreateSettingsPanel(frame)
    local H = self.uiHelpers
    local colors = self.theme.colors

    local panel = CreateFrame("Frame", "EPBossAuctionSettingsPanel", frame)
    panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -45)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
    self:SkinPanel(panel)
    panel:Hide()
    panel:SetScript("OnShow", function() auction:RefreshSettings() end)
    self.settingsPanel = panel
    self.settingsControls = {}

    local controls = self.settingsControls

    -- ---- Колонки: курсор y движется вниз по мере добавления виджетов ----
    local function NewColumn(x) return { x = x, y = -12, first = true } end

    -- Заголовок раздела: золотой текст и тонкая линия под ним.
    local function Header(col, text)
        if not col.first then col.y = col.y - SECTION_GAP end
        col.first = false
        local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", panel, "TOPLEFT", col.x, col.y)
        label:SetText(text)
        label:SetTextColor(colors.accent[1], colors.accent[2], colors.accent[3])
        local line = panel:CreateTexture(nil, "ARTWORK")
        line:SetTexture(colors.accent[1], colors.accent[2], colors.accent[3], 0.35)
        line:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
        line:SetSize(COL_W, 1)
        col.y = col.y - 24
        return label, line
    end

    -- Серый поясняющий текст (в несколько строк).
    local function Hint(col, text, height)
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", panel, "TOPLEFT", col.x, col.y)
        fs:SetWidth(COL_W)
        fs:SetJustifyH("LEFT")
        fs:SetTextColor(0.6, 0.6, 0.6)
        fs:SetText(text)
        col.y = col.y - (height or 26)
        return fs
    end

    -- Подсказка при наведении (заголовок золотой, пояснение зелёное — как у кнопок шапки).
    local function AttachTip(widget, title, text)
        if not text then return end
        widget:HookScript("OnEnter", function(w)
            GameTooltip:SetOwner(w, "ANCHOR_RIGHT")
            GameTooltip:AddLine(title)
            GameTooltip:AddLine(text, 0.5, 1, 0.5, true)
            GameTooltip:Show()
        end)
        widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- Регистрация виджета: refresh читает значение из db (RefreshSettings).
    local function Register(refresh)
        table.insert(controls, { refresh = refresh })
    end

    -- Галочка. get() → bool, set(bool) пишет в db.
    local function Check(col, name, label, get, set, tip)
        local box = CreateFrame("CheckButton", name, panel, "UICheckButtonTemplate")
        box:SetSize(20, 20)
        box:SetPoint("TOPLEFT", panel, "TOPLEFT", col.x, col.y)
        box:SetHitRectInsets(0, -(COL_W - 24), 0, 0)
        local text = _G[name .. "Text"]
        text:SetFontObject(GameFontHighlight)
        text:ClearAllPoints()
        text:SetPoint("LEFT", box, "RIGHT", 6, 0)
        text:SetWidth(COL_W - 30)
        text:SetJustifyH("LEFT")
        text:SetText(label)
        auction:SkinCheckbox(box)
        box:HookScript("OnClick", function(b)
            local state = b:GetChecked() and true or false
            H.SetCheckboxChecked(b, state)
            set(state)
        end)
        AttachTip(box, label, tip)
        col.y = col.y - ROW_CHECK
        Register(function() H.SetCheckboxChecked(box, get()) end)
        return box
    end

    -- Выпадающий список с подписью слева. items = { {value=, text=}, ... },
    -- get() → текущее value, set(value) пишет в db; fallback — подпись, если
    -- текущего значения нет в списке; textOf (необязательно) — своя подпись.
    local function Dropdown(col, name, label, items, get, set, fallback, textOf)
        local caption = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        caption:SetPoint("TOPLEFT", panel, "TOPLEFT", col.x, col.y - 5)
        caption:SetWidth(LABEL_W)
        caption:SetJustifyH("LEFT")
        caption:SetText(label)

        local function CurrentText()
            if textOf then return textOf() end
            local value = get()
            for _, item in ipairs(items) do
                if item.value == value then return item.text end
            end
            return fallback or "—"
        end

        local dropdown = H.MakeDropdown(panel, name, COL_W - LABEL_W - 50, col.x + LABEL_W, col.y, CurrentText())
        UIDropDownMenu_Initialize(dropdown, function()
            H.LockDropdownHeight(dropdown)
            local current = get()
            for _, item in ipairs(items) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = item.text
                info.checked = (current == item.value)
                info.func = function()
                    set(item.value)
                    UIDropDownMenu_SetText(dropdown, CurrentText())
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        H.LockDropdownHeight(dropdown)
        auction:SkinDropdown(dropdown)
        col.y = col.y - ROW_DROP
        Register(function() UIDropDownMenu_SetText(dropdown, CurrentText()) end)
        return dropdown
    end

    -- Кнопка (в стиле остальных кнопок аддона). x — смещение от левого края колонки.
    local function Button(col, text, width, onClick, xOffset, keepRow)
        local button = H.MakeButton(auction, panel, text, width, col.x + (xOffset or 0), col.y, onClick)
        if not keepRow then col.y = col.y - ROW_DROP end
        return button
    end

    local left, right = NewColumn(LEFT_X), NewColumn(RIGHT_X)

    -- =====================================================
    -- ЛЕВАЯ КОЛОНКА
    -- =====================================================

    -- ---- Окно ----
    Header(left, "Окно")
    Dropdown(left, "EPBASetScaleDropdown", "Масштаб:",
        (function()
            local list = {}
            for _, v in ipairs(SCALE_VALUES) do table.insert(list, { value = v, text = Pct(v) }) end
            return list
        end)(),
        function() return Near(SCALE_VALUES, auction.windowScale) end,
        function(value) auction:SetWindowScale(value); Commit() end,
        nil, function() return Pct(auction.windowScale) end)

    Dropdown(left, "EPBASetAlphaDropdown", "Прозрачность:",
        (function()
            local list = {}
            for _, v in ipairs(ALPHA_VALUES) do table.insert(list, { value = v, text = Pct(v) }) end
            return list
        end)(),
        function() return Near(ALPHA_VALUES, auction.db.window.alpha) end,
        function(value) auction.db.window.alpha = value; Commit() end,
        nil, function() return Pct(auction.db.window.alpha) end)

    Check(left, "EPBASetLockWindow", "Закрепить окно (запретить перемещение)",
        function() return auction.db.window.locked == true end,
        function(state) auction.db.window.locked = state; Commit() end,
        "Окно нельзя будет перетащить. Масштаб (Ctrl+колесо мыши) и размер (правый нижний угол) менять по-прежнему можно.")

    Button(left, "Сбросить позицию", 136, function()
        if not auction.frame then return end
        auction.db.window.point, auction.db.window.relativePoint = "CENTER", "CENTER"
        auction.db.window.x, auction.db.window.y = 0, 0
        auction.frame:ClearAllPoints()
        auction.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        Commit()
    end, 0, true)
    Button(left, "Сбросить размер", 136, function()
        if not auction.frame then return end
        auction.db.window.width = auction.defaults.window.width
        auction.db.window.height = auction.defaults.window.height
        auction.frame:SetSize(auction.db.window.width, auction.db.window.height)
        if auction.UpdateScrollFrameSize then auction:UpdateScrollFrameSize() end
        Commit()
    end, 144)

    -- ---- Миникарта ----
    Header(left, "Миникарта")
    Check(left, "EPBASetShowMinimap", "Показывать кнопку у миникарты",
        function() return auction.db.minimap.show ~= false end,
        function(state) auction.db.minimap.show = state; Commit() end)
    Button(left, "Сбросить позицию кнопки", 180, function()
        auction.db.minimap.position = { angle = 0 }
        auction.minimapButtonPosition = auction.db.minimap.position
        Commit()
    end)

    -- ---- Таблица ставок ----
    Header(left, "Таблица ставок")
    Dropdown(left, "EPBASetTableSize", "Размер таблицы:",
        (function()
            local list = {}
            for _, size in ipairs(TABLE_SIZES) do table.insert(list, { value = size.key, text = size.text }) end
            return list
        end)(),
        CurrentTableSize,
        function(key)
            for _, size in ipairs(TABLE_SIZES) do
                if size.key == key then
                    local t = auction.db.table
                    t.rowHeight, t.itemFontSize, t.bidFontSize = size.rowHeight, size.fontSize, size.fontSize
                    Commit()
                    return
                end
            end
        end,
        "Своя")

    Dropdown(left, "EPBASetColorMode", "Цвет названий:", COLOR_MODES,
        function() return auction.db.table.itemColorMode or "gold" end,
        function(value) auction.db.table.itemColorMode = value; Commit() end,
        "Золотой")

    Dropdown(left, "EPBASetTopBids", "Ставок в строке:",
        (function()
            local list = {}
            for _, v in ipairs(TOP_BIDS_VALUES) do table.insert(list, { value = v, text = tostring(v) }) end
            return list
        end)(),
        function() return auction.db.table.showTopBids or 2 end,
        function(value) auction.db.table.showTopBids = value; Commit() end,
        "2")

    Dropdown(left, "EPBASetTooltipAnchor", "Подсказки:", ANCHORS,
        function() return auction.db.table.tooltipAnchor or "CURSOR" end,
        function(value) auction.db.table.tooltipAnchor = value; Commit() end,
        nil,
        function() return ANCHOR_NAMES[auction.db.table.tooltipAnchor or "CURSOR"] or "У курсора" end)

    Check(left, "EPBASetShowIcons", "Показывать иконки предметов",
        function() return auction.db.table.showIcons ~= false end,
        function(state) auction.db.table.showIcons = state; Commit() end)

    Check(left, "EPBASetHideNoBids", "Скрывать предметы без ставок",
        function() return auction.db.table.hideNoBids == true end,
        function(state) auction.db.table.hideNoBids = state; Commit() end,
        "В таблице останутся только предметы, на которые уже кто-то поставил.")

    -- =====================================================
    -- ПРАВАЯ КОЛОНКА
    -- =====================================================

    -- ---- Ставки и звук ----
    Header(right, "Ставки и звук")
    Check(right, "EPBASetConfirmBid", "Подтверждать ставку перед отправкой",
        function() return auction.db.general.confirmBid == true end,
        function(state) auction.db.general.confirmBid = state; Commit() end,
        "Перед отправкой ставки появится окно с предметом и суммой.")

    Check(right, "EPBASetSound", "Звук, когда мою ставку перебили",
        function() return auction.db.general.soundEnabled ~= false end,
        function(state) auction.db.general.soundEnabled = state; Commit() end)

    Dropdown(right, "EPBASetSoundFile", "Звук:", SOUNDS,
        function() return auction.db.general.soundFile end,
        function(value)
            auction.db.general.soundFile = value
            Commit()
            PlaySoundFile(value)   -- сразу слышно, что выбрали
        end,
        "Свой файл")

    Button(right, "Проверить звук", 136, function()
        PlaySoundFile(auction.db.general.soundFile or SOUNDS[1].value)
    end)

    Check(right, "EPBASetAnnounce", "Рейд-варн: блокировка и очистка (ЛМ)",
        function() return auction.db.general.announceToRaid == true end,
        function(state) auction.db.general.announceToRaid = state; Commit() end,
        "Для Loot Master: блокировка/разблокировка ставок и очистка таблицы будут объявлены в рейд-варн (или в рейд-чат, если нет прав на варн).")

    -- ---- Мои предметы (белый список) ----
    Header(right, "Мои предметы")
    Check(right, "EPBASetWatchOnly", "Показывать только отмеченные ★",
        function() return auction:IsWatchlistOnly() end,
        function(state) auction:SetWatchlistOnly(state) end,
        "В таблице останутся только предметы, отмеченные звёздочкой. То же делает кнопка «★ Мои» в шапке окна.")
    local count = Hint(right, "", 18)
    Register(function()
        count:SetText("Отмечено предметов: " .. auction:GetWatchedCount())
    end)
    Hint(right, "Звёздочка справа от названия предмета в таблице добавляет его в список. Список общий для всех боссов и хранится только у вас.", 40)
    Button(right, "Очистить список", 136, function()
        StaticPopup_Show("EPBA_CLEAR_WATCHLIST")
    end)

    -- ---- ЕП за боссов (только Loot Master) ----
    -- Раздел целиком показывается только ЛМ (RefreshSettings при открытии вкладки
    -- и при смене состава рейда).
    local epLabel, epLine = Header(right, "ЕП за боссов (Loot Master)")
    local epHint = Hint(right, "", 52)
    local epButton = Button(right, "Настроить", 136, function() auction:ShowBossEPWindow() end)
    Register(function()
        local isLM = auction:IsLootMaster()
        local filled, total = 0, 0
        for _, boss in ipairs(auction.bossOrder or {}) do
            total = total + 1
            if auction:GetBossEP(boss) then filled = filled + 1 end
        end
        epHint:SetText("Сколько ЕП рейд получает за каждого босса. Число подставляется в окне добычи в блок «Массовое начисление». Заполнено: " .. filled .. " из " .. total .. ".")
        for _, widget in ipairs({ epLabel, epLine, epHint, epButton }) do
            if isLM then widget:Show() else widget:Hide() end
        end
    end)

    -- =====================================================
    -- НИЖНЯЯ СТРОКА
    -- =====================================================
    local debugBox = Check(left, "EPBASetDebug", "Режим отладки",
        function() return auction.db.general.debug == true end,
        function(state) auction.db.general.debug = state; Commit() end,
        "Подробный журнал работы аддона в чат. Нужен разработчику; для диагностики лучше «Меню» → «Нашли баг?».")
    debugBox:ClearAllPoints()
    debugBox:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", LEFT_X, 12)

    local resetButton = H.MakeButton(self, panel, "Сбросить настройки", 150, 0, 0, function()
        StaticPopup_Show("EPBA_RESET_SETTINGS")
    end)
    resetButton:ClearAllPoints()
    resetButton:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 12)

    self:RefreshSettings()
end

-- ======================
-- Interface Options (заглушка)
-- ======================
-- В «Интерфейс → Модификации → EP Boss Auction» осталась только кнопка,
-- которая открывает вкладку «Настройки» главного окна.
function auction:CreateInterfaceOptionsStub()
    local panel = CreateFrame("Frame", "EPBossAuctionOptionsPanel", UIParent)
    panel.name = "EP Boss Auction"
    panel:Hide()

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("EP Boss Auction")

    local info = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    info:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    info:SetWidth(460)
    info:SetJustifyH("LEFT")
    info:SetText("Настройки находятся в главном окне аддона: вкладка с шестерёнкой слева от окна (то же: «Меню» → «Настройки» или команда /epbaoptions).")

    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(200, 25)
    button:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -16)
    button:SetText("Открыть настройки")
    button:SetScript("OnClick", function()
        if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then
            HideUIPanel(InterfaceOptionsFrame)
        end
        auction:OpenOptions()
    end)

    InterfaceOptions_AddCategory(panel)
    self.optionsPanel = panel
end
