-- Portable data only. Native build XML carries kept plans and checkpoints.
-- cspell:ignore jsontype
local json=require("dkjson")
local sha1=require("sha1")
local M={limit=16*1024*1024}
function M.contents(xml)
	local parsed=assert(common.xml.ParseXML(xml));local root=assert(parsed[1]);assert(root.elem=="PathOfBuilding","Bundle needs native Path of Building XML")
	local result={crafts=0,checkpoints=0,inventory=0,atlas=0,stages=0,wishlist=0,milestones=0,filters=0,sections={},unreadableSections={}}
	for _,node in ipairs(root) do if type(node)=="table" then
		result.sections[#result.sections+1]=node.elem
		if node.elem=="CraftingProjects" or node.elem=="AtlasPlans" or node.elem=="BuildJourney" or node.elem=="LootFilters" then
			local ok,counts=pcall(function()
				local raw=table.concat(node);if not raw:match("%S") then return {} end
				local data,pos=json.decode(raw)
				assert(type(data)=="table" and pos and not raw:sub(pos):find("%S") and data.schemaVersion==1)
				local counts={}
				local function array(value,required)
					if value==nil and not required then return {} end
					assert(type(value)=="table" and value~=json.null)
					local meta=getmetatable(value);assert(not meta or meta.__jsontype~="object")
					return value
				end
				if node.elem=="CraftingProjects" then
					counts.crafts,counts.inventory,counts.checkpoints=0,0,0
					for _,project in ipairs(array(data.projects,true)) do
						assert(type(project)=="table");counts.crafts=counts.crafts+1
						counts.inventory=counts.inventory+#array(project.inventory)
						if project.run then counts.checkpoints=counts.checkpoints+1 end
					end
				elseif node.elem=="AtlasPlans" then counts.atlas=#array(data.plans,true)
				elseif node.elem=="LootFilters" then counts.filters=#array(data.profiles,true)
				else for _,key in ipairs({"stages","wishlist","milestones"}) do counts[key]=#array(data[key]) end end
				return counts
			end)
			if ok then for key,value in pairs(counts) do result[key]=value end
			else result.unreadableSections[#result.unreadableSections+1]=node.elem end
		end
	end end
	return result
end
function M.export(build)
	local xml=require("Modules.DesktopBuildBridge").serialize(build)
	local bundle={kind="PathOfBuilding-AI-Edition",schemaVersion=1,createdAt=os.time(),sourceVersion=launch.versionNumber,buildName=(build.buildName or "Imported planning bundle"):sub(1,120),xml=xml,checksum=sha1(xml)}
	local raw=json.encode(bundle);assert(#raw<=M.limit,"Planning bundle exceeds 16 MiB");return raw,M.contents(xml)
end
function M.import(raw)
	assert(type(raw)=="string" and #raw<=M.limit,"Planning bundle exceeds 16 MiB")
	local bundle,pos=json.decode(raw)
	assert(bundle and not raw:sub(pos):find("[^ \t\r\n]"),"This is not a valid planning bundle.")
	assert(type(bundle)=="table" and bundle.kind=="PathOfBuilding-AI-Edition" and bundle.schemaVersion==1,"Unsupported planning bundle")
	assert(type(bundle.xml)=="string" and type(bundle.checksum)=="string" and sha1(bundle.xml)==bundle.checksum,"Bundle checksum does not match")
	assert(type(bundle.buildName)=="string" and #bundle.buildName<=120 and bundle.buildName:match("%S") and not bundle.buildName:find("[%c]"),"Invalid bundle build name")
	bundle.contents=M.contents(bundle.xml);return bundle
end
local sectionsForCount={crafts="CraftingProjects",checkpoints="CraftingProjects",inventory="CraftingProjects",atlas="AtlasPlans",stages="BuildJourney",wishlist="BuildJourney",milestones="BuildJourney",filters="LootFilters"}
function M.count(contents,key)
	for _,section in ipairs(contents.unreadableSections or {}) do if section==sectionsForCount[key] then return "Unavailable" end end
	return tostring(contents[key] or 0)
end
function M.lines(contents)
	local lines={string.format("%s crafting guides | %s working checkpoints | %s saved items | %s Atlas plans",M.count(contents,"crafts"),M.count(contents,"checkpoints"),M.count(contents,"inventory"),M.count(contents,"atlas")),string.format("%s milestones | %s gear goals | %s leveling stages",M.count(contents,"milestones"),M.count(contents,"wishlist"),M.count(contents,"stages")),string.format("%s loot-filter profiles | native character, items, skills, passives, configuration and notes.",M.count(contents,"filters")),"Only kept plans and checkpoints travel. Keep working drafts before exporting.","Prices, crafting odds and external references retain their recorded dates and assumptions. They are not refreshed on import."}
	if contents.unreadableSections and #contents.unreadableSections>0 then lines[#lines+1]="Some planning data could not be summarized; its original data is included unchanged: "..table.concat(contents.unreadableSections,", ") end
	return lines
end
return M
