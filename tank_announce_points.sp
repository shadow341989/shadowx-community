#include <sourcemod>
#include <sdktools>
#include <colors> // Include colors.inc for chat colors
#include <tank_panel> // Include the panel logic

#pragma semicolon 1
#pragma newdecls required

#define ZC_TANK 8

int g_iTankPoints[MAXPLAYERS + 1]; // Points for the tank player
int g_iSurvivorPoints[MAXPLAYERS + 1]; // Points for each survivor
int g_iRocksHit[MAXPLAYERS + 1]; // Number of successful rock hits
int g_iIncapCount[MAXPLAYERS + 1]; // Number of incaps caused by the tank
int g_iObjectHits[MAXPLAYERS + 1]; // Number of object hits
int g_iTankClient = -1; // Client ID of the current tank
bool g_bTankAlive; // Whether the tank is alive
Handle g_hUpdatePanelTimer[MAXPLAYERS + 1]; // Timer for updating the panel
int g_iConsecutiveRocks[MAXPLAYERS + 1]; // Tracks consecutive successful rock hits
bool g_bRockMissed[MAXPLAYERS + 1]; // Tracks if the Tank missed a rock

// List of hittable object weapon names
static const char g_sHittableObjects[][] = {
    "prop_vehicle_driveable", // Cars
    "prop_vehicle_jeep",      // Cars
    "prop_physics",           // Generic physics objects
    "prop_dynamic",           // Dynamic props
    "prop_car_alarm",         // Car alarms
    "models/props_junk/dumpster_2.mdl", // Dumpsters
    "models/props_junk/trashdumpster01.mdl", // Dumpsters
    "models/props_c17/forklift.mdl", // Forklifts
    "models/props_debris/concrete_chunk01a.mdl", // Concrete slabs
    "models/props_debris/concrete_chunk02a.mdl", // Concrete slabs
    "models/props_foliage/tree_trunk_fallen.mdl" // Logs (Hard Rain)
};

public Plugin myinfo =
{
    name = "Tank Points",
    author = "shadowx",
    description = "Tracks and rates tank performance in L4D2.",
    version = "2.0",
    url = "shadowcommunity.us"
};

public void OnPluginStart()
{
    HookEvent("tank_spawn", Event_TankSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("player_hurt", Event_PlayerHurt);
    HookEvent("player_incapacitated", Event_PlayerIncap);
    HookEvent("tank_frustrated", Event_TankFrustrated); // Hook the tank_frustrated event
    HookEvent("weapon_fire", Event_WeaponFire); // Hook weapon_fire to detect rock throws
}

public void OnMapStart()
{
    g_iTankClient = -1;
    g_bTankAlive = false;
    for (int i = 1; i <= MaxClients; i++)
    {
        g_iTankPoints[i] = 0;
        g_iSurvivorPoints[i] = 0;
        g_iRocksHit[i] = 0;
        g_iIncapCount[i] = 0;
        g_iObjectHits[i] = 0;
        g_iConsecutiveRocks[i] = 0;
        g_bRockMissed[i] = false;
        g_hUpdatePanelTimer[i] = null;
    }
}

public void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0 && GetEntProp(client, Prop_Send, "m_zombieClass") == ZC_TANK && g_iTankClient != client)
    {
        g_iTankClient = client;
        g_bTankAlive = true;
        g_hUpdatePanelTimer[client] = CreateTimer(1.0, Timer_UpdatePanel, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
}

public void Event_TankFrustrated(Event event, const char[] name, bool dontBroadcast)
{
    int oldTankClient = g_iTankClient; // Store the previous Tank client
    int newTankClient = GetClientOfUserId(event.GetInt("userid")); // Get the new Tank client

    if (oldTankClient > 0 && oldTankClient <= MaxClients && IsClientInGame(oldTankClient))
    {
        // Print summary for the previous Tank player
        PrintTankSummary(oldTankClient);

        // Reset stats for the previous Tank player
        ResetTankStats(oldTankClient);
    }

    if (newTankClient > 0 && newTankClient <= MaxClients && IsClientInGame(newTankClient))
    {
        // Initialize stats for the new Tank player
        g_iTankClient = newTankClient;
        g_bTankAlive = true;
        g_hUpdatePanelTimer[newTankClient] = CreateTimer(1.0, Timer_UpdatePanel, newTankClient, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client == g_iTankClient)
    {
        g_bTankAlive = false;

        // Print summary for the Tank player
        PrintTankSummary(client);

        // Close the panel immediately
        ClosePanel(client);

        // Reset tank-related variables
        ResetTankStats(client);
    }
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    // Print summary for the Tank player if they are still alive
    if (g_bTankAlive && g_iTankClient > 0 && g_iTankClient <= MaxClients && IsClientInGame(g_iTankClient))
    {
        PrintTankSummary(g_iTankClient);
    }

    // Reset panel and tank-related variables
    for (int i = 1; i <= MaxClients; i++)
    {
        if (g_iTankPoints[i] > 0 && IsClientInGame(i)) // Only reset stats if the Tank had points and is valid
        {
            ResetTankStats(i);
        }
    }
}

void PrintTankSummary(int client)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client))
    {
        LogError("Invalid client index in PrintTankSummary: %d", client);
        return;
    }

    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));

    int tankHP = GetClientHealth(client);
    char rating[32];
    Format(rating, sizeof(rating), "%s", GetRating(g_iTankPoints[client]));

    CPrintToChatAll("{green}%s's Summary", name);
    CPrintToChatAll("----------------");
    CPrintToChatAll("{blue}Total Points: %d", g_iTankPoints[client]);
    CPrintToChatAll("{green}Rating: %s", rating);
    CPrintToChatAll("{blue}Successful Rocks: %d", g_iRocksHit[client]);
    CPrintToChatAll("{green}Remaining HP: %d", tankHP);
}

void ClosePanel(int client)
{
    if (IsClientInGame(client))
    {
        // Send an empty panel to close the existing one
        Panel panel = new Panel();
        panel.DrawItem("", ITEMDRAW_RAWLINE); // Add an empty line
        panel.Send(client, PanelHandler, 1); // Close the panel
        delete panel;
    }
}

void ResetTankStats(int client)
{
    g_iTankPoints[client] = 0;
    g_iSurvivorPoints[client] = 0;
    g_iRocksHit[client] = 0;
    g_iIncapCount[client] = 0;
    g_iObjectHits[client] = 0;
    g_iConsecutiveRocks[client] = 0;
    g_bRockMissed[client] = false;

    if (g_hUpdatePanelTimer[client] != null)
    {
        KillTimer(g_hUpdatePanelTimer[client]);
        g_hUpdatePanelTimer[client] = null;
    }

    g_iTankClient = -1;
    g_bTankAlive = false;
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int victim = GetClientOfUserId(event.GetInt("userid"));
    if (attacker == g_iTankClient && IsSurvivor(victim))
    {
        char weapon[32];
        event.GetString("weapon", weapon, sizeof(weapon));

        if (StrEqual(weapon, "tank_claw"))
        {
            // Only award punch points if the survivor is not incapacitated
            if (!IsPlayerIncapacitated(victim))
            {
                g_iTankPoints[attacker] += 100; // Punch points (changed from 75 to 100)
                g_iSurvivorPoints[victim] += 100; // Add points to the survivor
            }
        }
        else if (StrEqual(weapon, "tank_rock"))
        {
            // Only award rock hit points if the survivor is not incapacitated
            if (!IsPlayerIncapacitated(victim))
            {
                g_iTankPoints[attacker] += 125; // Rock hit points (changed from 100 to 125)
                g_iSurvivorPoints[victim] += 125; // Add points to the survivor
                g_iRocksHit[attacker]++;

                // Increment consecutive rock hits
                g_iConsecutiveRocks[attacker]++;
                if (g_iConsecutiveRocks[attacker] >= 3)
                {
                    g_iTankPoints[attacker] += 250; // Bonus for 3 consecutive rocks
                    CPrintToChat(attacker, "{blue}[!] You have landed 3 successful rocks! +250 points!");
                    g_iConsecutiveRocks[attacker] = 0; // Reset counter after bonus
                }
            }
        }
        else if (IsHittableObject(weapon)) // Check if the weapon is a hittable object
        {
            // Award points for hitting a survivor with a hittable object
            g_iTankPoints[attacker] += 100; // Base points for hitting with a hittable object
            g_iSurvivorPoints[victim] += 100; // Add points to the survivor
            g_iObjectHits[attacker]++; // Increment object hits counter
        }
        else
        {
            LogError("Unknown weapon used by Tank: %s", weapon);
        }
    }
}

public void Event_PlayerIncap(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int victim = GetClientOfUserId(event.GetInt("userid"));
    if (attacker == g_iTankClient && IsSurvivor(victim))
    {
        char weapon[32];
        event.GetString("weapon", weapon, sizeof(weapon));

        if (StrEqual(weapon, "tank_claw"))
        {
            // Punch incap: 100 (punch) + 125 (incap) = 225 total
            g_iTankPoints[attacker] += 125; // Incap bonus points
            g_iSurvivorPoints[victim] += 125; // Add points to the survivor
            g_iIncapCount[attacker]++;

        }
        else if (StrEqual(weapon, "tank_rock"))
        {
            // Rock incap: 125 (rock) + 125 (incap) = 250 total
            g_iTankPoints[attacker] += 125; // Incap bonus points
            g_iSurvivorPoints[victim] += 125; // Add points to the survivor
            g_iIncapCount[attacker]++;

            // Increment successful rock hits and consecutive rock hits
            g_iRocksHit[attacker]++;
            g_iConsecutiveRocks[attacker]++;
            if (g_iConsecutiveRocks[attacker] >= 3)
            {
                g_iTankPoints[attacker] += 250; // Bonus for 3 consecutive rocks
                CPrintToChat(attacker, "{blue}[!] You have landed 3 successful rocks! +250 points!");
                g_iConsecutiveRocks[attacker] = 0; // Reset counter after bonus
            }

        }
        else if (IsHittableObject(weapon)) // Check if the weapon is a hittable object
        {
            // Hittable object incap: 100 (hit) + 300 (incap) = 400 total
            g_iTankPoints[attacker] += 300; // Incap bonus points
            g_iSurvivorPoints[victim] += 300; // Add points to the survivor
            g_iIncapCount[attacker]++;

        }
    }
}

public void Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client == g_iTankClient)
    {
        char weapon[32];
        event.GetString("weapon", weapon, sizeof(weapon));

        if (StrEqual(weapon, "tank_rock"))
        {
            // If the Tank throws a rock, check if the previous rock was missed
            if (g_bRockMissed[client])
            {
                g_iConsecutiveRocks[client] = 0; // Reset consecutive rocks counter
                g_bRockMissed[client] = false; // Reset the missed flag
            }
        }
    }
}

public Action Timer_UpdatePanel(Handle timer, int client)
{
    if (g_bTankAlive && g_iTankClient > 0 && g_iTankClient <= MaxClients && IsClientInGame(g_iTankClient))
    {
        // Display the panel to all infected players and spectators
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && !IsFakeClient(i)) // Ensure the client is valid and not a bot
            {
                int team = GetClientTeam(i);
                if (team == 3 || team == 1) // Infected team (3) or Spectators (1)
                {
                    DisplayTankPanel(i, g_iTankPoints[g_iTankClient], g_iRocksHit[g_iTankClient], GetClientHealth(g_iTankClient));
                }
            }
        }
    }
    return Plugin_Continue;
}

bool IsSurvivor(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2;
}

bool IsPlayerIncapacitated(int client)
{
    return GetEntProp(client, Prop_Send, "m_isIncapacitated") == 1;
}

bool IsHittableObject(const char[] weapon)
{
    for (int i = 0; i < sizeof(g_sHittableObjects); i++)
    {
        if (StrEqual(weapon, g_sHittableObjects[i]))
        {
            return true;
        }
    }
    return false;
}