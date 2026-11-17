-- Empirical cumulative curves; failed/capped trials remain in the denominator.
local M={modes={"Success by attempts","Attempts per trial","Success by spending","Spending per trial","Success by executed actions","Executed actions per trial"}}
function M.series(routes,mode)
	local spending=mode==M.modes[3] or mode==M.modes[4];local executed=mode==M.modes[5] or mode==M.modes[6]
	local success=mode==M.modes[1] or mode==M.modes[3] or mode==M.modes[5] or mode=="Success by action count"
	local series={};local currency;local omitted={};local maximum=0;local warnings={};local hasTransitionErrors=false
	for _,route in ipairs(routes) do local result=route.result
		if result then
			local notes={};for _,warning in ipairs(result.warnings or {}) do notes[#notes+1]=warning.message;warnings[#warnings+1]=route.label..": "..warning.message end
			local failed=0;for _,count in pairs(result.transitionErrors or {}) do failed=failed+count end
			if failed>0 then
				hasTransitionErrors=true;local note=failed.." failed modeled transitions were not charged. The curves include the affected trials."
				notes[#notes+1]=note;warnings[#warnings+1]=route.label..": "..note
			end
			local buckets=spending and result.costDistribution or executed and result.executedActionDistribution or result.actionDistribution
			if spending and not result.costDistribution then omitted[#omitted+1]=route.label..": missing prices"
			elseif executed and not result.executedActionDistribution then omitted[#omitted+1]=route.label..": executed-action counts unavailable; rerun the simulation"
			elseif spending and currency and currency~=result.costCurrency then omitted[#omitted+1]=route.label..": different price unit"
			else
				if spending then currency=result.costCurrency end
				local points={};local count=0;local key=spending and "cost" or "actions"
				for _,bucket in ipairs(buckets or {}) do count=count+(success and bucket.successes or bucket.trials);points[#points+1]={x=bucket[key],y=count/result.trials*100,count=count,trials=result.trials};maximum=math.max(maximum,bucket[key]) end
				series[#series+1]={label=route.label,points=points,result=result,notes=notes,failedTransitions=result.transitionErrors and failed or nil}
			end
		end
	end
	return {series=series,mode=mode,maximum=maximum,unit=spending and (currency or "supplied price units") or executed and "executed actions" or "attempts",omitted=omitted,warnings=warnings,hasTransitionErrors=hasTransitionErrors,success=success,
		note=success and "Successes within the captured trial budget / all trials. No extrapolation or guaranteed success." or "Completed trials at or below each value, including failures and capped trials. Not a cost of guaranteed success."}
end
function M.at(points,x)
	local found={x=0,y=0,count=0,trials=points[1] and points[1].trials or 0}
	for _,point in ipairs(points) do if point.x>x then break end;found=point end
	return found
end
function M.csv(data)
	local lines={"route,value,percent,count,trials,mode,unit,failed_modeled_transitions,model_notes,omitted_routes,chart_note"}
	local function quoted(value) return '"'..tostring(value or ""):gsub('"','""')..'"' end
	for _,series in ipairs(data.series) do for _,point in ipairs(series.points) do
		lines[#lines+1]=string.format('%s,%.12g,%.12g,%d,%d,%s,%s,%s,%s,%s,%s',quoted(series.label),point.x,point.y,point.count,point.trials,
			quoted(data.mode),quoted(data.unit),series.failedTransitions==nil and "" or tostring(series.failedTransitions),quoted(table.concat(series.notes or {},"\n")),quoted(table.concat(data.omitted or {},"\n")),quoted(data.note))
	end end
	-- Keep omission and chart context available even when no route can be plotted.
	if #lines==1 then lines[2]=table.concat({quoted(""),"","","","",quoted(data.mode),quoted(data.unit),"",quoted(""),quoted(table.concat(data.omitted or {},"\n")),quoted(data.note)},",") end
	return table.concat(lines,"\n")
end
return M
