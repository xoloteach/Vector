# Environment

Toolchain recorded from the build sandbox on **2026-09-22**. Versions are
pinned so the project can be rebuilt byte-similarly later.

## Host

| | |
| --- | --- |
| OS | Amazon Linux 2023 (`ID_LIKE=fedora`) |
| Arch | `x86_64` |
| Package manager | `dnf` |
| Network | open internet |

## Tools

| Tool | Version | Source |
| --- | --- | --- |
| Godot | `4.7.2.stable.official.ed1daf0bf` | GitHub release, `Godot_v4.7.2-stable_linux.x86_64.zip` |
| Godot export templates | `4.7.2.stable` | GitHub release, `Godot_v4.7.2-stable_export_templates.tpz` |
| Blender | `4.5.14 LTS` (build 2026-09-15) | `mirror.clarkson.edu/blender/release/Blender4.5/blender-4.5.14-linux-x64.tar.xz` |
| Git | `2.50.1` | preinstalled |
| Python | `3.9.25` (system) | preinstalled; Blender ships its own 3.11 for `bpy` |
| Node.js | `22.23.2` | preinstalled (nvm) |
| Chromium | `Google Chrome for Testing 153.0.8010.12` | Playwright browser bundle |
| Playwright | latest (`npm i -g playwright`) | npm |
| ffmpeg | `n7.0.1-playwright-build-1011` | Playwright bundle |

`download.blender.org` sits behind a Cloudflare challenge that blocks
non-interactive fetches. Use a community mirror
(`mirror.clarkson.edu`, `ftp.nluug.nl`, `mirrors.dotsrc.org`) instead.

## Reproducing the toolchain

```bash
# --- system libraries (Blender and Chromium both need these) ---
dnf install -y xz mesa-libGL mesa-libEGL mesa-dri-drivers \
  libXi libXxf86vm libXfixes libXrender libXcursor libXinerama libXrandr \
  libSM libICE libxkbcommon libdecor

# --- Godot 4.7.2 + export templates ---
mkdir -p /opt/tools && cd /opt/tools
V=4.7.2-stable
wget -O godot_linux.zip \
  "https://github.com/godotengine/godot/releases/download/${V}/Godot_v${V}_linux.x86_64.zip"
wget -O godot_templates.tpz \
  "https://github.com/godotengine/godot/releases/download/${V}/Godot_v${V}_export_templates.tpz"
unzip -oq godot_linux.zip
chmod +x Godot_v${V}_linux.x86_64
ln -sf /opt/tools/Godot_v${V}_linux.x86_64 /usr/local/bin/godot

# Templates must land in a directory named exactly "<version>.stable"
mkdir -p tpl && unzip -oq godot_templates.tpz -d tpl
TPLDIR="$HOME/.local/share/godot/export_templates/4.7.2.stable"
mkdir -p "$TPLDIR"
cp tpl/templates/web* tpl/templates/linux* "$TPLDIR/"

# --- Blender 4.5 LTS (headless art pipeline) ---
cd /opt/tools
wget -O blender.tar.xz \
  "https://mirror.clarkson.edu/blender/release/Blender4.5/blender-4.5.14-linux-x64.tar.xz"
tar xf blender.tar.xz
ln -sf /opt/tools/blender-4.5.14-linux-x64/blender /usr/local/bin/blender

# --- Chromium + ffmpeg for capture and smoke tests ---
npm i -g playwright@latest
npx playwright install chromium       # NOTE: omit --with-deps, it assumes apt
ln -sf /opt/playwright/chromium-*/chrome-linux64/chrome /usr/local/bin/chromium
ln -sf /opt/playwright/ffmpeg-*/ffmpeg-linux /usr/local/bin/ffmpeg
```

### Verify

```bash
godot --version      # 4.7.2.stable.official.ed1daf0bf
blender --version    # Blender 4.5.14 LTS
chromium --version
ffmpeg -version
ls ~/.local/share/godot/export_templates/4.7.2.stable/web_nothreads_release.zip
```

## Gotchas found the hard way

- `npx playwright install --with-deps` fails on Amazon Linux — it shells out to
  `apt-get`. Install the system libraries with `dnf` first, then run
  `playwright install chromium` without `--with-deps`.
- `tar xf *.tar.xz` fails until `xz` is installed; the error is the misleading
  `xz: Cannot exec`.
- Blender fails with `libGL.so.1: cannot open shared object file` even in
  `--background` mode until `mesa-libGL` is present.
- The export templates directory name must match Godot's version string
  exactly, or exports fail with "no export template found".
- Chromium must run with `--no-sandbox` as root in this container.
