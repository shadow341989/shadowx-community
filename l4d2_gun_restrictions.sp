#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

// Maximum allowed instances of each weapon
#define MAX_AK47 2
#define MAX_SNIPER 2

// Global counters for each weapon type
int g_AK47Count = 0;
int g_SniperCount = 0;

// Array to store the restricted weapons (by entity name)
char RestrictedWeapons[][] = {
    "weapon_rifle_ak47",
    "weapon_sniper_military"
};

public Plugin:myinfo =
{
    name        = "L4D2 Gun Restrictions",
    author      = "shadowx",
    description = "Restricts usage of certain weapons in L4D2",
    version     = "1.4",
    url         = "https://example.com"
};

public void OnPluginStart()
{
    // Hook events
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Post);
    
    // Hook SDK functions for weapon equip and drop
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            SDKHook(i, SDKHook_WeaponCanUse, OnWeaponCanUse);
        }
    }
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    UpdateWeaponCounts();
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    SDKHook(client, SDKHook_WeaponCanUse, OnWeaponCanUse);
    return Plugin_Continue;  
}

public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    SDKUnhook(client, SDKHook_WeaponCanUse, OnWeaponCanUse);
    UpdateWeaponCounts();
    return Plugin_Continue;  
}

public Action OnWeaponCanUse(int client, int weapon)
{
    static float fLastMessageTime[MAXPLAYERS + 1];
    
    char weaponClassname[64];
    GetEntityClassname(weapon, weaponClassname, sizeof(weaponClassname));
    
    for (int i = 0; i < sizeof(RestrictedWeapons); i++)
    {
        if (StrEqual(weaponClassname, RestrictedWeapons[i], false))
        {
            // Update the weapon count
            UpdateWeaponCounts();
            
            // Check if the player already has the weapon
            char currentWeapon[64];
            GetClientWeapon(client, currentWeapon, sizeof(currentWeapon));
            if (StrEqual(currentWeapon, weaponClassname))
            {
                // Allow the player to pick up another instance of the weapon
                return Plugin_Continue;
            }
            
            // Check if the weapon count exceeds the limit
            if ((StrEqual(weaponClassname, "weapon_rifle_ak47") && g_AK47Count >= MAX_AK47) ||
                (StrEqual(weaponClassname, "weapon_sniper_military") && g_SniperCount >= MAX_SNIPER))
            {
                // Prevent the client from using the restricted weapon
                if (GetGameTime() - fLastMessageTime[client] > 5.0)
                {
                    PrintToChat(client, "\x04[Server]\x01 This weapon has reached it's limit 2/2.");
                    fLastMessageTime[client] = GetGameTime();
                }
                return Plugin_Handled;
            }
        }
    }
    
    // If the weapon is not restricted, allow its use
    return Plugin_Continue;
}

void UpdateWeaponCounts()
{
    // Reset counts
    g_AK47Count = 0;
    g_SniperCount = 0;

    // Loop through all players and bots to count weapons
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))  
        {
            char weapon[64];
            GetClientWeapon(i, weapon, sizeof(weapon));
            
            // Check if the player is a bot or real client
            if (IsFakeClient(i))
            {
                // For bots, continue to check and update their weapon counts
                if (StrEqual(weapon, "weapon_rifle_ak47"))
                {
                    g_AK47Count++;
                }
                else if (StrEqual(weapon, "weapon_sniper_military"))
                {
                    g_SniperCount++;
                }
            }
            else
            {
                // For real players, count weapons
                if (StrEqual(weapon, "weapon_rifle_ak47"))
                {
                    g_AK47Count++;
                }
                else if (StrEqual(weapon, "weapon_sniper_military"))
                {
                    g_SniperCount++;
                }
            }
        }
    }
}
