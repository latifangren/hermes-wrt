# Hermes-WRT custom files template
# Copy files here matching OpenWrt rootfs structure.
# They will be injected into the firmware at build time.

# Example structure:
# files/
# ├── etc/
# │   ├── config/           # default config (network, wireless, etc.)
# │   ├── banner            # login banner
# │   ├── rc.local          # startup commands
# │   └── uci-defaults/     # one-time setup scripts
# ├── usr/
# │   └── lib/lua/luci/themes/hermes/   # custom luci theme
# └── root/
#     └── install.sh
