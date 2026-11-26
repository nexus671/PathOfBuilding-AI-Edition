-- Windows PowerShell used for short Task Scheduler management and opt-in alerts.
-- A console must never be allocated, even when Windows Terminal is the default host.
local M = {}

function M.literal(value)
	return "'" .. value:gsub("'", "''") .. "'"
end

local ffi = require("ffi")
local base64 = require("base64")
ffi.cdef[[
	typedef struct {
		uint32_t cb;
		uint16_t *reserved, *desktop, *title;
		uint32_t x, y, xSize, ySize, xCountChars, yCountChars, fillAttribute, flags;
		uint16_t showWindow, reservedSize;
		uint8_t *reservedData;
		void *standardInput, *standardOutput, *standardError;
	} PoBLootStartupInfo;
	typedef struct {
		void *process, *thread;
		uint32_t processId, threadId;
	} PoBLootProcessInfo;
	int __stdcall MultiByteToWideChar(unsigned int, unsigned long, const char *, int, uint16_t *, int);
	int __stdcall WideCharToMultiByte(unsigned int, unsigned long, const uint16_t *, int, char *, int, const char *, int *);
	unsigned int __stdcall GetSystemDirectoryW(uint16_t *, unsigned int);
	int __stdcall CreateProcessW(const uint16_t *, uint16_t *, void *, void *, int, uint32_t, void *, const uint16_t *, PoBLootStartupInfo *, PoBLootProcessInfo *);
	uint32_t __stdcall WaitForSingleObject(void *, uint32_t);
	int __stdcall GetExitCodeProcess(void *, uint32_t *);
	int __stdcall TerminateProcess(void *, unsigned int);
	int __stdcall CloseHandle(void *);
]]

local function wide(value)
	local size = ffi.C.MultiByteToWideChar(65001, 8, value, #value, nil, 0)
	assert(size > 0, "Invalid Windows command text")
	local buffer = ffi.new("uint16_t[?]", size + 1)
	assert(ffi.C.MultiByteToWideChar(65001, 8, value, #value, buffer, size) == size, "Could not encode Windows command text")
	return buffer, size
end
local function encode(value)
	local buffer, size = wide(value)
	return base64.encode(ffi.string(buffer, size * 2))
end
function M.run(script, timeoutMs)
	local system = ffi.new("uint16_t[?]", 32768)
	local length = ffi.C.GetSystemDirectoryW(system, 32768)
	assert(length > 0 and length < 32768, "Could not find the Windows system directory")
	local bytes = ffi.new("char[?]", length * 4)
	local count = ffi.C.WideCharToMultiByte(65001, 0, system, length, bytes, length * 4, nil, nil)
	assert(count > 0, "Could not read the Windows system directory")
	local powershell = ffi.string(bytes, count) .. "\\WindowsPowerShell\\v1.0\\powershell.exe"
	local command = '"%s" -NoLogo -NoProfile -NonInteractive -EncodedCommand %s'
	local startup = ffi.new("PoBLootStartupInfo")
	startup.cb = ffi.sizeof(startup)
	local process = ffi.new("PoBLootProcessInfo")
	local executablePath = wide(powershell)
	local parameters = wide(command:format(powershell, encode(script)))
	local createNoWindow = 0x08000000
	assert(ffi.C.CreateProcessW(executablePath, parameters, nil, nil, 0, createNoWindow, nil, nil, startup, process) ~= 0,
		"Could not start Windows PowerShell")
	ffi.C.CloseHandle(process.thread)
	local waited = ffi.C.WaitForSingleObject(process.process, timeoutMs)
	local exitCode = ffi.new("uint32_t[1]", 1)
	local observed = waited==0 and ffi.C.GetExitCodeProcess(process.process,exitCode)~=0
	if waited == 258 then ffi.C.TerminateProcess(process.process, 1) end
	ffi.C.CloseHandle(process.process)
	return observed and tonumber(exitCode[0]) or nil
end

return M
