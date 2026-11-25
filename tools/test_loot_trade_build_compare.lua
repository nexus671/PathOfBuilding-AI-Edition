local root=assert(arg[1]):gsub("\\","/").."/"
arg={}
dofile("HeadlessWrapper.lua")
main.disableDevAutoSave=true
newBuild()
main.popups={}
local headless=require("Modules.HeadlessUI").install({width=720,height=600})
headless:bind(build)
package.loaded["Modules.LootTradeOverlayWindows"]={
	processId=function() return 175 end,
	foregroundProcess=function() return 175 end,
	replaceFile=function(from,to) os.remove(to);assert(os.rename(from,to)) end,
}
local target=root.."LootTradeBuildTarget.json"
local transport=require("Modules.LootTradeBuildCompare")
local json=require("dkjson")
local function read(path)
	local file=io.open(path,"rb")
	if not file then return end
	local text=file:read("*a")
	file:close()
	return json.decode(text)
end
local function write(path,object)
	local file=assert(io.open(path,"wb"))
	assert(file:write(json.encode(object)))
	assert(file:close())
end
local raw="Rarity: Rare\nFixture Ring\nAmethyst Ring\nItem Level: 86\n+90 to maximum Life"
local bridge=require("Modules.DesktopBuildBridge")
local before=bridge.revision(build)
local now=os.time()
assert(not pcall(transport.send,root,raw,now))
transport.tick(root,build,now)
local peer=assert(read(target))
local path=root.."LootTradeBuild-"..peer.ticket..".json"
assert(transport.send(root,raw,now)==peer.name and read(path).item==raw)
main:OpenMessagePopup("Existing dialog","Keep this dialog open.")
transport.tick(root,build,now+1)
assert(main.popups[1].title=="Existing dialog" and not read(path))
main:ClosePopup()
transport.tick(root,build,now+2)
assert(main.popups[1].title=="Compare in PoB" and not read(path))
headless:text("search","Ring 1")
headless:click("choose")
assert(main.popups[1].title=="Build comparison")
local evidence={}
for _, line in ipairs(main.popups[1].controls.details.list) do evidence[#evidence+1]=StripEscapes(line[1] or "") end
local text=table.concat(evidence," ")
assert(text:find("+90",1,true) and text:find("Hypothetical stat changes",1,true),text)
assert(bridge.revision(build)==before)
main.popups={}
write(path,{version=1,ticket=peer.ticket,created=now-60,item=raw})
transport.tick(root,build,now+3)
assert(not main.popups[1] and not read(path))
write(path,{version=1,ticket=string.rep("b",40),created=now+2,item=raw})
transport.tick(root,build,now+4)
assert(not main.popups[1] and not read(path))
transport.close()
assert(not read(target))
assert(not pcall(transport.send,root,raw,now+5))
print("Local trade handoff previews real build stats and discards expired or mismatched requests")
