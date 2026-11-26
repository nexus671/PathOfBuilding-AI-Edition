/* Windows GUI launcher for the scheduled PoB worker.
 * Build from an x64 Visual Studio Developer Command Prompt:
 * cl /nologo /O2 /MT /W4 /WX /std:c11 /Fe:runtime\PoBLootSync.exe tools\loot_sync_launcher.c /link /SUBSYSTEM:WINDOWS /Brepro
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wchar.h>

static const wchar_t worker_name[] = L"Path of Building.exe";
static const wchar_t scheduled_mode[] = L"--loot-filter-sync-scheduled";

static BOOL valid_endpoint(const wchar_t *value)
{
    size_t length = wcslen(value);
    if (length < 9 || length > 400 || wcsncmp(value, L"https://", 8) != 0) {
        return FALSE;
    }
    for (const wchar_t *p = value + 8; *p; ++p) {
        wchar_t c = *p;
        if (!((c >= L'a' && c <= L'z') || (c >= L'A' && c <= L'Z') ||
              (c >= L'0' && c <= L'9') || c == L'.' || c == L'_' ||
              c == L'-' || c == L':' || c == L'/')) {
            return FALSE;
        }
    }
    return TRUE;
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR endpoint, int show)
{
    wchar_t directory[MAX_PATH];
    wchar_t worker[MAX_PATH];
    wchar_t command[MAX_PATH + 460];
    STARTUPINFOW startup = {0};
    PROCESS_INFORMATION child = {0};
    DWORD result = ERROR_GEN_FAILURE;
    DWORD size;

    (void)instance;
    (void)previous;
    (void)show;
    if (endpoint[0] && !valid_endpoint(endpoint)) {
        return ERROR_INVALID_PARAMETER;
    }
    size = GetModuleFileNameW(NULL, directory, ARRAYSIZE(directory));
    if (size == 0 || size == ARRAYSIZE(directory)) {
        return ERROR_BAD_PATHNAME;
    }
    wchar_t *separator = wcsrchr(directory, L'\\');
    if (!separator) {
        return ERROR_BAD_PATHNAME;
    }
    separator[1] = L'\0';
    if (swprintf_s(worker, ARRAYSIZE(worker), L"%ls%ls", directory, worker_name) < 0 ||
        swprintf_s(command, ARRAYSIZE(command), L"\"%ls\" %ls %ls", worker, scheduled_mode, endpoint) < 0) {
        return ERROR_BAD_PATHNAME;
    }

    /* SimpleGraphic shows its startup window unless the native startup settings hide it. */
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESHOWWINDOW;
    startup.wShowWindow = SW_HIDE;
    if (!CreateProcessW(worker, command, NULL, NULL, FALSE, CREATE_NO_WINDOW,
                        NULL, directory, &startup, &child)) {
        return (int)GetLastError();
    }
    CloseHandle(child.hThread);
    if (WaitForSingleObject(child.hProcess, INFINITE) == WAIT_OBJECT_0) {
        GetExitCodeProcess(child.hProcess, &result);
    }
    CloseHandle(child.hProcess);
    return (int)result;
}
