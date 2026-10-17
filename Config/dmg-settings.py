# Lemon's install window (dmgbuild settings), used by scripts/release.sh:
#   dmgbuild -s Config/dmg-settings.py -D app=build/export/Lemon.app Lemon build/Lemon-X.Y.dmg
# The background is drawn by scripts/make-dmg-background.py; icon positions match it (centres, from the top left).

app = defines.get("app", "build/export/Lemon.app")  # noqa: F821 (provided by dmgbuild)

files = [app]
symlinks = {"Applications": "/Applications"}
hide_extension = ["Lemon.app"]

background = "Config/dmg/background.tiff"
window_rect = ((200, 140), (660, 428))  # 400 of content plus the title bar
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 112
text_size = 13
icon_locations = {"Lemon.app": (170, 200), "Applications": (490, 200)}

format = "UDZO"
filesystem = "HFS+"
