local M={}

-- Only report versioned entries that actually fall in the downloaded update.
function M.describe(text, installed, target)
	installed=installed or "unknown";target=target or "unknown"
	local result={"Installed: "..installed,"Downloaded: "..target,""}
	if target=="unknown" then result[#result+1]="The downloaded version could not be read. Release notes are unavailable.";return result end
	if installed==target then result[#result+1]="This update repairs or refreshes files for the installed version.";return result end
	local entries,current={},nil
	for line in ((text or "").."\n"):gmatch("([^\n]*)\n") do
		line=line:gsub("\r$","")
		local version,date=line:match("^VERSION%[(.-)%]%[(.-)%]$")
		if version then current={version=version,date=date,lines={}};entries[#entries+1]=current
		elseif current then current.lines[#current.lines+1]=line end
	end
	local prefix,targetNumber=target:match("^(.-%.preview)(%d+)$")
	local previousPrefix,previousNumber=installed:match("^(.-%.preview)(%d+)$")
	local selected,hasTarget,seen={},false,{}
	if prefix then
		targetNumber=tonumber(targetNumber);previousNumber=previousPrefix==prefix and tonumber(previousNumber) or nil
		for _,entry in ipairs(entries) do
			local p,n=entry.version:match("^(.-%.preview)(%d+)$");n=tonumber(n)
			if p==prefix and n and n<=targetNumber and (not previousNumber or n>previousNumber) then
				if seen[n] then result[#result+1]="Release notes contain duplicate versions and cannot be displayed reliably.";return result end
				seen[n]=true;selected[#selected+1]=entry;if n==targetNumber then hasTarget=true end
			end
		end
		table.sort(selected,function(a,b) return tonumber(a.version:match("(%d+)$"))>tonumber(b.version:match("(%d+)$")) end)
		if not hasTarget then result[#result+1]="Release notes for the downloaded version are unavailable.";return result end
		if not previousNumber or #selected~=targetNumber-previousNumber then result[#result+1]="Some earlier preview notes are unavailable.";result[#result+1]="" end
	else
		local started,foundPrevious=false,false
		for _,entry in ipairs(entries) do
			if entry.version==target then started=true;hasTarget=true end
			if started and entry.version==installed then foundPrevious=true;break end
			if started then selected[#selected+1]=entry end
		end
		if not hasTarget then result[#result+1]="Release notes for the downloaded version are unavailable.";return result end
		if not foundPrevious then result[#result+1]="Some earlier release notes may be unavailable.";result[#result+1]="" end
	end
	for _,entry in ipairs(selected) do
		result[#result+1]="Version "..entry.version.." ("..entry.date..")"
		for _,line in ipairs(entry.lines) do result[#result+1]=line end
	end
	return result
end
function M.target(path)
	local ok,document=pcall(require("xml").LoadXMLFile,path)
	if not ok then return nil end
	local version,hash
	if document and document[1] and document[1].elem=="PoBVersion" then
		for _,node in ipairs(document[1]) do if type(node)=="table" then
			local attrs=node.attrib or {}
			if node.elem=="Version" then version=attrs.number
			elseif node.elem=="File" and attrs.part=="default" and attrs.name=="changelog.txt" then hash=attrs.sha1 end
		end end
	end
	return version,hash
end
function M.matches(contents,expected)
	if type(contents)~="string" or type(expected)~="string" or not expected:match("^[a-f0-9]+$") or #expected~=40 then return false end
	local sha1=require("sha1")
	return sha1(contents)==expected or sha1(contents:gsub("\n","\r\n"))==expected
end
function M.readVerified(path,expected)
	if type(expected)~="string" or #expected~=40 then return nil end
	local file=io.open(path,"rb");if not file then return nil end
	local contents=file:read("*a");file:close()
	if M.matches(contents,expected) then return contents end
end
return M
