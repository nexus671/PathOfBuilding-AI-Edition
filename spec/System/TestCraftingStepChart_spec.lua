describe("Crafting step spending chart",function()
	local UI=require("Modules.HeadlessUI")
	local function text(ui)
		local out={};for _,command in ipairs(ui.commands) do if command.kind=="text" then out[#out+1]=command.text end end;return table.concat(out," ")
	end
	before_each(function() newBuild();main.popups={} end)
	after_each(function() main.popups={} end)
	it("pages all visited steps and keeps unavailable prices separate",function()
		local ui=UI.install({width=960,height=640});ui:bind(build)
		local counts,steps={},{};for i=1,10 do counts[i]={pricedCost=i*2,unpricedComponents=0};steps[i]={method="alchemy"} end
		counts[2].unpricedComponents=1
		local c=require("Classes.CraftingStepCostsControl").Open({{label="First",recipe={steps=steps},result={trials=2,costCurrency="chaos",routeCounts=counts}},{label="Second",result={trials=1,costCurrency="divine",routeCounts={[1]={pricedCost=3,unpricedComponents=0}}}}})
		ui:frame();local first=text(ui);assert.is_truthy(first:find("Step 1: Orb of Alchemy",1,true));assert.is_truthy(first:find("1.00 chaos",1,true));assert.is_truthy(first:find("Unavailable: missing prices",1,true))
		assert.is_true(c.next:IsEnabled());ui:click("next");ui:frame();assert.is_truthy(text(ui):find("Step 10",1,true));assert.is_false(c.next:IsEnabled())
		c.route:SelByValue(2,"val");c.route.selFunc();ui:frame();assert.is_truthy(text(ui):find("3.00 divine",1,true));assert.is_false(c.previous:IsEnabled())
		ui:bind(nil)
	end)
end)
