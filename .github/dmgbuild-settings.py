import os

application = os.environ["APP_PATH"]
background = os.environ["DMG_BACKGROUND_PATH"]
app_name = os.path.basename(application)

format = "UDZO"
files = [application]
symlinks = {"Applications": "/Applications"}

window_rect = ((200, 160), (720, 440))
default_view = "icon-view"
show_toolbar = False
show_sidebar = False
show_status_bar = False
show_pathbar = False
show_tab_view = False
show_icon_preview = False
include_icon_view_settings = "auto"

arrange_by = None
grid_offset = (0, 0)
grid_spacing = 120
scroll_position = (0, 0)
label_pos = "bottom"
text_size = 14
icon_size = 112

icon_locations = {
    app_name: (180, 242),
    "Applications": (540, 242),
}
