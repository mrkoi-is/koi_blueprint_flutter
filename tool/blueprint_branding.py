"""Generate native icon/splash assets in a stage, then commit owned outputs."""
from __future__ import annotations

import json
from pathlib import Path
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from tool.blueprint_assets import file_hash, owned_changes
from tool.blueprint_capabilities import FileTransaction, safe_file
from tool.blueprint_environment import inspect_tool


def _run(command, cwd):
    subprocess.run([str(part) for part in command], cwd=cwd, check=True, timeout=60)


def apply_brand(app, brand, platforms, *, source_root=None, adopt_runner_assets=False, run=None, plan_only=False):
    app = Path(app).resolve()
    source_root = Path(source_root or app).resolve()
    run = run or _run
    foreground = brand.get('iconForeground')
    background = brand.get('iconBackground', '#ffffff')
    if not foreground or not re.fullmatch(r'#[0-9A-Fa-f]{6}', background):
        raise ValueError('Branding requires iconForeground and a #RRGGBB iconBackground')
    source = safe_file(source_root, foreground)
    if not source.is_file() or source.suffix.lower() not in ('.png', '.svg'):
        raise ValueError('Brand foreground must be an existing PNG or SVG')
    if source.suffix.lower() == '.svg':
        text = source.read_text(encoding='utf-8')
        if re.search(r'<!DOCTYPE|<!ENTITY|(?:href|url)\s*[=(]\s*["\']?(?:https?:|file:|/)', text, re.I):
            raise ValueError('Brand SVG must be self-contained')
    tool = inspect_tool('imagemagick')
    if tool['status'] != 'AVAILABLE':
        raise ValueError('Branding requires ImageMagick >= 7.1 (BLUEPRINT_MAGICK)')
    outputs = {}
    with tempfile.TemporaryDirectory(prefix='blueprint-brand-') as temp:
        stage = Path(temp)
        master = stage / 'master.png'
        # Preserve transparent foreground; background remains a separate design input.
        run([tool['executable'], '-background', 'none', source, '-resize', '720x720', '-gravity', 'center', '-extent', '1024x1024', '-background', background, '-alpha', 'remove', '-alpha', 'off', '-strip', '-define', 'png:exclude-chunks=date,time', master], stage)
        if not master.is_file():
            raise ValueError('Brand renderer did not produce an icon')
        outputs['assets/brand/icon.png'] = master.read_bytes()
        outputs['assets/brand/foreground' + source.suffix.lower()] = source.read_bytes()

        def png(relative, size, transparent=False):
            target = stage / (str(len(outputs)) + '.png')
            if transparent:
                run([tool['executable'], '-background', 'none', source, '-resize', f'{round(size * .62)}x{round(size * .62)}', '-gravity', 'center', '-extent', f'{size}x{size}', '-strip', '-define', 'png:exclude-chunks=date,time', target], stage)
            else:
                run([tool['executable'], master, '-resize', f'{size}x{size}', '-strip', '-define', 'png:exclude-chunks=date,time', target], stage)
            if not target.is_file():
                raise ValueError(f'Missing generated icon: {relative}')
            outputs[relative] = target.read_bytes()

        for platform in platforms:
            if platform not in ('android', 'ios', 'macos', 'windows', 'linux', 'web'):
                raise ValueError(f'Unsupported brand platform: {platform}')
            if not (app / platform).is_dir():
                raise ValueError(f'Branding requires the {platform} runner')
            if platform == 'android':
                for density, pixels in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
                    png(f'android/app/src/main/res/mipmap-{density}/ic_launcher.png', pixels)
                    png(f'android/app/src/main/res/mipmap-{density}/ic_launcher_foreground.png', round(pixels * 108 / 48), True)
                outputs['android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml'] = b'<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@color/blueprint_icon_background"/><foreground android:drawable="@mipmap/ic_launcher_foreground"/></adaptive-icon>\n'
                outputs['android/app/src/main/res/values/blueprint_colors.xml'] = f'<resources><color name="blueprint_icon_background">{background}</color></resources>\n'.encode()
                png('android/app/src/main/res/drawable/blueprint_splash.png', 256, True)
                splash = b'<layer-list xmlns:android="http://schemas.android.com/apk/res/android"><item android:drawable="@color/blueprint_icon_background"/><item><bitmap android:gravity="center" android:src="@drawable/blueprint_splash"/></item></layer-list>\n'
                outputs['android/app/src/main/res/drawable/launch_background.xml'] = splash
                outputs['android/app/src/main/res/drawable-v21/launch_background.xml'] = splash
                outputs['android/app/src/main/res/values-v31/styles.xml'] = b'<resources><style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar"><item name="android:windowSplashScreenBackground">@color/blueprint_icon_background</item><item name="android:windowSplashScreenAnimatedIcon">@mipmap/ic_launcher_foreground</item><item name="android:windowBackground">@drawable/launch_background</item></style></resources>\n'
            elif platform in ('ios', 'macos'):
                folder = f'{platform}/Runner/Assets.xcassets/AppIcon.appiconset'
                contents = safe_file(app, folder + '/Contents.json')
                data = json.loads(contents.read_text())
                for entry in data['images']:
                    if 'filename' not in entry:
                        continue
                    filename = entry['filename']
                    if Path(filename).name != filename:
                        raise ValueError('Invalid Apple icon filename')
                    pixels = round(float(entry['size'].split('x')[0]) * float(entry.get('scale', '1x').rstrip('x')))
                    png(folder + '/' + filename, pixels)
                if platform == 'ios':
                    folder = 'ios/Runner/Assets.xcassets/LaunchImage.imageset'
                    contents = safe_file(app, folder + '/Contents.json')
                    if contents.is_file():
                        for entry in json.loads(contents.read_text())['images']:
                            if entry.get('filename'):
                                if Path(entry['filename']).name != entry['filename']:
                                    raise ValueError('Invalid launch image filename')
                                png(folder + '/' + entry['filename'], round(128 * float(entry.get('scale', '1x').rstrip('x'))), True)
                    storyboard = safe_file(app, 'ios/Runner/Base.lproj/LaunchScreen.storyboard')
                    if storyboard.is_file():
                        tree = ET.fromstring(storyboard.read_bytes())
                        for color in tree.iter('color'):
                            if color.attrib.get('key') == 'backgroundColor':
                                color.attrib.clear()
                                color.attrib.update(key='backgroundColor', red=str(int(background[1:3], 16) / 255), green=str(int(background[3:5], 16) / 255), blue=str(int(background[5:7], 16) / 255), alpha='1', colorSpace='custom', customColorSpace='sRGB')
                        outputs['ios/Runner/Base.lproj/LaunchScreen.storyboard'] = ET.tostring(tree, encoding='utf-8', xml_declaration=True)
            elif platform == 'windows':
                target = stage / 'app_icon.ico'
                run([tool['executable'], master, '-define', 'icon:auto-resize=256,128,64,48,32,16', target], stage)
                outputs['windows/runner/resources/app_icon.ico'] = target.read_bytes()
            elif platform == 'web':
                for size in (192, 512):
                    png(f'web/icons/Icon-{size}.png', size)
                    png(f'web/icons/Icon-maskable-{size}.png', size)
                png('web/favicon.png', 32)
            elif platform == 'linux':
                png('linux/runner/resources/app_icon.png', 256)
    inputs = {'foreground': foreground, 'foregroundSha256': file_hash(source.read_bytes()), 'background': background, 'platforms': sorted(platforms), 'tool': tool}
    # Default runner adoption is valid only while creating a fresh staged App.
    adopt = [path for path in outputs if path.split('/')[0] in platforms] if adopt_runner_assets else []
    changes = owned_changes(app, outputs, '.blueprint/brand.json', inputs, adopt=adopt)
    if plan_only:
        return changes
    if changes:
        FileTransaction(app, changes).commit()
    return {'schema': 1, 'status': 'PASS', 'changed': sorted(changes), 'outputs': sorted(outputs), 'tool': tool}
