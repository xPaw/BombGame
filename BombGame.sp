#include < sourcemod >
#include < sdktools >

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
	HookEvent( "round_end",   OnRoundEnd );
	HookEvent( "round_start", OnRoundStart );
	HookEvent( "item_pickup", OnItemPickUp );
	
	AddCommandListener( OnJoinTeamCommand, "jointeam" );
}

public OnMapStart( )
{
	new iEntity = -1;
	
	while( ( iEntity = FindEntityByClassname( iEntity, "func_bomb_target" ) ) != -1 )
	{
		AcceptEntityInput( iEntity, "kill" );
	}
	
	while( ( iEntity = FindEntityByClassname( iEntity, "func_hostage_rescue" ) ) != -1 )
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
		
		PrintToChatAll( "\x01\x0B\x01[BombGame] \x02%s\x01 has been left with the bomb!", szName );
		
		if( IsPlayerAlive( g_iCurrentBomber ) )
		{
			ForcePlayerSuicide( g_iCurrentBomber );
		}
	}
}

public Action:OnItemPickUp( Handle:hEvent, const String:szActionName[], bool:bDontBroadcast )
{
	new String:szName[ 32 ];
	GetEventString( hEvent, "item", szName, sizeof( szName ) );
	
	if( StrEqual( szName, "weapon_c4", false ) )
	{
		g_iCurrentBomber = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
		
		GetClientName( g_iCurrentBomber, szName, sizeof( szName ) );
		
		PrintToChatAll( "\x01\x0B\x01[BombGame] \x02%s\x01 has picked up the bomb!", szName );
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
	
	ChangeClientTeam( iClient, TEAM_TERRORITS );
	
	return Plugin_Handled;
}
