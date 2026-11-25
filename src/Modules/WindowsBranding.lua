-- cspell:ignore intptr uintptr
-- Apply the edition icon to this process's visible windows, not other PoB instances.
local M = {}
local icons
function M.apply()
	if jit.os~="Windows" then return false end
	local ffi=require("ffi")
	ffi.cdef[[
		typedef int (__stdcall *PoBAIEnumWindowProc)(void *, intptr_t);
		int __stdcall MultiByteToWideChar(unsigned int, unsigned long, const char *, int, uint16_t *, int);
		unsigned long __stdcall GetCurrentProcessId(void);
		int __stdcall EnumWindows(PoBAIEnumWindowProc, intptr_t);
		unsigned long __stdcall GetWindowThreadProcessId(void *, unsigned long *);
		int __stdcall IsWindowVisible(void *);
		void * __stdcall LoadImageW(void *, const uint16_t *, unsigned int, int, int, unsigned int);
		int __stdcall GetSystemMetrics(int);
		intptr_t __stdcall SendMessageW(void *, unsigned int, uintptr_t, intptr_t);
	]]
	local kernel,user=ffi.load("kernel32"),ffi.load("user32")
	local path=GetRuntimePath().."/Assets/AI-Edition.ico"
	local count=kernel.MultiByteToWideChar(65001,8,path,#path,nil,0)
	assert(count>0,"Invalid application icon path")
	local wide=ffi.new("uint16_t[?]",count+1)
	assert(kernel.MultiByteToWideChar(65001,8,path,#path,wide,count)==count,"Could not encode application icon path")
	local small=user.LoadImageW(nil,wide,1,user.GetSystemMetrics(49),user.GetSystemMetrics(50),0x10)
	local large=user.LoadImageW(nil,wide,1,user.GetSystemMetrics(11),user.GetSystemMetrics(12),0x10)
	assert(small~=nil and large~=nil,"Could not load the AI Edition icon")
	icons={small,large} -- Windows retains these handles while displaying the window.
	local process=kernel.GetCurrentProcessId()
	local applied=0
	local callback=ffi.cast("PoBAIEnumWindowProc",function(window)
		local owner=ffi.new("unsigned long[1]")
		user.GetWindowThreadProcessId(window,owner)
		if owner[0]==process and user.IsWindowVisible(window)~=0 then
			user.SendMessageW(window,0x80,0,ffi.cast("intptr_t",small))
			user.SendMessageW(window,0x80,1,ffi.cast("intptr_t",large))
			applied=applied+1
		end
		return 1
	end)
	user.EnumWindows(callback,0)
	callback:free()
	return applied>0
end
return M
