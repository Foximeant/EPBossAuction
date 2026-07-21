local ADDON_NAME, ns = ...

ns.EPGPBridge = {}
local EPGPBridge = ns.EPGPBridge

-- Мост к внешнему гильдейскому аддону EPGP (хранит ЕП/ГП в офицерских
-- заметках). EPBossAuction сам ничего не считает и не хранит — только
-- читает чужие данные через его публичное API:
--   EPGP:GetEPGP(name) -> ep, gp, main

function EPGPBridge:IsAvailable()
	return _G.EPGP ~= nil and type(_G.EPGP.GetEPGP) == "function"
end

-- Возвращает ep (число) или nil, если аддон EPGP не установлен, ещё не
-- загрузил ростер гильдии, либо не нашёл такого игрока (алт с другим
-- именем при отсутствии офицерской заметки и т.п.)
function EPGPBridge:GetPlayerEP(name)
	if not self:IsAvailable() then
		return nil
	end
	local ok, ep = pcall(function() return _G.EPGP:GetEPGP(name) end)
	if not ok or type(ep) ~= "number" then
		return nil
	end
	return ep
end
