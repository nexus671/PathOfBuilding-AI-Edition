describe("Update release notes",function()
 local notes=require("Modules.UpdateNotes")
 local text="VERSION[2.68.1-ai.preview546][date]\nFix updater\nVERSION[2.68.1-ai.preview545][date]\nPicker\nVERSION[2.68.1-ai.preview544][date]\nBudget\nVERSION[ai][date]\nOld shared notes\n"
 local function display(installed,target,source) return table.concat(notes.describe(source or text,installed,target),"\n") end
 it("shows installed and downloaded versions and only changes between them",function()
  local shown=display("2.68.1-ai.preview544","2.68.1-ai.preview546")
  assert.matches("Installed: 2.68.1%-ai%.preview544",shown);assert.matches("Downloaded: 2.68.1%-ai%.preview546",shown)
  assert.matches("Fix updater",shown);assert.matches("Picker",shown);assert.is_nil(shown:find("Budget",1,true));assert.is_nil(shown:find("Old shared notes",1,true))
 end)
 it("explains missing notes instead of showing stale notes",function()
  assert.matches("unavailable",display("2.68.1-ai.preview545","2.68.1-ai.preview547"))
  assert.matches("Some earlier preview notes are unavailable",display("2.68.1-ai.preview500","2.68.1-ai.preview546"),1,true)
  assert.matches("could not be read",display("2.68.1-ai.preview545",nil))
 end)
 it("identifies file repairs without repeating old notes",function()
  local shown=display("2.68.1-ai.preview546","2.68.1-ai.preview546");assert.matches("repairs",shown);assert.is_nil(shown:find("Fix updater",1,true))
 end)
 it("rejects ambiguous duplicate preview entries",function()
  local duplicate=text.."VERSION[2.68.1-ai.preview546][date]\nOther\n"
  assert.matches("duplicate versions",display("2.68.1-ai.preview545","2.68.1-ai.preview546",duplicate),1,true)
 end)
 it("reads the target version and changelog hash from the staged manifest",function()
  local xml=require("xml");local old=xml.LoadXMLFile
  xml.LoadXMLFile=function(path) assert.equal("Update/manifest.xml",path);return {{elem="PoBVersion",{elem="Version",attrib={number="2.68.1-ai.preview546"}},{elem="File",attrib={part="default",name="changelog.txt",sha1=string.rep("a",40)}}}} end
  local ok,version,hash=pcall(notes.target,"Update/manifest.xml");xml.LoadXMLFile=old
  assert.is_true(ok);assert.equal("2.68.1-ai.preview546",version);assert.equal(string.rep("a",40),hash)
 end)
 it("handles unreadable or incomplete staged manifests",function()
  local xml=require("xml");local old=xml.LoadXMLFile
  xml.LoadXMLFile=function() error("unreadable") end
  assert.is_nil(notes.target("Update/manifest.xml"))
  xml.LoadXMLFile=function() return {{elem="PoBVersion",{elem="Version"},{elem="File"}}} end
  assert.is_nil(notes.target("Update/manifest.xml"));xml.LoadXMLFile=old
 end)
 it("accepts only release notes matching the downloaded manifest",function()
  local sha1=require("sha1");local content="Example\n"
  assert.is_true(notes.matches(content,sha1(content)))
  assert.is_true(notes.matches(content,sha1("Example\r\n")))
  assert.is_false(notes.matches("stale notes",sha1(content)))
  assert.is_false(notes.matches(content,nil));assert.is_false(notes.matches(content,string.rep("z",40)))
 end)
 it("presents staged notes in the actual update popup",function()
  local oldTarget,oldRead,oldVersion=notes.target,notes.readVerified,launch.versionNumber
  local seen={};notes.target=function(path) seen.manifest=path;return "2.68.1-ai.preview546", string.rep("a",40) end
  notes.readVerified=function(path) seen[path]=true;if path=="Update/changelog.txt" then return text end end
  launch.versionNumber="2.68.1-ai.preview544";main.popups={}
  local ok,err=pcall(function()
   main:OpenUpdatePopup();local popup=main.popups[1];local rows={}
   for _,line in ipairs(popup.controls.changeLog.list) do rows[#rows+1]=line[1] or "" end
   local shown=table.concat(rows,"\n");assert.matches("Downloaded: 2.68.1%-ai%.preview546",shown)
   assert.matches("Fix updater",shown);assert.matches("Picker",shown);assert.is_nil(shown:find("Old shared notes",1,true))
   assert.equal("Update/manifest.xml",seen.manifest);assert.is_true(seen["Update/changelog.txt"])
  end)
  notes.target,notes.readVerified,launch.versionNumber=oldTarget,oldRead,oldVersion;main.popups={};assert.is_true(ok,err)
 end)
 it("handles ordinary upstream release sections",function()
  local source="VERSION[2.4][date]\nNew\nVERSION[2.3][date]\nPrevious\n"
  local shown=display("2.3","2.4",source);assert.matches("New",shown);assert.is_nil(shown:find("Previous",1,true))
 end)
end)
