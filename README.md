# // JITTER HUD (`JitterHud_Conky`)

A custom Conky + Lua telemetry HUD and hardware helper suite engineered to pair seamlessly with the matte-black and crimson (`#E11D2E`) **Jitter-Shadow** desktop theme on Linux XFCE and portable ARM64 cyberdecks.

### 🎨 Design Language
* **High-Contrast Crimson & Graphite:** Crisp `Fira Code` / `DejaVu Mono` typography, live Cairo graphs, and telemetry bars rendered over custom `684 × 684` HUD artwork (`jitter-bg.png`) designed for `#0D090A` and `#181012` dark surfaces.
* **Cyberdeck Telemetry & Display Supervision:** Tailored for `720 × 720` built-in cyberdeck screens with automatic display supervision (`jitter-start`) that keeps the HUD centered on the internal screen even when an external monitor is connected.

### 📦 Coverage
* **Core HUD Engine (`MAIN HUD CONF/`):** Conky window configuration (`jitter.conf`), the live Lua/Cairo rendering engine (`jitter-hud.lua`) for graphs, bars, weather, and telemetry, plus `jitter-bg.png` background artwork.
* **Hardware & Radio Helpers (`HUD scripts and helpers/`):** Modular shell utilities for USB enumeration (`jitter-usb`), serial-port detection (`jitter-ports`), hardware thermals (`jitter-temp`), Wi-Fi signal reporting (`jitter-wifi`), and environment diagnostics (`jitter-doctor`).
* **Optional Integrations:** Supports external battery telemetry (`~/.local/bin/jitter-batt`), custom user overrides (`~/.config/conky/jitter-hud.settings`), and Polychromatic red keyboard lighting (`jitter-keyboard-red.sh`).

## ⚙️ Installation

1. **Install required system packages** (Debian/Ubuntu-based syntax shown):
   ```bash
   sudo apt update && sudo apt install -y conky-all iproute2 iw lm-sensors usbutils x11-xserver-utils curl fonts-firacode
   ```

2. **Create your local configuration and binary directories:**
   ```bash
   mkdir -p ~/.config/conky ~/.local/bin
   ```

3. **Copy the HUD configuration and artwork into `~/.config/conky/`:**
   ```bash
   cp jitter.conf jitter-hud.lua jitter-bg.png ~/.config/conky/
   ```
   > **Note:** If you cloned or downloaded the repository with subfolders intact, run `cp "MAIN HUD CONF/"* ~/.config/conky/` instead.

4. **Install the helper scripts and make them executable:**
   ```bash
   cp jitter-* ~/.local/bin/
   chmod +x ~/.local/bin/jitter-*
   ```
   > **Note:** If copying from the repository subfolder, run `cp "HUD scripts and helpers/jitter-"* ~/.local/bin/` before running `chmod`.

5. **Verify your environment and launch the HUD:**
   ```bash
   ~/.local/bin/jitter-doctor
   ~/.local/bin/jitter-start
   ```
   > **Note:** Ensure `~/.local/bin` is included in your shell `$PATH` so you can run `jitter-*` commands from anywhere.
