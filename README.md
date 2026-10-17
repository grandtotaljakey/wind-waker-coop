# Wind Waker co-op — easy Windows setup

**[Download the small setup ZIP (about 29 MB)](https://github.com/grandtotaljakey/wind-waker-coop/releases/latest/download/Wind-Waker-Coop-Setup.zip)**

1. Extract the ZIP, then double-click **Install-Coop.bat**.
2. Open the **Wind Waker - Join** shortcut on your desktop.
3. On first play, connect [Tailscale](https://tailscale.com/download/windows), choose your own clean **USA GZLE01 Wind Waker ISO**, and enter Jake's host address.

Windows 10/11 x64. No Git, Python, compiler, or administrator access is needed for the co-op installer. Tailscale has its own installation and sign-in. If Dolphin reports a missing MSVC DLL, install the [Microsoft Visual C++ x64 runtime](https://aka.ms/vc14/vc_redist.x64.exe).

## Prefer PowerShell? Paste these three lines

```powershell
$repo = 'grandtotaljakey/wind-waker-coop'
Invoke-WebRequest "https://github.com/$repo/releases/latest/download/Install-Coop.ps1" -OutFile "$env:TEMP\Install-Coop.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\Install-Coop.ps1" -Repository $repo
```

The default folder is `Games\Wind-Waker-Coop` inside your Windows user folder. For another location, append `-InstallPath 'D:\Games\Wind-Waker-Coop'` to the last line.

## Updates

Close the game and double-click **Update-Coop.bat** in the install folder. Update **both PCs** before playing together. The mod download is about **5.6 MB**; the emulator downloads only when its files change or need repair. Downloads are checked with SHA-256 and interrupted downloads can resume. The installer preserves your `play` folder, controllers, settings, saves, and optional HD textures.

Jake opens **Host-Dungeon.bat** instead of Join. Save inside the game before closing it. Keep your clean ISO available; a changed native patch is prepared locally from it when needed. No full game image is hosted here.

## Optional HD later

Original textures, clothing colors, and live teammate portraits work with the quick setup. For the larger Hypatia HD pack, obtain the original full `Wind-Waker-Coop.zip` from Jake, run **Add-HD-Textures.bat**, and select that ZIP. Only textures and their credits are imported. The HD pack is about 2.9 GB compressed / 9.2 GiB extracted, and is not required to play.

## Current build

This is experimental Dragon Roost Cavern co-op using the `dungeon-sync-working` candidate. Recent local native checks cover loot allocation and inventory recovery. Some dungeon interactions and the exact previously reported two-PC pickup failure remain unresolved. Installing successfully does not establish that every gameplay bug is fixed.

Helper: modified [StephenSHorton/ww-multiplayer](https://github.com/StephenSHorton/ww-multiplayer), MIT license included. Emulator: [Dolphin 2609a](https://github.com/dolphin-emu/dolphin/tree/2609a), with its license files in the download. Optional texture artwork: Hypatia, credited in the full pack.
