local ADDON_NAME, ns = ...

EPBossAuction = LibStub("AceAddon-3.0"):NewAddon("EPBossAuction", "AceEvent-3.0", "AceConsole-3.0", "AceComm-3.0", "AceTimer-3.0")
local addon = EPBossAuction
ns.addon = addon

local defaults = {
	char = {
		-- state[bossID][itemID].bids[playerName] = { amount, offspec, timestamp }
		state = {},
		-- TODO: заменить на нормальную детекцию (raid lead/assist или явное назначение)
		isLootMaster = false,
	},
}

function addon:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("EPBossAuctionDB", defaults, true) -- char-scope

	self:RegisterChatCommand("epba", "SlashCommand")
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnGroupRosterUpdate")
	self:RegisterEvent("GET_ITEM_INFO_RECEIVED", "OnItemInfoReceived")

	self.wasInGroup = IsInRaid() or IsInGroup()
end

function addon:OnEnable()
	if ns.Comm then
		ns.Comm:Init()
		if self.wasInGroup then
			-- на релое/входе в аддон уже находясь в группе — тоже нужен свежий стейт
			ns.Comm:RequestSync()
		end
	end
end

-- Предмет докэшировался с сервера — перерисуем текущий вид, чтобы
-- заглушка "Предмет #ID" сменилась на нормальное имя/иконку
function addon:OnItemInfoReceived(event, itemID, success)
	if success and ns.UI and ns.UI.Refresh then
		ns.UI:Refresh()
	end
end

function addon:ToggleLootMaster()
	self.db.char.isLootMaster = not self.db.char.isLootMaster
	if self.db.char.isLootMaster then
		print("|cff00ff00EPBA:|r вы назначены лутмастером")
		if ns.Comm then
			ns.Comm.masterName = UnitName("player")
			ns.Comm:AnnounceLM()
		end
	else
		print("|cffff0000EPBA:|r вы больше не лутмастер")
		if ns.Comm then
			if ns.Comm.masterName == UnitName("player") then
				ns.Comm.masterName = nil
			end
			ns.Comm:AnnounceLMClear()
		end
	end
	if ns.UI and ns.UI.RefreshMasterStatus then
		ns.UI:RefreshMasterStatus()
	end
end

function addon:SlashCommand(input)
	input = strtrim(input or "")

	if input == "lm" then
		self:ToggleLootMaster()
		return
	end

	if ns.UI and ns.UI.Toggle then
		ns.UI:Toggle()
	end
end

-- Полная очистка ставок при выходе из группы/рейда.
-- Делается независимо на каждом клиенте (не полагаемся на broadcast от ЛМ,
-- т.к. ЛМ может вылететь без graceful disconnect).
function addon:OnGroupRosterUpdate()
	local inGroup = IsInRaid() or IsInGroup()
	if not inGroup and self.wasInGroup then
		wipe(self.db.char.state)
		if ns.UI and ns.UI.Refresh then
			ns.UI:Refresh()
		end
	elseif inGroup and not self.wasInGroup then
		if ns.Comm then
			ns.Comm:RequestSync()
		end
	end
	self.wasInGroup = inGroup
end

function addon:IsLootMaster()
	return self.db.char.isLootMaster
end
