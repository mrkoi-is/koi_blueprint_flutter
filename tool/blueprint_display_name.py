"""Pure native/web display-name plan; bundle IDs and executable names stay stable."""
from __future__ import annotations

import html
import json
from pathlib import Path
import plistlib
import re
import xml.etree.ElementTree as ET
from xml.sax.saxutils import quoteattr

from tool.blueprint_capabilities import safe_file


def _cpp(value):
    out = '"'
    for char in value:
        code = ord(char)
        if char in ('"', '\\'):
            out += '\\' + char
        elif code > 0xffff:
            out += '\\U%08x' % code
        elif code > 127:
            out += '\\u%04x' % code
        else:
            out += char
    return out + '"'


def plan_display_name(app, name, platforms):
    app = Path(app).resolve()
    if not isinstance(name, str) or not name.strip() or len(name) > 80 or any(not c.isprintable() for c in name):
        raise ValueError('Display name must contain 1–80 printable Unicode characters')
    outputs = {}
    def read(relative):
        path = safe_file(app, relative)
        if not path.is_file():
            raise ValueError(f'Missing platform display-name input: {relative}')
        return path.read_bytes()
    def add(relative, value):
        if isinstance(value, str): value = value.encode('utf-8')
        if read(relative) != value: outputs[relative] = value
    for platform in platforms:
        if platform == 'android':
            relative = 'android/app/src/main/AndroidManifest.xml'
            source = read(relative).decode()
            matches = list(re.finditer(r'<application\b[^>]*>', source))
            if len(matches) != 1: raise ValueError('Expected one Android application element')
            old = matches[0].group()
            label = 'android:label=' + quoteattr(name)
            new, count = re.subn(r'android:label=(?:"[^"]*"|\x27[^\x27]*\x27)', lambda _: label, old)
            if not count: new = old[:-1] + ' ' + label + '>'
            if count > 1: raise ValueError('Duplicate Android label')
            updated = source[:matches[0].start()] + new + source[matches[0].end():]
            ET.fromstring(updated)
            add(relative, updated)
        elif platform in ('ios', 'macos'):
            relative = f'{platform}/Runner/Info.plist'
            content = plistlib.loads(read(relative))
            old_name = content.get('CFBundleDisplayName', content.get('CFBundleName'))
            content['CFBundleDisplayName'] = name
            content['CFBundleName'] = name
            add(relative, plistlib.dumps(content, sort_keys=False))
            if platform == 'macos':
                xib = 'macos/Runner/Base.lproj/MainMenu.xib'
                tree = ET.fromstring(read(xib))
                for item in tree.iter():
                    value = item.get('title')
                    if item.tag == 'window' and item.get('customClass') == 'MainFlutterWindow':
                        item.set('title', name)
                    elif value:
                        for old in ('APP_NAME', old_name):
                            if not isinstance(old, str): continue
                            for prefix in ('', 'About ', 'Hide ', 'Quit '):
                                if value == prefix + old:
                                    item.set('title', prefix + name)
                add(xib, ET.tostring(tree, encoding='utf-8', xml_declaration=True))
        elif platform == 'windows':
            relative = 'windows/runner/main.cpp'
            source = read(relative).decode()
            updated, count = re.subn(r'(window\.Create\()L"(?:[^"\\]|\\.)*"', lambda m: m[1] + 'L' + _cpp(name), source)
            if count != 1: raise ValueError('Expected one Windows window title')
            add(relative, updated)
            relative = 'windows/runner/Runner.rc'
            source = read(relative).decode()
            for key in ('FileDescription', 'ProductName'):
                source, count = re.subn(r'(VALUE\s+"' + key + r'",\s*)"(?:[^"\\]|\\.)*"', lambda m: m[1] + json.dumps(name, ensure_ascii=False), source)
                if count != 1: raise ValueError(f'Expected one Windows {key}')
            if '#pragma code_page(65001)' not in source:
                source = '#pragma code_page(65001)\n' + source
            add(relative, source)
        elif platform == 'linux':
            relative = 'linux/runner/my_application.cc'
            source = read(relative).decode()
            updated, count = re.subn(r'(gtk_(?:header_bar|window)_set_title\([^,]+,\s*)"(?:[^"\\]|\\.)*"', lambda m: m[1] + _cpp(name), source)
            if count < 1: raise ValueError('Missing Linux window title')
            add(relative, updated)
        elif platform == 'web':
            relative = 'web/manifest.json'
            data = json.loads(read(relative))
            data['name'] = name
            data['short_name'] = name
            add(relative, json.dumps(data, ensure_ascii=False, indent=2) + '\n')
            relative = 'web/index.html'
            source = read(relative).decode()
            updated, count = re.subn(r'<title>.*?</title>', lambda _: '<title>' + html.escape(name) + '</title>', source, flags=re.S)
            if count != 1: raise ValueError('Expected one Web title')
            updated = re.sub(r'(<meta\s+name="apple-mobile-web-app-title"\s+content=)"[^"]*"', lambda m: m[1] + '"' + html.escape(name, quote=True) + '"', updated)
            add(relative, updated)
        else:
            raise ValueError(f'Unsupported display-name platform: {platform}')
    return outputs
