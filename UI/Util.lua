local ADDON_NAME, ns = ...

ns.Util = {}
local Util = ns.Util

-- Оборачивает имя в цвет класса (WoW classToken, напр. "PRIEST").
-- Если класс неизвестен (старые ставки до этого патча, ошибка сети и т.п.) —
-- возвращает имя как есть, без окраски.
function Util:ClassColorName(name, classToken)
	local color = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
	if color then
		return "|c" .. color.colorStr .. name .. "|r"
	end
	return name
end

-- AceGUI переиспользует один и тот же Blizzard-фрейм под РАЗНЫЕ виджеты одного
-- типа из пула (OnAcquire у SimpleGroup сбрасывает только ширину/высоту,
-- OnRelease вообще пустой). Если мы вешаем сырые EnableMouse/SetScript на
-- frame конкретного экземпляра (как делаем для кликабельных строк таблиц),
-- они остаются висеть НАВСЕГДА и могут сработать на совершенно другом
-- виджете при следующем переиспользовании этого фрейма из пула.
-- Поэтому перед тем как решать, нужна ли конкретному SimpleGroup
-- интерактивность, всегда сбрасываем прошлое состояние дочиста.
function Util:ResetRawInteractivity(frame)
	frame:EnableMouse(false)
	frame:SetScript("OnMouseUp", nil)
	frame:SetScript("OnEnter", nil)
	frame:SetScript("OnLeave", nil)
end
