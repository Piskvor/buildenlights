# buildenlights
Shows a literal green or red light according to build status.

## Requirements

- a switchable USB hub (see [a list of working devices](https://github.com/mvp/uhubctl#user-content-compatible-usb-hubs) for a recommended list), or a device with an integrated switchable hub (e.g. RPi 3B+)
- two lights, green and red, to plug into the hub (one is necessary, two are better)
- bash
- [uhubctl](https://github.com/mvp/uhubctl#user-content-compiling) to switch the USB ports on and off (this currently requires a Mac or a Linux)
- [curl](https://curl.haxx.se/) for requesting the repo status
- [jq](https://stedolan.github.io/jq/) for parsing the status result

## Operation

- USB hub is connected to a computer
- lights connected to hub
- buildenlights runs in a loop or periodically
   - checks GitHub repo status (using curl+jq)
   - if status is "success", turns green light on (using uhubctl)
   - if status is "failed", turns red light on (using uhubctl)
