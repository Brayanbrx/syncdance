"""Read the version an APK declares, from its compiled AndroidManifest.xml.

The panel asked for the version code by hand; a typo makes every phone see an
update forever (or never). The APK already says it: `versionCode` and
`versionName` of the <manifest> element, in Android's binary XML (AXML).
Only that element is read; anything unexpected returns None.
"""

import struct
import zipfile

RES_XML = 0x0003
RES_STRING_POOL = 0x0001
RES_XML_START_ELEMENT = 0x0102
UTF8_FLAG = 0x100
TYPE_STRING = 0x03
TYPE_INT_DEC = 0x10
TYPE_INT_HEX = 0x11
MAX_MANIFEST_BYTES = 4 * 1024 * 1024


def _strings(data, offset):
    _, header_size, size, count, _, flags, strings_start, _ = struct.unpack_from(
        "<HHIIIIII", data, offset
    )
    offsets = struct.unpack_from(f"<{count}I", data, offset + header_size)
    base = offset + strings_start
    utf8 = bool(flags & UTF8_FLAG)
    result = []
    for start in offsets:
        at = base + start
        if utf8:
            # Two lengths (characters, then bytes), each 1 or 2 bytes.
            for _ in range(2):
                length = data[at]
                at += 1
                if length & 0x80:
                    length = ((length & 0x7F) << 8) | data[at]
                    at += 1
            result.append(data[at : at + length].decode("utf-8", "replace"))
        else:
            (length,) = struct.unpack_from("<H", data, at)
            at += 2
            if length & 0x8000:
                (low,) = struct.unpack_from("<H", data, at)
                length = ((length & 0x7FFF) << 16) | low
                at += 2
            result.append(data[at : at + 2 * length].decode("utf-16-le", "replace"))
    return result, offset + size


def manifest_attributes(data: bytes):
    """Attributes of the <manifest> element: {name: (type, value, raw, offset)},
    where offset is where the typed value sits in `data`. None if unreadable."""
    try:
        kind, header_size, _ = struct.unpack_from("<HHI", data, 0)
        if kind != RES_XML:
            return None
        offset = header_size
        strings = []
        while offset + 8 <= len(data):
            kind, header, size = struct.unpack_from("<HHI", data, offset)
            if size < 8:
                return None
            if kind == RES_STRING_POOL:
                strings, _ = _strings(data, offset)
            elif kind == RES_XML_START_ELEMENT:
                ext = offset + header
                _, name, attr_start, attr_size, attr_count = struct.unpack_from("<IIHHH", data, ext)
                if strings[name] != "manifest":
                    return None  # the first element of a manifest is <manifest>
                attributes = {}
                for i in range(attr_count):
                    at = ext + attr_start + i * attr_size
                    _, attr_name, raw, _, _, value_type, value = struct.unpack_from(
                        "<IIIHBBI", data, at
                    )
                    attributes[strings[attr_name]] = (value_type, value, raw, at + 16)
                return attributes, strings
            offset += size
    except (struct.error, IndexError, UnicodeError):
        return None
    return None


def manifest_versions(data: bytes):
    """(version_code, version_name) of a compiled manifest, or None."""
    found = manifest_attributes(data)
    if found is None:
        return None
    attributes, strings = found
    code = version = None
    if "versionCode" in attributes:
        value_type, value, _, _ = attributes["versionCode"]
        if value_type in (TYPE_INT_DEC, TYPE_INT_HEX):
            code = value
    if "versionName" in attributes:
        value_type, value, raw, _ = attributes["versionName"]
        index = value if value_type == TYPE_STRING else raw
        version = strings[index] if index < len(strings) else None
    return (code, version) if code else None


def apk_versions(upload):
    """Versions declared by an uploaded APK file, or None if unreadable."""
    try:
        upload.seek(0)
        with zipfile.ZipFile(upload) as apk:
            info = apk.getinfo("AndroidManifest.xml")
            if info.file_size > MAX_MANIFEST_BYTES:
                return None
            return manifest_versions(apk.read(info))
    except (zipfile.BadZipFile, KeyError, OSError):
        return None
    finally:
        upload.seek(0)
