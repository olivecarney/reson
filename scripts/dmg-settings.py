"""Finder layout for the drag-to-Applications disk image."""
from pathlib import Path
from importlib.metadata import distribution

app = Path(defines['app']).resolve()
# The bundled arrow background retains dmgbuild's MIT notice.
dist = distribution('dmgbuild')
license_file = next(p for p in dist.files if p.name == 'LICENSE')
files = [str(app), (str(dist.locate_file(license_file)), '.background-license.txt')]
symlinks = {'Applications': '/Applications'}
icon = str(app / 'Contents/Resources/AppIcon.icns')
format = 'UDZO'
filesystem = 'HFS+'
background = 'builtin-arrow'
window_rect = ((200, 200), (640, 280))
default_view = 'icon-view'
icon_size = 96
text_size = 13
icon_locations = {'Reson.app': (140, 120), 'Applications': (500, 120)}
show_status_bar = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
