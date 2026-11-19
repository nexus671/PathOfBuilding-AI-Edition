-- Report provable priority conflicts. Do not guess overlap for different predicates.
local M={}
local parser=require("Modules.LootFilterParser")
local numeric=parser.numeric
local rarity={Normal=0,Magic=1,Rare=2,Unique=3}
local function number(condition)
 if #condition.values~=1 then return end
 if condition.keyword=="Rarity" then return rarity[condition.values[1]] end
 if numeric[condition.keyword] and condition.keyword~="Sockets" then return tonumber(condition.values[1]) end
end
-- Length prefixes keep arbitrary quoted values distinct without JSON-encoding
-- a new table for every value in every rule.
local function field(value) value=tostring(value);return #value..":"..value end
local function encoded(condition)
 local count=(condition.keyword=="HasExplicitMod" or condition.keyword=="HasEnchantment") and not (condition.quoted and condition.quoted[1]) and tonumber(condition.values[1])
 local values={};for i=count and 2 or 1,#condition.values do values[#values+1]=field(condition.values[i])..(condition.quoted and condition.quoted[i] and "1" or "0") end
 table.sort(values);return field(condition.keyword)..field(condition.operator)..field(count)..field(table.concat(values))
end
local function bound(condition)
 local op=condition.operator;local direction=(op==">" or op==">=") and "lower" or (op=="<" or op=="<=") and "upper"
 if not direction then return end
 local value=number(condition);if not value or value~=value or math.abs(value)==math.huge then return end
 -- Rarity has four discrete tiers. Strict comparisons at adjacent tiers are
 -- equivalent to inclusive comparisons at the next tier.
 if condition.keyword=="Rarity" and (op==">" or op=="<") then
  value=value+(op==">" and 1 or -1);return {direction=direction,value=value,inclusive=true}
 end
 return {direction=direction,value=value,inclusive=op==">=" or op=="<="}
end
local function covers(previous,current)
 if previous.value==current.value then return previous.inclusive or not current.inclusive end
 return current.direction=="lower" and previous.value<current.value or current.direction=="upper" and previous.value>current.value
end
-- Rarity is a finite domain, so compare its actual matching tiers instead of
-- guessing from the spelling of equality, exclusion or range expressions.
local function rarityChoices(condition)
 if condition.keyword~="Rarity" or #condition.values~=1 then return end
 local allowed={["="]=true,["=="]=true,["!"]=true,["!="]=true,[">"]=true,[">="]=true,["<"]=true,["<="]=true}
 if not allowed[condition.operator] then return end
 for _,value in ipairs(condition.values) do if rarity[value]==nil then return end end
 local values={};local count=0
 for _,name in ipairs({"Normal","Magic","Rare","Unique"}) do
  local result=parser.condition(condition,{Rarity=name})
  if result==nil then return end
  if result then values[name]=true;count=count+1 end
 end
 if count>0 then return values end
end
local function containsAll(earlier,later)
 for value in pairs(later) do if not earlier[value] then return false end end
 return true
end
-- Compare the intersection of bounds on one numeric property. This also
-- recognizes a range covering an exact value or a narrower two-sided range.
local function intervals(rule)
 local byKeyword={}
 for _,condition in ipairs(rule.conditions) do
  if condition.keyword~="Rarity" then
   local value=bound(condition)
   local exact=(condition.operator=="=" or condition.operator=="==") and number(condition)
   if exact and (exact~=exact or math.abs(exact)==math.huge) then exact=nil end
   if value or exact then
    local entry=byKeyword[condition.keyword] or {conditions={},lower=nil,upper=nil};byKeyword[condition.keyword]=entry
    entry.conditions[condition]=true
    local function add(b)
     local old=entry[b.direction]
     if not old or covers(old,b) then entry[b.direction]=b end
    end
    if value then add(value) else add({direction="lower",value=exact,inclusive=true});add({direction="upper",value=exact,inclusive=true}) end
   end
  end
 end
 local result={}
 for keyword,entry in pairs(byKeyword) do
  local lower,upper=entry.lower,entry.upper
  if not lower or not upper or lower.value<upper.value or lower.value==upper.value and lower.inclusive and upper.inclusive then
   local other={};for _,condition in ipairs(rule.conditions) do if not entry.conditions[condition] then other[#other+1]=encoded(condition) end end
   table.sort(other);local key=field(keyword);for _,value in ipairs(other) do key=key..field(value) end
   entry.group=key;result[#result+1]=entry
  end
 end
 return result
end
local function intervalCovers(earlier,later)
 return (not earlier.lower or later.lower and covers(earlier.lower,later.lower)) and (not earlier.upper or later.upper and covers(earlier.upper,later.upper))
end
function M.shadowing(parsed)
 local seen,thresholds,sets,combined,paired,diagnostics={},{},{},{},{},{};local rarityIndex,intervalIndex={},{};local terminal
 for _,rule in ipairs(parsed.rules) do
  local conditions,variants,pairsToIndex,rarityVariants={},{},{},{}
  if not terminal then for _,condition in ipairs(rule.conditions) do conditions[#conditions+1]=encoded(condition) end end
  table.sort(conditions);local parts={};for _,condition in ipairs(conditions) do parts[#parts+1]=field(condition) end
  local key=table.concat(parts);local prior=terminal or seen[key];local broader=false
  if not prior then
   -- A terminating rule whose conditions are a subset of this rule also
   -- covers it. Check removal of up to two conditions without an unbounded
   -- pairwise comparison over large imported filters.
   if #conditions<=16 then for first=1,#conditions do
    for second=first,#conditions do
     local other={}
     for index,value in ipairs(conditions) do
      if index~=first and (second==first or index~=second) then other[#other+1]=field(value) end
     end
     local candidate=seen[table.concat(other)]
     if candidate and (not prior or candidate.line<prior.line) then prior=candidate;broader=true end
    end
   end end
  end
  local intervalVariants=not prior and #conditions<=16 and intervals(rule) or {}
  if not prior then for _,entry in ipairs(intervalVariants) do
   for _,candidate in ipairs(intervalIndex[entry.group] or {}) do
    if intervalCovers(candidate,entry) and (not prior or candidate.rule.line<prior.line) then prior=candidate.rule;broader=true end
   end
  end end
  if not prior and #conditions<=16 then
   -- Match the finite rarity set on its own, with a class/base list, or with
   -- one numeric bound. Cap each bucket just like the other conflict indexes.
   for _,condition in ipairs(rule.conditions) do
    local choices=rarityChoices(condition)
    if choices then
     local function variant(other,kind,extra,bounds)
      local remaining,removedA,removedB={},false,not other
      local keyA,keyB=encoded(condition),other and encoded(other)
      for _,value in ipairs(conditions) do
       if not removedA and value==keyA then removedA=true
       elseif not removedB and value==keyB then removedB=true
       else remaining[#remaining+1]=field(value) end
      end
      local group=field(kind)..field(other and other.keyword)..field(bounds and bounds.direction)..table.concat(remaining)
      local entry={group=group,choices=choices,extra=extra,bound=bounds}
      for _,candidate in ipairs(rarityIndex[group] or {}) do
       if containsAll(candidate.choices,choices) and (not extra or containsAll(candidate.extra,extra)) and (not bounds or covers(candidate.bound,bounds))
        and (not prior or candidate.rule.line<prior.line) then prior=candidate.rule;broader=true end
      end
      rarityVariants[#rarityVariants+1]=entry
     end
     variant(nil,"rarity")
     for _,other in ipairs(rule.conditions) do if other~=condition then
      if (other.keyword=="BaseType" or other.keyword=="Class") and other.operator=="==" and #other.values>0 and #other.values<=256 then
       local values={};for _,value in ipairs(other.values) do values[value]=true end;variant(other,"rarity-list",values)
      elseif other.keyword~="Rarity" then local limit=bound(other);if limit then variant(other,"rarity-bound",nil,limit) end end
     end end
    end
   end
  end
  if not prior then
   -- Exact class and base-type lists are alternatives. If every value in the
   -- later list occurs in the earlier list, the earlier rule covers it. Keep
   -- candidate lists bounded for large imported filters.
   for _,condition in ipairs(rule.conditions) do
    if (condition.keyword=="BaseType" or condition.keyword=="Class") and condition.operator=="==" and #condition.values>0 and #condition.values<=256 and #conditions<=16 then
     local other,removed={},false;local target=encoded(condition)
     for _,value in ipairs(conditions) do if not removed and value==target then removed=true else other[#other+1]=field(value) end end
     local group=field(condition.keyword)..table.concat(other)
     for _,candidate in ipairs(sets[group] or {}) do
      local covered=true;for _,value in ipairs(condition.values) do if not candidate.values[value] then covered=false;break end end
      if covered and (not prior or candidate.rule.line<prior.line) then prior=candidate.rule;broader=true end
     end
    end
   end
  end
  if not prior then
   -- Combine one exact item-list comparison with one numeric bound. Index by
   -- all remaining conditions and cap candidates to bound imported-filter work.
   if #conditions<=16 then
    for _,list in ipairs(rule.conditions) do
     if (list.keyword=="BaseType" or list.keyword=="Class") and list.operator=="==" and #list.values>0 and #list.values<=256 then
      for _,limit in ipairs(rule.conditions) do
       local current=bound(limit)
       if current then
        local other,removedList,removedLimit={},false,false
        local listKey,limitKey=encoded(list),encoded(limit)
        for _,value in ipairs(conditions) do
         if not removedList and value==listKey then removedList=true
         elseif not removedLimit and value==limitKey then removedLimit=true
         else other[#other+1]=field(value) end
        end
        local group=field(list.keyword)..field(limit.keyword)..field(current.direction)..table.concat(other)
        for _,candidate in ipairs(combined[group] or {}) do
         local covered=covers(candidate.bound,current)
         if covered then for _,value in ipairs(list.values) do if not candidate.values[value] then covered=false;break end end end
         if covered and (not prior or candidate.rule.line<prior.line) then prior=candidate.rule;broader=true end
        end
       end
      end
     end
    end
   end
  end
  if not prior then
   -- Two numeric bounds may both narrow while all other conditions stay the
   -- same. Bound the index and skip repeated signatures to avoid ambiguity.
   local limits={}
   if #conditions<=16 then for _,condition in ipairs(rule.conditions) do
    local value=bound(condition)
    if value then limits[#limits+1]={condition=condition,bound=value,signature=field(condition.keyword)..field(value.direction)} end
   end end
   table.sort(limits,function(a,b) return a.signature<b.signature end)
   for first=1,#limits do for second=first+1,#limits do
    local a,b=limits[first],limits[second]
    if a.signature~=b.signature then
     local other,removedA,removedB={},false,false;local keyA,keyB=encoded(a.condition),encoded(b.condition)
     for _,value in ipairs(conditions) do
      if not removedA and value==keyA then removedA=true
      elseif not removedB and value==keyB then removedB=true
      else other[#other+1]=field(value) end
     end
     local group=field(a.signature)..field(b.signature)..table.concat(other)
     for _,candidate in ipairs(paired[group] or {}) do
      if covers(candidate.a,a.bound) and covers(candidate.b,b.bound) and (not prior or candidate.rule.line<prior.line) then prior=candidate.rule;broader=true end
     end
     pairsToIndex[#pairsToIndex+1]={group=group,a=a.bound,b=b.bound}
    end
   end end
  end
  if not prior then
   for _,condition in ipairs(rule.conditions) do
    local current=bound(condition)
    local exact=(condition.operator=="=" or condition.operator=="==") and number(condition)
    if exact and (exact~=exact or math.abs(exact)==math.huge) then exact=nil end
    if current or exact then
     local removed=false;local other={};local target=encoded(condition)
     for _,value in ipairs(conditions) do if not removed and value==target then removed=true else other[#other+1]=field(value) end end
     local function findCover(query)
      local group=field(condition.keyword)..field(query.direction)..table.concat(other)
      -- Stored bounds become progressively broader, so binary search finds
      -- the earliest covering predecessor without scanning the whole filter.
      local candidates=thresholds[group] or {};local low,high=1,#candidates
      while low<=high do local middle=math.floor((low+high)/2);if covers(candidates[middle].bound,query) then high=middle-1 else low=middle+1 end end
      local candidate=candidates[low]
      if candidate and (not prior or candidate.rule.line<prior.line) then prior=candidate.rule;broader=true end
      return group
     end
     if current then current.group=findCover(current);variants[#variants+1]=current
     else
      findCover({direction="lower",value=exact,inclusive=true})
      findCover({direction="upper",value=exact,inclusive=true})
     end
    end
   end
  end
  if prior then
   local explanation=broader and "matches every item matched by this block." or "matches the same conditions"..(terminal and " or every item." or ".")
   diagnostics[#diagnostics+1]={line=rule.line,shadowedBy=prior.line,warning="This block cannot be reached: a preceding terminating block at line "..prior.line.." "..explanation}
  elseif not rule.continue then
   seen[key]=rule;if #conditions==0 then terminal=rule end
   for _,entry in ipairs(intervalVariants) do
    local candidates=intervalIndex[entry.group] or {};intervalIndex[entry.group]=candidates
    if #candidates<32 then entry.rule=rule;candidates[#candidates+1]=entry end
   end
   for _,entry in ipairs(rarityVariants) do
    local candidates=rarityIndex[entry.group] or {};rarityIndex[entry.group]=candidates
    if #candidates<32 then entry.rule=rule;candidates[#candidates+1]=entry end
   end
   for _,pair in ipairs(pairsToIndex) do
    local candidates=paired[pair.group] or {};paired[pair.group]=candidates
    if #candidates<32 then candidates[#candidates+1]={rule=rule,a=pair.a,b=pair.b} end
   end
   if #conditions<=16 then for _,list in ipairs(rule.conditions) do
    if (list.keyword=="BaseType" or list.keyword=="Class") and list.operator=="==" and #list.values>0 and #list.values<=256 then
     for _,limit in ipairs(rule.conditions) do
      local current=bound(limit)
      if current then
       local other,removedList,removedLimit={},false,false
       local listKey,limitKey=encoded(list),encoded(limit)
       for _,value in ipairs(conditions) do
        if not removedList and value==listKey then removedList=true
        elseif not removedLimit and value==limitKey then removedLimit=true
        else other[#other+1]=field(value) end
       end
       local group=field(list.keyword)..field(limit.keyword)..field(current.direction)..table.concat(other)
       local candidates=combined[group] or {};combined[group]=candidates
       if #candidates<32 then local values={};for _,value in ipairs(list.values) do values[value]=true end;candidates[#candidates+1]={rule=rule,bound=current,values=values} end
      end
     end
    end
   end end
   for _,variant in ipairs(variants) do local group=thresholds[variant.group] or {};thresholds[variant.group]=group;group[#group+1]={rule=rule,bound=variant} end
   if #conditions<=16 then for _,condition in ipairs(rule.conditions) do
    if (condition.keyword=="BaseType" or condition.keyword=="Class") and condition.operator=="==" and #condition.values>0 and #condition.values<=256 then
     local other,removed={},false;local target=encoded(condition)
     for _,value in ipairs(conditions) do if not removed and value==target then removed=true else other[#other+1]=field(value) end end
     local group=field(condition.keyword)..table.concat(other);local candidates=sets[group] or {};sets[group]=candidates
     if #candidates<32 then local values={};for _,value in ipairs(condition.values) do values[value]=true end;candidates[#candidates+1]={rule=rule,values=values} end
    end
   end end
  end
 end
 return diagnostics
end
return M
