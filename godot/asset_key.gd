class_name AssetKey
# Decryption key for the embedded asset bundle (assets.enc).
# The repo version is always EMPTY (game falls back to generated art).
# package.ps1 temporarily injects the real key (config/asset_key.txt, gitignored)
# during export, then restores this placeholder. The key ships inside the exe --
# same casual-extraction protection tier as Godot's built-in PCK encryption.
# ASCII only: package.ps1 rewrites this file with Windows PowerShell 5.1.
const KEY := ""





