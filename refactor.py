import os

files = [
    "scripts/run/windsurf_mac_id_modifier.sh",
    "scripts/run/windsurf_linux_id_modifier.sh",
    "scripts/run/windsurf_win_id_modifier.ps1",
    "scripts/hook/windsurf_hook.js",
    "scripts/hook/inject_hook_win.ps1",
    "scripts/hook/inject_hook_unix.sh",
    "README.md",
    "README_CN.md",
    "README_JP.md"
]

replacements = [
    ("Cursor", "Windsurf"),
    ("cursor", "windsurf"),
    ("CURSOR", "WINDSURF")
]

for file_path in files:
    if os.path.exists(file_path):
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        for old, new in replacements:
            content = content.replace(old, new)
        
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Processed {file_path}")
    else:
        print(f"File not found: {file_path}")
