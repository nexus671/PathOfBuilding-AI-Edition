"""Embed AI Edition icon and version metadata in a Windows launcher copy."""
# cspell:ignore argtypes restype wintypes
import argparse
import ctypes
from ctypes import wintypes
from pathlib import Path
import struct


def aligned(data):
    return data + b"\0" * (-len(data) % 4)


def block(name, value=b"", value_length=0, kind=1, children=()):
    data = aligned(b"\0" * 6 + name.encode("utf-16le") + b"\0\0")
    data = aligned(data + value) + b"".join(children)
    if len(data) > 65535:
        raise ValueError("Windows version resource is too large")
    return struct.pack("<HHH", len(data), value_length, kind) + data[6:]


def version_resource(version):
    pieces = version.split(".")
    if len(pieces) != 3 or any(not part.isdigit() or int(part) > 65535 for part in pieces):
        raise ValueError("Use a three-part numeric edition version")
    major, minor, patch = map(int, pieces)
    version_ms, version_ls = major << 16 | minor, patch << 16
    fixed = struct.pack("<13I", 0xFEEF04BD, 0x10000, version_ms, version_ls,
                        version_ms, version_ls, 0x3F, 0, 0x40004, 1, 0, 0, 0)
    fields = {
        "CompanyName": "Path of Building AI Edition",
        "FileDescription": "Path of Building AI Edition",
        "FileVersion": version,
        "InternalName": "Path of Building AI Edition",
        "OriginalFilename": "Path of Building.exe",
        "ProductName": "Path of Building AI Edition",
        "ProductVersion": version,
    }
    strings = []
    for name, value in fields.items():
        encoded = (value + "\0").encode("utf-16le")
        strings.append(block(name, encoded, len(value) + 1))
    string_info = block("StringFileInfo", children=[block("040904B0", children=strings)])
    translation = block("Translation", struct.pack("<HH", 1033, 1200), 4, 0)
    var_info = block("VarFileInfo", children=[translation])
    return block("VS_VERSION_INFO", fixed, len(fixed), 0, [string_info, var_info])


def brand(executable, icon, version):
    if not hasattr(ctypes, "WinDLL"):
        raise RuntimeError("Branding the Windows launcher requires Windows")
    executable, icon = Path(executable).resolve(strict=True), Path(icon).resolve(strict=True)
    data = icon.read_bytes()
    reserved, kind, count = struct.unpack_from("<HHH", data)
    if reserved != 0 or kind != 1 or not 1 <= count <= 32 or len(data) < 6 + count * 16:
        raise ValueError("Invalid Windows icon")
    images, group = [], bytearray(struct.pack("<HHH", 0, 1, count))
    for index in range(count):
        width, height, colours, zero, planes, bits, size, offset = struct.unpack_from("<BBBBHHII", data, 6 + index * 16)
        if zero or not size or offset < 6 + count * 16 or offset + size > len(data):
            raise ValueError("Invalid Windows icon image")
        images.append(data[offset:offset + size])
        group.extend(struct.pack("<BBBBHHIH", width, height, colours, zero, planes, bits, size, index + 1))
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.BeginUpdateResourceW.argtypes = [wintypes.LPCWSTR, wintypes.BOOL]
    kernel.BeginUpdateResourceW.restype = wintypes.HANDLE
    kernel.UpdateResourceW.argtypes = [wintypes.HANDLE, ctypes.c_void_p, ctypes.c_void_p, wintypes.WORD, ctypes.c_void_p, wintypes.DWORD]
    kernel.UpdateResourceW.restype = wintypes.BOOL
    kernel.EndUpdateResourceW.argtypes = [wintypes.HANDLE, wintypes.BOOL]
    kernel.EndUpdateResourceW.restype = wintypes.BOOL
    handle = kernel.BeginUpdateResourceW(str(executable), False)
    if not handle:
        raise ctypes.WinError(ctypes.get_last_error())
    def write(resource_type, name, content):
        buf = ctypes.create_string_buffer(content)
        if not kernel.UpdateResourceW(handle, resource_type, name, 1033, buf, len(content)):
            raise ctypes.WinError(ctypes.get_last_error())
    try:
        for index, image in enumerate(images, 1):
            write(3, index, image)
        write(14, 1000, bytes(group))
        write(16, 1, version_resource(version))
    except BaseException:
        kernel.EndUpdateResourceW(handle, True)
        raise
    if not kernel.EndUpdateResourceW(handle, False):
        raise ctypes.WinError(ctypes.get_last_error())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("icon", type=Path)
    parser.add_argument("--version", required=True)
    args = parser.parse_args()
    brand(args.executable, args.icon, args.version)
