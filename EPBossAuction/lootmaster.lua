local auction = EPBossAuction

-- ============================================================
-- lootmaster.lua — окно выдачи добычи для лутмастера
-- ============================================================
-- Окно появляется ТОЛЬКО у ЛМ, в рейде, при открытии окна добычи
-- (LOOT_OPENED). Показывает выпавшие предметы; под каждым — топ ставок
-- (кликом выбирается победитель) и кнопки «Выдать», «Выдать себе»,
-- «Списать ЕП». В шапке — выбор босса и кнопка массового начисления ЕП
-- (причина = имя босса).
--
-- Как это работает (и почему прошлая версия не работала):
--   * В 3.3.5a GetMasterLootCandidate принимает ОДИН аргумент — индекс
--     кандидата (а не слот и индекс, как в поздних версиях). Индексы
--     читаются перебором 1..40 БЕЗ остановки на первом nil: пропуски
--     бывают (игрок далеко/оффлайн/не в зоне лута).
--   * Статус «выдан» ставится ТОЛЬКО по событию LOOT_SLOT_CLEARED, а не
--     сразу после GiveMasterLoot. Если за GIVE_TIMEOUT секунд слот не
--     очистился — строка возвращается в «не выдан» с пояснением.
--   * Состояние хранится ПО СЛОТУ (а не по itemID), поэтому два одинаковых
--     предмета не мешают друг другу.
--   * «Списать ЕП» доступна только после успешной выдачи и срабатывает
--     один раз на запись. Списание = EPGP:IncEPBy(имя, причина, -сумма)
--     (на сервере EPGP принимает отрицательные значения). EPGP начисляет/
--     списывает ЕП МЕЙНУ игрока — твинк, получивший предмет, списывается с мейна.
--   * Окно НЕ закрывается само, пока есть выданные, но не списанные
--     предметы: после выдачи последнего предмета Blizzard закрывает окно
--     добычи, но кнопка «Списать ЕП» остаётся доступной.
--
-- Данные:
--   auction.lootEntries — записи окна (одна на слот добычи), поля:
--     slot, itemID, link, name, icon, quantity, boss,
--     status = "open" | "giving" | "given" | "charged",
--     selected (выбранный победитель), winner (кому выдано), amount (сколько списать)
--   EPBossAuctionSavedLootLog — журнал выдач и массовых начислений (источник вкладки
--   «Статистика»), см. LootJournalAdd, LootJournalAddMass и stats.lua.
--   auction.db.lootmaster — позиция окна и последняя сумма «за босса» по боссам.
--
-- Тест: /epbaloot test — окно с предметами выбранного босса; выдача и
-- списание только имитируются (в EPGP и в игру ничего не пишется).
-- ============================================================

-- ======================
-- Настройки (правятся здесь)
-- ======================
local LOOT_MIN_QUALITY    = 4     -- показывать предметы не ниже этого качества (4 = эпик), плюс всё из таблиц боссов
local LOOT_TOP_BIDS       = 3     -- сколько верхних ставок показывать под предметом (1-3 — кнопки созданы по этому числу)
local GIVE_TIMEOUT        = 4     -- сек: сколько ждём очистки слота после GiveMasterLoot
local LATE_CLEAR_WINDOW   = 12    -- сек: слот очистился с опозданием после таймаута — всё равно считаем выдачей
local MASS_REPEAT_SECONDS = 1800  -- предупреждать о повторном начислении за того же босса в течение этого времени

-- Предметы, которые окно не показывает: [itemID] = true
auction.LOOT_IGNORED_ITEMS = {
    -- [12345] = true,
}

-- Сумма массового начисления по умолчанию: [имя босса] = число (необязательно;
-- после первого начисления окно запоминает последнюю введённую сумму по боссу).
auction.LOOT_BOSS_EP = {
    -- ["Имя босса"] = 100,
}

-- Размеры окна
local WIN_W, HEADER_H   = 520, 104
local ROW_W, ROW_H      = 474, 146
local ROW_GAP           = 6
local MAX_VISIBLE_ROWS  = 4

-- ======================
-- Состояние
-- ======================
auction.lootEntries      = {}
auction.lootBoss         = nil
auction.lootBossManual   = false
auction.lootTest         = false
auction.lootCandidates   = {}
auction.lootMassAwarded  = {}

-- ======================
-- Мелкие помощники
-- ======================
local function Say(msg, isError)
    DEFAULT_CHAT_FRAME:AddMessage((isError and "|cffff0000[EPBA]|r " or "|cff00ff00[EPBA]|r ")..msg)
end

local function ItemIDFromLink(link)
    if not link then return nil end
    return tonumber(string.match(link, "item:(%d+)"))
end

local function GetEPGP()
    return EPGP or EPGP_Auction or CEPGP or EPGPCore
end

local function Db()
    auction.db.lootmaster = auction.db.lootmaster or {}
    local d = auction.db.lootmaster
    d.bossEP = d.bossEP or {}
    return d
end

local function ReasonFor(e)
    return e.name or GetItemInfo(e.itemID) or ("item:"..tostring(e.itemID))
end

-- Кандидаты мастер-лута: имя → индекс. Перебираем все 40 индексов, пропуски допустимы.
local function BuildCandidates()
    local map = {}
    if not GetMasterLootCandidate then return map end
    for i = 1, 40 do
        local name = GetMasterLootCandidate(i)
        if name then map[name] = i end
    end
    return map
end

-- Проверка, что EPGP может выполнить операцию. method — "IncEPBy" или "IncMassEPBy".
-- Возвращает true, epgp  или  false, "текст ошибки".
local function EPGPCheck(method, reason, amount)
    local epgp = GetEPGP()
    if not epgp then return false, "EPGP-аддон не найден" end
    if not (epgp[method] and epgp.CanIncEPBy) then
        return false, "в EPGP нет метода "..method.." / CanIncEPBy"
    end
    local ok, can = pcall(epgp.CanIncEPBy, epgp, reason, amount)
    if not ok then return false, "ошибка EPGP: "..tostring(can) end
    if not can then
        return false, "EPGP не разрешает это изменение (нет прав на офицерские заметки или неверные данные)"
    end
    return true, epgp
end

-- ======================
-- Определение босса по предметам (лут боссов уникален)
-- ======================
local function GetBossByItem()
    if auction._bossByItem then return auction._bossByItem end
    local map = {}
    for bossName, items in pairs(auction.bosses or {}) do
        for _, id in ipairs(items) do
            if map[id] and map[id] ~= bossName then
                auction:Debug("Лут-окно: предмет "..id.." есть у двух боссов: "..map[id].." и "..bossName)
            else
                map[id] = bossName
            end
        end
    end
    auction._bossByItem = map
    return map
end

-- Босс, у которого совпало больше всего выпавших предметов. Ничья — выбранный
-- в главном окне босс, если он среди претендентов. Нет совпадений — nil.
local function DetectBoss(items)
    local byItem = GetBossByItem()
    local counts, best, bestCount = {}, nil, 0
    for _, it in ipairs(items) do
        local b = byItem[it.itemID]
        if b then counts[b] = (counts[b] or 0) + 1 end
    end
    for b, c in pairs(counts) do
        if c > bestCount then best, bestCount = b, c end
    end
    if best and auction.selectedBoss and counts[auction.selectedBoss] == bestCount then
        best = auction.selectedBoss
    end
    return best
end

-- ======================
-- Ставки
-- ======================
function auction:GetLootBids(e)
    local boss, id = e.boss, e.itemID
    if not boss then return {} end
    if not (self.sortedBids[boss] and self.sortedBids[boss][id]) then
        self:UpdateSortedBids(boss, id)
    end
    return self.sortedBids[boss][id] or {}
end

local function BidOf(bids, player)
    for _, b in ipairs(bids or {}) do
        if b.player == player then return b end
    end
    return nil
end

-- Сумма списания по умолчанию = ставка выбранного победителя; пользователь может
-- её поправить. Пока победитель не менялся, ручную правку не затираем.
local function SyncAmount(e)
    local who = (e.status == "open") and e.selected or e.winner
    if who ~= e.amountFor then
        e.amountFor = who
        local b = who and BidOf(auction:GetLootBids(e), who)
        e.amount = b and (tonumber(b.amount) or 0) or 0
    end
end

-- ======================
-- Журнал выдач (основа для статистики)
-- ======================
function auction:LootJournalAdd(e)
    if self.lootTest then return end
    local bids = self:GetLootBids(e)
    local b = BidOf(bids, e.winner)
    local rec = {
        t = time(), kind = "item", boss = e.boss, itemID = e.itemID, winner = e.winner,
        bid = b and (tonumber(b.amount) or 0) or 0,
        offspec = (b and b.isOffspec) and true or false,
        bids = #bids,
        charged = false,
    }
    -- id, ЛМ, обрезка журнала и обновление вкладки «Статистика» — в stats.lua
    e.log = self:StatsAddRecord(rec)
end

-- ======================
-- Сканирование окна добычи
-- ======================
local function ScanLoot()
    local items = {}
    local num = GetNumLootItems() or 0
    local threshold = GetLootThreshold and GetLootThreshold() or 2
    local byItem = GetBossByItem()
    for slot = 1, num do
        if LootSlotIsItem(slot) then
            local link = GetLootSlotLink(slot)
            local id = ItemIDFromLink(link)
            if id and not auction.LOOT_IGNORED_ITEMS[id] then
                local icon, name, quantity, quality = GetLootSlotInfo(slot)
                quality = quality or 0
                if quality >= threshold and (byItem[id] or quality >= LOOT_MIN_QUALITY) then
                    table.insert(items, {
                        slot = slot, itemID = id, link = link, name = name,
                        icon = icon, quantity = quantity, quality = quality,
                    })
                end
            end
        end
    end
    return items
end

local function AssignBosses(entries)
    local byItem = GetBossByItem()
    for _, e in ipairs(entries) do
        if e.status == "open" or e.status == "giving" then
            e.boss = byItem[e.itemID] or auction.lootBoss
        end
    end
end

-- Новое окно добычи: оставляем выданные-но-не-списанные записи, остальное
-- пересобираем из слотов.
function auction:LootOnOpened()
    if not self.fullyLoaded then return end
    if self.lootTest then
        self.lootTest = false
        wipe(self.lootEntries)
    end
    if not (self:IsLootMaster() and GetNumRaidMembers() > 0) then return end

    local scanned = ScanLoot()
    if #scanned == 0 then return end

    local keep = {}
    for _, e in ipairs(self.lootEntries) do
        if e.status == "given" then table.insert(keep, e) end
    end
    self.lootEntries = keep

    local detected = DetectBoss(scanned)
    if detected then
        self.lootBoss, self.lootBossManual = detected, false
    elseif not (self.lootBossManual and self.lootBoss) then
        self.lootBoss = self.selectedBoss
    end

    for _, it in ipairs(scanned) do
        it.status = "open"
        table.insert(self.lootEntries, it)
    end
    AssignBosses(self.lootEntries)

    self.lootCandidates = BuildCandidates()
    self:RefreshLootWindow()
    self.lootFrame:Show()
end

function auction:LootOnClosed()
    local keep, warn = {}, nil
    for _, e in ipairs(self.lootEntries) do
        if e.status == "given" or e.status == "charged" then
            table.insert(keep, e)
        elseif e.status == "giving" then
            warn = e
        end
    end
    if self.lootTest then return end
    self.lootEntries = keep
    if warn then
        Say("Окно добычи закрылось во время выдачи "..(warn.link or warn.name or "предмета")..": проверьте, получил ли его "..tostring(warn.pendingWinner)..".", true)
    end
    if self.lootFrame then
        if #keep == 0 then
            self.lootFrame:Hide()
        else
            self:RefreshLootWindow()
        end
    end
end

-- Слот очищен: либо наша выдача прошла, либо предмет забрали мимо аддона.
function auction:LootOnSlotCleared(slot)
    if self.lootTest then return end
    local changed, remove = false, {}
    for _, e in ipairs(self.lootEntries) do
        if e.slot == slot and (e.status == "giving" or e.status == "open") then
            local late = e.status == "open" and e.pendingWinner and e.giveTime
                and (GetTime() - e.giveTime) < LATE_CLEAR_WINDOW
            if e.status == "giving" or late then
                e.winner = e.pendingWinner
                e.status = "given"
                e.err = nil
                e.slot = nil
                SyncAmount(e)
                self:LootJournalAdd(e)
            else
                remove[e] = true  -- забрали вручную (через стандартное окно)
            end
            changed = true
        end
    end
    if next(remove) then
        local keep = {}
        for _, e in ipairs(self.lootEntries) do
            if not remove[e] then table.insert(keep, e) end
        end
        self.lootEntries = keep
    end
    if changed and self.lootFrame and self.lootFrame:IsShown() then
        self:RefreshLootWindow()
    end
end

-- ======================
-- Выдача
-- ======================
function auction:LootGive(e, player)
    if not (e and player) or e.status ~= "open" then return end

    e.selected = player
    e.userPick = true
    SyncAmount(e)

    if self.lootTest then
        e.winner, e.status = player, "given"
        self:RefreshLootWindow()
        return
    end

    if not self:IsLootMaster() then
        Say("Вы не Loot Master.", true)
        return
    end
    -- Слот мог измениться (кто-то забрал предмет, окно открыто заново).
    local link = e.slot and GetLootSlotLink(e.slot)
    if not link or ItemIDFromLink(link) ~= e.itemID then
        Say("Слот добычи изменился — список обновлён.", true)
        self:LootOnOpened()
        return
    end
    self.lootCandidates = BuildCandidates()
    local index = self.lootCandidates[player]
    if not index then
        e.err = player.." сейчас не может получить предмет (далеко, оффлайн или не в рейде)"
        self:RefreshLootWindow()
        return
    end

    e.err = nil
    e.pendingWinner = player
    e.giveTime = GetTime()
    e.status = "giving"
    GiveMasterLoot(e.slot, index)
    self:RefreshLootWindow()
end

-- ======================
-- Списание ЕП
-- ======================
function auction:LootConfirmCharge(e)
    if not e or e.status ~= "given" then return end
    local amount = math.floor(tonumber(e.amount) or 0)
    if amount <= 0 then
        Say("Укажите положительную сумму списания.", true)
        return
    end
    if not self.lootTest then
        local ok, why = EPGPCheck("IncEPBy", ReasonFor(e), -amount)
        if not ok then Say("Списать нельзя: "..why, true) return end
    end
    local text = string.format("Списать %s ЕП у %s за %s?", self:FormatNumber(amount), tostring(e.winner), ReasonFor(e))
    local main = self.GetMainName and self:GetMainName(e.winner)
    if main then text = text.."\nЕП будет списан с мейна: "..main end
    local ep = self:GetPlayerEP(e.winner, true)
    if ep and ep < amount then
        text = text.."\n|cffff5555Внимание: у игрока "..self:FormatNumber(ep).." ЕП — меньше суммы списания.|r"
    end
    StaticPopup_Show("EPBA_LOOT_CHARGE", text, nil, e)
end

function auction:LootDoCharge(e)
    if not e or e.status ~= "given" then return end
    local amount = math.floor(tonumber(e.amount) or 0)
    if amount <= 0 then return end

    if self.lootTest then
        Say("[ТЕСТ] списано "..self:FormatNumber(amount).." ЕП у "..tostring(e.winner))
        e.status, e.chargedAmount, e.chargedMain = "charged", amount, e.winner
        self:RefreshLootWindow()
        return
    end

    local ok, epgp = EPGPCheck("IncEPBy", ReasonFor(e), -amount)
    if not ok then Say("Списать нельзя: "..epgp, true) return end
    local success, result = pcall(epgp.IncEPBy, epgp, e.winner, ReasonFor(e), -amount)
    -- По описанию EPGP IncEPBy возвращает имя мейна; nil — игрок неизвестен EPGP.
    if not success or type(result) ~= "string" then
        Say("EPGP не выполнил списание для "..tostring(e.winner)..(success and "" or (": "..tostring(result)))..".", true)
        return
    end

    e.status, e.chargedAmount, e.chargedMain = "charged", amount, result
    if e.log then
        e.log.charged, e.log.chargedAmount, e.log.main = true, amount, result
        self:StatsChanged()
    end
    Say(string.format("Списано %s ЕП с %s за %s.", self:FormatNumber(amount), result, ReasonFor(e)))
    -- Ставка победителя больше не актуальна — убираем её у всех (ApplyBidChange рассылает SYNC).
    self:ApplyBidChange(e.boss, e.itemID, e.winner, 0, false)
    self:ScheduleTimer(function() auction:CheckAndUpdateEP() end, 2)
    self:RefreshLootWindow()
end

-- ======================
-- Массовое начисление ЕП
-- ======================
function auction:LootConfirmMass()
    local f = self.lootFrame
    local boss = self.lootBoss
    local amount = math.floor(tonumber(f.massBox:GetText()) or 0)
    if not boss then Say("Босс не определён — выберите его в списке.", true) return end
    if amount <= 0 then Say("Укажите положительную сумму ЕП за босса.", true) return end

    local n
    if not self.lootTest then
        local ok, why = EPGPCheck("IncMassEPBy", boss, amount)
        if not ok then Say("Начислить нельзя: "..why, true) return end
        if why.GetNumMembersInAwardList then
            local okN, count = pcall(why.GetNumMembersInAwardList, why)
            if okN then n = count end
        end
    end
    local text = string.format("Начислить %s ЕП рейду?\nПричина: %s", self:FormatNumber(amount), boss)
    if n then text = text.."\nПолучателей: "..tostring(n) end
    local last = self.lootMassAwarded[boss]
    if last and time() - last < MASS_REPEAT_SECONDS then
        text = text..string.format("\n|cffff5555За этого босса уже начисляли %d мин. назад!|r", math.floor((time() - last) / 60))
    end
    StaticPopup_Show("EPBA_LOOT_MASS", text, nil, { boss = boss, amount = amount, n = n })
end

function auction:LootDoMass(data)
    if not data then return end
    if self.lootTest then
        Say("[ТЕСТ] рейду начислено "..self:FormatNumber(data.amount).." ЕП за: "..data.boss)
        return
    end
    local ok, epgp = EPGPCheck("IncMassEPBy", data.boss, data.amount)
    if not ok then Say("Начислить нельзя: "..epgp, true) return end
    local success, err = pcall(epgp.IncMassEPBy, epgp, data.boss, data.amount)
    if not success then
        Say("Ошибка EPGP при начислении: "..tostring(err), true)
        return
    end
    self.lootMassAwarded[data.boss] = time()
    self:LootJournalAddMass(data.boss, data.amount, data.n)   -- для статистики (stats.lua)
    Db().bossEP[data.boss] = data.amount
    Say(string.format("Рейду начислено %s ЕП за: %s.", self:FormatNumber(data.amount), data.boss))
    self:ScheduleTimer(function() auction:CheckAndUpdateEP() end, 2)
end

StaticPopupDialogs["EPBA_LOOT_CHARGE"] = {
    text = "%s",
    button1 = "Списать",
    button2 = "Отмена",
    OnAccept = function(self, data) auction:LootDoCharge(data) end,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
}

StaticPopupDialogs["EPBA_LOOT_MASS"] = {
    text = "%s",
    button1 = "Начислить",
    button2 = "Отмена",
    OnAccept = function(self, data) auction:LootDoMass(data) end,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
}

-- Снимок посещаемости на выбранном боссе (кнопка «Создать снимок»). Записью и
-- сообщениями о результате (нет доступа, не в рейде, дубль за 5 минут) занимается
-- RecordAttendanceManual из attendance.lua. В тестовом режиме ничего не пишет.
function auction:LootSnapshot()
    local boss = self.lootBoss
    if not boss then return end
    if self.lootTest then
        self:AttendanceSay("Тест: снимок посещаемости не записывается")
        return
    end
    self:RecordAttendanceManual(boss)
end

-- ======================
-- Выбор босса
-- ======================
function auction:LootSetBoss(name)
    self.lootBoss, self.lootBossManual = name, true
    local byItem = GetBossByItem()
    for _, e in ipairs(self.lootEntries) do
        if (e.status == "open" or e.status == "giving") and not byItem[e.itemID] then
            e.boss = name
        end
    end
    self:RefreshLootWindow()
end

local function BossChoices()
    local inst = auction.lootBoss and auction.bossToInstance[auction.lootBoss]
        or auction.selectedBoss and auction.bossToInstance[auction.selectedBoss]
    local list = inst and auction.instances[inst]
    return list or auction.bossOrder
end

-- ======================
-- UI
-- ======================
local function MakeEdit(parent, w, h)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(w, h)
    box:SetAutoFocus(false)
    box:SetFontObject(GameFontHighlight)
    box:SetTextInsets(6, 6, 0, 0)
    box:SetMaxLetters(7)
    box:SetNumeric(true)
    box:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    auction:SkinInput(box)
    return box
end

local function MakeButton(parent, w, h, text)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h)
    b:SetText(text)
    auction:SkinButton(b)
    return b
end

local function SetBtn(btn, enabled)
    if enabled then btn:Enable() else btn:Disable() end
end

local function CreateRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(ROW_W, ROW_H)
    auction:SkinPanel(row)
    row:SetBackdropColor(0.13, 0.13, 0.13, 0.95)

    local iconBtn = CreateFrame("Button", nil, row)
    iconBtn:SetSize(32, 32)
    iconBtn:SetPoint("TOPLEFT", 8, -8)
    iconBtn.tex = iconBtn:CreateTexture(nil, "ARTWORK")
    iconBtn.tex:SetAllPoints()
    iconBtn.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconBtn:SetScript("OnEnter", function(self)
        local e = row.entry
        if e and e.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(e.link)
            GameTooltip:Show()
        end
    end)
    iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.iconBtn = iconBtn

    row.itemText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.itemText:SetPoint("TOPLEFT", iconBtn, "TOPRIGHT", 8, 0)
    row.itemText:SetPoint("RIGHT", -8, 0)
    row.itemText:SetJustifyH("LEFT")

    row.infoText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.infoText:SetPoint("TOPLEFT", row.itemText, "BOTTOMLEFT", 0, -4)
    row.infoText:SetPoint("RIGHT", -8, 0)
    row.infoText:SetJustifyH("LEFT")

    row.bidButtons = {}
    for k = 1, LOOT_TOP_BIDS do
        local btn = CreateFrame("Button", nil, row)
        btn:SetSize(300, 20)
        btn:SetPoint("TOPLEFT", 48, -46 - (k - 1) * 20)
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        btn:SetBackdropColor(0, 0, 0, 0.25)
        btn:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
        btn:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.12)
        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.label:SetPoint("LEFT", 6, 0)
        btn.label:SetPoint("RIGHT", -4, 0)
        btn.label:SetJustifyH("LEFT")
        btn:SetScript("OnClick", function(self)
            local e = row.entry
            if e and e.status == "open" and self.player then
                e.selected, e.userPick = self.player, true
                auction:RefreshLootWindow()
            end
        end)
        row.bidButtons[k] = btn
    end

    row.moreText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.moreText:SetPoint("TOPLEFT", 52, -46 - LOOT_TOP_BIDS * 20 + 2)

    local amountLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    amountLabel:SetPoint("TOPLEFT", 358, -48)
    amountLabel:SetText("Списать ЕП:")
    row.amountBox = MakeEdit(row, 100, 22)
    row.amountBox:SetPoint("TOPLEFT", 360, -62)
    row.amountBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput and row.entry then
            row.entry.amount = tonumber(self:GetText()) or 0
            row.chargeBtn:SetText(row.entry.status == "given" and ("Списать "..auction:FormatNumber(row.entry.amount).." ЕП") or "Списать ЕП")
            SetBtn(row.chargeBtn, row.entry.status == "given" and row.entry.amount > 0)
        end
    end)

    row.epText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.epText:SetPoint("TOPLEFT", 360, -90)
    row.epText:SetWidth(106)
    row.epText:SetJustifyH("LEFT")

    row.giveBtn = MakeButton(row, 130, 22, "Выдать")
    row.giveBtn:SetPoint("BOTTOMLEFT", 8, 8)
    row.giveBtn:SetScript("OnClick", function()
        local e = row.entry
        if e then auction:LootGive(e, e.selected) end
    end)

    row.selfBtn = MakeButton(row, 130, 22, "Выдать себе")
    row.selfBtn:SetPoint("LEFT", row.giveBtn, "RIGHT", 8, 0)
    row.selfBtn:SetScript("OnClick", function()
        local e = row.entry
        if e then auction:LootGive(e, UnitName("player")) end
    end)

    row.chargeBtn = MakeButton(row, 178, 22, "Списать ЕП")
    row.chargeBtn:SetPoint("LEFT", row.selfBtn, "RIGHT", 8, 0)
    row.chargeBtn:SetScript("OnClick", function()
        local e = row.entry
        if e then auction:LootConfirmCharge(e) end
    end)

    return row
end

function auction:CreateLootWindow()
    if self.lootFrame then return self.lootFrame end
    local c = self.theme.colors

    local f = CreateFrame("Frame", "EPBossAuctionLootFrame", UIParent)
    f:SetSize(WIN_W, 300)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    local pos = Db().pos
    f:ClearAllPoints()
    if pos and pos.left and pos.top then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.left, pos.top)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 260, 0)
    end
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local left, top = s:GetLeft(), s:GetTop()
        if left and top then Db().pos = { left = left, top = top } end
    end)
    self:SkinPanel(f)
    f:Hide()
    -- В UISpecialFrames намеренно НЕ добавляем: Esc не должен закрывать окно
    -- посреди выдачи/списания.

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -12)
    title:SetText("EPBA: добыча")
    title:SetTextColor(c.accent[1], c.accent[2], c.accent[3])
    f.title = title

    f.testLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.testLabel:SetPoint("LEFT", title, "RIGHT", 10, 0)
    f.testLabel:SetText("|cffff5555ТЕСТ — в игру и EPGP ничего не пишется|r")

    local close = MakeButton(f, 22, 22, "x")
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() auction:LootHideWindow() end)

    local bossLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bossLabel:SetPoint("TOPLEFT", 16, -42)
    bossLabel:SetText("Босс:")

    local dd = CreateFrame("Frame", "EPBALootBossDropdown", f, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", 52, -34)
    UIDropDownMenu_SetWidth(dd, 230)
    UIDropDownMenu_Initialize(dd, function(selfDD, level)
        for _, name in ipairs(BossChoices()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.checked = (name == auction.lootBoss)
            info.func = function() auction:LootSetBoss(name) end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    self:SkinDropdown(dd)
    f.bossDropdown = dd

    -- «Создать снимок»: записывает посещаемость на выбранном боссе (состав рейда
    -- сейчас) в историю Attendance — то же, что «Записать килл» на вкладке Attendance.
    f.snapBtn = MakeButton(f, 164, 24, "Создать снимок")
    f.snapBtn:SetPoint("TOPLEFT", 338, -36)
    f.snapBtn:SetScript("OnClick", function() auction:LootSnapshot() end)
    f.snapBtn:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Записать посещаемость на боссе", 1, 1, 1)
        GameTooltip:AddLine("Сохраняет текущий состав рейда как килл выбранного босса (вкладка Attendance).", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    f.snapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local massLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    massLabel:SetPoint("TOPLEFT", 16, -76)
    massLabel:SetText("ЕП рейду за босса:")
    f.massBox = MakeEdit(f, 90, 22)
    f.massBox:SetPoint("LEFT", massLabel, "RIGHT", 10, 0)
    f.massBtn = MakeButton(f, 150, 24, "Начислить рейду")
    f.massBtn:SetPoint("LEFT", f.massBox, "RIGHT", 10, 0)
    f.massBtn:SetScript("OnClick", function() auction:LootConfirmMass() end)

    local scroll = CreateFrame("ScrollFrame", "EPBossAuctionLootScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -HEADER_H)
    scroll:SetPoint("BOTTOMRIGHT", -30, 12)
    local scrollBar = _G["EPBossAuctionLootScrollScrollBar"]
    if scrollBar then self:SkinScrollBar(scrollBar) end
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(ROW_W, 1)
    scroll:SetScrollChild(content)
    f.scroll, f.content, f.rows = scroll, content, {}

    -- Таймаут выдачи: слот не очистился — возвращаем строку в «не выдан».
    f:SetScript("OnUpdate", function(s, elapsed)
        s.acc = (s.acc or 0) + elapsed
        if s.acc < 0.25 then return end
        s.acc = 0
        local now, changed = GetTime(), false
        for _, e in ipairs(auction.lootEntries) do
            if e.status == "giving" and now - (e.giveTime or now) > GIVE_TIMEOUT then
                e.status = "open"
                e.err = "Выдача не подтверждена: у игрока нет места в сумке или он далеко"
                changed = true
            end
        end
        if changed then auction:RefreshLootWindow() end
    end)

    self.lootFrame = f
    return f
end

local function FillRow(row, e, ctx)
    row.entry = e
    local status = e.status
    local isOpen = status == "open"

    row.iconBtn.tex:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.itemText:SetText((e.link or e.name or ("Предмет #"..e.itemID))
        .. ((e.quantity and e.quantity > 1) and (" x"..e.quantity) or ""))

    -- Строка состояния
    local info
    if status == "giving" then
        info = "|cffffff00Выдача: "..tostring(e.pendingWinner).."...|r"
    elseif status == "given" then
        info = "|cff00ff00Выдан: "..tostring(e.winner).."|r  (ЕП ещё не списан)"
    elseif status == "charged" then
        info = "|cff00ff00Выдан: "..tostring(e.winner).."; списано "..auction:FormatNumber(e.chargedAmount or 0)
            .." ЕП с "..tostring(e.chargedMain).."|r"
    elseif e.reserved then
        info = "|cffffd200Резерв — предмет продан, ставки закрыты|r"
    else
        info = "|cff999999"..tostring(e.boss or "босс не определён").."|r"
    end
    if e.err and isOpen then info = info.."  |cffff5555"..e.err.."|r" end
    row.infoText:SetText(info)

    -- Ставки
    local shownWinner = isOpen and e.selected or (e.winner or e.pendingWinner)
    local bids = e._bids or {}
    for k = 1, LOOT_TOP_BIDS do
        local btn = row.bidButtons[k]
        local b = (not e.reserved) and bids[k] or nil
        if b then
            btn.player = b.player
            btn:Show()
            btn:EnableMouse(isOpen)
            local ep = auction:GetPlayerEP(b.player, false)
            local text = string.format("%d. %s|r — %s ЕП%s  |  ЕП: %s", k, auction:FormatColoredName(b.player),
                auction:FormatNumber(tonumber(b.amount) or 0), b.isOffspec and " (офф)" or "", auction:FormatNumber(ep))
            if isOpen and not ctx.test and not ctx.cands[b.player] then
                text = text.."  |cffff5555(вне лута)|r"
            end
            btn.label:SetText(text)
            if ep < (tonumber(b.amount) or 0) then
                btn.label:SetTextColor(1, 0.55, 0.55)
            else
                btn.label:SetTextColor(1, 1, 1)
            end
            if b.player == shownWinner then
                btn:SetBackdropColor(ctx.accent[1], ctx.accent[2], ctx.accent[3], 0.35)
            else
                btn:SetBackdropColor(0, 0, 0, 0.25)
            end
        else
            btn.player = nil
            btn:Hide()
        end
    end
    if e.reserved then
        row.moreText:SetText("")
    elseif #bids == 0 then
        row.moreText:SetText("Ставок нет")
    elseif #bids > LOOT_TOP_BIDS then
        row.moreText:SetText(string.format("+ ещё ставок: %d", #bids - LOOT_TOP_BIDS))
    else
        row.moreText:SetText("")
    end

    -- Сумма и ЕП игрока
    local box = row.amountBox
    local editable = (status == "open" or status == "given")
    if not box:HasFocus() then
        box:SetText(tostring(math.floor(tonumber(e.amount) or 0)))
    end
    box:EnableMouse(editable)
    box:SetAlpha(editable and 1 or 0.5)
    if not editable then box:ClearFocus() end

    local who = shownWinner
    if who then
        local main = auction.GetMainName and auction:GetMainName(who)
        row.epText:SetText("ЕП: "..auction:FormatNumber(auction:GetPlayerEP(who, false))
            ..(main and ("\n|cff999999мейн: "..main.."|r") or ""))
    else
        row.epText:SetText("")
    end

    -- Кнопки
    local canGive = isOpen and not e.reserved and e.selected and (ctx.test or ctx.cands[e.selected]) and true or false
    local canSelf = isOpen and (ctx.test or ctx.cands[ctx.me]) and true or false
    row.giveBtn:SetText(status == "giving" and "Выдача..." or "Выдать")
    SetBtn(row.giveBtn, canGive)
    SetBtn(row.selfBtn, canSelf)
    local amount = math.floor(tonumber(e.amount) or 0)
    if status == "given" then
        row.chargeBtn:SetText("Списать "..auction:FormatNumber(amount).." ЕП")
    elseif status == "charged" then
        row.chargeBtn:SetText("Списано")
    else
        row.chargeBtn:SetText("Списать ЕП")
    end
    SetBtn(row.chargeBtn, status == "given" and amount > 0)
end

function auction:RefreshLootWindow()
    local f = self:CreateLootWindow()
    local entries = self.lootEntries
    local me = UnitName("player")
    local test = self.lootTest
    local cands = test and {} or (self.lootCandidates or {})

    -- Модель: ставки, резерв, выбранный победитель (без дублирования между копиями)
    local taken = {}
    for _, e in ipairs(entries) do
        e._bids = self:GetLootBids(e)
        e.reserved = (e.boss and self.IsReserved and self:IsReserved(e.boss, e.itemID)) and true or false
        taken[e.itemID] = taken[e.itemID] or {}
        local t = taken[e.itemID]
        if e.status == "open" then
            if e.reserved then
                e.selected = nil
            else
                local sel = e.selected
                local valid = sel and BidOf(e._bids, sel) and true or false
                if not valid or (t[sel] and not e.userPick) then
                    sel = nil
                    for _, b in ipairs(e._bids) do
                        if not t[b.player] then sel = b.player break end
                    end
                    e.selected, e.userPick = sel, false
                end
                if sel then t[sel] = true end
            end
            SyncAmount(e)
        else
            local w = e.winner or e.pendingWinner
            if w then t[w] = true end
            if e.status == "given" then SyncAmount(e) end
        end
    end

    -- Шапка
    f.testLabel:SetShown(test)
    UIDropDownMenu_SetText(f.bossDropdown, self.lootBoss or "— выберите босса —")
    if f.massFilledFor ~= self.lootBoss then
        f.massFilledFor = self.lootBoss
        local v = self.lootBoss and (Db().bossEP[self.lootBoss] or self.LOOT_BOSS_EP[self.lootBoss])
        f.massBox:SetText(v and tostring(v) or "")
    end
    SetBtn(f.massBtn, self.lootBoss ~= nil)
    SetBtn(f.snapBtn, self.lootBoss ~= nil)

    -- Строки (пул: создаются один раз, дальше переиспользуются)
    local ctx = { test = test, cands = cands, me = me, accent = self.theme.colors.accent }
    for i, e in ipairs(entries) do
        local row = f.rows[i]
        if not row then
            row = CreateRow(f.content)
            f.rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -(i - 1) * (ROW_H + ROW_GAP))
        FillRow(row, e, ctx)
        row:Show()
    end
    for i = #entries + 1, #f.rows do
        f.rows[i].entry = nil
        f.rows[i]:Hide()
    end

    local n = #entries
    f.content:SetHeight(math.max(1, n * (ROW_H + ROW_GAP)))
    f:SetHeight(HEADER_H + math.min(math.max(n, 1), MAX_VISIBLE_ROWS) * (ROW_H + ROW_GAP) + 14)
end

function auction:LootHideWindow()
    if not self.lootFrame then return end
    -- Закрыли окно — списанные записи больше не нужны; выданные, но не списанные, остаются.
    local keep = {}
    for _, e in ipairs(self.lootEntries) do
        if e.status ~= "charged" then table.insert(keep, e) end
    end
    self.lootEntries = keep
    self.lootFrame:Hide()
end

-- ======================
-- События
-- ======================
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("LOOT_OPENED")
ev:RegisterEvent("LOOT_CLOSED")
ev:RegisterEvent("LOOT_SLOT_CLEARED")
ev:RegisterEvent("UPDATE_MASTER_LOOT_LIST")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "EPBossAuction" and type(EPBossAuctionSavedLootLog) ~= "table" then
            EPBossAuctionSavedLootLog = {}
        end
    elseif event == "LOOT_OPENED" then
        auction:LootOnOpened()
    elseif event == "LOOT_CLOSED" then
        auction:LootOnClosed()
    elseif event == "LOOT_SLOT_CLEARED" then
        auction:LootOnSlotCleared(arg1)
    elseif event == "UPDATE_MASTER_LOOT_LIST" then
        if auction.lootFrame and auction.lootFrame:IsShown() and not auction.lootTest then
            auction.lootCandidates = BuildCandidates()
            auction:RefreshLootWindow()
        end
    end
end)

-- ======================
-- Тестовый режим и команда
-- ======================
function auction:ShowLootTestWindow()
    local boss = self.selectedBoss or (self.bossOrder and self.bossOrder[1])
    local list = boss and self.bosses[boss]
    if not list or #list == 0 then
        Say("Для теста выберите в главном окне босса с предметами.", true)
        return
    end
    wipe(self.lootEntries)
    self.lootTest = true
    self.lootBoss, self.lootBossManual = boss, false
    for i = 1, math.min(#list, 4) do
        local id = list[i]
        local name, link, quality, _, _, _, _, _, _, icon = GetItemInfo(id)
        table.insert(self.lootEntries, {
            itemID = id, name = name or ("Предмет #"..id), link = link, icon = icon,
            quantity = 1, quality = quality, status = "open", boss = boss,
        })
    end
    self:RefreshLootWindow()
    self.lootFrame:Show()
    Say("Тестовое окно: выдача и списание имитируются, EPGP не трогается.")
end

SLASH_EPBA_LOOT1 = "/epbaloot"
SlashCmdList["EPBA_LOOT"] = function(msg)
    msg = string.lower(msg or "")
    if msg == "test" then
        auction:ShowLootTestWindow()
    elseif msg == "hide" then
        auction:LootHideWindow()
    elseif #auction.lootEntries > 0 then
        auction:RefreshLootWindow()
        auction.lootFrame:Show()
    else
        Say("Нет добычи для выдачи. Команды: /epbaloot test, /epbaloot hide")
    end
end
