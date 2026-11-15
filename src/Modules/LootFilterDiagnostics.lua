-- Report provable priority conflicts. Do not guess overlap for different predicates.
local M={}
local numeric=require("Modules.LootFilterParser").numeric
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
 if not direction or not numeric[condition.keyword] or condition.keyword=="Sockets" or #condition.values~=1 then return end
 local value=tonumber(condition.values[1]);if not value or value~=value or math.abs(value)==math.huge then return end
 return {direction=direction,value=value,inclusive=op==">=" or op=="<="}
end
local function covers(previous,current)
 if previous.value==current.value then return previous.inclusive or not current.inclusive end
 return current.direction=="lower" and previous.value<current.value or current.direction=="upper" and previous.value>current.value
end
function M.shadowing(parsed)
 local seen,thresholds,diagnostics={},{},{};local terminal
 for _,rule in ipairs(parsed.rules) do
  local conditions,variants={},{}
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
  if not prior then
   for _,condition in ipairs(rule.conditions) do
    local current=bound(condition)
    local exact=(condition.operator=="=" or condition.operator=="==") and numeric[condition.keyword]
     and condition.keyword~="Sockets" and #condition.values==1 and tonumber(condition.values[1])
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
   for _,variant in ipairs(variants) do local group=thresholds[variant.group] or {};thresholds[variant.group]=group;group[#group+1]={rule=rule,bound=variant} end
  end
 end
 return diagnostics
end
return M
