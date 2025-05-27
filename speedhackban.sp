#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "2.0"
#define CONFIG_FILE "speedhack"

// Detection system
ConVar g_cvPluginEnable, g_cvCheckInterval, g_cvRequiredViolations, g_cvDebug;
// Ban settings
ConVar g_cvBanMessage;
// Immunity
ConVar g_cvAdrenalineImmunity;
// Speed thresholds
ConVar g_cvSurvivorMax, g_cvHunterPounceMax, g_cvChargerChargeMax, g_cvWitchRunMax;
ConVar g_cvTankNormalMax, g_cvTankBurningMax;
ConVar g_cvJockeyMax, g_cvSpitterMax, g_cvBoomerMax, g_cvSmokerMax;

bool g_bAdrenalineImmune[MAXPLAYERS + 1];
Handle g_hAdrenalineTimer[MAXPLAYERS + 1];
int g_iSpeedViolations[MAXPLAYERS + 1];
float g_fLastPosition[MAXPLAYERS + 1][3];

public Plugin myinfo = 
{
    name = "Precision Speed Hack Ban",
    author = "Your Name",
    description = "Advanced speed hack detection with auto-config",
    version = PLUGIN_VERSION,
    url = ""
};

public void OnPluginStart()
{
    // Create plugin version cvar
    CreateConVar("sm_speedhackban_version", PLUGIN_VERSION, "Plugin version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
    
    // Register auto-config (creates speedhack.cfg if missing)
    AutoExecConfig(true, CONFIG_FILE);
    
    // Create all configuration variables
    CreateConVars();
    
    // Hook necessary events
    HookEvents();
    
    // Initialize timer for speed checks
    CreateTimer(g_cvCheckInterval.FloatValue, Timer_CheckSpeeds, _, TIMER_REPEAT);
    
    // Initialize all connected players
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i)) {
            OnClientPutInServer(i);
        }
    }
}

void CreateConVars()
{
    // Plugin toggle
    g_cvPluginEnable = CreateConVar("sm_speedhackban_enable", "1", 
        "Enable speed hack detection (0=Off, 1=On)", FCVAR_NONE, true, 0.0, true, 1.0);
    
    // Ban message
    g_cvBanMessage = CreateConVar("sm_speedhack_banmessage", 
        "Banned for speed hacking", "Message shown when banning players");
    
    // Detection settings
    g_cvCheckInterval = CreateConVar("sm_speedhack_check_interval", "1.0", 
        "Speed check interval in seconds", FCVAR_NONE, true, 0.1, true, 5.0);
    
    g_cvRequiredViolations = CreateConVar("sm_speedhack_required_violations", "3", 
        "Consecutive violations before ban", FCVAR_NONE, true, 1.0, true, 10.0);
    
    g_cvAdrenalineImmunity = CreateConVar("sm_speedhack_adrenaline_immunity", "30.0", 
        "Adrenaline immunity duration (seconds)", FCVAR_NONE, true, 0.0, true, 60.0);
    
    // Speed thresholds
    g_cvSurvivorMax = CreateConVar("sm_speedhack_survivor_max", "250.0", 
        "Max survivor speed", FCVAR_NONE, true, 100.0, true, 2000.0);
    
    g_cvHunterPounceMax = CreateConVar("sm_speedhack_hunter_pounce_max", "1000.0", 
        "Max hunter pounce speed", FCVAR_NONE, true, 500.0, true, 2000.0);
    
    g_cvChargerChargeMax = CreateConVar("sm_speedhack_charger_charge_max", "650.0", 
        "Max charger charge speed", FCVAR_NONE, true, 300.0, true, 2000.0);
    
    g_cvWitchRunMax = CreateConVar("sm_speedhack_witch_run_max", "400.0", 
        "Max witch running speed", FCVAR_NONE, true, 200.0, true, 2000.0);
    
    g_cvTankNormalMax = CreateConVar("sm_speedhack_tank_normal_max", "210.0", 
        "Max tank speed (not burning)", FCVAR_NONE, true, 100.0, true, 500.0);
    
    g_cvTankBurningMax = CreateConVar("sm_speedhack_tank_burning_max", "160.0", 
        "Max tank speed (burning)", FCVAR_NONE, true, 50.0, true, 300.0);
    
    g_cvJockeyMax = CreateConVar("sm_speedhack_jockey_max", "250.0", 
        "Max jockey speed", FCVAR_NONE, true, 100.0, true, 500.0);
    
    g_cvSpitterMax = CreateConVar("sm_speedhack_spitter_max", "210.0", 
        "Max spitter speed", FCVAR_NONE, true, 100.0, true, 500.0);
    
    g_cvBoomerMax = CreateConVar("sm_speedhack_boomer_max", "175.0", 
        "Max boomer speed", FCVAR_NONE, true, 100.0, true, 300.0);
    
    g_cvSmokerMax = CreateConVar("sm_speedhack_smoker_max", "210.0", 
        "Max smoker speed", FCVAR_NONE, true, 100.0, true, 300.0);
    
    // Debug
    g_cvDebug = CreateConVar("sm_speedhack_debug", "0", 
        "Debug mode (0=Off, 1=Log detections, 2=Log all checks)", FCVAR_NONE, true, 0.0, true, 2.0);
}

void HookEvents()
{
    HookEvent("adrenaline_used", Event_AdrenalineUsed);
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("pounce_start", Event_HunterPounce);
    HookEvent("charger_charge_start", Event_ChargerCharge);
    HookEvent("witch_harasser_set", Event_WitchStartled);
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    g_bAdrenalineImmune[client] = false;
    g_iSpeedViolations[client] = 0;
    GetClientAbsOrigin(client, g_fLastPosition[client]);
}

public void OnClientDisconnect(int client)
{
    ClearAdrenalineImmunity(client);
    g_iSpeedViolations[client] = 0;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    for (int i = 1; i <= MaxClients; i++) {
        g_iSpeedViolations[i] = 0;
    }
    return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client && IsClientInGame(client)) {
        g_iSpeedViolations[client] = 0;
        GetClientAbsOrigin(client, g_fLastPosition[client]);
    }
    return Plugin_Continue;
}

public Action Event_HunterPounce(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client) g_iSpeedViolations[client] = 0;
    return Plugin_Continue;
}

public Action Event_ChargerCharge(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client) g_iSpeedViolations[client] = 0;
    return Plugin_Continue;
}

public Action Event_WitchStartled(Event event, const char[] name, bool dontBroadcast)
{
    int witch = event.GetInt("witchid");
    if (IsValidEntity(witch)) {
        SetEntProp(witch, Prop_Data, "m_iSpeedViolations", 0);
    }
    return Plugin_Continue;
}

public Action Event_AdrenalineUsed(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client && IsClientInGame(client)) {
        ClearAdrenalineImmunity(client);
        g_bAdrenalineImmune[client] = true;
        g_hAdrenalineTimer[client] = CreateTimer(g_cvAdrenalineImmunity.FloatValue, Timer_RemoveImmunity, GetClientUserId(client));
    }
    return Plugin_Continue;
}

public Action Timer_RemoveImmunity(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client) g_bAdrenalineImmune[client] = false;
    g_hAdrenalineTimer[client] = null;
    return Plugin_Stop;
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (victim > 0 && victim <= MaxClients && GetClientTeam(victim) == 3 && 
        GetEntProp(victim, Prop_Send, "m_zombieClass") == 8 && // Tank
        (damagetype & DMG_BURN)) {
        g_iSpeedViolations[victim] = 0;
    }
    return Plugin_Continue;
}

void ClearAdrenalineImmunity(int client)
{
    g_bAdrenalineImmune[client] = false;
    if (g_hAdrenalineTimer[client] != null) {
        KillTimer(g_hAdrenalineTimer[client]);
        g_hAdrenalineTimer[client] = null;
    }
}

public Action Timer_CheckSpeeds(Handle timer)
{
    if (!g_cvPluginEnable.BoolValue) {
        return Plugin_Continue;
    }
    
    char banMessage[256];
    g_cvBanMessage.GetString(banMessage, sizeof(banMessage));
    
    for (int client = 1; client <= MaxClients; client++) {
        if (!IsClientInGame(client) || !IsPlayerAlive(client) || g_bAdrenalineImmune[client]) {
            continue;
        }
        
        float newPos[3];
        GetClientAbsOrigin(client, newPos);
        
        float distance = GetVectorDistance(g_fLastPosition[client], newPos);
        float speed = distance / g_cvCheckInterval.FloatValue;
        
        g_fLastPosition[client] = newPos;
        
        float maxSpeed = GetEntityMaxSpeed(client);
        
        if (speed > maxSpeed) {
            g_iSpeedViolations[client]++;
            
            if (g_cvDebug.IntValue > 0) {
                char clientName[MAX_NAME_LENGTH];
                GetClientName(client, clientName, sizeof(clientName));
                LogMessage("Speed violation #%d for %s: %.1f > %.1f", 
                    g_iSpeedViolations[client], clientName, speed, maxSpeed);
            }
            
            if (g_iSpeedViolations[client] >= g_cvRequiredViolations.IntValue) {
                BanSpeedHacker(client, speed, maxSpeed, banMessage);
                g_iSpeedViolations[client] = 0;
            }
        } else if (g_iSpeedViolations[client] > 0) {
            g_iSpeedViolations[client]--;
        }
    }
    
    // Check witches
    int witch = -1;
    while ((witch = FindEntityByClassname(witch, "witch")) != -1) {
        if (GetEntProp(witch, Prop_Data, "m_bAngry")) {
            float witchSpeed = GetEntitySpeed(witch);
            if (witchSpeed > g_cvWitchRunMax.FloatValue) {
                int violations = GetEntProp(witch, Prop_Data, "m_iSpeedViolations") + 1;
                SetEntProp(witch, Prop_Data, "m_iSpeedViolations", violations);
                
                if (violations >= g_cvRequiredViolations.IntValue) {
                    LogMessage("Detected speed hacking witch (speed: %.1f)", witchSpeed);
                    AcceptEntityInput(witch, "Kill");
                }
            } else {
                SetEntProp(witch, Prop_Data, "m_iSpeedViolations", 0);
            }
        }
    }
    
    return Plugin_Continue;
}

float GetEntityMaxSpeed(int entity)
{
    if (entity <= 0 || entity > MaxClients) {
        if (IsValidEntity(entity) && HasEntProp(entity, Prop_Data, "m_bAngry")) {
            return g_cvWitchRunMax.FloatValue;
        }
        return 0.0;
    }
    
    int team = GetClientTeam(entity);
    if (team == 2) return g_cvSurvivorMax.FloatValue;
    
    if (team == 3) {
        int zClass = GetEntProp(entity, Prop_Send, "m_zombieClass");
        
        switch (zClass) {
            case 3: return g_cvHunterPounceMax.FloatValue;
            case 6: return g_cvChargerChargeMax.FloatValue;
            case 5: return g_cvJockeyMax.FloatValue;
            case 7: return g_cvSpitterMax.FloatValue;
            case 4: return g_cvBoomerMax.FloatValue;
            case 1: return g_cvSmokerMax.FloatValue;
            case 8: return (GetEntProp(entity, Prop_Send, "m_bIsBurning")) ? 
                   g_cvTankBurningMax.FloatValue : g_cvTankNormalMax.FloatValue;
        }
    }
    
    return 0.0;
}

float GetEntitySpeed(int entity)
{
    float vel[3];
    if (entity > 0 && entity <= MaxClients) {
        GetEntPropVector(entity, Prop_Data, "m_vecVelocity", vel);
    } else if (IsValidEntity(entity)) {
        GetEntPropVector(entity, Prop_Data, "m_vecVelocity", vel);
    }
    return GetVectorLength(vel);
}

void BanSpeedHacker(int client, float speed, float maxSpeed, const char[] message)
{
    char clientName[MAX_NAME_LENGTH], authId[32];
    GetClientName(client, clientName, sizeof(clientName));
    
    if (GetClientAuthId(client, AuthId_Steam2, authId, sizeof(authId))) {
        ServerCommand("sm_ban #%d 0 \"%s\"", GetClientUserId(client), message);
        LogMessage("Banned %s (%s) for speed hacking. Speed: %.1f (max: %.1f)", 
            clientName, authId, speed, maxSpeed);
        
        for (int i = 1; i <= MaxClients; i++) {
            if (IsClientInGame(i) && !IsFakeClient(i)) {
                PrintToChat(i, "\x04[SpeedHackBan] \x01Banned \x03%s \x01for speed hacking (%.0f > %.0f)", 
                    clientName, speed, maxSpeed);
            }
        }
    }
}