"""Finder layout for the drag-to-Applications disk image."""
from pathlib import Path

app = Path(defines['app']).resolve()
files = [str(app)]
symlinks = {'Applications': '/Applications'}
icon = str(app / 'Contents/Resources/AppIcon.icns')
format = 'UDZO'
filesystem = 'HFS+'
background = str(Path(defines['background']).resolve())
window_rect = ((200, 200), (640, 460))
default_view = 'icon-view'
icon_size = 96
text_size = 13
icon_locations = {'reson.app': (160, 194), 'Applications': (480, 194)}
show_status_bar = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
