local ADDON_NAME, ns = ...
local AceGUI = LibStub("AceGUI-3.0")

ns.UI = {}
local UI = ns.UI

local frame, treeGroup, lmButton
local currentBossID, currentItemID, currentView -- currentView: "list" | "detail" | nil
local resizeTimer

local function ShowItemList(bossID)
	currentBossID = bossID
	currentItemID = nil
	currentView = "list"
	ns.ItemListView:Render(treeGroup, bossID, function(clickedBossID, itemID)
		currentBossID = clickedBossID
		currentItemID = itemID
		currentView = "detail"
		ns.BidDetailView:Render(treeGroup, clickedBossID, itemID, function()
			ShowItemList(clickedBossID)
		end)
	end)
end

local function GetMasterStatusText()
	if ns.addon:IsLootMaster() then
		return "Вы — лутмастер"
	elseif ns.Comm and ns.Comm.masterName then
		return "ЛМ: " .. ns.Comm.masterName
	end
	return "ЛМ: не определён"
end

-- Вызывается из Core.lua/Comm.lua при любом изменении роли/известного ЛМ
function UI:RefreshMasterStatus()
	if not frame then return end
	frame:SetStatusText(GetMasterStatusText())
	if lmButton then
		lmButton:SetText(ns.addon:IsLootMaster() and "Снять роль ЛМ" or "Стать ЛМ")
	end
end

function UI:Create()
	frame = AceGUI:Create("Frame")
	frame:SetTitle("EP Boss Auction")
	frame:SetLayout("Fill")
	frame:SetWidth(720)
	frame:SetHeight(520)
	frame:SetCallback("OnClose", function(widget)
		AceGUI:Release(widget)
		frame = nil
		if resizeTimer then
			ns.addon:CancelTimer(resizeTimer)
			resizeTimer = nil
		end
	end)
	-- Убираем прозрачность фона (по умолчанию AceGUI Frame полупрозрачный)
	frame.frame:SetBackdropColor(0.05, 0.05, 0.05, 1)

	-- Разумный минимум, чтобы колонки в таблице не сжимались до абсурда
	-- (у AceGUI Frame и так есть дефолт 400x200, но он слишком мал под нашу таблицу)
	frame.frame:SetMinResize(560, 320)

	-- У AceGUI SimpleGroup при изменении ширины родителем НЕ пересчитывается
	-- внутренний Flow-layout (только обновляется content.width, раскладка
	-- остаётся старой) — из-за этого при сужении окна перенесённый текст
	-- ставок наезжал на нижнюю границу строки. Просто перерисовываем текущий
	-- вид заново после ресайза — с небольшой задержкой, чтобы не дёргать
	-- перерисовку на каждый пиксель во время перетаскивания угла окна.
	frame.frame:HookScript("OnSizeChanged", function()
		if resizeTimer then
			ns.addon:CancelTimer(resizeTimer)
		end
		resizeTimer = ns.addon:ScheduleTimer(function()
			resizeTimer = nil
			UI:Refresh()
		end, 0.15)
	end)

	-- Frame:SetLayout("Fill") ждёт РОВНО одного ребёнка, поэтому кладём
	-- туда одну обёртку с Flow-раскладкой: верхняя панель фиксированной
	-- высоты (кнопка ЛМ) + дерево боссов ниже на всю оставшуюся высоту
	-- (Flow поддерживает child:SetFullHeight(true) как раз для этого).
	-- Кнопка — обычный AceGUI Button, а не сырой CreateFrame: так её
	-- подхватывают скины интерфейса (ElvUI и подобные), которые смотрят
	-- именно на AceGUI-виджеты.
	local wrapper = AceGUI:Create("SimpleGroup")
	wrapper:SetLayout("Flow")
	wrapper:SetFullWidth(true)
	wrapper:SetFullHeight(true)
	frame:AddChild(wrapper)

	local topBar = AceGUI:Create("SimpleGroup")
	topBar:SetLayout("Flow")
	topBar:SetFullWidth(true)
	topBar:SetHeight(30)
	wrapper:AddChild(topBar)

	lmButton = AceGUI:Create("Button")
	lmButton:SetWidth(150)
	lmButton:SetCallback("OnClick", function()
		ns.addon:ToggleLootMaster()
	end)
	topBar:AddChild(lmButton)

	treeGroup = AceGUI:Create("TreeGroup")
	treeGroup:SetLayout("Fill")
	treeGroup:SetFullWidth(true)
	treeGroup:SetFullHeight(true)
	treeGroup:SetTree(ns.BossTree:Build())
	-- AceGUI TreeGroup отдаёт составной путь через \001 для вложенных узлов —
	-- нам нужен только последний сегмент (id босса), клик по инстансу (родителю) игнорируем
	treeGroup:SetCallback("OnGroupSelected", function(widget, event, uniquevalue)
		local bossID = uniquevalue:match("([^\001]+)$")
		if ns.BossTree:GetBossByID(bossID) then
			ShowItemList(bossID)
		end
	end)
	wrapper:AddChild(treeGroup)

	UI:RefreshMasterStatus()
end

function UI:Toggle()
	if frame then
		AceGUI:Release(frame)
		frame = nil
		if resizeTimer then
			ns.addon:CancelTimer(resizeTimer)
			resizeTimer = nil
		end
	else
		UI:Create()
	end
end

function UI:Refresh()
	if frame then
		if currentView == "detail" and currentBossID and currentItemID then
			ns.BidDetailView:Render(treeGroup, currentBossID, currentItemID, function()
				ShowItemList(currentBossID)
			end)
		elseif currentView == "list" and currentBossID then
			ShowItemList(currentBossID)
		end
	end
	UI:RefreshMasterStatus()
end
