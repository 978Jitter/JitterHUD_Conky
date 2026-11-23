# // JITTER HUD (`JitterHud_Conky`)

A custom Conky + Lua telemetry HUD and hardware helper suite engineered to pair seamlessly with the matte-black and crimson (`#E11D2E`) **Jitter-Shadow** desktop theme on Linux XFCE and portable ARM64 cyberdecks.

### 🎨 Design Language
* **High-Contrast Crimson & Graphite:** Crisp `Fira Code` / `DejaVu Mono` typography, live Cairo graphs, and telemetry bars rendered over custom `684 × 684` HUD artwork (`jitter-bg.png`) designed for `#0D090A` and `#181012` dark surfaces.
* **Cyberdeck Telemetry & Display Supervision:** Tailored for `720 × 720` built-in cyberdeck screens with automatic display supervision (`jitter-start`) that keeps the HUD centered on the internal screen even when an external monitor is connected.

### 📦 Coverage
* **Core HUD Engine (`MAIN HUD CONF/`):** Conky window configuration (`jitter.conf`), the live Lua/Cairo rendering engine (`jitter-hud.lua`) for graphs, bars, weather, and telemetry, plus `jitter-bg.png` background artwork.
* **Hardware & Radio Helpers (`HUD scripts and helpers/`):** Modular shell utilities for USB enumeration (`jitter-usb`), serial-port detection (`jitter-ports`), hardware thermals (`jitter-temp`), Wi-Fi signal reporting (`jitter-wifi`), and environment diagnostics (`jitter-doctor`).
* **Optional Integrations:** Supports external battery telemetry (`~/.local/bin/jitter-batt`), custom user overrides (`~/.config/conky/jitter-hud.settings`), and Polychromatic red keyboard lighting (`jitter-keyboard-red.sh`).

### ⚙️ Installation
1. Install core dependencies (`conky-all`, `iproute2`, `iw`, `lm-sensors`, `usbutils`, `x11-xserver-utils`, `curl`, `fonts-firacode`), then copy the HUD files and helpers into place:
   ```bash
   mkdir -p ~/.config/conky ~/.local/bin
   cp "MAIN HUD CONF/jitter.conf" "MAIN HUD CONF/jitter-hud.lua" "MAIN HUD CONF/jitter-bg.png" ~/.config/conky/
   cp "HUD scripts and helpers/jitter-"* ~/.local/bin/
   chmod +x ~/.local/bin/jitter-*

Place HUD configs & artwork in ~/.config/conky/:
mkdir -p ~/.config/conky ~/.local/bin
cp "MAIN HUD CONF/jitter.conf" "MAIN HUD CONF/jitter-hud.lua" "MAIN HUD CONF/jitter-bg.png" ~/.config/conky/

Install & mark helper scripts executable in ~/.local/bin/:
cp "HUD scripts and helpers/jitter-start" \
   "HUD scripts and helpers/jitter-doctor" \
   "HUD scripts and helpers/jitter-usb" \
   "HUD scripts and helpers/jitter-ports" \
   "HUD scripts and helpers/jitter-temp" \
   "HUD scripts and helpers/jitter-wifi" \
   "HUD scripts and helpers/jitter-keyboard-red.sh" \
   ~/.local/bin/
chmod +x ~/.local/bin/jitter-*

Path Note: Some configs and scripts currently reference /home/jitter—update paths to match your user ($HOME) if deploying under a different username.
