-- Expand only explicitly supplied filter texts; never read arbitrary paths.
local parser=require("Modules.LootFilterParser")
local M={}
-- Only called after the user explicitly enters a path and chooses Load file.
function M.readFile(path,limit)
	assert(type(path)=="string" and path~="","Enter a local file path")
	local handle,why=io.open(path,"rb")
	assert(handle,"Could not open file: "..tostring(why))
	local contents,err=handle:read((limit or 2*1024*1024)+1)
	handle:close()
	assert(contents or not err,"Could not read file: "..tostring(err))
	contents=contents or ""
	assert(#contents<=(limit or 2*1024*1024),"Filter file exceeds 2 MiB")
	assert(not contents:find("\0",1,true),"Filter file contains binary data")
	return contents
end
-- Load simple sibling filter names only after an explicit user action.
-- Keep path-like references unresolved instead of following them outside the chosen folder.
function M.collectLocal(raw,sourcePath,limit)
	assert(type(sourcePath)=="string" and sourcePath~="","Enter the main filter's local file path")
	limit=limit or 2*1024*1024
	local folder=sourcePath:match("^(.*[/\\])") or "./"
	local queue,seen,files,issues={}, {}, {}, {};local total=0
	local function enqueue(text) for _,entry in ipairs(parser.parse(text).imports) do queue[#queue+1]=entry end end
	enqueue(raw);local cursor=1
	while cursor<=#queue do
		local entry=queue[cursor];cursor=cursor+1;local name=entry.file;local prior=seen[name]
		if prior then if prior.issue then prior.issue.optional=prior.issue.optional and entry.optional end
		else
			local item={};seen[name]=item
			local stem=(name:match("^([^%.]+)") or ""):gsub("%s+$",""):upper()
			local reserved=stem=="CON" or stem=="PRN" or stem=="AUX" or stem=="NUL" or stem:match("^COM[1-9]$") or stem:match("^LPT[1-9]$")
			local safe=#name<=240 and not reserved and not name:find('[%c/\\:*?"<>|]') and require("Modules.LootFilterFileNames").isFilter(name)
			local ok,value
			if safe then ok,value=pcall(M.readFile,folder..name,limit) else ok,value=false,"Only simple sibling .filter or .ruthlessfilter names up to 240 characters can be loaded automatically." end
			if ok and total+#name+#value<=limit then
				total=total+#name+#value;files[#files+1]={name=name,text=value};enqueue(value)
			else
				if ok then value="Included files exceed the 2 MiB combined limit." end
				item.issue={name=name,optional=entry.optional and true or false,reason=tostring(value)};issues[#issues+1]=item.issue
			end
		end
	end
	return {files=files,issues=issues}
end
function M.merge(existing,loaded)
	local result=copyTable(existing or {});local positions={}
	for index,file in ipairs(result) do positions[file.name]=index end
	for _,file in ipairs(loaded or {}) do local index=positions[file.name] or #result+1;result[index]=copyTable(file);positions[file.name]=index end
	return result
end
function M.expand(raw,files,limit)
	local sources={};for _,file in ipairs(files or {}) do sources[file.name]=file.text end
	local size=0;local stack={};local output={};limit=limit or 2*1024*1024
	local function emit(line)
		size=size+#line+1;assert(size<=limit,"Expanded filter exceeds 2 MiB");output[#output+1]=line
	end
	local function expand(text,depth)
		assert(depth<=32,"Filter imports exceed nesting limit")
		-- Each supplied file may have its own UTF-8 byte-order mark. Once
		-- embedded in the compiled filter it is no longer at the start of a file.
		text=text:gsub("^\239\187\191","")
		for line in (text.."\n"):gmatch("([^\n]*)\n") do
			local ok,tokens=pcall(parser.tokens,line)
			local name=ok and tokens[1]=="Import" and tokens[2]
			if name and (#tokens==2 or #tokens==3 and tokens[3]=="Optional") and sources[name] and not stack[name] then
				emit("# Included filter: "..name);stack[name]=true;expand(sources[name],depth+1);stack[name]=nil;emit("# End included filter: "..name)
			else emit(line) end
		end
	end
	expand(raw,0);return table.concat(output,"\n")
end
-- Use the same expansion as preview/export so this list includes nested
-- references and identifies cycles without consulting the local filesystem.
function M.summarize(parsed,files)
	local supplied={};for _,file in ipairs(files or {}) do supplied[file.name]=true end
	local found,rows={},{}
	for _,entry in ipairs(parsed.imports) do
		local row=found[entry.file]
		if not row then
			row={name=entry.file,optional=entry.optional,cycle=supplied[entry.file] or false,count=0}
			found[entry.file]=row;rows[#rows+1]=row
		else row.optional=row.optional and entry.optional end
		row.count=row.count+1
	end
	table.sort(rows,function(a,b) return a.name:lower()==b.name:lower() and a.name<b.name or a.name:lower()<b.name:lower() end)
	return rows
end
function M.unresolved(raw,files,limit)
	return M.summarize(parser.parse(M.expand(raw,files,limit)),files)
end
return M
