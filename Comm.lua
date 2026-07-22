local ADDON_NAME, ns = ...
local addon = ns.addon
local AceSerializer = LibStub("AceSerializer-3.0")

local COMM_PREFIX = "EPBA"

-- Протокол:
--   BID            Player -> LM     WHISPER   { bossID, itemID, amount, offspec, class }
--   STATE_UPDATE   LM -> All        RAID      { bossID, bossData }  -- full snapshot по боссу
--   SYNC_REQUEST   Player -> All    RAID      {}                    -- широковещательно, отвечает только ЛМ
--   SYNC_RESPONSE  LM -> Player     WHISPER   { state, lmName }     -- весь state целиком
--   LM_ANNOUNCE    LM -> All        RAID      {}                    -- "я теперь ЛМ", sender = имя ЛМ
--   LM_CLEAR       LM -> All        RAID      {}                    -- "я больше не ЛМ", sender = имя бывшего ЛМ

local MSG_BID = "BID"
local MSG_STATE_UPDATE = "STATE_UPDATE"
local MSG_SYNC_REQUEST = "SYNC_REQUEST"
local MSG_SYNC_RESPONSE = "SYNC_RESPONSE"
local MSG_LM_ANNOUNCE = "LM_ANNOUNCE"
local MSG_LM_CLEAR = "LM_CLEAR"

ns.Comm = {}
local Comm = ns.Comm

-- Имя текущего лутмастера, известное этому клиенту. Не персистится —
-- заново узнаётся через SYNC_RESPONSE/LM_ANNOUNCE при каждом входе в группу.
Comm.masterName = nil

-- IsInRaid()/IsInGroup() — API из патча 5.0.4, недоступны в 3.3.5.
-- Используем классические счётчики, они есть в клиенте с самого начала.
local function GetGroupChannel()
	if GetNumRaidMembers() > 0 then return "RAID" end
	if GetNumPartyMembers() > 0 then return "PARTY" end
	return nil
end

function Comm:Send(msgType, payload, target)
	local channel = target and "WHISPER" or GetGroupChannel()
	if not channel then return end -- не в группе — отправлять некому

	local serialized = AceSerializer:Serialize(msgType, payload)
	addon:SendCommMessage(COMM_PREFIX, serialized, channel, target)
end

function Comm:SendBid(bossID, itemID, amount, offspec, classToken)
	if not self.masterName then
		print("|cffff0000EPBA:|r лутмастер ещё не найден, ставка сохранена локально, синхронизируется когда ЛМ отзовётся")
		self:RequestSync()
		return
	end
	self:Send(MSG_BID, { bossID = bossID, itemID = itemID, amount = amount, offspec = offspec, class = classToken }, self.masterName)
end

function Comm:BroadcastBossState(bossID)
	local bossData = addon.db.char.state[bossID]
	self:Send(MSG_STATE_UPDATE, { bossID = bossID, bossData = bossData })
end

function Comm:RequestSync()
	self:Send(MSG_SYNC_REQUEST, {})
end

function Comm:SendSyncResponse(target)
	self:Send(MSG_SYNC_RESPONSE, { state = addon.db.char.state, lmName = UnitName("player") }, target)
end

function Comm:AnnounceLM()
	self:Send(MSG_LM_ANNOUNCE, {})
end

function Comm:AnnounceLMClear()
	self:Send(MSG_LM_CLEAR, {})
end

function Comm:Init()
	addon:RegisterComm(COMM_PREFIX)
end

-- Точка входа AceComm — метод должен называться так же, как передано в
-- RegisterComm (по умолчанию "OnCommReceived"), поэтому вешаем на addon,
-- а дальше просто делегируем сюда.
function addon:OnCommReceived(prefix, message, distribution, sender)
	if prefix ~= COMM_PREFIX then return end

	local success, msgType, payload = AceSerializer:Deserialize(message)
	if not success then return end

	if msgType == MSG_BID then
		if addon:IsLootMaster() then
			ns.State:ApplyBid(payload.bossID, payload.itemID, sender, payload.amount, payload.offspec, payload.class)
			ns.Comm:BroadcastBossState(payload.bossID)
		end
	elseif msgType == MSG_STATE_UPDATE then
		ns.State:ApplyBossState(payload.bossID, payload.bossData)
	elseif msgType == MSG_SYNC_REQUEST then
		if sender == UnitName("player") then
			return -- не отвечаем сами себе на собственный broadcast
		end
		if addon:IsLootMaster() then
			ns.Comm:SendSyncResponse(sender)
		end
	elseif msgType == MSG_SYNC_RESPONSE then
		ns.Comm.masterName = payload.lmName
		ns.State:ApplyFullState(payload.state)
		if ns.UI and ns.UI.RefreshMasterStatus then
			ns.UI:RefreshMasterStatus()
		end
	elseif msgType == MSG_LM_ANNOUNCE then
		if sender == UnitName("player") then
			return -- собственное объявление, эхо не обрабатываем
		end

		ns.Comm.masterName = sender

		-- Кто-то другой назначился ЛМ, а мы сами всё ещё думаем, что ЛМ — это мы.
		-- Последний объявленный побеждает, снимаем с себя роль автоматически.
		if addon:IsLootMaster() then
			addon.db.char.isLootMaster = false
			print("|cffff0000EPBA:|r роль лутмастера теперь у " .. sender .. ", вы автоматически сняты с этой роли")
		end

		if ns.UI and ns.UI.RefreshMasterStatus then
			ns.UI:RefreshMasterStatus()
		end

		-- новый ЛМ мог начать с чистого состояния — подтянем его версию сразу
		ns.Comm:RequestSync()
	elseif msgType == MSG_LM_CLEAR then
		if sender == UnitName("player") then
			return -- собственное объявление, эхо не обрабатываем
		end

		-- Снимаем известного ЛМ, только если объявил именно он сам —
		-- иначе можно случайно затереть более свежее LM_ANNOUNCE от другого игрока
		if ns.Comm.masterName == sender then
			ns.Comm.masterName = nil
		end

		if ns.UI and ns.UI.RefreshMasterStatus then
			ns.UI:RefreshMasterStatus()
		end
	end
end
