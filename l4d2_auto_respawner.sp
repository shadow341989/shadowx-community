#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "1.0"

public Plugin myinfo = 
{
    name = "L4D2 Auto Respawner",
    author = "Your Name",
    description = "Handles suicide detection, respawning, and immunity systems",
    version = PLUGIN_VERSION,
    url = ""
};

// Player Tracking
bool g_bPressedSpace[MAXPLAYERS+1];
bool g_bInPardon[MAXPLAYERS+1];
bool g_bIsImmune[MAXPLAYERS+1];
int g_iPardonTime[MAXPLAYERS+1];
Handle g_hPardonTimer[MAXPLAYERS+1];
float g_fDeathTime[MAXPLAYERS+1];
float g_vDeathPos[MAXPLAYERS+1][3];
int g_iDeathWeapons[MAXPLAYERS+1][5];
int g_iDeathCharacter[MAXPLAYERS+1];

// ConVars
ConVar g_cvPardonTime;
ConVar g_cvTankImmunity;
ConVar g_cvSuicideWindow;

public void OnPluginStart()
{
    // Create ConVars
    g_cvPardonTime = CreateConVar("sm_respawner_pardontime", "10", "Time in seconds to pardon a suicide", _, true, 5.0, true, 30.0);
    g_cvTankImmunity = CreateConVar("sm_respawner_tankimmunity", "4", "Immunity time after Tank punch", _, true, 1.0, true, 10.0);
    g_cvSuicideWindow = CreateConVar("sm_respawner_suicidewindow", "3", "Time window to detect suicide after space press", _, true, 1.0, true, 5.0);

    // Register commands
    RegConsoleCmd("sm_pardon", Cmd_Pardon, "Pardon a player who committed suicide");

    // Hook events
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
    HookEvent("round_start", Event_RoundStart);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("tank_spawn", Event_TankSpawn);
    HookEvent("player_spawn", Event_PlayerSpawn);

    // Initialize arrays
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i))
        {
            OnClientPutInServer(i);
        }
    }
}

public void OnClientPutInServer(int client)
{
    g_bPressedSpace[client] = false;
    g_bInPardon[client] = false;
    g_bIsImmune[client] = false;
}

public void OnClientDisconnect(int client)
{
    if(g_bInPardon[client])
    {
        RespawnSurvivor(client);
    }
    
    if(g_hPardonTimer[client] != null)
    {
        KillTimer(g_hPardonTimer[client]);
        g_hPardonTimer[client] = null;
    }
    
    g_bPressedSpace[client] = false;
    g_bInPardon[client] = false;
    g_bIsImmune[client] = false;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    if(IsClientInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) == 2)
    {
        if(buttons & IN_JUMP)
        {
            g_bPressedSpace[client] = true;
            CreateTimer(g_cvSuicideWindow.FloatValue, Timer_ResetSpacePress, GetClientUserId(client));
        }
    }
    return Plugin_Continue;
}

public Action Timer_ResetSpacePress(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if(client > 0)
    {
        g_bPressedSpace[client] = false;
    }
    return Plugin_Stop;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if(client > 0 && GetClientTeam(client) == 2 && !g_bIsImmune[client])
    {
        if(g_bPressedSpace[client] || (GetGameTime() - g_fDeathTime[client] <= g_cvSuicideWindow.FloatValue))
        {
            HandleSuicide(client);
        }
        else
        {
            g_fDeathTime[client] = GetGameTime();
        }
    }
    return Plugin_Continue;
}

void HandleSuicide(int client)
{
    GetClientAbsOrigin(client, g_vDeathPos[client]);
    SavePlayerWeapons(client);
    g_iDeathCharacter[client] = GetEntProp(client, Prop_Send, "m_survivorCharacter");
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && GetClientTeam(i) == 2 && i != client)
        {
            PrintToChat(i, "\x04[Respawner] \x03%N \x01has committed suicide. Type \x04!pardon \x01within \x03%d \x01seconds to forgive.", 
                client, g_cvPardonTime.IntValue);
        }
    }
    
    g_bInPardon[client] = true;
    g_iPardonTime[client] = g_cvPardonTime.IntValue;
    g_hPardonTimer[client] = CreateTimer(1.0, Timer_PardonCountdown, GetClientUserId(client), TIMER_REPEAT);
}

public Action Timer_PardonCountdown(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if(client == 0 || !IsClientInGame(client))
    {
        RespawnSurvivor(client);
        g_hPardonTimer[client] = null;
        return Plugin_Stop;
    }
    
    g_iPardonTime[client]--;
    
    if(g_iPardonTime[client] <= 0)
    {
        KickClient(client, "You were kicked for committing suicide");
        RespawnSurvivor(client);
        g_hPardonTimer[client] = null;
        return Plugin_Stop;
    }
    
    return Plugin_Continue;
}

public Action Cmd_Pardon(int client, int args)
{
    if(client == 0) return Plugin_Handled;
    
    if(GetClientTeam(client) != 2)
    {
        ReplyToCommand(client, "[Respawner] Only survivors can pardon suicides.");
        return Plugin_Handled;
    }
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && g_bInPardon[i])
        {
            g_bInPardon[i] = false;
            if(g_hPardonTimer[i] != null)
            {
                KillTimer(g_hPardonTimer[i]);
                g_hPardonTimer[i] = null;
            }
            
            PrintToChatAll("\x04[Respawner] \x03%N \x01has been pardoned by \x03%N\x01.", i, client);
            return Plugin_Handled;
        }
    }
    
    ReplyToCommand(client, "[Respawner] No one needs pardoning right now.");
    return Plugin_Handled;
}

void SavePlayerWeapons(int client)
{
    for(int i = 0; i < 5; i++)
    {
        g_iDeathWeapons[client][i] = -1;
    }
    
    int weapon;
    for(int i = 0; i < 5; i++)
    {
        weapon = GetPlayerWeaponSlot(client, i);
        if(weapon != -1)
        {
            g_iDeathWeapons[client][i] = GetEntProp(weapon, Prop_Data, "m_iItemDefinitionIndex");
        }
    }
}

void RespawnSurvivor(int client)
{
    int nearest = FindNearestSurvivor(g_vDeathPos[client]);
    float spawnPos[3];
    
    if(nearest != -1)
    {
        GetClientAbsOrigin(nearest, spawnPos);
        spawnPos[2] += 20.0;
    }
    else
    {
        spawnPos = g_vDeathPos[client];
    }
    
    int bot = FindSurvivorBot();
    if(bot != -1)
    {
        SetEntProp(bot, Prop_Send, "m_survivorCharacter", g_iDeathCharacter[client]);
        TeleportEntity(bot, spawnPos, NULL_VECTOR, NULL_VECTOR);
        
        for(int i = 0; i < 5; i++)
        {
            if(g_iDeathWeapons[client][i] != -1)
            {
                char weaponName[32];
                GetWeaponClassname(g_iDeathWeapons[client][i], weaponName, sizeof(weaponName));
                GivePlayerItem(bot, weaponName);
            }
        }
        
        if(IsClientInGame(client) && GetClientTeam(client) == 2 && !IsFakeClient(client))
        {
            FakeClientCommand(client, "sb_takecontrol");
        }
    }
    else
    {
        int newBot = CreateFakeClient("SurvivorBot");
        if(newBot > 0)
        {
            ChangeClientTeam(newBot, 2);
            DispatchSpawn(newBot);
            SetEntProp(newBot, Prop_Send, "m_survivorCharacter", g_iDeathCharacter[client]);
            TeleportEntity(newBot, spawnPos, NULL_VECTOR, NULL_VECTOR);
            
            for(int i = 0; i < 5; i++)
            {
                if(g_iDeathWeapons[client][i] != -1)
                {
                    char weaponName[32];
                    GetWeaponClassname(g_iDeathWeapons[client][i], weaponName, sizeof(weaponName));
                    GivePlayerItem(newBot, weaponName);
                }
            }
            
            if(IsClientInGame(client) && GetClientTeam(client) == 2 && !IsFakeClient(client))
            {
                FakeClientCommand(client, "sb_takecontrol");
            }
        }
    }
}

int FindSurvivorBot()
{
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && IsFakeClient(i) && GetClientTeam(i) == 2)
        {
            return i;
        }
    }
    return -1;
}

int FindNearestSurvivor(float pos[3])
{
    int nearest = -1;
    float minDist = -1.0;
    float dist;
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2)
        {
            float clientPos[3];
            GetClientAbsOrigin(i, clientPos);
            dist = GetVectorDistance(pos, clientPos);
            
            if(nearest == -1 || dist < minDist)
            {
                nearest = i;
                minDist = dist;
            }
        }
    }
    
    return nearest;
}

public Action Event_TankSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int tank = GetClientOfUserId(event.GetInt("userid"));
    if(tank > 0)
    {
        SDKHook(tank, SDKHook_OnTakeDamagePost, OnTakeDamagePost_Tank);
    }
    return Plugin_Continue;
}

public void OnTakeDamagePost_Tank(int victim, int attacker, int inflictor, float damage, int damagetype)
{
    if(attacker > 0 && attacker <= MaxClients && GetClientTeam(attacker) == 2 && IsPlayerAlive(attacker))
    {
        g_bIsImmune[attacker] = true;
        CreateTimer(g_cvTankImmunity.FloatValue, Timer_RemoveImmunity, GetClientUserId(attacker));
    }
}

public Action Timer_RemoveImmunity(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if(client > 0)
    {
        g_bIsImmune[client] = false;
    }
    return Plugin_Stop;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    for(int i = 1; i <= MaxClients; i++)
    {
        g_bIsImmune[i] = false;
    }
    return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && GetClientTeam(i) == 2)
        {
            g_bIsImmune[i] = true;
        }
    }
    return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if(client > 0 && GetClientTeam(client) == 2)
    {
        g_bPressedSpace[client] = false;
        g_bInPardon[client] = false;
    }
    return Plugin_Continue;
}

void GetWeaponClassname(int weaponId, char[] buffer, int maxlen)
{
    switch(weaponId)
    {
        case 1: strcopy(buffer, maxlen, "weapon_smg");
        case 2: strcopy(buffer, maxlen, "weapon_rifle");
        case 3: strcopy(buffer, maxlen, "weapon_shotgun_chrome");
        case 4: strcopy(buffer, maxlen, "weapon_hunting_rifle");
        case 5: strcopy(buffer, maxlen, "weapon_smg_silenced");
        case 6: strcopy(buffer, maxlen, "weapon_shotgun_spas");
        case 7: strcopy(buffer, maxlen, "weapon_rifle_ak47");
        case 8: strcopy(buffer, maxlen, "weapon_rifle_desert");
        case 9: strcopy(buffer, maxlen, "weapon_sniper_military");
        case 10: strcopy(buffer, maxlen, "weapon_shotgun_pump");
        case 11: strcopy(buffer, maxlen, "weapon_rifle_sg552");
        case 12: strcopy(buffer, maxlen, "weapon_sniper_awp");
        case 13: strcopy(buffer, maxlen, "weapon_sniper_scout");
        case 14: strcopy(buffer, maxlen, "weapon_rifle_m60");
        case 15: strcopy(buffer, maxlen, "weapon_grenade_launcher");
        case 16: strcopy(buffer, maxlen, "weapon_pistol");
        case 17: strcopy(buffer, maxlen, "weapon_pistol_magnum");
        case 18: strcopy(buffer, maxlen, "weapon_molotov");
        case 19: strcopy(buffer, maxlen, "weapon_pipe_bomb");
        case 20: strcopy(buffer, maxlen, "weapon_vomitjar");
        case 21: strcopy(buffer, maxlen, "weapon_first_aid_kit");
        case 22: strcopy(buffer, maxlen, "weapon_pain_pills");
        case 23: strcopy(buffer, maxlen, "weapon_adrenaline");
        default: buffer[0] = '\0';
    }
}