# Orca

`orca-ide` launches the desktop app; `orca` provides the CLI.

## Linux computer use

Requires a desktop session with D-Bus and AT-SPI. On NixOS:

```nix
services.gnome.at-spi2-core.enable = true;
```

Log out and back in after enabling the service.

The package supplies Python/GI dependencies. Set
`ORCA_COMPUTER_DESKTOP_SCRIPT_PROVIDER_PATH` to use a custom provider.

## Checks

Install checks verify the CLI version and Linux GI imports. To check macOS
signatures from Linux:

```sh
nix build .#checks.x86_64-linux.codesign-orca
```
