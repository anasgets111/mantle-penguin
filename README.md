# Pip the Penguin

A desktop penguin with no function, built on the [Mantle](https://github.com/anasgets111/mantle)
shell engine in one Lua file.

Every 20–90 s Pip waddles in from the side or peeks up from the bottom edge, does one to three of
32 antics, maybe says something, and leaves. Grab it and throw it while it's out; click it for a
giggle, or to wake it up when it dozes off. While hidden, its panel is unmapped, so nothing is
drawn or composited.

## Run it

Needs Mantle 0.9 or later and a compositor with layer-shell (niri, Hyprland, Sway, ...).

```sh
./pip.sh                # start Pip; run it again to send Pip home
./install-desktop.sh    # add "Pip the Penguin" to your app launcher
./install-desktop.sh --remove
```

Or run it directly with `mantle -c . -d`.
