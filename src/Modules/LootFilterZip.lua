-- Create a portable, uncompressed ZIP without depending on a system archiver.
local bit=require("bit")
local band,bxor,rshift=bit.band,bit.bxor,bit.rshift
local crcTable={}
for n=0,255 do
	local crc=n
	for _=1,8 do crc=band(crc,1)==1 and bxor(rshift(crc,1),0xEDB88320) or rshift(crc,1) end
	crcTable[n]=crc
end
local function crc32(data)
	local crc=0xFFFFFFFF
	for i=1,#data do crc=bxor(rshift(crc,8),crcTable[band(bxor(crc,data:byte(i)),255)]) end
	return bxor(crc,0xFFFFFFFF)
end
local function u16(n) return string.char(band(n,255),band(rshift(n,8),255)) end
local function u32(n) return u16(n)..u16(rshift(n,16)) end
local M={}
local function archive(files)
	local output,central,seen={},{},{};local offset=0
	assert(#files<=65535,"Too many ZIP entries")
	for _,file in ipairs(files) do
		local name,body=file.name,file.text
		assert(not seen[name:lower()],"ZIP filenames collide");seen[name:lower()]=true
		local size=#body;local crc=crc32(body)
		local metadata=u16(20)..u16(0x0800)..u16(0)..u16(0)..u16(0)..u32(crc)..u32(size)..u32(size)..u16(#name)..u16(0)
		local localHeader="PK\003\004"..metadata..name
		output[#output+1]=localHeader;output[#output+1]=body
		central[#central+1]="PK\001\002"..u16(20)..metadata..u16(0)..u16(0)..u16(0)..u32(0)..u32(offset)..name
		offset=offset+#localHeader+size
	end
	local directory=table.concat(central)
	output[#output+1]=directory
	output[#output+1]="PK\005\006"..u16(0)..u16(0)..u16(#files)..u16(#files)..u32(#directory)..u32(offset)..u16(0)
	return table.concat(output)
end
function M.variants(profile,filename)
 local names=require("Modules.LootFilterFileNames");names.stem(profile,filename)
 local files={};for _,file in ipairs(require("Modules.LootFilters").variants(profile)) do files[#files+1]={name=names.variant(profile,filename,file.strictness),text=file.text} end
 return archive(files)
end
-- Explicit export only: include referenced local files in the ZIP and rewrite
-- paths to safe flat filenames. Never silently omit a missing optional sound.
local function soundBundle(filters,sourceDirectory)
 assert(type(filters)=="table" and type(sourceDirectory)=="string" and not sourceDirectory:find("[%c]"),"Invalid filter or sound directory")
 assert(not sourceDirectory:match("^[/\\][/\\]"),"Network sound folders are not supported in a portable bundle")
 local files,byPath,total={}, {},0
 local function sound(path)
  assert(path~="" and not path:find('[%c"]'),"Invalid custom sound path")
  local absolute=path:match("^%a:[/\\]") or path:sub(1,1)=="/"
  assert(not path:match("^[/\\][/\\]"),"Network sound paths are not supported in a portable bundle")
  local full=path
  if not absolute then
   assert(sourceDirectory~="","Choose the folder used by relative sound paths")
   for part in path:gmatch("[^/\\]+") do assert(part~=".." and part~=".","Relative sound paths cannot contain dot segments") end
   assert(not path:find(":",1,true),"Invalid relative sound path")
   full=sourceDirectory.."/"..path
  end
  if byPath[full] then return byPath[full] end
  local ext=path:match("%.([%w]+)$");assert(ext and #ext<=8,"Sound files need a simple file extension")
  local file=assert(io.open(full,"rb"),"Could not read a referenced sound: "..path)
  local size=file:seek("end");if not size or size>32*1024*1024 then file:close();error("A sound file exceeds the 32 MiB limit") end
  file:seek("set",0);local body=file:read(size+1);file:close();assert(body and #body==size,"Could not read the complete sound: "..path)
  total=total+size;assert(total<=128*1024*1024,"Sound files exceed the 128 MiB bundle limit")
  local target="pob-sound-"..require("sha1")(full):sub(1,20).."."..ext:lower()
  for _,entry in ipairs(files) do assert(entry.name:lower()~=target:lower(),"Sound filename collision") end
  assert(#files<256,"A sound bundle can contain at most 256 files")
  files[#files+1]={name=target,text=body};byPath[full]=target;return target
 end
 local rewritten={}
 for _,filter in ipairs(filters) do
 local lines={};local lineNumber=0
 for line,ending in filter.text:gmatch("([^\n]*)(\n?)") do
  if line=="" and ending=="" then break end
  lineNumber=lineNumber+1
  assert(not line:match("^%s*Import%s"),"Resolve all filter imports before bundling sounds")
  local prefix,value,suffix=line:match('^(%s*CustomAlertSoundOptional%s+)"([^"]*)"(.*)$')
  if not prefix then prefix,value,suffix=line:match('^(%s*CustomAlertSound%s+)"([^"]*)"(.*)$') end
  if prefix and value~="None" then
   local paths={};for part in (value..";"):gmatch("(.-);") do paths[#paths+1]=sound(part) end
   line=prefix..'"'..table.concat(paths,";")..'"'..suffix
  elseif not prefix then
   assert(not line:match("^%s*CustomAlertSound[%w]*%s"),"Use quoted custom sound paths before bundling (line "..lineNumber..")")
  end
  lines[#lines+1]=line..ending
 end
 rewritten[#rewritten+1]={name=filter.name,text=table.concat(lines)}
 end
 local count=#files;for _,file in ipairs(files) do rewritten[#rewritten+1]=file end
 return archive(rewritten),count
end
function M.soundBundle(profile,filename,raw,sourceDirectory)
 require("Modules.LootFilterFileNames").stem(profile,filename)
 assert(type(raw)=="string","Invalid filter")
 return soundBundle({{name=filename,text=raw}},sourceDirectory)
end
function M.soundBundleVariants(profile,filename,sourceDirectory)
 local names=require("Modules.LootFilterFileNames");names.stem(profile,filename)
 local files={};for _,file in ipairs(require("Modules.LootFilters").variants(profile)) do files[#files+1]={name=names.variant(profile,filename,file.strictness),text=file.text} end
 return soundBundle(files,sourceDirectory)
end
return M
