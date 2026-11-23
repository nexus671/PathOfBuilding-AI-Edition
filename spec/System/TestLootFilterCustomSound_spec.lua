describe("Custom filter sound preview",function()
 local audio=require("Modules.LootFilterAudio")
 local path
 before_each(function() path=os.tmpname()..".wav" end)
 after_each(function() os.remove(path);os.remove(path.."-second.wav") end)
 it("prepares the first WAV at the chosen volume",function()
  local source=assert(io.open("Assets/LootFilters/alert-1.wav","rb"));local raw=source:read("*a");source:close()
  local file=assert(io.open(path,"wb"));file:write(raw);file:close()
  local wave=assert(audio.prepareCustomWave(path..";other.wav",100));assert.equal(raw,wave)
  local quieter=assert(audio.prepareCustomWave(path,50));assert.is_not.equal(raw,quieter)
 end)
 it("prepares a selected WAV from a list without changing its order",function()
  local first=assert(io.open("Assets/LootFilters/alert-1.wav","rb"));local one=first:read("*a");first:close()
  local second=assert(io.open("Assets/LootFilters/alert-2.wav","rb"));local two=second:read("*a");second:close()
  local a=assert(io.open(path,"wb"));a:write(one);a:close();local b=assert(io.open(path.."-second.wav","wb"));b:write(two);b:close()
  local list=path..";"..path.."-second.wav";assert.equal(two,assert(audio.prepareCustomWave(list,100,2)));assert.equal(one,assert(audio.prepareCustomWave(list,100,1)))
  local missing,reason=audio.prepareCustomWave(list,100,3);assert.is_nil(missing);assert.matches("Choose",reason)
 end)
 it("scales integer PCM samples of different widths and rejects malformed frames",function()
  local function u16(n) return string.char(n%256,math.floor(n/256)%256) end
  local function u32(n) return u16(n%65536)..u16(math.floor(n/65536)) end
  local function wave(bits, samples, channels, format)
   channels=channels or 1;local align=channels*bits/8
   local fmt=u16(format or 1)..u16(channels)..u32(44100)..u32(44100*align)..u16(align)..u16(bits)
   local data="fmt "..u32(#fmt)..fmt.."data"..u32(#samples)..samples..(#samples%2==1 and "\0" or "")
   return "RIFF"..u32(#data+4).."WAVE"..data
  end
  local cases={
   {8,string.char(0,128,255),string.char(64,128,191)},
   {16,string.char(0,128,0,0,255,127),string.char(0,192,0,0,255,63)},
   {24,string.char(0,0,128,0,0,0,255,255,127),string.char(0,0,192,0,0,0,255,255,63)},
   {32,string.char(0,0,0,128,0,0,0,0,255,255,255,127),string.char(0,0,0,192,0,0,0,0,255,255,255,63)},
  }
  for _,case in ipairs(cases) do
   local input=wave(case[1],case[2]);assert.equal(input,audio.scaleReferenceWave(input,100))
   assert.equal(wave(case[1],case[3]),audio.scaleReferenceWave(input,50))
  end
  local loud=wave(8,string.char(0,255));assert.equal(loud,audio.scaleReferenceWave(loud,300))
  assert.has_error(function() audio.scaleReferenceWave(wave(16,"\0",2),100) end)
  assert.has_error(function() audio.scaleReferenceWave(wave(32,"\0\0\0\0",1,3),100) end)
  local truncated=wave(24,"\0\0\0");assert.has_error(function() audio.scaleReferenceWave(truncated:sub(1,-2),100) end)
 end)
 it("reports unsupported paths, missing files, invalid WAVs and zero volume",function()
  local wave,why=audio.prepareCustomWave("relative.wav",100);assert.is_nil(wave);assert.matches("absolute",why)
  wave,why=audio.prepareCustomWave(path..".mp3",100);assert.is_nil(wave);assert.matches("WAV",why)
  wave,why=audio.prepareCustomWave(path,0);assert.is_nil(wave);assert.matches("zero",why)
  wave,why=audio.prepareCustomWave(path,100);assert.is_nil(wave);assert.matches("Could not open",why)
  local file=assert(io.open(path,"wb"));file:write("not a wave");file:close()
  wave,why=audio.prepareCustomWave(path,100);assert.is_nil(wave);assert.matches("valid",why)
 end)
 it("filters the browser without changing its default filter behavior",function()
  local browser=require("Classes.LootFilterFileBrowser");local saved=_G.NewFileSearch
  _G.NewFileSearch=function(_,folders)
   local names=folders and {"folder"} or {"sound.WAV","loot.filter","notes.txt"};local index=1
   return {GetFileName=function() return names[index] end,NextFile=function() index=index+1;return index<=#names end,Close=function() end}
  end
  local ok,err=pcall(function()
   local sounds=browser.entries("C:/",{accept=function(name) return name:lower():match("%.wav$")~=nil end,itemLabel="Sound",category="Sounds"})
   assert.equal(2,#sounds);assert.equal("Sound: sound.WAV",sounds[2].label)
   local filters=browser.entries("C:/");assert.equal(2,#filters);assert.equal("Filter: loot.filter",filters[2].label)
  end)
  _G.NewFileSearch=saved;assert.is_true(ok,err)
 end)
 it("limits the size of local audio",function()
  local file=assert(io.open(path,"wb"));file:seek("set",2*1024*1024);file:write("x");file:close()
  local wave,why=audio.prepareCustomWave(path,100);assert.is_nil(wave);assert.matches("2 MiB",why)
 end)
end)
