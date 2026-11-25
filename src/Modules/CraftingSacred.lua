-- Experimental shared base-defence roll based on published client-protocol
-- research. The official server distribution and current behavior are unverified.
local M={}

function M.percentiles(armour,random)
	local roll=math.floor(random()*32)
	local result={}
	for _,kind in ipairs({"Armour","Evasion","EnergyShield","Ward"}) do
		local low,high=armour[kind.."BaseMin"],armour[kind.."BaseMax"]
		if low and high and high>low then
			local value=math.floor(low+(high-low)*roll/31+0.5)
			result[kind]=(value-low)/(high-low)
		end
	end
	return result
end

function M.describe(stats)
	local parts={}
	for _,field in ipairs({{"Armour","Armour"},{"Evasion","Evasion"},{"EnergyShield","Energy shield"},{"Ward","Ward"}}) do
		if stats[field[1]] and stats[field[1]]>0 then parts[#parts+1]=field[2].." "..stats[field[1]] end
	end
	return #parts>0 and table.concat(parts,", ") or "No displayed defences"
end

return M
