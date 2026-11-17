local auction = EPBossAuction

-- ============================================================
-- reserve.lua — резерв предметов: данные, правила, сеть
-- ============================================================
-- Зачем: иногда рейд водят под продажу предметов за золото. Что нужно
-- покупателям (не из гильдии), оговорено заранее. Такие предметы
-- помечаются как «резерв» — на них нельзя делать ставки.
--
-- Файлы Резерва:
--   reserve.lua    — ЭТОТ файл: данные, проверка, рассылка в рейд, синхронизация офицеров;
--   reserve_ui.lua — вкладка «Резерв» (список, кнопки).
--
-- Кто редактирует: только тот, кто может РЕДАКТИРОВАТЬ офицерскую заметку
-- (то же правило, что у Attendance — HasReserveAccess ниже просто зовёт
-- HasAttendanceAccess, правило доступа живёт в одном месте).
--
-- Структура данных (у тех, у кого есть доступ):
--   auction.reserves[boss][itemID] = { qty = N, note = "покупатель", t = <unix-время правки>, by = "кто правил" }
--   qty = 0 — «надгробие» (запись снята): нужно, чтобы снятие дошло до других
--   офицеров при синхронизации; через RESERVE_TOMBSTONE_DAYS дней стирается.
--   qty > 0 — предмет закрыт для ставок целиком (qty — сколько копий продано,
--   кнопка «−» на вкладке уменьшает его, когда предмет выдан покупателю).
-- У остальных игроков: auction.reservePublic[boss][itemID] = qty — публичная
-- копия без заметок, её рассылает ЛМ.
--
-- Два уровня защиты:
--   1) ЛМ-клиент не принимает BID на зарезервированный предмет (Handle_BID в
--      comm.lua → IsReserved → ответ RESERVED). Это жёсткая защита: её не
--      обойти старой версией аддона или правкой клиента у игрока.
--   2) Остальные клиенты видят резерв в таблице: строка затемнена, выбрать
--      предмет нельзя, ставка не отправляется (UX, не безопасность).
--
-- Сеть (диспетчер HandleMessage в comm.lua находит Handle_<КОМАНДА> сам):
--   RES_UPD;boss;itemID;qty;t;note        GUILD    офицер → офицеры: правка одной записи (live)
--   RES_REQ;sid;i;n;<дайджест>            GUILD    офицер → офицеры: «вот что у меня есть» (pull)
--   RES_REC;sid;rid;i;n;<запись>          WHISPER  ответ: недостающая/более свежая запись
--   RES_DONE;sid;N                        WHISPER  «закончил, прислал N записей»
--   RES;gen;boss;itemID;qty               RAID     ЛМ → рейд: запись публичного списка
--   RES_END;gen;N                         RAID     ЛМ → рейд: «список gen закончен, в нём N записей»
--   RES_ONE;boss;itemID;qty               RAID     ЛМ → рейд: одиночное изменение (qty=0 — снято)
--   RESERVED;boss;itemID                  WHISPER  ЛМ → игрок: «ставка отклонена, предмет в резерве»
-- Список RES…RES_END клиент применяет целиком только после RES_END (не
-- остаётся «половинчатого» списка при потере сообщений).
--
-- Требование: публичный список в рейд рассылает ЛМ, а он берёт его из своей
-- вкладки, поэтому ЛМ должен иметь доступ к «Резерву». Если не имеет —
-- OnBecameLootMaster один раз за сессию предупреждает в чат.
--
-- Известные ограничения (сознательно простые, как у Attendance):
--   • GUILD-сообщения RES_UPD/RES_REQ видит любой гильдеец с аддоном; заметка о
--     покупателе в них передаётся открыто (≤ 30 символов). Хотите скрыть — не
--     пишите заметки;
--   • отправителя RES_UPD клиент проверить не может, но автор записи (by) берётся
--     из имени отправителя сообщения и виден на вкладке;
--   • аддон не знает, сколько копий предмета выпало, поэтому qty > 0 закрывает
--     предмет для ставок целиком, пока офицер не уменьшит qty.
-- ============================================================

auction.RESERVE_MAX_ENTRIES = 250       -- записей всего (вместе с надгробиями)
auction.RESERVE_MAX_QTY = 99
auction.RESERVE_NOTE_LEN = 30           -- символов в заметке о покупателе
auction.RESERVE_TOMBSTONE_DAYS = 30     -- сколько хранить снятые записи для синхронизации

local CHUNK_BYTES = 170                 -- размер куска данных в одном сообщении
local MAX_RECORDS_PER_RESPONSE = 150
local RESPOND_COOLDOWN = 20             -- не отвечать одному запросившему чаще, сек
local SYNC_MAX_SECONDS = 120
local REQUEST_WAIT = 6
local BROADCAST_DELAY = 3               -- «склеиваем» несколько запросов в одну рассылку, сек

auction.reserves = auction.reserves or {}
auction.reservePublic = auction.reservePublic or {}
auction.reservePending = auction.reservePending or {}
auction.reserveRevision = 0

-- ======================
-- Вспомогательное
-- ======================

-- Заметка: без служебных символов формата и управляющих, не длиннее RESERVE_NOTE_LEN символов.
local function CleanNote(s)
    s = tostring(s or "")
    s = s:gsub("[%^~,;|%c]", "")
    s = strtrim(s)
    return auction.Utf8Prefix(s, auction.RESERVE_NOTE_LEN)
end
auction.CleanReserveNote = CleanNote

-- Имя автора годится для передачи, если в нём нет служебных символов.
local function SafeBy(s)
    if type(s) == "string" and #s > 0 and #s <= 32 and not s:find("[%^~,;|]") then return s end
    return nil
end

-- Короткий хэш имени босса для дайджеста (сумма по байтам, 16 бит).
local function BossHash(boss)
    local h = 0
    for i = 1, #boss do h = (h * 31 + boss:byte(i)) % 65536 end
    return h
end

-- Канал рассылки в группу: RAID, PARTY или nil, если мы не в группе.
local function GroupChannel()
    if GetNumRaidMembers() > 0 then return "RAID" end
    if GetNumPartyMembers() > 0 then return "PARTY" end
    return nil
end

-- Сколько всего записей (с надгробиями) в локальном списке.
function auction:CountReserveEntries()
    local n = 0
    for _, items in pairs(self.reserves) do
        for _ in pairs(items) do n = n + 1 end
    end
    return n
end

-- Число активных резервов: позиций и копий (для счётчика на вкладке).
function auction:CountActiveReserves()
    local positions, copies = 0, 0
    for _, items in pairs(self.reserves) do
        for _, e in pairs(items) do
            if e.qty > 0 then positions = positions + 1; copies = copies + e.qty end
        end
    end
    return positions, copies
end

-- Есть ли предмет в списке предметов босса (auction.bosses).
function auction:BossHasItem(boss, itemID)
    local list = self.bosses[boss]
    if not list or not itemID then return false end
    for _, id in ipairs(list) do
        if id == itemID then return true end
    end
    return false
end

-- Боссы, у которых есть этот предмет, в порядке подземелий/боссов аддона.
function auction:GetBossesForItem(itemID)
    local result, seen = {}, {}
    for _, instanceName in ipairs(self.instanceOrder or {}) do
        for _, boss in ipairs(self.instances[instanceName] or {}) do
            if not seen[boss] and self:BossHasItem(boss, itemID) then
                seen[boss] = true
                result[#result + 1] = boss
            end
        end
    end
    return result
end

-- ======================
-- Доступ и чтение
-- ======================

-- Единое правило доступа — то же, что у Attendance (см. CanRecordAttendance).
function auction:HasReserveAccess()
    return self:HasAttendanceAccess()
end

function auction:GetReserveEntry(boss, itemID)
    local items = self.reserves[boss]
    return items and items[itemID] or nil
end

-- Сколько копий предмета в резерве. Тот, у кого есть доступ (в том числе ЛМ),
-- смотрит в свой список; остальные — в публичную копию от ЛМ.
function auction:GetReserveQty(boss, itemID)
    if not boss or not itemID then return 0 end
    if self:HasReserveAccess() then
        local e = self:GetReserveEntry(boss, itemID)
        return (e and e.qty) or 0
    end
    local items = self.reservePublic[boss]
    return (items and items[itemID]) or 0
end

function auction:IsReserved(boss, itemID)
    return self:GetReserveQty(boss, itemID) > 0
end

-- ======================
-- Загрузка
-- ======================

-- Читает EPBossAuctionSavedReserves, отбрасывая неизвестных боссов/предметы и
-- старые надгробия. Вызывается из events.lua при ADDON_LOADED.
function auction:LoadReserves()
    self.reserves = {}
    local saved = EPBossAuctionSavedReserves
    if type(saved) ~= "table" then return end
    local cutoff = time() - self.RESERVE_TOMBSTONE_DAYS * 86400
    for boss, items in pairs(saved) do
        if self.bosses[boss] and type(items) == "table" then
            for itemID, e in pairs(items) do
                itemID = tonumber(itemID)
                if itemID and type(e) == "table" and self:BossHasItem(boss, itemID) then
                    local qty = math.floor(tonumber(e.qty) or 0)
                    local t = tonumber(e.t) or 0
                    if qty > 0 or t >= cutoff then
                        self.reserves[boss] = self.reserves[boss] or {}
                        self.reserves[boss][itemID] = {
                            qty = math.max(0, math.min(self.RESERVE_MAX_QTY, qty)),
                            note = CleanNote(e.note),
                            t = t,
                            by = SafeBy(e.by) or "",
                        }
                    end
                end
            end
        end
    end
end

-- ======================
-- Правка (только с доступом)
-- ======================

-- Ставит количество (и, если передана, заметку) для предмета. qty = 0 — снять.
-- Возвращает true, если запись принята.
function auction:SetReserve(boss, itemID, qty, note)
    if not self:HasReserveAccess() then return false end
    if not self.bosses[boss] or not self:BossHasItem(boss, itemID) then return false end
    qty = math.max(0, math.min(self.RESERVE_MAX_QTY, math.floor(tonumber(qty) or 0)))

    self.reserves[boss] = self.reserves[boss] or {}
    local old = self.reserves[boss][itemID]
    if not old and qty == 0 then return true end
    if not old and self:CountReserveEntries() >= self.RESERVE_MAX_ENTRIES then
        self:AttendanceSay("Резерв: достигнут предел записей ("..self.RESERVE_MAX_ENTRIES.."). Снимите ненужные.", true)
        return false
    end

    local t = time()
    if old and old.t >= t then t = old.t + 1 end   -- правка всегда «новее» предыдущей
    local newNote
    if qty == 0 then
        newNote = ""
    elseif note ~= nil then
        newNote = CleanNote(note)
    else
        newNote = old and old.note or ""
    end
    self.reserves[boss][itemID] = { qty = qty, note = newNote, t = t, by = UnitName("player") }
    self:ReserveChanged(boss, itemID, true)
    return true
end

-- Снять все резервы (с подтверждением на вкладке).
function auction:ClearAllReserves()
    for boss, items in pairs(self.reserves) do
        for itemID, e in pairs(items) do
            if e.qty > 0 then self:SetReserve(boss, itemID, 0) end
        end
    end
end

-- Разбирает текст со ссылками на предметы (или голыми id) и резервирует их.
-- Предмет есть у нескольких боссов: берём выбранного на вкладке, а если у него
-- предмета нет — всех, у кого он есть (в чат пишется, где именно).
-- Повторная вставка того же предмета добавляет копию. Возвращает число добавленных.
function auction:AddReservesFromText(text, preferredBoss)
    text = tostring(text or "")
    local ids = {}
    for id in text:gmatch("|Hitem:(%d+)") do ids[#ids + 1] = tonumber(id) end
    if #ids == 0 then
        for id in text:gmatch("(%d%d%d+)") do ids[#ids + 1] = tonumber(id) end
    end
    local added, unknown = 0, 0
    for _, itemID in ipairs(ids) do
        local bosses = self:GetBossesForItem(itemID)
        if #bosses == 0 then
            unknown = unknown + 1
        else
            local targets = bosses
            for _, b in ipairs(bosses) do
                if b == preferredBoss then targets = { b } break end
            end
            for _, boss in ipairs(targets) do
                local old = self:GetReserveEntry(boss, itemID)
                local qty = ((old and old.qty) or 0) + 1
                if self:SetReserve(boss, itemID, qty) then
                    added = added + 1
                    self:AttendanceSay("Резерв: «"..tostring(self:GetCachedItemName(itemID, boss)).."» — "..boss.." (копий: "..qty..")")
                end
            end
        end
    end
    if unknown > 0 then
        self:AttendanceSay("Резерв: предметов, которых нет в списках боссов аддона: "..unknown, true)
    end
    return added
end

-- Любое изменение резерва (своё, от офицера или после синхронизации).
-- fromLocalEdit — правка сделана на этом клиенте: надо разослать офицерам.
function auction:ReserveChanged(boss, itemID, fromLocalEdit)
    self.reserveRevision = self.reserveRevision + 1
    self:RequestSaveData()
    if fromLocalEdit then self:SendReserveUpdate(boss, itemID) end
    if self:IsLootMaster() then self:ApplyReserveOnLootMaster(boss, itemID) end
    self:ReserveUIChanged(boss, itemID)
end

-- На ЛМ: предмет ушёл в резерв — снимаем уже сделанные ставки на него (рейд
-- получит пустой SYNC) и сообщаем рейду об изменении.
function auction:ApplyReserveOnLootMaster(boss, itemID)
    local qty = self:GetReserveQty(boss, itemID)
    if qty > 0 then
        local bids = self.bids[boss] and self.bids[boss][itemID]
        if bids and #bids > 0 then
            self.bids[boss][itemID] = {}
            self:UpdateSortedBids(boss, itemID)
            self:UpdateBidCaches(boss, itemID)
            self:QueueSync(boss, itemID)
        end
    end
    local channel = GroupChannel()
    if channel and self:HasReserveAccess() then
        SendAddonMessage(self.prefix, "RES_ONE;"..boss..";"..itemID..";"..qty, channel)
    end
end

-- ======================
-- Отображение в главной таблице ставок
-- ======================

-- Перерисовывает то, что зависит от резерва: снимает выбор с ставшего
-- недоступным предмета, обновляет таблицу и вкладку «Резерв».
function auction:ReserveUIChanged(boss, itemID)
    if self.selectedBoss and self.selectedItem and (not boss or boss == self.selectedBoss) then
        if self:IsReserved(self.selectedBoss, self.selectedItem) then
            self.selectedItem = nil
            if self.itemDropdown then UIDropDownMenu_SetText(self.itemDropdown, "Выбрать предмет") end
        end
    end
    if self.selectedBoss and (not boss or boss == self.selectedBoss) then
        if not (itemID and self:RefreshRowForItem(itemID)) then
            self:RequestRefresh()
        end
    end
    if self.RefreshReserve then self:RefreshReserve() end
end

-- Красит строку таблицы ставок под текущее состояние резерва (в обе стороны:
-- строки берутся из пула и переиспользуются). Вызывается из RenderItemRow и RefreshTable.
function auction:ApplyReserveMark(row, bossName, itemID)
    if not row or not row.itemName then return end
    if bossName and itemID and self:IsReserved(bossName, itemID) then
        row.itemName:SetAlpha(0.45)
        row.icon:SetAlpha(0.45)
        row.bidsStr:SetText("|cffb0b0b0Резерв — ставки закрыты|r")
    else
        row.itemName:SetAlpha(1)
        row.icon:SetAlpha(1)
    end
end

-- Добавляет в уже подготовленный тултип предмета строки про резерв.
function auction:AppendReserveTooltip(itemID)
    local boss = self.selectedBoss
    if not boss or not itemID then return end
    local qty = self:GetReserveQty(boss, itemID)
    if qty <= 0 then return end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Резерв: ставки закрыты", 1, 0.5, 0.2)
    if self:HasReserveAccess() then
        local e = self:GetReserveEntry(boss, itemID)
        local who = (e and e.note and e.note ~= "") and ("   Покупатель: "..e.note) or ""
        GameTooltip:AddLine("Копий: "..qty..who, 0.8, 0.8, 0.8)
    end
end

-- Короткое предупреждение по центру экрана при попытке ставки на резерв.
function auction:ReserveClickNotice()
    if UIErrorsFrame then
        UIErrorsFrame:AddMessage("Предмет зарезервирован — ставки закрыты", 1.0, 0.5, 0.0, 3)
    end
end

-- ======================
-- Рассылка публичного списка (ЛМ → рейд)
-- ======================

-- Вызывается из events.lua, когда этот клиент стал ЛМ.
function auction:OnBecameLootMaster()
    if self:HasReserveAccess() then
        self:StartReserveSync(true)     -- подтянуть правки других офицеров
        self:QueueReserveBroadcast()
    elseif not self.reserveNoAccessWarned then
        self.reserveNoAccessWarned = true
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[EPBA]|r Вы Loot Master, но у вас нет доступа к вкладке «Резерв» (нужно право редактировать офицерскую заметку): предметы, проданные заранее, у вас блокироваться не будут.")
    end
end

-- Откладывает рассылку на BROADCAST_DELAY сек: серия HELLO от входящих в рейд
-- игроков превращается в одну рассылку, а не в десятки.
function auction:QueueReserveBroadcast()
    if not self:IsLootMaster() or self.resBroadcastTimer then return end
    self.resBroadcastTimer = self:ScheduleTimer(function()
        self.resBroadcastTimer = nil
        self:BroadcastReserves()
    end, BROADCAST_DELAY)
end

-- Полный публичный список в группу: RES… по записи, затем RES_END с числом записей.
function auction:BroadcastReserves()
    if not self:IsLootMaster() or not self:HasReserveAccess() then return end
    local channel = GroupChannel()
    if not channel then return end
    local gen = string.format("%x", math.random(0x1000, 0xFFFFF))
    local count = 0
    for boss, items in pairs(self.reserves) do
        for itemID, e in pairs(items) do
            if e.qty > 0 then
                self:AttQueueSend(string.format("RES;%s;%s;%d;%d", gen, boss, itemID, e.qty), channel)
                count = count + 1
            end
        end
    end
    self:AttQueueSend(string.format("RES_END;%s;%d", gen, count), channel)
    self:Debug("Резерв: рассылка в "..channel..", записей: "..count)
end

-- RES: запись нового публичного списка (копим до RES_END). Только от текущего ЛМ.
function auction:Handle_RES(rest, sender)
    if self:IsLootMaster() or sender ~= self.lastLM then return end
    local gen, boss, itemID, qty = rest:match("^(%x+);([^;]+);(%d+);(%d+)$")
    itemID, qty = tonumber(itemID), tonumber(qty)
    if not gen or not self.bosses[boss] or not self:BossHasItem(boss, itemID) or not qty or qty <= 0 or qty > self.RESERVE_MAX_QTY then return end
    local p = self.reservePending[gen]
    if not p then
        self.reservePending = {}           -- держим только самый свежий список
        p = { items = {}, count = 0 }
        self.reservePending[gen] = p
    end
    p.items[boss] = p.items[boss] or {}
    if not p.items[boss][itemID] then p.count = p.count + 1 end
    p.items[boss][itemID] = qty
end

-- RES_END: список полный — заменяем публичный целиком. Если записей пришло меньше
-- заявленного (потеря сообщений), оставляем прежний список.
function auction:Handle_RES_END(rest, sender)
    if self:IsLootMaster() or sender ~= self.lastLM then return end
    local gen, count = rest:match("^(%x+);(%d+)$")
    count = tonumber(count)
    if not gen or not count then return end
    local p = self.reservePending[gen]
    if (p and p.count >= count) or count == 0 then
        self.reservePublic = p and p.items or {}
        self.reservePending = {}
        self:ReserveUIChanged(nil, nil)
    else
        self:Debug("Резерв: список неполный ("..(p and p.count or 0).."/"..count.."), оставляю прежний")
    end
end

-- RES_ONE: одиночное изменение публичного списка (qty = 0 — снято).
function auction:Handle_RES_ONE(rest, sender)
    if self:IsLootMaster() or sender ~= self.lastLM then return end
    local boss, itemID, qty = rest:match("^([^;]+);(%d+);(%d+)$")
    itemID, qty = tonumber(itemID), tonumber(qty)
    if not boss or not self.bosses[boss] or not self:BossHasItem(boss, itemID) or not qty or qty > self.RESERVE_MAX_QTY then return end
    self.reservePublic[boss] = self.reservePublic[boss] or {}
    self.reservePublic[boss][itemID] = (qty > 0) and qty or nil
    self:ReserveUIChanged(boss, itemID)
end

-- RESERVED: ЛМ отклонил мою ставку. Заодно «лечит» публичный список: если у меня
-- предмета в нём не было (потеряли рассылку), добавляем.
function auction:Handle_RESERVED(rest, sender)
    local boss, itemID = rest:match("^([^;]+);(%d+)$")
    itemID = tonumber(itemID)
    if not boss or not self.bosses[boss] or not itemID then return end
    if sender == self.lastLM and not self:IsLootMaster() then
        self.reservePublic[boss] = self.reservePublic[boss] or {}
        if (self.reservePublic[boss][itemID] or 0) == 0 then self.reservePublic[boss][itemID] = 1 end
    end
    self:ReserveClickNotice()
    self:ReserveUIChanged(boss, itemID)
end

-- ======================
-- Синхронизация между офицерами
-- ======================

-- Правка одной записи — всем офицерам сразу (GUILD; без доступа клиенты игнорируют).
function auction:SendReserveUpdate(boss, itemID)
    if not IsInGuild() then return end
    local e = self:GetReserveEntry(boss, itemID)
    if not e then return end
    self:AttQueueSend(string.format("RES_UPD;%s;%d;%d;%d;%s", boss, itemID, e.qty, e.t, e.note or ""), "GUILD")
end

-- Проверка входящей записи (чужим данным не доверяем): известный босс и предмет,
-- разумные количество и время, чистая заметка. Возвращает запись или nil.
function auction:ValidateReserveEntry(boss, itemID, qty, t, note, by)
    if type(boss) ~= "string" or not self.bosses[boss] then return nil end
    if not itemID or not self:BossHasItem(boss, itemID) then return nil end
    if not qty or qty < 0 or qty > self.RESERVE_MAX_QTY then return nil end
    if not t or t < 1000000000 or t > 4000000000 then return nil end
    return { qty = math.floor(qty), note = CleanNote(note), t = math.floor(t), by = SafeBy(by) or "" }
end

-- Слияние: побеждает запись с большим временем правки. true — локальный список изменился.
function auction:MergeReserveEntry(boss, itemID, entry)
    self.reserves[boss] = self.reserves[boss] or {}
    local old = self.reserves[boss][itemID]
    if old and old.t >= entry.t then return false end
    if not old and self:CountReserveEntries() >= self.RESERVE_MAX_ENTRIES then return false end
    self.reserves[boss][itemID] = entry
    return true
end

-- RES_UPD от другого офицера.
function auction:Handle_RES_UPD(rest, sender)
    if self.StripRealm(sender) == UnitName("player") then return end
    if not self:HasReserveAccess() then return end
    local boss, itemID, qty, t, note = rest:match("^([^;]+);(%d+);(%d+);(%d+);(.*)$")
    itemID = tonumber(itemID)
    local entry = self:ValidateReserveEntry(boss, itemID, tonumber(qty), tonumber(t), note, self.StripRealm(sender))
    if entry and self:MergeReserveEntry(boss, itemID, entry) then
        self:ReserveChanged(boss, itemID, false)
    end
end

-- Запись ↔ строка для RES_REC: boss^itemID^qty^t^note^by.
function auction:SerializeReserveEntry(boss, itemID, e)
    return table.concat({ boss, tostring(itemID), tostring(e.qty), string.format("%d", e.t), e.note or "", e.by or "" }, "^")
end

function auction:ParseReserveEntry(str, defaultBy)
    local f = {}
    for part in (str.."^"):gmatch("(.-)%^") do f[#f + 1] = part end
    if #f ~= 6 then return nil end
    local itemID = tonumber(f[2])
    local entry = self:ValidateReserveEntry(f[1], itemID, tonumber(f[3]), tonumber(f[4]), f[5], (f[6] ~= "" and f[6]) or defaultBy)
    if not entry then return nil end
    return f[1], itemID, entry
end

-- Дайджест своего списка: "хэшБосса:itemID:t" в hex через запятую.
local function BuildDigest(self)
    local keys = {}
    for boss, items in pairs(self.reserves) do
        local h = BossHash(boss)
        for itemID, e in pairs(items) do
            keys[#keys + 1] = string.format("%x:%x:%x", h, itemID, e.t)
        end
    end
    table.sort(keys)
    return table.concat(keys, ",")
end

-- Запрашивает у офицеров недостающие/более свежие записи (pull, как у Attendance).
function auction:StartReserveSync(silent)
    if not self:HasReserveAccess() or not IsInGuild() then return false end
    if self.resSync and GetTime() - self.resSync.started < SYNC_MAX_SECONDS then
        if not silent then self:AttendanceSay("Резерв: синхронизация уже идёт", true) end
        return false
    end
    local sid = string.format("%x", math.random(0x1000, 0xFFFFF))
    local chunks = self.SplitUtf8(BuildDigest(self), CHUNK_BYTES)
    for i, chunk in ipairs(chunks) do
        self:AttQueueSend(string.format("RES_REQ;%s;%d;%d;%s", sid, i, #chunks, chunk), "GUILD")
    end
    local now = GetTime()
    self.resSync = { sid = sid, started = now, lastActivity = now, added = 0, from = {}, bufs = {}, silent = silent }
    self:ScheduleTimer(function() self:CheckReserveSyncFinished() end, 10)
    if not silent then self:AttendanceSay("Резерв: запрос на синхронизацию отправлен офицерам") end
    return true
end

function auction:CheckReserveSyncFinished()
    local s = self.resSync
    if not s then return end
    local now = GetTime()
    if now - s.lastActivity < 6 and now - s.started < SYNC_MAX_SECONDS then
        self:ScheduleTimer(function() self:CheckReserveSyncFinished() end, 3)
        return
    end
    self.resSync = nil
    local names = {}
    for name in pairs(s.from) do names[#names + 1] = name end
    table.sort(names)
    local who = table.concat(names, ", ")
    if s.added > 0 then
        self:AttendanceSay("Резерв: синхронизация завершена, обновлено записей: "..s.added.." (ответили: "..who..")")
    elseif not s.silent then
        if #names == 0 then
            self:AttendanceSay("Резерв: никто из офицеров не ответил", true)
        else
            self:AttendanceSay("Резерв: синхронизация завершена, новых записей нет (ответили: "..who..")")
        end
    end
end

-- Один раз за сессию — тихая синхронизация через 30 секунд после входа в мир.
function auction:ScheduleReserveAutoSync()
    if self.resAutoSynced then return end
    self.resAutoSynced = true
    self:ScheduleTimer(function() self:StartReserveSync(true) end, 30)
end

-- RES_REQ: собираем дайджест запросившего и отвечаем тем, чего у него нет или что у нас свежее.
function auction:Handle_RES_REQ(rest, sender)
    if self.StripRealm(sender) == UnitName("player") then return end
    if not self:HasReserveAccess() then return end
    local sid, i, n, payload = rest:match("^([^;]*);(%d+);(%d+);(.*)$")
    i, n = tonumber(i), tonumber(n)
    if not sid or not i or not n or n < 1 or n > 40 or i < 1 or i > n then return end

    self.resReqBuf = self.resReqBuf or {}
    local key = sender..":"..sid
    local buf = self.resReqBuf[key]
    if not buf then
        buf = { parts = {}, n = n, got = 0, done = false }
        self.resReqBuf[key] = buf
        self:ScheduleTimer(function() self:RespondToReserveRequest(sender, sid) end, REQUEST_WAIT)
    end
    if not buf.parts[i] then
        buf.parts[i] = payload
        buf.got = buf.got + 1
    end
    if buf.got == buf.n then self:RespondToReserveRequest(sender, sid) end
end

function auction:RespondToReserveRequest(sender, sid)
    local key = sender..":"..sid
    local buf = self.resReqBuf and self.resReqBuf[key]
    if not buf or buf.done then return end
    buf.done = true
    self.resReqBuf[key] = nil

    self.resServed = self.resServed or {}
    local now = GetTime()
    if self.resServed[sender] and now - self.resServed[sender] < RESPOND_COOLDOWN then return end
    self.resServed[sender] = now

    local parts = {}
    for i = 1, buf.n do parts[i] = buf.parts[i] or "" end
    local theirs = {}
    for item in (table.concat(parts)..","):gmatch("(.-),") do
        local h, id, t = item:match("^(%x+):(%x+):(%x+)$")
        if h then theirs[h..":"..id] = tonumber(t, 16) end
    end

    local missing = {}
    for boss, items in pairs(self.reserves) do
        local h = string.format("%x", BossHash(boss))
        for itemID, e in pairs(items) do
            local theirT = theirs[h..":"..string.format("%x", itemID)]
            if not theirT or e.t > theirT then
                missing[#missing + 1] = { boss = boss, itemID = itemID, e = e }
            end
        end
    end

    local total = math.min(#missing, MAX_RECORDS_PER_RESPONSE)
    for idx = 1, total do
        local m = missing[idx]
        local chunks = self.SplitUtf8(self:SerializeReserveEntry(m.boss, m.itemID, m.e), CHUNK_BYTES)
        for i, chunk in ipairs(chunks) do
            self:AttQueueSend(string.format("RES_REC;%s;%d;%d;%d;%s", sid, idx, i, #chunks, chunk), "WHISPER", sender)
        end
    end
    self:AttQueueSend(string.format("RES_DONE;%s;%d", sid, total), "WHISPER", sender)
end

-- RES_REC: кусок записи от офицера, которому мы слали запрос.
function auction:Handle_RES_REC(rest, sender)
    local s = self.resSync
    if not s then return end
    local sid, rid, i, n, chunk = rest:match("^([^;]*);(%d+);(%d+);(%d+);(.*)$")
    if not sid or sid ~= s.sid then return end
    i, n = tonumber(i), tonumber(n)
    if not i or not n or n < 1 or n > 10 or i < 1 or i > n then return end
    s.lastActivity = GetTime()

    local key = sender..":"..rid
    local buf = s.bufs[key]
    if not buf then
        buf = { parts = {}, got = 0, n = n }
        s.bufs[key] = buf
    end
    if not buf.parts[i] then
        buf.parts[i] = chunk
        buf.got = buf.got + 1
    end
    if buf.got == buf.n then
        s.bufs[key] = nil
        local boss, itemID, entry = self:ParseReserveEntry(table.concat(buf.parts, "", 1, buf.n), self.StripRealm(sender))
        if entry and self:MergeReserveEntry(boss, itemID, entry) then
            s.added = s.added + 1
            self:ReserveChanged(boss, itemID, false)
        end
    end
end

function auction:Handle_RES_DONE(rest, sender)
    local s = self.resSync
    if not s then return end
    local sid, count = rest:match("^([^;]*);(%d+)$")
    if not sid or sid ~= s.sid then return end
    s.from[sender] = tonumber(count) or 0
    s.lastActivity = GetTime()
end
