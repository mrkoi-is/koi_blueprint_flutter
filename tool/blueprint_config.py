"""Strict, versioned inputs shared by create, capabilities and builds."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re

PLATFORMS = ('web', 'android', 'ios', 'macos', 'windows', 'linux')
ARCHITECTURES = {'web': ('web',), 'android': ('arm64-v8a', 'armeabi-v7a', 'x86_64'),
                 'ios': ('arm64',), 'macos': ('arm64', 'x86_64'),
                 'windows': ('x64', 'arm64'), 'linux': ('x64', 'arm64')}
DEFAULT_ARCH = {key: values[0] for key, values in ARCHITECTURES.items()}


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()).hexdigest()


def read_config(path=None):
    value = json.loads(Path(path).read_text(encoding='utf-8')) if path else {'schema': 1}
    if not isinstance(value, dict) or value.get('schema') != 1:
        raise ValueError('Configuration must be a JSON object with schema: 1')
    allowed = {'schema', 'template', 'platforms', 'org', 'locales', 'capabilities', 'brand', 'buildProfiles', 'capabilityOptions'}
    if extra := value.keys() - allowed:
        raise ValueError('Unknown configuration fields: ' + ', '.join(sorted(extra)))
    if value.get('template', 'minimal') not in ('minimal', 'workbench'):
        raise ValueError('template must be minimal or workbench')
    for key in ('platforms', 'locales', 'capabilities'):
        items = value.get(key, [])
        if not isinstance(items, list) or any(not isinstance(item, str) for item in items) or len(items) != len(set(items)):
            raise ValueError(f'{key} must be a list of unique strings')
    if any(p not in PLATFORMS for p in value.get('platforms', [])) or ('platforms' in value and not value['platforms']):
        raise ValueError('platforms must be a nonempty subset of the six supported platforms')
    if any(p not in ('en', 'zh', 'zh_Hant') for p in value.get('locales', [])):
        raise ValueError('The tested locale set is en, zh, zh_Hant; add and validate translations before extending it')
    if 'locales' in value and set(value['locales']) != {'en', 'zh', 'zh_Hant'}:
        raise ValueError('Both templates currently require the complete tested locale set: en, zh, zh_Hant')
    options = value.get('capabilityOptions', {})
    if not isinstance(options, dict) or any(not isinstance(v, dict) for v in options.values()):
        raise ValueError('capabilityOptions must map capability IDs to option objects')
    brand = value.get('brand', {})
    if not isinstance(brand, dict) or brand.keys() - {'displayName', 'iconForeground', 'iconBackground'}:
        raise ValueError('brand supports displayName, iconForeground, iconBackground')
    if any(not isinstance(v, str) or not v.strip() for v in brand.values()):
        raise ValueError('Brand values must be nonempty strings')
    profiles = value.get('buildProfiles', {})
    if not isinstance(profiles, dict):
        raise ValueError('buildProfiles must be an object')
    for name, profile in profiles.items():
        if not re.fullmatch(r'[a-z][a-z0-9_-]*', name):
            raise ValueError(f'Invalid profile name: {name}')
        validate_profile(profile)
    return value


def validate_profile(profile):
    if not isinstance(profile, dict) or profile.keys() - {'platform', 'arch', 'mode', 'channel', 'format', 'codesign'}:
        raise ValueError('Unsupported build profile fields')
    platform = profile.get('platform')
    if platform not in PLATFORMS:
        raise ValueError('Build profile requires platform')
    arch = profile.get('arch', DEFAULT_ARCH[platform])
    if arch not in ARCHITECTURES[platform]:
        raise ValueError(f'Unsupported {platform} architecture: {arch}')
    if profile.get('mode', 'release') not in ('release', 'profile', 'debug'):
        raise ValueError('Build mode must be release, profile or debug')
    if not re.fullmatch(r'[a-z][a-z0-9_-]*', profile.get('channel', 'local')):
        raise ValueError('Invalid channel')
    if 'codesign' in profile and not isinstance(profile['codesign'], bool):
        raise ValueError('codesign must be boolean')
    formats = {'web': ('zip',), 'android': ('apk',), 'ios': ('app',), 'macos': ('dmg',),
               'windows': ('exe',), 'linux': ('deb', 'AppImage')}
    if 'format' in profile and profile['format'] not in formats[platform]:
        raise ValueError(f'Unsupported packaging format for {platform}')
    return {'platform': platform, 'arch': arch, 'mode': profile.get('mode', 'release'),
            'channel': profile.get('channel', 'local'), 'codesign': profile.get('codesign', False),
            **({'format': profile['format']} if 'format' in profile else {})}


def choose(explicit, config, key, default=None):
    configured = config.get(key)
    if explicit is not None and configured is not None and explicit != configured:
        raise ValueError(f'Conflicting --{key} and configuration {key}')
    return explicit if explicit is not None else configured if configured is not None else default
