# Character Dialogue

Character Dialogue is a VMF mod for browsing and controlling individual Vermintide 2 voice lines. It uses stable Wwise event IDs, persists only user overrides, and leaves unmodified dialogue on the vanilla path.

The full catalogue is generated offline from `Vermintide-2-Source-Code/dialogues/generated/*.lua`:

```powershell
py -3 tools/dialogue/generate_catalogue.py --source C:\path\to\Vermintide-2-Source-Code\dialogues\generated --output character_dialogue\scripts\mods\character_dialogue\character_dialogue_catalogue.lua
```

Preview playback is local-only. Natural dialogue selection remains host-authoritative and sends only vanilla dialogue IDs/indexes through the existing engine RPC.
