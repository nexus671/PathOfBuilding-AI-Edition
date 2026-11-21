-- Configure a single observed Rog offer; no offer generation is implied.
local ui=require("Modules.PlanningUI")
local M={}
function M.Open(initial,keep)
	local width=math.min(620,main.screenW-40);local height=412
	local controls={};initial=initial or {}
	ui.description(controls,"intro",16,28,width-32,38,{"Enter an offer and its price as shown by Rog. The outcome is an estimate."},16)
	ui.label(controls,"operationLabel",16,78,"Observed offer",16)
	controls.operation=new("DropDownControl"):DropDownControl(ui.anchor,{16,100,454,26},{{label="Reroll one side",val="reroll"},{label="Add a modifier to one side",val="add"},{label="Remove the lowest-level modifier",val="remove_lowest"},{label="Remove the two lowest-level modifiers",val="remove_lowest_two"}})
	controls.operation:SelByValue(initial.rogOperation or "reroll","val")
	ui.label(controls,"sideLabel",16,140,"Modifier side",16)
	controls.side=new("DropDownControl"):DropDownControl(ui.anchor,{16,162,250,26},{{label="Prefixes",val="Prefix"},{label="Suffixes",val="Suffix"}})
	ui.label(controls,"attemptLabel",300,140,"Attempts",16)
	controls.attempts=new("DropDownControl"):DropDownControl(ui.anchor,{300,162,170,26},{{label="1",val=1},{label="3",val=3},{label="5",val=5}})
	controls.side:SelByValue(initial.rogSide or "Prefix","val");controls.attempts:SelByValue(initial.rogAttempts or 1,"val")
	local function sideOffer() local operation=controls.operation:GetSelValueByKey("val");return operation=="reroll" or operation=="add" end
	for _,key in ipairs({"sideLabel","side","attemptLabel","attempts"}) do controls[key].shown=sideOffer end
	ui.description(controls,"removeHint",16,145,width-32,40,{"If modifier levels are tied, this preview assumes equal selection chances."},14)
	controls.removeHint.shown=function() return not sideOffer() end
	ui.description(controls,"costHint",16,201,width-32,40,{"Order Artifacts: leave every field blank if the price is unknown. Enter 0 for a known free tier."},14)
	for index,tier in ipairs({"lesser","greater","grand","exceptional"}) do
		local x=16+(index-1)*145
		ui.label(controls,tier.."Label",x,250,tier:gsub("^%l",string.upper),14)
		local iconPath=select(2,require("Modules.CraftingPrices").describe("Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction3_"..index))
		if iconPath then
			local icon=NewImageHandle();icon:Load(iconPath);local label=controls[tier.."Label"];local draw=label.Draw
			function label:Draw(viewport) draw(self,viewport);local ix,iy=self:GetPos();SetDrawColor(1,1,1);DrawImage(icon,ix+95,iy-3,20,20) end
		end
		controls[tier]=new("EditControl"):EditControl(ui.anchor,{x,273,125,26},initial.artifactCost and tostring(initial.artifactCost[tier] or 0) or "",nil,nil,10)
	end
	ui.description(controls,"limits",16,315,width-32,32,{"Rog's exact offer rules and selection odds are unverified."},14)
	controls.keep=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{16,height-44,180,28},"Use observed offer",function()
		local ok,err=pcall(function()
		local operation=controls.operation:GetSelValueByKey("val");local craft={method="rog_reroll"};local cost={};local any=false
		if sideOffer() then craft.rogSide=controls.side:GetSelValueByKey("val");craft.rogAttempts=controls.attempts:GetSelValueByKey("val") end
		if operation~="reroll" then craft.rogOperation=operation end
		for _,tier in ipairs({"lesser","greater","grand","exceptional"}) do
			local value=controls[tier].buf:match("^%s*(.-)%s*$")
			if value~="" then assert(value:match("^%d+$"),"Enter whole artifact quantities");cost[tier]=tonumber(value);any=true end
		end
		if any then craft.artifactCost=cost end
		require("Modules.CraftingRog").validate(craft);keep(craft);main:ClosePopup()
		end)
		if not ok then main:OpenMessagePopup("Rog offer",ui.errorText(err)) end
	end),"primary")
	controls.close=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{width-132,height-44,116,28},"Cancel",function() main:ClosePopup() end))
	ui.style(controls,{keep=true});for _,control in pairs(controls) do control.layoutAudit="rog-offer" end
	main:OpenPopup(width,height,"Rog: observed offer",controls,nil,nil,"close")
	return controls
end
return M
