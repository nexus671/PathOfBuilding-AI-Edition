-- Genesis tree draft editor. Allocation rules and rendering remain experimental.
local planner=require("Modules.GenesisPlanner")
local ui=require("Modules.PlanningUI")
local Canvas=newClass("GenesisTreeCanvas","Control","TooltipHost")
local angles={0,30,45,60,90,120,135,150,180,210,225,240,270,300,315,330}
local function position(node)
	local angle=math.rad(angles[node.orbitIndex+1] or 0);local radius=node.orbit==2 and 162 or 0
	return node.groupX+math.sin(angle)*radius,node.groupY-math.cos(angle)*radius
end
function Canvas:GenesisTreeCanvas(rect,tree,getPlan,onFocus,onActivate)
	self:Control(ui.anchor,rect);self:TooltipHost();self.tree=tree;self.getPlan=getPlan;self.onFocus=onFocus;self.onActivate=onActivate
	self.icons={};self.frames={}
	local file=assert(io.open("Assets/Genesis/manifest.json","rb"));local manifest=assert(require("dkjson").decode(file:read("*a")));file:close()
	for name,entry in pairs(manifest.icons) do local handle=NewImageHandle();handle:Load(entry.file);self.icons[name]=handle end
	for name,entry in pairs(manifest.frames) do local handle=NewImageHandle();handle:Load(entry.file);self.frames[name]=handle end
	self.background=NewImageHandle();self.background:Load(manifest.background.file);self.backgroundSize=manifest.background.nativeSize
	self:SetBranch(19625);return self
end
function Canvas:SetBranch(root)
	self.root=root;self.focus=nil;self:Fit()
end
function Canvas:Fit()
	local x1,x2,y1,y2=math.huge,-math.huge,math.huge,-math.huge
	for _,node in pairs(self.tree.nodes) do if node.root==self.root then local x,y=position(node);x1=math.min(x1,x);x2=math.max(x2,x);y1=math.min(y1,y);y2=math.max(y2,y) end end
	self.centerX,self.centerY=(x1+x2)/2,(y1+y2)/2
	self.scale=math.min((self.width-100)/math.max(1,x2-x1),(self.height-100)/math.max(1,y2-y1),0.55)
end
function Canvas:Position(node)
	local x,y=position(node);return self.width/2+(x-self.centerX)*self.scale,self.height/2+(y-self.centerY)*self.scale
end
function Canvas:IsMouseOver() return self:IsShown() and self:IsMouseInBounds() end
function Canvas:Draw()
	local x,y=self:GetPos();local cursorX,cursorY=GetCursorPos();local allocated={}
	if self.drag then self.centerX=self.drag.centerX-(cursorX-self.drag.x)/self.scale;self.centerY=self.drag.centerY-(cursorY-self.drag.y)/self.scale end
	for _,id in ipairs(self.getPlan().nodes) do allocated[id]=true end
	allocated[self.root]=true;for id in pairs(planner.wombs) do allocated[id]=true end
	SetViewport(x,y,self.width,self.height);SetDrawColor("^x101923");DrawImage(nil,0,0,self.width,self.height)
	local bw,bh=self.backgroundSize[1],self.backgroundSize[2]
	SetDrawColor(1,1,1);DrawImage(self.background,self.width/2+(-bw/2-self.centerX)*self.scale,self.height/2+(-bh/2-self.centerY)*self.scale,bw*self.scale,bh*self.scale)
	for id,node in pairs(self.tree.nodes) do if node.root==self.root then
		local a,b=self:Position(node)
		for _,other in ipairs(node.links) do if id<other and id~=self.root and other~=self.root then
			local c,d=self:Position(self.tree.nodes[other]);local dx,dy=c-a,d-b;local len=math.max(1,math.sqrt(dx*dx+dy*dy));local ox,oy=-dy/len,dx/len
			SetDrawColor(allocated[id] and allocated[other] and "^xB25AFF" or "^x6D587A");DrawImageQuad(nil,a+ox,b+oy,c+ox,d+oy,c-ox,d-oy,a-ox,b-oy)
		end end
	end end
	self.hover=nil;local nearest=math.huge
	for id,node in pairs(self.tree.nodes) do if node.root==self.root and id~=self.root then
		local a,b=self:Position(node);local womb=planner.wombs[id];local notable=node.notable or node.choice
		local size=womb and 20 or notable and 22 or 15
		local frameSize=womb and 40 or notable and 36 or 24
		if not womb then
			local icon=node.icon and node.icon:match("/([^/]+)%.dds$");local handle=icon and self.icons[icon]
			if handle then SetDrawColor(allocated[id] and 1 or 0.65,allocated[id] and 1 or 0.65,allocated[id] and 1 or 0.65);DrawImage(handle,a-size/2,b-size/2,size,size)
			else SetDrawColor(self.focus==id and "^x6EDDD1" or allocated[id] and "^xCBA965" or "^x63798A");DrawImage(nil,a-size/2,b-size/2,size,size) end
		end
		local frame=womb and "Womb" or notable and (allocated[id] and "FrameNotableActive" or "FrameNotable") or (allocated[id] and "FrameSmallActive" or "FrameSmall")
		SetDrawColor(1,1,1);DrawImage(self.frames[frame],a-frameSize/2,b-frameSize/2,frameSize,frameSize)
		if self.focus==id then SetDrawColor("^x6EDDD1");DrawImage(nil,a-size/2-2,b-size/2-2,size+4,2);DrawImage(nil,a-size/2-2,b+size/2,size+4,2) end
		local distance=(cursorX-x-a)^2+(cursorY-y-b)^2
		if distance<nearest and distance<=(frameSize/2)^2 then self.hover=id;nearest=distance end
	end end
	SetViewport()
	if self.hover and self:IsMouseOver() then
		local node=self.tree.nodes[self.hover];self.tooltip:Clear();self.tooltip:AddLine(16,node.name)
		for _,stat in ipairs(node.stats) do self.tooltip:AddLine(14,stat) end
		self.tooltip:AddLine(14,planner.wombs[self.hover] and "Womb starting point" or "Click to inspect; double click to change")
		SetDrawLayer(nil,100);self.tooltip:Draw(cursorX,cursorY,1,1,main.viewPort);SetDrawLayer(nil,0)
	end
end
function Canvas:OnKeyDown(key,doubleClick)
	if key=="LEFTBUTTON" and self:IsMouseOver() and self.hover then
		self.focus=self.hover;self.onFocus(self.hover);if doubleClick and not planner.wombs[self.hover] then self.onActivate(self.hover) end
	elseif (key=="LEFTBUTTON" or key=="RIGHTBUTTON") and self:IsMouseOver() then
		local x,y=GetCursorPos();self.drag={x=x,y=y,centerX=self.centerX,centerY=self.centerY};return self
	end
end
function Canvas:OnKeyUp(key)
	if key=="WHEELUP" or key=="WHEELDOWN" then
		local old=self.scale;self.scale=key=="WHEELUP" and math.min(1,old*1.25) or math.max(0.02,old/1.25)
		local x,y=self:GetPos();local cx,cy=GetCursorPos()
		self.centerX=self.centerX+(cx-x-self.width/2)*(1/old-1/self.scale);self.centerY=self.centerY+(cy-y-self.height/2)*(1/old-1/self.scale)
	else self.drag=nil end
end
function Canvas:OnFocusLost() self.drag=nil end

local Panel={}
function Panel.Open(original,onKeep)
	local plan=planner.validate(original or planner.empty());local tree=planner.tree();local c={}
	local w,h=math.min(1100,main.screenW-40),math.min(760,main.screenH-60);local side=w-278;local graphW=side-32;local graphH=h-180
	local function button(key,x,y,width,label,callback)
		c[key]=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{x,y,width,28},label,callback))
	end
	local function safe(fn) local ok,err=pcall(fn);if not ok then ui.errorPopup("Genesis planner",err) end end
	local refresh;local canToggle=false
	local function isAllocated(id) for _,value in ipairs(plan.nodes) do if value==id then return true end end;return false end
	local function replacedChoice(id)
		local node=tree.nodes[id]
		if not node or not node.choiceOption or isAllocated(id) then return nil end
		for _,parent in ipairs(node.links) do if tree.nodes[parent].choice then
			for _,other in ipairs(tree.nodes[parent].links) do
				if tree.nodes[other].choiceOption and isAllocated(other) then return tree.nodes[other] end
			end
		end end
	end
	local function apply(id)
		safe(function()
			local removing=isAllocated(id);local replaced=replacedChoice(id);local next,affected
			if removing then next,affected=planner.toggle(plan,id) else next,affected=planner.connect(plan,id) end
			local function commit() plan=next;refresh() end
			if replaced then
				main:OpenConfirmPopup("Replace Genesis choice","Replace "..replaced.name.." with "..tree.nodes[id].name.."?","Replace",commit)
			elseif #affected>1 then
				main:OpenConfirmPopup(removing and "Remove Genesis branch" or "Connect Genesis path",removing and (#affected.." passives would be removed, including disconnected nodes.") or (#affected.." nodes will be added to connect this passive."),removing and "Remove" or "Connect",commit)
			else commit() end
		end)
	end
	c.canvas=new("GenesisTreeCanvas"):GenesisTreeCanvas({16,80,graphW,graphH},tree,function() return plan end,function() refresh() end,apply)
	c.branch=new("DropDownControl"):DropDownControl(ui.anchor,{16,30,200,28},{{label="Currency",val=19625},{label="Equipment",val=22476},{label="Unique",val=47967},{label="Mysterious",val=42956}})
	c.branch:SelByValue(19625,"val")
	ui.label(c,"count",232,37,"",14)
	button("fit",side,30,110,"Fit tree",function() c.canvas:Fit() end)
	ui.label(c,"version",side+118,37,"3.30.0d Standard",14)
	c.search=new("EditControl"):EditControl(ui.anchor,{side,80,246,26},"","Search all trees",nil,120)
	c.results=new("TextListControl"):TextListControl(ui.anchor,{side,112,246,104},nil,{})
	ui.description(c,"details",side,226,246,math.max(40,h-390),{},14)
	button("toggle",side,h-146,246,"Allocate or remove",function() if c.canvas.focus then apply(c.canvas.focus) end end)
	c.toggle.enabled=function() return canToggle end
	c.toggle.label=function()
		return isAllocated(c.canvas.focus) and "Remove passive" or "Connect path"
	end
	button("keep",16,h-48,220,"Use in Atlas draft",function() safe(function() onKeep(plan);main:ClosePopup() end) end)
	button("close",w-132,h-48,116,"Cancel",function() main:ClosePopup() end)
	ui.description(c,"help",16,h-82,w-32,30,{"Wheel: zoom | Drag: pan | Select a passive to change it. Rules need game verification."},14)
	local function search()
		local rows={};local query=c.search.buf:lower()
		if query~="" then
			local matches={};for id,node in pairs(tree.nodes) do if node.name~="" and not planner.wombs[id] and not planner.roots[id] then
				if (node.name.." "..table.concat(node.stats," ")):lower():find(query,1,true) then matches[#matches+1]=node end
			end end
			table.sort(matches,function(a,b) if a.name==b.name then return a.id<b.id end;return a.name<b.name end)
			for _,node in ipairs(matches) do rows[#rows+1]={height=38,textSize=14,"^7"..ui.fit(node.name,216,14),subtitle=planner.roots[node.root].." tree",node=node} end
			if #rows==0 then rows=ui.rows({"No matching passives."},216,14) end
		else rows=ui.rows({"Search all trees by name or effect."},216,14) end
		c.results.list=rows;c.results.controls.scrollBar:SetOffset(0)
	end
	ui.selectable(c.results,function(row) return row.node and row.node.id end,function(row)
		local node=row.node
		if c.canvas.root~=node.root then c.canvas:SetBranch(node.root);c.branch:SelByValue(node.root,"val") end
		c.canvas.focus=node.id;c.canvas.centerX,c.canvas.centerY=position(node);c.canvas.scale=math.max(c.canvas.scale,0.35);refresh()
	end)
	c.search.changeFunc=search
	c.branch.selFunc=function() c.canvas:SetBranch(c.branch:GetSelValueByKey("val"));search();refresh() end
	refresh=function()
		local report=planner.report(plan);local count=report.counts[c.canvas.root]
		c.count.label="^7"..count.allocated..(count.allocated==1 and " passive | " or " passives | ")..count.options..(count.options==1 and " choice" or " choices")
		local node=c.canvas.focus and tree.nodes[c.canvas.focus];local lines=node and {node.name} or {"Select a passive to inspect it."}
		if count.publishedMaximum then
			lines[#lines+1]="3.29 notes: Equipment maximum "..count.publishedMaximum.." points."
			lines[#lines+1]="Womb and choice point costs need game verification."
			if count.selectedPassivesExceedReference then lines[#lines+1]="^xFFBB77Over 16 passives selected; verify their point costs in game." end
		end
		canToggle=false
		if node then
			for _,stat in ipairs(node.stats) do lines[#lines+1]=stat end
			if planner.wombs[node.id] then lines[#lines+1]="This womb is the starting point for its tree."
			else
				local allocated=isAllocated(node.id);local ok,reason,path
				if allocated then ok,reason,path=pcall(planner.toggle,plan,node.id) else ok,reason,path=pcall(planner.connect,plan,node.id) end
				canToggle=ok
				if not ok then lines[#lines+1]=ui.errorText(reason)
				elseif not allocated then
					lines[#lines+1]=#path..(#path==1 and " node to connect." or " nodes to connect.")
					local projected=planner.report(reason).counts[c.canvas.root]
					if projected.selectedPassivesExceedReference and not count.selectedPassivesExceedReference then lines[#lines+1]="^xFFBB77This path selects over 16 passives; verify point costs." end
				end
			end
			if node.choice then lines[#lines+1]="Choose one connected option." end
			local replaced=replacedChoice(node.id)
			if replaced then lines[#lines+1]="Replaces "..replaced.name.."." end
		end
		if #report.missingChoices>0 then lines[#lines+1]=#report.missingChoices.." allocated choice nodes need an option." end
		c.details.list=ui.rows(lines,230,14)
	end
	search();refresh();ui.style(c,{keep=true});for _,control in pairs(c) do control.layoutAudit="genesis-planner" end
	main:OpenPopup(w,h,"Genesis tree",c,nil,nil,"close");return c
end
return Panel
