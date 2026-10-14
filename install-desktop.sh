#!/bin/bash
# Adds Pip to the app launcher: writes ~/.local/share/applications/pip-penguin.desktop pointing at
# pip.sh in this directory. Launching it starts Pip; launching it again stops it.
# `./install-desktop.sh --remove` takes the entry away.
set -euo pipefail
dir=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
apps=${XDG_DATA_HOME:-$HOME/.local/share}/applications
file=$apps/pip-penguin.desktop
if [ "${1:-}" = "--remove" ]; then
    rm -f "$file"
    echo "removed $file"
    exit 0
fi
for f in bin/mantle bin/mantle-renderer pip.sh; do
    [ -x "$dir/$f" ] || { echo "missing $dir/$f" >&2; exit 1; }
done
mkdir -p "$apps"
cat > "$file" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Pip the Penguin
GenericName=Desktop mascot
Comment=A penguin that wanders onto your screen now and then. Launch again to send it home.
Exec="$dir/pip.sh"
Icon=$dir/pip.svg
Terminal=false
Categories=Amusement;Game;
Keywords=penguin;mascot;tux;pet;
DESKTOP
command -v update-desktop-database >/dev/null && update-desktop-database "$apps" 2>/dev/null || true
echo "wrote $file"
