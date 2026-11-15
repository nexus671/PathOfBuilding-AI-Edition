describe("3.30 client bench catalogue",function()
	local bench=require("Modules.CraftingBenchCosts")
	it("indexes current class-specific costs while accepting saved lock wording",function()
		local f=assert(io.open("Data/Crafting/3.30-bench.json","rb"));local raw=f:read("*a");f:close()
		local catalogue=assert(require("dkjson").decode(raw));assert.are.equal(782,#catalogue.bench)
		local lookup=bench.index(catalogue)
		local mod={"Prefixes Cannot Be Changed",level=1,type="Suffix"}
		local model={item={type="Ring",base={}},byId={["bench:728"]=mod}}
		local cost,sources=bench.cost(model,"bench:728",lookup)
		assert.are.same({["Metadata/Items/Currency/CurrencyModValues"]=4,["Metadata/Items/Currency/CurrencyAddModToRare"]=8},cost)
		assert.are.same({"StrMasterItemGenerationCannotChangePrefixesC"},sources)
		model.item.type="Body Armour"
		assert.are.same({["Metadata/Items/Currency/CurrencyModValues"]=4,["Metadata/Items/Currency/CurrencyRerollImplicit"]=4},bench.cost(model,"bench:728",lookup))
		model.item.type="Jewel";assert.is_nil(bench.cost(model,"bench:728",lookup))
	end)
end)
