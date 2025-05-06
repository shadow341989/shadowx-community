#include <sourcemod>
#include <sdktools>
#include <colors> // Include colors for colored chat messages

#pragma semicolon 1
#pragma newdecls required

#define ZC_TANK 8 // Tank class ID

public Plugin myinfo = 
{
    name = "Tank HP Display",
    author = "shadowx",
    description = "Displays the current Tank's HP when a player types !hp.",
    version = "1.0",
    url = "shadowcommunity.us"
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_hp", Command_ShowTankHP, "Displays the current Tank's HP.");
}

public Action Command_ShowTankHP(int client, int args)
{
    int tank = FindTank();
    
    if (tank == -1)
    {
        CPrintToChat(client, "{green}[!] No tank in play.");
        return Plugin_Handled;
    }
    
    int tankHP = GetEntProp(tank, Prop_Data, "m_iHealth");
    CPrintToChat(client, "{blue}[!] Tank's HP: %d", tankHP);
    
    return Plugin_Handled;
}

int FindTank()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsPlayerAlive(i) && GetEntProp(i, Prop_Send, "m_zombieClass") == ZC_TANK)
        {
            return i;
        }
    }
    
    return -1; // No Tank found
}