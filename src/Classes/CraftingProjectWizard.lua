-- Guided project creation with item previews and a fixed footer on small screens.
local ui=require("Modules.PlanningUI")
local projects=require("Modules.CraftingProjects")
local M={}
function M.Open(build,source,initialItem,initialSlot,layout,preview,onKeep)
	local draft=source and copyTable(source) or {id="craft-"..require("sha1")(tostring({})..os.time()):sub(1,16),title="New crafting plan",slot=initialSlot or "Helmet",startingItem=initialItem or "",goals={},steps={}}
	local c={};local w,h=math.min(880,main.screenW-40),math.min(644,main.screenH-48);local col=math.floor((w-48)/2)
	local function edit(key,x,y,width,height,value,limit)
		c[key]=new("EditControl"):EditControl(ui.anchor,{x,y,width,height},value or "",nil,height>28 and "^%C\t\n" or nil,limit,nil,height>28 and 16 or nil)
		c[key].changeFunc=function() ui.draft(build,"crafting") end
	end
	local function button(key,x,y,width,label,run) c[key]=new("ButtonControl"):ButtonControl(ui.anchor,{x,y,width,28},label,run) end
	local names={};for slot in pairsSortByKey(build.itemsTab.slots) do names[#names+1]=slot end
	c.wizardPage=new("DropDownControl"):DropDownControl(ui.anchor,{16,24,200,26},{"Starting item","Target","Method & budget","Review"})
	ui.tabs(c,c.wizardPage,{{"wizardItem","Starting item","1. Item"},{"wizardTarget","Target","2. Target"},{"wizardPlan","Method & budget","3. Plan"},{"wizardReview","Review","4. Review"}},16,24,w-32)
	ui.label(c,"titleLabel",16,70,"Project name");edit("title",16,94,col,28,draft.title,120)
	c.slot=new("DropDownControl"):DropDownControl(ui.anchor,{col+32,94,col,28},names);c.slot:SelByValue(draft.slot)
	c.slot.selFunc=function() ui.draft(build,"crafting") end
	ui.label(c,"slotLabel",col+32,70,"Equipment slot")
	ui.label(c,"startingLabel",16,138,"Paste your starting item");edit("starting",16,164,col,148,draft.startingItem,24000)
	button("pasteStarting",16,326,math.floor((col-8)/2),"Paste item",function() c.starting:SetText(Paste());if c.starting.changeFunc then c.starting.changeFunc() end end)
	local function equippedItem() local slot=build.itemsTab.slots[c.slot:GetSelValue()];return slot and build.itemsTab.items[slot.selItemId] end
	button("useEquipped",24+math.floor((col-8)/2),326,math.floor((col-8)/2),"Use equipped",function() local item=assert(equippedItem(),"This equipment slot is empty");c.starting:SetText(item.raw);c.starting.changeFunc() end)
	c.useEquipped.enabled=function() return equippedItem()~=nil end
	c.useEquipped.tooltipText=function() return equippedItem() and "Copy the equipped item into this crafting plan." or "Equip an item in the selected slot, or paste a starting item." end
	local beforeBlank,blankSnapshot
	button("blankStarting",16,368,math.floor((col-8)/2),"Use blank base",function()
		local ok,base=pcall(projects.blankBase,c.starting.buf)
		if not ok then ui.errorPopup("Blank starting base",base);return end
		beforeBlank=c.starting.buf;blankSnapshot=base;c.starting:SetText(base);c.starting.changeFunc()
	end)
	c.blankStarting.enabled=function() return c.starting.buf:match("%S")~=nil and c.starting.buf~=blankSnapshot end
	c.blankStarting.tooltipText="Make a hypothetical normal base at the same item level.\nReview its implicit, sockets and quality; your target stays unchanged."
	button("undoBlank",24+math.floor((col-8)/2),368,math.floor((col-8)/2),"Undo blank base",function()
		if beforeBlank and c.starting.buf==blankSnapshot then local original=beforeBlank;beforeBlank=nil;blankSnapshot=nil;c.starting:SetText(original);c.starting.changeFunc() end
	end)
	c.undoBlank.enabled=function() return beforeBlank~=nil and c.starting.buf==blankSnapshot end
	c.undoBlank.tooltipText="Restore the previous starting item if the blank base has not been edited."
	ui.description(c,"blankHint",16,410,col,58,{"Fresh base: review its implicit, sockets and quality. The original modifiers are not copied."},14)
	local startPreview=require("Classes.JourneyItemControl").new(c,"startPreview",col+32,148,col,208,"STARTING ITEM")
	ui.label(c,"targetLabel",16,76,"Desired item (optional)");edit("target",16,102,col,180,draft.targetItem,24000)
	button("pasteTarget",16,296,math.floor((col-8)/2),"Paste target item",function() c.target:SetText(Paste());c.target.changeFunc() end)
	button("originalTarget",24+math.floor((col-8)/2),296,math.floor((col-8)/2),"Use original item",function()
		if beforeBlank and not c.target.buf:match("%S") then c.target:SetText(beforeBlank);c.target.changeFunc() end
	end)
	c.originalTarget.enabled=function() return beforeBlank~=nil and not c.target.buf:match("%S") end
	c.originalTarget.tooltipText=function()
		if not beforeBlank then return "Use a blank base on the first page to keep the original as a target." end
		if c.target.buf:match("%S") then return "Clear the target first; this will not overwrite an existing target." end
		return "Copy the original item into the target. This does not equip or change gear."
	end
	local targetPreview=require("Classes.JourneyItemControl").new(c,"targetPreview",col+32,82,col,244,"TARGET ITEM")
	ui.label(c,"goalsLabel",16,344,"Target modifiers / goals (one per line)");edit("goals",16,370,w-32,math.max(50,h-450),table.concat(draft.goals,"\n"),2*1024*1024)
	local steps={};for _,step in ipairs(draft.steps) do steps[#steps+1]=step.action end;local original=table.concat(steps,"\n")
	ui.label(c,"stepsLabel",16,76,"Written crafting guide");edit("steps",16,102,col,140,original,2*1024*1024)
	ui.label(c,"methodLabel",col+32,76,"Starting currency")
	local methods={};local sim=require("Modules.CraftingSimulator");for _,method in ipairs(sim.methods) do methods[#methods+1]={label=sim.labels[method] or method,val=method} end
	c.method=new("DropDownControl"):DropDownControl(ui.anchor,{col+32,102,col,28},methods);c.method:SelByValue(draft.preferredMethod or draft.nativeRecipe and draft.nativeRecipe.steps[1].method or "alchemy","val")
	c.method.selFunc=function() ui.draft(build,"crafting") end
	ui.description(c,"methodHint",col+32,144,col,88,{"Configure special currency options and executable recipes in the workbench. Written guide steps remain notes."},15)
	ui.label(c,"notesLabel",16,258,"Stop conditions and notes");edit("notes",16,284,w-32,66,draft.notes,8000)
	ui.label(c,"costLabel",16,368,"Estimated total");edit("cost",16,394,120,28,draft.estimate and tostring(draft.estimate.amount),20)
	edit("currency",148,394,120,28,draft.estimate and draft.estimate.currency or "chaos",24)
	edit("priceSource",280,394,w-296,28,draft.estimate and draft.estimate.source,240)
	ui.label(c,"currencyLabel",148,368,"Currency");ui.label(c,"sourceLabel",280,368,"Price source")
	c.review=new("TextListControl"):TextListControl(ui.anchor,{16,78,w-32,h-156},nil,{})
	local function read()
		draft.title=c.title.buf;draft.slot=c.slot:GetSelValue();draft.startingItem=c.starting.buf;draft.targetItem=c.target.buf;draft.notes=c.notes.buf;draft.preferredMethod=c.method:GetSelValueByKey("val")
		draft.goals={};for line in c.goals.buf:gmatch("[^\r\n]+") do if line:match("%S") then draft.goals[#draft.goals+1]=line end end
		if c.steps.buf~=original then
			local previous=draft.steps;local oldByText,newCount,lines={},{},{}
			for _,step in ipairs(previous) do local group=oldByText[step.action] or {};oldByText[step.action]=group;group[#group+1]=step end
			for line in c.steps.buf:gmatch("[^\r\n]+") do if line:match("%S") then lines[#lines+1]=line;newCount[line]=(newCount[line] or 0)+1 end end
			for action,group in pairs(oldByText) do
				local remove=math.max(0,#group-(newCount[action] or 0))
				-- Identical instructions are indistinguishable here. Retain every
				-- protected copy and discard only unannotated duplicates.
				local retained={}
				for _,step in ipairs(group) do
					if remove>0 and not step.done and not step.uniqueCraft and (not step.stopWhen or step.stopWhen=="") and (not step.onFailure or step.onFailure=="") then
						remove=remove-1
					else retained[#retained+1]=step end
				end
				assert(remove==0,"This edit would remove step progress, notes or a modeled craft. Use Browse guide steps to edit or remove that step first.")
				oldByText[action]=retained
			end
			draft.steps={}
			local used={}
			for _,line in ipairs(lines) do
				used[line]=(used[line] or 0)+1;local group=oldByText[line];local old=group and group[used[line]]
				draft.steps[#draft.steps+1]=old and copyTable(old) or {action=line}
			end
		end
		if c.cost.buf~="" then local amount=assert(tonumber(c.cost.buf),"Enter a numeric cost");local old=draft.estimate;draft.estimate={amount=amount,currency=c.currency.buf,source=c.priceSource.buf,quotedAt=old and old.amount==amount and old.currency==c.currency.buf and old.source==c.priceSource.buf and old.quotedAt or os.time()} else draft.estimate=nil end
		-- A checkpoint belongs to its original item. Keep it in the editor's
		-- draft until the user confirms changing that item; do not validate it
		-- against a different base while preparing the review.
		local candidate=copyTable(draft)
		if source and candidate.startingItem~=source.startingItem then candidate.run=nil end
		return projects.validate(candidate)
	end
	local groups={
		["Starting item"]={"titleLabel","title","slotLabel","slot","startingLabel","starting","pasteStarting","useEquipped","blankStarting","undoBlank","blankHint","startPreview","startPreviewMods"},
		Target={"targetLabel","target","pasteTarget","originalTarget","targetPreview","targetPreviewMods","goalsLabel","goals"},
		["Method & budget"]={"stepsLabel","steps","methodLabel","method","methodHint","notesLabel","notes","costLabel","cost","currencyLabel","currency","sourceLabel","priceSource"},Review={"review"},
	}
	for page,keys in pairs(groups) do for _,key in ipairs(keys) do c[key].shown=function() return c.wizardPage:GetSelValue()==page end end end
	c.wizardPage.selFunc=function() if c.wizardPage:GetSelValue()=="Review" then c.review.list=ui.rows(projects.lines(read()),w-56) end end
	local function update(key,render) local ok,item=pcall(projects.item,c[key].buf);render(ok and item or nil) end
	c.starting.changeFunc=function() ui.draft(build,"crafting");update("starting",startPreview) end
	c.target.changeFunc=function() ui.draft(build,"crafting");update("target",targetPreview) end
	button("previous",16,h-48,120,"Previous",function() c.wizardPage:SetSel(math.max(1,c.wizardPage.selIndex-1)) end)
	button("next",148,h-48,120,"Next",function()
		if c.wizardPage.selIndex==1 then local item=projects.item(c.starting.buf);assert(build.itemsTab:IsItemValidForSlot(item,c.slot:GetSelValue()),"Item cannot use this slot") end
		c.wizardPage:SetSel(math.min(4,c.wizardPage.selIndex+1))
	end)
	button("save",16,h-48,200,"Keep project in build",function()
		local candidate=read();local changed=source and candidate.startingItem~=source.startingItem
		local starts=0
		if changed then
			if candidate.nativeRecipe and candidate.nativeRecipe.initialState then starts=starts+1 end
			for _,alternative in ipairs(candidate.recipeAlternatives or {}) do if alternative.recipe.initialState then starts=starts+1 end end
		end
		local function keep(reset)
			if reset then
				if candidate.nativeRecipe then candidate.nativeRecipe.initialState=nil end
				for _,alternative in ipairs(candidate.recipeAlternatives or {}) do alternative.recipe.initialState=nil end
			end
			local kept=build.savers.CraftingProjects:Upsert(candidate);main:ClosePopup();onKeep(kept)
		end
		if changed and (starts>0 or source.run) then
			local lines={}
			if starts>0 then lines[#lines+1]="Changing the item resets "..starts.." saved recipe starting state"..(starts==1 and "" or "s").."." end
			if source.run then lines[#lines+1]="The saved working session and its history will be discarded." end
			lines[#lines+1]="Recipe steps, goals and item snapshots are kept."
			main:OpenConfirmPopup("Change starting item",table.concat(lines,"\n"),"Use new item",function()
				local ok,err=pcall(keep,true);if not ok then ui.errorPopup("Crafting project",err) end
			end)
		else keep(false) end
	end)
	button("preview",232,h-48,180,"Preview target stats",function() preview(read()) end)
	button("close",w-136,h-48,120,"Cancel",function() ui.discard(build,"crafting");main:ClosePopup() end)
	c.save.shown=function() return c.wizardPage.selIndex==4 end;c.preview.shown=c.save.shown;c.previous.shown=function() return c.wizardPage.selIndex>1 and c.wizardPage.selIndex<4 end;c.next.shown=function() return c.wizardPage.selIndex<4 end
	update("starting",startPreview);update("target",targetPreview)
	for _,control in pairs(c) do control.layoutAudit="crafting-project-wizard" end
	ui.style(c,{next=true,save=true},{startPreview=true,targetPreview=true});main:OpenPopup(w,h,"Crafting project",c,nil,"title","close")
end
return M
