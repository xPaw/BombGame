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
		AcceptEntityInput( iEntity, "Disable" );
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

public OnRoundStart( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	new iEntity = -1;
	
	while( ( iEntity = FindEntityByClassname( iEntity, "hostage_entity" ) ) != -1 )
	{
		AcceptEntityInput( iEntity, "kill" );
	}
	
	g_iCurrentBomber = 0;
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
	}
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
	
	//new iPrimarySlot = GetPlayerWeaponSlot( iClient, CS_SLOT_PRIMARY );
	new iSecondarySlot = GetPlayerWeaponSlot( iClient, CS_SLOT_SECONDARY );
	
	if( iSecondarySlot > -1 )
	{
		RemovePlayerItem( iClient, iSecondarySlot );
	}
}

public Action:OnBombPickup( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	new iClient = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
	
	if( g_iCurrentBomber != iClient )
	{
		g_iCurrentBomber = iClient;
		
		new String:szName[ 32 ];
		GetClientName( iClient, szName, sizeof( szName ) );
		
		PrintToChatAll( "\x01\x0B\x04[BombGame] \x02%s\x01 has picked up the bomb!", szName );
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