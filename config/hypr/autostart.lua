-- Extra autostart processes.
-- o.launch_on_start("my-service")

o.launch_on_start("telegram -startintray")
o.launch_on_start("sh -c 'command -v xrandr >/dev/null 2>&1 && xrandr | grep -q \"DP-2 connected\" && xrandr --output DP-2 --primary || true'")
o.launch_on_start("kdeconnect-indicator")

