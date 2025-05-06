#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.0"

Database g_Database = null;

public Plugin myinfo = 
{
    name = "L4D2 Chat Logger",
    author = "Shadowx",
    description = "Logs all chat messages to database (updated for offenses config)",
    version = PLUGIN_VERSION,
    url = "shadowcommunity.us"
};

public void OnPluginStart()
{
    // Connect to database using the EXACT name from databases.cfg
    Database.Connect(SQL_OnConnect, "offenses");
    
    // Hook chat events
    AddCommandListener(Command_Say, "say");
    AddCommandListener(Command_SayTeam, "say_team");
    
    // Create tables if they don't exist
    SQL_CreateTables();
}

public void SQL_OnConnect(Database db, const char[] error, any data)
{
    if (db == null)
    {
        LogError("Database connection failure: %s", error);
        return;
    }
    
    g_Database = db;
    LogMessage("Successfully connected to 'offenses' database");
    
    // Set UTF-8 encoding for proper character support
    g_Database.SetCharset("utf8mb4");
}

void SQL_CreateTables()
{
    char query[1024];
    Format(query, sizeof(query), 
        "CREATE TABLE IF NOT EXISTS chat_logs ( \
            id INT AUTO_INCREMENT PRIMARY KEY, \
            timestamp INT NOT NULL, \
            player_name VARCHAR(128) NOT NULL, \
            steamid VARCHAR(32) NOT NULL, \
            message TEXT NOT NULL, \
            server_ip VARCHAR(32) NOT NULL, \
            team_message BOOLEAN NOT NULL, \
            INDEX(steamid), \
            INDEX(timestamp) \
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    );
    
    if (g_Database != null)
    {
        g_Database.Query(SQL_CheckForError, query);
    }
    else
    {
        CreateTimer(5.0, Timer_RetryConnection);
    }
}

public Action Timer_RetryConnection(Handle timer)
{
    Database.Connect(SQL_OnConnect, "offenses");
    return Plugin_Stop;
}

public void SQL_CheckForError(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0])
    {
        LogError("SQL Error: %s", error);
    }
}

public Action Command_Say(int client, const char[] command, int argc)
{
    if (client == 0) return Plugin_Continue;
    
    char message[256];
    GetCmdArgString(message, sizeof(message));
    StripQuotes(message);
    
    if (strlen(message) == 0) return Plugin_Continue;
    
    LogChatMessage(client, message, false);
    return Plugin_Continue;
}

public Action Command_SayTeam(int client, const char[] command, int argc)
{
    if (client == 0) return Plugin_Continue;
    
    char message[256];
    GetCmdArgString(message, sizeof(message));
    StripQuotes(message);
    
    if (strlen(message) == 0) return Plugin_Continue;
    
    LogChatMessage(client, message, true);
    return Plugin_Continue;
}

void LogChatMessage(int client, const char[] message, bool teamMessage)
{
    if (g_Database == null || !IsClientInGame(client)) return;
    
    char steamId[32];
    if (!GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId), true))
    {
        strcopy(steamId, sizeof(steamId), "UNKNOWN");
    }
    
    char playerName[MAX_NAME_LENGTH];
    GetClientName(client, playerName, sizeof(playerName));
    
    char serverIP[32];
    int ip = FindConVar("hostip").IntValue;
    Format(serverIP, sizeof(serverIP), "%d.%d.%d.%d", 
        (ip >> 24) & 0xFF, (ip >> 16) & 0xFF, (ip >> 8) & 0xFF, ip & 0xFF);
    
    char escapedName[MAX_NAME_LENGTH * 2 + 1];
    char escapedMessage[512];
    
    g_Database.Escape(playerName, escapedName, sizeof(escapedName));
    g_Database.Escape(message, escapedMessage, sizeof(escapedMessage));
    
    char query[1024];
    Format(query, sizeof(query), 
        "INSERT INTO chat_logs (timestamp, player_name, steamid, message, server_ip, team_message) \
        VALUES (%d, '%s', '%s', '%s', '%s', %d)",
        GetTime(), escapedName, steamId, escapedMessage, serverIP, teamMessage);
    
    g_Database.Query(SQL_CheckForError, query);
}