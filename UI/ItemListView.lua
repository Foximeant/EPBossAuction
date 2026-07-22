local ADDON_NAME, ns = ...
local AceGUI = LibStub("AceGUI-3.0")

ns.ItemListView = {}
local ItemListView = ns.ItemListView

-- Общая таблица на все строки — не аллоцируем новую при каждом Render().
-- Только заливка, без рамки (edgeFile/edgeSize убраны — теперь строки
-- разделяет только зебра, а не бордер)
local ROW_BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
}

-- Базовая яркость заливки чередующихся строк (зебра). Наведение добавляет
-- сверху ещё немного, поэтому даже "тёмная" строка при ховере отличима.
local ZEBRA_ALPHA_ODD = 0.035
local ZEBRA_ALPHA_EVEN = 0
local HOVER_ALPHA_BONUS = 0.05

local NAME_COL_WIDTH = 300

local function FormatBidderName(bid)
	local name = ns.Util:ClassColorName(bid.player, bid.class)
	return name .. (bid.offspec and " |cff888888(О)|r" or "")
end

local function GetTopBidsText(bossID, itemID)
	local sorted = ns.State:GetSortedBids(bossID, itemID)
	if #sorted == 0 then
		return "|cff888888нет ставок|r"
	end
	local parts = {}
	for i = 1, math.min(2, #sorted) do
		local b = sorted[i]
		table.insert(parts, string.format("%s: %d ЕП", FormatBidderName(b), b.amount))
	end
	return table.concat(parts, "   |   ")
end

-- container: любой AceGUI-контейнер (у нас это content-пейн TreeGroup)
-- onItemClick(bossID, item)
function ItemListView:Render(container, bossID, onItemClick)
	container:ReleaseChildren()

	local boss = ns.BossTree:GetBossByID(bossID)
	if not boss then return end

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("List")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	if #boss.items == 0 then
		local empty = AceGUI:Create("Label")
		empty:SetText("Нет предметов для этого босса")
		empty:SetFullWidth(true)
		scroll:AddChild(empty)
		return
	end

	for i, itemID in ipairs(boss.items) do
		local name, icon = ns.ItemInfo:GetDisplay(itemID)

		-- Строка — SimpleGroup с двумя колонками фиксированной ширины,
		-- а не единый текст с пробелами: так ставки у всех предметов
		-- начинаются строго с одного и того же отступа, независимо от
		-- длины названия предмета.
		local row = AceGUI:Create("SimpleGroup")
		row:SetLayout("Flow")
		row:SetFullWidth(true)
		-- Высоту не фиксируем — AceGUI сам выставит её по факту раскладки
		-- (см. SimpleGroup:LayoutFinished), в т.ч. когда колонка со ставками
		-- переносится на вторую строку при нехватке ширины

		-- Клик/наведение/тултип вешаем на сырой фрейм строки целиком,
		-- а не на дочерние Label — так вся строка кликабельна, а не только текст.
		-- Сначала чистим то, что могло остаться от прошлой жизни этого
		-- переработанного фрейма (см. Util:ResetRawInteractivity).
		ns.Util:ResetRawInteractivity(row.frame)
		row.frame:SetBackdrop(ROW_BACKDROP)

		-- Зебра: чередуем яркость заливки через строку, вместо рамки
		local baseAlpha = (i % 2 == 0) and ZEBRA_ALPHA_EVEN or ZEBRA_ALPHA_ODD
		row.frame:SetBackdropColor(1, 1, 1, baseAlpha)
		row.frame:EnableMouse(true)
		row.frame:SetScript("OnMouseUp", function()
			onItemClick(bossID, itemID)
		end)
		row.frame:SetScript("OnEnter", function(rowFrame)
			GameTooltip:SetOwner(rowFrame, "ANCHOR_LEFT")
			GameTooltip:SetHyperlink("item:" .. itemID)
			GameTooltip:Show()
			rowFrame:SetBackdropColor(1, 1, 1, baseAlpha + HOVER_ALPHA_BONUS)
		end)
		row.frame:SetScript("OnLeave", function(rowFrame)
			GameTooltip:Hide()
			rowFrame:SetBackdropColor(1, 1, 1, baseAlpha)
		end)

		local nameLabel = AceGUI:Create("Label")
		nameLabel:SetImage(icon)
		nameLabel:SetImageSize(20, 20)
		nameLabel:SetText(name)
		nameLabel:SetWidth(NAME_COL_WIDTH)
		row:AddChild(nameLabel)

		local bidsLabel = AceGUI:Create("Label")
		bidsLabel:SetText(GetTopBidsText(bossID, itemID))
		bidsLabel:SetWidth(340)
		row:AddChild(bidsLabel)

		scroll:AddChild(row)
	end
end
