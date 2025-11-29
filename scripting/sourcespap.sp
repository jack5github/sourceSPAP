#include <sourcemod>
#include <json>
// <sdkhooks> cannot set up its event listeners in Portal
// Portal does not support <sdktools_functions> methods
#include <websocket>

// Strings must contain 1 extra character to be terminated
public char thisPluginName[11] = "sourceSPAP";

public Plugin myinfo =	 // Variable must be called 'myinfo'
	{
		name				= thisPluginName,
		author			= "Jack5",
		description = "source Single Player Archipelago Plugin",
		version			= "0.0.0",
		url					= "https://github.com/jack5github/sourceSPAP"
	};

// === Constants ===
char			gameFolderName[7];
char			gameName[7];
char			jsonConfigPath[41]	= "addons\\sourcemod\\configs\\sourcespap.json";
char			cannotRunError[129] = "[sSPAP] sourceSPAP must be the only loaded plugin, move other .smx files in 'addons/sourcemod/plugins/' to 'disabled/' subfolder";

// === Configuration & Websocket ===
char			apProtocol[4]				= "ws";
char			apDomain[32]				= "archipelago.gg";
int				apPort							= 0;
char			apSlot[32]					= "";
char			apPassword[32]			= "";
// Whether debug mode is enabled, can only be set by manually editing the config.
bool			debug								= false;
WebSocket apWebsocket;
int				apSlotNo;

// === Game State ===
// Whether sourceSPAP should be in a functional state or not, set to false if other plugins are loaded.
bool			shouldRun					= true;
// Whether sourceSPAP should be checking for the existence of weapons and deleting them, only true a short amount of time after the player has spawned.
bool			shouldKillWeapons = false;
// The number of game frames since the player has spawned. Used to determine during what time to kill weapons.
int				killWeaponsFrames = 0;
ArrayList checkedLocations;
ArrayList unlockedItems;

// API Reference - https://www.sourcemod.net/new-api/
public void OnPluginStart()
{
	checkedLocations = new ArrayList();
	unlockedItems		 = new ArrayList();

	PrintToServer("[sSPAP] Fetching game names");
	GetGameFolderName(gameFolderName, sizeof(gameFolderName));
	if (StrEqual(gameFolderName, "portal"))
	{
		gameName = "Portal";
	}
	else {
		PrintToServer("[sSPAP] ERROR: Game folder name '%s' not implemented", gameFolderName);
		return;
	}

	if (FileExists(jsonConfigPath))
	{
		PrintToServer("[sSPAP] Reading config from '%s'", jsonConfigPath);
		JSONObject jsonConfig = JSONObject.FromFile(jsonConfigPath);
		if (jsonConfig != null)
		{
			if (jsonConfig.HasKey("protocol"))
			{
				jsonConfig.GetString("protocol", apProtocol, sizeof(apProtocol));
			}
			if (jsonConfig.HasKey("domain"))
			{
				jsonConfig.GetString("domain", apDomain, sizeof(apDomain));
			}
			if (jsonConfig.HasKey("port"))
			{
				apPort = jsonConfig.GetInt("port");
			}
			if (jsonConfig.HasKey("slot"))
			{
				jsonConfig.GetString("slot", apSlot, sizeof(apSlot));
			}
			if (jsonConfig.HasKey("debug"))
			{
				debug = jsonConfig.GetBool("debug");
			}
			// Password is not stored in the config for security reasons
		}
		else {
			PrintToServer("[sSPAP] WARNING: Failed to read config, using default values");
		}
		CloseHandle(jsonConfig);
	}

	// Commands - https://wiki.alliedmods.net/Commands_(SourceMod_Scripting)
	PrintToServer("[sSPAP] Creating commands");
	RegServerCmd("sspap_protocol", Command_SetProtocol, "Get/set protocol of the Archipelago server");
	RegServerCmd("sspap_domain", Command_SetDomain, "Get/set domain of the Archipelago server");
	RegServerCmd("sspap_port", Command_SetPort, "Get/set port of the Archipelago server");
	RegServerCmd("sspap_slot", Command_SetSlot, "Get/set slot name of the Archipelago player");
	RegServerCmd("sspap_pwd", Command_SetPassword, "Get/set password of the Archipelago player");
	RegServerCmd("sspap_connect", Command_Connect, "Connect to the Archipelago server");
	RegServerCmd("sspap_disconnect", Command_Disconnect, "Disconnect from the Archipelago server");
	if (debug)
	{
		RegServerCmd("sspap_debug_entdump", Command_DumpEntities, "Dump all entities to the console");
		RegServerCmd("sspap_debug_itemdump", Command_DumpItems, "Dump all unlocked items to the console");
		RegServerCmd("sspap_debug_locdump", Command_DumpLocations, "Dump all checked locations to the console");
	}

	// Event Hooks - https://wiki.alliedmods.net/Events_(SourceMod_Scripting)
	PrintToServer("[sSPAP] Creating event hooks");
	HookEvent("player_spawn", Event_PreSpawn, EventHookMode_Pre);
	HookEvent("player_spawn", Event_PostSpawn, EventHookMode_Post);
	// TODO: Implement player_use for other games, seemingly doesn't trigger in Portal
	// TODO: Implement player_shoot for other games, seemingly doesn't trigger in Portal
	HookEvent("physgun_pickup", Event_Pickup, EventHookMode_Post);
	HookEvent("player_hurt", Event_Hurt, EventHookMode_Post);
	HookEvent("player_death", Event_Dead, EventHookMode_Post);
	if (StrEqual(gameFolderName, "portal"))
	{
		HookEvent("portal_player_touchedground", Event_PortalGroundTouch, EventHookMode_Post);
		HookEvent("portal_player_portaled", Event_PortalEnterPortal, EventHookMode_Post);
		HookEvent("security_camera_detached", Event_PortalCameraDropped, EventHookMode_Post);
		HookEvent("dinosaur_signal_found", Event_PortalDinosaurFound, EventHookMode_Post);
		// TODO: Find alternative to turret_hit_turret, doesn't trigger in Portal
	}
}

// Checks for the existence of other plugins. If any are found, sourceSPAP is put into a non-functional state.
public void OnAllPluginsLoaded()
{
	PluginIterator iter = new PluginIterator();
	while (iter.Next() && MorePlugins(iter))
	{
		char pluginName[32];
		GetPluginInfo(iter.Plugin, PlInfo_Name, pluginName, sizeof(pluginName));
		if (!StrEqual(pluginName, thisPluginName))
		{
			shouldRun = false;
			PrintToServer(cannotRunError);
			return;
		}
	}
	PrintToServer("[sSPAP] Started successfully");
}

/*
=== Utility Functions ===
*/

// Saves the Archipelago server configuration to a JSON file.
void SaveConfig()
{
	JSONObject jsonConfig = new JSONObject();
	jsonConfig.SetString("protocol", apProtocol);
	jsonConfig.SetString("domain", apDomain);
	jsonConfig.SetInt("port", apPort);
	jsonConfig.SetString("slot", apSlot);
	// Password is not stored in the config for security reasons
	jsonConfig.SetBool("debug", debug);	 // Required to preserve debug value
	if (jsonConfig.ToFile(jsonConfigPath))
	{
		PrintToServer("[sSPAP] Saved config to '%s'", jsonConfigPath);
	}
	else {
		PrintToServer("[sSPAP] ERROR: Failed to save config to '%s'", jsonConfigPath);
	}
	if (!shouldRun)
	{
		PrintToServer("[sSPAP] WARNING: Config will have no effect until game is restarted with sSPAP properly set up");
	}
	CloseHandle(jsonConfig);
}

// Returns an array of indices for all valid entities. IsValidEntity() effectively gives the same output as that from IsValidEdict().
//
// @returns The array of entity indices. This handle must be closed when no longer needed.
ArrayList GetEntityIndices()
{
	// No need to multiply by 2, singleplayer games have no networked entities
	int				maxEntities = GetMaxEntities();
	ArrayList indices			= new ArrayList();
	for (int i = 0; i < maxEntities; i++)
	{
		if (IsValidEntity(i))
		{
			indices.Push(i);
		}
	}
	return indices;
}

/*
=== Commands ===
https://wiki.alliedmods.net/Commands_(SourceMod_Scripting)
*/

// Sets the protocol of the Archipelago server.
//
// @param args The number of arguments.
public Action Command_SetProtocol(int args)
{
	if (args <= 0)
	{
		PrintToServer("[sSPAP] Archipelago protocol is '%s'", apProtocol);
		return Plugin_Continue;
	}
	GetCmdArgString(apProtocol, sizeof(apProtocol));
	PrintToServer("[sSPAP] Archipelago protocol set to '%s'", apProtocol);
	SaveConfig();
	return Plugin_Continue;
}

// Sets the domain of the Archipelago server.
//
// @param args The number of arguments.
public Action Command_SetDomain(int args)
{
	if (args <= 0)
	{
		PrintToServer("[sSPAP] Archipelago domain is '%s'", apDomain);
		return Plugin_Continue;
	}
	GetCmdArgString(apDomain, sizeof(apDomain));
	PrintToServer("[sSPAP] Archipelago domain set to '%s'", apDomain);
	SaveConfig();
	return Plugin_Continue;
}

public Action Command_SetPort(int args)
{
	if (args <= 0)
	{
		PrintToServer("[sSPAP] Archipelago port is %i", apPort);
		return Plugin_Continue;
	}
	apPort = GetCmdArgInt(1);
	PrintToServer("[sSPAP] Archipelago port set to %i", apPort);
	SaveConfig();
	return Plugin_Continue;
}

public Action Command_SetSlot(int args)
{
	if (args <= 0)
	{
		PrintToServer("[sSPAP] Archipelago player slot is '%s'", apSlot);
		return Plugin_Continue;
	}
	GetCmdArgString(apSlot, sizeof(apSlot));
	PrintToServer("[sSPAP] Archipelago player slot set to '%s'", apSlot);
	SaveConfig();
	return Plugin_Continue;
}

// Sets the password of the Archipelago player. The password is not shown or saved in the config for security reasons.
//
// @param args The number of arguments.
public Action Command_SetPassword(int args)
{
	if (args <= 0)
	{
		Format(apPassword, sizeof(apPassword), "");
		PrintToServer("[sSPAP] Archipelago player password is no longer set");
		return Plugin_Continue;
	}
	GetCmdArgString(apPassword, sizeof(apPassword));
	PrintToServer("[sSPAP] Archipelago player password set");
	return Plugin_Continue;
}

// Connects to the Archipelago server via websockets.
//
// @param args The number of arguments.
public Action Command_Connect(int args)
{
	if (!shouldRun)
	{
		PrintToServer(cannotRunError);
		return Plugin_Continue;
	}
	char apUrl[64];
	strcopy(apUrl, sizeof(apUrl), apProtocol);
	StrCat(apUrl, sizeof(apUrl), "://");
	StrCat(apUrl, sizeof(apUrl), apDomain);
	StrCat(apUrl, sizeof(apUrl), ":");
	char apWsPort[6];
	Format(apWsPort, sizeof(apWsPort), "%i", apPort);
	StrCat(apUrl, sizeof(apUrl), apWsPort);
	PrintToServer("[sSPAP] Connecting to Archipelago server at '%s'", apUrl);
	apWebsocket = new WebSocket(apUrl, WebSocket_JSON);
	apWebsocket.SetOpenCallback(Websocket_Open);
	apWebsocket.SetCloseCallback(Websocket_Close);
	apWebsocket.SetErrorCallback(Websocket_Error);
	apWebsocket.SetMessageCallback(Websocket_Message);
	apWebsocket.Connect();
	return Plugin_Handled;
}

public Action Command_Disconnect(int args)
{
	PrintToServer("[sSPAP] Disconnecting from Archipelago server...");
	apWebsocket.Disconnect();
	return Plugin_Handled;
}

// Dumps all entity indices and their classnames to the server console.
//
// @param args The number of arguments.
public Action Command_DumpEntities(int args)
{
	ArrayList entities = GetEntityIndices();
	for (int i = 0; i < entities.Length; i++)
	{
		char classname[32];
		GetEntityClassname(entities.Get(i), classname, sizeof(classname));
		PrintToServer("[sSPAP] Entity %i (classname '%s')", entities.Get(i), classname);
	}
	entities.Close();
	return Plugin_Continue;
}

public Action Command_DumpItems(int args)
{
	for (int i = 0; i < unlockedItems.Length; i++)
	{
		PrintToServer("[sSPAP] You have item %i", unlockedItems.Get(i));
	}
	return Plugin_Continue;
}

public Action Command_DumpLocations(int args)
{
	for (int i = 0; i < checkedLocations.Length; i++)
	{
		PrintToServer("[sSPAP] You checked location %i", checkedLocations.Get(i));
	}
	return Plugin_Continue;
}

/*
=== Websocket Callbacks ===
https://github.com/ProjectSky/sm-ext-websocket
https://github.com/ArchipelagoMW/Archipelago/blob/main/docs/network%20protocol.md
*/

void Websocket_Open(WebSocket ws)
{
	PrintToServer("[sSPAP] Connected to Archipelago server");
	// TODO: Send connect message
}

void Websocket_Close(WebSocket ws, int code, char[] reason)
{
	PrintToServer("[sSPAP] Disconnected from Archipelago server (%i: %s)", code, reason);
}

void Websocket_Error(WebSocket ws, char[] errMsg)
{
	PrintToServer("[sSPAP] ERROR: Websocket error '%s'", errMsg);
}

// Reads a string array from JSON and returns it as an ArrayList.
//
// @param rootJson The JSON to read from. This JSON must be the root handle and not a scoped copy.
// @param pointer The JSON pointer to the array. This is usually in the format '/key/nestedKey', with 0-indexed numbers being used for array indices.
// @param pointerSize The size of the JSON pointer. It does not need to be large enough to fit the array indices.
// @param maxDigits The maximum number of digits in the array indices. Defaults to 3.
// @param stringSize The maximum size of all strings in the array. If this is not high enough, the reading will fail early. Defaults to 64.
// @return The array of strings. This array will return empty if there is an error reading the array at the given pointer. Needs to be closed when no longer needed.
ArrayList GetJSONStringArray(JSON rootJson, char[] pointer, int pointerSize, int maxDigits = 3, int stringSize = 64)
{
	if (debug)
	{
		char pointerJsonStr[1024];
		JSON pointerJson = rootJson.PtrGet(pointer);
		pointerJson.ToString(pointerJsonStr, sizeof(pointerJsonStr));
		PrintToServer("[sSPAP] Creating string array of JSON at pointer '%s': %s", pointer, pointerJsonStr);
		pointerJson.Close();
	}
	int scopedPointerSize = pointerSize + 1;	// Fit forward slash
	char[] scopedPointer	= new char[scopedPointerSize];
	strcopy(scopedPointer, scopedPointerSize, pointer);
	StrCat(scopedPointer, scopedPointerSize, "/");
	int i									 = 0;
	int indexedPointerSize = scopedPointerSize + maxDigits;	 // Fit digits
	char[] stringBuffer		 = new char[stringSize];
	ArrayList stringArray	 = new ArrayList(stringSize);
	while (i >= 0)	// Avoid reduntant test warning
	{
		char[] indexedPointer = new char[indexedPointerSize];
		strcopy(indexedPointer, indexedPointerSize, scopedPointer);
		char[] iStr = new char[maxDigits];
		Format(iStr, maxDigits, "%i", i);
		StrCat(indexedPointer, indexedPointerSize, iStr);
		if (!rootJson.PtrTryGetString(indexedPointer, stringBuffer, stringSize))
		{
			if (debug)
			{
				PrintToServer("[sSPAP] JSON item '%s' does not exist or string size buffer is too small", indexedPointer);
			}
			break;
		}
		// No need to use PtrGetString(), PtrTryGetString() does the job
		if (debug)
		{
			PrintToServer("[sSPAP] JSON item '%s' is '%s'", indexedPointer, stringBuffer);
		}
		stringArray.PushString(stringBuffer);
		i++;
	}
	if (debug)
	{
		PrintToServer("[sSPAP] Array length is %i", stringArray.Length);
		for (int j = 0; j < stringArray.Length; j++)
		{
			stringArray.GetString(j, stringBuffer, stringSize);
			PrintToServer("[sSPAP] Array item %i is '%s'", j, stringBuffer);
		}
	}
	return stringArray;
}

// Receives a message from the Archipelago server.
//
// @param ws The WebSocket connection to the Archipelago server.
// @param message The message from the Archipelago server, typically an ordered list of network commands.
// @param wireSize The size of the message.
void Websocket_Message(WebSocket ws, const JSONArray message, int wireSize)
{
	char messageString[1024];
	if (debug)
	{
		message.ToString(messageString, sizeof(messageString));
		PrintToServer("[sSPAP] Received packet from Archipelago server: '%s'", messageString);
	}
	if (!message.IsArray)
	{
		PrintToServer("[sSPAP] ERROR: Non-array packet");
		return;
	}
	for (int i = 0; i < message.Length; i++)
	{
		JSONObject command = message.Get(i);
		if (!command.IsObject)
		{
			PrintToServer("[sSPAP] ERROR: Non-object command %i", i);
			command.Close();
			continue;
		}
		char cmd[18];
		command.GetString("cmd", cmd, sizeof(cmd));
		if (debug)
		{
			PrintToServer("[sSPAP] Command %i is a '%s'", i, cmd);
		}
		if (StrEqual(cmd, "RoomInfo"))
		{
			// After connecting, server accepts connection and responds with a RoomInfo packet
			char pointer[9];
			Format(pointer, sizeof(pointer), "/%i/games", i);
			// Archipelago multiworlds usually do not exceed 999 games
			ArrayList games			= GetJSONStringArray(message, pointer, sizeof(pointer), 3);
			bool			gameFound = false;
			for (int j = 0; j < games.Length; j++)
			{
				char jsonGameName[64];
				games.GetString(j, jsonGameName, sizeof(jsonGameName));
				if (StrEqual(jsonGameName, gameName))
				{
					gameFound = true;
					break;
				}
			}
			games.Close();
			if (!gameFound)
			{
				PrintToServer("[sSPAP] ERROR: Game '%s' not listed on Archipelago server", gameName);
			}
			else {
				bool passwordRequired = command.GetBool("password");
				SendConnectCommand(ws, passwordRequired);
			}
		}
		else if (StrEqual(cmd, "Connected")) {
			PrintToServer("[sSPAP] Connected to Archipelago server");
			apSlotNo = command.GetInt("slot");
			checkedLocations.Clear();
			JSONArray jsonCheckedLocations = command.Get("checked_locations");
			for (int j = 0; j < jsonCheckedLocations.Length; j++)
			{
				checkedLocations.Push(jsonCheckedLocations.GetInt(j));
			}
			jsonCheckedLocations.Close();
			shouldRun = true;
		}
		else if (StrEqual(cmd, "ReceivedItems")) {
			JSONArray receivedItems = command.Get("items");
			for (int j = 0; j < receivedItems.Length; j++)
			{
				JSONObject receivedItem = receivedItems.Get(j);
				if (receivedItem.GetInt("player") != apSlotNo)
				{
					continue;
				}
				int itemId = receivedItem.GetInt("item");
				receivedItem.Close();
				// TODO: Handle filler items differently
				unlockedItems.Push(itemId);
				if (debug)
				{
					PrintToServer("[sSPAP] Received item %i", itemId);
				}
			}
			receivedItems.Close();
		}
		else if (StrEqual(cmd, "PrintJSON")) {
			char pointer[15];
			Format(pointer, sizeof(pointer), "/%i/data/0/text", i);
			char text[1024];
			if (!command.PtrTryGetString(pointer, text, sizeof(text)))
			{
				PrintToServer("[sSPAP] ERROR: PrintJSON packet missing text");
			}
			else {
				// No need to use PtrGetString(), PtrTryGetString() does the job
				// TODO: Create entities to display this text on screen
				PrintToServer("[sSPAP] '%s'", text);
			}
		}
		else if (StrEqual(cmd, "RoomUpdate")) {
			JSONArray jsonCheckedLocations = command.Get("checked_locations");
			for (int j = 0; j < jsonCheckedLocations.Length; j++)
			{
				int locationId = jsonCheckedLocations.GetInt(j);
				PrintToServer("[sSPAP] Check for location %i registered by server", locationId);
				checkedLocations.Push(locationId);
			}
			jsonCheckedLocations.Close();
		}
		else if (StrEqual(cmd, "InvalidPacket")) {
			char text[1024];
			command.GetString("text", text, sizeof(text));
			PrintToServer("[sSPAP] ERROR: Invalid packet: %s", text);
		}
		else
		{
			// TODO: Implement other commands
			message.ToString(messageString, sizeof(messageString));
			PrintToServer("[sSPAP] ERROR: Command '%s' not implemented: %s", cmd, messageString);
		}
		command.Close();
	}
}

// Sends the Connect command to the Archipelago server, which performs a connection handshake, documented here: https://github.com/ArchipelagoMW/Archipelago/blob/main/docs/network%20protocol.md#connect
//
// @param ws The WebSocket connection to the Archipelago server.
// @param passwordRequired Whether the Archipelago server requires a password.
void SendConnectCommand(WebSocket ws, bool passwordRequired)
{
	PrintToServer("[sSPAP] Sending Connect command");
	JSONObject connectCommand = new JSONObject();
	connectCommand.SetString("cmd", "Connect");
	if (passwordRequired)
	{
		connectCommand.SetString("password", apPassword);
	}
	else {	// All fields are required, send empty string
		connectCommand.SetString("password", "");
	}
	connectCommand.SetString("game", gameName);
	connectCommand.SetString("name", apSlot);
	// TODO: Get uuid from Windows file `%localappdata%/Archipelago/Cache/common.json` or Linux file `~/.cache/Archipelago/Cache/common.json`, sending empty string for now
	connectCommand.SetString("uuid", "");
	JSONObject connectVersion = new JSONObject();
	connectVersion.SetString("class", "Version");
	connectVersion.SetString("build", "0");
	connectVersion.SetString("major", "6");
	connectVersion.SetString("minor", "4");
	connectCommand.Set("version", connectVersion);
	/*
	items_handling uses a flags system:
	- 1: Items are sent from other worlds (games)
	- 2: Items are sent from this world
	- 4: This world has a starting inventory
	sourceSPAP must allow all three flags, therefore 4 + 2 + 1 = 7
	*/
	connectCommand.SetInt("items_handling", 7);
	JSONArray connectTags = new JSONArray();
	connectTags.PushString("DeathLink");	// sourceSPAP supports DeathLink
	connectCommand.Set("tags", connectTags);
	connectCommand.SetBool("slot_data", true);
	JSONArray commandArray = new JSONArray();
	commandArray.Push(connectCommand);
	if (debug)
	{
		char commandArrayString[1024];
		commandArray.ToString(commandArrayString, sizeof(commandArrayString));
		PrintToServer("[sSPAP] Sending JSON '%s'", commandArrayString);
	}
	ws.WriteJSON(commandArray);
	connectVersion.Close();
	connectTags.Close();
	connectCommand.Close();
	commandArray.Close();
}

// Sends the LocationChecks command to the Archipelago server with a single location, which informs the server that the client has checked it, documented here: https://github.com/ArchipelagoMW/Archipelago/blob/main/docs/network%20protocol.md#locationchecks
//
// @param ws The WebSocket connection to the Archipelago server.
// @param locationId The ID of the location the client has checked.
void SendLocationCheckedCommand(WebSocket ws, int locationId)
{
	if (checkedLocations.FindValue(locationId) != -1)
	{
		if (debug)
		{
			PrintToServer("[sSPAP] Location %i already checked, not sending", locationId);
		}
		return;
	}
	PrintToServer("[sSPAP] Marking location %i as checked", locationId);
	JSONObject locationChecksCommand = new JSONObject();
	locationChecksCommand.SetString("cmd", "LocationChecks");
	JSONArray locationsArray = new JSONArray();
	locationsArray.PushInt(locationId);
	locationChecksCommand.Set("locations", locationsArray);
	JSONArray commandArray = new JSONArray();
	commandArray.Push(locationChecksCommand);
	if (debug)
	{
		char commandArrayString[1024];
		commandArray.ToString(commandArrayString, sizeof(commandArrayString));
		PrintToServer("[sSPAP] Sending JSON '%s'", commandArrayString);
	}
	ws.WriteJSON(commandArray);
	locationsArray.Close();
	locationChecksCommand.Close();
	commandArray.Close();
}

/*
=== Events ===
https://wiki.alliedmods.net/Events_(SourceMod_Scripting)

For many events, a user ID is assigned, which is an incrementing number as a string that is not the same as the client ID. Since sourceSPAP is only concerned with singleplayer games, the user ID can be ignored, and the client ID is always 1.

```
char userid[32];
event.GetString("userid", userid, sizeof(userid));
```
*/

// Returns the client ID of the current client, as it is not always 1.
//
// @returns The client ID of the current client.
int GetClientId()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			return i;
		}
	}
	PrintToServer("[sSPAP] ERROR: Could not find client ID");
	return 0;
}

// First checks if the current map is a background map, and if so, exits early so no logic is run on it. Then checks if the current map is the expected map, and if not, optionally changes the map to it. This should only be run after checking shouldRun to avoid console spam.
//
// @param changeMap Whether to change the map if the current map is not the expected map. Defaults to false.
// @returns Whether the current map is the expected map.
bool EvaluateMap(bool changeMap = false)
{
	char mapName[32];
	GetCurrentMap(mapName, sizeof(mapName));
	if (StrContains(mapName, "background") != -1)
	{
		PrintToServer("[sSPAP] Not evaluating background map, likely on main menu");
		return false;
	}
	// TODO: Manage maps as unlocks
	/*
	if (!StrEqual(mapName, ...))
	{
		PrintToServer("[sSPAP] Map does not match map expected by sSPAP");
		if (!changeMap) return false;
		ForceChangeLevel(..., "Map does not match map expected by sSPAP");
		return false;
	}
	*/
	return true;
}

// Teleports all entities with the specified name to the specified position. Can teleport the player if the name is '!player'.
//
// @param name The name of the entity.
// @param position The position to teleport to as a vector.
void TeleportEntitiesByName(char[] name, float position[3])
{
	ServerCommand("ent_fire %s addoutput \"origin %f %f %f\"", name, position[0], position[1], position[2]);
}

// Fires before the client has spawned.
//
// @param event The event object.
// @param name The name of the event.
// @param dontBroadcast If the event's broadcasting is disabled.
public Action Event_PreSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if (!shouldRun)
	{
		PrintToServer(cannotRunError);
		return Plugin_Continue;
	}
	PrintToServer("[sSPAP] Client is spawning");
	if (!EvaluateMap(true))
	{
		return Plugin_Continue;
	}
	// TODO: Change map logic while player has yet to spawn
	// Changing location of info_player_start has no effect on player spawn, change player location in Event_PostSpawn() instead
	return Plugin_Continue;
}

public Action Event_PostSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if (!shouldRun)
	{
		PrintToServer(cannotRunError);
		return Plugin_Continue;
	}
	PrintToServer("[sSPAP] Client spawned");
	if (!EvaluateMap())
	{
		return Plugin_Continue;
	}
	// Test of teleporting player, player does not pick up items nor activate triggers located at spawn
	char mapName[32];
	GetCurrentMap(mapName, sizeof(mapName));
	if (StrEqual(mapName, "testchmb_a_10"))
	{
		TeleportEntitiesByName("!player", { -889.87, -2753.50, -191.97 });
	}
	shouldKillWeapons = true;
	killWeaponsFrames = 0;
	// TODO: Figure out how to change player looking direction
	// TODO: Display notices after player has spawned
	return Plugin_Continue;
}

// Run once per game tick (66 times per second). This function should be used as sparingly as possible due to how costly it is. Right now, this function is used to kill weapons, as they do not exist right when the player spawns, and <sdkhooks> and <sdktools_functions> are not supported in Portal.
public void OnGameFrame()
{
	if (!shouldKillWeapons) return;
	ArrayList entities = GetEntityIndices();
	for (int i = 0; i < entities.Length; i++)
	{
		char classname[32];
		GetEntityClassname(entities.Get(i), classname, sizeof(classname));
		if (StrContains(classname, "weapon_") == 0)
		{
			RemoveEntity(entities.Get(i));
		}
	}
	entities.Close();
	killWeaponsFrames++;
	if (killWeaponsFrames >= 66)	// 1 second
	{
		shouldKillWeapons = false;
	}
}

public void Event_Pickup(Event event, const char[] name, bool dontBroadcast)
{
	if (!shouldRun) return;	 // Do not spam console any more than player spawning
	char entindex[64];
	event.GetString("entindex", entindex, sizeof(entindex));
	PrintToServer("[sSPAP] Client picked up object '%s'", entindex);
	// TODO: React on certain objects
}

public void Event_PortalGroundTouch(Event event, const char[] name, bool dontBroadcast)
{
	if (!shouldRun) return;	 // Do not spam console any more than player spawning
	// Ignore event if client is dead, spams otherwise
	int health = GetClientHealth(GetClientId());
	if (health == 0) return;
	// Player is alive
	PrintToServer("[sSPAP] Client touched the ground");
	// TODO: Cancel airborne status
}

public void Event_PortalEnterPortal(Event event, const char[] name, bool dontBroadcast)
{
	if (!shouldRun) return;	 // Do not spam console any more than player spawning
	// Ignore event if client is dead, spams otherwise
	int health = GetClientHealth(GetClientId());
	if (health == 0) return;
	// Player is alive
	bool portal2 = event.GetBool("portal2");
	if (!portal2)
	{
		PrintToServer("[sSPAP] Client entered blue portal");
	}
	else {
		PrintToServer("[sSPAP] Client entered orange portal");
	}
	// TODO: Check portal exit point
}

public void Event_PortalCameraDropped(Event event, const char[] name, bool dontBroadcast)
{
	if (!shouldRun) return;	 // Do not spam console any more than player spawning
	PrintToServer("[sSPAP] Client detached camera");
	// TODO: Reward for each camera
}

// Fires when the client takes a radio to a "dinosaur" noise location. The ID of the dinosaur noises start from 0 and increment by 1 for every radio, in chamber order. An offset ID is sent as a location check.
//
// @param event The event object.
// @param name The name of the event.
// @param dontBroadcast If true, the event will not be broadcast to other clients.
public void Event_PortalDinosaurFound(Event event, const char[] name, bool dontBroadcast)
{
	if (!shouldRun) return;	 // Do not spam console any more than player spawning
	char idStr[3];
	event.GetString("id", idStr, sizeof(idStr));
	int id	 = StringToInt(idStr);
	int apId = 85200 + id;	// Reference to radio reading "85.2 FM"
	PrintToServer("[sSPAP] Client found dinosaur noise %i (%i)", id, apId);
	SendLocationCheckedCommand(apWebsocket, apId);
}

// Fires when the client is hurt. This is only intended to be used to fire a DeathLink event to the Archipelago server if the game in question sees very little damage, and the player has enabled getting hurt triggering DeathLink, provided that the event is sent only after a certain amount of time since the last event.
public void Event_Hurt(Event event, const char[] name, bool dontBroadcast)
{
	if (!shouldRun) return;	 // Do not spam console any more than player spawning
	char attacker[32];
	event.GetString("attacker", attacker, sizeof(attacker));
	int health = event.GetInt("health");
	PrintToServer("[sSPAP] Client hurt by entity '%s', %i health remaining", attacker, health);
	// TODO: Send DeathLink conditionally
}

// Fires when the client dies. This is intended to be used to fire DeathLink events to the Archipelago server. If being hurt also triggers DeathLink, this event uses the same delay system as Event_Hurt().
public void Event_Dead(Event event, const char[] name, bool dontBroadcast)
{
	if (!shouldRun) return;	 // Do not spam console any more than player spawning
	char attacker[32];
	event.GetString("attacker", attacker, sizeof(attacker));
	PrintToServer("[sSPAP] Client killed by entity '%s'", attacker);
	// TODO: Send DeathLink conditionally
}
