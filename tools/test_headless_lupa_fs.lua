-- Exercise the optional filesystem adapter using real temporary files.
local lfs=require("lfs")
local directory=os.tmpname();os.remove(directory);assert(lfs.mkdir(directory))
local path=directory.."/sample.txt";local file=assert(io.open(path,"wb"));file:write("sample");file:close()
local found=false;for name in lfs.dir(directory) do if name=="sample.txt" then found=true end end
assert(found,"Directory iteration missed the file")
assert(os.remove(path));assert(lfs.rmdir(directory));assert(not pcall(lfs.dir,directory),"Missing directories must report an error")
print("Headless filesystem adapter: passed")
