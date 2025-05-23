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
#define ZC_TANK 8 // Tank class ID
#define PARDON_TIME 15 // Time in seconds to wait for pardon

Database g_sbDb; // For sourcebans
Database g_offensesDb; // For offenses
int g_iSuicideClient;
bool g_bPardonInProgress;
Handle g_hPardonTimer;
bool g_bRoundEnded = false; // Track if the round has ended
float g_fTankPunchTime[MAXPLAYERS + 1]; // Track the last time a survivor was punched by a Tank

// Track the last attacker and damage type for each player
int g_iLastAttacker[MAXPLAYERS + 1];
char g_sLastDamageType[MAXPLAYERS + 1][64];

// Immunity variables
bool g_bIsImmune[MAXPLAYERS + 1]; // Track if the player is immune
float g_fLastKeyPressTime[MAXPLAYERS + 1]; // Track the last time the player pressed SPACE

// Tiered ban system variables
StringMap g_smPlayerOffenses; // Store player offenses and probation end times

public Plugin myinfo = {
    name = "Auto Suicide Ban",
    author = "shadowx",
    description = "Automatically bans players for suicide after a pardon period.",
    version = "2.8", // Updated version
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

    // Hook player death event
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);

    // Hook round start and end events to reset states
    HookEvent("round_start", Event_RoundStart, EventHookMode_Post);
    HookEvent("round_end", Event_RoundEnd, EventHookMode_Post);

    // Hook player team change event to handle team switches
    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);

    // Add the new command to remove player offenses
    RegAdminCmd("sm_removeplayeroffense", Command_RemovePlayerOffense, ADMFLAG_BAN, "Removes a player's offenses from the database.");

    // Add the new command to reload the offenses from the database
    RegAdminCmd("sm_reload_autoban", Command_ReloadAutoBan, ADMFLAG_BAN, "Reloads the offenses from the database.");

    // Register pardon command
    RegConsoleCmd("sm_pardon", Command_Pardon, "Pardon a player from being banned for suicide.");

    // Create a repeating timer to reload offenses every 1 minute (60 seconds)
    CreateTimer(60.0, Timer_ReloadOffenses, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ReloadOffenses(Handle timer)
{
    // Reload offenses from the database
    LoadPlayerOffenses();
    PrintToServer("[AutoBan] Offenses reloaded from the database.");
    return Plugin_Continue;
}

public void OnPluginEnd()
{
    // Save offenses to the database when the plugin ends
    SavePlayerOffenses();
}

public void OnClientPutInServer(int client)
{
    // Hook damage events for new clients
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);

    // Initialize immunity state for new clients
    g_bIsImmune[client] = true;
    g_fLastKeyPressTime[client] = 0.0;
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
    // Track the last attacker and damage type
    if (IsValidClient(attacker))
    {
        g_iLastAttacker[victim] = attacker;
        GetEdictClassname(inflictor, g_sLastDamageType[victim], sizeof(g_sLastDamageType[]));

        // Check if the attacker is a Tank (human or bot) and the damage is from a punch
        if (GetEntProp(attacker, Prop_Send, "m_zombieClass") == ZC_TANK && 
            (StrContains(g_sLastDamageType[victim], "tank_claw") != -1 || StrContains(g_sLastDamageType[victim], "tank_rock") != -1))
        {
            g_fTankPunchTime[victim] = GetGameTime(); // Record the time of the Tank punch
        }
    }
    else
    {
        g_iLastAttacker[victim] = -1;
        g_sLastDamageType[victim][0] = '\0';
    }

    return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    if (!IsValidClient(client) || !IsPlayerSurvivor(client))
    {
        return Plugin_Continue;
    }

    // Check if the player is pressing SPACE (jump)
    bool bPressingKey = (buttons & IN_JUMP) != 0; // Only check for SPACE (jump)

    if (bPressingKey)
    {
        // Player is pressing SPACE, remove immunity
        g_bIsImmune[client] = false;
        g_fLastKeyPressTime[client] = GetGameTime(); // Update the last key press time
    }
    else
    {
        // Player is not pressing SPACE, check if 3 seconds have passed since the last key press
        if (GetGameTime() - g_fLastKeyPressTime[client] >= 3.0)
        {
            g_bIsImmune[client] = true; // Grant immunity
        }
    }

    return Plugin_Continue;
}

public void OnMapStart()
{
    g_bPardonInProgress = false;
    g_bRoundEnded = false; // Reset round end state on map start

    // Reset last attacker and damage type tracking
    for (int i = 1; i <= MaxClients; i++)
    {
        g_iLastAttacker[i] = -1;
        g_sLastDamageType[i][0] = '\0';
        g_fTankPunchTime[i] = 0.0; // Reset Tank punch time
        g_bIsImmune[i] = true; // Grant immunity at map start
        g_fLastKeyPressTime[i] = 0.0; // Reset key press time
    }

    // Load offenses when the map starts
    LoadPlayerOffenses();
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    // Reset pardon state at the start of each round
    g_bPardonInProgress = false;
    g_bRoundEnded = false; // Round has started, immunity is lifted

    // Reset last attacker and damage type tracking
    for (int i = 1; i <= MaxClients; i++)
    {
        g_iLastAttacker[i] = -1;
        g_sLastDamageType[i][0] = '\0';
        g_bIsImmune[i] = true; // Grant immunity at the start of the round
        g_fLastKeyPressTime[i] = 0.0; // Reset key press time
    }
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    // Reset pardon state at the end of each round
    g_bPardonInProgress = false;
    g_bRoundEnded = true; // Round has ended, immunity is active
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    // Reset pardon state if the player changes teams
    g_bPardonInProgress = false;
}

public void OnClientDisconnect(int client)
{
    // Check if the disconnected player is the suicide client and a pardon is in progress
    if (client == g_iSuicideClient && g_bPardonInProgress)
    {
        // Auto-ban the player if they disconnect during the pardon period
        BanSuicidePlayer(client);
        g_bPardonInProgress = false; // Reset pardon state
        
        // Clean up the timer if it exists
        if (g_hPardonTimer != null)
        {
            delete g_hPardonTimer;
            g_hPardonTimer = null;
        }
    }
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    // Check if the round has ended (immunity is active)
    if (g_bRoundEnded)
    {
        return;
    }

    int client = GetClientOfUserId(event.GetInt("userid"));

    // Check if the client is valid and a survivor
    if (!IsValidClient(client))
    {
        return;
    }

    if (!IsPlayerSurvivor(client))
    {
        return;
    }

    // Check if the survivor is immune due to not pressing SPACE for 3 seconds
    if (g_bIsImmune[client])
    {
        return; // Immune from being banned
    }

    // Check if the survivor is immune due to a recent Tank punch
    if (GetGameTime() - g_fTankPunchTime[client] < 4.0)
    {
        return; // Immune from being banned
    }

    char deathString[64];
    event.GetString("weapon", deathString, sizeof(deathString));

    // Check if death was caused by special infected or common infected
    if (StrContains(deathString, "witch") != -1 ||
        StrContains(deathString, "tank") != -1 ||
        StrContains(deathString, "charger") != -1 ||
        StrContains(deathString, "hunter") != -1 ||
        StrContains(deathString, "smoker") != -1 ||
        StrContains(deathString, "spitter") != -1 ||
        StrContains(deathString, "boomer") != -1 ||
        StrContains(deathString, "common") != -1 ||
        StrContains(deathString, "jockey") != -1)
    {
        return; // Ignore deaths caused by special/common infected
    }

    // Check if the player committed suicide (including water deaths)
    if ((StrContains(deathString, "world") != -1 || StrContains(deathString, "water") != -1 || StrContains(deathString, "drowning") != -1 || StrContains(deathString, "suicide") != -1 || StrContains(deathString, "trigger_hurt") != -1))
    {
        // Check if the death was caused by environmental damage from a special infected
        if (g_iLastAttacker[client] != -1 && IsPlayerInfected(g_iLastAttacker[client]))
        {
            return; // Ignore environmental deaths caused by special infected
        }

        g_iSuicideClient = client;

        // Check the number of survivors and handle the pardon or auto-ban accordingly
        int survivorCount = GetSurvivorCount();

        if (survivorCount == 1)
        {
            // Auto-ban if the victim is the only survivor
            BanSuicidePlayer(client);
        }
        else
        {
            // Start pardon period for other survivors
            StartPardonPeriod(client);
        }
    }
}

void StartPardonPeriod(int client)
{
    if (g_bPardonInProgress)
    {
        return;
    }

    g_bPardonInProgress = true;

    char playerName[MAX_NAME_LENGTH];
    GetClientName(client, playerName, sizeof(playerName));

    // Display pardon message to other survivors (not the victim)
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i) && IsPlayerSurvivor(i) && i != client)
        {
            CPrintToChat(i, "{green}Player %s has committed suicide, if this was a accident please type {blue}!pardon {green}(if no one types !pardon player will be banned in 15 secs)", playerName);
        }
    }

    // Start pardon timer
    g_hPardonTimer = CreateTimer(float(PARDON_TIME), Timer_PardonTimeout, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Command_Pardon(int client, int args)
{
    if (!g_bPardonInProgress || !IsPlayerSurvivor(client) || client == g_iSuicideClient)
    {
        return Plugin_Handled;
    }

    char playerName[MAX_NAME_LENGTH];
    GetClientName(g_iSuicideClient, playerName, sizeof(playerName));

    // Cancel the ban
    CPrintToChatAll("{green}Ban for Player %s has been canceled.", playerName);
    g_bPardonInProgress = false;

    // Clean up the timer if it exists
    if (g_hPardonTimer != null)
    {
        delete g_hPardonTimer;
        g_hPardonTimer = null;
    }

    return Plugin_Handled;
}

public Action Timer_PardonTimeout(Handle timer)
{
    if (g_bPardonInProgress)
    {
        // No one pardoned, ban the player
        BanSuicidePlayer(g_iSuicideClient);
        g_bPardonInProgress = false;
        g_hPardonTimer = null;
    }
    return Plugin_Stop;
}

int GetSurvivorCount()
{
    int count = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsPlayerSurvivor(i))
        {
            count++;
        }
    }
    return count;
}

bool IsPlayerInfected(int client)
{
    // Check if the client is valid and on the infected team (team 3)
    return IsValidClient(client) && GetClientTeam(client) == 3;
}

// Function to find the smallest available ID
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

void BanSuicidePlayer(int client)
{
    // Check if the round has ended (immunity is active)
    if (g_bRoundEnded)
    {
        return;
    }

    if (!IsValidClient(client))
    {
        return;
    }

    char steamId[64], playerName[MAX_NAME_LENGTH];
    GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId));
    GetClientName(client, playerName, sizeof(playerName));

    int offenses = 0;
    int probationEndTime = 0;
    int offenseData[2]; // Renamed to avoid shadowing warning

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
    ExecuteBanQuery(steamId, playerName, "Suicide", banDuration);

    // Log the ban event to the auto_ban_logs table
    LogBanEvent(steamId, playerName);

    // Announce ban to all players
    CPrintToChatAll("{Green}[Auto ban] The %s has been banned for %s due to suiciding.", playerName, banDurationStr);

    // Ban the player
    char banMessage[256];
    Format(banMessage, sizeof(banMessage), "You have been banned for suiciding for %s. If you feel like this was a mistake feel free to appeal it at https://shadowcommunity.us/bans/index.php?p=protest", banDurationStr);
    BanClient(client, banDuration, BANFLAG_AUTO, "Suicide", banMessage);
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

    // Check if the client is in the game and not a bot
    return IsClientInGame(client) && !IsFakeClient(client);
}

bool IsPlayerSurvivor(int client)
{
    // Check if the client is valid and on the survivor team (team 2)
    return IsValidClient(client) && GetClientTeam(client) == 2;
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
        int offenseData[2]; // Renamed to avoid shadowing warning
        offenseData[0] = offenses;
        offenseData[1] = probationEndTime;
        g_smPlayerOffenses.SetArray(steamId, offenseData, sizeof(offenseData));
    }
}

void SavePlayerOffenses()
{
    StringMapSnapshot snapshot = g_smPlayerOffenses.Snapshot();
    char steamId[64];
    int offenseData[2]; // Renamed to avoid shadowing warning

    for (int i = 0; i < snapshot.Length; i++)
    {
        snapshot.GetKey(i, steamId, sizeof(steamId));
        g_smPlayerOffenses.GetArray(steamId, offenseData, sizeof(offenseData));

        // Insert or update the player's offenses in the auto_ban_offenses table
        char query[QUERY_BUFFER_SIZE];
        Format(query, sizeof(query),
            "INSERT INTO auto_ban_offenses (steamid, offenses, probation_end_time) VALUES ('%s', %d, %d) " ...
            "ON DUPLICATE KEY UPDATE offenses = %d, probation_end_time = %d",
            steamId, offenseData[0], offenseData[1], offenseData[0], offenseData[1]);

        g_offensesDb.Query(OnSavePlayerOffenses, query);
    }

    delete snapshot;
}

public void OnSavePlayerOffenses(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("Failed to save player offenses: %s", error);
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
