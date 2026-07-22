local ADDON_NAME, ns = ...
local AceGUI = LibStub("AceGUI-3.0")

ns.BidDetailView = {}
local BidDetailView = ns.BidDetailView

-- Общие таблицы на все строки — не аллоцируем новые при каждом Render()
local ROW_BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Buttons\\WHITE8x8",
	edgeSize = 1,
}
-- Черновик несохранённого ввода — переживает пересборку Render(), которая
-- происходит при КАЖДОЙ чужой ставке (см. State:ApplyBid -> UI:Refresh()).
-- Без этого напечатанный текст стирался, стоило кому-то поставить раньше вас.
local draftKey, draftText, draftOffspec

local ROW_HEIGHT = 24
local RANK_COL_WIDTH = 34
local NAME_COL_WIDTH = 260

-- container: content-пейн TreeGroup
-- itemID: числовой ID предмета (имя/иконка тянутся через ItemInfo)
-- onBack(): вернуться к ItemListView
function BidDetailView:Render(container, bossID, itemID, onBack)
	container:ReleaseChildren()

	local key = tostring(bossID) .. ":" .. tostring(itemID)

	-- ВАЖНО: content-пейн TreeGroup настроен на Fill-layout (ожидает ровно
	-- одного ребёнка). Поэтому все секции кладём в один wrapper со своим
	-- List-layout, а не добавляем их напрямую в container.
	local wrapper = AceGUI:Create("SimpleGroup")
	ns.Util:ResetRawInteractivity(wrapper.frame)
	wrapper:SetLayout("List")
	wrapper:SetFullWidth(true)
	wrapper:SetFullHeight(true)
	container:AddChild(wrapper)

	-- Верхняя строка: назад / иконка+название
	local topRow = AceGUI:Create("SimpleGroup")
	ns.Util:ResetRawInteractivity(topRow.frame)
	topRow:SetLayout("Flow")
	topRow:SetFullWidth(true)
	wrapper:AddChild(topRow)

	local backBtn = AceGUI:Create("Button")
	backBtn:SetText("< Назад")
	backBtn:SetWidth(90)
	backBtn:SetCallback("OnClick", onBack)
	topRow:AddChild(backBtn)

	local itemName, itemIcon = ns.ItemInfo:GetDisplay(itemID)

	local headingIcon = AceGUI:Create("Icon")
	headingIcon:SetImage(itemIcon)
	headingIcon:SetImageSize(24, 24)
	headingIcon:SetWidth(30)
	topRow:AddChild(headingIcon)

	local heading = AceGUI:Create("Label")
	heading:SetText(itemName)
	heading:SetFontObject(GameFontNormalLarge)
	heading:SetWidth(280)
	topRow:AddChild(heading)

	-- Таблица ставок: место, ник (окрашен по классу, офф-спек тегом), ЕП
	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("List")
	scroll:SetFullWidth(true)
	scroll:SetHeight(220)
	wrapper:AddChild(scroll)

	local sorted = ns.State:GetSortedBids(bossID, itemID)
	if #sorted == 0 then
		local empty = AceGUI:Create("Label")
		empty:SetText("|cff888888Пока никто не поставил|r")
		empty:SetFullWidth(true)
		scroll:AddChild(empty)
	else
		for i, b in ipairs(sorted) do
			local row = AceGUI:Create("SimpleGroup")
			ns.Util:ResetRawInteractivity(row.frame)
			row:SetLayout("Flow")
			row:SetFullWidth(true)
			row:SetHeight(ROW_HEIGHT)

			row.frame:SetBackdrop(ROW_BACKDROP)
			-- Первое место — лёгкая золотая подложка, остальные строки чередуем
			-- по яркости, чтобы таблица не сливалась в сплошной текст
			if i == 1 then
				row.frame:SetBackdropColor(0.6, 0.5, 0.1, 0.18)
				row.frame:SetBackdropBorderColor(1, 0.82, 0, 0.4)
			else
				row.frame:SetBackdropColor(1, 1, 1, (i % 2 == 0) and 0.03 or 0)
				row.frame:SetBackdropBorderColor(1, 1, 1, 0.12)
			end

			local rankLabel = AceGUI:Create("Label")
			rankLabel:SetText((i == 1) and "|cffffd100#1|r" or ("#" .. i))
			rankLabel:SetWidth(RANK_COL_WIDTH)
			row:AddChild(rankLabel)

			local nameLabel = AceGUI:Create("Label")
			local coloredName = ns.Util:ClassColorName(b.player, b.class)
			local suffix = b.offspec and " |cff888888(офф-спек)|r" or ""
			nameLabel:SetText(coloredName .. suffix)
			nameLabel:SetWidth(NAME_COL_WIDTH)
			row:AddChild(nameLabel)

			local amountLabel = AceGUI:Create("Label")
			amountLabel:SetText(string.format("|cffffffff%d|r ЕП", b.amount))
			amountLabel:SetWidth(120)
			row:AddChild(amountLabel)

			scroll:AddChild(row)
		end
	end

	-- Ввод ставки
	local bottomRow = AceGUI:Create("SimpleGroup")
	ns.Util:ResetRawInteractivity(bottomRow.frame)
	bottomRow:SetLayout("Flow")
	bottomRow:SetFullWidth(true)
	wrapper:AddChild(bottomRow)

	local edit = AceGUI:Create("EditBox")
	edit:SetLabel("Ставка (ЕП)")
	edit:SetWidth(150)
	-- Сырой Blizzard EditBox под капотом AceGUI — SetNumeric режет ввод
	-- до цифр, не даёт напечатать буквы/спецсимволы
	edit.editbox:SetNumeric(true)
	bottomRow:AddChild(edit)

	local offspecCheck = AceGUI:Create("CheckBox")
	offspecCheck:SetLabel("Офф-спек")
	offspecCheck:SetWidth(150)
	bottomRow:AddChild(offspecCheck)

	-- Восстанавливаем то, что человек уже успел напечатать/выбрать для
	-- ЭТОГО предмета до того, как пришла чужая ставка и пересобрала вид
	if draftKey == key then
		if draftText and draftText ~= "" then
			edit:SetText(draftText)
			edit.editbox:SetCursorPosition(#draftText)
		end
		if draftOffspec then
			offspecCheck:SetValue(true)
		end
	end

	-- Ваш ЕП (из гильдейского аддона EPGP) — справочно, под вводом ставки.
	-- При офф-спеке показываем половину: ставки в офф-спек обычно вдвое
	-- дешевле по местным правилам, но ставим реальную сумму сам игрок —
	-- это только подсказка, сколько разумно поставить.
	local epRow = AceGUI:Create("SimpleGroup")
	ns.Util:ResetRawInteractivity(epRow.frame)
	epRow:SetLayout("Flow")
	epRow:SetFullWidth(true)
	wrapper:AddChild(epRow)

	local epLabel = AceGUI:Create("Label")
	epLabel:SetFullWidth(true)
	epRow:AddChild(epLabel)

	local function GetMaxAllowedBid()
		local ep = ns.EPGPBridge:GetPlayerEP(UnitName("player"))
		if not ep then
			return nil -- не знаем ЕП — не ограничиваем
		end
		return offspecCheck:GetValue() and math.floor(ep / 2) or ep
	end

	local function RefreshEPLabel()
		local ep = ns.EPGPBridge:GetPlayerEP(UnitName("player"))
		if not ep then
			epLabel:SetText("|cff888888ЕПГП: аддон EPGP не найден или нет данных по вам|r")
			return
		end
		if offspecCheck:GetValue() then
			epLabel:SetText(string.format(
				"Ваш ЕП: |cffffffff%d|r   (для офф-спека: |cffffd100%d|r)",
				ep, math.floor(ep / 2)
			))
		else
			epLabel:SetText(string.format("Ваш ЕП: |cffffffff%d|r", ep))
		end
	end

	-- Живая проверка при вводе: если сумма больше доступного ЕП — красим
	-- поле красным. Возвращает true, если текущий ввод допустим (в т.ч.
	-- когда ЕП неизвестен и мы никого не ограничиваем).
	local function ValidateBidAmount()
		local amount = tonumber(edit:GetText())
		local maxAllowed = GetMaxAllowedBid()
		if amount and maxAllowed and amount > maxAllowed then
			edit.editbox:SetTextColor(1, 0.15, 0.15)
			return false
		end
		edit.editbox:SetTextColor(1, 1, 1)
		return true
	end

	local function SaveDraft()
		draftKey = key
		draftText = edit:GetText()
		draftOffspec = offspecCheck:GetValue()
	end

	edit:SetCallback("OnTextChanged", function()
		SaveDraft()
		ValidateBidAmount()
	end)
	offspecCheck:SetCallback("OnValueChanged", function()
		SaveDraft()
		RefreshEPLabel()
		ValidateBidAmount()
	end)
	RefreshEPLabel()
	ValidateBidAmount()

	-- AceGUI EditBox сам добавляет "OK" в поле ввода — отдельная кнопка не нужна
	edit:SetCallback("OnEnterPressed", function(widget, event, text)
		local amount = tonumber(text)
		if not amount then
			print("|cffff0000EPBA:|r ставка должна быть числом")
			return
		end
		local maxAllowed = GetMaxAllowedBid()
		if maxAllowed and amount > maxAllowed then
			print(string.format("|cffff0000EPBA:|r ставка %d превышает доступный ЕП (%d)", amount, maxAllowed))
			ValidateBidAmount()
			return
		end
		ns.State:PlaceBid(bossID, itemID, amount, offspecCheck:GetValue())
		-- Ставка ушла — черновик для этого предмета больше не актуален,
		-- иначе следующая пересборка вида (в т.ч. от нашей же ставки) снова
		-- подставит только что отправленный текст обратно в поле
		if draftKey == key then
			draftKey, draftText, draftOffspec = nil, nil, nil
		end
		BidDetailView:Render(container, bossID, itemID, onBack)
	end)
end
