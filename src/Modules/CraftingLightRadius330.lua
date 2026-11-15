-- Preserve pre-3.30 Light Radius values while using the current native ranges.
local M={ranges={LightRadiusAndAccuracy1="10-15",LightRadiusAndAccuracy2="16-20",LightRadiusAndAccuracy3="21-30",
	LightRadiusAndAccuracyNew1="10-15",LightRadiusAndAccuracyNew2="16-20",
	LocalLightRadiusAndAccuracy1="10-15",LocalLightRadiusAndAccuracy2="16-20",LocalLightRadiusAndAccuracy3="10-15",
	LocalLightRadiusAndAccuracyNew1_="16-20",LocalLightRadiusAndAccuracyNew2="21-30"}}
local legacyValues={LightRadiusAndAccuracy1=5,LightRadiusAndAccuracy2=10,LightRadiusAndAccuracy3=15,
	LightRadiusAndAccuracyNew1=5,LightRadiusAndAccuracyNew2=10,
	LocalLightRadiusAndAccuracy1=5,LocalLightRadiusAndAccuracy2=10,LocalLightRadiusAndAccuracy3=15,
	LocalLightRadiusAndAccuracyNew1_=5,LocalLightRadiusAndAccuracyNew2=10}

function M.prepare(model)
	model.legacyLightRadius={}
	for id,range in pairs(M.ranges) do
		local old=model.byId[id]
		if old then
			local current,legacy=copyTable(old),copyTable(old);local changed=0
			for index,line in ipairs(old) do
				local fixed=legacyValues[id].."% increased Light Radius";local updated="("..range..")% increased Light Radius"
				if line==fixed or line==updated then current[index]=updated;legacy[index]=fixed;changed=changed+1 end
			end
			assert(changed==1,"Unexpected Light Radius modifier data: "..id)
			if current.tradeHashes and current.tradeHashes[1263695895] then current.tradeHashes[1263695895]={"("..range..")% increased Light Radius"} end
			if legacy.tradeHashes and legacy.tradeHashes[1263695895] then legacy.tradeHashes[1263695895]={legacyValues[id].."% increased Light Radius"} end
			model.legacyLightRadius[id]=legacy;model.byId[id]=current
		end
	end
	for _,entry in ipairs(model.mods) do if model.legacyLightRadius[entry.id] then entry.mod=model.byId[entry.id] end end
end
return M
