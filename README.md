# mac-config-shell

<p align='center'>A "shell" script which configures machine on macOS based on architecture<br/><b>Compatible with Apple Silicon</b></p>

## Note

> This configuration was made for remote employee who work always from home and has it's secure home for it. No one touches to my machine

**I do not guarantee nor support for your any damage & data loss, do & run it at your own risk**

Looking similar for Windows? Look at [here](https://github.com/dalisoft/win-install)

## Used projects

- <https://github.com/mathiasbynens/dotfiles/blob/main/.macos>

## Guide

If you want guide (optional), there exists a file. See [here](./guide.md)

## Pre-installation

- Give "Full-disk access" for "Terminal" ([guide](https://www.howtoisolve.com/full-disk-access-full-permissions-on-mac/))
- Import a "dotfiles" `.terminal` theme into "Terminal"
- Login into "macOS App Store" and download any app ([guide](https://support.apple.com/en-uz/guide/app-store/fir6253293d/3.0/mac/12.0))

## Installation

```shell
# go-to your desired downloads folder
git clone https://github.com/dalisoft/mac-config-shell.git
cd mac-config-shell
sh install.sh
> "YOUR_PASSWORD"
```

## Old histories

- [`78c55d`](https://github.com/dalisoft/config/commit/78c55d1182d93ccde8b5a82958ee3afbbbf9e2bd) until [`409750`](https://github.com/dalisoft/config/commit/4097507eb225644425e37dca15965f3a2b0aca40) commits, see [compare](https://github.com/dalisoft/ansible-config/compare/78c55d...409750)
- [`ae9e98`](https://github.com/dalisoft/ansible-config/commit/ae9e9892b770ab3817107a56271a96d6deb1558a) until [`fe1c09`](https://github.com/dalisoft/ansible-config/commit/fe1c09426aec767ba8471f496e91bb21a0be091b) commits, see [compare](https://github.com/dalisoft/ansible-config/compare/ae9e98...fe1c09)

## License

Apache-2.0 License
