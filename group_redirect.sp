#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define PLUGIN_VERSION "1.0"

ConVar g_cvSteamGroup;

public Plugin myinfo = 
{
    name = "Steam Group Redirect",
    author = "Your Name",
    description = "Provides !group command to redirect players to your Steam group",
    version = PLUGIN_VERSION,
    url = "https://yourwebsite.com"
};

public void OnPluginStart()
{
    g_cvSteamGroup = CreateConVar("z_steamgroup", "", "URL of the Steam group to redirect to");
    
    RegConsoleCmd("sm_group", Command_Group, "Opens the server's Steam group in your browser");
    RegConsoleCmd("sm_steamgroup", Command_Group, "Opens the server's Steam group in your browser");
    
    AutoExecConfig(true, "group_redirect");
}

public Action Command_Group(int client, int args)
{
    if (!client)
    {
        ReplyToCommand(client, "[SM] This command can only be used in-game.");
        return Plugin_Handled;
    }
    
    char steamGroupURL[256];
    g_cvSteamGroup.GetString(steamGroupURL, sizeof(steamGroupURL));
    
    if (steamGroupURL[0] == '\0')
    {
        ReplyToCommand(client, "[SM] Steam group URL is not configured.");
        return Plugin_Handled;
    }
    
    ShowMOTDPanel(client, "Server Steam Group", steamGroupURL, MOTDPANEL_TYPE_URL);
    PrintToChat(client, "[SM] Opening the server's Steam group in your browser...");
    
    return Plugin_Handled;
}