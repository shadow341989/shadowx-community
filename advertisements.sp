#include <sourcemod>
#include <colors>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = 
{
    name = "Advertisements for Left 4 Dead 2",
    author = "Your Name",
    description = "Displays advertisements from a config file to clients as they load in.",
    version = "1.0",
    url = "http://yourwebsite.com"
};

// Global Variables
Handle g_hAdvertisements; // Array to store advertisements
int g_iCurrentAd[MAXPLAYERS + 1]; // Current advertisement index for each client
bool g_bFinale = false;   // Track if the finale is active

public void OnPluginStart()
{
    // Register a command to reload the advertisements config
    RegConsoleCmd("sm_reloadads", Command_ReloadAds, "Reloads the advertisements config file.");
    
    // Load the advertisements config file
    LoadAdsConfig();
    
    // Hook finale events to handle finale-specific advertisements
    HookEvent("finale_start", Event_FinaleStart, EventHookMode_Post);
    HookEvent("finale_win", Event_FinaleEnd, EventHookMode_Post);
    
    // Hook client connection events
    HookEvent("player_connect", Event_PlayerConnect, EventHookMode_Post);
    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
    
    // Initialize advertisement indices for all clients
    for (int i = 1; i <= MaxClients; i++)
    {
        g_iCurrentAd[i] = 0;
    }
}

// Command to reload the advertisements config
public Action Command_ReloadAds(int client, int args)
{
    LoadAdsConfig();
    ReplyToCommand(client, "Advertisements config reloaded.");
    return Plugin_Handled;
}

// Load advertisements from the config file
void LoadAdsConfig()
{
    // Clear the existing advertisements array
    if (g_hAdvertisements != INVALID_HANDLE)
    {
        ClearArray(g_hAdvertisements);
    }
    else
    {
        g_hAdvertisements = CreateArray(256);
    }
    
    // Build the path to the config file
    char path[PLATFORM_MAX_PATH];
    Format(path, sizeof(path), "cfg/sourcemod/advertisements.cfg");
    
    // Check if the config file exists
    if (!FileExists(path))
    {
        // Create the directory if it doesn't exist
        char dir[PLATFORM_MAX_PATH];
        Format(dir, sizeof(dir), "cfg/sourcemod");
        if (!DirExists(dir))
        {
            CreateDirectory(dir, 511); // 511 = full permissions
        }
        
        // Create the file if it doesn't exist
        File file = OpenFile(path, "w");
        if (file == null)
        {
            SetFailState("Failed to create the advertisements config file at %s", path);
        }
        
        // Write default advertisements to the file
        file.WriteLine("{green}Welcome to shadow-garden {blue}normal server.  ");
        file.WriteLine("{blue}Please visit our steam group and join @ {green}https://steamcommunity.com/groups/gs1422  ");
        file.WriteLine("{green}Join our discord server at https://discord.gg/MYQtr4rMF3  ");
        file.WriteLine("[finale]{orange}You have reached the finale. thank you for playing. Don't forget to join our steam group server @ {blue}https://steamcommunity.com/groups/gs1422");
        
        // Close the file
        delete file;
        
        LogMessage("Created default advertisements config file at %s", path);
    }
    
    // Open the config file for reading
    File file = OpenFile(path, "r");
    if (file == null)
    {
        SetFailState("Failed to open the advertisements config file at %s", path);
    }
    
    // Read each line from the config file
    char line[256];
    while (file.ReadLine(line, sizeof(line)))
    {
        TrimString(line); // Remove leading/trailing whitespace
        if (strlen(line) > 0) // Ignore empty lines
        {
            PushArrayString(g_hAdvertisements, line); // Add the line to the array
        }
    }
    
    // Close the file
    delete file;
}

// Event: Finale starts
public void Event_FinaleStart(Event event, const char[] name, bool dontBroadcast)
{
    g_bFinale = true; // Set finale flag to true
    DisplayFinaleAds(); // Display finale-specific advertisements
}

// Event: Finale ends
public void Event_FinaleEnd(Event event, const char[] name, bool dontBroadcast)
{
    g_bFinale = false; // Set finale flag to false
}

// Display advertisements marked with [finale]
void DisplayFinaleAds()
{
    for (int i = 0; i < GetArraySize(g_hAdvertisements); i++)
    {
        char ad[256];
        GetArrayString(g_hAdvertisements, i, ad, sizeof(ad)); // Get the advertisement
        
        // Check if the advertisement is marked for the finale
        if (StrContains(ad, "[finale]") == 0)
        {
            ReplaceString(ad, sizeof(ad), "[finale]", ""); // Remove the [finale] tag
            
            // Display the advertisement to all connected clients
            for (int client = 1; client <= MaxClients; client++)
            {
                if (IsClientInGame(client) && !IsFakeClient(client))
                {
                    CPrintToChat(client, ad);
                }
            }
        }
    }
}

// Event: Player connects
public void Event_PlayerConnect(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0 && !IsFakeClient(client))
    {
        // Reset the advertisement index for the new client
        g_iCurrentAd[client] = 0;
        
        // Start displaying advertisements to the client
        CreateTimer(5.0, Timer_DisplayAdToClient, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
}

// Event: Player changes team (indicates they have fully loaded)
public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0 && !IsFakeClient(client))
    {
        // Start displaying advertisements to the client
        CreateTimer(5.0, Timer_DisplayAdToClient, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
}

// Timer: Display advertisements to a specific client
public Action Timer_DisplayAdToClient(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client > 0 && IsClientInGame(client) && !IsFakeClient(client))
    {
        // Check if there are more advertisements to display
        if (g_iCurrentAd[client] < GetArraySize(g_hAdvertisements))
        {
            // Get the current advertisement
            char ad[256];
            GetArrayString(g_hAdvertisements, g_iCurrentAd[client], ad, sizeof(ad));
            
            // Skip advertisements marked for the finale during normal gameplay
            if (StrContains(ad, "[finale]") != 0 || g_bFinale)
            {
                ReplaceString(ad, sizeof(ad), "[finale]", ""); // Remove the [finale] tag
                CPrintToChat(client, ad); // Display the advertisement to the client
            }
            
            g_iCurrentAd[client]++; // Move to the next advertisement
            
            // Schedule the next advertisement for this client
            CreateTimer(10.0, Timer_DisplayAdToClient, userid, TIMER_FLAG_NO_MAPCHANGE);
        }
    }
    
    return Plugin_Stop;
}