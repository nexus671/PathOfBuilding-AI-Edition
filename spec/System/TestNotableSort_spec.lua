describe("Anoint notable sorting", function()
 before_each(function() newBuild() end)
 it("requests Full DPS only for that sort while preserving stat order", function()
  local calls={}
  local nodes={
   {id=1,dn="First",sd={},recipe={1},modKey="first"},
   {id=2,dn="Second",sd={},recipe={1},modKey="second"},
  }
  local tab={displayItem={base={type="Amulet"}},build={calcsTab={}}}
  function tab:anointItem(node) return node end
  function tab.build.calcsTab:GetMiscCalculator()
   return function(override,useFull)
    calls[#calls+1]=useFull
    local node=override.repItem
    return {Life=100+(node and node.id or 0),FullDPS=100+(node and 3-node.id or 0)}
   end
  end
  local control=new("NotableDBControl"):NotableDBControl(nil,{0,0,360,360},tab,nodes,"ANOINT")
  for _,case in ipairs({{stat="Life",flag=false,first=2},{stat="FullDPS",flag=true,first=1}}) do
   calls={};control:SetSortMode(case.stat)
   local job=coroutine.create(control.ListBuilder)
   repeat local ok,err=coroutine.resume(job,control);assert.is_true(ok,err) until coroutine.status(job)=="dead"
   assert.equal(3,#calls);for _,flag in ipairs(calls) do assert.equal(case.flag,flag) end
   assert.equal(case.first,control.list[1].id)
   assert.equal(2,control.list[1].measuredPower);assert.equal(1,control.list[2].measuredPower)
  end
 end)
end)
