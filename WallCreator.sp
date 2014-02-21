#include < sourcemod >
#include < sdktools >
#include < cstrike >

#define PREFIX            " \x01\x0B\x04[Wall Creator]\x01"
//#define ZONES_MODEL       "models/error.mdl"
#define ZONES_MODEL       "models/props/cs_office/vending_machine.mdl"
#define INIT              -1
#define MAX_ZONE_LENGTH   64
#define LIFETIME_INTERVAL 5.0

enum // Just makes plugin readable
{
	NO_POINT,
	FIRST_POINT,
	SECOND_POINT,

	POINTS_SIZE
}

enum
{
	NO_VECTOR,
	FIRST_VECTOR,
	SECOND_VECTOR,

	VECTORS_SIZE
}

enum
{
	ZONE_NAME,
	ZONE_COORDS1,
	ZONE_COORDS2,

	ZONEARRAY_SIZE
}

// ====[ VARIABLES ]=========================================================
new	Handle:ZonesArray       = INVALID_HANDLE,
	Handle:show_zones       = INVALID_HANDLE;

// ====[ ARRAYS ]============================================================
new	EditingZone[MAXPLAYERS + 1]           = { INIT,     ... },
	EditingVector[MAXPLAYERS + 1]         = { INIT,     ... },
	ZonePoint[MAXPLAYERS + 1]             = { NO_POINT, ... },
	bool:NamesZone[MAXPLAYERS + 1]        = { false,    ... },
	bool:RenamesZone[MAXPLAYERS + 1]      = { false,    ... },
	Float:FirstZoneVector[MAXPLAYERS + 1][3],
	Float:SecondZoneVector[MAXPLAYERS + 1][3];

// ====[ GLOBALS ]===========================================================
new	LaserMaterial,
	HaloMaterial,
	GlowSprite,
	String:map[64];

// ====[ PLUGIN ]============================================================
public Plugin:myinfo =
{
	name        = "Wall Creator",
	author      = "Root, slightly edited by xPaw",
	description = "Defines map zones where players are not allowed to enter",
	version     = "1.0",
	url         = "http://www.dodsplugins.com/, http://www.wcfan.de/"
}

/**
 * --------------------------------------------------------------------------
 *     ____           ______                  __  _
 *    / __ \____     / ____/__  ______  _____/ /_(_)____  ____  _____
 *   / / / / __ \   / /_   / / / / __ \/ ___/ __/ // __ \/ __ \/ ___/
 *  / /_/ / / / /  / __/  / /_/ / / / / /__/ /_/ // /_/ / / / (__  )
 *  \____/_/ /_/  /_/     \__,_/_/ /_/\___/\__/_/ \____/_/ /_/____/
 *
 * --------------------------------------------------------------------------
*/

/* OnPluginStart()
 *
 * When the plugin starts up.
 * -------------------------------------------------------------------------- */
public OnPluginStart()
{
	show_zones       = CreateConVar("bombgame_show_walls", "0", "Whether or not show the walls on a map all the times", FCVAR_PLUGIN, true, 0.0, true, 1.0);

	// Register admin commands to control zones
	RegAdminCmd("bombgame_walls", Command_SetupZones, ADMFLAG_CONFIG, "Opens the walls main menu");

	// Load some plugin translations
	LoadTranslations("common.phrases");
	LoadTranslations("playercommands.phrases");
	LoadTranslations("sm_zones.phrases");

	// Create a zones array
	ZonesArray = CreateArray();

	// And create/load plugin's config
	AutoExecConfig(true, "sm_zones");

	// Get the zones path
	decl String:path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "data/zones");

	// If there are no 'zones' folder - create it
	if (!DirExists(path))
	{
		// After creating a zones folder set its permissions to allow plugin to create/load/edit configs from this directory
		CreateDirectory(path, FPERM_U_READ|FPERM_U_WRITE|FPERM_U_EXEC|FPERM_G_READ|FPERM_G_EXEC|FPERM_O_READ|FPERM_O_EXEC);
	}
}

/* OnMapStart()
 *
 * When the map starts.
 * -------------------------------------------------------------------------- */
public OnMapStart()
{
	// Get the current map
	decl String:curmap[64];
	GetCurrentMap(curmap, sizeof(curmap));

	// Does current map string is contains a "workshop" word?
	if (strncmp(curmap, "workshop", 8) == 0)
	{
		// If yes - skip the first 19 characters to avoid comparing the "workshop/12345678" prefix
		strcopy(map, sizeof(map), curmap[19]);
	}
	else
	{
		// Not a workshop map
		strcopy(map, sizeof(map), curmap);
	}

	LaserMaterial = PrecacheModel("materials/sprites/laserbeam.vmt");
	HaloMaterial  = PrecacheModel("materials/sprites/glow01.vmt");
	GlowSprite    = PrecacheModel("materials/sprites/blueflare1.vmt");

	// Precache zones model
	PrecacheModel(ZONES_MODEL, true);

	// Prepare a config for new map
	ParseZoneConfig();

	// Create global repeatable timer to show zones
	CreateTimer(LIFETIME_INTERVAL, Timer_ShowZones, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

/* OnClientPutInServer()
 *
 * Called when a client is entering the game.
 * -------------------------------------------------------------------------- */
public OnClientPutInServer(client)
{
	// Reset everything when the player connects
	EditingZone[client] =
	EditingVector[client] = INIT;
	ZonePoint[client] =
	NamesZone[client] =
	RenamesZone[client] = false;
}

/* OnPlayerRunCmd()
 *
 * When a clients movement buttons are being processed.
 * -------------------------------------------------------------------------- */
public Action:OnPlayerRunCmd(client, &buttons)
{
	// Use this intead of a global
	static bool:PressedUse[MAXPLAYERS + 1] = false;

	// Make sure player is pressing +USE button
	if (buttons & IN_USE)
	{
		// Also check if player is about to create new zones
		if (!PressedUse[client] && ZonePoint[client] != NO_POINT)
		{
			decl Float:origin[3];
			GetClientAbsOrigin(client, origin);

			// Player is creating first corner
			if (ZonePoint[client] == FIRST_POINT)
			{
				// Set point for second one
				ZonePoint[client] = SECOND_POINT;
				FirstZoneVector[client][0] = origin[0];
				FirstZoneVector[client][1] = origin[1];
				FirstZoneVector[client][2] = origin[2];

				PrintToChat(client, "%s%t", PREFIX, "Zone Edge");
			}
			else if (ZonePoint[client] == SECOND_POINT)
			{
				// Player is creating second point now
				ZonePoint[client] = NO_POINT;
				SecondZoneVector[client][0] = origin[0];
				SecondZoneVector[client][1] = origin[1];
				SecondZoneVector[client][2] = origin[2];

				// Notify client and set name boolean to 'true' to hook player chat for naming zone
				PrintToChat(client, "%s%t", PREFIX, "Type Zone Name");
				NamesZone[client] = true;
			}
		}

		// Sort of cooldown
		PressedUse[client] = true;
	}

	// Player not IN_USE
	else PressedUse[client] = false;
}

/**
 * --------------------------------------------------------------------------
 *     ______                                          __
 *    / ____/___  ____ ___  ____ ___  ____ _____  ____/ /____
 *   / /   / __ \/ __ `__ \/ __ `__ \/ __ `/ __ \/ __  / ___/
 *  / /___/ /_/ / / / / / / / / / / / /_/ / / / / /_/ (__  )
 *  \____/\____/_/ /_/ /_/_/ /_/ /_/\__,_/_/ /_/\__,_/____/
 *
 * --------------------------------------------------------------------------
*/

/* Command_Chat()
 *
 * When the say/say_team commands are used.
 * -------------------------------------------------------------------------- */
public Action:OnClientSayCommand(client, const String:command[], const String:sArgs[])
{
	decl String:text[MAX_ZONE_LENGTH];

	// Copy original message
	strcopy(text, sizeof(text), sArgs);

	// Remove quotes from dest string
	StripQuotes(text);

	// When player is about to name a zone
	if (NamesZone[client])
	{
		// Set boolean after sending a text
		NamesZone[client] = false;

		// Or cancel renaming
		if (StrEqual(text, "!stop", false) || StrEqual(text, "!cancel", false))
		{
			PrintToChat(client, "%s%t", PREFIX, "Abort Zone Name");

			// Reset vector settings for new zone
			ClearVector(FirstZoneVector[client]);
			ClearVector(SecondZoneVector[client]);
			return Plugin_Handled;
		}

		// Show save menu after sending a name.
		ShowSaveZoneMenu(client, text);

		// Don't show new zone name in chat
		return Plugin_Handled;
	}
	else if (RenamesZone[client])
	{
		// Player is about to rename a zone
		decl String:OldZoneName[MAX_ZONE_LENGTH];
		RenamesZone[client] = false;

		if (StrEqual(text, "!stop", false) || StrEqual(text, "!cancel", false))
		{
			PrintToChat(client, "%s%t", PREFIX, "Abort Zone Rename");

			// When renaming is cancelled - redraw zones menu
			ShowZoneOptionsMenu(client);
			return Plugin_Handled;
		}

		// Kill the previous zone (its really better than just renaming via config)
		KillZone(EditingZone[client]);

		new Handle:hZone = GetArrayCell(ZonesArray, EditingZone[client]);

		// Get the old name of a zone
		GetArrayString(hZone, ZONE_NAME, OldZoneName, sizeof(OldZoneName));

		// And set to a new one
		SetArrayString(hZone, ZONE_NAME, text);

		// Re-spawn an entity again
		SpawnZone(EditingZone[client]);

		// Update the config file
		decl String:config[PLATFORM_MAX_PATH];
		BuildPath(Path_SM, config, sizeof(config), "data/zones/%s.cfg", map);

		PrintToChat(client, "%s%t", PREFIX, "Name Edited");

		// Read the config
		new Handle:kv = CreateKeyValues("Zones");
		FileToKeyValues(kv, config);
		if (!KvGotoFirstSubKey(kv))
		{
			// Log an error if cant save zones config
			PrintToChat(client, "%s%t", PREFIX, "Cant save", map);
			CloseHandle(kv);

			// Redraw menu and discard changes
			ShowZoneOptionsMenu(client);
			return Plugin_Handled;
		}

		// Otherwise find the zone to edit
		decl String:buffer[MAX_ZONE_LENGTH];
		KvGetSectionName(kv, buffer, sizeof(buffer));
		do
		{
			// Compare name to make sure we gonna edit correct zone
			KvGetString(kv, "zone_ident", buffer, sizeof(buffer));
			if (StrEqual(buffer, OldZoneName, false))
			{
				// Write the new name in config
				KvSetString(kv, "zone_ident", text);
				break;
			}
		}
		while (KvGotoNextKey(kv));

		KvRewind(kv);
		KeyValuesToFile(kv, config);
		CloseHandle(kv);

		ShowZoneOptionsMenu(client);

		// Don't show new zone name in chat
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

/* Command_SetupZones()
 *
 * Shows a zones menu to a client.
 * -------------------------------------------------------------------------- */
public Action:Command_SetupZones(client, args)
{
	// Make sure valid client used a command
	if (!client)
	{
		ReplyToCommand(client, "%t", "Command is in-game only");
		return Plugin_Handled;
	}

	// Show a menu on zones command
	ShowZonesMainMenu(client);
	return Plugin_Handled;
}

/**
 * --------------------------------------------------------------------------
 *      __  ___
 *     /  |/  /___  ___  __  ________
 *    / /|_/ / _ \/ __ \/ / / // ___/
 *   / /  / /  __/ / / / /_/ /(__  )
 *  /_/  /_/\___/_/ /_/\__,_/_____/
 *
 * --------------------------------------------------------------------------
*/

/* ShowZonesMainMenu()
 *
 * Creates a menu handler to setup zones.
 * -------------------------------------------------------------------------- */
ShowZonesMainMenu(client)
{
	// When main menu is called, reset everything related to menu info
	EditingZone[client] = INIT;
	ZonePoint[client] =
	NamesZone[client] =
	RenamesZone[client] = false;

	ClearVector(FirstZoneVector[client]);
	ClearVector(SecondZoneVector[client]);

	// Create menu with translated items
	decl String:translation[128];
	new Handle:menu = CreateMenu(Menu_Zones);

	// Set menu title
	SetMenuTitle(menu, "%T\n \n", "Setup Zones For", client, map);

	// Translate a string and add menu items
	Format(translation, sizeof(translation), "%T", "Add Zones", client);
	AddMenuItem(menu, "add_zone", translation);

	Format(translation, sizeof(translation), "%T\n \n", "Active Zones", client);
	AddMenuItem(menu, "active_zones", translation);

	// Add exit button, and display menu as long as possible
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

/* Menu_Zones()
 *
 * Main menu to setup zones.
 * -------------------------------------------------------------------------- */
public Menu_Zones(Handle:menu, MenuAction:action, client, param)
{
	if (action == MenuAction_Select)
	{
		decl String:info[17];

		// Retrieve info of menu item
		GetMenuItem(menu, param, info, sizeof(info));

		// Player selected 'Add Zone' menu
		if (StrEqual(info, "add_zone", false))
		{
			// Print an instruction in player's chat
			PrintToChat(client, "%s%t", PREFIX, "Add Zone Instruction");

			// Allow player to define zones by E button
			ZonePoint[client] = FIRST_POINT;
		}

		// No, maybe that was an 'Active zones' ?
		else if (StrEqual(info, "active_zones", false))
		{
			ShowActiveZonesMenu(client);
		}
	}
	else if (action == MenuAction_End)
	{
		// Close menu handle on menu ending
		CloseHandle(menu);
	}
}


/* ShowActiveZonesMenu()
 *
 * Creates a menu handler to setup active zones.
 * -------------------------------------------------------------------------- */
ShowActiveZonesMenu(client)
{
	new Handle:menu = CreateMenu(Menu_ActiveZones);

	// Set menu title
	SetMenuTitle(menu, "%T:", "Active Zones", client);

	decl String:name[PLATFORM_MAX_PATH], String:strnum[8];
	for (new i; i < GetArraySize(ZonesArray); i++)
	{
		// Loop through all zones in array
		new Handle:hZone = GetArrayCell(ZonesArray, i);
		GetArrayString(hZone, ZONE_NAME, name, sizeof(name));

		// Add every zone as a menu item
		IntToString(i, strnum, sizeof(strnum));
		AddMenuItem(menu, strnum, name);
	}

	// Add exit button
	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

/* Menu_ActiveZones()
 *
 * Menu handler to select/edit active zones.
 * -------------------------------------------------------------------------- */
public Menu_ActiveZones(Handle:menu, MenuAction:action, client, param)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			decl String:info[8], zone;
			GetMenuItem(menu, param, info, sizeof(info));

			// Define a zone number
			zone = StringToInt(info);

			// Store the zone index for further reference
			EditingZone[client] = zone;

			// Show zone menu
			ShowZoneOptionsMenu(client);
		}
		case MenuAction_Cancel:
		{
			// When player is pressed 'Back' button
			if (param == MenuCancel_ExitBack)
			{
				ShowZonesMainMenu(client);
			}
		}
		case MenuAction_End: CloseHandle(menu);
	}
}

/* ShowZoneOptionsMenu()
 *
 * Creates a menu handler to setup zones options.
 * -------------------------------------------------------------------------- */
ShowZoneOptionsMenu(client)
{
	// Make sure player is not editing any other zone at this moment
	if (EditingZone[client] != INIT)
	{
		decl String:ZoneName[MAX_ZONE_LENGTH], String:translation[128];

		new Handle:hZone = GetArrayCell(ZonesArray, EditingZone[client]);
		GetArrayString(hZone, ZONE_NAME, ZoneName, sizeof(ZoneName));

		// Create menu handler and set menu title
		new Handle:menu = CreateMenu(Menu_ZoneOptions);
		SetMenuTitle(menu, "%T", "Manage Zone", client, ZoneName);

		// Add 7 items to main menu to edit
		Format(translation, sizeof(translation), "%T", "Edit First Point", client);
		AddMenuItem(menu, "vec1", translation);

		Format(translation, sizeof(translation), "%T", "Edit Second Point", client);
		AddMenuItem(menu, "vec2", translation);

		Format(translation, sizeof(translation), "%T", "Edit Name", client);
		AddMenuItem(menu, "zone_ident", translation);

		Format(translation, sizeof(translation), "%T", "Teleport To", client);

		// Also appripriately set info for every menu item
		AddMenuItem(menu, "teleport", translation);

		// Add 'delete zone' option
		Format(translation, sizeof(translation), "%T", "Delete Zone", client);
		AddMenuItem(menu, "delete", translation);

		// Display menu and add 'Exit' button
		SetMenuExitBackButton(menu, true);
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
	}
}

/* Menu_ZoneOptions()
 *
 * Menu handler to fully edit a zone.
 * -------------------------------------------------------------------------- */
public Menu_ZoneOptions(Handle:menu, MenuAction:action, client, param)
{
	// Retrieve the menu action
	switch (action)
	{
		case MenuAction_Select:
		{
			// Get a config, menu item info and initialize everything else
			decl String:config[PLATFORM_MAX_PATH], String:ZoneName[MAX_ZONE_LENGTH], String:info[11], Float:vec1[3], Float:vec2[3];
			GetMenuItem(menu, param, info, sizeof(info));
			BuildPath(Path_SM, config, sizeof(config), "data/zones/%s.cfg", map);

			// Retrieve zone which player is editing right now
			new Handle:hZone = GetArrayCell(ZonesArray, EditingZone[client]);

			// Retrieve vectors and a name
			GetArrayArray(hZone,  FIRST_VECTOR,  vec1, VECTORS_SIZE);
			GetArrayArray(hZone,  SECOND_VECTOR, vec2, VECTORS_SIZE);
			GetArrayString(hZone, ZONE_NAME,     ZoneName, sizeof(ZoneName));

			// Now teleport player in center of a zone
			if (StrEqual(info, "teleport", false))
			{
				decl Float:origin[3];
				GetMiddleOfABox(vec1, vec2, origin);
				TeleportEntity(client, origin, NULL_VECTOR, Float:{0.0, 0.0, 0.0});

				// Redisplay the menu
				ShowZoneOptionsMenu(client);
			}
			// Zone coordinates is editing
			else if (StrEqual(info, "vec1", false) || StrEqual(info, "vec2", false))
			{
				if (StrEqual(info, "vec1", false))
					 EditingVector[client] = FIRST_VECTOR;
				else EditingVector[client] = SECOND_VECTOR;

				if (IsVectorZero(FirstZoneVector[client]) && IsVectorZero(SecondZoneVector[client]))
				{
					// Clear vectors on every selection
					ClearVector(FirstZoneVector[client]);
					ClearVector(SecondZoneVector[client]);

					// And increase on every selection
					AddVectors(FirstZoneVector[client],  vec1, FirstZoneVector[client]);
					AddVectors(SecondZoneVector[client], vec2, SecondZoneVector[client]);
				}

				// Always show a zone box
				TE_SendBeamBoxToClient(client, FirstZoneVector[client], SecondZoneVector[client], LaserMaterial, HaloMaterial, 0, 30, LIFETIME_INTERVAL, 5.0, 5.0, 2, 1.0, { 0, 127, 255, 255 }, 0);

				// Highlight the currently edited edge for players editing a zone
				if (EditingVector[client] == FIRST_VECTOR)
				{
					TE_SetupGlowSprite(FirstZoneVector[client], GlowSprite, LIFETIME_INTERVAL, 1.0, 100);
					TE_SendToClient(client);
				}
				else //if (EditingVector[client] == SECOND_VECTOR)
				{
					TE_SetupGlowSprite(SecondZoneVector[client], GlowSprite, LIFETIME_INTERVAL, 1.0, 100);
					TE_SendToClient(client);
				}

				// Don't close vectors edit menu on every selection
				ShowZoneVectorEditMenu(client);
			}
			else if (StrEqual(info, "zone_ident", false))
			{
				// Set rename bool to deal with say/say_team callbacks and retrieve name string
				PrintToChat(client, "%s%t", PREFIX, "Type Zone Name");
				RenamesZone[client] = true;
			}
			else if (StrEqual(info, "delete", false))
			{
				// Create confirmation panel
				new Handle:panel = CreatePanel();

				decl String:buffer[128];

				// Draw a panel with only 'Yes/No' options
				Format(buffer, sizeof(buffer), "%T", "Confirm Delete Zone", client, ZoneName);
				SetPanelTitle(panel, buffer);

				Format(buffer, sizeof(buffer), "%T", "Yes", client);
				DrawPanelItem(panel, buffer);

				Format(buffer, sizeof(buffer), "%T", "No", client);
				DrawPanelItem(panel, buffer);

				// Send panel
				SendPanelToClient(panel, client, Panel_Confirmation, MENU_TIME_FOREVER);

				// Close panel handler just now
				CloseHandle(panel);
			}
		}
		case MenuAction_Cancel:
		{
			// Set player to not editing something when menu is closed
			EditingZone[client] = EditingVector[client] = INIT;

			// Clear vectors that client has changed before
			ClearVector(FirstZoneVector[client]);
			ClearVector(SecondZoneVector[client]);

			// When client pressed 'Back' option
			if (param == MenuCancel_ExitBack)
			{
				// Show active zones menu
				ShowActiveZonesMenu(client);
			}
		}
		case MenuAction_End: CloseHandle(menu);
	}
}


/* ShowZoneVectorEditMenu()
 *
 * Creates a menu handler to setup zone coordinations.
 * -------------------------------------------------------------------------- */
ShowZoneVectorEditMenu(client)
{
	// Make sure player is not editing any other zone at this moment
	if (EditingZone[client] != INIT || EditingVector[client] != INIT)
	{
		// Initialize translation string
		decl String:ZoneName[MAX_ZONE_LENGTH], String:translation[128];

		// Get the zone name
		new Handle:hZone = GetArrayCell(ZonesArray, EditingZone[client]);
		GetArrayString(hZone, ZONE_NAME, ZoneName, sizeof(ZoneName));

		new Handle:menu = CreateMenu(Menu_ZoneVectorEdit);
		SetMenuTitle(menu, "%T", "Edit Zone", client, ZoneName, EditingVector[client]);

		Format(translation, sizeof(translation), "%T", "Add to X", client);
		AddMenuItem(menu, "ax", translation);

		Format(translation, sizeof(translation), "%T", "Add to Y", client);

		// Set every menu item as unique
		AddMenuItem(menu, "ay", translation);

		Format(translation, sizeof(translation), "%T", "Add to Z", client);
		AddMenuItem(menu, "az", translation);

		Format(translation, sizeof(translation), "%T", "Subtract from X", client);
		AddMenuItem(menu, "sx", translation);

		Format(translation, sizeof(translation), "%T", "Subtract from Y", client);
		AddMenuItem(menu, "sy", translation);

		Format(translation, sizeof(translation), "%T", "Subtract from Z", client);
		AddMenuItem(menu, "sz", translation);

		// Add save option
		Format(translation, sizeof(translation), "%T\n \n", "Save", client);
		AddMenuItem(menu, "save", translation);

		// Add \n \n in save option to make spacer between 7 and 8 buttons
		Format(translation, sizeof(translation), "%T", "Back", client);
		AddMenuItem(menu, "back", translation);

		// Also add 'Back' button and show menu as long as possible
		//SetMenuExitBackButton(menu, true);

		// Set no pagination so we have 'save' button as 7th param
		SetMenuPagination(menu, MENU_NO_PAGINATION);
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
	}
}

/* Menu_ZoneVectorEdit()
 *
 * Menu handler to edit zone coordinates/vectors.
 * -------------------------------------------------------------------------- */
public Menu_ZoneVectorEdit(Handle:menu, MenuAction:action, client, param)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			// Get the menu item
			decl String:info[5];
			GetMenuItem(menu, param, info, sizeof(info));

			// Save the new coordinates to the file and the array
			if (StrEqual(info, "save", false))
			{
				decl String:ZoneName[MAX_ZONE_LENGTH];
				new Handle:hZone = GetArrayCell(ZonesArray, EditingZone[client]);

				// Retrieve zone name and appropriately set zone vector (client info) on every selection
				GetArrayString(hZone, ZONE_NAME,     ZoneName, sizeof(ZoneName));
				SetArrayArray(hZone,  FIRST_VECTOR,  FirstZoneVector[client],  VECTORS_SIZE);
				SetArrayArray(hZone,  SECOND_VECTOR, SecondZoneVector[client], VECTORS_SIZE);

				// Re-spawn zone when its saved (its better, trust me)
				KillZone(EditingZone[client]);
				SpawnZone(EditingZone[client]);

				// Notify client about saving position
				PrintToChat(client, "%s%t", PREFIX, "Saved");

				// Write changes into config file
				decl String:config[PLATFORM_MAX_PATH];
				BuildPath(Path_SM, config, sizeof(config), "data/zones/%s.cfg", map);

				new Handle:kv = CreateKeyValues("Zones");
				FileToKeyValues(kv, config);

				// But before make sure config is not corrupted
				if (!KvGotoFirstSubKey(kv))
				{
					CloseHandle(kv);
					ShowZoneVectorEditMenu(client);

					// Error
					PrintToChat(client, "%s%t", PREFIX, "Cant save", map);
					return;
				}

				decl String:buffer[MAX_ZONE_LENGTH];
				KvGetSectionName(kv, buffer, sizeof(buffer));

				// Go thru KV config
				do
				{
					// Set coordinates for zone
					KvGetString(kv, "zone_ident", buffer, sizeof(buffer));
					if (StrEqual(buffer, ZoneName, false))
					{
						// Set appropriate section for KV config
						KvSetVector(kv, "coordinates 1", FirstZoneVector[client]);
						KvSetVector(kv, "coordinates 2", SecondZoneVector[client]);
						break;
					}
				}

				// Until config is ended
				while (KvGotoNextKey(kv));

				KvRewind(kv);
				KeyValuesToFile(kv, config);
				CloseHandle(kv);
			}

			// Add X
			else if (StrEqual(info, "ax", false))
			{
				// Add to the x axis
				if (EditingVector[client] == FIRST_VECTOR)
				{
					// Move zone for 5 units on every selection
					FirstZoneVector[client][0] += 5.0;
				}
				else SecondZoneVector[client][0] += 5.0;
			}
			else if (StrEqual(info, "ay", false))
			{
				// Add to the y axis
				if (EditingVector[client] == FIRST_VECTOR)
				{
					FirstZoneVector[client][1] += 5.0;
				}
				else SecondZoneVector[client][1] += 5.0;
			}
			else if (StrEqual(info, "az", false))
			{
				// Add to the z axis
				if (EditingVector[client] == FIRST_VECTOR)
				{
					FirstZoneVector[client][2] += 5.0;
				}
				else SecondZoneVector[client][2] += 5.0;
			}

			// Subract X
			else if (StrEqual(info, "sx", false))
			{
				// Subtract from the x axis
				if (EditingVector[client] == FIRST_VECTOR)
				{
					FirstZoneVector[client][0] -= 5.0;
				}
				else SecondZoneVector[client][0] -= 5.0;
			}
			else if (StrEqual(info, "sy", false))
			{
				// Subtract from the y axis
				if (EditingVector[client] == FIRST_VECTOR)
				{
					FirstZoneVector[client][1] -= 5.0;
				}
				else SecondZoneVector[client][1] -= 5.0;
			}
			else if (StrEqual(info, "sz", false))
			{
				// Subtract from the z axis
				if (EditingVector[client] == FIRST_VECTOR)
				{
					FirstZoneVector[client][2] -= 5.0;
				}
				else SecondZoneVector[client][2] -= 5.0;
			}

			// Always show a zone box on every selection
			TE_SendBeamBoxToClient(client, FirstZoneVector[client], SecondZoneVector[client], LaserMaterial, HaloMaterial, 0, 30, LIFETIME_INTERVAL, 5.0, 5.0, 2, 1.0, { 0, 127, 255, 255 }, 0);

			// Highlight the currently edited edge for players editing a zone
			if (EditingVector[client] == FIRST_VECTOR)
			{
				TE_SetupGlowSprite(FirstZoneVector[client], GlowSprite, LIFETIME_INTERVAL, 1.0, 100);
				TE_SendToClient(client);
			}
			else //if (EditingVector[client] == SECOND_VECTOR)
			{
				TE_SetupGlowSprite(SecondZoneVector[client], GlowSprite, LIFETIME_INTERVAL, 1.0, 100);
				TE_SendToClient(client);
			}

			if (!StrEqual(info, "back", false))
			{
				// Redisplay the menu if no 'back' button were pressed
				ShowZoneVectorEditMenu(client);
			}
			else ShowZoneOptionsMenu(client); // Otherwise go into main menu
		}
		case MenuAction_Cancel:
		{
			// When player is presset 'back' button
			if (param == MenuCancel_ExitBack)
			{
				// Redraw zone options menu
				ShowZoneOptionsMenu(client);
			}
			else EditingZone[client] = INIT; // When player just pressed Exit button, make sure player is not editing any zone anymore
		}
		case MenuAction_End: CloseHandle(menu);
	}
}


/* ShowSaveZoneMenu()
 *
 * Creates a menu handler to save or discard new zone.
 * -------------------------------------------------------------------------- */
ShowSaveZoneMenu(client, const String:name[])
{
	decl String:translation[128];

	// Confirm the new zone after naming
	new Handle:menu = CreateMenu(Menu_SaveZone);
	SetMenuTitle(menu, "%T", "Adding Zone", client);

	// Add 2 options to menu - Save & Discard
	Format(translation, sizeof(translation), "%T", "Save", client);
	AddMenuItem(menu, name, translation);
	Format(translation, sizeof(translation), "%T", "Discard", client);
	AddMenuItem(menu, "discard", translation);

	// Dont show 'Exit' button here
	SetMenuExitButton(menu, false);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

/* Menu_SaveZone()
 *
 * Menu handler to save new created zone.
 * -------------------------------------------------------------------------- */
public Menu_SaveZone(Handle:menu, MenuAction:action, client, param)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			decl String:info[MAX_ZONE_LENGTH];
			GetMenuItem(menu, param, info, sizeof(info));

			// Don't save the new zone if player pressed 'Discard' option
			if (StrEqual(info, "discard", false))
			{
				// Clear vectors
				ClearVector(FirstZoneVector[client]);
				ClearVector(SecondZoneVector[client]);

				// Notify player
				PrintToChat(client, "%s%t", PREFIX, "Discarded");
			}
			else // Save the new zone, because any other item is selected
			{
				// Save new zone in config
				decl String:config[PLATFORM_MAX_PATH];
				BuildPath(Path_SM, config, sizeof(config), "data/zones/%s.cfg", map);

				// Get "Zones" config
				new Handle:kv = CreateKeyValues("Zones"), number;
				FileToKeyValues(kv, config);

				decl String:buffer[MAX_ZONE_LENGTH], String:strnum[8], temp;
				if (KvGotoFirstSubKey(kv))
				{
					do
					{
						// Get the highest numer and increase it by 1
						KvGetSectionName(kv, buffer, sizeof(buffer));
						temp = StringToInt(buffer);

						// Saving every zone as a number is faster and safer
						if (temp >= number)
						{
							// Set another increased number for zone in config
							number = ++temp;
						}

						// Oops there is already a zone with this name
						KvGetString(kv, "zone_ident", buffer, sizeof(buffer));
						if (StrEqual(buffer, info, false))
						{
							// Notify player about that and hook say/say_team callbacks to allow player to give new name
							PrintToChat(client, "%s%t", PREFIX, "Name Already Taken", info);
							NamesZone[client] = true;
							return;
						}
					}
					while (KvGotoNextKey(kv));
					KvGoBack(kv);
				}

				// Convert number to a string (we're dealing with KV)
				IntToString(number, strnum, sizeof(strnum));

				// Jump to zone number
				KvJumpToKey(kv, strnum, true);

				// Set name and coordinates
				KvSetString(kv, "zone_ident",    info);
				KvSetVector(kv, "coordinates 1", FirstZoneVector[client]);
				KvSetVector(kv, "coordinates 2", SecondZoneVector[client]);

				// Get back to the top, save config and close KV handle again
				KvRewind(kv);
				KeyValuesToFile(kv, config);
				CloseHandle(kv);

				// Store the current vectors to the array
				new Handle:TempArray = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));

				// Set the name
				PushArrayString(TempArray, info);

				// Set the first coordinates
				PushArrayArray(TempArray, FirstZoneVector[client], VECTORS_SIZE);

				// Set the second coordinates
				PushArrayArray(TempArray, SecondZoneVector[client], VECTORS_SIZE);

				// Set editing zone for a player
				EditingZone[client] = PushArrayCell(ZonesArray, TempArray);

				// Spawn the trigger_multiple entity (zone)
				SpawnZone(EditingZone[client]);

				// Notify client about successfull saving
				PrintToChat(client, "%s%t", PREFIX, "Saved");

				// Show edit zone options for client
				ShowZoneOptionsMenu(client);
			}
		}
		case MenuAction_Cancel:
		{
			// When menu is ended - reset everything
			EditingZone[client] = EditingVector[client] = INIT;

			ClearVector(FirstZoneVector[client]);
			ClearVector(SecondZoneVector[client]);

			if (param == MenuCancel_ExitBack)
			{
				// If player pressed back button, show active zones menu (again)
				ShowActiveZonesMenu(client);
			}
		}
		case MenuAction_End: CloseHandle(menu);
	}
}

/* Panel_Confirmation()
 *
 * Panel handler to confirm zone deletion.
 * -------------------------------------------------------------------------- */
public Panel_Confirmation(Handle:menu, MenuAction:action, client, param)
{
	// Client pressed a button
	if (action == MenuAction_Select)
	{
		// 'Yes' - so delete zone
		if (param == 1)
		{
			// Kill the trigger_multiple entity (a box)
			KillZone(EditingZone[client]);

			// Delete from cache array
			decl String:ZoneName[MAX_ZONE_LENGTH];
			new Handle:hZone = GetArrayCell(ZonesArray, EditingZone[client]);

			// Close array handle
			GetArrayString(hZone, ZONE_NAME, ZoneName, sizeof(ZoneName));
			CloseHandle(hZone);

			// Remove info from array
			RemoveFromArray(ZonesArray, EditingZone[client]);

			// Reset edited zone appropriately
			EditingZone[client] = INIT;

			// Delete zone from config file
			decl String:config[PLATFORM_MAX_PATH];
			BuildPath(Path_SM, config, sizeof(config), "data/zones/%s.cfg", map);

			new Handle:kv = CreateKeyValues("Zones");
			FileToKeyValues(kv, config);
			if (!KvGotoFirstSubKey(kv))
			{
				// Something was wrong - stop and draw active zones again
				CloseHandle(kv);
				ShowActiveZonesMenu(client);
				return;
			}

			decl String:buffer[MAX_ZONE_LENGTH];
			KvGetSectionName(kv, buffer, sizeof(buffer));
			do
			{
				// Compare zone names
				KvGetString(kv, "zone_ident", buffer, sizeof(buffer));
				if (StrEqual(buffer, ZoneName, false))
				{
					// Delete the whole zone section on match
					KvDeleteThis(kv);
					break;
				}
			}
			while (KvGotoNextKey(kv));

			KvRewind(kv);
			KeyValuesToFile(kv, config);
			CloseHandle(kv);

			// Notify client and show active zones menu
			PrintToChat(client, "%s%t", PREFIX, "Deleted Zone", ZoneName);
			ShowActiveZonesMenu(client);
		}
		else
		{
			// Player pressed 'No' button - cancel deletion and redraw previous menu
			PrintToChat(client, "%s%t", PREFIX, "Canceled Zone Deletion");
			ShowZoneOptionsMenu(client);
		}
	}
	else if (action == MenuAction_Cancel)
	{
		// Cancel deletion if menu was closed
		PrintToChat(client, "%s%t", PREFIX, "Canceled Zone Deletion");

		ShowZoneOptionsMenu(client);
	}

	// Since its just a panel - no need to check MenuAction_End action to close handle
}


/**
 * --------------------------------------------------------------------------
 *      ______                  __  _
 *     / ____/__  ______  _____/ /_(_)____  ____  _____
 *    / /_   / / / / __ \/ ___/ __/ // __ \/ __ \/ ___/
 *   / __/  / /_/ / / / / /__/ /_/ // /_/ / / / (__  )
 *  /_/     \__,_/_/ /_/\___/\__/_/ \____/_/ /_/____/
 *
 * --------------------------------------------------------------------------
*/

/* Timer_ShowZones()
 *
 * Repeatable timer to redraw zones on a map.
 * -------------------------------------------------------------------------- */
public Action:Timer_ShowZones(Handle:timer)
{
	// Get all zones
	for (new i; i < GetArraySize(ZonesArray); i++)
	{
		// Initialize positions, other stuff
		decl Float:pos1[3], Float:pos2[3], client;
		new Handle:hZone = GetArrayCell(ZonesArray, i);

		// Retrieve positions from array
		GetArrayArray(hZone, FIRST_VECTOR,  pos1, VECTORS_SIZE);
		GetArrayArray(hZone, SECOND_VECTOR, pos2, VECTORS_SIZE);

		// Loop through all clients
		for (client = 1; client <= MaxClients; client++)
		{
			if (IsClientInGame(client))
			{
				// If player is editing a zones - show all zones then
				if (EditingZone[client] != INIT || GetConVarBool(show_zones))
				{
					TE_SendBeamBoxToClient(client, pos1, pos2, LaserMaterial, HaloMaterial, 0, 30, LIFETIME_INTERVAL, 5.0, 5.0, 2, 1.0, { 0, 127, 255, 255 }, 0);
				}
			}
		}
	}
}

/* ParseZoneConfig()
 *
 * Prepares a zones config at every map change.
 * -------------------------------------------------------------------------- */
ParseZoneConfig()
{
	// Clear previous info
	CloseHandleArray(ZonesArray);
	ClearArray(ZonesArray);

	// Get the config
	decl String:config[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, config, sizeof(config), "data/zones/%s.cfg", map);

	if (FileExists(config))
	{
		// Load config for this map if exists
		new Handle:kv = CreateKeyValues("Zones");
		FileToKeyValues(kv, config);
		if (!KvGotoFirstSubKey(kv))
		{
			CloseHandle(kv);
			return;
		}

		// Initialize everything, also get the section names
		decl String:buffer[MAX_ZONE_LENGTH], Float:vector[3], zoneIndex;
		KvGetSectionName(kv, buffer, sizeof(buffer));

		// Go through config for this map
		do
		{
			// Create temporary array
			new Handle:TempArray = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));

			// Retrieve zone name, and push name into temp array
			KvGetString(kv, "zone_ident", buffer, sizeof(buffer));
			PushArrayString(TempArray, buffer);

			// Get first coordinations
			KvGetVector(kv, "coordinates 1", vector);
			PushArrayArray(TempArray, vector, VECTORS_SIZE);

			// Second coordinations
			KvGetVector(kv, "coordinates 2", vector);
			PushArrayArray(TempArray, vector, VECTORS_SIZE);

			// Get the zone index
			zoneIndex = PushArrayCell(ZonesArray, TempArray);

			// Spawn a zone each time KV got a config for
			SpawnZone(zoneIndex);
		}

		// Until keyvalues config is ended
		while (KvGotoNextKey(kv));

		// Get back to the top
		KvGoBack(kv);

		// And close KeyValues handler
		CloseHandle(kv);
	}
}

/* SpawnZone()
 *
 * Spawns a trigger_multiple entity (zone)
 * -------------------------------------------------------------------------- */
SpawnZone(zoneIndex)
{
	decl Float:middle[3], Float:m_vecMins[3], Float:m_vecMaxs[3], String:ZoneName[MAX_ZONE_LENGTH+9];

	// Get zone index from array
	new Handle:hZone = GetArrayCell(ZonesArray, zoneIndex);
	GetArrayArray(hZone,  FIRST_VECTOR,  m_vecMins, VECTORS_SIZE);
	GetArrayArray(hZone,  SECOND_VECTOR, m_vecMaxs, VECTORS_SIZE);
	GetArrayString(hZone, ZONE_NAME,     ZoneName, sizeof(ZoneName));

	// Create a zone (best entity for that is trigger_multiple)
	new zone = CreateEntityByName("func_wall");

	// Set name
	Format(ZoneName, sizeof(ZoneName), "sm_zone_%s", ZoneName);
	DispatchKeyValue(zone, "targetname", ZoneName);
	DispatchKeyValue(zone, "spawnflags", "64");
	DispatchKeyValue(zone, "disableshadows", "1");

	// Spawn an entity
	DispatchSpawn(zone);

	// Since its brush entity, use ActivateEntity as well
	ActivateEntity(zone);

	// Get the middle of zone
	GetMiddleOfABox(m_vecMins, m_vecMaxs, middle);

	// Move zone entity in middle of a box
	TeleportEntity(zone, middle, NULL_VECTOR, NULL_VECTOR);

	// Set the model (yea, its also required for brush model)
	SetEntityModel(zone, ZONES_MODEL);

	// Have the m_vecMins always be negative
	m_vecMins[0] = m_vecMins[0] - middle[0];
	if (m_vecMins[0] > 0.0)
		m_vecMins[0] *= -1.0;
	m_vecMins[1] = m_vecMins[1] - middle[1];
	if (m_vecMins[1] > 0.0)
		m_vecMins[1] *= -1.0;
	m_vecMins[2] = m_vecMins[2] - middle[2];
	if (m_vecMins[2] > 0.0)
		m_vecMins[2] *= -1.0;

	// And the m_vecMaxs always be positive
	m_vecMaxs[0] = m_vecMaxs[0] - middle[0];
	if (m_vecMaxs[0] < 0.0)
		m_vecMaxs[0] *= -1.0;
	m_vecMaxs[1] = m_vecMaxs[1] - middle[1];
	if (m_vecMaxs[1] < 0.0)
		m_vecMaxs[1] *= -1.0;
	m_vecMaxs[2] = m_vecMaxs[2] - middle[2];
	if (m_vecMaxs[2] < 0.0)
		m_vecMaxs[2] *= -1.0;

	// Set mins and maxs for entity
	SetEntPropVector(zone, Prop_Send, "m_vecMins", m_vecMins);
	SetEntPropVector(zone, Prop_Send, "m_vecMaxs", m_vecMaxs);

	SetEntProp(zone, Prop_Send, "m_nSolidType", 2);
	SetEntProp(zone, Prop_Send, "m_CollisionGroup", 11);

	new m_fEffects = GetEntProp(zone, Prop_Send, "m_fEffects");
	m_fEffects |= 32;
	SetEntProp(zone, Prop_Send, "m_fEffects", m_fEffects);
}

/* KillZone()
 *
 * Removes a trigger_multiple entity (zone) from a world.
 * -------------------------------------------------------------------------- */
KillZone(zoneIndex)
{
	decl String:ZoneName[MAX_ZONE_LENGTH], String:class[MAX_ZONE_LENGTH+9], zone;

	// Get the zone index and name of a zone
	new Handle:hZone = GetArrayCell(ZonesArray, zoneIndex);
	GetArrayString(hZone, ZONE_NAME, ZoneName, sizeof(ZoneName));

	zone = INIT;
	while ((zone = FindEntityByClassname(zone, "func_wall")) != INIT)
	{
		if (IsValidEntity(zone)
		&& GetEntPropString(zone, Prop_Data, "m_iName", class, sizeof(class)) // Get m_iName datamap
		&& StrEqual(class[8], ZoneName, false)) // And check if m_iName is equal to name from array
		{
			AcceptEntityInput(zone, "Kill");
			break;
		}
	}
}

/**
 * --------------------------------------------------------------------------
 *      __  ___
 *     /  |/  (_)__________
 *    / /|_/ / // ___/ ___/
 *   / /  / / /(__  ) /__
 *  /_/  /_/_//____/\___/
 *
 * --------------------------------------------------------------------------
*/

/* CloseHandleArray()
 *
 * Closes active adt_array handles.
 * -------------------------------------------------------------------------- */
CloseHandleArray(Handle:adt_array)
{
	// Loop through all array handles
	for (new i; i < GetArraySize(adt_array); i++)
	{
		// Retrieve cell value from array, and close it
		new Handle:hZone = GetArrayCell(adt_array, i);
		CloseHandle(hZone);
	}
}

/* ClearVector()
 *
 * Resets vector to 0.0
 * -------------------------------------------------------------------------- */
ClearVector(Float:vec[3])
{
	vec[0] = vec[1] = vec[2] = 0.0;
}

/* IsVectorZero()
 *
 * SourceMod Anti-Cheat stock.
 * -------------------------------------------------------------------------- */
bool:IsVectorZero(const Float:vec[3])
{
	return vec[0] == 0.0 && vec[1] == 0.0 && vec[2] == 0.0;
}

/* GetMiddleOfABox()
 *
 * Retrieves a real center of zone box.
 * -------------------------------------------------------------------------- */
GetMiddleOfABox(const Float:vec1[3], const Float:vec2[3], Float:buffer[3])
{
	// Just make vector from points and half-divide it
	decl Float:mid[3];
	MakeVectorFromPoints(vec1, vec2, mid);
	mid[0] = mid[0] / 2.0;
	mid[1] = mid[1] / 2.0;
	mid[2] = mid[2] / 2.0;
	AddVectors(vec1, mid, buffer);
}

/**
 * Sets up a boxed beam effect.
 *
 * Ported from eventscripts vecmath library
 *
 * @param client		The client to show the box to.
 * @param upc			One upper corner of the box.
 * @param btc			One bottom corner of the box.
 * @param ModelIndex	Precached model index.
 * @param HaloIndex		Precached model index.
 * @param StartFrame	Initital frame to render.
 * @param FrameRate		Beam frame rate.
 * @param Life			Time duration of the beam.
 * @param Width			Initial beam width.
 * @param EndWidth		Final beam width.
 * @param FadeLength	Beam fade time duration.
 * @param Amplitude		Beam amplitude.
 * @param color			Color array (r, g, b, a).
 * @param Speed			Speed of the beam.
 * @noreturn
  * -------------------------------------------------------------------------- */
TE_SendBeamBoxToClient(client, const Float:upc[3], const Float:btc[3], ModelIndex, HaloIndex, StartFrame, FrameRate, const Float:Life, const Float:Width, const Float:EndWidth, FadeLength, const Float:Amplitude, const Color[4], Speed)
{
	// Create the additional corners of the box
	decl Float:tc1[] = {0.0, 0.0, 0.0};
	decl Float:tc2[] = {0.0, 0.0, 0.0};
	decl Float:tc3[] = {0.0, 0.0, 0.0};
	decl Float:tc4[] = {0.0, 0.0, 0.0};
	decl Float:tc5[] = {0.0, 0.0, 0.0};
	decl Float:tc6[] = {0.0, 0.0, 0.0};

	AddVectors(tc1, upc, tc1);
	AddVectors(tc2, upc, tc2);
	AddVectors(tc3, upc, tc3);
	AddVectors(tc4, btc, tc4);
	AddVectors(tc5, btc, tc5);
	AddVectors(tc6, btc, tc6);

	tc1[0] = btc[0];
	tc2[1] = btc[1];
	tc3[2] = btc[2];
	tc4[0] = upc[0];
	tc5[1] = upc[1];
	tc6[2] = upc[2];

	// Draw all the edges
	TE_SetupBeamPoints(upc, tc1, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(upc, tc2, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(upc, tc3, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc6, tc1, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc6, tc2, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc6, btc, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc4, btc, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc5, btc, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc5, tc1, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc5, tc3, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc4, tc3, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc4, tc2, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
}
