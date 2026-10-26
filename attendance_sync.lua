local auction = EPBossAuction

-- ============================================================
-- attendance_sync.lua — синхронизация истории посещаемости между офицерами
-- ============================================================
-- Зачем: каждый офицер пишет историю на своём клиенте (см. attendance.lua), и
-- у того, кого не было в рейде при килле, в истории дыра. Синхронизация
-- докачивает недостающие записи у других офицеров.
--
-- Как это работает (три команды, диспетчер HandleMessage в comm.lua находит
-- Handle_<КОМАНДА> сам):
--   ATT_REQ;<sid>;<i>;<n>;<ключи>      GUILD    запрос: "вот что у меня есть, пришлите остальное".
--                                      Ключи — компактный список уже имеющихся
--                                      записей (время:хэш босса), часть i из n.
--   ATT_REC;<sid>;<rid>;<i>;<n>;<данные> WHISPER  ответ: одна запись целиком, кусок i из n.
--   ATT_DONE;<sid>;<число>             WHISPER  "я закончил, прислал столько записей".
-- sid — случайный номер сессии (чужие ответы с другим sid игнорируются).
--
-- Что именно синхронизируется:
--   • только записи за последние ATT_SYNC_DAYS дней и только с известным боссом;
--   • одинаковым считается килл с тем же боссом и временем в пределах
--     ATTENDANCE_SAME_KILL_SECONDS (у каждого офицера время записи чуть своё);
--   • при совпадении остаётся ЛОКАЛЬНАЯ запись (дополняются только мейны);
--   • то, что вы удалили или очистили (attendanceMeta в attendance.lua), от
--     других офицеров назад не возвращается.
--
-- Когда запускается: кнопкой "Синхронизировать" на вкладке и один раз за сессию
-- автоматически через 25 секунд после входа в мир (ScheduleAttendanceAutoSync,
-- вызывается из HandleWorldEnter в comm.lua).
--
-- Ограничения и безопасность (сознательно простые):
--   • 3.3.5a ограничивает сообщение 255 байтами, поэтому запись режется на куски
--     (SplitUtf8 — не посреди русской буквы), а отправка идёт очередью по
--     одному сообщению в 0.2 сек (AttQueueSend), чтобы не упереться в лимиты.
--   • Запрос уходит всей гильдии, отвечают только те, у кого есть доступ к
--     Attendance (HasAttendanceAccess). Проверить, что запрашивающий — именно
--     офицер, клиент не может: любой гильдеец с аддоном и подправленным кодом
--     может запросить историю. Данные — только имена и классы в рейде.
--   • Ответы принимаются только в течение нашей сессии и только с её sid.
--   • Входящие записи проходят проверку (DeserializeAttendanceRecord +
--     MergeAttendanceRecord): известный босс, разумное время, не больше 60 игроков.
-- ============================================================

-- За сколько последних дней синхронизируем историю.
auction.ATT_SYNC_DAYS = 60

local CHUNK_BYTES = 170               -- размер куска данных в одном сообщении
local SEND_INTERVAL = 0.2             -- пауза между исходящими сообщениями, сек
local MAX_RECORDS_PER_RESPONSE = 120  -- не больше записей в одном ответе
local RESPOND_COOLDOWN = 20           -- не отвечать одному и тому же запросившему чаще, сек
local SYNC_MAX_SECONDS = 120          -- сессия синхронизации длится не дольше, сек
local REQUEST_WAIT = 6                -- сколько ждём недостающие куски запроса, сек

-- Коды классов в сериализованной записи (один символ вместо длинного токена).
local CLASS_CODES = {
    WARRIOR = "0", PALADIN = "1", HUNTER = "2", ROGUE = "3", PRIEST = "4",
    DEATHKNIGHT = "5", SHAMAN = "6", MAGE = "7", WARLOCK = "8", DRUID = "9",
}
local CODE_CLASSES = {}
for token, code in pairs(CLASS_CODES) do CODE_CLASSES[code] = token end

-- ======================
-- Сериализация
-- ======================

-- Короткий хэш имени босса (для ключей записей): сумма по байтам, 16 бит.
local function BossHash(boss)
    local h = 0
    for i = 1, #boss do h = (h * 31 + boss:byte(i)) % 65536 end
    return h
end

-- Ключ записи для обмена: "время:хэш_босса" в hex, например "6537c8a1:3f2a".
function auction:AttendanceKey(rec)
    return string.format("%x:%x", math.floor(rec.t), BossHash(rec.boss))
end

-- Разбирает список ключей "t:h,t:h,..." в список { t, h }.
local function ParseKeys(csv)
    local list = {}
    for item in (csv..","):gmatch("(.-),") do
        local th, hh = item:match("^(%x+):(%x+)$")
        if th then list[#list + 1] = { t = tonumber(th, 16), h = tonumber(hh, 16) } end
    end
    return list
end

-- Режет строку на куски не длиннее maxBytes, не разрывая UTF-8 символ
-- (кириллица — 2 байта): если следующий байт — "продолжение" символа,
-- кусок укорачивается до границы. Пустая строка даёт один пустой кусок.
local function SplitUtf8(str, maxBytes)
    local chunks, pos, len = {}, 1, #str
    if len == 0 then return { "" } end
    while pos <= len do
        local stop = math.min(pos + maxBytes - 1, len)
        if stop < len then
            while stop > pos do
                local nextByte = str:byte(stop + 1)
                if nextByte and nextByte >= 0x80 and nextByte < 0xC0 then stop = stop - 1 else break end
            end
        end
        chunks[#chunks + 1] = str:sub(pos, stop)
        pos = stop + 1
    end
    return chunks
end
auction.SplitUtf8 = SplitUtf8

-- Имя годится для передачи, если в нём нет служебных символов формата.
local function SafeName(s)
    if type(s) == "string" and #s > 0 and #s <= 32 and not s:find("[%^~,;|]") then return s end
    return nil
end

-- Запись → строка. Поля через "^": время, босс, подземелье, флаги ("m" —
-- вручную), игроки "имя~код класса", отдыхающие, мейны "твинк~мейн" (списки через ",").
function auction:SerializeAttendanceRecord(rec)
    local players = {}
    for name, class in pairs(rec.players) do
        if SafeName(name) then players[#players + 1] = name.."~"..(CLASS_CODES[class] or "?") end
    end
    table.sort(players)

    local rested = {}
    for name in pairs(rec.rested or {}) do
        if SafeName(name) then rested[#rested + 1] = name end
    end
    table.sort(rested)

    local mains = {}
    for alt, main in pairs(rec.mains or {}) do
        if SafeName(alt) and SafeName(main) then mains[#mains + 1] = alt.."~"..main end
    end
    table.sort(mains)

    return table.concat({
        string.format("%d", math.floor(rec.t)),
        rec.boss or "",
        rec.instance or "",
        rec.manual and "m" or "",
        table.concat(players, ","),
        table.concat(rested, ","),
        table.concat(mains, ","),
    }, "^")
end

-- Строка → запись, либо nil, если данные не проходят проверку (чужие данные
-- не доверяем): 7 полей, разумное время, известный нам босс, 1–60 игроков.
function auction:DeserializeAttendanceRecord(str)
    local fields = {}
    for part in (str.."^"):gmatch("(.-)%^") do fields[#fields + 1] = part end
    if #fields ~= 7 then return nil end

    local t = tonumber(fields[1])
    local boss = fields[2]
    if not t or t < 1000000000 or t > 4000000000 then return nil end
    if boss == "" or not self.bosses[boss] then return nil end

    local rec = { t = math.floor(t), boss = boss, players = {}, rested = {} }
    rec.instance = self.bossToInstance[boss] or (fields[3] ~= "" and fields[3] or nil)
    if fields[4] == "m" then rec.manual = true end

    local count = 0
    for entry in (fields[5]..","):gmatch("(.-),") do
        local name, code = entry:match("^([^~]+)~(.)$")
        if name and #name <= 32 then
            rec.players[name] = CODE_CLASSES[code] or "UNKNOWN"
            count = count + 1
            if count > 60 then return nil end
        end
    end
    if count == 0 then return nil end

    for name in (fields[6]..","):gmatch("(.-),") do
        if name ~= "" and rec.players[name] then rec.rested[name] = true end
    end

    local mains
    for entry in (fields[7]..","):gmatch("(.-),") do
        local alt, main = entry:match("^([^~]+)~([^~]+)$")
        if alt and main and rec.players[alt] and #main <= 32 then
            mains = mains or {}
            mains[alt] = main
        end
    end
    rec.mains = mains
    return rec
end

-- ======================
-- Очередь отправки
-- ======================

-- Ставит сообщение в очередь; очередь разбирается по одному сообщению раз в
-- SEND_INTERVAL секунд. channel — "GUILD" или "WHISPER" (тогда target — имя).
function auction:AttQueueSend(msg, channel, target)
    self.attSendQueue = self.attSendQueue or {}
    table.insert(self.attSendQueue, { msg = msg, channel = channel, target = target })
    if not self.attSendRunning then
        self.attSendRunning = true
        self:AttPumpQueue()
    end
end

-- Отправляет следующее сообщение из очереди и планирует следующее.
function auction:AttPumpQueue()
    local item = table.remove(self.attSendQueue or {}, 1)
    if not item then
        self.attSendRunning = false
        return
    end
    SendAddonMessage(self.prefix, item.msg, item.channel, item.target)
    self:ScheduleTimer(function() self:AttPumpQueue() end, SEND_INTERVAL)
end

-- ======================
-- Запрос (мы просим записи)
-- ======================

-- Запускает синхронизацию: рассылает гильдии список своих записей за
-- ATT_SYNC_DAYS дней. silent = true (автозапуск) — сообщения в чат только если
-- что-то добавилось. Возвращает true, если запрос отправлен.
function auction:StartAttendanceSync(silent)
    -- доступ (редактирование офицерской заметки) уже подразумевает членство в гильдии
    if not self:HasAttendanceAccess() then return false end
    if self.attSync and GetTime() - self.attSync.started < SYNC_MAX_SECONDS then
        if not silent then self:AttendanceSay("Attendance: синхронизация уже идёт", true) end
        return false
    end

    local cutoff = time() - self.ATT_SYNC_DAYS * 86400
    local keys = {}
    for _, rec in ipairs(self.attendance) do
        if rec.boss and rec.t >= cutoff then keys[#keys + 1] = self:AttendanceKey(rec) end
    end

    local sid = string.format("%x", math.random(0x1000, 0xFFFFF))
    local chunks = SplitUtf8(table.concat(keys, ","), CHUNK_BYTES)
    for i, chunk in ipairs(chunks) do
        self:AttQueueSend(string.format("ATT_REQ;%s;%d;%d;%s", sid, i, #chunks, chunk), "GUILD")
    end

    local now = GetTime()
    self.attSync = { sid = sid, started = now, lastActivity = now, added = 0, from = {}, bufs = {}, silent = silent }
    self:ScheduleTimer(function() self:CheckAttendanceSyncFinished() end, 10)
    if not silent then self:AttendanceSay("Attendance: запрос на синхронизацию отправлен офицерам") end
    return true
end

-- Завершает сессию, когда ответы закончились (тишина 6 сек) или вышло время;
-- иначе проверит ещё раз через 3 сек. Итог — одним сообщением в чат.
function auction:CheckAttendanceSyncFinished()
    local s = self.attSync
    if not s then return end

    local now = GetTime()
    if now - s.lastActivity < 6 and now - s.started < SYNC_MAX_SECONDS then
        self:ScheduleTimer(function() self:CheckAttendanceSyncFinished() end, 3)
        return
    end

    self.attSync = nil
    if s.added > 0 then self:AttendanceChanged() end

    local names = {}
    for name in pairs(s.from) do names[#names + 1] = name end
    table.sort(names)
    local who = table.concat(names, ", ")
    if s.added > 0 then
        self:AttendanceSay("Attendance: синхронизация завершена, добавлено записей: "..s.added.." (ответили: "..who..")")
    elseif not s.silent then
        if #names == 0 then
            self:AttendanceSay("Attendance: никто из офицеров не ответил", true)
        else
            self:AttendanceSay("Attendance: синхронизация завершена, новых записей нет (ответили: "..who..")")
        end
    end
end

-- Один раз за сессию запускает тихую синхронизацию через 25 секунд после входа
-- в мир (время нужно, чтобы подгрузились гильдия и рейд). Вызывается из HandleWorldEnter.
function auction:ScheduleAttendanceAutoSync()
    if self.attAutoSynced then return end
    self.attAutoSynced = true
    self:ScheduleTimer(function() self:StartAttendanceSync(true) end, 25)
end

-- ======================
-- Ответ (нас просят записи)
-- ======================

-- ATT_REQ от другого офицера: собираем куски списка его ключей и отвечаем.
function auction:Handle_ATT_REQ(rest, sender)
    if self.StripRealm(sender) == UnitName("player") then return end
    if not self:HasAttendanceAccess() then return end

    local sid, i, n, payload = rest:match("^([^;]*);(%d+);(%d+);(.*)$")
    i, n = tonumber(i), tonumber(n)
    if not sid or not i or not n or n < 1 or n > 20 or i < 1 or i > n then return end

    self.attReqBuf = self.attReqBuf or {}
    local key = sender..":"..sid
    local buf = self.attReqBuf[key]
    if not buf then
        buf = { parts = {}, n = n, got = 0, done = false }
        self.attReqBuf[key] = buf
        -- на случай потерянных кусков: через REQUEST_WAIT сек отвечаем по тому, что есть
        self:ScheduleTimer(function() self:RespondToAttendanceRequest(sender, sid) end, REQUEST_WAIT)
    end
    if not buf.parts[i] then
        buf.parts[i] = payload
        buf.got = buf.got + 1
    end
    if buf.got == buf.n then self:RespondToAttendanceRequest(sender, sid) end
end

-- Отправляет запросившему те записи за ATT_SYNC_DAYS дней, которых нет в его
-- списке ключей (не больше MAX_RECORDS_PER_RESPONSE, новые в приоритете),
-- затем ATT_DONE. Одному запросившему отвечаем не чаще раза в RESPOND_COOLDOWN сек.
function auction:RespondToAttendanceRequest(sender, sid)
    local key = sender..":"..sid
    local buf = self.attReqBuf and self.attReqBuf[key]
    if not buf or buf.done then return end
    buf.done = true
    self.attReqBuf[key] = nil

    self.attServed = self.attServed or {}
    local now = GetTime()
    if self.attServed[sender] and now - self.attServed[sender] < RESPOND_COOLDOWN then
        self:Debug("Attendance: "..sender.." запрашивает слишком часто, не отвечаю")
        return
    end
    self.attServed[sender] = now

    local parts = {}
    for i = 1, buf.n do parts[i] = buf.parts[i] or "" end
    local theirKeys = ParseKeys(table.concat(parts))

    local window = self.ATTENDANCE_SAME_KILL_SECONDS
    local cutoff = time() - self.ATT_SYNC_DAYS * 86400
    local missing = {}
    for i = #self.attendance, 1, -1 do
        local rec = self.attendance[i]
        if rec.t < cutoff then break end            -- список по возрастанию времени: дальше только старше
        if rec.boss then
            local hash, known = BossHash(rec.boss), false
            for _, k in ipairs(theirKeys) do
                if k.h == hash and math.abs(k.t - rec.t) <= window then known = true break end
            end
            if not known then
                missing[#missing + 1] = rec
                if #missing >= MAX_RECORDS_PER_RESPONSE then break end
            end
        end
    end

    -- отправляем от старых к новым; rid — номер записи в этом ответе
    local total = #missing
    for idx = total, 1, -1 do
        local chunks = SplitUtf8(self:SerializeAttendanceRecord(missing[idx]), CHUNK_BYTES)
        for i, chunk in ipairs(chunks) do
            self:AttQueueSend(string.format("ATT_REC;%s;%d;%d;%d;%s", sid, total - idx + 1, i, #chunks, chunk), "WHISPER", sender)
        end
    end
    self:AttQueueSend(string.format("ATT_DONE;%s;%d", sid, total), "WHISPER", sender)
end

-- ATT_REC: кусок записи от офицера, которому мы слали запрос. Склеиваем куски,
-- проверяем запись и сливаем её в историю (интерфейс обновим один раз в конце сессии).
function auction:Handle_ATT_REC(rest, sender)
    local s = self.attSync
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
        local rec = self:DeserializeAttendanceRecord(table.concat(buf.parts, "", 1, buf.n))
        if rec and self:MergeAttendanceRecord(rec, true) == "added" then
            s.added = s.added + 1
        end
    end
end

-- ATT_DONE: офицер закончил отвечать. Запоминаем, кто ответил (для итога в чате).
function auction:Handle_ATT_DONE(rest, sender)
    local s = self.attSync
    if not s then return end
    local sid, count = rest:match("^([^;]*);(%d+)$")
    if not sid or sid ~= s.sid then return end
    s.from[sender] = tonumber(count) or 0
    s.lastActivity = GetTime()
end
