#pragma semicolon 1

#include < sourcemod >
#include < sdktools >
#include < cstrike >

#define IS_EXPOSURE_MODE 0 // Do this in a cvar
#define EXPOSURE_TIME 25
#define MAX_GRACE_JOIN_TIME 1000.0 // We override game's cvar

#define HIDEHUD_RADAR  ( 1 << 12 )

public Plugin:myinfo =
{
	name = "BombGame",
	author = "xPaw",
	description = "Good ol' bomb game.",
	version = "1.0",
	url = "http://xpaw.ru"
};

new g_iBombHeldTimer[ MAXPLAYERS ];
new g_bDeadPlayers[ MAXPLAYERS ];
new g_bStarting;
new g_bGameRunning;
new g_iFakeClient;
new g_iLastBomber;
new g_iCurrentBomber;
new g_iPreviousBomber;
new bool:g_bIgnoreFirstRoundStart;
new bool:g_bMapHasHostages;
new bool:g_bIsNuke;
new Float:g_flRoundTime;
new Handle:g_hTimerSound = INVALID_HANDLE;
new Handle:g_hTimerStuck = INVALID_HANDLE;
new Handle:g_hBlockedSounds;
new Handle:g_hCvarGraceJoinTime;

new g_iStatsBombDropped;
new g_iStatsBombSwitched;

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
	SetTrieValue( g_hBlockedSounds, "weapons/knife/knife_stab.wav", 1 );
	SetTrieValue( g_hBlockedSounds, "weapons/knife/knife_hit1.wav", 1 );
	SetTrieValue( g_hBlockedSounds, "weapons/knife/knife_hit2.wav", 1 );
	SetTrieValue( g_hBlockedSounds, "weapons/knife/knife_hit3.wav", 1 );
	SetTrieValue( g_hBlockedSounds, "weapons/knife/knife_hit4.wav", 1 );
	// knife_hitwall1-4
	
	AddNormalSoundHook( OnNormalSound );
	
	AddCommandListener( OnCommandCallVote, "callvote" );
	AddCommandListener( OnCommandJoinClass, "joinclass" );
	
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
	HookEvent( "round_announce_match_start", OnRoundAnnounceMatchStart, EventHookMode_Pre );
	HookEvent( "cs_win_panel_round", OnWinPanelRound, EventHookMode_Pre );
	
	HookConVarChange( FindConVar( "mp_restartgame" ), OnRestartGameCvar );
	
	g_hCvarGraceJoinTime = FindConVar( "mp_join_grace_time" );
	
	SetConVarBounds( g_hCvarGraceJoinTime, ConVarBound_Upper, true, MAX_GRACE_JOIN_TIME );
}

public OnWinPanelRound( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	decl String:szName[ 32 ];
	GetEventString( hEvent, "funfact_token", szName, sizeof( szName ) );
	
	PrintToChatAll( "DEBUG: funfact_token: %s, funfact_player: %i, funfact_data1: %i, funfact_data2: %i, funfact_data3: %i",
		szName,
		GetEventInt( hEvent, "funfact_player" ),
		GetEventInt( hEvent, "funfact_data1" ),
		GetEventInt( hEvent, "funfact_data2" ),
		GetEventInt( hEvent, "funfact_data3" )
	);
}

public OnPluginEnd( )
{
	if( g_iFakeClient )
	{
		KickClient( g_iFakeClient, "Plugin end" );
	}
}

public OnConfigsExecuted( )
{
	ServerCommand( "exec BombGame.cfg" );
	
	PrecacheSound( "player/geiger1.wav" );
	PrecacheSound( "player/geiger2.wav" );
	PrecacheSound( "player/geiger3.wav" );
	PrecacheSound( "buttons/blip2.wav" );
	PrecacheSound( "ui/beep22.wav" );
	PrecacheSound( "ui/arm_bomb.wav" );
	PrecacheSound( "items/ammo_pickup.wav" );
	PrecacheSound( "training/countdown.wav" );
	PrecacheSound( "weapons/hegrenade/explode3.wav" );
	PrecacheModel( "sprites/zerogxplode.spr" );
	
	g_iPlayerModel = PrecacheModel( "models/player/tm_anarchist_variantd.mdl" );
	
#if IS_EXPOSURE_MODE
	SetConVarFloat( FindConVar( "mp_roundtime" ), 10.0 );
#endif
	
	SetConVarFloat( g_hCvarGraceJoinTime, MAX_GRACE_JOIN_TIME );
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
	
	// Edit info_map_parameters
	iEntity = FindEntityByClassname( iEntity, "info_map_parameters" );
	
	if( iEntity == -1 )
	{
		iEntity = CreateEntityByName( "info_map_parameters" );
	}
	
	if( iEntity != -1 )
	{
		DispatchKeyValue( iEntity, "buying", "0" );
		DispatchKeyValue( iEntity, "petpopulation", "0" );
		DispatchSpawn( iEntity );
	}
	
	// Create fake bomb spot
	iEntity = CreateEntityByName( "func_bomb_target" );
	
	if( iEntity != -1 )
	{
		DispatchKeyValue( iEntity, "targetname", "B" );
		DispatchSpawn( iEntity );
		ActivateEntity( iEntity );
		TeleportEntity( iEntity, Float:{ 0.0, 0.0, -99999.0 }, NULL_VECTOR, NULL_VECTOR );
		SetEntPropVector( iEntity, Prop_Send, "m_vecMins", Float:{ -1.0, -1.0, -1.0 } );
		SetEntPropVector( iEntity, Prop_Send, "m_vecMaxs", Float:{ 1.0, 1.0, 1.0 } );
		SetEntProp( iEntity, Prop_Send, "m_fEffects", 32 );
	}
	
	g_bIgnoreFirstRoundStart = true;
	
	new String:szMap[ 32 ];
	GetCurrentMap( szMap, sizeof( szMap ) );
	
	g_bIsNuke = StrEqual( szMap, "de_nuke", false );
	g_bMapHasHostages = FindEntityByClassname( -1, "hostage_entity" ) > -1;
	
	if( g_bIsNuke )
	{
		InitializeNuke( );
	}
	
	CreateTimer( 1.0, OnTimerCreateBot, _, TIMER_FLAG_NO_MAPCHANGE );
	
	SetConVarFloat( g_hCvarGraceJoinTime, MAX_GRACE_JOIN_TIME );
}

public Action:OnTimerCreateBot( Handle:hTimer )
{
	if( !g_iFakeClient || !IsClientInGame( g_iFakeClient ) )
	{
		g_iFakeClient = CreateFakeClient( "BombGame Coach" );
		
		if( g_iFakeClient > 0 )
		{
			CS_SwitchTeam( g_iFakeClient, CS_TEAM_CT );
		}
		else
		{
			LogError( "Failed to create a fake player" );
		}
	}
}

public OnMapEnd( )
{
	ResetGame( );
	
	if( g_iFakeClient )
	{
		KickClient( g_iFakeClient, "Map end" );
	}
}

public OnClientDisconnect( iClient )
{
	if( g_iFakeClient == iClient )
	{
		g_iFakeClient = 0;
		
		return;
	}
	
	if( iClient == g_iCurrentBomber )
	{
		g_iCurrentBomber = 0;
		
		decl String:szName[ 32 ];
		GetClientName( iClient, szName, sizeof( szName ) );
		
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x02 %s left the game while being the bomber.", szName );
		
		EndRound( );
	}
	else
	{
		CheckEnoughPlayers( iClient );
	}
}

public OnClientPutInServer( iClient )
{
	if( g_bGameRunning || g_bStarting )
	{
		g_bDeadPlayers[ iClient ] = true;
	}
}

public Action:OnCommandCallVote( iClient, const String:szCommand[ ], iArguments )
{
	decl String:szIssue[ 16 ];
	GetCmdArg( 1, szIssue, sizeof( szIssue ) );
	
	if( StrEqual( szIssue, "ScrambleTeams", false ) || StrEqual( szIssue, "SwapTeams", false ) )
	{
		PrintToChat( iClient, " \x01\x0B\x04[BombGame]\x02 Scramble and switch teams votes are disabled." );
		
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action:OnCommandJoinClass( iClient, const String:szCommand[ ], iArguments )
{
	if( iClient > 0 && ( g_bGameRunning || g_bStarting ) )
	{
		PrintToChatAll( "DEBUG: %i joined team, but we forced them to be dead because game is in progress!!", iClient );
		
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
		if( g_hTimerStuck != INVALID_HANDLE )
		{
			ReplyToCommand( iClient, " \x01\x0B\x04[BombGame]\x01 You're already waiting for the bomb." );
		}
		else if( GetPlayerWeaponSlot( iClient, CS_SLOT_C4 ) == -1 )
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
	if( g_bStarting || g_bGameRunning )
	{
		ReplyToCommand( iClient, " \x01\x0B\x04[BombGame]\x01 The game is already running." );
	}
	else if( !IsEnoughPlayersToPlay( ) )
	{
		ReplyToCommand( iClient, " \x01\x0B\x04[BombGame]\x01 Not enough players to start the game." );
	}
	else
	{
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x01 Starting the game by player request." );
		
		g_bStarting = true;
		g_bIgnoreFirstRoundStart = false;
		
		CS_TerminateRound( 0.5, CSRoundEnd_Draw );
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

public Action:OnRoundAnnounceMatchStart( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	return Plugin_Handled;
}

public OnRoundStart( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	CS_SetTeamScore( CS_TEAM_CT, 13 );
	SetTeamScore( CS_TEAM_CT, 13 );
	
	CS_SetTeamScore( CS_TEAM_T, 37 );
	SetTeamScore( CS_TEAM_T, 37 );
	
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
	
	if( g_bIgnoreFirstRoundStart )
	{
		g_bIgnoreFirstRoundStart = false;
		
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x01 If you want to start the game manually, say\x02 /start\x01" );
	}
	else if( !g_bStarting && !g_bGameRunning && IsEnoughPlayersToPlay( ) )
	{
		g_bStarting = true;
		
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x01 The game is starting...\x01 Say\x02 /help\x01 for more information. Say\x02 /stuck\x01 if your bomb is inaccessible." );
	}
}

public OnRoundFreezeEnd( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	if( !g_bStarting )
	{
		PrintToChatAll( "DEBUG: g_bStarting is not true, not starting bombgame..." ); // TODO
		
		SetConVarFloat( g_hCvarGraceJoinTime, MAX_GRACE_JOIN_TIME );
		
		return;
	}
	
	g_bStarting = false;
	
	SetConVarFloat( g_hCvarGraceJoinTime, 0.0 ); // We don't want to allow late joins
	
	new iPlayers[ MaxClients ], iAlive, iDead, i;
	
	for( i = 1; i <= MaxClients; i++ )
	{
		if( IsPlayerBombGamer( i ) )
		{
			iPlayers[ iAlive++ ] = i;
		}
		
		if( g_bDeadPlayers[ i ] )
		{
			iDead++;
		}
	}
	
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
		
#if IS_EXPOSURE_MODE
		g_hTimerSound = CreateTimer( 1.0, OnTimerIncreaseExposure, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE );
#else
		g_hTimerSound = CreateTimer( g_flRoundTime - 4.0, OnRoundSoundTimer, _, TIMER_FLAG_NO_MAPCHANGE );
#endif
		
		if( iAlive == 2 && iDead > 0 )
		{
			new Handle:hAnnounce = CreateEvent( "round_announce_final" );
			FireEvent( hAnnounce );
		}
	}
	else if( iDead > 0 )
	{
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x02 Something magical happened, resetting the game." );
		
		ResetGame( );
		
		SetConVarInt( FindConVar( "mp_restartgame" ), 1 );
	}
	
	g_flRoundTime = 0.0;
}

public Action:OnTimerIncreaseExposure( Handle:hTimer )
{
	if( !g_iCurrentBomber )
	{
		// TODO
		PrintToChatAll( "DEBUG: OnTimerIncreaseExposure fired but there is no bomber" );
		LogError( "OnTimerIncreaseExposure fired but there is no bomber" );
		
		return;
	}
	
	new iTime = ++g_iBombHeldTimer[ g_iCurrentBomber ];
	
	if( iTime >= EXPOSURE_TIME )
	{
		SetEntProp( g_iCurrentBomber, Prop_Send, "m_iHealth", 0 );
		
		CS_TerminateRound( 5.0, CSRoundEnd_TargetBombed );
	}
	else
	{
		if( iTime == EXPOSURE_TIME - 1 )
		{
			EmitSoundToAll( "ui/arm_bomb.wav", g_iCurrentBomber );
		}
		else if( iTime > EXPOSURE_TIME - 5 )
		{
			EmitSoundToAll( "player/geiger3.wav", g_iCurrentBomber );
		}
		else if( iTime > EXPOSURE_TIME / 2 )
		{
			EmitSoundToClient( g_iCurrentBomber, "player/geiger2.wav", g_iCurrentBomber );
		}
		else
		{
			EmitSoundToClient( g_iCurrentBomber, "player/geiger1.wav", g_iCurrentBomber );
		}
		
		SetEntProp( g_iCurrentBomber, Prop_Send, "m_iHealth", RoundToFloor( 100.0 - ( 100.0 / EXPOSURE_TIME * iTime ) ) );
	}
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

public Action:CS_OnTerminateRound( &Float:flDelay, &CSRoundEndReason:iReason )
{
	if( g_hTimerStuck != INVALID_HANDLE )
	{
		KillTimer( g_hTimerStuck );
		
		g_hTimerStuck = INVALID_HANDLE;
	}
	
	if( g_hTimerSound != INVALID_HANDLE )
	{
		KillTimer( g_hTimerSound );
		
		g_hTimerSound = INVALID_HANDLE;
	}
	
	if( !g_bGameRunning )
	{
		if( iReason == CSRoundEnd_TargetSaved )
		{
			iReason = CSRoundEnd_TargetBombed;
			
			return Plugin_Changed;
		}
		
		return Plugin_Continue;
	}
	
	new iBomber = g_iCurrentBomber;
	
	g_iCurrentBomber = 0;
	
	if( iBomber > 0 && IsClientInGame( iBomber ) )
	{
		decl String:szName[ 32 ];
		GetClientName( iBomber, szName, sizeof( szName ) );
		
#if IS_EXPOSURE_MODE
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x02 %s died from exposure!", szName );
#else
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x02 %s has been left with the bomb!", szName );
#endif
		
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x01 Bomb was dropped\x04 %i\x01 times, bomber switched\x04 %i\x01 times during this round.", g_iStatsBombDropped, g_iStatsBombSwitched );
		
		g_iLastBomber = iBomber;
		
		g_bDeadPlayers[ iBomber ] = true;
		
		if( IsPlayerAlive( iBomber ) )
		{
			ForcePlayerSuicide( iBomber );
			
			SetEntProp( iBomber, Prop_Data, "m_iFrags", 0 );
			
			new Float:vPosition[ 3 ];
			GetClientAbsOrigin( iBomber, vPosition );
			
			EmitAmbientSound( "weapons/hegrenade/explode3.wav", vPosition, iBomber, SNDLEVEL_RAIDSIREN );
			
			new iExplosion = CreateEntityByName( "env_explosion" );
			
			if( iExplosion != -1 )
			{
				DispatchKeyValueVector( iExplosion, "Origin", vPosition );
				DispatchKeyValue( iExplosion, "iMagnitude", "0" );
				DispatchKeyValue( iExplosion, "spawnflags", "128" );
				DispatchSpawn( iExplosion );
				AcceptEntityInput( iExplosion, "Explode" );
				AcceptEntityInput( iExplosion, "Kill" );
			}
		}
	}
	
	g_bStarting = true;
	g_bGameRunning = false;
	
	RemoveBomb( );
	
	new iPlayers, i, iAlivePlayer;
	
	for( i = 1; i <= MaxClients; i++ )
	{
#if IS_EXPOSURE_MODE
		g_iBombHeldTimer[ i ] = 0;
#endif
		
		if( IsPlayerBombGamer( i ) )
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
		iReason = CSRoundEnd_TerroristWin;
	}
	else if( iReason == CSRoundEnd_TargetSaved )
	{
		flDelay = 5.0;
		iReason = CSRoundEnd_TargetBombed;
	}
	
	return Plugin_Changed;
}

public OnPlayerSpawn( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	new iClient = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
	
	if( !IsPlayerAlive( iClient ) )
	{
		PrintToChatAll( "DEBUG: Client %i spawned, but not alive", iClient );
		return;
	}
	
	if( IsFakeClient( iClient ) )
	{
		SetEntityMoveType( iClient, MOVETYPE_NOCLIP );
		SetEntProp( iClient, Prop_Data, "m_takedamage", 0, 1 );
		SetEntProp( iClient, Prop_Data, "m_fEffects", GetEntProp( g_iFakeClient, Prop_Data, "m_fEffects" ) | 0x020 );
		TeleportEntity( iClient, Float:{ 0.0, 0.0, -99999.0 }, NULL_VECTOR, NULL_VECTOR );
		
		return;
	}
	
	if( g_bGameRunning )
	{
		PrintToChatAll( "DEBUG: Client %i spawned while game is running (sound timer exists? %i)", iClient, g_hTimerSound != INVALID_HANDLE );
	}
	else
	{
		PrintToChatAll( "DEBUG: Client %i spawned", iClient );
	}
	
	if( g_bDeadPlayers[ iClient ] )
	{
		PrintToChat( iClient, " \x01\x0B\x04[BombGame]\x01 You can't play this round!" );
		
		ForcePlayerSuicide( iClient );
		
		SetEntProp( iClient, Prop_Data, "m_iFrags", 0 );
		SetEntProp( iClient, Prop_Data, "m_iDeaths", GetEntProp( iClient, Prop_Data, "m_iDeaths" ) - 1 );
		
		return;
	}
	
	CreateTimer( 0.0, OnTimerHideRadar, GetClientSerial( iClient ), TIMER_FLAG_NO_MAPCHANGE );
}

public Action:OnTimerHideRadar( Handle:hTimer, any:iSerial )
{
	new iClient = GetClientFromSerial( iSerial );
	
	if( iClient && IsPlayerAlive( iClient ) )
	{
		HideRadar( iClient );
		
		SetEntProp( iClient, Prop_Data, "m_takedamage", 0, 1 );
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
		g_iCurrentBomber = 0;
		g_iLastBomber = iClient;
		
		g_bDeadPlayers[ iClient ] = true;
		
		decl String:szName[ 32 ];
		GetClientName( iClient, szName, sizeof( szName ) );
		
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x02 %s suicided while being the bomber.", szName );
		
		EndRound( );
	}
	else
	{
		if( g_iLastBomber != iClient )
		{
			CheckEnoughPlayers( iClient );
			
			new iRagdoll = GetEntPropEnt( iClient, Prop_Send, "m_hRagdoll" );
			
			if( iRagdoll > 0 )
			{
				AcceptEntityInput( iRagdoll, "kill" );
			}
		}
		
		if( g_bGameRunning )
		{
			g_bDeadPlayers[ iClient ] = true;
		}
	}
	
	ClientCommand( iClient, "playgamesound Music.StopAllMusic" ); // TODO: This gets blocked clientside
}

public OnBombPickup( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	if( !g_bGameRunning || g_bStarting )
	{
		return;
	}
	
	if( g_hTimerStuck != INVALID_HANDLE )
	{
		KillTimer( g_hTimerStuck );
		
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
		
#if IS_EXPOSURE_MODE
		if( g_iBombHeldTimer[ g_iCurrentBomber ] == EXPOSURE_TIME - 1 )
		{
			EmitSoundToAll( "ui/arm_bomb.wav", g_iCurrentBomber );
		}
#endif
	}
	else
	{
		EmitSoundToAll( "items/ammo_pickup.wav", iClient );
	}
}

public OnBombDropped( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	g_iStatsBombDropped++;
	
#if IS_EXPOSURE_MODE
	new iEntity = GetClientOfUserId( GetEventInt( hEvent, "entindex" ) );
	
	if( IsValidEdict( iEntity ) )
	{
		SetEntityRenderColor( iEntity, 241, 196, 15, 255 );
		SetEntityRenderMode( iEntity, RENDER_TRANSCOLOR );
	}
#endif
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

public OnRestartGameCvar( Handle:hCvar, const String:szOldValue[ ], const String:szNewValue[ ] )
{
	if( StringToInt( szNewValue ) != 0 )
	{
		ResetGame( );
		
		// Massive hacks all the way across the sky
		new Float:flDelay = 10.0;
		new CSRoundEndReason:iReason = CSRoundEnd_GameStart;
		
		CS_OnTerminateRound( flDelay, iReason );
	}
}

MakeBomber( iClient )
{
	ShowRadar( iClient );
	
	g_iPreviousPlayerModel = GetEntProp( iClient, Prop_Data, "m_nModelIndex", 2 );
	
	SetEntProp( iClient, Prop_Data, "m_nModelIndex", g_iPlayerModel, 2 );
}

EndRound( )
{
	CS_TerminateRound( 3.0, CSRoundEnd_Draw );
}

IsPlayerBombGamer( iClient )
{
	return IsClientInGame( iClient ) && IsPlayerAlive( iClient ) && GetClientTeam( iClient ) == CS_TEAM_T;
}

IsEnoughPlayersToPlay( )
{
	new iPlayers, i;
	
	for( i = 1; i <= MaxClients; i++ )
	{
		if( IsPlayerBombGamer( i ) )
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
		g_iBombHeldTimer[ i ] = 0;
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
		if( i != iClient && IsPlayerBombGamer( i ) )
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
