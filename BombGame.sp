#include < sourcemod >
#include < sdktools >
#include < cstrike >

#define HIDEHUD_RADAR  ( 1 << 12 )

#define BOMBER_SPEED   1.25
#define BOMBER_GRAVITY 0.75

public Plugin:myinfo =
{
	name = "BombGame",
	author = "xPaw",
	description = "Good ol' bomb game.",
	version = "1.0",
	url = "http://xpaw.ru"
};

new g_bDeadPlayers[ MAXPLAYERS ] = { false, ... };
new g_bStarting;
new g_bGameRunning;
new g_iLastBomber;
new g_iCurrentBomber;
new g_iPreviousBomber;
new bool:g_bMapHasHostages;
new bool:g_bIsNuke;
new bool:g_bIsAssault;
new Float:g_flRoundTime;
new Handle:g_hTimer = INVALID_HANDLE;
new Handle:g_hTimerSound = INVALID_HANDLE;
new Handle:g_hBlockedSounds;

public OnPluginStart( )
{
	g_hBlockedSounds = CreateTrie();
	
	SetTrieValue( g_hBlockedSounds, "items/itempickup.wav", 1 );
	SetTrieValue( g_hBlockedSounds, "player/death1.wav", 1 );
	SetTrieValue( g_hBlockedSounds, "player/death2.wav", 1 );
	SetTrieValue( g_hBlockedSounds, "player/death3.wav", 1 );
	SetTrieValue( g_hBlockedSounds, "player/death4.wav", 1 );
	SetTrieValue( g_hBlockedSounds, "player/death5.wav", 1 );
	SetTrieValue( g_hBlockedSounds, "player/death6.wav", 1 );
	
	HookEvent( "round_start",      OnRoundStart );
	HookEvent( "round_freeze_end", OnRoundFreezeEnd );
	HookEvent( "bomb_pickup",      OnBombPickup );
	HookEvent( "player_spawn",     OnPlayerSpawn );
	HookEvent( "player_death",     OnPlayerDeath );
	HookEvent( "player_death",     OnPlayerPreDeath, EventHookMode_Pre );
	HookEvent( "jointeam_failed",  OnJoinTeamFailed, EventHookMode_Pre );
	
	AddNormalSoundHook( OnNormalSound );
	
#if false
	new iEntity = -1, String:szZoneName[ 9 ];
	
	while( ( iEntity = FindEntityByClassname( iEntity, "func_wall" ) ) != -1 )
	{
		if( GetEntPropString( iEntity, Prop_Data, "m_iName", szZoneName, sizeof( szZoneName ) ) && StrEqual( szZoneName, "sm_zone_" ) )
		{
			HookSingleEntityOutput( iEntity, "OnStartTouch", OnInvisibleWallTouch );
		}
	}
#endif
	
	ServerCommand( "mp_restartgame 1" );
}

public OnInvisibleWallTouch(const String:output[], caller, activator, Float:delay)
{
	PrintToChatAll( "OnInvisibleWallTouch: %i - %i - %s", caller, activator, output );
}

public OnConfigsExecuted( )
{
	ServerCommand( "exec BombGame.cfg" );
	
	PrecacheSound( "error.wav" );
	PrecacheSound( "ui/beep22.wav" );
	PrecacheSound( "training/countdown.wav" );
}

public OnMapStart( )
{
	new iEntity = -1;
	
	// Remove all bomb sites
	while( ( iEntity = FindEntityByClassname( iEntity, "func_bomb_target" ) ) != -1 )
	{
		AcceptEntityInput( iEntity, "kill" );
	}
	
	// Remove all hostage rescue zones
	while( ( iEntity = FindEntityByClassname( iEntity, "func_hostage_rescue" ) ) != -1 )
	{
		AcceptEntityInput( iEntity, "kill" );
	}
	
	// Remove all counter-terrorist spawn points
	while( ( iEntity = FindEntityByClassname( iEntity, "info_player_counterterrorist" ) ) != -1 )
	{
		AcceptEntityInput( iEntity, "kill" );
	}
	
	// Create fake bomb spot
	iEntity = CreateEntityByName( "func_bomb_target" );
	DispatchSpawn( iEntity );
	ActivateEntity( iEntity );
	TeleportEntity( iEntity, Float:{ 0.0, 0.0, -99999.0 }, NULL_VECTOR, NULL_VECTOR );
	SetEntPropVector( iEntity, Prop_Send, "m_vecMins", Float:{ -1.0, -1.0, -1.0 } );
	SetEntPropVector( iEntity, Prop_Send, "m_vecMaxs", Float:{ 1.0, 1.0, 1.0 } );
	SetEntProp( iEntity, Prop_Send, "m_fEffects", 32 );
	
	new String:szMap[ 32 ];
	GetCurrentMap( szMap, sizeof( szMap ) );
	
	PrintToChatAll( "Map: %s", szMap );
	
	if( StrEqual( szMap, "de_nuke", false ) )
	{
		g_bIsNuke = true;
		
		InitializeNuke( );
	}
	else if( StrEqual( szMap, "cs_assault", false ) )
	{
		g_bIsAssault = true;
		
		InitializeAssault( );
	}
	
	g_bMapHasHostages = FindEntityByClassname( -1, "hostage_entity" ) > -1;
}

public OnMapEnd( )
{
	if( g_hTimer != INVALID_HANDLE )
	{
		CloseHandle( g_hTimer );
		
		g_hTimer = INVALID_HANDLE;
	}
	
	if( g_hTimerSound != INVALID_HANDLE )
	{
		CloseHandle( g_hTimerSound );
		
		g_hTimerSound = INVALID_HANDLE;
	}
	
	ResetGame( );
}

public OnClientDisconnect( iClient )
{
	if( iClient == g_iCurrentBomber )
	{
		g_iCurrentBomber = 0;
		
		decl String:szName[ 32 ];
		GetClientName( iClient, szName, sizeof( szName ) );
		
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x02 %s left the game while being the bomber.", szName );
		
		EndRound( );
		
		CS_TerminateRound( 3.0, CSRoundEnd_Draw );
	}
	else
	{
		CheckEnoughPlayers( );
	}
}

public OnClientPutInServer( iClient )
{
	if( g_bGameRunning )
	{
		g_bDeadPlayers[ iClient ] = true;
	}
}

public OnRoundStart( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	g_iLastBomber = 0;
	g_iPreviousBomber = 0;
	
	if( g_bMapHasHostages )
	{
		RemoveHostages( );
	}
	
	if( g_bIsNuke )
	{
		InitializeNuke( );
	}
	
	g_flRoundTime = GetEventFloat( hEvent, "timelimit" );
}

public OnRoundFreezeEnd( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	if( g_hTimer != INVALID_HANDLE )
	{
		CloseHandle( g_hTimer );
	}
	
	if( g_hTimerSound != INVALID_HANDLE )
	{
		CloseHandle( g_hTimerSound );
	}
	
	new iPlayers[ MaxClients ], iAlive, i;
	
	for( i = 1; i <= MaxClients; i++ )
	{
		if( IsClientInGame( i ) && IsPlayerAlive( i ) )
		{
			iPlayers[ iAlive++ ] = i;
		}
	}
	
	g_bStarting = false;
	
	if( iAlive > 1 )
	{
		g_bGameRunning = true;
		
		g_iCurrentBomber = g_iPreviousBomber = iPlayers[ GetRandomInt( 0, iAlive - 1 ) ];
		
		GivePlayerItem( g_iCurrentBomber, "weapon_c4" );
		
		FakeClientCommand( g_iCurrentBomber, "use weapon_c4" );
		
		SetEntPropFloat( g_iCurrentBomber, Prop_Send, "m_flLaggedMovementValue", BOMBER_SPEED );
		SetEntityGravity( g_iCurrentBomber, BOMBER_GRAVITY );
		
		decl String:szName[ 32 ];
		GetClientName( g_iCurrentBomber, szName, sizeof( szName ) );
		
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x02 %s\x01 spawned with the bomb!", szName );
		
		ShowRadar( g_iCurrentBomber );
		
		EmitSoundToClient( g_iCurrentBomber, "ui/beep22.wav" );
		
		g_hTimer = CreateTimer( g_flRoundTime, OnRoundTimerEnd, _, TIMER_FLAG_NO_MAPCHANGE );
		g_hTimerSound = CreateTimer( g_flRoundTime - 3.0, OnRoundSoundTimer, _, TIMER_FLAG_NO_MAPCHANGE );
	}
}

public Action:OnRoundSoundTimer( Handle:hTimer )
{
	g_hTimerSound = INVALID_HANDLE;
	
	EmitSoundToAll( "training/countdown.wav" );
}

public Action:OnRoundTimerEnd( Handle:hTimer )
{
	g_hTimer = INVALID_HANDLE;
	
	new iBomber = g_iCurrentBomber;
	
	g_iCurrentBomber = 0;
	
	if( iBomber > 0 && IsClientInGame( iBomber ) )
	{
		decl String:szName[ 32 ];
		GetClientName( iBomber, szName, sizeof( szName ) );
		
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x02 %s has been left with the bomb!", szName );
		
		g_iLastBomber = iBomber;
		
		g_bDeadPlayers[ iBomber ] = true;
		
		if( IsPlayerAlive( iBomber ) )
		{
			SetEntityGravity( iBomber, 1.0 );
			
			ForcePlayerSuicide( iBomber );
			
			SetEntProp( iBomber, Prop_Data, "m_iFrags", 0 );
		}
	}
	
	g_bStarting = true;
	g_bGameRunning = false;
	
	new iEntity = -1;
	
	while( ( iEntity = FindEntityByClassname( iEntity, "weapon_c4" ) ) != -1 )
	{
		AcceptEntityInput( iEntity, "kill" );
	}
	
	new iPlayers, i, iAlivePlayer, Float:flDelay = 7.0;
	
	for( i = 1; i <= MaxClients; i++ )
	{
		if( IsClientInGame( i ) && IsPlayerAlive( i ) )
		{
			iAlivePlayer = i;
			iPlayers++;
			
			CS_SetClientContributionScore( i, CS_GetClientContributionScore( i ) + 1 );
		}
	}
	
	if( iPlayers == 1 )
	{
		ResetGame( );
		
		decl String:szName[ 32 ];
		GetClientName( iAlivePlayer, szName, sizeof( szName ) );
		
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x04 %s has won the bomb game!", szName );
		
		CS_SetMVPCount( iAlivePlayer, CS_GetMVPCount( iAlivePlayer ) + 1 );
		
		new Handle:hLeader = CreateEvent( "round_mvp" );
		SetEventInt( hLeader, "userid", GetClientUserId( iAlivePlayer ) );
		FireEvent( hLeader );
		
		flDelay = 10.0;
	}
	
	if( hTimer != INVALID_HANDLE )
	{
		CS_TerminateRound( flDelay, CSRoundEnd_TargetBombed );
	}
}

public OnPlayerSpawn( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	new iClient = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
	
	if( g_bDeadPlayers[ iClient ] )
	{
		PrintToChat( iClient, " \x01\x0B\x04[BombGame]\x01 You can't play this round!" );
		
		ForcePlayerSuicide( iClient );
		
		SetEntProp( iClient, Prop_Data, "m_iFrags", 0 );
		SetEntProp( iClient, Prop_Data, "m_iDeaths", GetEntProp( iClient, Prop_Data, "m_iDeaths" ) - 1 );
		
		return;
	}
	
	CreateTimer( 0.0, OnTimerHideRadar, GetClientSerial( iClient ), TIMER_FLAG_NO_MAPCHANGE );
	
	//SetEntProp( iClient, Prop_Data, "m_iFrags", 0 );
	SetEntProp( iClient, Prop_Data, "m_takedamage", 0, 1 );
	
	if( !g_bStarting && !g_bGameRunning && IsEnoughPlayersToPlay( ) )
	{
		g_bStarting = true;
		
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x01 The game is starting..." );
		
		CS_TerminateRound( 2.0, CSRoundEnd_CTWin );
	}
}

public Action:OnTimerHideRadar( Handle:hTimer, any:iSerial )
{
	new iClient = GetClientFromSerial( iSerial );
	
	if( iClient && IsPlayerAlive( iClient ) )
	{
		HideRadar( iClient );
	}
}

public Action:OnPlayerPreDeath( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	new iClient = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
	
	if( g_iLastBomber > 0 && g_iLastBomber == iClient )
	{
		PrintToChatAll( "Setting death weapon to c4" );
		
		SetEventString( hEvent, "weapon", "hegrenade" );
		
		if( g_iPreviousBomber > 0 && IsClientInGame( g_iPreviousBomber ) )
		{
			SetEventInt( hEvent, "attacker", GetClientUserId( g_iPreviousBomber ) );
		}
		
		return Plugin_Continue;
	}
	else if( g_bDeadPlayers[ iClient ] )
	{
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public OnPlayerDeath( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	new iClient = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
	
	SetEntProp( iClient, Prop_Data, "m_iFrags", 0 );
	
	ShowRadar( iClient );
	
	if( iClient == g_iCurrentBomber )
	{
		g_iCurrentBomber = 0;
		g_iLastBomber = iClient;
		
		g_bDeadPlayers[ iClient ] = true;
		
		SetEntityGravity( iClient, 1.0 );
		
		decl String:szName[ 32 ];
		GetClientName( iClient, szName, sizeof( szName ) );
		
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x02 %s suicided while being the bomber.", szName );
		
		EndRound( );
		
		CS_TerminateRound( 3.0, CSRoundEnd_Draw );
	}
	else
	{
		CheckEnoughPlayers( );
		
		if( g_bGameRunning )
		{
			g_bDeadPlayers[ iClient ] = true;
		}
	}
	
	new iRagdoll = GetEntPropEnt( iClient, Prop_Send, "m_hRagdoll" );
	
	if( iRagdoll > 0 )
	{
		if( g_iLastBomber == iClient )
		{
			g_iLastBomber = 0;
			
			new iEntity = CreateEntityByName( "env_entity_dissolver" );
			
			if( iEntity > 0 )
			{
				new String:szTargetName[ 16 ];
				Format( szTargetName, sizeof( szTargetName ), "dissolve_%i", iClient );
				
				DispatchKeyValue( iRagdoll, "targetname", szTargetName );
				DispatchKeyValue( iEntity, "target", szTargetName );
				DispatchKeyValue( iEntity, "dissolvetype", "1" );
				DispatchKeyValue( iEntity, "magnitude", "5.0" );
				AcceptEntityInput( iEntity, "Dissolve" );
				AcceptEntityInput( iEntity, "kill" );
			}
			else
			{
				AcceptEntityInput( iRagdoll, "kill" );
			}
		}
		else
		{
			AcceptEntityInput( iRagdoll, "kill" );
		}
	}
	
	ClientCommand( iClient, "playgamesound Music.StopAllMusic" );
}

public OnBombPickup( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	if( !g_bGameRunning || g_bStarting )
	{
		return;
	}
	
	new iClient = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
	
	if( g_iCurrentBomber != iClient )
	{
		if( g_iCurrentBomber > 0 && IsPlayerAlive( g_iCurrentBomber ) )
		{
			SetEntPropFloat( g_iCurrentBomber, Prop_Send, "m_flLaggedMovementValue", 1.0 );
			SetEntityGravity( g_iCurrentBomber, 1.0 );
			
			HideRadar( g_iCurrentBomber );
		}
		
		g_iPreviousBomber = g_iCurrentBomber;
		g_iCurrentBomber = iClient;
		
		SetEntPropFloat( iClient, Prop_Send, "m_flLaggedMovementValue", BOMBER_SPEED );
		SetEntityGravity( iClient, BOMBER_GRAVITY );
		
		ShowRadar( iClient );
		
		decl String:szName[ 32 ];
		GetClientName( iClient, szName, sizeof( szName ) );
		
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x02 %s\x01 has picked up the bomb!", szName );
		
		EmitSoundToAll( "error.wav", iClient );
	}
}

public Action:OnJoinTeamFailed( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	new iClient = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
	
	if( IsClientInGame( iClient ) && GetClientTeam( iClient ) != CS_TEAM_T )
	{
		CS_SwitchTeam( iClient, CS_TEAM_T );
		
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action:OnNormalSound( clients[ 64 ], &numClients, String:sample[ PLATFORM_MAX_PATH ], &entity, &channel, &Float:volume, &level, &pitch, &flags )
{
	new dummy;
	
	return GetTrieValue( g_hBlockedSounds, sample, dummy ) ? Plugin_Handled : Plugin_Continue;
}

EndRound( )
{
	if( g_hTimer != INVALID_HANDLE )
	{
		CloseHandle( g_hTimer );
		
		g_hTimer = INVALID_HANDLE;
	}
	
	if( g_hTimerSound != INVALID_HANDLE )
	{
		CloseHandle( g_hTimerSound );
		
		g_hTimerSound = INVALID_HANDLE;
	}
	
	OnRoundTimerEnd( INVALID_HANDLE );
}

IsEnoughPlayersToPlay( )
{
	new iPlayers, i;
	
	for( i = 1; i <= MaxClients; i++ )
	{
		if( IsClientInGame( i ) && IsPlayerAlive( i ) )
		{
			iPlayers++;
			
			if( iPlayers > 1 )
			{
				return true;
			}
		}
	}
	
	return false;
}

ResetGame( )
{
	for( new i = 1; i <= MaxClients; i++ )
	{
		g_bDeadPlayers[ i ] = false;
	}
	
	if( g_iCurrentBomber > 0 && IsPlayerAlive( g_iCurrentBomber ) )
	{
		SetEntityGravity( g_iCurrentBomber, 1.0 );
	}
	
	g_bStarting = false;
	g_bGameRunning = false;
	g_iCurrentBomber = 0;
	g_iPreviousBomber = 0;
}

CheckEnoughPlayers( )
{
	if( !g_bGameRunning )
	{
		return;
	}
	
	new iAlive, iLastPlayer, i;
	
	for( i = 1; i <= MaxClients; i++ )
	{
		if( IsClientInGame( i ) && IsPlayerAlive( i ) )
		{
			iAlive++;
			
			if( iAlive > 1 )
			{
				return;
			}
			
			iLastPlayer = i;
		}
	}
	
	if( iAlive == 0 )
	{
		ResetGame( );
		
		return;
	}
	
	if( iLastPlayer == g_iCurrentBomber )
	{
		decl String:szName[ 32 ];
		GetClientName( iLastPlayer, szName, sizeof( szName ) );
		
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x02 %s\x01 was the last person alive, everyone else left or died, resetting the game.", szName );
	}
	else
	{
		PrintToChatAll( "What happened here? last bomber: %i - current bomber: %i", g_iLastBomber, g_iCurrentBomber );
	}
	
	ResetGame( );
	
	CS_TerminateRound( 3.0, CSRoundEnd_Draw );
}

HideRadar( iClient )
{
	SetEntProp( iClient, Prop_Send, "m_iHideHUD", GetEntProp( iClient, Prop_Send, "m_iHideHUD" ) | HIDEHUD_RADAR );
}

ShowRadar( iClient )
{
	SetEntProp( iClient, Prop_Send, "m_iHideHUD", GetEntProp( iClient, Prop_Send, "m_iHideHUD" ) & ~HIDEHUD_RADAR );
}

RemoveHostages( )
{
	new iEntity = -1;
	
	while( ( iEntity = FindEntityByClassname( iEntity, "hostage_entity" ) ) != -1 )
	{
		AcceptEntityInput( iEntity, "kill" );
	}
}

InitializeNuke( )
{
	new iEntity = -1, String:szModel[ 42 ];
	
	// Remove all doors
	while( ( iEntity = FindEntityByClassname( iEntity, "prop_door_rotating" ) ) != -1 )
	{
		if( GetEntPropString( iEntity, Prop_Data, "m_ModelName", szModel, sizeof( szModel ) ) && StrEqual( szModel, "models/props_downtown/metal_door_112.mdl" ) )
		{
			AcceptEntityInput( iEntity, "kill" );
		}
	}
}

InitializeAssault( )
{
	new iEntity = -1, String:szModel[ 43 ];
	
	// Remove all ladders
	while( ( iEntity = FindEntityByClassname( iEntity, "prop_static" ) ) != -1 )
	{
		GetEntPropString( iEntity, Prop_Data, "m_ModelName", szModel, sizeof( szModel ) );
		
		PrintToChatAll( "Model: %s", szModel );
		
		if( true
		&& ( StrEqual( szModel, "models/props_equipment/metalladder002.mdl" ) || StrEqual( szModel, "models/props/cs_assault/Ladder_tall.mdl" ) ) )
		{
			AcceptEntityInput( iEntity, "kill" );
		}
	}
	
	while( ( iEntity = FindEntityByClassname( iEntity, "func_ladder" ) ) != -1 )
	{
		PrintToChatAll( "Found ladder: %i", iEntity );
	}
}
