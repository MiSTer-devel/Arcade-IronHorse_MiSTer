# Iron Horse for [MISTer](https://github.com/MiSTer-devel/Main_MiSTer/wiki)
An FPGA implementation of Iron Horse for the MiSTer platform

## Credits
- Sorgelig: MiSTer project lead
- Ace: Core design and Konami custom chip implementations
- ElectronAsh: Assistance with Konami custom chip implementations
- Steve C. - Shiffy: Sourcing a bootleg Iron Horse PCB for reverse-engineering
- JimmyStones: High score saving support & pause feature
- Kitrinx: ROM loader

## Features
- Logic modelled to match the original as closely as possible
- Standard joystick and keyboard controls
- High score saving
- Greg Miller's cycle-accurate MC6809E CPU core with modifications by Sorgelig
- T80s CPU by Daniel Wallner with fixes by MikeJ, Sorgelig, and others
- YM2203 implementation using JT03 by Jotego
- Modeling of bootleg PCBs' timing and graphical differences
- Fully-tuned audio filters including the PCB's switchable low-pass filters
- Option for normalized video timings to use with picky HDTVs and monitors (underclocks the game by ~1.8%)

## Installation
Place `*.rbf` into the "_Arcade/cores" folder on your SD card.  Then, place `*.mra` into the "_Arcade" folder and ROM files from MAME into "games/mame".

### ****ATTENTION****
ROMs are not included. In order to use this arcade core, you must provide the correct ROMs.

To simplify the process, .mra files are provided in the releases folder that specify the required ROMs along with their checksums.  The ROM's .zip filename refers to the corresponding file in the M.A.M.E. project.

Please refer to https://github.com/MiSTer-devel/Main_MiSTer/wiki/Arcade-Roms for information on how to setup and use the environment.

Quick reference for folders and file placement:

/_Arcade/<game name>.mra
/_Arcade/cores/<game rbf>.rbf
/games/mame/<mame rom>.zip
/games/hbmame/<hbmame rom>.zip

## Controls
### Keyboard
| Key | Function |
| --- | --- |
| 1 | 1-Player Start |
| 2 | 2-Player Start |
| 5, 6 | Coin |
| 9 | Service Credit |
| Arrow keys | Movement |
| CTRL | Power |
| ALT | Shoot |
| Space | Crouch |

### Joystick
| Joystick action | Function |
| --- | --- |
| D-Pad | Movement |
| Y | Power |
| B | Attack |
| A | Crouch |

## Known Issues
1) Although bootleg flaws are modeled, sprite flickering is not 100% accurate
2) The high score system may cause lockups or unusual behavior when high scores are loaded with normalized video timings
3) The volume scale of the YM2203's SSG section needs further verification

## High score save/load

Save and load of high scores is supported for this core:

To save your high scores manually, press the 'Save Settings' option in the OSD.  High scores will be automatically loaded when the core is started.

To enable automatic saving of high scores, turn on the 'Autosave Hiscores' option, press the 'Save Settings' option in the OSD, and reload the core.  High scores will then be automatically saved (if they have changed) any time the OSD is opened.

High score data is stored in /media/fat/config/nvram/ as ```<mra filename>.nvm```
