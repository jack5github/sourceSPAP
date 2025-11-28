#include <sourcemod>
#include <json>
// <sdkhooks> cannot set up its event listeners in Portal
// Portal does not support <sdktools_functions> methods
#include <websocket>

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
int				clientId = 1;

char			gameFolderName[7];

char			jsonConfigPath[41]	= "addons\\sourcemod\\configs\\sourcespap.json";

char			cannotRunError[129] = "[sSPAP] sourceSPAP must be the only loaded plugin, move other .smx files in 'addons/sourcemod/plugins/' to 'disabled/' subfolder";

// === Configuration & Websocket ===
char			apDomain[32]				= "archipelago.gg";

int				apPort							= 0;

char			apSlot[32]					= "";

char			apPassword[32]			= "";

// Whether debug mode is enabled, can only be set by manually editing the config.
bool			debug								= false;

WebSocket apWebsocket;

// === Game State ===

// Whether sourceSPAP should be in a functional state or not, set to false if other plugins are loaded.
bool			shouldRun						= true;

// Whether sourceSPAP should be checking for the existence of weapons and deleting them, only true a short amount of time after the player has spawned.
bool			shouldKillWeapons		= false;

// The map Archipelago is expecting the client to be on. If the client is not on this map before they spawn, the server will switch to this map. This appears as the map loading twice, but on modern hardware this is negligible.
char			expectedMapName[32] = "testchmb_a_10";

// API Reference - https://www.sourcemod.net/new-api/
public void OnPluginStart()
{
	GetGameFolderName(gameFolderName, sizeof(gameFolderName));

	if (FileExists(jsonConfigPath))
	{
		PrintToServer("[sSPAP] Reading config from '%s'", jsonConfigPath);
		JSONObject jsonConfig = JSONObject.FromFile(jsonConfigPath);
		if (jsonConfig != null)
		{
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
	RegServerCmd("sspap_domain", Command_SetDomain, "Get/set domain of the Archipelago server");
	RegServerCmd("sspap_port", Command_SetPort, "Get/set port of the Archipelago server");
	RegServerCmd("sspap_slot", Command_SetSlot, "Get/set slot name of the Archipelago player");
	RegServerCmd("sspap_pwd", Command_SetPassword, "Get/set password of the Archipelago player");
	RegServerCmd("sspap_connect", Command_Connect, "Connect to the Archipelago server");
	RegServerCmd("sspap_disconnect", Command_Disconnect, "Disconnect from the Archipelago server");
	if (debug)
	{
		RegServerCmd("sspap_debug_entdump", Command_DumpEntities, "Dump all entities to the console");
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
	jsonConfig.SetString("domain", apDomain);
	jsonConfig.SetInt("port", apPort);
	jsonConfig.SetString("slot", apSlot);
	jsonConfig.SetBool("debug", debug);
	// Password is not stored in the config for security reasons
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
	char apWsDomain[64] = "ws://";
	StrCat(apWsDomain, sizeof(apWsDomain), apDomain);
	StrCat(apWsDomain, sizeof(apWsDomain), ":");
	char apWsPort[6];
	Format(apWsPort, sizeof(apWsPort), "%i", apPort);
	StrCat(apWsDomain, sizeof(apWsDomain), apWsPort);
	PrintToServer("[sSPAP] Connecting to Archipelago server at '%s'", apWsDomain);
	apWebsocket = new WebSocket(apWsDomain, WebSocket_JSON);
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

/*
=== Websocket Callbacks ===
https://github.com/ProjectSky/sm-ext-websocket
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

void Websocket_Message(WebSocket ws, JSON message, int wireSize)
{
	// TODO: Interpret message from Archipelago server
	if (debug)
	{
		char messageString[1024];
		message.ToString(messageString, sizeof(messageString));
		PrintToServer("[sSPAP] Received message from Archipelago server: %s", messageString);
	}
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

// First checks if the current map is a background map, and if so, exits early so no logic is run on it. Then checks if the current map is the expected map, and if not, changes the map to it. This should only be run after checking shouldRun to avoid console spam.
//
// @returns Whether the current map is the expected map.
bool EvaluateMap()
{
	char mapName[32];
	GetCurrentMap(mapName, sizeof(mapName));
	if (StrContains(mapName, "background") != -1)
	{
		PrintToServer("[sSPAP] Not evaluating background map, likely on main menu");
		return false;
	}
	if (!StrEqual(mapName, expectedMapName))
	{
		ForceChangeLevel(expectedMapName, "Map does not match map expected by sSPAP");
		return false;
	}
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
	if (!EvaluateMap())
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
	TeleportEntitiesByName("!player", { -889.87, -2753.50, -191.97 });
	shouldKillWeapons = true;
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
		if (StrContains(classname, "weapon_") != -1)
		{
			RemoveEntity(entities.Get(i));
			// TODO: Make this more generic, currently assumes only one weapon exists (portal gun)
			shouldKillWeapons = false;
		}
	}
	entities.Close();
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
	int health = GetClientHealth(clientId);
	if (health == 0) return;
	// Player is alive
	PrintToServer("[sSPAP] Client touched the ground");
	// TODO: Cancel airborne status
}

public void Event_PortalEnterPortal(Event event, const char[] name, bool dontBroadcast)
{
	if (!shouldRun) return;	 // Do not spam console any more than player spawning
	// Ignore event if client is dead, spams otherwise
	int health = GetClientHealth(clientId);
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

public void Event_PortalDinosaurFound(Event event, const char[] name, bool dontBroadcast)
{
	if (!shouldRun) return;	 // Do not spam console any more than player spawning
	char id[32];
	event.GetString("id", id, sizeof(id));
	PrintToServer("[sSPAP] Client found dinosaur noise '%s'", id);
	// TODO: Reward for each dinosaur
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
