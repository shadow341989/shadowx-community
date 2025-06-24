#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.1"
#define WITCH_CLASSNAME "witch"
#define SPAWN_ENTITY "info_versus_spawn"

public Plugin myinfo = 
{
    name = "L4D2 Witch Mod",
    author = "shadowx",
    description = "Spawns witches",
    version = PLUGIN_VERSION,
    url = "https://github.com/shadow341989/shadowx-community"
};

ConVar g_cvEnabled;
ConVar g_cvWitchCount;
ConVar g_cvBonusPoints;
ConVar g_cvWalkChance; // New: Walking witch chance

bool g_bEnabled;
int g_iWitchCount;
int g_iBonusPoints;
float g_fWalkChance; // New: Stores walk chance
int g_iWitchesKilled;
int g_iSpawnedWitches;

public void OnPluginStart()
{
    CreateConVar("l4d2_witch_mod_version", PLUGIN_VERSION, "Plugin version", FCVAR_NOTIFY|FCVAR_DONTRECORD);
    
    g_cvEnabled = CreateConVar("l4d2_witch_mod_enabled", "1", "Enable/Disable the Witch Mod plugin", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvWitchCount = CreateConVar("z_number_witches", "1", "Number of witches to spawn per round", FCVAR_NONE, true, 0.0);
    g_cvBonusPoints = CreateConVar("l4d2_witch_mod_bonus_points", "10", "Bonus points awarded per witch kill (5-50)", FCVAR_NONE, true, 5.0, true, 50.0);
    g_cvWalkChance = CreateConVar("l4d2_witch_mod_walk_chance", "0.4", "Chance (0.0-1.0) for a witch to spawn as a walking witch", FCVAR_NONE, true, 0.0, true, 1.0);
    
    HookEvent("witch_killed", Event_WitchKilled);
    HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookConVarChange(g_cvEnabled, OnConVarChanged);
    HookConVarChange(g_cvWitchCount, OnConVarChanged);
    HookConVarChange(g_cvBonusPoints, OnConVarChanged);
    HookConVarChange(g_cvWalkChance, OnConVarChanged);
    
    AutoExecConfig(true, "witchmod");
    UpdateCvars();
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    UpdateCvars();
}

void UpdateCvars()
{
    g_bEnabled = g_cvEnabled.BoolValue;
    g_iWitchCount = g_cvWitchCount.IntValue;
    g_iBonusPoints = g_cvBonusPoints.IntValue;
    g_fWalkChance = g_cvWalkChance.FloatValue; // New: Update walk chance
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    g_iWitchesKilled = 0;
    g_iSpawnedWitches = 0;
    
    if (!g_bEnabled || g_iWitchCount <= 0) return;
    
    CreateTimer(5.0, Timer_SpawnWitches, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_SpawnWitches(Handle timer)
{
    if (!g_bEnabled || g_iWitchCount <= 0) return Plugin_Stop;
    
    int currentWitches = CountWitches();
    int witchesNeeded = g_iWitchCount - currentWitches;
    
    for (int i = 0; i < witchesNeeded && g_iSpawnedWitches < g_iWitchCount; i++)
    {
        float spawnPos[3];
        if (FindWitchSpawnPosition(spawnPos))
        {
            SpawnWitch(spawnPos);
            g_iSpawnedWitches++;
        }
    }
    
    return Plugin_Stop;
}

bool FindWitchSpawnPosition(float spawnPos[3])
{
    int spawnEnt = FindRandomEntity(SPAWN_ENTITY);
    if (spawnEnt != -1)
    {
        GetEntPropVector(spawnEnt, Prop_Data, "m_vecOrigin", spawnPos);
        spawnPos[2] += 20.0;
        return IsPositionSafe(spawnPos);
    }
    
    int survivor = GetRandomSurvivor();
    if (survivor != -1)
    {
        GetClientAbsOrigin(survivor, spawnPos);
        spawnPos[0] += GetRandomFloat(-500.0, 500.0);
        spawnPos[1] += GetRandomFloat(-500.0, 500.0);
        spawnPos[2] += 20.0;
        return IsPositionSafe(spawnPos);
    }
    
    return false;
}

void SpawnWitch(const float spawnPos[3])
{
    int witch = CreateEntityByName(WITCH_CLASSNAME);
    if (witch != -1 && IsValidEntity(witch))
    {
        // 40% chance to be a walking witch (angry)
        bool bWalkingWitch = (GetRandomFloat(0.0, 1.0) <= g_fWalkChance;
        
        DispatchKeyValue(witch, "Angry", bWalkingWitch ? "1" : "0");
        DispatchSpawn(witch);
        TeleportEntity(witch, spawnPos, NULL_VECTOR, NULL_VECTOR);
        
        // Optional: Adjust speed for walking witches
        if (bWalkingWitch)
        {
            SetEntPropFloat(witch, Prop_Data, "m_speed", 100.0); // Slower than raging speed
        }
    }
}

int CountWitches()
{
    int count = 0;
    int entity = -1;
    
    while ((entity = FindEntityByClassname(entity, WITCH_CLASSNAME)) != -1)
    {
        if (IsValidEntity(entity))
        {
            count++;
        }
    }
    
    return count;
}

bool IsPositionSafe(const float pos[3])
{
    TR_TraceHullFilter(pos, pos, view_as<float>({-16.0, -16.0, 0.0}), view_as<float>({16.0, 16.0, 72.0}), 
        MASK_PLAYERSOLID, TraceEntityFilterPlayers);
    
    return !TR_DidHit();
}

public bool TraceEntityFilterPlayers(int entity, int contentsMask)
{
    return entity > MaxClients;
}

public void Event_WitchKilled(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bEnabled) return;
    g_iWitchesKilled++;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bEnabled || g_iWitchesKilled == 0) return;
    
    int totalBonus = g_iWitchesKilled * g_iBonusPoints;
    int survivorScore = GetTeamScore(2);
    SetTeamScore(2, survivorScore + totalBonus);
    
    PrintToChatAll("\x04[Witch Mod]\x01 Survivors earned \x05%d\x01 bonus points for killing \x05%d\x01 witches!", totalBonus, g_iWitchesKilled);
}

public void OnMapStart()
{
    g_iWitchesKilled = 0;
    g_iSpawnedWitches = 0;
}

int GetRandomSurvivor()
{
    int clients[MAXPLAYERS+1], count;
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i))
        {
            clients[count++] = i;
        }
    }
    
    return (count > 0) ? clients[GetRandomInt(0, count-1)] : -1;
}

int FindRandomEntity(const char[] classname)
{
    int entity = -1;
    int entities[1024];
    int count;
    
    while ((entity = FindEntityByClassname(entity, classname)) != -1)
    {
        if (IsValidEntity(entity))
        {
            entities[count++] = entity;
        }
    }
    
    return (count > 0) ? entities[GetRandomInt(0, count-1)] : -1;
}
