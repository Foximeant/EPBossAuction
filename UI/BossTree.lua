local ADDON_NAME, ns = ...

ns.BossTree = {}
local BossTree = ns.BossTree

function BossTree:Build()
	local tree = {}
	for _, instance in ipairs(ns.BossData) do
		local node = {
			value = instance.instance,
			text = instance.instance,
			children = {},
		}
		for _, boss in ipairs(instance.bosses) do
			table.insert(node.children, {
				value = boss.id,
				text = boss.name,
			})
		end
		table.insert(tree, node)
	end
	return tree
end

function BossTree:GetBossByID(bossID)
	for _, instance in ipairs(ns.BossData) do
		for _, boss in ipairs(instance.bosses) do
			if boss.id == bossID then
				return boss
			end
		end
	end
end
