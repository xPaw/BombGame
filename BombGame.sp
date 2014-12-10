#pragma semicolon 1

#include < sourcemod >
#include < sdktools >
#include < cstrike >

#define EXPOSURE_TIME 25
#define MAX_GRACE_JOIN_TIME 1000.0 // We override game's cvar
#define BOT_NAME "BombGame Coach"

#define HIDEHUD_RADAR  ( 1 << 12 )
#define OBS_MODE_ROAMING 6

public Plugin:myinfo =
{
	name        = "BombGame",
	description = "Good ol' bomb game.",
	author      = "xPaw",
	version     = "1.0",
	url         = "https://github.com/xPaw/BombGame"
};

new g_iBombHeldTimer[ MAXPLAYERS ];
new g_bGameRunning;
new g_iFakeClient;
new g_iLastBomber;
new g_iCurrentBomber;
new bool:g_bIsNuke;
new bool:g_bFixTerminateRound;
new Float:g_fStuckBackTime;
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
	
	RegConsoleCmd( "sm_help", OnCommandHelp, "Display helpful message about the bomb game" );
	RegConsoleCmd( "sm_stuck", OnCommandStuck, "Get the bomb back if you're the bomber" );
	RegConsoleCmd( "sm_s", OnCommandStuck, "Get the bomb back if you're the bomber" );
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
	
	HookUserMessage( GetUserMessageId( "TextMsg" ), OnUserMessage, true );
	
	HookConVarChange( FindConVar( "mp_restartgame" ), OnRestartGameCvar );
	
	g_hCvarGraceJoinTime = FindConVar( "mp_join_grace_time" );
	
	SetConVarBounds( g_hCvarGraceJoinTime, ConVarBound_Upper, true, MAX_GRACE_JOIN_TIME );
}

public OnPluginEnd( )
{
	if( g_iFakeClient )
	{
		KickClient( g_iFakeClient, "Plugin end" );
	}
	
	if( g_iCurrentBomber )
	{
		SetEntProp( g_iCurrentBomber, Prop_Data, "m_nModelIndex", g_iPreviousPlayerModel, 2 );
	}
	
	/*for( new i = 1; i <= MaxClients; i++ )
	{
		if( IsClientInGame( i ) )
		{
			CS_SetClientClanTag( i, "" );
		}
	}*/
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
	
	g_iPlayerModel = PrecacheModel( "models/player/zombie.mdl" );
	
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
	
	new String:szMap[ 32 ];
	GetCurrentMap( szMap, sizeof( szMap ) );
	
	g_bIsNuke = StrEqual( szMap, "de_nuke", false );
	
	if( g_bIsNuke )
	{
		InitializeNuke( );
	}
	
	CreateTimer( 1.0, OnTimerCreateBot, _, TIMER_FLAG_NO_MAPCHANGE );
	
	SetConVarFloat( g_hCvarGraceJoinTime, MAX_GRACE_JOIN_TIME );
	
	/** begin insane warmup hacks **/
	ServerCommand( "mp_do_warmup_period 1" );
	ServerCommand( "mp_warmuptime 25" );
	ServerCommand( "mp_warmup_start" );
	ServerCommand( "mp_warmup_start" );
}

public Action:OnTimerCreateBot( Handle:hTimer )
{
	if( !g_iFakeClient || !IsClientInGame( g_iFakeClient ) )
	{
		g_iFakeClient = CreateFakeClient( BOT_NAME );
		
		if( g_iFakeClient > 0 )
		{
			CS_SwitchTeam( g_iFakeClient, CS_TEAM_CT );
			
			CS_SetClientClanTag( g_iFakeClient, "[BombGame]" );
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
		g_iLastBomber = iClient;
		
		decl String:szName[ 32 ];
		GetClientName( iClient, szName, sizeof( szName ) );
		
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x02 %s left the game while being the bomber.", szName );
		
		TerminateRound( );
		
		GiveBombStuff( iClient );
	}
	else
	{
		// TODO: useless check??
		if( g_iLastBomber != iClient )
		{
			CheckEnoughPlayers( iClient );
		}
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
			g_hTimerStuck = CreateTimer( g_fStuckBackTime, OnTimerGiveBomb, GetClientSerial( iClient ), TIMER_FLAG_NO_MAPCHANGE );
			
			ReplyToCommand( iClient, " \x01\x0B\x04[BombGame]\x01 You will get your bomb in %.0f seconds.", g_fStuckBackTime );
			
			g_fStuckBackTime += 3.0;
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
	if( g_bGameRunning )
	{
		ReplyToCommand( iClient, " \x01\x0B\x04[BombGame]\x01 The game is already running." );
	}
	else if( IsWarmupPeriod( ) || IsFreezePeriod( ) )
	{
		ReplyToCommand( iClient, " \x01\x0B\x04[BombGame]\x01 Can't start the game in warmup period." );
	}
	else if( !IsEnoughPlayersToPlay( ) )
	{
		ReplyToCommand( iClient, " \x01\x0B\x04[BombGame]\x01 Not enough players to start the game." );
	}
	else
	{
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x01 Starting the game by player request." );
		
		CS_TerminateRound( 0.1, CSRoundEnd_Draw, true );
		
		StartGame( );
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


public Action:OnUserMessage( UserMsg:MsgId, Handle:hProtobuf, const iPlayers[], iNumPlayers, bool:bReliable, bool:bInit )
{
	decl String:szText[ 36 ];
	PbReadString( hProtobuf, "params", szText, sizeof( szText ), 0 );
	
	if( StrEqual( szText, "#SFUI_Notice_YouDroppedWeapon" )
	||  StrEqual( szText, "#SFUI_Notice_Got_Bomb" )
	||  StrEqual( szText, "#SFUI_Notice_C4_Plant_At_Bomb_Spot" ) )
	{
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public OnRoundStart( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	g_iLastBomber = 0;
	g_iStatsBombDropped = 0;
	g_iStatsBombSwitched = 0;
	
	if( g_bIsNuke )
	{
		InitializeNuke( );
	}
	
	g_fStuckBackTime = 5.0;
	
	if( !g_bGameRunning && !IsWarmupPeriod() )
	{
		if( IsEnoughPlayersToPlay( ) )
		{
			PrintToChatAll( " \x01\x0B\x04[BombGame]\x01 The game is starting...\x01 Say\x02 /help\x01 for more information." );
			PrintToChatAll( " \x01\x0B\x04[BombGame]\x01 Say\x02 /stuck\x01 if your bomb is inaccessible." );
			
			StartGame( );
		}
		else
		{
			PrintToChatAll( " \x01\x0B\x04[BombGame]\x01 Not enough players to start the game, once there are enough players you can say\x02 /start\x01" );
		}
	}
}

public OnRoundFreezeEnd( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	if( !g_bGameRunning )
	{
		SetConVarFloat( g_hCvarGraceJoinTime, MAX_GRACE_JOIN_TIME );
		
		return;
	}
	
	SetConVarFloat( g_hCvarGraceJoinTime, 0.0 ); // We don't want to allow late joins
	
	GiveBombStuff( );
}

GiveBombStuff( iBomber = 0 )
{
	new iPlayers[ MaxClients ], iAlive, i, iBestBomberCandidate, Float:flHighestDistance, Float:flDistance, bool:bMidGame = iBomber > 0;
	
	new Float:entityVec[3];
	new Float:targetVec[3];
	
	if( bMidGame )
	{
		GetEntPropVector( iBomber, Prop_Data, "m_vecOrigin", targetVec );
	}
	
	for( i = 1; i <= MaxClients; i++ )
	{
		if( i != iBomber && IsPlayerBombGamer( i ) && IsPlayerAlive( i ) )
		{
			iPlayers[ iAlive++ ] = i;
			
			if( bMidGame )
			{
				CS_SetClientContributionScore( i, CS_GetClientContributionScore( i ) + 1 );
				
				GetEntPropVector( i, Prop_Data, "m_vecOrigin", entityVec );
				
				flDistance = GetVectorDistance( entityVec, targetVec );
				
				if( flDistance > flHighestDistance )
				{
					flHighestDistance = flDistance;
					
					iBestBomberCandidate = i;
				}
			}
		}
	}
	
	if( iAlive > 1 )
	{
		if( iBestBomberCandidate == 0 )
		{
			iBestBomberCandidate = iPlayers[ GetRandomInt( 0, iAlive - 1 ) ];
		}
		
		g_iCurrentBomber = iBestBomberCandidate;
		
		decl String:szName[ 32 ];
		GetClientName( g_iCurrentBomber, szName, sizeof( szName ) );
		
		if( bMidGame )
		{
			PrintToChatAll( " \x01\x0B\x04[BombGame]\x02 %s\x01 now has the bomb for being the furthest player!", szName );
			
			if( iAlive == 2 )
			{
				new Handle:hAnnounce = CreateEvent( "round_announce_match_point" ); // round_announce_final
				FireEvent( hAnnounce );
			}
		}
		else
		{
			PrintToChatAll( " \x01\x0B\x04[BombGame]\x02 %s\x01 spawned with the bomb!", szName );
		}
		
		PrintCenterTextAll( "%s now has the bomb!", szName );
		
		GivePlayerItem( g_iCurrentBomber, "weapon_c4" );
		
		FakeClientCommand( g_iCurrentBomber, "use weapon_c4" );
		
		MakeBomber( g_iCurrentBomber );
		
		EmitSoundToClient( g_iCurrentBomber, "ui/beep22.wav" );
		
		g_hTimerSound = CreateTimer( 1.0, OnTimerIncreaseExposure, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE );
	}
	else if( iAlive == 1 )
	{
		iAlive = iPlayers[ 0 ];
		
		decl String:szName[ 32 ];
		GetClientName( iAlive, szName, sizeof( szName ) );
		
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x04 %s won the bomb game!", szName );
		
		CS_SetMVPCount( iAlive, CS_GetMVPCount( iAlive ) + 1 );
		
		CS_SetClientContributionScore( iAlive, CS_GetClientContributionScore( iAlive ) + 10 );
		
		new Handle:hLeader = CreateEvent( "round_mvp" );
		SetEventInt( hLeader, "userid", GetClientUserId( iAlive ) );
		FireEvent( hLeader );
		
		ResetGame( );
		
		g_bFixTerminateRound = true;
		
		ForcePlayerSuicide( g_iFakeClient );
	}
	else
	{
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x02 Something magical happened, resetting the game." );
		
		SetConVarInt( FindConVar( "mp_restartgame" ), 1 );
	}
}

public Action:OnTimerIncreaseExposure( Handle:hTimer )
{
	if( !g_iCurrentBomber )
	{
		// TODO
		PrintToChatAll( "DEBUG: OnTimerIncreaseExposure fired but there is no bomber" );
		
		ResetGame( );
		
		return;
	}
	
	new iTime = ++g_iBombHeldTimer[ g_iCurrentBomber ];
	
	if( iTime >= EXPOSURE_TIME )
	{
		new iBomber = g_iCurrentBomber;
		
		SetEntProp( iBomber, Prop_Send, "m_iHealth", 0 );
		
		TerminateRound( );
		
		GiveBombStuff( iBomber );
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

public TerminateRound( )
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
	
	new iBomber = g_iCurrentBomber;
	
	g_iCurrentBomber = 0;
	
	if( iBomber > 0 && IsClientInGame( iBomber ) )
	{
		decl String:szName[ 32 ];
		GetClientName( iBomber, szName, sizeof( szName ) );
		
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x02 %s died from exposure!", szName );
		
		//PrintToChatAll( " \x01\x0B\x04[BombGame]\x01 Bomb was dropped\x04 %i\x01 times.", g_iStatsBombDropped );
		//PrintToChatAll( " \x01\x0B\x04[BombGame]\x01 Bomber switched\x04 %i\x01 times during this round.", g_iStatsBombSwitched );
		
		g_iLastBomber = iBomber;
		
		if( IsPlayerAlive( iBomber ) )
		{
			ForcePlayerSuicide( iBomber );
			
			SetEntProp( iBomber, Prop_Data, "m_iFrags", 0 );
			
			new Float:vPosition[ 3 ];
			GetClientAbsOrigin( iBomber, vPosition );
			
			//EmitAmbientSound( "weapons/hegrenade/explode3.wav", vPosition, iBomber, SNDLEVEL_RAIDSIREN );
			
			new iExplosion = CreateEntityByName( "env_explosion" );
			
			if( iExplosion != -1 )
			{
				DispatchKeyValueVector( iExplosion, "Origin", vPosition );
				DispatchKeyValue( iExplosion, "iMagnitude", "500" );
				DispatchKeyValue( iExplosion, "spawnflags", "128" );
				DispatchSpawn( iExplosion );
				AcceptEntityInput( iExplosion, "Explode" );
				AcceptEntityInput( iExplosion, "Kill" );
			}
		}
	}
	
	RemoveBomb( );
	
	for( new i = 1; i <= MaxClients; i++ )
	{
		if( IsPlayerBombGamer( i ) && IsPlayerAlive( i ) )
		{
			CS_SetClientContributionScore( i, CS_GetClientContributionScore( i ) + 1 );
		}
	}
	
	g_fStuckBackTime = 5.0;
}

public Action:CS_OnTerminateRound( &Float:flDelay, &CSRoundEndReason:iReason )
{
	if( g_bFixTerminateRound )
	{
		g_bFixTerminateRound = false;
		
		iReason = CSRoundEnd_TargetBombed;
		
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}

public OnPlayerSpawn( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	new iClient = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
	
	if( !IsPlayerAlive( iClient ) )
	{
		return;
	}
	
	if( iClient == g_iFakeClient && IsFakeClient( iClient ) )
	{
		SetEntityMoveType( iClient, MOVETYPE_NOCLIP );
		SetEntProp( iClient, Prop_Data, "m_takedamage", 0, 1 );
		SetEntProp( iClient, Prop_Data, "m_fEffects", GetEntProp( g_iFakeClient, Prop_Data, "m_fEffects" ) | 0x020 );
		TeleportEntity( iClient, Float:{ 0.0, 0.0, -99999.0 }, NULL_VECTOR, NULL_VECTOR );
		
		return;
	}
	
	if( !g_bGameRunning && !IsWarmupPeriod( ) && !IsFreezePeriod( ) && IsEnoughPlayersToPlay( ) )
	{
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x01 Enough players joined, starting the game." );
		
		CS_TerminateRound( 0.1, CSRoundEnd_Draw, true );
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
	
	return g_iCurrentBomber == iClient || g_iLastBomber == iClient ? Plugin_Continue : Plugin_Handled;
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
		
		decl String:szName[ 32 ];
		GetClientName( iClient, szName, sizeof( szName ) );
		
		PrintToChatAll( " \x01\x0B\x04[BombGame]\x02 %s suicided while being the bomber.", szName );
		
		TerminateRound( );
		
		GiveBombStuff( iClient );
	}
	else
	{
		// TODO: useless check??
		if( g_iLastBomber != iClient )
		{
			CheckEnoughPlayers( iClient );
		}
		
		//decl String:szName[ 32 ];
		//GetClientName( iClient, szName, sizeof( szName ) );
		
		//PrintToChatAll( " \x01\x0B\x04[BombGame]\x02 %s is a silly person and decided to suicide.", szName );
	}
}

public OnBombPickup( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	if( !g_bGameRunning )
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
		
		g_iCurrentBomber = iClient;
		
		MakeBomber( iClient );
		
		decl String:szName[ 32 ];
		GetClientName( iClient, szName, sizeof( szName ) );
		
		//PrintToChatAll( " \x01\x0B\x04[BombGame]\x02 %s\x01 has picked up the bomb!", szName );
		
		PrintCenterTextAll( "%s now has the bomb!", szName );
		
		EmitSoundToAll( "buttons/blip2.wav", iClient );
		
		g_iStatsBombSwitched++;
		
		if( g_iBombHeldTimer[ g_iCurrentBomber ] == EXPOSURE_TIME - 1 )
		{
			EmitSoundToAll( "ui/arm_bomb.wav", g_iCurrentBomber );
		}
	}
	else
	{
		EmitSoundToAll( "items/ammo_pickup.wav", iClient );
	}
}

public OnBombDropped( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	g_iStatsBombDropped++;
	
	new iEntity = GetClientOfUserId( GetEventInt( hEvent, "entindex" ) );
	
	if( IsValidEdict( iEntity ) )
	{
		SetEntityRenderColor( iEntity, 241, 196, 15, 255 );
		SetEntityRenderMode( iEntity, RENDER_TRANSCOLOR );
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

public OnRestartGameCvar( Handle:hCvar, const String:szOldValue[ ], const String:szNewValue[ ] )
{
	if( StringToInt( szNewValue ) != 0 )
	{
		ResetGame( );
		
		TerminateRound( );
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
	CS_TerminateRound( 3.0, CSRoundEnd_Draw, true );
}

IsPlayerBombGamer( iClient )
{
	return IsClientInGame( iClient ) && /*IsPlayerAlive( iClient ) &&*/ GetClientTeam( iClient ) == CS_TEAM_T;
}

IsWarmupPeriod( )
{
	return GameRules_GetProp( "m_bWarmupPeriod" );
}

IsFreezePeriod( )
{
	return GameRules_GetProp( "m_bFreezePeriod" );
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

StartGame( )
{
	g_bGameRunning = true;
}

ResetGame( )
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
	
	for( new i = 1; i <= MaxClients; i++ )
	{
		g_iBombHeldTimer[ i ] = 0;
	}
	
	g_bGameRunning = false;
	g_iCurrentBomber = 0;
	g_fStuckBackTime = 5.0;
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
		if( i != iClient && IsPlayerBombGamer( i ) && IsPlayerAlive( i ) )
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
	
	decl String:szName[ 32 ];
	GetClientName( iLastPlayer, szName, sizeof( szName ) );
	
	PrintToChatAll( " \x01\x0B\x04[BombGame]\x02 %s\x01 was the last person alive, everyone else left or died, resetting the game.", szName );
	
	ResetGame( );
	
	EndRound( );
}

HideRadar( iClient )
{
	SetEntProp( iClient, Prop_Send, "m_iHideHUD", GetEntProp( iClient, Prop_Send, "m_iHideHUD" ) | HIDEHUD_RADAR );
}

ShowRadar( iClient )
{
	SetEntProp( iClient, Prop_Send, "m_iHideHUD", GetEntProp( iClient, Prop_Send, "m_iHideHUD" ) & ~HIDEHUD_RADAR );
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
