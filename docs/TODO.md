# TODO:

## sourceSPAP

- [ ] Receive and interpret all types of [network commands from the Archipelago server](https://github.com/ArchipelagoMW/Archipelago/blob/main/docs/network%20protocol.md#server---client)
  - [ ] RoomInfo
  - [ ] ConnectionRefused
  - [ ] Connected
  - [ ] ReceivedItems
  - [ ] LocationInfo
  - [ ] RoomUpdate
  - [ ] PrintJSON
  - [ ] DataPackage
  - [ ] Bounced
  - [ ] InvalidPacket
  - [ ] Retrieved
  - [ ] SetReply
- [ ] Send all types of [client network commands](https://github.com/ArchipelagoMW/Archipelago/blob/main/docs/network%20protocol.md#client---server) to the Archipelago server
  - [ ] Connect
  - [ ] ConnectUpdate
  - [ ] Sync
  - [ ] LocationChecks
  - [ ] LocationScouts
  - [ ] CreateHints
  - [ ] UpdateHint
  - [ ] StatusUpdate
  - [ ] Say
  - [ ] GetDataPackage
  - [ ] Bounce
  - [ ] Get
  - [ ] Set
  - [ ] SetNotify
- [ ] Separate common functionality from game-specific functionality
- [ ] Support connecting to secure websockets (`wss://`)
  - Currently fails due to a certificate error. Under the hood, it is supposed to call `CERT_STORE_PROV_SYSTEM/Root` from the win32 API.
- [ ] Support connecting to the official Archipelago server (`ws://archipelago.gg:#####`)
  - Currently fails due to not being able to read the HTTP status. This could have something to do with **[sm-ext-websocket](https://github.com/ProjectSky/sm-ext-websocket)** not supporting TLS 1.3. This could potentially be fixed by building it from source with the latest version of **[IXWebSocket](https://github.com/machinezone/IXWebSocket)**.

## SourceMod

- [ ] Reverse engineer Portal binaries to potentially enable `sdkhooks` and `sdktools` functions by populating SourceMod `gamedata` for Portal
  - This process requires [signature scanning](https://wiki.alliedmods.net/Signature_Scanning). It is not completely clear yet what the process of doing this is, so a number of potentially useful resources are listed below:
    1. Read the linked wiki page above thoroughly.
    2. Install the Linux packages `binutils` (which includes `objdump`).
    3. For the Linux version of the game, navigate to `/.../steam/steamapps/common/<GAME_NAME>/<GAME_FOLDER>/bin/` and run the command `objdump server.so -d > server.so.objdump`.
    4. Follow [this video](https://www.youtube.com/watch?v=SD6Rn2D7IGo) as a guide.
    5. Add the needed signatures to a new `gamedata` file following [this guide](https://wiki.alliedmods.net/User:Nosoop/Guide/Advanced#Creating_Signatures).
  - [ ] Document the reverse engineering process so it can be reproduced by others for future game support
  - [ ] Consider contributing to **[SourceMod](https://github.com/alliedmodders/sourcemod)** with the newly created `gamedata` files

## [Portal APWorld](https://github.com/jack5github/Archipelago-Portal-1)

- [ ] Determine all possible regions
- [ ] Determine all possible locations/checks for each region
  - This is highly dependent on what is possible in SourceMod, [see above](#sourcemod).
- [ ] Determine all possible items that can be unlocked in each location
  - [Same as before](#sourcemod).
- [ ] Codify all aspects of the APWorld so it can be used by sourceSPAP
