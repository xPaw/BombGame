#include < sourcemod >
#include < sdktools >

public Plugin:myinfo =
{
	name = "Spawn Editor",
	author = "meng",
	description = "Spawn point editing tools",
	version = "1.0",
	url = ""
}

new Handle:KillSpawnsADT;
new Handle:CustSpawnsADT;
new bool:RemoveDefSpawns;
new bool:InEditMode;
new String:MapCfgPath[PLATFORM_MAX_PATH];
new BlueGlowSprite;

public OnPluginStart()
{
	RegAdminCmd("bombgame_spawns", Command_SetupZones, ADMFLAG_CONFIG, "Opens the spawn editor menu");
	
	decl String:configspath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, configspath, sizeof(configspath), "data/bombgame_spawns");
	if (!DirExists(configspath))
		CreateDirectory(configspath, 0x0265);

	KillSpawnsADT = CreateArray(3);
	CustSpawnsADT = CreateArray(5);
}

public OnMapStart()
{
	RemoveDefSpawns = false;
	InEditMode = false;

	new String:mapName[64], String:curmap[64];
	GetCurrentMap(curmap, sizeof(curmap));
	
	// Does current map string is contains a "workshop" word?
	if (strncmp(curmap, "workshop", 8) == 0)
	{
		// If yes - skip the first 19 characters to avoid comparing the "workshop/12345678" prefix
		strcopy(mapName, sizeof(mapName), curmap[19]);
	}
	else
	{
		// Not a workshop map
		strcopy(mapName, sizeof(mapName), curmap);
	}
	
	BuildPath(Path_SM, MapCfgPath, sizeof(MapCfgPath), "data/bombgame_spawns/%s.cfg", mapName);
	ReadConfig();
	
	BlueGlowSprite = PrecacheModel("sprites/blueglow1.vmt");
}

ReadConfig()
{
	new Handle:kv = CreateKeyValues("ST7Root");
	if (FileToKeyValues(kv, MapCfgPath))
	{
		new num;
		decl String:sBuffer[32], Float:fVec[3], Float:DataFloats[5];
		if (KvGetNum(kv, "remdefsp"))
		{
			RemoveAllDefaultSpawns();
			RemoveDefSpawns = true;
		}
		else
		{
			Format(sBuffer, sizeof(sBuffer), "rs:%d:pos", num);
			KvGetVector(kv, sBuffer, fVec);
			while (fVec[0] != 0.0)
			{
				RemoveSingleDefaultSpawn(fVec);
				PushArrayArray(KillSpawnsADT, fVec);
				num++;
				Format(sBuffer, sizeof(sBuffer), "rs:%d:pos", num);
				KvGetVector(kv, sBuffer, fVec);
			}
		}
		num = 0;
		Format(sBuffer, sizeof(sBuffer), "ns:%d:pos", num);
		KvGetVector(kv, sBuffer, fVec);
		while (fVec[0] != 0.0)
		{
			DataFloats[0] = fVec[0];
			DataFloats[1] = fVec[1];
			DataFloats[2] = fVec[2];
			Format(sBuffer, sizeof(sBuffer), "ns:%d:ang", num);
			DataFloats[3] = KvGetFloat(kv, sBuffer);
			Format(sBuffer, sizeof(sBuffer), "ns:%d:team", num);
			DataFloats[4] = KvGetFloat(kv, sBuffer);
			CreateSpawn(DataFloats, false);
			PushArrayArray(CustSpawnsADT, DataFloats);
			num++;
			Format(sBuffer, sizeof(sBuffer), "ns:%d:pos", num);
			KvGetVector(kv, sBuffer, fVec);
		}
	}

	CloseHandle(kv);
}

public Action:Command_SetupZones(client, args)
{
	if (client)
	{
		ShowToolzMenu(client);
	}
	
	return Plugin_Handled;
}

ShowToolzMenu(client)
{
	new Handle:menu = CreateMenu(MainMenuHandler);
	SetMenuTitle(menu, "Spawn Editor");
	decl String:menuItem[64];
	Format(menuItem, sizeof(menuItem), "%s Edit Mode", InEditMode == false ? "Enable" : "Disable");
	AddMenuItem(menu, "0", menuItem);
	Format(menuItem, sizeof(menuItem), "%s Default Spawn Removal", RemoveDefSpawns == false ? "Enable" : "Disable");
	AddMenuItem(menu, "1", menuItem);
	AddMenuItem(menu, "2", "Add T Spawn");
	AddMenuItem(menu, "3", "Add CT Spawn");
	AddMenuItem(menu, "4", "Remove Spawn");
	AddMenuItem(menu, "5", "Save Configuration");
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public MainMenuHandler(Handle:menu, MenuAction:action, client, selection)
{
	if (action == MenuAction_Select)
	{
		if (selection == 0)
		{
			InEditMode = InEditMode == false ? true : false;
			PrintToChatAll(" \x01\x0B\x04[Spawn Editor]\x01 Edit Mode %s.", InEditMode == false ? "Disabled" : "Enabled");
			if (InEditMode)
				CreateTimer(1.0, ShowEditModeGoodies, INVALID_HANDLE, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

			ShowToolzMenu(client);
		}
		else if (selection == 1)
		{
			RemoveDefSpawns = RemoveDefSpawns == false ? true : false;
			PrintToChatAll(" \x01\x0B\x04[Spawn Editor]\x01 Default Spawn Removal will be %s.", RemoveDefSpawns == false ? "Disabled" : "Enabled");
			ShowToolzMenu(client);
		}
		else if (selection == 2)
		{
			InitializeNewSpawn(client, 2);
			ShowToolzMenu(client);
		}
		else if (selection == 3)
		{
			//InitializeNewSpawn(client, 3);
			PrintToChatAll(" \x01\x0B\x04[Spawn Editor]\x01 Refusing to create CT spawn because of BombGame!");
			ShowToolzMenu(client);
		}
		else if (selection == 4)
		{
			if (!RemoveSpawn(client))
				PrintToChatAll(" \x01\x0B\x04[Spawn Editor]\x01 No valid spawn point found.");
			else
				PrintToChatAll(" \x01\x0B\x04[Spawn Editor]\x01 Spawn point removed!");

			ShowToolzMenu(client);
		}
		else if (selection == 5)
		{
			SaveConfiguration();
			ShowToolzMenu(client);
		}
	}
	else if (action == MenuAction_End)
		CloseHandle(menu);
}

public Action:ShowEditModeGoodies(Handle:timer)
{
	if (!InEditMode)
		return Plugin_Stop;

	new maxEnt = GetMaxEntities(), tsCount, ctsCount;
	decl String:sClassName[64], Float:fVec[3];
	for (new i = MaxClients; i < maxEnt; i++)
	{
		if (IsValidEdict(i) && IsValidEntity(i) && GetEdictClassname(i, sClassName, sizeof(sClassName)))
		{
			if (StrEqual(sClassName, "info_player_terrorist"))
			{
				tsCount++;
				GetEntPropVector(i, Prop_Data, "m_vecOrigin", fVec);
				TE_SetupGlowSprite(fVec, BlueGlowSprite, 1.0, 0.4, 249);
				TE_SendToAll();
			}
			else if (StrEqual(sClassName, "info_player_counterterrorist"))
			{
				ctsCount++;
				GetEntPropVector(i, Prop_Data, "m_vecOrigin", fVec);
				TE_SetupGlowSprite(fVec, BlueGlowSprite, 1.0, 0.3, 237);
				TE_SendToAll();
			}
		}
	}
	PrintHintTextToAll("T Spawns: %i \nCT Spawns: %i", tsCount, ctsCount);

	return Plugin_Continue;
}

RemoveAllDefaultSpawns()
{
	new maxent = GetMaxEntities();
	decl String:sClassName[64];
	for (new i = MaxClients; i < maxent; i++)
	{
		if (IsValidEdict(i) && IsValidEntity(i) && GetEdictClassname(i, sClassName, sizeof(sClassName)) &&
		(StrEqual(sClassName, "info_player_terrorist") || StrEqual(sClassName, "info_player_counterterrorist")))
			RemoveEdict(i);
	}
}

RemoveSingleDefaultSpawn(Float:fVec[3])
{
	new maxent = GetMaxEntities();
	decl String:sClassName[64], Float:ent_fVec[3];
	for (new i = MaxClients; i < maxent; i++)
	{
		if (IsValidEdict(i) && IsValidEntity(i) && GetEdictClassname(i, sClassName, sizeof(sClassName)) &&
		(StrEqual(sClassName, "info_player_terrorist") || StrEqual(sClassName, "info_player_counterterrorist")))
		{
			GetEntPropVector(i, Prop_Data, "m_vecOrigin", ent_fVec);
			if (fVec[0] == ent_fVec[0])
			{
				RemoveEdict(i);
				break;
			}
		}
	}
}

InitializeNewSpawn(client, team)
{
	decl Float:DataFloats[5], Float:posVec[3], Float:angVec[3];
	GetClientAbsOrigin(client, posVec);
	GetClientEyeAngles(client, angVec);
	DataFloats[0] = posVec[0];
	DataFloats[1] = posVec[1];
	DataFloats[2] = (posVec[2] + 16.0);
	DataFloats[3] = angVec[1];
	DataFloats[4] = float(team);

	if (CreateSpawn(DataFloats, true))
		PrintToChatAll(" \x01\x0B\x04[Spawn Editor]\x01 New spawn point created!");
	else
		LogError("failed to create new sp entity");
}

CreateSpawn(Float:DataFloats[5], bool:isNew)
{
	decl Float:posVec[3], Float:angVec[3];
	posVec[0] = DataFloats[0];
	posVec[1] = DataFloats[1];
	posVec[2] = DataFloats[2];
	angVec[0] = 0.0;
	angVec[1] = DataFloats[3];
	angVec[2] = 0.0;

	new entity = CreateEntityByName(DataFloats[4] == 2.0 ? "info_player_terrorist" : "info_player_counterterrorist");
	if (DispatchSpawn(entity))
	{
		TeleportEntity(entity, posVec, angVec, NULL_VECTOR);
		if (isNew)
			PushArrayArray(CustSpawnsADT, DataFloats);

		return true;
	}

	return false;
}

RemoveSpawn(client)
{
	new arraySize = GetArraySize(CustSpawnsADT);
	new maxent = GetMaxEntities();
	decl Float:client_posVec[3], Float:DataFloats[5], String:sClassName[64], Float:ent_posVec[3], i, d;
	GetClientAbsOrigin(client, client_posVec);
	client_posVec[2] += 16;
	for (d = MaxClients; d < maxent; d++)
	{
		if (IsValidEdict(d) && IsValidEntity(d) && GetEdictClassname(d, sClassName, sizeof(sClassName)) && StrEqual(sClassName, "info_player_terrorist"))
		{
			GetEntPropVector(d, Prop_Data, "m_vecOrigin", ent_posVec);
			if (GetVectorDistance(client_posVec, ent_posVec) < 42.7)
			{
				for (i = 0; i < arraySize; i++)
				{
					GetArrayArray(CustSpawnsADT, i, DataFloats);
					if (DataFloats[0] == ent_posVec[0])
					{
						/* spawn was custom */
						RemoveFromArray(CustSpawnsADT, i);
						RemoveEdict(d);

						return true;
					}
				}
				/* spawn was default */
				PushArrayArray(KillSpawnsADT, ent_posVec);
				RemoveEdict(d);

				return true;
			}
		}
	}

	return false;
}

SaveConfiguration()
{
	new Handle:kv = CreateKeyValues("ST7Root");
	decl arraySize, String:sBuffer[32], Float:DataFloats[5], Float:posVec[3];
	KvJumpToKey(kv, "smdata", true);
	KvSetNum(kv, "remdefsp", RemoveDefSpawns == true ? 1 : 0);
	arraySize = GetArraySize(CustSpawnsADT);
	if (arraySize)
	{
		for (new i = 0; i < arraySize; i++)
		{
			GetArrayArray(CustSpawnsADT, i, DataFloats);
			posVec[0] = DataFloats[0];
			posVec[1] = DataFloats[1];
			posVec[2] = DataFloats[2];
			Format(sBuffer, sizeof(sBuffer), "ns:%d:pos", i);
			KvSetVector(kv, sBuffer, posVec);
			Format(sBuffer, sizeof(sBuffer), "ns:%d:ang", i);
			KvSetFloat(kv, sBuffer, DataFloats[3]);
			Format(sBuffer, sizeof(sBuffer), "ns:%d:team", i);
			KvSetFloat(kv, sBuffer, DataFloats[4]);
		}
	}
	arraySize = GetArraySize(KillSpawnsADT);
	if (arraySize)
	{
		for (new i = 0; i < arraySize; i++)
		{
			GetArrayArray(KillSpawnsADT, i, posVec);
			Format(sBuffer, sizeof(sBuffer), "rs:%d:pos", i);
			KvSetVector(kv, sBuffer, posVec);
		}
	}
	if (KeyValuesToFile(kv, MapCfgPath))
		PrintToChatAll(" \x01\x0B\x04[Spawn Editor]\x01 Configuration Saved!");
	else
		LogError("failed to save to key values");

	CloseHandle(kv);
}

public OnMapEnd()
{
	ClearArray(KillSpawnsADT);
	ClearArray(CustSpawnsADT);
}
