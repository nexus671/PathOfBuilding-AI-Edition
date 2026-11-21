-- Preserve the observed quality without guessing patch-specific effects.
local M={}
function M.validate(quality)
 if quality==nil then return nil end
 assert(type(quality)=="table" and type(quality.kind)=="string" and #quality.kind>=1 and #quality.kind<=80
  and quality.kind:match("^[%w '%-]+$"),"Invalid map quality type")
 assert(type(quality.value)=="number" and quality.value==math.floor(quality.value)
  and quality.value>=0 and quality.value<=100,"Map quality must be a whole number from 0 to 100")
 return {kind=quality.kind,value=quality.value}
end

-- Patch notes document these values at exactly 20% quality. Do not
-- extrapolate to other amounts or treat a "more" drop multiplier as additive.
function M.effect(quality)
 quality=M.validate(quality)
 if not quality then return nil end
 if quality.value~=20 then return {supported=false,note="Only effects at 20% quality are documented in this model."} end
 local kind=quality.kind:lower()
 if kind=="pack size" then return {supported=true,stat="packSize",value=10,text="+10% Monster Pack Size"} end
 if kind=="rarity" or kind=="item rarity" then return {supported=true,stat="rarity",value=25,text="+25% Item Rarity"} end
 -- 3.30 renamed the Scarab chisel but does not state its new magnitude.
 if kind=="threads" then return {supported=true,stat="threadQuantity",status="amount_unverified",text="Increased Thread quantity (amount unverified)"} end
 -- 3.28 documented this legacy effect. 3.30 replaced map modifier quantity
 -- with Atlas Drops, but does not establish how this quality type converts.
 if kind=="item quantity" or kind=="quantity" then return {supported=true,stat="legacyItemQuantity",value=10,status="historical",text="Historically +10% Item Quantity; current effect unverified"} end
 if kind=="currency" then return {supported=true,stat="currencyMore",value=50,text="50% more Currency"} end
 if kind=="divination cards" then return {supported=true,stat="divinationMore",value=50,text="50% more Divination Cards"} end
 return {supported=false,note="This quality type has no verified numerical effect in the model."}
end
return M
