"""Plan Apple bundle languages and localized diagnostic permission resources."""
from __future__ import annotations

import hashlib
import json
import plistlib
import re
from pathlib import Path


APPLE_LOCALES = ('en', 'zh-Hans', 'zh-Hant')
LOCAL_NETWORK_PROMPTS = {
    'en': 'View application diagnostics from a browser on your local network.',
    'zh-Hans': '允许同一局域网内的浏览器查看应用诊断信息。',
    'zh-Hant': '允許同一區域網路內的瀏覽器檢視應用程式診斷資訊。',
}


def _once(text, anchor, replacement):
    if text.count(anchor) != 1:
        raise ValueError(f'Unsupported Apple localization anchor: {anchor}')
    return text.replace(anchor, replacement, 1)


def _object(text, identifier):
    matches = list(re.finditer(
        rf'^\t\t{identifier}(?: /\*[^\n]*?\*/)? = \{{\n.*?\n\t\t\}};', text, re.M | re.S))
    if len(matches) != 1:
        raise ValueError(f'Ambiguous Apple localization object: {identifier}')
    return matches[0].group()


def _resource_fields(project, identifier):
    # CocoaPods/Xcode may reorder objects, expand lines and regenerate comments.
    # Compare the owned flat resource objects by fields, not their serialization.
    clean = re.sub(r'/\*.*?\*/', '', project, flags=re.S)
    matches = re.findall(rf'\b{identifier}\s*=\s*\{{([^{{}}]*)\}};', clean, re.S)
    if len(matches) != 1:
        raise ValueError('Missing or duplicate managed Apple localization object')
    fields = {}
    for key, value in re.findall(r'(\w+)\s*=\s*(.*?);', matches[0], re.S):
        if key in fields:
            raise ValueError('Duplicate Apple localization resource field')
        value = value.strip()
        fields[key] = tuple(re.findall(r'[A-F0-9]{24}', value)) if key == 'children' else value.strip('"')
    return fields


def _resources(project):
    ids = {key: hashlib.sha256(f'koi-localization:{key}'.encode()).hexdigest()[:24].upper()
           for key in ('group', 'build', *APPLE_LOCALES)}
    lines = ['/* Koi localized InfoPlist begin */']
    for locale in APPLE_LOCALES:
        lines.append(f'\t\t{ids[locale]} = {{isa = PBXFileReference; lastKnownFileType = text.plist.strings; '
                     f'name = "{locale}"; path = "{locale}.lproj/InfoPlist.strings"; sourceTree = "<group>"; }};')
    children = ', '.join(ids[locale] for locale in APPLE_LOCALES)
    lines.append(f'\t\t{ids["group"]} = {{isa = PBXVariantGroup; children = ({children}); '
                 'name = InfoPlist.strings; sourceTree = "<group>"; };')
    lines.append(f'\t\t{ids["build"]} = {{isa = PBXBuildFile; fileRef = {ids["group"]}; }};')
    lines.append('/* Koi localized InfoPlist end */')
    managed = '\n'.join(lines)
    existing = any(value in project for value in ids.values())
    if existing:
        for identifier in ids.values():
            if _resource_fields(project, identifier) != _resource_fields(managed, identifier):
                raise ValueError('Edited managed Apple localization resources')
    elif 'InfoPlist.strings' in project:
        raise ValueError('Existing Apple localization resources require an explicit merge')

    def anchor(kind):
        matches = re.findall(rf'([A-F0-9]{{24}}) /\* Runner \*/ = \{{\n\s*isa = {kind};', project)
        if len(matches) != 1:
            raise ValueError(f'Missing Runner {kind} localization anchor')
        return matches[0]

    group = anchor('PBXGroup')
    target = _object(project, anchor('PBXNativeTarget'))
    phases = re.findall(r'([A-F0-9]{24}) /\* Resources \*/', target)
    if len(phases) != 1:
        raise ValueError('Missing Runner resource build phase')
    for identifier, field, value in ((group, 'children', ids['group']), (phases[0], 'files', ids['build'])):
        block = _object(project, identifier)
        entry = f'\t\t\t\t{value} /* InfoPlist.strings */,\n'
        if existing:
            match = re.search(rf'{field} = \((.*?)\);', block, re.S)
            if not match or re.findall(r'[A-F0-9]{24}', match[1]).count(value) != 1:
                raise ValueError('Detached Apple localization resource')
        else:
            updated = _once(block, f'{field} = (\n', f'{field} = (\n' + entry)
            project = _once(project, block, updated)
    if not existing:
        project = _once(project, '\tobjects = {\n', '\tobjects = {\n' + managed + '\n')
    return project


def plan_apple_localizations(app, *, diagnostics=False, base_changes=None):
    """Return bytes only; the caller owns the transaction and provenance."""
    app = Path(app)
    base_changes = base_changes or {}
    output = {}

    def read(relative):
        path = app / relative
        if any((app / parent).is_symlink() for parent in (Path(relative), *Path(relative).parents)):
            raise ValueError(f'Unsafe Apple localization path: {relative}')
        return base_changes[relative] if relative in base_changes else path.read_bytes()

    for platform in ('ios', 'macos'):
        if not (app / platform).is_dir():
            continue
        plist_path = f'{platform}/Runner/Info.plist'
        info = plistlib.loads(read(plist_path))
        locales = info.get('CFBundleLocalizations', [])
        if not isinstance(locales, list) or not all(isinstance(item, str) for item in locales):
            raise ValueError('Invalid CFBundleLocalizations')
        info['CFBundleLocalizations'] = list(dict.fromkeys([*locales, *APPLE_LOCALES]))
        project_path = f'{platform}/Runner.xcodeproj/project.pbxproj'
        project = read(project_path).decode('utf-8')
        # Flutter emits CRLF projects on Windows. Parse a normalized view and
        # preserve the project's original newline convention when serializing.
        newline = '\r\n' if '\r\n' in project else '\n'
        project = project.replace('\r\n', '\n')
        regions = list(re.finditer(r'knownRegions = \(\n(.*?)\n\s*\);', project, re.S))
        if len(regions) != 1:
            raise ValueError('Missing Apple knownRegions localization anchor')
        region = regions[0]
        names = re.findall(r'\s*"?([A-Za-z0-9_-]+)"?,', region[1])
        additions = ''.join(f'\n\t\t\t\t"{locale}",' for locale in APPLE_LOCALES if locale not in names)
        project = project[:region.end(1)] + additions + project[region.end(1):]
        if diagnostics:
            if info.get('NSLocalNetworkUsageDescription', LOCAL_NETWORK_PROMPTS['en']) != LOCAL_NETWORK_PROMPTS['en']:
                raise ValueError('Custom local network permission rationale requires an explicit localization merge')
            info.setdefault('NSLocalNetworkUsageDescription', LOCAL_NETWORK_PROMPTS['en'])
            project = _resources(project)
            for locale, prompt in LOCAL_NETWORK_PROMPTS.items():
                relative = f'{platform}/Runner/{locale}.lproj/InfoPlist.strings'
                content = ('/* Koi diagnostics permission rationale. */\n'
                           '"NSLocalNetworkUsageDescription" = ' + json.dumps(prompt, ensure_ascii=False) + ';\n').encode()
                if (app / relative).exists() or (app / relative).is_symlink():
                    if read(relative) != content:
                        raise ValueError(f'Localized native resource has user changes: {relative}')
                output[relative] = content
        output[plist_path] = plistlib.dumps(info, sort_keys=False)
        output[project_path] = project.replace('\n', newline).encode('utf-8')
    return output
