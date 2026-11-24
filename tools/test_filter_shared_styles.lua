arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local shared=require("Modules.LootFilterSharedStyles")
local raw=[[# untouched
Show
 SetTextColor 255 0 0 # red
 SetBackgroundColor 0 0 0
 PlayAlertSound 2 200 # alert
 CustomAlertSound "C:\sounds\a#1.wav" 100
Hide
 SetTextColor 0 255 0 255
Import "other.filter"
 SetTextColor 255 0 0
]]
local entries={
	{key="SetTextColor",from="FF0000FF",to="00FF00FF"},
	{key="SetTextColor",from="00FF00FF",to="0000FFFF"},
	{key="SetBackgroundColor",from="000000F0",to="11223344"},
	{key="PlayAlertSound",from="2",to="6"},
	{key="CustomAlertSound",from="C:\\sounds\\a#1.wav",to="C:\\sounds\\b.wav"},
}
local before=shared.list(raw);assert(#before==5,"Unexpected shared style inventory")
local result=shared.apply(raw,entries)
assert(result:find("SetTextColor 0 255 0 255 # red",1,true),"Replacement lost the comment or chained into another mapping")
assert(result:find("SetTextColor 0 0 255 255",1,true),"Second source was not replaced")
assert(result:find("SetBackgroundColor 17 34 51 68",1,true),"Background default alpha was not matched")
assert(result:find("PlayAlertSound 6 200 # alert",1,true),"Alert volume or comment was lost")
assert(result:find('CustomAlertSound "C:\\sounds\\b.wav" 100',1,true),"Quoted custom sound was not preserved")
assert(result:find('Import "other.filter"\n SetTextColor 255 0 0',1,true),"An import's contents were changed without loading it")
assert(shared.apply(raw,{})==raw,"Empty mappings changed the filter")
assert(not pcall(shared.validate,{{key="SetTextColor",from="FF0000FF",to="00FF00FF"},{key="SetTextColor",from="FF0000FF",to="FFFFFFFF"}}),"Duplicate sources were accepted")
print("FILTER_SHARED_STYLES_OK")
