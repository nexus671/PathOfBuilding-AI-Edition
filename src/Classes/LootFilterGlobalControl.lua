-- Reversible, build-owned settings applied to the complete compiled filter.
-- cspell:ignore RRGGBB RRGGBBAA
local ui=require("Modules.PlanningUI")
local filters=require("Modules.LootFilters")
local parser=require("Modules.LootFilterParser")
local visual=require("Modules.LootFilterVisuals")
local appearance=require("Modules.LootFilterAppearanceSettings")
local M={}
function M.Open(profile,onKeep,options)
	options=options or {}
	local c={};local settings=copyTable(profile.appearance or {})
	ui.description(c,"help",16,24,588,48,{options.help or "Change declared styles across personal rules and the base preset. Blank colours keep the original palette. Continue inheritance and pickup conditions are preserved."},14)
	local function setting(key,y,title,entries)
		local present=false;for _,entry in ipairs(entries) do if entry.val==settings[key] then present=true end end
		if settings[key]~=nil and not present then entries[#entries+1]={label="Custom: "..tostring(settings[key]),val=settings[key]} end
		ui.label(c,key.."Label",16,y,title,14)
		c[key]=new("DropDownControl"):DropDownControl(ui.anchor,{268,y-4,336,28},entries,function(_,value) settings[key]=value.val~=false and value.val or nil end)
		c[key]:SelByValue(settings[key]~=nil and settings[key] or false,"val")
	end
	local fonts={{label="Keep original sizes",val=false}};for _,size in ipairs({28,32,36,40,45}) do fonts[#fonts+1]={label="Minimum size "..size,val=size} end
	setting("minimumFontSize",92,"Label size",fonts)
	local volumes={{label="Keep original volumes",val=false},{label="Mute filter alerts",val=0}};for _,v in ipairs({50,100,200,300}) do volumes[#volumes+1]={label="Alert volume "..v,val=v} end
	setting("alertVolume",134,"Alert sounds",volumes)
	local beams={{label="Keep original beams",val=false},{label="Disable beams",val=true}};for _,color in ipairs(appearance.colors) do beams[#beams+1]={label=color.." beams",val=color} end
	setting("disableEffects",176,"Drop beams",beams);c.disableEffects:SelByValue(settings.disableEffects or settings.effectColor or false,"val")
	c.disableEffects.selFunc=function(_,entry) settings.disableEffects=entry.val==true and true or nil;settings.effectColor=type(entry.val)=="string" and entry.val or nil end
	local alerts={{label="Keep original alerts",val=false}};for i=1,16 do alerts[#alerts+1]={label="Use alert "..i,val=i} end
	setting("alertId",218,"Alert identity",alerts)
	setting("disableIcons",260,"Minimap icons",{{label="Keep original icons",val=false},{label="Disable icons",val=true}})
	local colorKeys={"textColor","borderColor","backgroundColor"}
	for i,key in ipairs(colorKeys) do
		local y=302+(i-1)*42;ui.label(c,key.."Label",16,y,({"Text colour","Border colour","Background colour"})[i],14)
		c[key]=new("EditControl"):EditControl(ui.anchor,{268,y-4,252,28},appearance.hex(settings[key]),nil,nil,9,function(value) if value=="" then settings[key]=nil else local color=appearance.fromHex(value);if color then settings[key]=color end end end);c[key].placeholder="Keep original / hex RGBA"
		c[key.."Pick"]=new("ButtonControl"):ButtonControl(ui.anchor,{528,y-4,76,28},"Pick",function()
			local initial=appearance.fromHex(c[key].buf) or settings[key]
			if not initial then local styles=parser.parse(filters.rule("example","Example",{},nil,profile.theme).text).rules[1].styles;local style=({textColor="SetTextColor",borderColor="SetBorderColor",backgroundColor="SetBackgroundColor"})[key];initial=appearance.rgba(style,styles[style]) end
			require("Classes.ColourPickerControl").Open(initial,function(colour) c[key]:SetText(appearance.hex(colour),true) end,{title=({textColor="Text colour",borderColor="Border colour",backgroundColor="Background colour"})[key],minimumAlpha=key=="textColor" and profile.mode=="Ruthless" and 80 or 0})
		end)
	end
	ui.label(c,"colourHint",16,414,"Hex: RRGGBB or RRGGBBAA; FF is opaque. Overrides replace tier colours.",12)
	c.preview=new("Control"):Control(ui.anchor,{16,440,588,64})
	function c.preview:Draw()
		local example=filters.rule("example","Example",{'BaseType == "Iron Hat"'},nil,profile.theme)
		local raw=require("Modules.LootFilterDecorators").apply(example.text,settings)
		local styles=parser.parse(require("Modules.LootFilterDecorators").apply(raw,options.previewAppearance)).rules[1].styles
		local x,y=self:GetPos();local width=self:GetSize();visual.floor(x,y,width,64);visual.chip(x,y,width,64,{BaseType="Crafting base"},{action="Show",styles=styles})
	end
	c.keep=new("ButtonControl"):ButtonControl(ui.anchor,{16,526,220,28},"Keep appearance",function()
		for _,key in ipairs(colorKeys) do assert(c[key].buf=="" or appearance.fromHex(c[key].buf),"Enter a valid hex colour") end
		local next=copyTable(profile);next.appearance=settings
		if options.validate then options.validate(settings) else local _,report=filters.compile(next);for _,d in ipairs(report.diagnostics) do assert(not d.error,d.error) end end;onKeep(next);main:ClosePopup()
	end)
	c.reset=new("ButtonControl"):ButtonControl(ui.anchor,{252,526,180,28},"Restore original",function() local next=copyTable(profile);next.appearance=nil;onKeep(next);main:ClosePopup() end)
	c.close=new("ButtonControl"):ButtonControl(ui.anchor,{448,526,156,28},"Cancel",function() main:ClosePopup() end)
	local w,h=620,574
	if main.screenH<634 or main.screenW<660 then
		w,h=math.min(w,main.screenW-40),math.min(h,main.screenH-60)
		c.page=new("DropDownControl"):DropDownControl(ui.anchor,{16,24,160,26},{"Style","Colours"})
		ui.tabs(c,c.page,{{"pageStyle","Style","Style"},{"pageColours","Colours","Colours"}},16,24,w-32)
		c.help.y=60;c.help.width=w-32
		local function page(key,name) c[key].shown=function() return c.page:GetSelValue()==name end end
		local labelWidth=math.floor((w-32)*0.4)
		for i,key in ipairs({"minimumFontSize","alertVolume","disableEffects","alertId","disableIcons"}) do
			local y=108+(i-1)*36;c[key.."Label"].y=y;c[key].x=16+labelWidth;c[key].y=y-4;c[key].width=w-32-labelWidth;page(key.."Label","Style");page(key,"Style")
		end
		for i,key in ipairs(colorKeys) do
			local y=108+(i-1)*42;c[key.."Label"].y=y;c[key].x=16+labelWidth;c[key].y=y-4;c[key].width=w-116-labelWidth;c[key.."Pick"].x=w-92;c[key.."Pick"].y=y-4
			page(key.."Label","Colours");page(key,"Colours");page(key.."Pick","Colours")
		end
		c.colourHint.y=242;page("colourHint","Colours")
		c.preview.y=h-128;c.preview.width=w-32
		local footer=math.floor((w-44)/3)
		for i,key in ipairs({"keep","reset","close"}) do c[key].x=16+(i-1)*(footer+6);c[key].y=h-44;c[key].width=footer end
	end
	ui.style(c,{keep=true});main:OpenPopup(w,h,options.title or "Whole-filter appearance",c,nil,nil,"close")
	for _,control in pairs(c) do if control.anchor then control.anchor.other=main.popups[1] end end
end
return M
