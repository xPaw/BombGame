#include < sourcemod >
#include < sdktools >
#include < cstrike >

#define HIDEHUD_RADAR  ( 1 << 12 )

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
new Float:g_flRoundTime;
new Handle:g_hTimer = INVALID_HANDLE;
new Handle:g_hTimerSound = INVALID_HANDLE;
new Handle:g_hTimerStuck = INVALID_HANDLE;
new Handle:g_hBlockedSounds;

new g_iStatsBombDropped;
new g_iStatsBombSwitched;

new g_iExplosionSprite;
new g_iSmokeSprite;
new g_iPlayerModel;
new g_iPreviousPlayerModel;

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
	
	AddNormalSoundHook( OnNormalSound );
	
	RegConsoleCmd( "sm_help", OnCommandHelp, "Display helpful message about the bomb game" );
	RegConsoleCmd( "sm_stuck", OnCommandStuck, "Get the bomb back if you're the bomber" );
	RegConsoleCmd( "sm_start", OnCommandStart, "Start the game" );
	
	HookEvent( "round_start",      OnRoundStart );
	HookEvent( "round_freeze_end", OnRoundFreezeEnd );
	HookEvent( "bomb_pickup",      OnBombPickup );
	HookEvent( "bomb_dropped",     OnBombDropped );
	HookEvent( "player_spawn",     OnPlayerSpawn );
	HookEvent( "player_death",     OnPlayerDeath );
	HookEvent( "player_death",     OnPlayerPreDeath, EventHookMode_Pre );
	HookEvent( "jointeam_failed",  OnJoinTeamFailed, EventHookMode_Pre );
	
	//ServerCommand( "mp_restartgame 1" );
}

public OnBombDropped( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	g_iStatsBombDropped++;
}

public OnConfigsExecuted( )
{
	ServerCommand( "exec BombGame.cfg" );
	
	PrecacheSound( "buttons/blip2.wav" );
	PrecacheSound( "ui/beep22.wav" );
	PrecacheSound( "ui/arm_bomb.wav" );
	PrecacheSound( "items/ammo_pickup.wav" );
	PrecacheSound( "training/countdown.wav" );
	PrecacheSound( "weapons/hegrenade/explode3.wav" );
	
	g_iPlayerModel = PrecacheModel( "models/player/tm_anarchist_variantd.mdl" );
	
	g_iExplosionSprite = PrecacheModel( "sprites/blueglow1.vmt" );
	g_iSmokeSprite = PrecacheModel( "sprites/steam1.vmt" );
}

public OnMapStart( )
{
	new iEntity = -1;
	
	// Remove all bomb sites
	while( ( iEntity = FindEntityByClassname( iEntity, "func_bomb_target" ) ) != -1 )
	{
		AcceptEntityInput( iEntity, "kill" );
	}
	
	iEntity = -1;
	
	// Remove all hostage rescue zones
	while( ( iEntity = FindEntityByClassname( iEntity, "func_hostage_rescue" ) ) != -1 )
	{
		AcceptEntityInput( iEntity, "kill" );
	}
	
	iEntity = -1;
	
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
	
	g_bIsNuke = StrEqual( szMap, "de_nuke", false );
	g_bMapHasHostages = FindEntityByClassname( -1, "hostage_entity" ) > -1;
	
	if( g_bIsNuke )
	{
		InitializeNuke( );
	}
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
		CheckEnoughPlayers( iClient );
	}
}

public OnClientPutInServer( iClient )
{
	if( g_bGameRunning )
	{
		g_bDeadPlayers[ iClient ] = true;
	}
}

public Action:OnCommandHelp( iClient, iArguments )
{
	ReplyToCommand( iClient, " \x01\x0B\x04[BombGame]\x01 It's simple, just make sure you're not the last person to hold the bomb when the time runs out." );
	ReplyToCommand( iClient, " \x01\x0B\x04[BombGame]\x01 Say\x02 /stuck\x01 if your bomb is inaccessible." );
	
	return Plugin_Handled;
}

public Action:OnCommandStuck( iClient, iArguments )
{
	if( iClient != g_iCurrentBomber )
	{
		ReplyToCommand( iClient, " \x01\x0B\x04[BombGame]\x01 You're not the bomber." );
	}
	else if( IsPlayerAlive( iClient ) )
	{
		if( GetPlayerWeaponSlot( iClient, CS_SLOT_C4 ) == -1 )
		{
			g_hTimerStuck = CreateTimer( 5.0, OnTimerGiveBomb, GetClientSerial( iClient ), TIMER_FLAG_NO_MAPCHANGE );
			
			ReplyToCommand( iClient, " \x01\x0B\x04[BombGame]\x01 You will get your bomb in 5 seconds." );
		}
		else
		{
			ReplyToCommand( iClient, " \x01\x0B\x04[BombGame]\x01 Couldn't find any bomb on the floor." );
		}
	}
	
	return Plugin_Handled;
}

public Action:OnCommandStart( iClient, iArguments )
{
	if( !g_bStarting && !g_bGameRunning && IsEnoughPlayersToPlay( ) )
	{
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x01 Starting the game by player request." );
		
		g_bStarting = true;
		
		CS_TerminateRound( 5.0, CSRoundEnd_Draw );
	}
	else
	{
		ReplyToCommand( iClient, " \x01\x0B\x04[BombGame]\x01 Can't start the game now." );
	}
	
	return Plugin_Handled;
}

public Action:OnTimerGiveBomb( Handle:hTimer, any:iSerial )
{
	g_hTimerStuck = INVALID_HANDLE;
	
	new iClient = GetClientFromSerial( iSerial );
	
	if( iClient && iClient == g_iCurrentBomber && IsPlayerAlive( iClient ) && GetPlayerWeaponSlot( iClient, CS_SLOT_C4 ) == -1 )
	{
		RemoveBomb( );
		
		GivePlayerItem( g_iCurrentBomber, "weapon_c4" );
		
		ReplyToCommand( iClient, " \x01\x0B\x04[BombGame]\x01 Bomb given back!" );
	}
}

public OnRoundStart( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	CS_SetTeamScore(CS_TEAM_CT, 13);
	SetTeamScore(CS_TEAM_CT, 13);
	
	CS_SetTeamScore(CS_TEAM_T, 37);
	SetTeamScore(CS_TEAM_T, 37);
	
	g_iLastBomber = 0;
	g_iPreviousBomber = 0;
	g_iStatsBombDropped = 0;
	g_iStatsBombSwitched = 0;
	
	if( g_bMapHasHostages )
	{
		RemoveHostages( );
	}
	
	if( g_bIsNuke )
	{
		InitializeNuke( );
	}
	
	g_flRoundTime = GetEventFloat( hEvent, "timelimit" );
	
	if( !g_bStarting && !g_bGameRunning && IsEnoughPlayersToPlay( ) )
	{
		g_bStarting = true;
		
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x01 The game is starting...\x01 Say\x02 /help\x01 for more information. Say\x02 /stuck\x01 if your bomb is inaccessible." );
	}
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
		
		g_hTimerSound = INVALID_HANDLE;
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
		
		decl String:szName[ 32 ];
		GetClientName( g_iCurrentBomber, szName, sizeof( szName ) );
		
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x02 %s\x01 spawned with the bomb!", szName );
		
		MakeBomber( g_iCurrentBomber );
		
		EmitSoundToClient( g_iCurrentBomber, "ui/beep22.wav" );
		
		g_hTimer = CreateTimer( g_flRoundTime, OnRoundTimerEnd, _, TIMER_FLAG_NO_MAPCHANGE );
		g_hTimerSound = CreateTimer( g_flRoundTime - 4.0, OnRoundSoundTimer, _, TIMER_FLAG_NO_MAPCHANGE );
	}
	else
	{
		g_hTimer = CreateTimer( g_flRoundTime, OnRoundTimerEndWithNoGameRunning, _, TIMER_FLAG_NO_MAPCHANGE );
	}
	
	g_flRoundTime = 0.0;
}

public Action:OnRoundSoundTimer( Handle:hTimer )
{
	g_hTimerSound = CreateTimer( 3.0, OnRoundArmSoundTimer, _, TIMER_FLAG_NO_MAPCHANGE );
	
	EmitSoundToAll( "training/countdown.wav" );
}

public Action:OnRoundArmSoundTimer( Handle:hTimer )
{
	g_hTimerSound = INVALID_HANDLE;
	
	EmitSoundToAll( "ui/arm_bomb.wav" );
}

public Action:OnRoundTimerEndWithNoGameRunning( Handle:hTimer )
{
	g_hTimer = INVALID_HANDLE;
	
	CS_TerminateRound( 5.0, CSRoundEnd_Draw );
	
	PrintToChatAll( " \x01\x0B\x04[BombGame]\x01 Ending round..." );
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
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x01 Bomb was dropped\x04 %i\x01 times, bomber switched\x04 %i\x01 times during this round.", g_iStatsBombDropped, g_iStatsBombSwitched );
		
		g_iLastBomber = iBomber;
		
		g_bDeadPlayers[ iBomber ] = true;
		
		if( IsPlayerAlive( iBomber ) )
		{
			ForcePlayerSuicide( iBomber );
			
			SetEntProp( iBomber, Prop_Data, "m_iFrags", 0 );
			
			new Float:vPosition[ 3 ];
			GetClientEyePosition( iBomber, vPosition );
			
			TE_SetupExplosion( vPosition, g_iExplosionSprite, 5.0, 1, 0, 100, 600, _, '-' );
			TE_SendToAll();
			
			TE_SetupSmoke( vPosition, g_iSmokeSprite, 10.0, 3 );
			TE_SendToAll();
			
			EmitAmbientSound( "weapons/hegrenade/explode3.wav", vPosition, iBomber, SNDLEVEL_RAIDSIREN );
		}
	}
	
	g_bStarting = true;
	g_bGameRunning = false;
	
	RemoveBomb( );
	
	new iPlayers, i, iAlivePlayer, Float:flDelay = 4.0;
	
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
		
		flDelay = 6.5;
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
		CreateTimer( 0.1, OnTimerCheckAlive, GetClientSerial( iClient ), TIMER_FLAG_NO_MAPCHANGE );
		
		SetEntProp( iClient, Prop_Data, "m_iFrags", 0 );
		SetEntProp( iClient, Prop_Data, "m_iDeaths", GetEntProp( iClient, Prop_Data, "m_iDeaths" ) - 1 );
		
		return;
	}
	
	CreateTimer( 0.0, OnTimerHideRadar, GetClientSerial( iClient ), TIMER_FLAG_NO_MAPCHANGE );
	
	//SetEntProp( iClient, Prop_Data, "m_iFrags", 0 );
	SetEntProp( iClient, Prop_Data, "m_takedamage", 0, 1 );
}

public Action:OnTimerCheckAlive( Handle:hTimer, any:iSerial )
{
	new iClient = GetClientFromSerial( iSerial );
	
	if( iClient && IsPlayerAlive( iClient ) )
	{
		PrintToChatAll( "%i managed to stay alive, killing again...", iClient );
		ForcePlayerSuicide( iClient );
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
	
	if( g_iLastBomber == iClient )
	{
		SetEventString( hEvent, "weapon", "hegrenade" );
		
		if( g_iPreviousBomber > 0 && IsClientInGame( g_iPreviousBomber ) )
		{
			SetEventInt( hEvent, "attacker", GetClientUserId( g_iPreviousBomber ) );
		}
		
		return Plugin_Changed;
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
		//SetEntProp( g_iCurrentBomber, Prop_Data, "m_nModelIndex", g_iPreviousPlayerModel, 2 );
		
		g_iCurrentBomber = 0;
		g_iLastBomber = iClient;
		
		g_bDeadPlayers[ iClient ] = true;
		
		decl String:szName[ 32 ];
		GetClientName( iClient, szName, sizeof( szName ) );
		
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x02 %s suicided while being the bomber.", szName );
		
		EndRound( );
		
		CS_TerminateRound( 3.0, CSRoundEnd_Draw );
	}
	else
	{
		if( g_iLastBomber != iClient )
		{
			CheckEnoughPlayers( iClient );
		}
		
		if( g_bGameRunning )
		{
			g_bDeadPlayers[ iClient ] = true;
		}
	}
	
	new iRagdoll = GetEntPropEnt( iClient, Prop_Send, "m_hRagdoll" );
	
	if( iRagdoll > 0 )
	{
		AcceptEntityInput( iRagdoll, "kill" );
	}
	
	ClientCommand( iClient, "playgamesound Music.StopAllMusic" );
}

public OnBombPickup( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	if( !g_bGameRunning || g_bStarting )
	{
		return;
	}
	
	if( g_hTimerStuck != INVALID_HANDLE )
	{
		CloseHandle( g_hTimerStuck );
		
		g_hTimerStuck = INVALID_HANDLE;
	}
	
	new iClient = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
	
	if( g_iCurrentBomber != iClient )
	{
		if( g_iCurrentBomber > 0 && IsPlayerAlive( g_iCurrentBomber ) )
		{
			HideRadar( g_iCurrentBomber );
			
			SetEntProp( g_iCurrentBomber, Prop_Data, "m_nModelIndex", g_iPreviousPlayerModel, 2 );
		}
		
		g_iPreviousBomber = g_iCurrentBomber;
		g_iCurrentBomber = iClient;
		
		MakeBomber( iClient );
		
		decl String:szName[ 32 ];
		GetClientName( iClient, szName, sizeof( szName ) );
		
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x02 %s\x01 has picked up the bomb!", szName );
		
		EmitSoundToAll( "buttons/blip2.wav", iClient );
		
		g_iStatsBombSwitched++;
	}
	else
	{
		EmitSoundToAll( "items/ammo_pickup.wav", iClient );
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

MakeBomber( iClient )
{
	ShowRadar( iClient );
	
	g_iPreviousPlayerModel = GetEntProp( iClient, Prop_Data, "m_nModelIndex", 2 );
	
	SetEntProp( iClient, Prop_Data, "m_nModelIndex", g_iPlayerModel, 2 );
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
	
	g_bStarting = false;
	g_bGameRunning = false;
	g_iCurrentBomber = 0;
	g_iPreviousBomber = 0;
}

CheckEnoughPlayers( iClient )
{
	if( !g_bGameRunning )
	{
		return;
	}
	
	new iAlive, iLastPlayer, i;
	
	for( i = 1; i <= MaxClients; i++ )
	{
		if( i != iClient && IsClientInGame( i ) && IsPlayerAlive( i ) )
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
		
		LogError( "Abnormal!! What happened here? last bomber: %i - current bomber: %i", g_iLastBomber, g_iCurrentBomber );
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

RemoveBomb( )
{
	new iEntity = -1;
	
	while( ( iEntity = FindEntityByClassname( iEntity, "weapon_c4" ) ) != -1 )
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
