local ADDON_NAME, ns = ...

ns.ItemInfo = {}
local ItemInfo = ns.ItemInfo

local FALLBACK_ICON = "Interface\\ICONS\\INV_Misc_QuestionMark"

-- Возвращает name, icon, link. Если клиент ещё не закэшировал предмет,
-- отдаёт заглушку — сервер подтянет данные, и Core.lua обновит UI по
-- событию GET_ITEM_INFO_RECEIVED.
function ItemInfo:GetDisplay(itemID)
	local name, link, quality, ilvl, minLevel, itemType, itemSubType, stackCount, equipLoc, icon = GetItemInfo(itemID)
	if name then
		return name, icon or FALLBACK_ICON, link
	end
	return "Предмет #" .. itemID, FALLBACK_ICON, nil
end
