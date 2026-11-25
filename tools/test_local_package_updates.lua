-- Run against a fresh portable extraction built with --local-updates.
local xml=require("xml")
local manifest=assert(xml.LoadXMLFile("manifest.xml"))
local updates
for _,node in ipairs(manifest[1]) do
	if type(node)=="table" and node.elem=="Version" then updates=node.attrib.updates end
end
assert(updates=="local","Expected a local-update package")
local marker=assert(io.open("first.run","wb"))
marker:close()
dofile("HeadlessWrapper.lua")
assert(launch.localUpdates and not launch.devMode and not launch.installedMode)
assert(not launch.updateCheckRunning and not launch.updateMsg)
local untouched=assert(io.open("first.run","rb"),"First-run updater acted on the local package")
untouched:close()
os.remove("first.run")
LaunchSubScript=function() error("The updater started a network script") end
launch:CheckForUpdate()
launch:ApplyUpdate("program")
assert(not launch.updateCheckRunning and not launch.updateMsg and not launch.doRestart)
assert(not main.controls.checkUpdate:IsShown() and not main.controls.applyUpdate:IsShown())
print("Local app package skips startup and manual updates in portable mode")
