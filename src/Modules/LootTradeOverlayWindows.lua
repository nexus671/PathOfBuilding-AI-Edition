-- cspell:ignore UNICODETEXT
local ffi = require("ffi")
assert(ffi.os=="Windows","The trade overlay requires Windows")
local user, kernel = ffi.load("user32"), ffi.load("kernel32")
local bit = require("bit")
local M = {}

ffi.cdef[[
typedef struct { long left, top, right, bottom; } PoBOverlayRect;
typedef struct { uint32_t size; PoBOverlayRect monitor, work; uint32_t flags; } PoBOverlayMonitor;
typedef struct {
	void *window; uint32_t message; uintptr_t wParam; intptr_t lParam;
	uint32_t time; long x, y; uint32_t private;
} PoBOverlayMessage;
typedef struct {
	uint32_t type;
	union {
		struct { long x, y; uint32_t data, flags, time; uintptr_t extra; } mouse;
		struct { uint16_t key, scan; uint32_t flags, time; uintptr_t extra; } keyboard;
	};
} PoBOverlayInput;
typedef int (__stdcall *PoBOverlayWindowCallback)(void *, intptr_t);
void * __stdcall GetForegroundWindow(void);
uint32_t __stdcall GetWindowThreadProcessId(void *window, uint32_t *pid);
int __stdcall EnumWindows(PoBOverlayWindowCallback callback, intptr_t extra);
int __stdcall GetWindowTextW(void *window, uint16_t *text, int capacity);
void * __stdcall MonitorFromWindow(void *window, uint32_t flags);
int __stdcall GetMonitorInfoW(void *monitor, PoBOverlayMonitor *info);
uint32_t __stdcall GetDpiForWindow(void *window);
int __stdcall SetWindowPos(void *window, void *after, int x, int y, int width, int height, uint32_t flags);
int __stdcall ShowWindow(void *window, int command);
int __stdcall SetForegroundWindow(void *window);
int __stdcall IsIconic(void *window);
int __stdcall RegisterHotKey(void *window, int id, uint32_t modifiers, uint32_t key);
int __stdcall UnregisterHotKey(void *window, int id);
int __stdcall PeekMessageW(PoBOverlayMessage *message, void *window, uint32_t first, uint32_t last, uint32_t flags);
short __stdcall GetAsyncKeyState(int key);
uint32_t __stdcall SendInput(uint32_t count, PoBOverlayInput *data, int size);
uint32_t __stdcall GetClipboardSequenceNumber(void);
int __stdcall OpenClipboard(void *window);
int __stdcall CloseClipboard(void);
void * __stdcall GetClipboardOwner(void);
void * __stdcall GetClipboardData(uint32_t format);
uintptr_t __stdcall GlobalSize(void *memory);
void * __stdcall GlobalLock(void *memory);
int __stdcall GlobalUnlock(void *memory);
uint32_t __stdcall GetCurrentProcessId(void);
uint64_t __stdcall GetTickCount64(void);
uint32_t __stdcall GetLastError(void);
void * __stdcall OpenProcess(uint32_t access, int inherit, uint32_t pid);
int __stdcall QueryFullProcessImageNameW(void *process, uint32_t flags, uint16_t *path, uint32_t *length);
int __stdcall CloseHandle(void *handle);
void * __stdcall CreateEventW(void *attributes, int manualReset, int initialState, const uint16_t *name);
int __stdcall SetEvent(void *event);
void * __stdcall CreateMutexA(void *attributes, int owner, const char *name);
uint32_t __stdcall WaitForSingleObject(void *handle, uint32_t milliseconds);
int __stdcall WideCharToMultiByte(uint32_t page, uint32_t flags, const uint16_t *input, int size,
	char *output, int capacity, const char *fallback, int *usedFallback);
]]

local function unicode(wide, length)
	if length==0 then return "" end
	local capacity=length*4
	local output=ffi.new("char[?]",capacity)
	local bytes=kernel.WideCharToMultiByte(65001,128,wide,length,output,capacity,nil,nil)
	if bytes>0 then return ffi.string(output,bytes) end
end

local function windowHandle(id)
	return ffi.cast("void *",id)
end

local function foreground()
	local handle=user.GetForegroundWindow()
	return handle~=nil and tonumber(ffi.cast("uintptr_t",handle)) or nil
end

local function pid(window)
	if not window then return end
	local owner=ffi.new("uint32_t[1]")
	user.GetWindowThreadProcessId(windowHandle(window),owner)
	return tonumber(owner[0])
end

local function executable(window)
	local owner=pid(window)
	if not owner or owner==0 then return end
	local process=kernel.OpenProcess(0x1000,0,owner)
	if process==nil then return end
	local size=ffi.new("uint32_t[1]",2048)
	local path=ffi.new("uint16_t[?]",size[0])
	local valid=kernel.QueryFullProcessImageNameW(process,0,path,size)
	kernel.CloseHandle(process)
	if valid~=0 then return unicode(path,size[0]) end
end

local function readItem(expectedPID)
	if user.OpenClipboard(nil)==0 then return end
	local raw
	local owner=user.GetClipboardOwner()
	if owner~=nil and pid(tonumber(ffi.cast("uintptr_t",owner)))==expectedPID then
		local data=user.GetClipboardData(13) -- CF_UNICODETEXT
		if data~=nil then
			local size=tonumber(kernel.GlobalSize(data))
			if size>=2 and size<=48002 then
				local memory=kernel.GlobalLock(data)
				if memory~=nil then
					local wide=ffi.cast("const uint16_t *",memory)
					for index=0,math.floor(size/2)-1 do
						if wide[index]==0 then raw=unicode(wide,index); break end
					end
					kernel.GlobalUnlock(data)
				end
			end
		end
	end
	user.CloseClipboard()
	if raw and #raw<=24000 then return raw end
end

local function copy()
	local events=ffi.new("PoBOverlayInput[4]")
	for index, key in ipairs({0x11,0x43,0x43,0x11}) do
		events[index-1].type=1
		events[index-1].keyboard.key=key
		events[index-1].keyboard.flags=index>2 and 2 or 0
	end
	return user.SendInput(4,events,ffi.sizeof("PoBOverlayInput"))==4
end

function M.listener(event)
	local msg=ffi.new("PoBOverlayMessage[1]")
	local id, hotkey = 0x321,0x312
	return {
		time=function() return tonumber(kernel.GetTickCount64()) end,
		foreground=foreground,pid=pid,executable=executable,
		wait=function(ms) return kernel.WaitForSingleObject(windowHandle(event),ms)~=258 end,
		register=function(code) return user.RegisterHotKey(nil,id,0x4003,code)~=0 end,
		unregister=function() user.UnregisterHotKey(nil,id) end,
		nextHotkey=function()
			return user.PeekMessageW(msg,nil,hotkey,hotkey,1)~=0 and msg[0].wParam==id
		end,
		chordDown=function(code)
			for _, key in ipairs({code,0x10,0x11,0x12,0x5B,0x5C}) do
				if bit.band(user.GetAsyncKeyState(key),0x8000)~=0 then return true end
			end
			return false
		end,
		sequence=user.GetClipboardSequenceNumber,copy=copy,read=readItem,
	}
end

function M.singleInstance()
	local mutex=kernel.CreateMutexA(nil,0,"Local\\PoB AI Trade Overlay")
	if mutex==nil then return end
	if kernel.GetLastError()~=183 then return mutex end
	kernel.CloseHandle(mutex)
end

function M.stopEvent()
	local event=kernel.CreateEventW(nil,1,0,nil)
	return event~=nil and tonumber(ffi.cast("uintptr_t",event)) or nil
end

function M.signal(event)
	if event then kernel.SetEvent(windowHandle(event)) end
end

function M.close(handle)
	if handle then kernel.CloseHandle(windowHandle(handle)) end
end

function M.findWindow(title)
	local found
	local process=kernel.GetCurrentProcessId()
	local text=ffi.new("uint16_t[128]")
	local callback=ffi.cast("PoBOverlayWindowCallback",function(handle)
		local window=tonumber(ffi.cast("uintptr_t",handle))
		if pid(window)==process and unicode(text,user.GetWindowTextW(handle,text,128))==title then
			found=window
			return 0
		end
		return 1
	end)
	user.EnumWindows(callback,0)
	callback:free()
	return found
end

function M.present(window, game)
	if foreground()~=game then return false end
	local target, handle=windowHandle(game),windowHandle(window)
	local info=ffi.new("PoBOverlayMonitor[1]")
	info[0].size=ffi.sizeof(info[0])
	if user.GetMonitorInfoW(user.MonitorFromWindow(target,2),info)==0 then return false end
	local work=info[0].work
	local scale=math.max(96,user.GetDpiForWindow(target))/96
	local width=math.min(work.right-work.left,math.floor(960*scale))
	local height=math.min(work.bottom-work.top,math.floor(700*scale))
	user.ShowWindow(handle,9) -- SW_RESTORE
	if user.SetWindowPos(handle,windowHandle(-1),work.left+math.floor((work.right-work.left-width)/2),
		work.top+math.floor((work.bottom-work.top-height)/2),width,height,0x0050)==0 then return false end
	user.SetForegroundWindow(handle)
	return true
end

function M.minimize(window)
	local handle=windowHandle(window)
	user.SetWindowPos(handle,windowHandle(-2),0,0,0,0,0x0013)
	user.ShowWindow(handle,6) -- SW_MINIMIZE
end

M.foreground=foreground
M.minimized=function(window) return user.IsIconic(windowHandle(window))~=0 end
M.pointerDown=function()
	return bit.band(user.GetAsyncKeyState(1),0x8000)~=0 or bit.band(user.GetAsyncKeyState(2),0x8000)~=0
end
return M
