-- Browse local folders only in response to the user's explicit selection.
local M={}
local function directory(path)
	path=(path or ""):gsub("\\","/")
	if path=="" then path=(main.userPath or "./"):gsub("\\","/") end
	if path:sub(-1)~="/" then path=path:match("^(.*)/[^/]*$") or ".";path=path.."/" end
	return path
end
local function parent(path)
	local trimmed=path:gsub("/$","")
	if trimmed=="" or trimmed:match("^%a:$") then return nil end
	local result=trimmed:match("^(.*)/[^/]+$")
	if result==nil then return nil end
	if result=="" then return "/" end
	return result.."/"
end
function M.entries(path)
	local entries={}
	local up=parent(path)
	if up then entries[#entries+1]={id=up,label=".. (parent folder)",category="Folders",folder=true} end
	local function scan(folders)
		local handle=NewFileSearch(path.."*",folders)
		while handle do
			local name=handle:GetFileName()
			if name~="." and name~=".." and (folders or require("Modules.LootFilterFileNames").isFilter(name)) then
				local full=path..name..(folders and "/" or "")
				entries[#entries+1]={id=full,label=(folders and "Folder: " or "Filter: ")..name,category=folders and "Folders" or "Filters",folder=folders,details={full}}
			end
			if not handle:NextFile() then break end
		end
		if handle and handle.Close then handle:Close() end
	end
	scan(true);scan(false)
	table.sort(entries,function(a,b) if a.folder~=b.folder then return a.folder end return a.label:lower()<b.label:lower() end)
	return entries
end
function M.Open(initial,choose)
	local function browse(path)
		local entries=M.entries(path)
		require("Classes.PlanningBrowserControl").Open("Choose a local filter",entries,{action="Open",closeOnChoose=false,choose=function(entry)
			main:ClosePopup()
			if entry.folder then browse(entry.id) else choose(entry.id) end
		end})
	end
	browse(directory(initial))
end
return M
