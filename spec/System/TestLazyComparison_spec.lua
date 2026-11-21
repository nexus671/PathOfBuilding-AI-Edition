describe("Deferred comparison calculator", function()
	local tab, original, calls
	before_each(function()
		newBuild();runCallback("OnFrame");tab=build.calcsTab;original=tab.calcs.getMiscCalculator;calls=0
		tab.calcs.getMiscCalculator=function(...) calls=calls+1;return original(...) end
	end)
	after_each(function() tab.calcs.getMiscCalculator=original end)
	it("creates one fresh calculator on demand after each build update", function()
		build.buildFlag=true;runCallback("OnFrame")
		assert.equal(0,calls);assert.is_nil(build.configTab.calcFunc);assert.is_nil(build.configTab.calcBase)
		local calc,base=tab:GetMiscCalculator();assert.equal(1,calls);assert.is_truthy(base.Life)
		local again,againBase=tab:GetMiscCalculator();assert.equal(1,calls);assert.equal(calc,again);assert.equal(base,againBase)
		local output=calc();assert.equal(base.Life,output.Life)
		build.configTab.calcFunc,build.configTab.calcBase=calc,base
		build.characterLevel=math.max(1,build.characterLevel-1);build.buildFlag=true;runCallback("OnFrame")
		assert.equal(1,calls);assert.is_nil(build.configTab.calcFunc);assert.is_nil(build.configTab.calcBase)
		local fresh,freshBase=tab:GetMiscCalculator();assert.equal(2,calls);assert.is_true(fresh~=calc);assert.is_true(freshBase~=base)
		assert.equal(freshBase.Life,fresh().Life)
	end)
end)
