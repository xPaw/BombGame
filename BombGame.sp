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

new g_iCurrentBomber;
new Handle:g_hTimer = INVALID_HANDLE;

public OnPluginStart( )
{
	HookEvent( "round_mvp",       OnRoundMVP );
	HookEvent( "round_end",       OnRoundEnd );
	HookEvent( "round_start",     OnRoundStart );
	HookEvent( "bomb_pickup",     OnBombPickup );
	HookEvent( "jointeam_failed", OnJoinTeamFailed, EventHookMode_Pre );
	HookEvent( "player_spawn",    OnPlayerSpawn );
	
	AddCommandListener( OnJoinTeamCommand, "jointeam" );
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
	
	ServerCommand( "exec BombGame.cfg" );
}

public OnMapEnd( )
{
	if( g_hTimer != INVALID_HANDLE )
	{
		CloseHandle( g_hTimer );
		
		g_hTimer = INVALID_HANDLE;
	}
}

public OnClientPutInServer( iClient )
{
	FakeClientCommand( iClient, "joingame" );
	FakeClientCommandEx( iClient, "jointeam 2" );
}

public OnRoundStart( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	new iEntity = -1;
	
	while( ( iEntity = FindEntityByClassname( iEntity, "hostage_entity" ) ) != -1 )
	{
		AcceptEntityInput( iEntity, "kill" );
	}
	
	if( g_hTimer != INVALID_HANDLE )
	{
		CloseHandle( g_hTimer );
	}
	
	new Float:flRoundTime = GetEventFloat( hEvent, "timelimit" );
	
	g_hTimer = CreateTimer( flRoundTime, OnRoundTimerEnd );
}

public Action:OnRoundTimerEnd( Handle:hTimer )
{
	g_hTimer = INVALID_HANDLE;
	
	PrintToChatAll( "Forcing round end" );
	
	CS_TerminateRound( 3.0, g_iCurrentBomber > 0 ? CSRoundEnd_TargetBombed : CSRoundEnd_TerroristWin );
}

public OnRoundEnd( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	if( g_iCurrentBomber > 0 && IsClientInGame( g_iCurrentBomber ) )
	{
		new String:szName[ 32 ];
		GetClientName( g_iCurrentBomber, szName, sizeof( szName ) );
		
		PrintToChatAll( "\x01\x0B\x04[BombGame] \x02%s\x01 has been left with the bomb!", szName );
		
		if( IsPlayerAlive( g_iCurrentBomber ) )
		{
			ForcePlayerSuicide( g_iCurrentBomber );
		}
		
		new Handle:hLeader = CreateEvent( "round_mvp" );
		SetEventInt( hLeader, "userid", g_iCurrentBomber );
		SetEventInt( hLeader, "reason", 0 );
		FireEvent( hLeader );
	}
	
	g_iCurrentBomber = 0;
}

public OnRoundMVP( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	new iClient = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
	new iReason = GetEventInt( hEvent, "reason" );
	
	PrintToChatAll( "MVP: %i - Reason: %i", iClient, iReason );
}

public OnPlayerSpawn( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	new iClient = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
	
	SetEntProp( iClient, Prop_Data, "m_takedamage", 0, 1 );
}

public Action:OnBombPickup( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	new iClient = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
	
	if( g_iCurrentBomber != iClient )
	{
		if( g_iCurrentBomber > 0 && IsPlayerAlive( g_iCurrentBomber ) )
		{
			set_rendering( g_iCurrentBomber );
		}
		
		#define FxGlowShell 17
		#define FxGlow 3
		
		set_rendering( iClient, FxGlowShell, 255, 100, 0, FxGlow );
		
		g_iCurrentBomber = iClient;
		
		new String:szName[ 32 ];
		GetClientName( iClient, szName, sizeof( szName ) );
		
		PrintToChatAll( "\x01\x0B\x04[BombGame] \x02%s\x01 has picked up the bomb!", szName );
		
		new Handle:hLeader = CreateEvent( "gg_leader" );
		SetEventInt( hLeader, "playerid", GetEventInt( hEvent, "userid" ) );
		FireEvent( hLeader );
	}
}

public Action:OnJoinTeamFailed( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	new iClient = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
	
	if( IsClientInGame( iClient ) )
	{
		PrintToChatAll( "Forced %i to terrorists team because it said it was full", iClient );
		
		ChangeClientTeam( iClient, 2 );
		
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action:OnJoinTeamCommand( iClient, const String:szCommand[], iArguments )
{
	if( iArguments < 1 || !IsClientInGame( iClient ) )
	{
		return Plugin_Continue;
	}
	
	#define TEAM_SPECTATORS 1
	#define TEAM_TERRORITS  2
	
	new String:szArgument[ 4 ];
	GetCmdArg( 1, szArgument, sizeof( szArgument ) );
	new iNewTeam = StringToInt( szArgument );
	
	if( iNewTeam == TEAM_SPECTATORS || iNewTeam == TEAM_TERRORITS )
	{
		ReplyToCommand( iClient, "You joined team %i", iNewTeam );
		
		return Plugin_Continue;
	}
	
	ReplyToCommand( iClient, "Forced to join terrorists" );
	
	FakeClientCommand( iClient, "jointeam %i", TEAM_TERRORITS );
	
	return Plugin_Handled;
}

stock set_rendering(index, fx=0, r=255, g=255, b=255, render=0, amount=255)
{
	SetEntProp(index, Prop_Send, "m_nRenderFX", fx, 1);
	SetEntProp(index, Prop_Send, "m_nRenderMode", render, 1);
	
	if( fx > 0 )
	{
		new offset = GetEntSendPropOffs(index, "m_clrRender");
		
		SetEntData(index, offset, r, 1, true);
		SetEntData(index, offset + 1, g, 1, true);
		SetEntData(index, offset + 2, b, 1, true);
		SetEntData(index, offset + 3, amount, 1, true);
	}
}
