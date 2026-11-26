local alerts = require("Modules.LootFilterBackgroundAlerts")

local function check(before, after, expected)
	assert(alerts.countChanges({changes=before},{changes=after})==expected, "Unexpected managed-rule count")
end

local function copy(value)
	local result = {}
	for key, item in pairs(value) do result[key] = item end
	return result
end

local function with(value, fields)
	local result = copy(value)
	for key, item in pairs(fields) do result[key] = item end
	return result
end

local map = {name="Tier-wide",classes={"Maps"},scope="maps",old=1,cutoff=0}
local gem = {name="Added Cold Damage Support",classes={"Support Gems"},scope="all",old=1,cutoff=0,
	gemLevel=20,gemQuality=20}
local currency = {name="Orb of Alteration",classes={"Stackable Currency"},scope="all",old=6,cutoff=3}
local rows = {
	with(map,{tier=15,blighted=false,ravaged=false}), with(map,{tier=16,blighted=false,ravaged=false}),
	with(map,{tier=16,blighted=true,ravaged=false}), with(map,{tier=16,blighted=true,ravaged=true}),
	with(gem,{corrupted=false}), with(gem,{corrupted=true}), currency, with(currency,{scope="campaign"}),
}
check({},rows,8)
check(rows,{},8)
check(rows,rows,0)
check({}, {currency,currency},1)
check({currency},{with(currency,{retainedReason="Missing quote"})},0)
check({currency},{with(currency,{cutoff=2})},1)
check({currency},{with(currency,{uniqueBase=true})},2)
check({currency},{with(currency,{classes={"Stackable Currency","Stackable Currency"}})},0)

local first = {firstStack=20,icon="1 Yellow Circle"}
local strong = {firstStack=40,icon="0 Orange Star",actions={sound=4,fontSize=40}}
local highlight = with(currency,{cutoff=currency.old,highlights={first}})
local twoStyles = with(highlight,{highlights={first,strong}})
check({}, {highlight},1)
check({currency},{highlight},1)
check({highlight},{twoStyles},1)
check({twoStyles},{with(twoStyles,{highlights={strong,first}})},0)
check({twoStyles},{with(twoStyles,{highlights={first,with(strong,{actions={sound=4,volume=50,fontSize=40}})}})},0)
for _, style in ipairs({
	with(strong,{firstStack=39}), with(strong,{icon="0 Red Star"}),
	with(strong,{actions={sound=4,volume=0,fontSize=40}}), with(strong,{actions={sound=4,fontSize=45}}),
}) do
	check({twoStyles},{with(twoStyles,{highlights={first,style}})},1)
end
check({highlight},{with(twoStyles,{cutoff=2})},1)

local baseline = {enabled=true,backgroundEnabled=true,backgroundNotifications=true,current="before",
	lastSuccess=100,revision="same",review={protectedChecks=600,changes={}}}
local appearanceOnly = {}
for index=1,5 do appearanceOnly[index] = with(highlight,{name="Fixture "..index}) end
local changed = with(baseline,{current="after",lastSuccess=200,review={protectedChecks=600,changes=appearanceOnly}})

local function summarize(previous, current, failed)
	return alerts.summarize({configuration=function() return current end},{default=previous},failed)
end

local text, failed = summarize(baseline,changed,false)
assert(text:find("^5 managed loot rules changed") and failed==false)
assert(not summarize(baseline,with(changed,{review={protectedChecks=0,changes=appearanceOnly}}),false))
assert(not summarize(baseline,with(changed,{revision="different"}),false))
assert(not summarize(baseline,with(changed,{backgroundNotifications=false}),false))
table.remove(appearanceOnly)
assert(not summarize(baseline,changed,false))
local failure = with(baseline,{lastFailure={message="The provider is temporarily unavailable"}})
text, failed = summarize(baseline,failure,true)
assert(text:find("^A scheduled update failed") and failed)
assert(not summarize(failure,failure,true))
assert(not summarize(baseline,failure,false))

print("Background alerts preserve visibility and appearance counting and honor profile opt-in.")
