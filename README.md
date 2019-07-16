# buildenlights
Shows a literal green or red light according to build status.

## Overview

- USB hub is connected to a computer
- lights are connected to the hubs
- buildenlights runs in a loop or periodically
   - checks GitHub repo status (using curl+jq)
   - if status of all branches is "success", turns green light on (using uhubctl)
   - if status of any branch is "failed", turns red light on (using uhubctl)
   - if the checks fail (e.g. network unreachable), turns both lights off.

## Requirements

- a computer/device running Linux, OSX or similar UN*Xlike (uhubctl apparently has [no Windows support](https://github.com/mvp/uhubctl/issues/79))
- a switchable USB hub (see [a list of working devices](https://github.com/mvp/uhubctl#user-content-compatible-usb-hubs) for a recommended list) - note that some devices already have a hub integrated (e.g. RPi 3B+)
- two lights (e.g. green and red, one to indicate success, the other for failure), to plug into the hub (one is necessary, two are better)
- bash
- [uhubctl](https://github.com/mvp/uhubctl#user-content-compiling) to switch the USB ports on and off
- [curl](https://curl.haxx.se/) for requesting the repo status
- [jq](https://stedolan.github.io/jq/) for parsing the status result

## Configuration

- Connect the USB hub to your device and run `uhubctl`
    - You should see something like this:
    
    ```
    Current status for hub 1-1.3 [05e3:0608 USB2.0 Hub, USB 2.10, 4 ports]
          Port 1: 0100 power
          Port 2: 0100 power
          Port 3: 0100 power
          Port 4: 0100 power
    ```
    - The interesting parts are the location (`1-1.3`) and the device identification (`05e3:0608`), those depend on your specific setup.
    - If uhubctl complains `No compatible smart hubs detected!` but works with sudo, it also offers a fix. Note that you need to edit the vendor ID - in this case, this would be `ATTR{idVendor}=="05e3"` (the first part of the device ID). 
    - If you see multiple hubs, try unplugging the one you want and see which disappears from the list.
    - Plug the lights into the hub, and try cycling each port (`--action 2`) - that will give you the port numbers for each light: `for X in 1 2 3 4; do uhubctl --loc 1-1.3 --action 2 --delay 10 --port $X; sleep 10; done`, where `--loc` is taken from the output above (I have 4 ports in the listing, so I try them `in 1 2 3 4`, similarly for e.g. 7-port hubs). Note the port number when a light is turned off.
    
- In your GitHub account, make a Personal access token
    - Needs the "repo" permission
    - Copy the token
    
- Copy buildenlights.rc.example to buildenlights.rc and edit the config
    - `REPO_OWNER`, `REPO_NAME`and `PERSONAL_ACCESS_TOKEN` are required for GH access
    - `REFS` is a list of branches (or other [git-refs](https://git-scm.com/book/en/v2/Git-Internals-Git-References)) to watch - they will be checked in order. Note that they're space-separated.
    - `USB_DEVICE_ID` and `USB_DEVICE_LOCATION` are recommended, so that you don't switch multiple hubs by accident - copy these from your uhubctl output.
    - `USB_PORT_SUCCESS` is the USB hub port number for the green light - either set to `-` (off), or to the number seen when cycling the individual ports.
    - `USB_PORT_FAILURE` is the USB hub port number for the red light - either set to `any` (all ports of the hub are used), or to the number seen when cycling the individual ports.

## Running

- Simplest case: `buildenlights.sh --infinite-loop` - waits for `DELAY_SECONDS` between each run.  
- Nohup: `nohup buildenlights.sh --infinite-loop &` - doesn't exit with terminal
- Cron or similar scheduler: `*/10 * * * * * /home/your/path/buildenlights.sh > /dev/null 2> /dev/null` - ignores the `DELAY_SECONDS` variable
- Systemd: example units are provided in `systemd-example/`, one which loops via systemd, other looping internally 
