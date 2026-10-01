"""Read selected packaged UI declarations without unpacking the application.

Original inspection helper. Default source is the user-supplied local bundle.
Run with Python 3; writes bundle-tokens.json alongside this file.
CSS offsets are Unicode character offsets; source hashes cover original bytes.
"""
import pathlib,struct,json,re,hashlib
P=pathlib.Path('/Users/max/Downloads/ChatGPT-Contents/Resources/app.asar')
with P.open('rb') as f:
 A=struct.unpack('<4I',f.read(16));H=json.loads(f.read(A[3]));OFFSET=8+A[1]
def walk(node=H,base=''):
 for n,v in node.get('files',{}).items():
  q=base+n
  if 'files' in v:yield from walk(v,q+'/')
  else:yield q,v
FILES=dict(walk())
def read(n):
 v=FILES[n]
 with P.open('rb') as f:f.seek(OFFSET+int(v['offset']));return f.read(v['size']).decode()
def decls(s):
 # Declarations retained with full containing block stack. Quote-aware braces.
 stack=[];start=0;quote=None;escape=False
 for i,c in enumerate(s):
  if quote:
   if escape:escape=False
   elif c=='\\':escape=True
   elif c==quote:quote=None
   continue
  if escape:
   escape=False;continue
  if c=='\\':escape=True;continue
  if c in ('\"',"'"):quote=c;continue
  if c=='{':stack.append(s[start:i].strip());start=i+1
  elif c in ';}':
   chunk=s[start:i].strip();m=re.match(r'(--[\w-]+|[\w-]+):(.+)$',chunk,re.S)
   if m:yield {'property':m[1],'value':m[2],'selector':list(stack),'character_offset':start}
   start=i+1
   if c=='}' and stack:stack.pop()
def digest(n):return hashlib.sha256(read(n).encode()).hexdigest()

import plistlib
from datetime import datetime, timezone

CSS_FILES = [
    'webview/assets/app-shared-b42a855b3317.css',
    'webview/assets/app-initial-a3898107ddbb.css',
    'webview/assets/app-primary-547a6c7b4fb3.css',
    'webview/assets/popover-33fff3f58ec9.css',
    'webview/assets/floating-navigation-rail-layout-17bd6c59412b.css',
]
EXACT = {
    '--spacing', '--text-xs', '--text-sm', '--text-base', '--text-lg',
    '--font-sans-default', '--font-content', '--font-mono-default',
    '--height-toolbar', '--height-titlebar', '--spacing-token-sidebar',
    '--border-width-hairline', '--transition-duration-basic',
    '--transition-duration-relaxed', '--color-token-side-bar-background',
    '--color-token-main-surface-primary', '--app-color-background-shell',
    '--app-color-background-surface', '--app-color-background-surface-under',
    '--app-color-background-editor-opaque', '--app-color-background-elevated-primary',
    '--app-color-background-elevated-primary-opaque', '--app-color-text-foreground',
    '--app-color-text-foreground-secondary', '--app-color-text-foreground-tertiary',
    '--color-surface', '--color-surface-secondary', '--color-surface-tertiary',
    '--color-surface-elevated', '--color-ring', '--color-border',
    '--menu-gutter', '--menu-radius', '--menu-font-size', '--menu-line-height',
    '--menu-item-padding', '--menu-item-radius', '--menu-item-background-color',
    '--menu-background-color', '--menu-box-shadow', '--popover-radius',
    '--tooltip-border-radius', '--tooltip-background-color', '--tooltip-text-color',
    '--tooltip-font-size', '--tooltip-compact-padding', '--tooltip-compact-font-size',
    '--app-shell-sidebar-divider', '--app-shell-main-surface-top-start-radius',
    '--app-shell-main-surface-top-end-radius',
}

def selected(file, d):
    prop = d['property']; context = ' '.join(d['selector'])
    if 'extension' in context and 'not([data-codex-window-type=extension])' not in context:
        return False
    if '@layer utilities' in context:
        return False
    if prop in EXACT:
        return True
    if re.match(r'^--(?:gray-fixed-(?:0|50|100|150|500|550|700|750|800|850|900)|radius-.*-base|control-size-.+|control-icon-size-.+|font-text-(?:xs|sm|md)-(?:size|line-height))$', prop):
        return True
    if '_Button_eg66f_2:focus-visible:after' in context:
        return True
    if '_Button_eg66f_2[data-disabled]' in context and ':not(' not in context and prop in ('opacity', 'transform', 'cursor'):
        return True
    if 'bo1ta' in context and prop == 'background-color' and ('_PageSurfaceLayout' in context or '_FloatingHeader' in context):
        return True
    if 'popover-33' in file and prop in ('border-radius', 'background', 'transition-duration'):
        return True
    if 'floating-navigation-rail' in file and prop == 'transition-duration':
        return True
    return False

assets = []
for name in CSS_FILES:
    content = read(name)
    assets.append({'file': name, 'size_bytes': FILES[name]['size'],
                   'sha256': digest(name),
                   'declarations': [d for d in decls(content) if selected(name, d)]})

SHARED_JS = 'webview/assets/app-shared-5d8e744d1fa1.js'
POPOVER_JS = 'webview/assets/popover-65d93efc06aa.js'
BEHAVIORS = [
    (SHARED_JS, 'dismiss_top_layer', 'e.key===`Escape`&&(i?.(e),!e.defaultPrevented&&c',
     'Dismissable layer handles Escape only for its top layer; consumers may prevent the default dismissal.'),
    (SHARED_JS, 'modal_focus', 'trapFocus:n.open,disableOutsidePointerEvents:n.open',
     'DialogContentModal traps focus while open, prevents outside focus, and restores focus to its trigger by default.'),
    (SHARED_JS, 'menu_key_map', 'hy=[`Enter`,` `],Cje=[`ArrowDown`,`PageUp`,`Home`]',
     'Menu primitives declare activation and boundary navigation keys; left/right submenu direction is RTL aware.'),
    (SHARED_JS, 'menu_disabled_and_typeahead', 'let t=E.current+e,n=b().filter(e=>!e.disabled)',
     'Menu typeahead filters disabled entries, tracks a one-second search buffer, and focuses matching text.'),
    (SHARED_JS, 'menu_selection_close', 't.defaultPrevented?l.current=!1:o.onClose()',
     'Selecting an enabled menu item dispatches a cancelable select event and closes unless prevented.'),
    (SHARED_JS, 'menu_trigger_keys', '[`Enter`,` `].includes(e.key)&&a.onOpenToggle()',
     'Dropdown trigger opens/toggles with Enter or Space; ArrowDown opens; disabled trigger guards these actions.'),
    (SHARED_JS, 'menu_focus_restore', 'o.current||i.triggerRef.current?.focus(),o.current=!1',
     'Dropdown close restores trigger focus unless an outside-interaction condition has been recorded.'),
    (POPOVER_JS, 'popover_collision', 'avoidCollisions:t??!0,hideWhenDetached:!0,collisionPadding:20',
     'Popover has collision avoidance and hides when its anchor detaches; base side offset is 8.'),
    (POPOVER_JS, 'popover_hover', 'hoverOpenDelay:r=150',
     'Optional hover opening has a 150ms default delay; touch pointer movement does not trigger hover opening.'),
    (POPOVER_JS, 'popover_keyboard', 'e.target===t&&e.key===`Tab`&&e.shiftKey',
     'Popover focuses its content on opening when configured, and Shift-Tab from the container focuses its last focusable descendant.'),
    (POPOVER_JS, 'popover_escape_override', 'onEscapeKeyDown:p,onKeyDown:',
     'This wrapper overrides Escape with an imported handler; this excerpt alone does not establish its final dismissal behavior.'),
]
behaviors = []
for name, key, needle, statement in BEHAVIORS:
    content = read(name); offset = content.index(needle)
    behaviors.append({'id': key, 'file': name, 'source_sha256': digest(name),
                      'character_offset': offset, 'evidence_excerpt': needle,
                      'finding': statement, 'kind': 'static_implementation'})
for name in (SHARED_JS, POPOVER_JS):
    assets.append({'file': name, 'size_bytes': FILES[name]['size'], 'sha256': digest(name)})
with (P.parent.parent / 'Info.plist').open('rb') as f:
    info = plistlib.load(f)
result = {
    'captured_at': datetime.now(timezone.utc).isoformat(),
    'bundle_directory': str(P.parent.parent), 'archive': str(P),
    'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
    'archive_size_bytes': P.stat().st_size, 'asar_data_offset': OFFSET,
    'header_sha256': hashlib.sha256(json.dumps(H, separators=(',',':')).encode()).hexdigest(),
    'header_hash_scope': 'parsed header reserialized with compact JSON separators',
    'scope': 'Selected packaged static declarations and JavaScript primitives; not computed styles or a complete official design specification.',
    'assets': assets, 'behaviors': behaviors,
    'not_verified': ['runtime theme overrides', 'native titlebar computed appearance', 'actual menu/popover interaction', 'live accessibility tree', 'all platform designs'],
}
out = pathlib.Path(__file__).with_name('bundle-tokens.json')
out.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
print(f'{out}: {sum(len(x.get("declarations", [])) for x in assets)} declarations; {len(behaviors)} behaviors; {out.stat().st_size} bytes')
