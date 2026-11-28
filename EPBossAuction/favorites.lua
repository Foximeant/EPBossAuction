local auction = EPBossAuction

-- ============================================================
-- favorites.lua — вкладка «Избранные предметы»
-- ============================================================
-- Показывает ВСЕ предметы, отмеченные звёздочкой ★ (auction.db.watchlist, см.
-- watchlist.lua), сразу со всех боссов: сгруппированы по боссам, у каждого — топ ставок
-- (как в основной таблице), клик по предмету выбирает его, снизу — поле ставки, галочка
-- офф-спека, «Сделать ставку» и «Снять ставку». Звёздочка справа в строке убирает предмет
-- из избранного. Основная таблица и фильтр «★ Мои» работают как раньше.
--
-- Вкладка видна всем игрокам (квадратная кнопка слева, см. TAB_DEFS в attendance_ui.lua).
--
-- Ставки: общая логика — auction:PlaceBid (UI.lua): те же проверки, подтверждение и отправка,
-- что и у основной таблицы; босс и предмет передаются явно, потому что на этой вкладке
-- предметы разных боссов, а auction.selectedBoss не используется и не меняется.
--
-- Данные: ставки по всем боссам хранятся у каждого клиента (SYNC от ЛМ принимается по любому
-- боссу), но при входе в игру клиент запрашивает у ЛМ только выбранного босса. Поэтому при
-- открытии вкладки (не чаще раза в REQUEST_THROTTLE секунд) и по кнопке «Обновить ставки»
-- шлём ЛМ HELLO по каждому боссу с избранным. ЛМ копит HELLO от одного игрока 1 секунду
-- (LM_REPLY_DELAY в comm.lua) и запоминает только последний, поэтому запросы идут с
-- интервалом REQUEST_STAGGER и с разными ключами очереди.
--
-- Что вызывает эту вкладку снаружи (все вызовы безопасны, пока окно не создано):
--   FavoritesBidsChanged   — ставки изменились (ApplyBidChange, Handle_BID, Handle_SYNC);
--   FavoritesRefreshSoon   — изменился список избранного или резерв;
--   FavoritesUpdateBar     — изменились ЕП / блокировка ставок (нижняя панель).
-- ============================================================

local BAR_H = 76
local REQUEST_THROTTLE = 120    -- сек: не чаще при открытии вкладки (кнопка «Обновить ставки» — без ограничения)
local REQUEST_STAGGER = 1.2     -- сек между запросами по разным боссам (см. шапку)
local MAX_REQUEST_BOSSES = 8
local ITEM_RETRY, ITEM_RETRY_MAX = 0.6, 12
local STAR_GOLD = { 1.0, 0.82, 0.0 }

auction.favState = auction.favState or {}   -- { boss, itemID } — выбранный предмет
auction.favRows = auction.favRows or {}

local function Notice(text)
    UIErrorsFrame:AddMessage(text, 1.0, 0.5, 0.0, 3)
end

local function Backdrop(frame, bg, border)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

local function MakeBtn(parent, text, width, point, x, y, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 24)
    b:SetPoint(point, parent, point, x, y)
    b:SetText(text)
    b:SetNormalFontObject(GameFontNormal)
    auction:SkinButton(b)
    b:SetScript("OnClick", onClick)
    return b
end

-- ======================
-- Данные
-- ======================

-- Группы избранного: { { boss, instance, items = {itemID, ...} }, ... } — боссы в порядке
-- подземелий из auction.instanceOrder, предметы — в порядке таблицы босса. Предмет, который
-- есть в таблицах нескольких боссов, попадёт в каждую группу (ставки у боссов раздельные).
function auction:GetFavoriteGroups()
    local groups, seen = {}, {}
    local watch = self:GetWatchlist()
    local function addBoss(boss)
        if seen[boss] then return end
        seen[boss] = true
        local items = self.bosses[boss]
        if not items then return end
        local list = {}
        for _, id in ipairs(items) do
            if watch[id] then list[#list + 1] = id end
        end
        if #list > 0 then
            groups[#groups + 1] = { boss = boss, instance = self.bossToInstance[boss], items = list }
        end
    end
    for _, instanceName in ipairs(self.instanceOrder) do
        for _, boss in ipairs(self.instances[instanceName] or {}) do addBoss(boss) end
    end
    -- Боссы, которых нет в instances (на всякий случай): по алфавиту, чтобы порядок был стабильным
    local rest = {}
    for boss in pairs(self.bosses) do
        if not seen[boss] then rest[#rest + 1] = boss end
    end
    table.sort(rest)
    for _, boss in ipairs(rest) do addBoss(boss) end
    return groups
end

local function MyBid(boss, itemID)
    local bids = auction.bids[boss] and auction.bids[boss][itemID]
    local me = UnitName("player")
    for _, b in ipairs(bids or {}) do
        if b.player == me then return b end
    end
    return nil
end

-- Топ ставок строкой: «Игрок - 500 | Игрок - 450 (O)», как в основной таблице.
local function BidsText(boss, itemID)
    local n = auction.db.table.showTopBids or 2
    local bids = auction.sortedBids[boss] and auction.sortedBids[boss][itemID] or {}
    local text = ""
    for j = 1, n do
        local b = bids[j]
        if not b then break end
        local part = auction:FormatColoredName(b.player).." - "..auction:FormatNumber(b.amount)..(b.isOffspec and " (O)" or "")
        text = (j == 1) and part or (text.." | "..part)
    end
    return text
end

-- ======================
-- Запрос ставок у ЛМ
-- ======================
function auction:FavoritesRequestData(force)
    if self:IsLootMaster() then return end   -- у ЛМ данные и так полные
    if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then return end
    local now = GetTime()
    if not force and self._favRequestedAt and (now - self._favRequestedAt) < REQUEST_THROTTLE then return end
    self._favRequestedAt = now

    local bosses = {}
    for _, g in ipairs(self:GetFavoriteGroups()) do
        if #bosses < MAX_REQUEST_BOSSES then bosses[#bosses + 1] = g.boss end
    end
    for i, boss in ipairs(bosses) do
        self:ScheduleTimer(function()
            auction:SendToLootMaster("HELLO;"..boss, 2, "HELLO:"..boss)
        end, (i - 1) * REQUEST_STAGGER)
    end
    if force then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[EPBA]|r Запрошены ставки у ЛМ по боссам с избранным: "..#bosses..".")
    end
end

-- ======================
-- Панель
-- ======================
function auction:CreateFavoritesPanel(frame)
    local c = self.theme.colors
    local panel = CreateFrame("Frame", "EPBossAuctionFavPanel", frame)
    panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -45)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    panel:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    panel:SetBackdropBorderColor(0, 0, 0, 1)
    self:SkinPanel(panel)
    panel:Hide()
    self.favPanel = panel

    -- Шапка
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -9)
    title:SetTextColor(c.accent[1], c.accent[2], c.accent[3])
    title:SetText("Избранные предметы")
    local count = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    count:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -30)
    count:SetTextColor(0.65, 0.65, 0.65)
    self.favCount = count

    local refresh = MakeBtn(panel, "Обновить ставки", 130, "TOPRIGHT", -10, -8, function()
        auction:FavoritesRequestData(true)
        auction:RefreshFavorites()
    end)
    refresh:HookScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Запросить ставки у ЛМ")
        GameTooltip:AddLine("Просит ЛМ прислать ставки по всем боссам, у которых есть избранные предметы. Обычно не нужно: ставки приходят сами.", 0.5, 1, 0.5, true)
        GameTooltip:Show()
    end)
    refresh:HookScript("OnLeave", function() GameTooltip:Hide() end)
    self.favRefreshBtn = refresh

    -- Таблица
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(0, 0, 0, 0.25)
    bg:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -52)
    bg:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, BAR_H + 6)

    local scroll = CreateFrame("ScrollFrame", "EPBossAuctionFavScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -52)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, BAR_H + 6)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(580, 1)
    scroll:SetScrollChild(content)
    self.favScroll, self.favContent = scroll, content
    local scrollBar = _G["EPBossAuctionFavScrollScrollBar"]
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 22, -17)
        scrollBar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 22, 17)
        self:SkinScrollBar(scrollBar)
    end

    local empty = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    empty:SetPoint("CENTER", panel, "CENTER", 0, 20)
    empty:SetWidth(460)
    empty:SetJustifyH("CENTER")
    empty:SetTextColor(0.6, 0.6, 0.6)
    empty:SetText("Избранных предметов пока нет.\nОтметьте нужные звёздочкой справа от названия в таблице на вкладке «Ставки»: они появятся здесь, со всех боссов сразу.")
    self.favEmpty = empty

    self:BuildFavoritesBar(panel)

    panel:SetScript("OnShow", function()
        auction:RefreshFavorites()
        auction:FavoritesRequestData(false)
    end)
end

-- Нижняя панель: выбранный предмет, поле ставки, офф-спек, кнопки.
function auction:BuildFavoritesBar(panel)
    local c = self.theme.colors
    local bar = CreateFrame("Frame", nil, panel)
    bar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 6, 6)
    bar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 6)
    bar:SetHeight(BAR_H)
    Backdrop(bar, c.inputBg, c.border)
    self.favBar = bar

    self.favSelText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.favSelText:SetPoint("TOPLEFT", bar, "TOPLEFT", 10, -10)
    self.favSelText:SetWidth(400)
    self.favSelText:SetJustifyH("LEFT")
    self.favSelText:SetWordWrap(false)
    self.favMyBid = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.favMyBid:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -10, -12)
    self.favMyBid:SetJustifyH("RIGHT")

    local box = CreateFrame("EditBox", "EPBossAuctionFavBidBox", bar, "InputBoxTemplate")
    box:SetSize(100, 25)
    box:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 16, 10)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(6)
    box:SetScript("OnEnterPressed", function() auction:FavoritesSendBid() end)
    box:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
    box:SetScript("OnTextChanged", function() auction:FavoritesUpdateBar() end)
    self:SkinInput(box)
    self.favBidBox = box

    local cb = CreateFrame("CheckButton", "EPBossAuctionFavOffspec", bar, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb:SetPoint("LEFT", box, "RIGHT", 12, 0)
    local cbText = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cbText:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cbText:SetText("Офф-спек")
    cb:SetChecked(false)
    cb:SetScript("OnClick", function() auction:FavoritesUpdateBar() end)
    self:SkinCheckbox(cb)
    self.favOffspec = cb

    self.favMaxText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.favMaxText:SetPoint("LEFT", cbText, "RIGHT", 14, 0)
    self.favMaxText:SetJustifyH("LEFT")

    self.favCancelBtn = MakeBtn(bar, "Снять ставку", 100, "BOTTOMRIGHT", -10, 10, function()
        auction:FavoritesSendBid(0)
    end)
    self.favBidBtn = MakeBtn(bar, "Сделать ставку", 130, "BOTTOMRIGHT", -116, 10, function()
        auction:FavoritesSendBid()
    end)
end

-- Ставка на выбранный предмет. amount = 0 — снять свою ставку.
function auction:FavoritesSendBid(amount)
    local st = self.favState
    if not (st.boss and st.itemID) then
        Notice("Сначала выберите предмет в списке")
        return
    end
    local isOffspec = false
    if amount == nil then
        amount = tonumber(self.favBidBox:GetText())
        if not amount then
            Notice("Введите сумму ставки")
            return
        end
        isOffspec = self.favOffspec:GetChecked() and true or false
    end
    self:PlaceBid(st.boss, st.itemID, amount, isOffspec, function()
        auction.favBidBox:SetText("")
    end)
end

-- Обновляет нижнюю панель: выбранный предмет, моя ставка, максимум по ЕП, доступность кнопок.
function auction:FavoritesUpdateBar()
    if not self.favBar then return end
    local st = self.favState
    local has = st.boss and st.itemID

    local mine
    if has then
        local name = self:GetCachedItemName(st.itemID, st.boss)
        self.favSelText:SetText("Выбрано: |cffffd200"..name.."|r  |cff999999"..st.boss.."|r")
        mine = MyBid(st.boss, st.itemID)
        if mine then
            self.favMyBid:SetTextColor(0.5, 1, 0.5)
            self.favMyBid:SetText("Ваша ставка: "..self:FormatNumber(mine.amount)..(mine.isOffspec and " (офф-спек)" or ""))
        else
            self.favMyBid:SetTextColor(0.65, 0.65, 0.65)
            self.favMyBid:SetText("Вашей ставки нет")
        end
    else
        self.favSelText:SetText("|cff999999Кликните по предмету в списке, чтобы сделать ставку|r")
        self.favMyBid:SetText("")
    end

    local isOffspec = self.favOffspec:GetChecked() and true or false
    local maxBid = self:GetMaxBidAmount(isOffspec)
    local typed = tonumber(self.favBidBox:GetText()) or 0
    self.favMaxText:SetText("Макс. ставка: "..self:FormatNumber(maxBid))
    if typed > 0 and typed > maxBid then
        self.favMaxText:SetTextColor(1, 0, 0)
        self.favBidBox:SetTextColor(1, 0, 0)
    else
        self.favMaxText:SetTextColor(0.7, 0.7, 0.7)
        self.favBidBox:SetTextColor(1, 1, 1)
    end

    local locked = self.bidsLocked and true or false
    self.favBidBtn:SetText(locked and "Ставки закрыты" or "Сделать ставку")
    if has and not locked then self.favBidBtn:Enable() else self.favBidBtn:Disable() end
    if has and mine and not locked then self.favCancelBtn:Enable() else self.favCancelBtn:Disable() end
end

-- ======================
-- Строки списка
-- ======================
local function SelectFavorite(boss, itemID)
    if auction:IsReserved(boss, itemID) then
        auction:ReserveClickNotice()
        return
    end
    local st = auction.favState
    st.boss, st.itemID = boss, itemID
    auction:RefreshFavorites()
    auction.favBidBox:SetFocus()
end

local function RowBgColor(row)
    local t = auction.db.table
    if row.isHeader then return { 0.8, 0.62, 0.1, 0.14 } end
    local st = auction.favState
    if st.boss == row.boss and st.itemID == row.itemID then
        return t.selectedRowColor or { 0.80, 0.62, 0.10, 0.30 }
    end
    if row.index % 2 == 0 then return t.evenRowColor or { 1, 1, 1, 0.03 } end
    return t.oddRowColor or { 0, 0, 0, 0 }
end

local function PaintRow(row)
    local c = RowBgColor(row)
    row.bg:SetTexture(c[1], c[2], c[3], c[4])
end

local function CreateFavRow()
    local row = CreateFrame("Button", nil, auction.favContent)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    row.headText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.headText:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.headText:SetJustifyH("LEFT")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.itemName = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.itemName:SetJustifyH("LEFT")
    row.itemName:SetWordWrap(false)
    row.bidsStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.bidsStr:SetJustifyH("LEFT")
    row.bidsStr:SetWordWrap(false)

    local function hover(r)
        local t = auction.db.table.hoverRowColor or { 1, 1, 1, 0.08 }
        if not (auction.favState.boss == r.boss and auction.favState.itemID == r.itemID) then
            r.bg:SetTexture(t[1], t[2], t[3], t[4])
        end
    end

    -- Левая зона (предмет): выбор и тултип предмета
    row.left = CreateFrame("Button", nil, row)
    row.left:RegisterForClicks("LeftButtonUp")
    row.left:SetScript("OnClick", function() if row.itemID then SelectFavorite(row.boss, row.itemID) end end)
    row.left:SetScript("OnEnter", function(z)
        if not row.itemID then return end
        GameTooltip:SetOwner(z, auction:GetTooltipAnchor())
        GameTooltip:SetHyperlink("item:"..row.itemID)
        auction:AppendReserveTooltip(row.itemID, row.boss)
        GameTooltip:Show()
        hover(row)
    end)
    row.left:SetScript("OnLeave", function() GameTooltip:Hide(); PaintRow(row) end)

    -- Правая зона (ставки): выбор и тултип со всеми ставками
    row.right = CreateFrame("Button", nil, row)
    row.right:RegisterForClicks("LeftButtonUp")
    row.right:SetScript("OnClick", function() if row.itemID then SelectFavorite(row.boss, row.itemID) end end)
    row.right:SetScript("OnEnter", function(z)
        if not row.itemID then return end
        GameTooltip:SetOwner(z, auction:GetTooltipAnchor())
        auction:ShowBidsTooltip(row.itemID, row.boss)
        hover(row)
    end)
    row.right:SetScript("OnLeave", function() GameTooltip:Hide(); PaintRow(row) end)

    -- Звёздочка: убрать из избранного
    row.star = CreateFrame("Button", nil, row)
    row.star:SetSize(18, 18)
    row.star:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.star:SetFrameLevel(row:GetFrameLevel() + 5)
    local mark = row.star:CreateFontString(nil, "OVERLAY")
    mark:SetPoint("CENTER", 0, 0)
    if auction:TrySetSymbolFont(mark, 14) then
        mark:SetText("★")
    else
        mark:SetFontObject(GameFontNormal)
        mark:SetText("*")
    end
    mark:SetTextColor(STAR_GOLD[1], STAR_GOLD[2], STAR_GOLD[3])
    row.star:SetScript("OnClick", function()
        if row.itemID then
            auction:SetWatched(row.itemID, false)
            auction:AfterWatchlistChanged()
        end
    end)
    row.star:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:AddLine("В избранном")
        GameTooltip:AddLine("Нажмите, чтобы убрать предмет из избранного", 0.5, 1, 0.5, true)
        GameTooltip:Show()
    end)
    row.star:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

-- Заполняет строку. Возвращает true, если название предмета ещё не пришло из кэша клиента.
local function FillFavRow(row, entry, index, m)
    row.index = index
    row.boss, row.itemID = entry.boss, entry.itemID
    row.isHeader = entry.header and true or nil
    row:SetSize(m.width, m.rowHeight)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", auction.favContent, "TOPLEFT", 0, -(index - 1) * m.rowHeight)

    if entry.header then
        row.headText:SetText(entry.boss
            ..(entry.instance and ("  |cff888888"..entry.instance.."|r") or "")
            .."  |cff999999("..entry.count..")|r")
        row.headText:Show()
        row.icon:Hide(); row.itemName:SetText(""); row.bidsStr:SetText("")
        row.left:Hide(); row.right:Hide(); row.star:Hide()
        row.itemName:SetAlpha(1); row.icon:SetAlpha(1)
        PaintRow(row)
        return false
    end

    row.headText:Hide()
    row.left:Show(); row.right:Show(); row.star:Show()
    row.left:ClearAllPoints()
    row.left:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.left:SetPoint("BOTTOMRIGHT", row, "BOTTOMLEFT", m.itemWidth, 0)
    row.right:ClearAllPoints()
    row.right:SetPoint("TOPLEFT", row, "TOPLEFT", m.itemWidth, 0)
    row.right:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -28, 0)

    local name, icon = auction:GetCachedItemInfo(entry.itemID, entry.boss)
    local pending = not name
    row.itemName:SetText(name or "Загрузка...")
    row.itemName:SetFont(GameFontNormal:GetFont(), m.itemFontSize)
    row.itemName:ClearAllPoints()
    row.itemName:SetWidth(m.itemWidth - (m.showIcons and 32 or 12))
    if m.colorMode == "gold" then
        row.itemName:SetTextColor(1, 0.8, 0)
    else
        local _, _, quality = GetItemInfo(entry.itemID)
        local qc = quality and ITEM_QUALITY_COLORS[quality]
        if qc then row.itemName:SetTextColor(qc.r, qc.g, qc.b) else row.itemName:SetTextColor(1, 1, 1) end
    end
    if m.showIcons and icon then
        local size = math.max(12, m.rowHeight - 4)
        row.icon:SetSize(size, size)
        row.icon:SetTexture(icon)
        row.icon:Show()
        row.itemName:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    else
        row.icon:Hide()
        row.itemName:SetPoint("LEFT", row, "LEFT", 8, 0)
    end

    row.bidsStr:SetText(BidsText(entry.boss, entry.itemID))
    row.bidsStr:SetFont(GameFontNormal:GetFont(), m.bidFontSize)
    row.bidsStr:ClearAllPoints()
    row.bidsStr:SetPoint("LEFT", row, "LEFT", m.itemWidth + 10, 0)
    row.bidsStr:SetWidth(math.max(10, m.width - m.itemWidth - 44))
    auction:ApplyReserveMark(row, entry.boss, entry.itemID)   -- резерв: приглушает строку и пишет «Резерв»

    PaintRow(row)
    return pending
end

function auction:RefreshFavorites()
    if not self.favPanel then return end
    local groups = self:GetFavoriteGroups()
    local entries, total = {}, 0
    for _, g in ipairs(groups) do
        entries[#entries + 1] = { header = true, boss = g.boss, instance = g.instance, count = #g.items }
        for _, id in ipairs(g.items) do
            entries[#entries + 1] = { boss = g.boss, itemID = id }
            total = total + 1
        end
    end

    -- Выбранный предмет мог пропасть из избранного
    local st = self.favState
    if st.itemID then
        local found = false
        for _, e in ipairs(entries) do
            if e.itemID == st.itemID and e.boss == st.boss then found = true break end
        end
        if not found then st.boss, st.itemID = nil, nil end
    end

    local orphans = self:GetWatchedCount()
    local distinct = {}
    for _, e in ipairs(entries) do if e.itemID then distinct[e.itemID] = true end end
    local distinctCount = 0
    for _ in pairs(distinct) do distinctCount = distinctCount + 1 end
    orphans = orphans - distinctCount
    local countText = total == 0 and "Список пуст" or (total.." предм. у "..#groups.." боссов")
    if orphans > 0 then
        countText = countText.."  |cffff9955(ещё "..orphans.." отмеченных нет в таблицах боссов)|r"
    end
    self.favCount:SetText(countText)
    if total == 0 then self.favEmpty:Show() else self.favEmpty:Hide() end

    local t = self.db.table
    local scrollWidth = self.favScroll:GetWidth()
    if scrollWidth < 100 then scrollWidth = 580 end
    local width = scrollWidth - 4
    local itemWidth = math.max(150, math.min(math.floor(width * 0.45), width - 100))
    local m = {
        width = width, itemWidth = itemWidth, rowHeight = math.max(20, t.rowHeight or 20),
        showIcons = t.showIcons ~= false, itemFontSize = t.itemFontSize or 12,
        bidFontSize = t.bidFontSize or 12, colorMode = t.itemColorMode or "gold",
    }
    self.favContent:SetWidth(width)

    local pending = false
    for i, entry in ipairs(entries) do
        local row = self.favRows[i]
        if not row then
            row = CreateFavRow()
            self.favRows[i] = row
        end
        if FillFavRow(row, entry, i, m) then pending = true end
        row:Show()
    end
    for i = #entries + 1, #self.favRows do
        local row = self.favRows[i]
        row.itemID, row.boss, row.isHeader = nil, nil, nil
        row:Hide()
    end
    self.favContent:SetHeight(math.max(1, #entries * m.rowHeight))

    if pending then self:FavoritesScheduleItemRetry() end
    self:FavoritesUpdateBar()
end

-- Предметы, которых нет в кэше клиента: перечитываем позже (как это делает основная таблица).
function auction:FavoritesScheduleItemRetry()
    if self._favItemTimer or (self._favRetries or 0) >= ITEM_RETRY_MAX then return end
    self._favRetries = (self._favRetries or 0) + 1
    self._favItemTimer = self:ScheduleTimer(function()
        auction._favItemTimer = nil
        if auction.favPanel and auction.favPanel:IsVisible() then auction:RefreshFavorites() end
    end, ITEM_RETRY)
end

-- ======================
-- Уведомления извне (безопасно вызывать, пока вкладка не создана или закрыта)
-- ======================
-- Перерисовка с задержкой 0.15 с: серия входящих SYNC схлопывается в одну.
function auction:FavoritesRefreshSoon()
    if not (self.favPanel and self.favPanel:IsVisible()) then return end
    if self._favRefreshTimer then return end
    self._favRefreshTimer = self:ScheduleTimer(function()
        auction._favRefreshTimer = nil
        if auction.favPanel and auction.favPanel:IsVisible() then
            auction._favRetries = 0
            auction:RefreshFavorites()
        end
    end, 0.15)
end

function auction:FavoritesBidsChanged()
    self:FavoritesRefreshSoon()
end
