local auction = EPBossAuction

-- ============================================================
-- watchlist.lua — белый список предметов («Мои предметы»)
-- ============================================================
-- Личный фильтр таблицы ставок: игрок отмечает нужные предметы звёздочкой
-- (★ справа в колонке предметов), а кнопка «★ Мои» в шапке окна включает
-- режим «показывать только отмеченные». Всё хранится у игрока локально
-- (auction.db.watchlist = { [itemID] = true }), в сеть ничего не уходит и
-- на ставки/синхронизацию не влияет — это только то, что рисует таблица.
--
-- Список общий для всех боссов: предмет, который падает с нескольких
-- боссов, отмечается один раз. Правый клик по строке (скрыть предмет до
-- конца сессии) работает независимо от списка.
-- Вкладка «Избранное» (favorites.lua) показывает ВСЕ отмеченные предметы сразу
-- со всех боссов, со ставками и возможностью поставить прямо оттуда.
--
-- Где используется:
--   UI.lua      CreateRowTemplate → CreateRowStar; RenderItemRow/RefreshTable →
--               LayoutRowStar/UpdateRowStar; RefreshTable фильтрует по
--               IsWatchlistOnly()/IsWatched();
--   options.lua раздел «Мои предметы» (галочка, счётчик, очистка);
--   attendance_ui.lua ShowMainTab прячет кнопку «★ Мои» вне вкладки «Ставки».
-- ============================================================

auction.STAR_SPACE = 20   -- сколько места в колонке предметов занимает звёздочка

local STAR_GOLD = { 1.0, 0.82, 0.0 }
local STAR_OFF  = { 0.45, 0.45, 0.45 }

-- ======================
-- Данные
-- ======================
function auction:GetWatchlist()
    self.db.watchlist = self.db.watchlist or {}
    return self.db.watchlist
end

function auction:IsWatched(itemID)
    local list = self.db and self.db.watchlist
    return (list and itemID and list[itemID] == true) and true or false
end

function auction:SetWatched(itemID, state)
    if not itemID then return end
    self:GetWatchlist()[itemID] = state and true or nil
    self:SaveSettings()
end

function auction:ToggleWatched(itemID)
    self:SetWatched(itemID, not self:IsWatched(itemID))
end

-- Сколько предметов в списке.
function auction:GetWatchedCount()
    local count = 0
    for _ in pairs(self:GetWatchlist()) do count = count + 1 end
    return count
end

-- Очищает весь список.
function auction:ClearWatchlist()
    self.db.watchlist = {}
    self:SaveSettings()
    self:AfterWatchlistChanged()
end

-- Включён ли режим «только отмеченные».
function auction:IsWatchlistOnly()
    return self.db and self.db.table and self.db.table.watchlistOnly == true
end

function auction:SetWatchlistOnly(state)
    self.db.table.watchlistOnly = state and true or false
    self:SaveSettings()
    self:AfterWatchlistChanged()
end

-- Обновляет всё, что показывает состояние списка: кнопку в шапке, вкладку
-- настроек (если открыта) и таблицу.
function auction:AfterWatchlistChanged()
    self:UpdateWatchButton()
    if self.settingsPanel and self.settingsPanel:IsShown() then self:RefreshSettings() end
    self:RequestRefresh()
    self:FavoritesRefreshSoon()   -- вкладка «Избранное» (favorites.lua) показывает весь этот список
end

StaticPopupDialogs["EPBA_CLEAR_WATCHLIST"] = {
    text = "Очистить список «Мои предметы»?\nОтметки со всех предметов будут сняты.",
    button1 = "Да", button2 = "Отмена",
    OnAccept = function() auction:ClearWatchlist() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- ======================
-- Кнопка «★ Мои» в шапке окна
-- ======================
-- Стоит левее кнопки «Меню», видна только на вкладке «Ставки».
function auction:CreateWatchlistButton(frame, anchor)
    local btn = CreateFrame("Button", "EPBossAuctionWatchButton", frame)
    btn:SetSize(66, 22)
    btn:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -8, 0)
    self:SkinButton(btn)

    -- Свой текст вместо SetText: символ ★ есть только в шрифте аддона, а
    -- состояние кнопки (наведение) не должно сбрасывать шрифт.
    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetPoint("CENTER", 0, 0)
    if self:TrySetSymbolFont(label, 12) then
        label:SetText("★ Мои")
    else
        label:SetFontObject(GameFontNormal)
        label:SetText("Мои")
    end
    btn.label = label

    btn:SetScript("OnClick", function()
        auction:SetWatchlistOnly(not auction:IsWatchlistOnly())
    end)
    btn:HookScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Только мои предметы")
        local state = auction:IsWatchlistOnly() and "включено" or "выключено"
        GameTooltip:AddLine("Сейчас: " .. state .. ". Отмечено предметов: " .. auction:GetWatchedCount(), 0.5, 1, 0.5, true)
        GameTooltip:AddLine("Отметить предмет — звёздочка справа от его названия в таблице.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    self.watchButton = btn
    self:UpdateWatchButton()
end

-- Подсвечивает кнопку, когда режим включён (золотой текст и рамка).
function auction:UpdateWatchButton()
    local btn = self.watchButton
    if not btn then return end
    local c = self.theme.colors
    if self:IsWatchlistOnly() then
        btn.label:SetTextColor(STAR_GOLD[1], STAR_GOLD[2], STAR_GOLD[3])
        btn:SetBackdropBorderColor(c.accent[1], c.accent[2], c.accent[3], 1)
    else
        btn.label:SetTextColor(0.8, 0.8, 0.8)
        btn:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], c.border[4])
    end
end

-- ======================
-- Звёздочка в строке таблицы
-- ======================
-- Создаётся один раз вместе со строкой (CreateRowTemplate).
function auction:CreateRowStar(row)
    local star = CreateFrame("Button", nil, row)
    star:SetSize(16, 16)
    star:SetFrameLevel(row:GetFrameLevel() + 5)   -- выше областей клика по строке
    star:RegisterForClicks("LeftButtonUp")

    local mark = star:CreateFontString(nil, "OVERLAY")
    mark:SetPoint("CENTER", 0, 0)
    if self:TrySetSymbolFont(mark, 14) then
        mark:SetText("★")
    else
        mark:SetFontObject(GameFontNormal)
        mark:SetText("*")
    end
    star.mark = mark

    star:SetScript("OnClick", function()
        if not row.itemID then return end
        auction:ToggleWatched(row.itemID)
        auction:UpdateRowStar(row)
        if auction:IsWatchlistOnly() then auction:RequestRefresh() end  -- снятая отметка уберёт строку
    end)
    star:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        if row.itemID and auction:IsWatched(row.itemID) then
            GameTooltip:AddLine("В списке «Мои предметы»")
            GameTooltip:AddLine("Нажмите, чтобы снять отметку", 0.5, 1, 0.5)
        else
            GameTooltip:AddLine("Отметить как «мой» предмет")
            GameTooltip:AddLine("Кнопка «★ Мои» вверху покажет только отмеченные", 0.5, 1, 0.5, true)
        end
        GameTooltip:Show()
    end)
    star:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.star = star
end

-- Ставит звёздочку у правого края колонки предметов (itemWidth — ширина колонки).
function auction:LayoutRowStar(row, itemWidth)
    if not row.star then return end
    row.star:ClearAllPoints()
    row.star:SetPoint("RIGHT", row, "LEFT", itemWidth - 4, 0)
    row.star:Show()
end

-- Красит звёздочку по состоянию предмета строки (золотая — в списке, серая — нет).
function auction:UpdateRowStar(row)
    if not row.star then return end
    local marked = row.itemID and self:IsWatched(row.itemID)
    local color = marked and STAR_GOLD or STAR_OFF
    row.star.mark:SetTextColor(color[1], color[2], color[3])
    row.star.mark:SetAlpha(marked and 1 or 0.6)
end
