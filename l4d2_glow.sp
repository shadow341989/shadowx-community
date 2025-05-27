#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0"

public Plugin myinfo = 
{
    name = "L4D2 Glow Effect",
    author = "shadowx",
    description = "Makes survivors glow when they type !glow",
    version = PLUGIN_VERSION,
    url = "https://github.com/shadow341989/shadowx-community"
};

bool g_bIsGlowing[MAXPLAYERS + 1];

public void OnPluginStart()
{
    RegConsoleCmd("sm_glow", Command_Glow, "Toggles a glow effect on your survivor.");
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
}

public Action Command_Glow(int client, int args)
{
    if (!IsValidClient(client) || !IsSurvivor(client))
    {
        ReplyToCommand(client, "[SM] Only alive survivors can use this command.");
        return Plugin_Handled;
    }

    if (g_bIsGlowing[client])
    {
        ReplyToCommand(client, "[SM] You are already glowing!");
        return Plugin_Handled;
    }

    // Apply glow effect
    SetGlowEffect(client, true);
    CreateTimer(7.0, Timer_RemoveGlow, GetClientUserId(client));

    ReplyToCommand(client, "[SM] You are now glowing for 7 seconds!");
    return Plugin_Handled;
}

public Action Timer_RemoveGlow(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (IsValidClient(client) && g_bIsGlowing[client])
    {
        SetGlowEffect(client, false);
    }
    return Plugin_Continue;
}

void SetGlowEffect(int client, bool enable)
{
    if (!IsValidClient(client)) return;

    g_bIsGlowing[client] = enable;

    if (enable)
    {
        // Randomly pick between blue, red, or white glow
        int color[4];
        switch (GetRandomInt(0, 2))
        {
            case 0: { color = {0, 0, 255, 255}; } // Blue
            case 1: { color = {255, 0, 0, 255}; } // Red
            case 2: { color = {255, 255, 255, 255}; } // White
        }

        // Apply glow
        SetEntProp(client, Prop_Send, "m_iGlowType", 3); // 3 = Outline glow
        SetEntProp(client, Prop_Send, "m_nGlowRange", 99999); // Visibility range
        SetEntProp(client, Prop_Send, "m_glowColorOverride", color[0] + (color[1] << 8) + (color[2] << 16));
    }
    else
    {
        // Remove glow
        SetEntProp(client, Prop_Send, "m_iGlowType", 0);
        SetEntProp(client, Prop_Send, "m_glowColorOverride", 0);
    }
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidClient(client) && g_bIsGlowing[client])
    {
        SetGlowEffect(client, false);
    }
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i) && g_bIsGlowing[i])
        {
            SetGlowEffect(i, false);
        }
    }
}

bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client));
}

bool IsSurvivor(int client)
{
    return (GetClientTeam(client) == 2); // 2 = Survivor team
}