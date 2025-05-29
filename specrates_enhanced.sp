#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <clientprefs>

#define DEFAULT_TICKRATE 30
#define MAX_TICKRATE 100.0
#define MIN_TICKRATE 10.0

ConVar g_cvMinTickrate;
ConVar g_cvMaxTickrate;
Handle g_hSpecRatesKV;
Handle g_hTickrateCookie;

public Plugin myinfo = 
{
    name = "SpecRates Enhanced",
    author = "shadowx",
    description = "Allows setting custom spectator tickrates for players",
    version = "1.0",
    url = "https://github.com/shadow341989/shadowx-community"
}

public void OnPluginStart()
{
    // Create console variables
    CreateConVar("sm_specrates_version", "1.2.0", "SpecRates Enhanced Version", FCVAR_NOTIFY|FCVAR_DONTRECORD);
    g_cvMinTickrate = CreateConVar("sm_specrates_min", "10", "Minimum allowed tickrate for spectators", _, true, MIN_TICKRATE, true, MAX_TICKRATE);
    g_cvMaxTickrate = CreateConVar("sm_specrates_max", "100", "Maximum allowed tickrate for spectators", _, true, MIN_TICKRATE, true, MAX_TICKRATE);
    
    // Create client cookie for persistent settings
    g_hTickrateCookie = RegClientCookie("specrates_tickrate", "Player's preferred spectator tickrate", CookieAccess_Protected);
    
    // Load translations
    LoadTranslations("specrates.phrases");
    
    // Create config if it doesn't exist
    AutoExecConfig(true, "specrates");
    
    // Load the keyvalues file
    LoadSpecRatesConfig();
    
    // Register admin commands
    RegAdminCmd("sm_specrate", Command_SpecRate, ADMFLAG_GENERIC, "Set a player's spectator tickrate");
    RegAdminCmd("sm_specrate_reload", Command_ReloadConfig, ADMFLAG_CONFIG, "Reload the specrates config file");
    
    // Hook client events
    HookEvent("player_team", Event_PlayerTeam);
}

void LoadSpecRatesConfig()
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/specrates.cfg");
    
    g_hSpecRatesKV = CreateKeyValues("SpecRates");
    
    if (!FileExists(path))
    {
        File file = OpenFile(path, "w");
        if (file != null)
        {
            file.WriteLine("// SpecRates Configuration");
            file.WriteLine("// Format: \"STEAM_X:X:XXXXXXXX\" \"tickrate\"");
            file.WriteLine("");
            file.WriteLine("\"STEAM_0:1:792246145\" \"80\"");
            file.Close();
            
            KeyValuesToFile(g_hSpecRatesKV, path);
        }
        else
        {
            LogError("Could not create specrates config file at %s", path);
        }
    }
    
    if (!FileToKeyValues(g_hSpecRatesKV, path))
    {
        LogError("Could not load specrates config file at %s", path);
    }
}

public void OnMapStart()
{
    // Refresh settings on map start
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            UpdateClientTickrate(i);
        }
    }
}

public void OnClientPostAdminCheck(int client)
{
    if (!IsFakeClient(client))
    {
        UpdateClientTickrate(client);
    }
}

public void OnClientDisconnect(int client)
{
    // Save cookie on disconnect if needed
    if (AreClientCookiesCached(client) && !IsFakeClient(client))
    {
        char steamId[32];
        if (GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId)))
        {
            int tickrate = GetClientTickrate(client);
            if (tickrate != DEFAULT_TICKRATE)
            {
                char value[8];
                IntToString(tickrate, value, sizeof(value));
                SetClientCookie(client, g_hTickrateCookie, value);
            }
        }
    }
}

public Action Command_SpecRate(int client, int args)
{
    if (args < 2)
    {
        ReplyToCommand(client, "[SM] Usage: sm_specrate <#userid|name> <tickrate>");
        return Plugin_Handled;
    }
    
    char targetArg[64];
    GetCmdArg(1, targetArg, sizeof(targetArg));
    
    char tickrateArg[8];
    GetCmdArg(2, tickrateArg, sizeof(tickrateArg));
    int tickrate = StringToInt(tickrateArg);
    
    int minTickrate = g_cvMinTickrate.IntValue;
    int maxTickrate = g_cvMaxTickrate.IntValue;
    
    if (tickrate < minTickrate || tickrate > maxTickrate)
    {
        ReplyToCommand(client, "[SM] Tickrate must be between %d and %d", minTickrate, maxTickrate);
        return Plugin_Handled;
    }
    
    char targetName[MAX_TARGET_LENGTH];
    int targetList[MAXPLAYERS], targetCount;
    bool tnIsMl;
    
    if ((targetCount = ProcessTargetString(
            targetArg,
            client,
            targetList,
            MAXPLAYERS,
            COMMAND_FILTER_NO_BOTS,
            targetName,
            sizeof(targetName),
            tnIsMl)) <= 0)
    {
        ReplyToTargetError(client, targetCount);
        return Plugin_Handled;
    }
    
    for (int i = 0; i < targetCount; i++)
    {
        int target = targetList[i];
        if (IsClientInGame(target) && !IsFakeClient(target))
        {
            char steamId[32];
            if (GetClientAuthId(target, AuthId_Steam2, steamId, sizeof(steamId)))
            {
                // Update the KeyValues in memory
                KvRewind(g_hSpecRatesKV);
                KvSetNum(g_hSpecRatesKV, steamId, tickrate);
                
                // Update the client's actual tickrate
                SetClientTickrate(target, tickrate);
                
                // Save to their cookie
                char value[8];
                IntToString(tickrate, value, sizeof(value));
                SetClientCookie(target, g_hTickrateCookie, value);
                
                // Notify
                PrintToChat(client, "[SM] Set %N's spectator tickrate to %d", target, tickrate);
                PrintToChat(target, "[SM] Your spectator tickrate has been set to %d", tickrate);
            }
        }
    }
    
    // Save the KeyValues to file
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/specrates.cfg");
    KeyValuesToFile(g_hSpecRatesKV, path);
    
    return Plugin_Handled;
}

public Action Command_ReloadConfig(int client, int args)
{
    LoadSpecRatesConfig();
    ReplyToCommand(client, "[SM] Reloaded specrates configuration.");
    return Plugin_Handled;
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client && !IsFakeClient(client))
    {
        // Update tickrate when player changes team (might have become spectator)
        CreateTimer(0.1, Timer_UpdateTickrate, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
    return Plugin_Continue;
}

public Action Timer_UpdateTickrate(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client && IsClientInGame(client) && !IsFakeClient(client))
    {
        UpdateClientTickrate(client);
    }
    return Plugin_Stop;
}

void UpdateClientTickrate(int client)
{
    if (IsFakeClient(client))
        return;
    
    char steamId[32];
    if (!GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId)))
        return;
    
    // Check if they have a cookie set first
    if (AreClientCookiesCached(client))
    {
        char cookieValue[8];
        GetClientCookie(client, g_hTickrateCookie, cookieValue, sizeof(cookieValue));
        
        if (cookieValue[0] != '\0')
        {
            int tickrate = StringToInt(cookieValue);
            SetClientTickrate(client, tickrate);
            return;
        }
    }
    
    // Check the config file
    KvRewind(g_hSpecRatesKV);
    int tickrate = KvGetNum(g_hSpecRatesKV, steamId, DEFAULT_TICKRATE);
    
    // Set their tickrate
    SetClientTickrate(client, tickrate);
}

void SetClientTickrate(int client, int tickrate)
{
    // Clamp the tickrate to allowed values
    int minTickrate = g_cvMinTickrate.IntValue;
    int maxTickrate = g_cvMaxTickrate.IntValue;
    
    if (tickrate < minTickrate) tickrate = minTickrate;
    if (tickrate > maxTickrate) tickrate = maxTickrate;
    
    // Only update if they're a spectator
    if (GetClientTeam(client) == 1)
    {
        SetCommandFlags("cl_updaterate", GetCommandFlags("cl_updaterate") & ~FCVAR_CHEAT);
        ClientCommand(client, "cl_updaterate %d", tickrate);
        SetCommandFlags("cl_updaterate", GetCommandFlags("cl_updaterate") | FCVAR_CHEAT);
        
        SetCommandFlags("cl_interp_ratio", GetCommandFlags("cl_interp_ratio") & ~FCVAR_CHEAT);
        ClientCommand(client, "cl_interp_ratio 0");
        SetCommandFlags("cl_interp_ratio", GetCommandFlags("cl_interp_ratio") | FCVAR_CHEAT);
    }
}

int GetClientTickrate(int client)
{
    if (IsFakeClient(client))
        return DEFAULT_TICKRATE;
    
    char steamId[32];
    if (!GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId)))
        return DEFAULT_TICKRATE;
    
    // Check the config file
    KvRewind(g_hSpecRatesKV);
    return KvGetNum(g_hSpecRatesKV, steamId, DEFAULT_TICKRATE);
}