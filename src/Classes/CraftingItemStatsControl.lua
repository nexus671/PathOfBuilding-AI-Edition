local stats=require("Modules.CraftingItemStats")
local Panel={}
function Panel.Open(goals,onKeep)
	local controls={};local anchor={"TOPLEFT",nil,"TOPLEFT"}
	controls.info=new("LabelControl"):LabelControl(anchor,{16,24,0,14},"Minimum item values. Blank fields impose no condition.")
	controls.scope=new("LabelControl"):LabelControl(anchor,{16,46,0,14},function() return controls.page:GetSelValue()=="Weapon / defence" and "Local stats, before character bonuses." or "Unconditional flat item bonuses, before character bonuses." end)
	controls.page=new("DropDownControl"):DropDownControl(anchor,{16,66,488,26},{"Weapon / defence","Life / resists / attributes"})
	if goals then
		local localGoal,flatGoal=false,false
		for i,field in ipairs(stats.fields) do if goals[field[1]]~=nil then if i<=10 then localGoal=true else flatGoal=true end end end
		if flatGoal and not localGoal then controls.page:SelByValue("Life / resists / attributes") end
	end
	for i,field in ipairs(stats.fields) do
		local index=(i-1)%10;local page=i<=10 and "Weapon / defence" or "Life / resists / attributes"
		local x=16+index%2*256;local y=100+math.floor(index/2)*54
		controls[field[1].."Label"]=new("LabelControl"):LabelControl(anchor,{x,y,0,14},field[2])
		controls[field[1]]=new("EditControl"):EditControl(anchor,{x,y+18,232,26},tostring(goals and goals[field[1]] or ""),nil,nil,16)
		controls[field[1].."Label"].shown=function() return controls.page:GetSelValue()==page end
		controls[field[1]].shown=function() return controls.page:GetSelValue()==page end
	end
	controls.keep=new("ButtonControl"):ButtonControl(anchor,{16,372,232,26},"Keep minimum stats",function()
		local ok,message=pcall(function()
			local result={}
			for _,field in ipairs(stats.fields) do local value=controls[field[1]].buf;if value~="" then result[field[1]]=assert(tonumber(value),"Enter a number for "..field[2]:lower()) end end
			if next(result) then stats.validate(result) else result=nil end
			onKeep(result);main:ClosePopup()
		end)
		if not ok then require("Modules.PlanningUI").errorPopup("Item stat goals",message) end
	end)
	controls.close=new("ButtonControl"):ButtonControl(anchor,{388,372,116,26},"Close",function() main:ClosePopup() end)
	require("Modules.PlanningUI").style(controls,{keep=true})
	main:OpenPopup(520,424,"Item stat goals",controls,nil,nil,"close")
	return controls
end
return Panel
