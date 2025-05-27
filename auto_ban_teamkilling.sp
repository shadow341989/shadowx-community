#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <colors>

#define FIRST_OFFENSE_BAN_DURATION 10080 // 1 week in minutes
#define SECOND_OFFENSE_BAN_DURATION 43200 // 1 month in minutes
#define PROBATION_PERIOD 129600 // 90 days in minutes
#define QUERY_BUFFER_SIZE 1024
#define TEAMKILL_TIMER_DURATION 9.0 // Time window to track teamkilling damage (9 seconds)
#define RESET_TIMER_DURATION 3.0 // Time to reset the timer if no damage is dealt (3 seconds)
#define FIRE_DAMAGE_IMMUNITY_DURATION 12.0 // Immunity lasts for 12 seconds after last fire damage

Database g_sbDb; // For sourcebans
Database g_offensesDb; // For offenses
StringMap g_smPlayerOffenses; // Store player offenses and probation end times

// Track teamkilling damage
float g_fTeamKillDamage[MAXPLAYERS + 1]; // Total damage dealt by player [attacker]
float g_fTeamKillTimer[MAXPLAYERS + 1]; // Timer to track teamkilling damage
float g_fLastDamageTime[MAXPLAYERS + 1]; // Last time the player dealt damage
Handle g_hTeamKillTimer[MAXPLAYERS + 1]; // Handle for the teamkilling timer

// Track special infected attacks and fire damage
bool g_bIsSurvivorTeamImmune = false; // Whether the survivor team is immune to friendly fire
int g_iSpecialInfectedAttacker[MAXPLAYERS + 1]; // Track which special infected is attacking a survivor
bool g_bIsOnFire[MAXPLAYERS + 1]; // Track if a survivor is on fire
float g_fLastFireDamageTime = 0.0; // Track the last time fire damage was dealt

public Plugin myinfo = {
    name = "Auto Ban Teamkiller",
    author = "shadowx",
    description = "Automatically bans players for teamkilling.",
    version = "1.4.3", // Updated version
    url = "https://shadowcommunity.us"
};

public void OnPluginStart()
{
    // Initialize the StringMap to store player offenses
    g_smPlayerOffenses = new StringMap();

    // Initialize database connections
    char error[128];

    // Connect to the offenses database
    g_offensesDb = SQL_Connect("offenses", true, error, sizeof(error));
    if (g_offensesDb == null)
    {
        LogError("Failed to connect to offenses database: %s", error);
    }
    else
    {
        PrintToServer("Connected to offenses database.");
    }

    // Connect to the sourcebans database
    g_sbDb = SQL_Connect("sourcebans", true, error, sizeof(error));
    if (g_sbDb == null)
    {
        LogError("Failed to connect to sourcebans database: %s", error);
    }
    else
    {
        PrintToServer("Connected to sourcebans database.");
    }

    // Load existing offenses from the database
    LoadPlayerOffenses();

    // Hook player damage event
    HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);

    // Hook special infected attack events
    HookEvent("lunge_pounce", Event_SpecialInfectedAttack); // Hunter pounce
    HookEvent("jockey_ride", Event_SpecialInfectedAttack); // Jockey ride
    HookEvent("charger_pummel_start", Event_SpecialInfectedAttack); // Charger pummel
    HookEvent("tongue_grab", Event_SpecialInfectedAttack); // Smoker grab

    // Hook player death and spawn events
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("player_spawn", Event_PlayerSpawn);

    // Add the new command to remove player offenses
    RegAdminCmd("sm_removeplayeroffense", Command_RemovePlayerOffense, ADMFLAG_BAN, "Removes a player's offenses from the database.");

    // Add the new command to reload the offenses from the database
    RegAdminCmd("sm_reload_autoban", Command_ReloadAutoBan, ADMFLAG_BAN, "Reloads the offenses from the database.");

    // Add a repeating timer to check for immunity expiry
    CreateTimer(1.0, Timer_CheckImmunity, _, TIMER_REPEAT);
}

public void OnClientPutInServer(int client)
{
    // Reset teamkilling damage data for the new client
    g_fTeamKillDamage[client] = 0.0;
    g_fTeamKillTimer[client] = 0.0;
    g_fLastDamageTime[client] = 0.0;

    // Reset special infected attack and fire damage tracking
    g_iSpecialInfectedAttacker[client] = 0;
    g_bIsOnFire[client] = false;

    // Hook damage events for new clients
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client)
{
    if (IsValidClient(client))
    {
        // Reset teamkilling data for the disconnected client
        g_fTeamKillDamage[client] = 0.0;
        g_fTeamKillTimer[client] = 0.0;
        g_fLastDamageTime[client] = 0.0;
        g_hTeamKillTimer[client] = null;

        g_iSpecialInfectedAttacker[client] = 0;
        g_bIsOnFire[client] = false;
    }
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
    // Check if the survivor team is immune to friendly fire
    if (g_bIsSurvivorTeamImmune && IsPlayerSurvivor(victim) && IsPlayerSurvivor(attacker) && attacker != victim)
    {
        return Plugin_Handled; // Block friendly fire damage
    }

    // Check if the attacker is a valid client and the victim is a survivor (bot or client)
    if (IsValidClient(attacker) && IsPlayerSurvivor(attacker) && IsPlayerSurvivor(victim) && attacker != victim)
    {
        // Track teamkilling damage
        g_fTeamKillDamage[attacker] += damage;
        g_fLastDamageTime[attacker] = GetGameTime();

        // Start or resume the teamkilling timer
        if (g_hTeamKillTimer[attacker] == null)
        {
            g_fTeamKillTimer[attacker] = GetGameTime();
            g_hTeamKillTimer[attacker] = CreateTimer(0.1, Timer_CheckTeamKill, attacker, TIMER_REPEAT);
        }
    }

    return Plugin_Continue;
}

public void Event_SpecialInfectedAttack(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("victim"));
    int attacker = GetClientOfUserId(event.GetInt("userid"));

    if (IsValidClient(victim) && IsPlayerSurvivor(victim) && IsValidClient(attacker) && IsPlayerInfected(attacker))
    {
        // Track the special infected attacker
        g_iSpecialInfectedAttacker[victim] = attacker;

        // Enable survivor team immunity
        EnableSurvivorTeamImmunity();
    }
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (IsValidClient(client) && IsPlayerInfected(client))
    {
        // Check if the dead infected was attacking a survivor
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsValidClient(i) && IsPlayerSurvivor(i) && g_iSpecialInfectedAttacker[i] == client)
            {
                g_iSpecialInfectedAttacker[i] = 0;

                // Check if survivor team immunity should be disabled
                DisableSurvivorTeamImmunity();
            }
        }
    }
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (IsValidClient(client) && IsPlayerInfected(client))
    {
        // Check if the spawned infected was attacking a survivor
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsValidClient(i) && IsPlayerSurvivor(i) && g_iSpecialInfectedAttacker[i] == client)
            {
                g_iSpecialInfectedAttacker[i] = 0;

                // Check if survivor team immunity should be disabled
                DisableSurvivorTeamImmunity();
            }
        }
    }
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int damageType = event.GetInt("type");

    // Check if the damage is fire damage (DMG_BURN)
    if (damageType & DMG_BURN)
    {
        if (IsValidClient(victim) && IsPlayerSurvivor(victim))
        {
            // Track that the survivor is on fire
            g_bIsOnFire[victim] = true;

            // Update the last fire damage time
            g_fLastFireDamageTime = GetGameTime();

            // Enable survivor team immunity
            EnableSurvivorTeamImmunity();
        }
    }
    else
    {
        // Check if the survivor is no longer on fire
        if (IsValidClient(victim) && IsPlayerSurvivor(victim) && g_bIsOnFire[victim])
        {
            g_bIsOnFire[victim] = false;

            // Check if survivor team immunity should be disabled
            DisableSurvivorTeamImmunity();
        }
    }
}

void EnableSurvivorTeamImmunity()
{
    if (!g_bIsSurvivorTeamImmune)
    {
        g_bIsSurvivorTeamImmune = true;
    }
}

void DisableSurvivorTeamImmunity()
{
    // Check if any survivor is still being attacked or on fire
    bool shouldDisable = true;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i) && IsPlayerSurvivor(i))
        {
            if (g_iSpecialInfectedAttacker[i] != 0 || g_bIsOnFire[i])
            {
                shouldDisable = false;
                break;
            }
        }
    }

    // Check if 12 seconds have passed since the last fire damage
    if (shouldDisable && g_bIsSurvivorTeamImmune)
    {
        if (GetGameTime() - g_fLastFireDamageTime >= FIRE_DAMAGE_IMMUNITY_DURATION)
        {
            g_bIsSurvivorTeamImmune = false;
        }
    }
}

public Action Timer_CheckImmunity(Handle timer)
{
    // Check if immunity should be disabled
    DisableSurvivorTeamImmunity();
    return Plugin_Continue;
}

public Action Timer_CheckTeamKill(Handle timer, int attacker)
{
    // Check if the attacker is still dealing damage
    if (GetGameTime() - g_fLastDamageTime[attacker] <= RESET_TIMER_DURATION)
    {
        // Check if the timer has exceeded the teamkill duration
        if (GetGameTime() - g_fTeamKillTimer[attacker] >= TEAMKILL_TIMER_DURATION)
        {
            // Ban the teamkiller
            BanTeamKiller(attacker);
            return Plugin_Stop;
        }
    }
    else
    {
        // Reset the timer and damage counter if no damage is dealt for 3 seconds
        g_fTeamKillDamage[attacker] = 0.0;
        g_fTeamKillTimer[attacker] = 0.0;
        g_fLastDamageTime[attacker] = 0.0;
        g_hTeamKillTimer[attacker] = null;

        return Plugin_Stop;
    }

    return Plugin_Continue;
}

int FindSmallestAvailableId(Database db)
{
    char query[QUERY_BUFFER_SIZE];
    Format(query, sizeof(query), "SELECT MIN(t1.id + 1) AS next_id FROM auto_ban_offenses t1 LEFT JOIN auto_ban_offenses t2 ON t1.id + 1 = t2.id WHERE t2.id IS NULL");

    DBResultSet results = SQL_Query(db, query);
    if (results == null)
    {
        char error[255];
        SQL_GetError(db, error, sizeof(error));
        LogError("Failed to query for smallest available ID: %s", error);
        return 1; // Default to 1 if the query fails
    }

    int nextId = 1;
    if (results.FetchRow())
    {
        nextId = results.FetchInt(0);
    }

    delete results;
    return nextId;
}

void BanTeamKiller(int client)
{
    // Check if the client is valid and not a bot
    if (!IsValidClient(client) || IsFakeClient(client))
    {
        return;
    }

    char steamId[64], playerName[MAX_NAME_LENGTH];
    GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId));
    GetClientName(client, playerName, sizeof(playerName));

    int offenses = 0;
    int probationEndTime = 0;
    int offenseData[2];

    if (g_smPlayerOffenses.GetArray(steamId, offenseData, sizeof(offenseData)))
    {
        offenses = offenseData[0];
        probationEndTime = offenseData[1];
    }

    int currentTime = GetTime();
    if (currentTime < probationEndTime)
    {
        // Player is still on probation
        offenses++;
    }
    else
    {
        // Probation period is over, reset offenses
        offenses = 1;
    }

    // Update probation end time
    probationEndTime = currentTime + (PROBATION_PERIOD * 60);

    // Determine ban duration based on offenses
    int banDuration = FIRST_OFFENSE_BAN_DURATION;
    char banDurationStr[32] = "1 week";

    if (offenses == 2)
    {
        banDuration = SECOND_OFFENSE_BAN_DURATION;
        banDurationStr = "1 month";
    }
    else if (offenses >= 3)
    {
        banDuration = 0; // Permanent ban
        banDurationStr = "permanent";
    }

    // Find the smallest available ID
    int nextId = FindSmallestAvailableId(g_offensesDb);

    // Update offenses and probation end time in the database
    char query[QUERY_BUFFER_SIZE];
    Format(query, sizeof(query),
        "INSERT INTO auto_ban_offenses (id, steamid, offenses, probation_end_time) VALUES (%d, '%s', %d, %d) " ...
        "ON DUPLICATE KEY UPDATE offenses = %d, probation_end_time = %d",
        nextId, steamId, offenses, probationEndTime, offenses, probationEndTime);

    g_offensesDb.Query(OnUpdatePlayerOffenses, query);

    // Log ban to database
    ExecuteBanQuery(steamId, playerName, "Team Killing", banDuration);

    // Log the ban event to the auto_ban_logs table
    LogBanEvent(steamId, playerName);

    // Announce ban to all players
    CPrintToChatAll("{Green}[Auto ban] The %s has been banned for %s due to Team Killing.", playerName, banDurationStr);

    // Ban the player
    char banMessage[256];
    Format(banMessage, sizeof(banMessage), "You have been banned for Team Killing for %s. If you feel like this was a mistake feel free to appeal it at https://shadowcommunity.us/bans/index.php?p=protest", banDurationStr);
    BanClient(client, banDuration, BANFLAG_AUTO, "Team Killing", banMessage);
}

void LogBanEvent(const char[] steamId, const char[] playerName)
{
    char mapName[128];
    GetCurrentMap(mapName, sizeof(mapName));

    // Get the server's IP address
    char serverIp[32];
    int hostip = FindConVar("hostip").IntValue;
    Format(serverIp, sizeof(serverIp), "%d.%d.%d.%d",
        (hostip >> 24) & 0xFF,
        (hostip >> 16) & 0xFF,
        (hostip >> 8) & 0xFF,
        hostip & 0xFF);

    // Insert the log into the database
    char query[QUERY_BUFFER_SIZE];
    Format(query, sizeof(query),
        "INSERT INTO auto_ban_logs (player_name, steamid, map_name, server_ip) VALUES ('%s', '%s', '%s', '%s')",
        playerName, steamId, mapName, serverIp);

    g_offensesDb.Query(OnLogBanEvent, query);
}

public void OnLogBanEvent(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("Failed to log ban event: %s", error);
    }
}

public void OnUpdatePlayerOffenses(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("Failed to update player offenses: %s", error);
    }
}

void ExecuteBanQuery(const char[] steamId, const char[] playerName, const char[] reason, int banDuration)
{
    char query[QUERY_BUFFER_SIZE];
    int banDurationInSeconds = banDuration * 60;

    char escapedSteamId[64], escapedPlayerName[128], escapedReason[128];
    SQL_EscapeString(g_sbDb, steamId, escapedSteamId, sizeof(escapedSteamId));
    SQL_EscapeString(g_sbDb, playerName, escapedPlayerName, sizeof(escapedPlayerName));
    SQL_EscapeString(g_sbDb, reason, escapedReason, sizeof(escapedReason));

    SQL_FormatQuery(g_sbDb, query, sizeof(query), "INSERT INTO sb_bans (authid, name, created, ends, length, reason, aid, sid, type) VALUES ('%s', '%s', UNIX_TIMESTAMP(), UNIX_TIMESTAMP() + %d, %d, '%s', 0, 0, 0)",
        escapedSteamId, escapedPlayerName, banDurationInSeconds, banDurationInSeconds, escapedReason);

    SQL_TQuery(g_sbDb, OnQueryExecuted, query);
}

public void OnQueryExecuted(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("Failed to execute ban query: %s", error);
    }
}

bool IsValidClient(int client)
{
    // Check if the client index is valid
    if (client <= 0 || client > MaxClients)
    {
        return false;
    }

    // Check if the client is in the game
    return IsClientInGame(client);
}

bool IsPlayerSurvivor(int client)
{
    // Check if the client is valid and on the survivor team (team 2)
    return IsValidClient(client) && GetClientTeam(client) == 2;
}

bool IsPlayerInfected(int client)
{
    // Check if the client is valid and on the infected team (team 3)
    return IsValidClient(client) && GetClientTeam(client) == 3;
}

void LoadPlayerOffenses()
{
    char query[QUERY_BUFFER_SIZE];
    Format(query, sizeof(query), "SELECT steamid, offenses, probation_end_time FROM auto_ban_offenses");

    g_offensesDb.Query(OnLoadPlayerOffenses, query);
}

public void OnLoadPlayerOffenses(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("Failed to load player offenses: %s", error);
        return;
    }

    while (results.FetchRow())
    {
        char steamId[64];
        results.FetchString(0, steamId, sizeof(steamId));
        int offenses = results.FetchInt(1);
        int probationEndTime = results.FetchInt(2);

        // Store the data in the StringMap
        int offenseData[2];
        offenseData[0] = offenses;
        offenseData[1] = probationEndTime;
        g_smPlayerOffenses.SetArray(steamId, offenseData, sizeof(offenseData));
    }
}

// Command to remove a player's offenses
public Action Command_RemovePlayerOffense(int client, int args)
{
    if (args < 1)
    {
        ReplyToCommand(client, "[SM] Usage: sm_removeplayeroffense <steamid>");
        return Plugin_Handled;
    }

    char steamId[64];
    GetCmdArgString(steamId, sizeof(steamId)); // Use GetCmdArgString to retrieve the full argument

    // Trim any leading/trailing whitespace from the SteamID
    TrimString(steamId);

    // Validate the SteamID format (basic check)
    if (StrContains(steamId, "STEAM_") != 0)
    {
        ReplyToCommand(client, "[SM] Invalid SteamID format. Please provide a valid SteamID.");
        return Plugin_Handled;
    }

    // Remove the player's offenses
    if (RemovePlayerOffense(steamId))
    {
        ReplyToCommand(client, "[SM] Successfully removed offenses for SteamID: %s", steamId);
    }
    else
    {
        ReplyToCommand(client, "[SM] No offenses found for SteamID: %s", steamId);
    }

    return Plugin_Handled;
}

// Function to remove a player's offenses
bool RemovePlayerOffense(const char[] steamId)
{
    // Remove the player's offenses from the auto_ban_offenses table
    char query[QUERY_BUFFER_SIZE];
    Format(query, sizeof(query), "DELETE FROM auto_ban_offenses WHERE steamid = '%s'", steamId);

    g_offensesDb.Query(OnRemovePlayerOffense, query);

    // Remove the player's offenses from the StringMap
    return g_smPlayerOffenses.Remove(steamId);
}

public void OnRemovePlayerOffense(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("Failed to remove player offenses: %s", error);
    }
}

// Command to reload the offenses from the database
public Action Command_ReloadAutoBan(int client, int args)
{
    LoadPlayerOffenses();
    ReplyToCommand(client, "[SM] Reloaded offenses from the database.");
    return Plugin_Handled;
}