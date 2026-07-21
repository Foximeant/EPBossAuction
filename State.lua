local ADDON_NAME, ns = ...

ns.State = {}
local State = ns.State

function State:GetItemBids(bossID, itemID)
	local addon = ns.addon
	local bossState = addon.db.char.state[bossID]
	if not bossState then return {} end
	local itemState = bossState[itemID]
	if not itemState then return {} end
	return itemState.bids or {}
end

-- Применение ставки (своей или чужой, пришедшей с сети). Не шлёт ничего по сети сама.
function State:ApplyBid(bossID, itemID, playerName, amount, offspec, classToken)
	local addon = ns.addon
	addon.db.char.state[bossID] = addon.db.char.state[bossID] or {}
	addon.db.char.state[bossID][itemID] = addon.db.char.state[bossID][itemID] or { bids = {} }
	addon.db.char.state[bossID][itemID].bids[playerName] = {
		amount = amount,
		offspec = offspec,
		class = classToken,
		timestamp = time(),
	}
	if ns.UI and ns.UI.Refresh then
		ns.UI:Refresh()
	end
end

-- Ставка от локального игрока: применяем сразу для отзывчивости UI,
-- затем либо broadcast'им (если мы ЛМ), либо шлём ЛМ на валидацию/учёт.
function State:PlaceBid(bossID, itemID, amount, offspec)
	local addon = ns.addon
	local playerName = UnitName("player")
	local _, classToken = UnitClass("player")
	self:ApplyBid(bossID, itemID, playerName, amount, offspec, classToken)

	if addon:IsLootMaster() then
		if ns.Comm then
			ns.Comm:BroadcastBossState(bossID)
		end
	else
		if ns.Comm then
			ns.Comm:SendBid(bossID, itemID, amount, offspec, classToken)
		end
	end
end

-- Full snapshot по одному боссу, пришедший от ЛМ (STATE_UPDATE)
function State:ApplyBossState(bossID, bossData)
	local addon = ns.addon
	addon.db.char.state[bossID] = bossData
	if ns.UI and ns.UI.Refresh then
		ns.UI:Refresh()
	end
end

-- Полный state целиком, пришедший от ЛМ (SYNC_RESPONSE при входе в группу/релоге)
function State:ApplyFullState(state)
	local addon = ns.addon
	addon.db.char.state = state or {}
	if ns.UI and ns.UI.Refresh then
		ns.UI:Refresh()
	end
end

function State:GetSortedBids(bossID, itemID)
	local bids = self:GetItemBids(bossID, itemID)
	local sorted = {}
	for player, data in pairs(bids) do
		table.insert(sorted, {
			player = player,
			amount = data.amount,
			offspec = data.offspec,
			class = data.class,
			timestamp = data.timestamp,
		})
	end
	table.sort(sorted, function(a, b) return a.amount > b.amount end)
	return sorted
end
