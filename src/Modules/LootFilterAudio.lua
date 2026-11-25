-- cspell:ignore hmod winmm
-- Original reference tones; game-native alert IDs play the game's sounds on export.
local M={}
local function ambiguity(styles)
	if styles.CustomAlertSound and styles.CustomAlertSoundOptional then
		return "Both custom alert modes are present; their precedence needs in-game verification."
	end
	local custom=styles.CustomAlertSound or styles.CustomAlertSoundOptional
	if custom and custom[1]=="None" and (styles.PlayAlertSound or styles.PlayAlertSoundPositional) then
		return "A disabled custom alert and a numbered alert are both present; their interaction needs in-game verification."
	end
end
function M.alert(styles)
	local uncertain=ambiguity(styles);if uncertain then return nil,uncertain end
	local custom=styles.CustomAlertSound or styles.CustomAlertSoundOptional
	if custom then
		if custom[1]=="None" then return nil,"The custom alert is disabled; no custom audio is previewed." end
		if styles.CustomAlertSoundOptional and not styles.CustomAlertSound then
			local fallback=styles.PlayAlertSound or styles.PlayAlertSoundPositional
			if fallback and fallback[1]~="None" and tonumber(fallback[2])~=0 then return nil,"Optional custom audio may fall back to a numbered alert if its file is missing. Use Preview sound for a local WAV." end
			if tonumber(custom[2])==0 then return nil,"The custom alert volume is zero." end
			return nil,"Optional custom audio plays only if its file is available. Use Preview sound for a local WAV."
		end
		if tonumber(custom[2])==0 then return nil,"The custom alert volume is zero." end
		return nil,"Custom audio overrides numbered alerts. Use Preview sound for a local WAV."
	end
	if styles.PlayAlertSound and styles.PlayAlertSoundPositional then return nil,"Both numbered alert modes are present in the same block; the effective sound is not verified." end
	local values=styles.PlayAlertSound or styles.PlayAlertSoundPositional
	if not values then return nil,"No numbered alert is configured. Custom sound files are preserved on export." end
	if values[1]=="None" then return nil,"The numbered alert is disabled." end
	local id=tonumber(values[1]);if not id or id<1 or id>16 or id~=math.floor(id) then return nil,"No reference tone for this alert." end
	if tonumber(values[2])==0 then return nil,"The numbered alert volume is zero." end
	return id
end
-- Describe the two independent drop-sound flags without assuming optional
-- custom files are present or interpreting undocumented action arguments.
function M.dropSound(styles)
	local disable,enable=styles.DisableDropSound,styles.EnableDropSound
	local conditional,restore=styles.DisableDropSoundIfAlertSound,styles.EnableDropSoundIfAlertSound
	if not (disable or enable or conditional or restore) then return nil end
	if disable and enable or conditional and restore then return "Drop sound: conflicting settings in one block." end
	for _,value in ipairs({disable or enable or {},conditional or restore or {}}) do
		if #value>0 then return "Drop sound: action arguments need in-game verification." end
	end
	if disable then return "Drop sound: disabled." end
	if conditional then return "Drop sound: disabled when an alert is specified; optional files may be missing." end
	return "Drop sound: enabled."
end
-- Scale integer PCM samples without changing system volume or WAV metadata.
function M.scaleReferenceWave(raw,volume)
	assert(type(raw)=="string" and raw:sub(1,4)=="RIFF" and raw:sub(9,12)=="WAVE","Invalid reference audio")
	assert(type(volume)=="number" and volume==volume and volume>=0 and volume<=300,"Invalid reference volume")
	local function u16(i) local a,b=raw:byte(i,i+1);assert(b,"Truncated reference audio");return a+b*256 end
	local function u32(i) return u16(i)+u16(i+2)*65536 end
	local limit=u32(5)+8;assert(limit>=12 and limit<=#raw,"Truncated reference audio")
	local offset,bits,alignment=13
	while offset+7<=limit do
		local kind=raw:sub(offset,offset+3);local size=u32(offset+4);local start=offset+8;local last=start+size-1
		assert(last+size%2<=limit,"Truncated reference audio")
		if kind=="fmt " then
			assert(size>=16 and u16(start)==1,"Unsupported reference audio format")
			local channels=u16(start+2);bits=u16(start+14);alignment=u16(start+12)
			assert(channels>0 and (bits==8 or bits==16 or bits==24 or bits==32) and alignment==channels*bits/8,"Unsupported reference audio format")
		elseif kind=="data" then
			assert(bits and size%alignment==0,"Unsupported reference audio format")
			local samples,chunks={},{};local bytes=bits/8;local midpoint=2^(bits-1);local range=midpoint*2;local gain=volume/100
			for i=start,last,bytes do
				local sample=0;for j=0,bytes-1 do sample=sample+raw:byte(i+j)*2^(8*j) end
				if bits==8 then sample=sample-midpoint elseif sample>=midpoint then sample=sample-range end
				local scaled=sample*gain;scaled=scaled<0 and math.ceil(scaled) or math.floor(scaled)
				scaled=math.max(-midpoint,math.min(midpoint-1,scaled))
				if bits==8 then scaled=scaled+midpoint elseif scaled<0 then scaled=scaled+range end
				local out={};for j=0,bytes-1 do out[#out+1]=string.char(math.floor(scaled/2^(8*j))%256) end
				samples[#samples+1]=table.concat(out)
				if #samples==4096 then chunks[#chunks+1]=table.concat(samples);samples={} end
			end
			chunks[#chunks+1]=table.concat(samples)
			return raw:sub(1,start-1)..table.concat(chunks)..raw:sub(last+1)
		end
		offset=last+1+size%2
	end
	error("Missing reference audio samples")
end
-- Prepare only explicitly selected local WAV files; relative game paths are preserved.
function M.customPaths(value,limit)
	local result={};if type(value)~="string" then return result end
	for path in (value..";"):gmatch("(.-);") do path=path:match("^%s*(.-)%s*$");if path~="" then result[#result+1]=path;if limit and #result>=limit then break end end end
	return result
end
function M.prepareCustomWave(path,volume,index)
	if type(path)~="string" then return nil,"No custom sound path is configured." end
	index=index or 1
	if type(index)~="number" or index<1 or index~=math.floor(index) then return nil,"Choose a custom sound file to preview." end
	local paths=M.customPaths(path,index);if not paths[index] then return nil,"Choose a custom sound file to preview." end
	path=paths[index]
	if path:find("[%z\r\n]") or not (path:match("^%a:[/\\]") or path:sub(1,2)=="\\\\" or path:sub(1,1)=="/") then
		return nil,"Choose an absolute WAV path for preview; relative paths remain in the exported filter."
	end
	if not path:lower():match("%.wav$") then return nil,"Custom preview supports integer PCM WAV files; the original path is preserved." end
	volume=tonumber(volume) or 100
	if volume~=volume or volume<0 or volume>300 then return nil,"Custom sound volume must be between 0 and 300." end
	if volume==0 then return nil,"The custom alert volume is zero." end
	local file=io.open(path,"rb");if not file then return nil,"Could not open the custom sound file; optional fallback is not previewed." end
	local size=file:seek("end")
	if not size or size>2*1024*1024 or not file:seek("set",0) then file:close();return nil,"Custom WAV preview is limited to files of 2 MiB or less." end
	local raw=file:read("*a");file:close()
	local ok,wave=pcall(M.scaleReferenceWave,raw,volume)
	if not ok then return nil,"Custom preview requires a valid 8-, 16-, 24- or 32-bit integer PCM WAV file." end
	return wave,"Playing the selected custom WAV at the selected preview volume."
end
local function playWave(wave,message)
	local ffi=require("ffi");if ffi.os~="Windows" then return false,"Audio preview is available on Windows." end
	pcall(ffi.cdef,"int __stdcall PlaySoundA(const char *pszSound, void *hmod, unsigned int fdwSound);")
	local ok,sound=pcall(ffi.load,"winmm");if not ok then return false,"Could not load Windows audio preview." end
	local buffer=ffi.new("char[?]",#wave+1);ffi.copy(buffer,wave,#wave)
	-- Keep the previous buffer alive until PlaySound replaces it.
	if sound.PlaySoundA(buffer,nil,0x00000007)==0 then return false,"Could not play the sound preview." end
	M.buffer=buffer;M.library=sound
	return true,message
end
function M.play(styles,customIndex)
	local uncertain=ambiguity(styles);if uncertain then return false,uncertain end
	local custom=styles.CustomAlertSound or styles.CustomAlertSoundOptional
	if custom and custom[1]~="None" then
		local wave,message=M.prepareCustomWave(custom[1],custom[2],customIndex);if not wave then return false,message end
		return playWave(wave,message)
	end
	local id,why=M.alert(styles);if not id then return false,why end
	local root=GetScriptPath();local filename=(root~="" and root.."/" or "").."Assets/LootFilters/alert-"..id..".wav"
	local file=io.open(filename,"rb");if not file then return false,"Could not load the reference tone." end
	local raw=file:read("*a");file:close()
	local values=styles.PlayAlertSound or styles.PlayAlertSoundPositional;local volume=tonumber(values[2]) or 50
	local ok,wave=pcall(M.scaleReferenceWave,raw,volume);if not ok then return false,"Could not prepare the reference tone." end
	M.filename=filename
	return playWave(wave,"Playing a volume-adjusted reference tone for alert "..id..". The game's exact sound plays in game.")
end
return M
