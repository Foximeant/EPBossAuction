local auction = EPBossAuction

-- ============================================================
-- bis.lua — BiS-конструктор: данные, правила, экспорт/импорт
-- ============================================================
-- Интерфейс (вкладка «BiS») — в bis_ui.lua. Здесь только данные и логика.
--
-- Список — самостоятельный объект, не привязанный к персонажу и к тому, какие
-- предметы у игрока есть. Предметы хранятся только как itemID, их названия и иконки
-- подтягиваются из кэша клиента (BisItemInfo).
--
--   EPBossAuctionDB.bis.lists[id] = {
--       id      = "1a2b3c4d5e6f",       -- уникален, создаётся при создании/импорте
--       name    = "Название",
--       author  = "Ник автора",
--       class   = "WARRIOR",            -- токен класса (RAID_CLASS_COLORS)
--       spec    = 1,                    -- 1..3 (порядок как в auction.bisClasses[..].specs)
--       comment = "Заметка к списку",
--       updated = <unix-время правки>,
--       slots   = { [1..17] = { items = { itemID, ... (до 3) }, note = "Заметка к слоту" } },
--   }
--
-- Данные лежат прямо в EPBossAuctionDB.bis (SaveData их не трогает, клиент сохраняет
-- всю таблицу при выходе), в сеть списки не уходят — только через строку экспорта.
--
-- Формат строки обмена (одна строка, без символа «|», поэтому безопасна в EditBox
-- и мессенджерах):
--   EPBIS1~имя~автор~КЛАСС~спек~заметка_списка~слот1;слот2;...;слот17~контрольная_сумма
-- слот = id,id,id или id,id^заметка_слота (пустой слот — пустая строка).
-- Текстовые поля кодируются %XX для символов % ~ ; , ^ | и управляющих (в т.ч. перенос строки).
-- Контрольная сумма считается по всему тексту до последней «~» и ловит обрезанную
-- или испорченную при копировании строку.
-- ============================================================

auction.BIS_FORMAT = "EPBIS1"
auction.BIS_MAX_PER_SLOT = 3        -- предметов в слоте: первый — основной, остальные запасные
auction.BIS_NAME_LEN = 40
auction.BIS_AUTHOR_LEN = 24
auction.BIS_LIST_NOTE_LEN = 500
auction.BIS_SLOT_NOTE_LEN = 200
auction.BIS_MAX_LISTS = 300

-- ======================
-- Классы и специализации
-- ======================
-- Порядок классов = CLASS_SORT_ORDER (07_constants). Иконки специализаций — штатные
-- иконки клиента; если на сервере какой-то нет, интерфейс подставит знак вопроса.
auction.bisClasses = {
    { token = "WARRIOR", name = "Воин", specs = {
        { name = "Оружие",       icon = "Interface\\Icons\\Ability_Rogue_Eviscerate" },
        { name = "Неистовство",  icon = "Interface\\Icons\\Ability_Warrior_InnerRage" },
        { name = "Защита",       icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance" } } },
    { token = "DEATHKNIGHT", name = "Рыцарь смерти", specs = {
        { name = "Кровь",        icon = "Interface\\Icons\\Spell_Deathknight_BloodPresence" },
        { name = "Лёд",          icon = "Interface\\Icons\\Spell_Deathknight_FrostPresence" },
        { name = "Нечестивость", icon = "Interface\\Icons\\Spell_Deathknight_UnholyPresence" } } },
    { token = "PALADIN", name = "Паладин", specs = {
        { name = "Свет",         icon = "Interface\\Icons\\Spell_Holy_HolyBolt" },
        { name = "Защита",       icon = "Interface\\Icons\\Spell_Holy_DevotionAura" },
        { name = "Возмездие",    icon = "Interface\\Icons\\Spell_Holy_AuraOfLight" } } },
    { token = "PRIEST", name = "Жрец", specs = {
        { name = "Послушание",   icon = "Interface\\Icons\\Spell_Holy_WordFortitude" },
        { name = "Свет",         icon = "Interface\\Icons\\Spell_Holy_GuardianSpirit" },
        { name = "Тьма",         icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain" } } },
    { token = "SHAMAN", name = "Шаман", specs = {
        { name = "Стихии",       icon = "Interface\\Icons\\Spell_Nature_Lightning" },
        { name = "Совершенствование", icon = "Interface\\Icons\\Spell_Nature_LightningShield" },
        { name = "Исцеление",    icon = "Interface\\Icons\\Spell_Nature_MagicImmunity" } } },
    { token = "DRUID", name = "Друид", specs = {
        { name = "Баланс",       icon = "Interface\\Icons\\Spell_Nature_StarFall" },
        { name = "Сила зверя",   icon = "Interface\\Icons\\Ability_Racial_BearForm" },
        { name = "Исцеление",    icon = "Interface\\Icons\\Spell_Nature_HealingTouch" } } },
    { token = "ROGUE", name = "Разбойник", specs = {
        { name = "Убийство",     icon = "Interface\\Icons\\Ability_Rogue_Eviscerate" },
        { name = "Бой",          icon = "Interface\\Icons\\Ability_BackStab" },
        { name = "Скрытность",   icon = "Interface\\Icons\\Ability_Stealth" } } },
    { token = "MAGE", name = "Маг", specs = {
        { name = "Тайная магия", icon = "Interface\\Icons\\Spell_Holy_MagicalSentry" },
        { name = "Огонь",        icon = "Interface\\Icons\\Spell_Fire_FireBolt02" },
        { name = "Лёд",          icon = "Interface\\Icons\\Spell_Frost_FrostBolt02" } } },
    { token = "WARLOCK", name = "Чернокнижник", specs = {
        { name = "Колдовство",   icon = "Interface\\Icons\\Spell_Shadow_DeathCoil" },
        { name = "Демонология",  icon = "Interface\\Icons\\Spell_Shadow_Metamorphosis" },
        { name = "Разрушение",   icon = "Interface\\Icons\\Spell_Shadow_RainOfFire" } } },
    { token = "HUNTER", name = "Охотник", specs = {
        { name = "Повелитель зверей", icon = "Interface\\Icons\\Ability_Hunter_BeastTaming" },
        { name = "Стрельба",     icon = "Interface\\Icons\\Ability_Marksmanship" },
        { name = "Выживание",    icon = "Interface\\Icons\\Ability_Hunter_SwiftStrike" } } },
}

local classByToken = {}
for _, c in ipairs(auction.bisClasses) do classByToken[c.token] = c end

function auction:BisClass(token)
    return classByToken[token]
end

-- ======================
-- Слоты (17 штук; порядок зашит в формат экспорта — НЕ менять местами)
-- ======================
-- slot — имя слота для GetInventorySlotInfo (оттуда берём иконку пустого слота).
auction.bisSlots = {
    { slot = "HeadSlot",          name = "Голова" },
    { slot = "NeckSlot",          name = "Шея" },
    { slot = "ShoulderSlot",      name = "Плечи" },
    { slot = "BackSlot",          name = "Спина" },
    { slot = "ChestSlot",         name = "Грудь" },
    { slot = "WristSlot",         name = "Запястья" },
    { slot = "HandsSlot",         name = "Кисти" },
    { slot = "WaistSlot",         name = "Пояс" },
    { slot = "LegsSlot",          name = "Ноги" },
    { slot = "FeetSlot",          name = "Ступни" },
    { slot = "Finger0Slot",       name = "Кольцо 1" },
    { slot = "Finger1Slot",       name = "Кольцо 2" },
    { slot = "Trinket0Slot",      name = "Аксессуар 1" },
    { slot = "Trinket1Slot",      name = "Аксессуар 2" },
    { slot = "MainHandSlot",      name = "Правая рука" },
    { slot = "SecondaryHandSlot", name = "Левая рука" },
    { slot = "RangedSlot",        name = "Дальний бой" },
}
auction.BIS_NUM_SLOTS = #auction.bisSlots

-- ======================
-- Хранилище
-- ======================

local function Utf8Cut(s, n)
    if auction.Utf8Prefix then return auction.Utf8Prefix(s, n) end
    return s:sub(1, n)
end

-- Убирает управляющие символы (кроме переноса строки, если keepNewlines) и обрезает.
local function CleanText(s, maxChars, keepNewlines)
    s = tostring(s or "")
    if keepNewlines then
        s = s:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("[\1-\9\11-\31]", "")
    else
        s = s:gsub("[\1-\31]", " ")
    end
    s = s:gsub("|", "")   -- коды цвета/ссылок в названиях и заметках не нужны, а ломают отображение
    return Utf8Cut(s, maxChars)
end
auction.BisCleanText = CleanText

local function NewId(existing)
    local id
    repeat
        id = string.format("%x%04x%04x", time(), math.random(0, 65535), math.random(0, 65535))
    until not existing[id]
    return id
end

local function ValidItemID(n)
    return type(n) == "number" and n >= 1 and n <= 999999999 and n == math.floor(n)
end

-- Чистит и нормализует один список; возвращает false, если список негоден.
local function SanitizeList(list)
    if type(list) ~= "table" then return false end
    if not classByToken[list.class] then return false end
    list.spec = tonumber(list.spec)
    if not list.spec or list.spec < 1 or list.spec > 3 or list.spec ~= math.floor(list.spec) then return false end
    list.name = CleanText(list.name, auction.BIS_NAME_LEN)
    if list.name == "" then list.name = "Без названия" end
    list.author = CleanText(list.author, auction.BIS_AUTHOR_LEN)
    list.comment = CleanText(list.comment, auction.BIS_LIST_NOTE_LEN, true)
    list.updated = tonumber(list.updated) or 0
    if type(list.slots) ~= "table" then list.slots = {} end
    local clean = {}
    for i = 1, auction.BIS_NUM_SLOTS do
        local s = list.slots[i]
        if type(s) == "table" then
            local items, seen = {}, {}
            for _, id in ipairs(type(s.items) == "table" and s.items or {}) do
                id = tonumber(id)
                if ValidItemID(id) and not seen[id] and #items < auction.BIS_MAX_PER_SLOT then
                    seen[id] = true
                    items[#items + 1] = id
                end
            end
            local note = CleanText(s.note, auction.BIS_SLOT_NOTE_LEN, true)
            if #items > 0 or note ~= "" then
                clean[i] = { items = items, note = note }
            end
        end
    end
    list.slots = clean
    return true
end

-- Возвращает таблицу {lists = {...}}; при первом обращении за сессию чистит данные
-- (на случай ручной правки SavedVariables или будущих изменений формата).
function auction:BisData()
    local db = self:GetDB()
    if type(db.bis) ~= "table" then db.bis = {} end
    local bis = db.bis
    if type(bis.lists) ~= "table" then bis.lists = {} end
    if not self._bisSanitized then
        self._bisSanitized = true
        for id, list in pairs(bis.lists) do
            if type(id) ~= "string" or not SanitizeList(list) then
                bis.lists[id] = nil
            else
                list.id = id
            end
        end
    end
    return bis
end

function auction:BisGetList(id)
    return id and self:BisData().lists[id] or nil
end

function auction:BisListCount()
    local n = 0
    for _ in pairs(self:BisData().lists) do n = n + 1 end
    return n
end

-- Число списков: по классу (spec = nil) или по классу и специализации.
function auction:BisCountLists(class, spec)
    local n = 0
    for _, list in pairs(self:BisData().lists) do
        if list.class == class and (not spec or list.spec == spec) then n = n + 1 end
    end
    return n
end

-- Списки класса и специализации: новые правки сверху.
function auction:BisGetLists(class, spec)
    local res = {}
    for _, list in pairs(self:BisData().lists) do
        if list.class == class and list.spec == spec then res[#res + 1] = list end
    end
    table.sort(res, function(a, b)
        if a.updated ~= b.updated then return a.updated > b.updated end
        return a.id < b.id
    end)
    return res
end

-- Сколько всего предметов в списке.
function auction:BisItemCount(list)
    local n = 0
    for _, s in pairs(list.slots) do n = n + #s.items end
    return n
end

-- Сколько слотов с заметкой.
function auction:BisNoteCount(list)
    local n = 0
    for _, s in pairs(list.slots) do if s.note and s.note ~= "" then n = n + 1 end end
    return n
end

local function Touch(list) list.updated = time() end

function auction:BisCreateList(class, spec, name, author)
    local bis = self:BisData()
    if self:BisListCount() >= self.BIS_MAX_LISTS then
        return nil, "Достигнут предел: "..self.BIS_MAX_LISTS.." списков. Удалите ненужные."
    end
    if not classByToken[class] or not spec or spec < 1 or spec > 3 then return nil, "Неизвестный класс или специализация" end
    local list = {
        class = class, spec = spec,
        name = CleanText(name, self.BIS_NAME_LEN),
        author = CleanText(author or UnitName("player") or "", self.BIS_AUTHOR_LEN),
        comment = "", slots = {}, updated = time(),
    }
    if list.name == "" then list.name = "Новый список" end
    list.id = NewId(bis.lists)
    bis.lists[list.id] = list
    return list
end

function auction:BisCopyList(id)
    local src = self:BisGetList(id)
    if not src then return nil end
    if self:BisListCount() >= self.BIS_MAX_LISTS then
        return nil, "Достигнут предел: "..self.BIS_MAX_LISTS.." списков. Удалите ненужные."
    end
    local bis = self:BisData()
    local copy = self.DeepCopy and self:DeepCopy(src) or src
    copy.id = NewId(bis.lists)
    copy.name = CleanText("Копия: "..src.name, self.BIS_NAME_LEN)
    copy.updated = time()
    bis.lists[copy.id] = copy
    return copy
end

function auction:BisDeleteList(id)
    self:BisData().lists[id] = nil
end

function auction:BisSetName(list, text)
    local name = CleanText(text, self.BIS_NAME_LEN)
    if name == "" then name = list.name end
    if name ~= list.name then list.name = name; Touch(list) end
    return list.name
end

function auction:BisSetAuthor(list, text)
    local author = CleanText(text, self.BIS_AUTHOR_LEN)
    if author ~= list.author then list.author = author; Touch(list) end
    return list.author
end

function auction:BisSetComment(list, text)
    list.comment = CleanText(text, self.BIS_LIST_NOTE_LEN, true)
    Touch(list)
end

local function DropIfEmpty(list, slot)
    local s = list.slots[slot]
    if s and #s.items == 0 and (not s.note or s.note == "") then list.slots[slot] = nil end
end

function auction:BisSetSlotNote(list, slot, text)
    if slot < 1 or slot > self.BIS_NUM_SLOTS then return end
    local note = CleanText(text, self.BIS_SLOT_NOTE_LEN, true)
    local s = list.slots[slot]
    if not s then
        if note == "" then return end
        s = { items = {}, note = "" }
        list.slots[slot] = s
    end
    s.note = note
    DropIfEmpty(list, slot)
    Touch(list)
end

-- Добавляет предмет в конец слота. Возвращает true или false + причину.
function auction:BisAddItem(list, slot, itemID)
    if slot < 1 or slot > self.BIS_NUM_SLOTS then return false, "Выберите слот" end
    if not ValidItemID(itemID) then return false, "Некорректный itemID" end
    local s = list.slots[slot]
    if not s then
        s = { items = {}, note = "" }
        list.slots[slot] = s
    end
    for _, id in ipairs(s.items) do
        if id == itemID then return false, "Этот предмет уже есть в слоте" end
    end
    if #s.items >= self.BIS_MAX_PER_SLOT then
        DropIfEmpty(list, slot)
        return false, "В слоте максимум "..self.BIS_MAX_PER_SLOT.." предмета: уберите лишний (ПКМ по иконке)"
    end
    s.items[#s.items + 1] = itemID
    Touch(list)
    return true
end

function auction:BisRemoveItem(list, slot, pos)
    local s = list.slots[slot]
    if not s or not s.items[pos] then return end
    table.remove(s.items, pos)
    DropIfEmpty(list, slot)
    Touch(list)
end

-- Делает предмет на позиции pos основным (остальные сдвигаются).
function auction:BisPromoteItem(list, slot, pos)
    local s = list.slots[slot]
    if not s or pos <= 1 or not s.items[pos] then return end
    local id = table.remove(s.items, pos)
    table.insert(s.items, 1, id)
    Touch(list)
end

function auction:BisClearSlot(list, slot)
    if list.slots[slot] then
        list.slots[slot] = nil
        Touch(list)
    end
end

-- ======================
-- Предметы: ввод и кэш клиента
-- ======================

-- Достаёт itemID из текста: все ссылки |Hitem:ID:...|h, иначе «item:ID», иначе число.
-- Возвращает список id (в порядке появления, без повторов).
function auction:BisExtractItemIDs(text)
    local ids, seen = {}, {}
    local function add(n)
        n = tonumber(n)
        if ValidItemID(n) and not seen[n] then
            seen[n] = true
            ids[#ids + 1] = n
        end
    end
    text = tostring(text or "")
    for n in text:gmatch("[Ii]tem:(%d+)") do add(n) end
    if #ids == 0 then
        for n in text:gmatch("%d+") do add(n) end
    end
    return ids
end

local scanTip
-- Просит клиент (и сервер) прислать предмет, которого нет в кэше: скрытый тултип.
-- События GET_ITEM_INFO_RECEIVED в 3.3.5 нет, поэтому интерфейс просто перечитывает кэш позже.
local function PrimeItem(id)
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "EPBossAuctionBisScanTip", UIParent, "GameTooltipTemplate")
    end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    pcall(scanTip.SetHyperlink, scanTip, "item:"..id)
end

-- name, quality, icon, known. Если предмета нет в кэше клиента: nil, nil, nil, false.
function auction:BisItemInfo(id)
    local name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(id)
    if name then return name, quality or 1, icon, true end
    PrimeItem(id)
    return nil, nil, nil, false
end

-- ======================
-- Экспорт / импорт
-- ======================

local function Enc(s)
    return (tostring(s or ""):gsub("[%%~;,%^|\1-\31]", function(ch)
        return string.format("%%%02X", ch:byte())
    end))
end

local function Dec(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function Checksum(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end

function auction:BisExport(list)
    local slotFields = {}
    for i = 1, self.BIS_NUM_SLOTS do
        local s = list.slots[i]
        local f = ""
        if s then
            f = table.concat(s.items, ",")
            if s.note and s.note ~= "" then f = f.."^"..Enc(s.note) end
        end
        slotFields[i] = f
    end
    local body = table.concat({
        self.BIS_FORMAT, Enc(list.name), Enc(list.author), list.class, tostring(list.spec),
        Enc(list.comment), table.concat(slotFields, ";"),
    }, "~")
    return body.."~"..Checksum(body)
end

-- Разбирает строку. Возвращает data или nil + текст ошибки (пустая строка — «пока ничего не введено»).
-- data = { name, author, class, spec, comment, slots, items (число предметов) }.
function auction:BisParse(text)
    text = strtrim(tostring(text or ""))
    if text == "" then return nil, "" end
    local fields = { strsplit("~", text) }
    if fields[1] ~= self.BIS_FORMAT then
        if text:sub(1, 5) == "EPBIS" then
            return nil, "Эта строка создана более новой версией аддона — обновите аддон"
        end
        return nil, "Это не строка BiS-листа (она должна начинаться с "..self.BIS_FORMAT..")"
    end
    if #fields ~= 8 then
        return nil, "Строка повреждена или обрезана: не хватает данных"
    end
    local body = text:sub(1, #text - #fields[8] - 1)
    if Checksum(body) ~= fields[8]:lower() then
        return nil, "Контрольная сумма не сошлась: строка испорчена при копировании"
    end
    local cls = fields[4]
    if not classByToken[cls] then return nil, "Неизвестный класс: "..cls end
    local spec = tonumber(fields[5])
    if not spec or spec < 1 or spec > 3 or spec ~= math.floor(spec) then
        return nil, "Некорректная специализация"
    end
    local slotParts = { strsplit(";", fields[7]) }
    if #slotParts ~= self.BIS_NUM_SLOTS then
        return nil, "Некорректное число слотов ("..#slotParts..", нужно "..self.BIS_NUM_SLOTS..")"
    end

    local data = {
        name = CleanText(Dec(fields[2]), self.BIS_NAME_LEN),
        author = CleanText(Dec(fields[3]), self.BIS_AUTHOR_LEN),
        class = cls, spec = spec,
        comment = CleanText(Dec(fields[6]), self.BIS_LIST_NOTE_LEN, true),
        slots = {}, items = 0,
    }
    for i, part in ipairs(slotParts) do
        local p = part:find("^", 1, true)
        local idsStr = p and part:sub(1, p - 1) or part
        local note = p and CleanText(Dec(part:sub(p + 1)), self.BIS_SLOT_NOTE_LEN, true) or ""
        local items, seen = {}, {}
        for token in idsStr:gmatch("[^,]+") do
            if not token:match("^%d+$") or #token > 9 then
                return nil, "Некорректный itemID в слоте "..i.." ("..self.bisSlots[i].name..")"
            end
            local n = tonumber(token)
            if not ValidItemID(n) then return nil, "Некорректный itemID в слоте "..i end
            if not seen[n] then
                if #items >= self.BIS_MAX_PER_SLOT then
                    return nil, "Слишком много предметов в слоте "..i.." ("..self.bisSlots[i].name..")"
                end
                seen[n] = true
                items[#items + 1] = n
            end
        end
        if #items > 0 or note ~= "" then
            data.slots[i] = { items = items, note = note }
            data.items = data.items + #items
        end
    end
    return data
end

-- Создаёт новый список из разобранных данных (старые списки никогда не перезаписываются).
function auction:BisImport(data)
    if self:BisListCount() >= self.BIS_MAX_LISTS then
        return nil, "Достигнут предел: "..self.BIS_MAX_LISTS.." списков. Удалите ненужные."
    end
    local bis = self:BisData()
    local list = {
        class = data.class, spec = data.spec,
        name = data.name ~= "" and data.name or "Без названия",
        author = data.author, comment = data.comment,
        slots = data.slots, updated = time(),
    }
    list.id = NewId(bis.lists)
    bis.lists[list.id] = list
    return list
end
