#pragma semicolon 1

#include <sourcemod>
#include <multicolors>
#include <SteamWorks>
#include <store>
#include <cstrike>

#pragma newdecls required

ConVar g_Cvar_Enable;
ConVar g_Cvar_Timer_Mode;
ConVar g_Cvar_Prefix;

int g_iTimerMode;
bool g_bEnable;
char g_sPrefix[32];

bool g_bCstrike = false;

enum struct Credit_Config
{
	int iInterval_amount;
	float fInterval_lenght;
	
	// Steam Group
	bool bEnableSteam;
	int iSteamGroupID;
	float fSteamGroupMulti;
	char sSteamGroupDesc[64];
	
	// Clan Tag
	bool bEnableClanTag;
	char sClanTag[32];
	float fClanTagMulti;
	char sClanTagDesc[64];
	
	// VIP 
	bool bEnableVIP;
	char sVIPFlags[16];
	int iVIPFlagbits;
	float fVIPMulti;
	char sVIPDesc[64];
}

enum struct Player_Status
{
	bool bEarnable;
	bool bHasSteam;
	bool bHasClanTag;
	bool bHasVIP;
}

Credit_Config g_Config;
Player_Status g_ClientStatus[MAXPLAYERS];
KeyValues kv;

public Plugin myinfo =
{
	name = "More configure store credits interval",
	author = "Oylsister",
	description = "",
	version = "1.1",
	url = "https://github.com/oylsister/"
};

public void OnPluginStart()
{
	char sGameName[32];
	GetGameFolderName(sGameName, sizeof(sGameName));
	
	if(StrEqual(sGameName, "cstrike", false) || StrEqual(sGameName, "csgo", false))
		g_bCstrike = true;
	
	g_Cvar_Enable = CreateConVar("sm_interval_enable", "1.0", "Enable this plugin or not", _, true, 0.0, true, 1.0);
	g_Cvar_Timer_Mode = CreateConVar("sm_interval_timer_mode", "1.0", "Timer that player will earn credits (1 = Based on Server Time, 2 = Based on Client)", _, true, 1.0, true, 2.0);
	g_Cvar_Prefix = CreateConVar("sm_interval_prefix", "{green}[Store]{default}", "Prefix for Interval message");
	
	RegAdminCmd("sm_loadinterval", Command_LoadConfig, ADMFLAG_CONFIG);
	RegConsoleCmd("sm_creditperk", CheckCreditsPerk);
	
	HookConVarChange(g_Cvar_Enable, OnConVarChange);
	
	AutoExecConfig(true);
}

public void OnConVarChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(convar == g_Cvar_Enable)
		g_bEnable = GetConVarBool(g_Cvar_Enable);
		
	else if (convar == g_Cvar_Timer_Mode)
		g_iTimerMode = GetConVarInt(g_Cvar_Timer_Mode);
		
	else
		GetConVarString(g_Cvar_Prefix, g_sPrefix, sizeof(g_sPrefix));
}

public void OnMapStart()
{
	LoadConfig();
	
	if(g_iTimerMode == 1 && g_bEnable)
		CreateTimer(g_Config.fInterval_lenght, Give_ClientCreditsAll, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientPostAdminCheck(int client)
{
	CheckClientPerk(client);
	
	if(g_iTimerMode == 2 && g_bEnable && g_ClientStatus[client].bEarnable)
		CreateTimer(g_Config.fInterval_lenght, Give_ClientCredits, client, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientSettingsChanged(int client)
{
	CheckClientPerk(client);
}

stock void LoadConfig()
{
	char sConfigPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sConfigPath, sizeof(sConfigPath), "configs/store/store_interval.txt");
	
	if(!FileExists(sConfigPath))
	{
		SetFailState("Could not find \"configs/store/store_interval.txt\"");
		return;
	}
	
	if(kv != INVALID_HANDLE) 
		delete kv;
		
	kv = CreateKeyValues("Interval");
	
	KvRewind(kv);
	
	g_Config.iInterval_amount = KvGetNum(kv, "interval_amount", -1);
	g_Config.fInterval_lenght = KvGetFloat(kv, "interval_lenght", 60.0);
	
	g_Config.bEnableSteam = view_as<bool>(KvGetNum(kv, "enable_steam", 0));
	g_Config.iSteamGroupID = KvGetNum(kv, "SteamGroupID", -1);
	g_Config.fSteamGroupMulti = KvGetFloat(kv, "SteamGroupMulti", 1.0);
	KvGetString(kv, "SteamGroupDesc", g_Config.sSteamGroupDesc, 64);
	
	g_Config.bEnableClanTag = view_as<bool>(KvGetNum(kv, "enable_clantag", 0));
	KvGetString(kv, "ClanTag", g_Config.sClanTag, 32);
	g_Config.fClanTagMulti = KvGetFloat(kv, "ClanTagMulti", 1.0);
	KvGetString(kv, "ClanTagDesc", g_Config.sClanTagDesc, 64);
	
	g_Config.bEnableVIP = view_as<bool>(KvGetNum(kv, "enable_vip", 0));
	KvGetString(kv, "VIPFlags", g_Config.sVIPFlags, 16);
	g_Config.fVIPMulti = KvGetFloat(kv, "VIPMulti", 1.0);
	KvGetString(kv, "VIPDesc", g_Config.sVIPDesc, 64);
	
	g_Config.iVIPFlagbits = ReadFlagString(g_Config.sVIPFlags);
	
	if(!g_bCstrike)
	{
		g_Config.bEnableClanTag = false;
		LogMessage("The engine is not CS:GO or CS:S, clantag feature has been disable");
	}
	
	delete kv;
}

void CheckClientPerk(int client)
{
	if(!IsValidClient(client))
	{
		g_ClientStatus[client].bEarnable = false;
		return;
	}
	else
	{
		g_ClientStatus[client].bEarnable = true;
		
		// Steam Group Stuff
		SteamWorks_GetUserGroupStatus(client, g_Config.iSteamGroupID);
	
		// Check ClanTag
		if(g_bCstrike)
			CheckClientClanTag(client);
		
		// Check VIP Stuff
		CheckClientAdminFlags(client);
	}
}

public Action Command_LoadConfig(int client, int args)
{
	CReplyToCommand(client, "%s Config Reloaded", g_sPrefix);
	LoadConfig();
	return Plugin_Handled;
}

public Action Give_ClientCreditsAll(Handle timer)
{
	SendAllCredits();
	return Plugin_Continue;
}

public void SendAllCredits()
{
	for (int i = 0; i < MaxClients; i++)
	{
		if(g_ClientStatus[i].bEarnable && GetClientTeam(i) > 1 && IsClientInGame(i))
		{
			int iCredits = Store_GetClientCredits(i);
			int iTotalEarn = g_Config.iInterval_amount;
			
			if(g_ClientStatus[i].bHasSteam)
				iTotalEarn += (g_Config.iInterval_amount * g_Config.fSteamGroupMulti) - g_Config.iInterval_amount;
			
			if(g_bCstrike)
			{
				if(g_ClientStatus[i].bHasClanTag)
					iTotalEarn += (g_Config.iInterval_amount * g_Config.fClanTagMulti) - g_Config.iInterval_amount;
			}
			
			if(g_ClientStatus[i].bHasVIP)
				iTotalEarn += (g_Config.iInterval_amount * g_Config.fVIPMulti) - g_Config.iInterval_amount;
			
			Store_SetClientCredits(i, iCredits + iTotalEarn);
			PrintEarningMessage(i, iCredits + iTotalEarn, g_ClientStatus[i].bHasSteam, g_ClientStatus[i].bHasClanTag, g_ClientStatus[i].bHasVIP);
		}
	}
}

public Action Give_ClientCredits(Handle timer, any client)
{
	if(!IsClientInGame(client))
		return Plugin_Stop;
		
	else
	{
		SendClientCredits(client);
		return Plugin_Continue;
	}
}

public void SendClientCredits(int client)
{
	if(g_ClientStatus[client].bEarnable && GetClientTeam(client) > 1)
	{
		int iCredits = Store_GetClientCredits(client);
		int iTotalEarn = g_Config.iInterval_amount;
			
		if(g_ClientStatus[client].bHasSteam)
			iTotalEarn += (g_Config.iInterval_amount * g_Config.fSteamGroupMulti) - g_Config.iInterval_amount;
			
		if(g_bCstrike)
		{
			if(g_ClientStatus[client].bHasClanTag)
				iTotalEarn += (g_Config.iInterval_amount * g_Config.fClanTagMulti) - g_Config.iInterval_amount;
		}
			
		if(g_ClientStatus[client].bHasVIP)
			iTotalEarn += (g_Config.iInterval_amount * g_Config.fVIPMulti) - g_Config.iInterval_amount;
			
		Store_SetClientCredits(client, iCredits + iTotalEarn);
		PrintEarningMessage(client, iCredits + iTotalEarn, g_ClientStatus[client].bHasSteam, g_ClientStatus[client].bHasClanTag, g_ClientStatus[client].bHasVIP);
	}
}

public void PrintEarningMessage(int client, int credits, bool hasSteam, bool hasTag, bool hasVIP)
{
	char g_sMessage[256];
	
	if(credits == 0)
		return;
		
	if(client == 0 || !IsClientInGame(client))
		return;
		
	if(!hasSteam && !hasTag && !hasVIP)
		CPrintToChat(client, "%s You have earned {lightgreen}%d{default} credits.", g_sPrefix, credits);
	
	else
	{
		int iPerk = 0;
		Format(g_sMessage, sizeof(g_sMessage), "(Extra: ");
		
		if(hasSteam)
		{
			iPerk++;
			StrCat(g_sMessage, sizeof(g_sMessage), g_Config.sSteamGroupDesc);
		}
		if(hasTag)
		{
			iPerk++;
			if(iPerk > 1)
				StrCat(g_sMessage, sizeof(g_sMessage), ", ");
				
			StrCat(g_sMessage, sizeof(g_sMessage), g_Config.sClanTagDesc);
		}
		if(hasVIP)
		{
			iPerk++;
			if(iPerk > 1)
				StrCat(g_sMessage, sizeof(g_sMessage), ", ");
				
			StrCat(g_sMessage, sizeof(g_sMessage), g_Config.sVIPDesc);
		}
		StrCat(g_sMessage, sizeof(g_sMessage), ")");
		CPrintToChat(client, "%s You have earned {lightgreen}%d{default} credits. %s", g_sPrefix, credits, g_sMessage);
	}
}

public Action CheckCreditsPerk(int client, int args)
{
	char sClientName[128];
	char sClientID[128];
	
	char sLine1[64], sLine2[64], sLine3[64], sLine4[64], sLine5[64];
	
	if(!g_ClientStatus[client].bEarnable)
	{
		CReplyToCommand(client, "%s Your account is invalid, try rejoining the server again", g_sPrefix);
		return Plugin_Handled;
	}
	
	Menu menu = new Menu(PerkInfoHandler, MENU_ACTIONS_ALL);
	menu.SetTitle("Credit Perk Info\n");
	
	GetClientName(client, sClientName, sizeof(sClientName));
	Format(sLine1, sizeof(sLine1), "Player: %s", sClientName);
	menu.AddItem("line1", sLine1);
	
	GetClientAuthId(client, AuthId_Steam2, sClientID, sizeof(sClientID), false);
	Format(sLine2, sizeof(sLine2), "ID: %s\n", sClientID);
	menu.AddItem("line2", sLine2);
	
	Format(sLine3, sizeof(sLine3), "Steam Group: %s", g_ClientStatus[client].bHasSteam ? "Active" : "Inactive");
	menu.AddItem("line3", sLine3);
	
	if(g_bCstrike)
	{
		Format(sLine4, sizeof(sLine4), "ClanTag: %s", g_ClientStatus[client].bHasClanTag ? "Active" : "Inactive");
		menu.AddItem("line4", sLine4);
	}
	
	Format(sLine5, sizeof(sLine5), "VIP Perk: %s", g_ClientStatus[client].bHasSteam ? "Active" : "Inactive");
	menu.AddItem("line5", sLine5);
	
	menu.ExitButton = true;
	menu.Display(client, 60);
	
	return Plugin_Handled;
}

public int PerkInfoHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_DrawItem:
		{
			int style;
			char info[64];
			menu.GetItem(param2, info, sizeof(info), style);
			
			return ITEMDRAW_RAWLINE;
		}
		case MenuAction_End:
			delete menu;
		
	}
	return 0;
}

public int SteamWorks_OnClientGroupStatus(int authid, int groupAccountID, bool isMember, bool isOfficer)
{
	int client = GetClientOfAuthID(authid);
	if (client != -1 && isMember)
		g_ClientStatus[client].bHasSteam = true;

	else
		g_ClientStatus[client].bHasSteam = false;
}

int GetClientOfAuthID(int authid)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i))
			continue;

		char charauth[64], authchar[64];
		if (!GetClientAuthId(i, AuthId_Steam3, charauth, sizeof(charauth)))
			continue;

		IntToString(authid, authchar, sizeof(authchar));

		if (StrContains(charauth, authchar) != -1)
			return i;
	}

	return -1;
}

void CheckClientClanTag(int client)
{
	char sTag[32];
	CS_GetClientClanTag(client, sTag, sizeof(sTag));

	if(StrEqual(sTag, g_Config.sClanTag, false))
		g_ClientStatus[client].bHasClanTag = true;
	
	else
		g_ClientStatus[client].bHasClanTag = false;
}

void CheckClientAdminFlags(int client)
{
	int iClientFlag = GetUserFlagBits(client);
	
	if(iClientFlag & g_Config.iVIPFlagbits)
		g_ClientStatus[client].bHasVIP = true;
		
	else
		g_ClientStatus[client].bHasVIP = false;
}

stock bool IsValidClient(int client, bool nobots = true)
{ 
    if (client <= 0 || client > MaxClients || !IsClientConnected(client) || (nobots && IsFakeClient(client)))
    {
        return false; 
    }
    return IsClientInGame(client); 
} 