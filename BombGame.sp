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

new g_bDeadPlayers[ MAXPLAYERS ] = { false, ... };
new g_bStarting;
new g_bGameRunning;
new g_iCurrentBomber;
new Float:g_flRoundTime;
new Handle:g_hTimer = INVALID_HANDLE;

public OnPluginStart( )
{
	HookEvent( "round_start",      OnRoundStart );
	HookEvent( "round_freeze_end", OnRoundFreezeEnd );
	HookEvent( "bomb_pickup",      OnBombPickup );
	HookEvent( "player_spawn",     OnPlayerSpawn );
	HookEvent( "player_death",     OnPlayerDeath );
	HookEvent( "jointeam_failed",  OnJoinTeamFailed, EventHookMode_Pre );
}

public OnConfigsExecuted( )
{
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

public OnClientDisconnect( iClient )
{
	if( iClient == g_iCurrentBomber )
	{
		g_iCurrentBomber = 0;
		
		decl String:szName[ 32 ];
		GetClientName( iClient, szName, sizeof( szName ) );
		
		PrintToChatAll( "\x01\x0B\x04[BombGame] \x02%s left the game while being the bomber.", szName );
		
		EndRound( );
		
		CS_TerminateRound( 3.0, CSRoundEnd_Draw );
	}
}

public OnRoundStart( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	new iEntity = -1;
	
	while( ( iEntity = FindEntityByClassname( iEntity, "hostage_entity" ) ) != -1 )
	{
		AcceptEntityInput( iEntity, "kill" );
	}
	
	g_flRoundTime = GetEventFloat( hEvent, "timelimit" );
}

public OnRoundFreezeEnd( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	if( g_hTimer != INVALID_HANDLE )
	{
		CloseHandle( g_hTimer );
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
		
		g_iCurrentBomber = iPlayers[ GetRandomInt( 0, iAlive - 1 ) ];
		
		GivePlayerItem( g_iCurrentBomber, "weapon_c4" );
		
		SetEntPropFloat( g_iCurrentBomber, Prop_Send, "m_flLaggedMovementValue", 1.3 );
		SetEntityGravity( g_iCurrentBomber, 0.7 );
		
		decl String:szName[ 32 ];
		GetClientName( g_iCurrentBomber, szName, sizeof( szName ) );
		
		PrintToChatAll( "\x01\x0B\x04[BombGame] \x02%s spawned with the bomb!", szName );
		
		g_hTimer = CreateTimer( g_flRoundTime, OnRoundTimerEnd );
	}
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
		
		PrintToChatAll( "\x01\x0B\x04[BombGame] \x02%s has been left with the bomb!", szName );
		
		g_bDeadPlayers[ iBomber ] = true;
		
		if( IsPlayerAlive( iBomber ) )
		{
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
		for( i = 1; i <= MaxClients; i++ )
		{
			g_bDeadPlayers[ i ] = false;
		}
		
		decl String:szName[ 32 ];
		GetClientName( iAlivePlayer, szName, sizeof( szName ) );
		
		PrintToChatAll( "\x01\x0B\x04[BombGame] \x04%s has won the bomb game!", szName );
		
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
		ForcePlayerSuicide( iClient );
		
		SetEntProp( iClient, Prop_Data, "m_iFrags", 0 );
		SetEntProp( iClient, Prop_Data, "m_iDeaths", GetEntProp( iClient, Prop_Data, "m_iDeaths" ) - 1 );
		
		return;
	}
	
	//SetEntProp( iClient, Prop_Data, "m_iFrags", 0 );
	SetEntProp( iClient, Prop_Data, "m_takedamage", 0, 1 );
	
	if( !g_bStarting && !g_bGameRunning && IsEnoughPlayersToPlay( ) )
	{
		g_bStarting = true;
		
		PrintToChatAll( "\x01\x0B\x04[BombGame] \x04The game is starting..." );
		
		CS_TerminateRound( 2.0, CSRoundEnd_CTWin );
		
		ServerCommand( "exec BombGame.cfg" );
	}
}

public OnPlayerDeath( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	new iClient = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
	
	SetEntProp( iClient, Prop_Data, "m_iFrags", 0 );
	
	if( iClient == g_iCurrentBomber )
	{
		g_iCurrentBomber = 0;
		
		g_bDeadPlayers[ iClient ] = true;
		
		decl String:szName[ 32 ];
		GetClientName( iClient, szName, sizeof( szName ) );
		
		PrintToChatAll( "\x01\x0B\x04[BombGame] \x02%s suicided while being the bomber.", szName );
		
		EndRound( );
		
		CS_TerminateRound( 3.0, CSRoundEnd_Draw );
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
		if( g_iCurrentBomber > 0 && IsPlayerAlive( g_iCurrentBomber ) )
		{
			SetEntPropFloat( g_iCurrentBomber, Prop_Send, "m_flLaggedMovementValue", 1.0 );
			SetEntityGravity( g_iCurrentBomber, 1.0 );
		}
		
		SetEntPropFloat( iClient, Prop_Send, "m_flLaggedMovementValue", 1.3 );
		SetEntityGravity( iClient, 0.7 );
		
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

EndRound( )
{
	if( g_hTimer != INVALID_HANDLE )
	{
		CloseHandle( g_hTimer );
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
