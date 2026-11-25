-- Configure a single observed Rog offer; no offer generation is implied.
local ui=require("Modules.PlanningUI")
local M={}
function M.Open(initial,keep,model)
	local width=math.min(620,main.screenW-40);local height=412
	local controls={};initial=initial or {}
	ui.description(controls,"intro",16,28,width-32,38,{"Enter an offer and its price as shown by Rog."},16)
	ui.label(controls,"operationLabel",16,78,"Observed offer",16)
	controls.operation=new("DropDownControl"):DropDownControl(ui.anchor,{16,100,454,26},{{label="Reroll one side",val="reroll"},{label="Add a modifier to one side",val="add"},{label="Fill empty modifier slots",val="fill"},{label="Set quality to 20%",val="set_quality"},{label="Upgrade modifier tiers by one",val="upgrade"},{label="Upgrade modifiers to highest tier",val="upgrade_highest"},{label="Remove the lowest-level modifier",val="remove_lowest"},{label="Remove the two lowest-level modifiers",val="remove_lowest_two"},{label="Reroll socket count, keep the most",val="socket_count"},{label="Reroll links, keep the longest",val="socket_links"},{label="Reroll values of one modifier",val="values_one"},{label="Reroll values on one side",val="values_side"},{label="Reroll implicit values",val="values_implicit"}})
	controls.operation:SelByValue(initial.rogOperation=="upgrade_highest_all" and "upgrade_highest" or initial.rogOperation or "reroll","val")
	ui.label(controls,"sideLabel",16,140,"Modifier side",16)
	controls.side=new("DropDownControl"):DropDownControl(ui.anchor,{16,162,250,26},{{label="Prefixes",val="Prefix"},{label="Suffixes",val="Suffix"}})
	ui.label(controls,"attemptLabel",300,140,"Attempts",16)
	controls.attempts=new("DropDownControl"):DropDownControl(ui.anchor,{300,162,170,26},{{label="1",val=1},{label="3",val=3},{label="5",val=5}})
	controls.side:SelByValue(initial.rogSide or "Prefix","val");controls.attempts:SelByValue(initial.rogAttempts or 1,"val")
	local function sideOffer() local operation=controls.operation:GetSelValueByKey("val");return operation=="reroll" or operation=="add" or operation=="values_side" end
	local function attemptOffer() local op=controls.operation:GetSelValueByKey("val");return sideOffer() or op=="values_one" or op=="values_implicit" end
	local function socketOffer() local operation=controls.operation:GetSelValueByKey("val");return operation=="socket_count" or operation=="socket_links" end
	ui.label(controls,"socketRollsLabel",16,140,"Observed rerolls",16)
	controls.socketRolls=new("DropDownControl"):DropDownControl(ui.anchor,{16,162,180,26},{{label="10",val=10},{label="20",val=20},{label="30",val=30},{label="50",val=50},{label="100",val=100}})
	controls.socketRolls:SelByValue(initial.rogSocketRolls or 10,"val")
	controls.socketRollsLabel.shown=socketOffer;controls.socketRolls.shown=socketOffer
	ui.description(controls,"socketHint",212,145,width-228,42,{"Uses estimated socket odds; first tied result is kept."},14)
	controls.socketHint.shown=socketOffer
	for _,key in ipairs({"sideLabel","side"}) do controls[key].shown=sideOffer end
	for _,key in ipairs({"attemptLabel","attempts"}) do controls[key].shown=attemptOffer end
	ui.label(controls,"upgradeCountLabel",16,140,"Modifiers to upgrade",16)
	controls.upgradeCount=new("DropDownControl"):DropDownControl(ui.anchor,{16,162,180,26},{{label="1",val=1},{label="2",val=2},{label="3",val=3},{label="4",val=4},{label="5",val=5},{label="6",val=6}})
	controls.upgradeCount:SelByValue(initial.count or 1,"val")
	controls.highestCount=new("DropDownControl"):DropDownControl(ui.anchor,{16,162,180,26},{{label="1",val=1},{label="2",val=2},{label="All",val=0}})
	controls.highestCount:SelByValue(initial.rogOperation=="upgrade_highest_all" and 0 or initial.count or 1,"val")
	controls.highestCount.shown=function() return controls.operation:GetSelValueByKey("val")=="upgrade_highest" end
	controls.upgradeCountLabel.shown=function() local op=controls.operation:GetSelValueByKey("val");return op=="upgrade" or op=="upgrade_highest" end
	ui.description(controls,"highestHint",215,145,width-231,45,{"Experimental: highest legal tier; game rules unverified."},14)
	controls.highestHint.shown=controls.highestCount.shown
	ui.description(controls,"upgradeHint",215,145,width-231,45,{"Experimental: unique adjacent tiers only; game rules unverified."},14)
	for _,key in ipairs({"upgradeCount","upgradeHint"}) do controls[key].shown=function() return controls.operation:GetSelValueByKey("val")=="upgrade" end end
	ui.description(controls,"removeHint",16,145,width-32,40,{"If modifier levels are tied, this preview assumes equal selection chances."},14)
	controls.removeHint.shown=function() local operation=controls.operation:GetSelValueByKey("val");return operation=="remove_lowest" or operation=="remove_lowest_two" end
	ui.description(controls,"fillHint",16,145,width-32,40,{"The preview fills slots sequentially using estimated modifier weights."},14)
	controls.fillHint.shown=function() return controls.operation:GetSelValueByKey("val")=="fill" end
	ui.description(controls,"qualityHint",16,145,width-32,40,{"Sets weapon or armour quality to 20%; offer eligibility is unverified."},14)
	controls.qualityHint.shown=function() return controls.operation:GetSelValueByKey("val")=="set_quality" end
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
	ui.description(controls,"limits",16,315,width-32,32,{"Offer availability, ranking and model odds are unverified."},14)
	local function jewelWarning() return require("Modules.CraftingRog").jewelOfferWarning(model,{rogOperation=controls.operation:GetSelValueByKey("val")}) end
	controls.limits.shown=function() local op=controls.operation:GetSelValueByKey("val");return not jewelWarning() and op~="values_one" and op~="values_side" and op~="values_implicit" end
	ui.description(controls,"valueHint",16,315,width-32,38,{"Best ranks numeric rolls, which may not match your preference. Odds and offer rules are unverified."},14)
	controls.valueHint.shown=function() local op=controls.operation:GetSelValueByKey("val");return not jewelWarning() and (op=="values_one" or op=="values_side" or op=="values_implicit") end
	ui.description(controls,"jewelHint",16,315,width-32,38,{"Not listed for jewels in 3.15.2; check the observed offer. Current availability is unverified."},14)
	local function jewelValueOffer() local op=controls.operation:GetSelValueByKey("val");return jewelWarning() and (op=="values_one" or op=="values_implicit") end
	controls.jewelHint.shown=function() return jewelWarning()~=nil and not jewelValueOffer() end
	ui.description(controls,"jewelValueHint",16,315,width-32,38,{"Not listed for jewels in 3.15.2; availability is unverified. Best ranks numeric rolls, not preferences."},14)
	controls.jewelValueHint.shown=function() return not not jewelValueOffer() end
	controls.keep=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{16,height-44,180,28},"Use observed offer",function()
		local ok,err=pcall(function()
		local operation=controls.operation:GetSelValueByKey("val");local craft={method="rog_reroll"};local cost={};local any=false
		if sideOffer() then craft.rogSide=controls.side:GetSelValueByKey("val") end
		if attemptOffer() then craft.rogAttempts=controls.attempts:GetSelValueByKey("val") end
		if operation~="reroll" then craft.rogOperation=operation end
		if operation=="upgrade" then craft.count=controls.upgradeCount:GetSelValueByKey("val") elseif operation=="upgrade_highest" then local count=controls.highestCount:GetSelValueByKey("val");if count==0 then craft.rogOperation="upgrade_highest_all" else craft.count=count end end
		if socketOffer() then craft.rogSocketRolls=controls.socketRolls:GetSelValueByKey("val") end
		for _,tier in ipairs({"lesser","greater","grand","exceptional"}) do
			local value=controls[tier].buf:match("^%s*(.-)%s*$")
			if value~="" then assert(value:match("^%d+$"),"Enter whole artifact quantities");cost[tier]=tonumber(value);any=true end
		end
		if any then craft.artifactCost=cost end
		require("Modules.CraftingRog").validate(craft);keep(craft);main:ClosePopup()
		end)
		if not ok then ui.errorPopup("Rog offer",err) end
	end),"primary")
	controls.close=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{width-132,height-44,116,28},"Cancel",function() main:ClosePopup() end))
	ui.style(controls,{keep=true});for _,control in pairs(controls) do control.layoutAudit="rog-offer" end
	main:OpenPopup(width,height,"Rog: observed offer",controls,nil,nil,"close")
	return controls
end
return M
