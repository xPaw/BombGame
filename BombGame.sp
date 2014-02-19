#include < sourcemod >
#include < sdktools >
#include < cstrike >

public Plugin:myinfo =
{
	name = "BombGame",
	author = "xPaw",
	description = "Good ol' bomb game.",
	version = "1.0",
	url = "http://mwh.co"
};

new g_bStarting;
new g_bGameRunning;
new g_iCurrentBomber;
new Handle:g_hTimer = INVALID_HANDLE;

public OnPluginStart( )
{
	HookEvent( "round_end",       OnRoundEnd );
	HookEvent( "round_start",     OnRoundStart );
	HookEvent( "bomb_pickup",     OnBombPickup );
	HookEvent( "jointeam_failed", OnJoinTeamFailed, EventHookMode_Pre );
	HookEvent( "player_spawn",    OnPlayerSpawn );
	
	ServerCommand( "exec BombGame.cfg" );
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
}

public OnMapEnd( )
{
	if( g_hTimer != INVALID_HANDLE )
	{
		CloseHandle( g_hTimer );
		
		g_hTimer = INVALID_HANDLE;
	}
}

public OnRoundStart( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	new iEntity = -1;
	
	while( ( iEntity = FindEntityByClassname( iEntity, "hostage_entity" ) ) != -1 )
	{
		AcceptEntityInput( iEntity, "kill" );
	}
	
	new iPlayers[ MaxClients ], iAlive, i;
	
	for( i = 1; i <= MaxClients; i++ )
	{
		if( IsClientInGame( i ) && IsPlayerAlive( i ) )
		{
			iPlayers[ iAlive++ ] = i;
		}
	}
	
	if( g_hTimer != INVALID_HANDLE )
	{
		CloseHandle( g_hTimer );
	}
	
	g_bStarting = false;
	
	if( iAlive > 1 )
	{
		g_bGameRunning = true;
		
		i = iPlayers[ GetRandomInt( 0, iAlive - 1 ) ];
		
		GivePlayerItem( i, "weapon_c4" );
		
		PrintToChatAll( "Giving bomb to #%i", i );
		
		new Float:flRoundTime = GetEventFloat( hEvent, "timelimit" );
		
		g_hTimer = CreateTimer( flRoundTime, OnRoundTimerEnd );
	}
}

public Action:OnRoundTimerEnd( Handle:hTimer )
{
	g_hTimer = INVALID_HANDLE;
	
	/*if( g_iCurrentBomber > 0 && IsClientInGame( g_iCurrentBomber ) )
	{
		new Handle:hLeader = CreateEvent( "round_mvp" );
		SetEventInt( hLeader, "userid", GetClientUserId( g_iCurrentBomber ) );
		SetEventInt( hLeader, "reason", 2 );
		FireEvent( hLeader );
	}*/
	
	CS_TerminateRound( 7.0, CSRoundEnd_TargetBombed );
}

public OnRoundEnd( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	new String:a[ 32 ];	
	GetEventString( hEvent, "message", a, 31 );
	
	PrintToChatAll( "RoundEnd: winner: %i - reason: %i - message: %s", GetEventInt( hEvent, "winner" ), GetEventInt( hEvent, "reason" ), a );
	
	if( g_iCurrentBomber > 0 && IsClientInGame( g_iCurrentBomber ) )
	{
		decl String:szName[ 32 ];
		GetClientName( g_iCurrentBomber, szName, sizeof( szName ) );
		
		PrintToChatAll( "\x01\x0B\x04[BombGame] \x02%s\x01 has been left with the bomb!", szName );
		
		if( IsPlayerAlive( g_iCurrentBomber ) )
		{
			ForcePlayerSuicide( g_iCurrentBomber );
		}
	}
	
	g_iCurrentBomber = 0;
	g_bStarting = true;
}

public OnPlayerSpawn( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	new iClient = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
	
	SetEntProp( iClient, Prop_Data, "m_takedamage", 0, 1 );
	
	if( !g_bGameRunning && !g_bStarting && IsEnoughPlayersToPlay( ) )
	{
		g_bStarting = true;
		
		PrintToChatAll( "\x01\x0B\x04[BombGame] \x04Starting the game!" );
		
		CS_TerminateRound( 1.0, CSRoundEnd_GameStart );
		
		ServerCommand( "exec BombGame.cfg" );
	}
}

public Action:OnBombPickup( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	if( !g_bGameRunning || g_bStarting )
	{
		return;
	}
	
	new iClient = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
	
	if( g_iCurrentBomber != iClient )
	{
		g_iCurrentBomber = iClient;
		
		decl String:szName[ 32 ];
		GetClientName( iClient, szName, sizeof( szName ) );
		
		PrintToChatAll( "\x01\x0B\x04[BombGame] \x02%s\x01 has picked up the bomb!", szName );
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
