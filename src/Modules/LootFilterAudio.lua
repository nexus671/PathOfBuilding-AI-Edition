-- cspell:ignore hmod winmm
-- Original reference tones; game-native alert IDs play the game's sounds on export.
local M={}
function M.alert(styles)
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
-- Scale the bundled 16-bit PCM reference tone without changing system volume.
function M.scaleReferenceWave(raw,volume)
	assert(type(raw)=="string" and raw:sub(1,4)=="RIFF" and raw:sub(9,12)=="WAVE","Invalid reference audio")
	assert(type(volume)=="number" and volume==volume and volume>=0 and volume<=300,"Invalid reference volume")
	local function u16(i) local a,b=raw:byte(i,i+1);assert(b,"Truncated reference audio");return a+b*256 end
	local function u32(i) return u16(i)+u16(i+2)*65536 end
	local offset,valid=13,false
	while offset+7<=#raw do
		local kind=raw:sub(offset,offset+3);local size=u32(offset+4);local start=offset+8;local last=start+size-1
		assert(last<=#raw,"Truncated reference audio")
		if kind=="fmt " then
			assert(size>=16 and u16(start)==1 and u16(start+14)==16,"Unsupported reference audio format");valid=true
		elseif kind=="data" then
			assert(valid and size%2==0,"Unsupported reference audio format")
			local samples={};local gain=volume/100
			for i=start,last,2 do
				local sample=u16(i);if sample>=32768 then sample=sample-65536 end
				local scaled=sample*gain;scaled=scaled<0 and math.ceil(scaled) or math.floor(scaled)
				scaled=math.max(-32768,math.min(32767,scaled));if scaled<0 then scaled=scaled+65536 end
				samples[#samples+1]=string.char(scaled%256,math.floor(scaled/256))
			end
			return raw:sub(1,start-1)..table.concat(samples)..raw:sub(last+1)
		end
		offset=last+1+size%2
	end
	error("Missing reference audio samples")
end
-- Prepare only explicitly selected local WAV files; relative game paths are preserved.
function M.prepareCustomWave(path,volume)
	if type(path)~="string" then return nil,"No custom sound path is configured." end
	path=path:match("^[^;]*") or ""
	path=path:match("^%s*(.-)%s*$")
	if path:find("[%z\r\n]") or not (path:match("^%a:[/\\]") or path:sub(1,2)=="\\\\" or path:sub(1,1)=="/") then
		return nil,"Choose an absolute WAV path for preview; relative paths remain in the exported filter."
	end
	if not path:lower():match("%.wav$") then return nil,"Custom preview supports 16-bit PCM WAV files; the original path is preserved." end
	volume=tonumber(volume) or 100
	if volume~=volume or volume<0 or volume>300 then return nil,"Custom sound volume must be between 0 and 300." end
	if volume==0 then return nil,"The custom alert volume is zero." end
	local file=io.open(path,"rb");if not file then return nil,"Could not open the custom sound file; optional fallback is not previewed." end
	local size=file:seek("end")
	if not size or size>2*1024*1024 or not file:seek("set",0) then file:close();return nil,"Custom WAV preview is limited to files of 2 MiB or less." end
	local raw=file:read("*a");file:close()
	local ok,wave=pcall(M.scaleReferenceWave,raw,volume)
	if not ok then return nil,"Custom preview requires a valid 16-bit PCM WAV file." end
	return wave,"Playing the first custom WAV at the selected preview volume."
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
function M.play(styles)
	local custom=styles.CustomAlertSound or styles.CustomAlertSoundOptional
	if custom and custom[1]~="None" then
		local wave,message=M.prepareCustomWave(custom[1],custom[2]);if not wave then return false,message end
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
