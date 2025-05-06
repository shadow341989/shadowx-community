#include <sourcemod>
#include <sdktools>
#include <colors>

#define CONFIG_FILE "addons/sourcemod/configs/chat_tags.cfg"
#define MAX_TAGS 64

bool g_PluginEnabled = true;
char g_Tags[MAX_TAGS][64];
char g_SteamIDs[MAX_TAGS][32];
int g_TotalTags = 0;

float g_LastTagChangeTime[MAXPLAYERS + 1]; // Stores the last time a player changed their tag

// List of restricted tags
char g_RestrictedTags[][] = {
    "admin",
    "community dir",
    "moderator",
    "mod",
    "VIP",
    "Vip",
    "vip",
    "Owner", // Added "Owner" to the restricted list
    "owner" // Optional: Add lowercase version for case-insensitive matching
};

public Plugin myinfo = {
    name = "L4D2 Chat Tags",
    author = "ShadowX",
    description = "A plugin to add custom chat tags based on SteamID",
    version = "3.6.7",
    url = "https://yourwebsite.com"
};

public void OnPluginStart() {
    LoadChatTags();
    RegConsoleCmd("sm_reloadtags", Command_ReloadTags);
    RegConsoleCmd("sm_addtag", Command_AddTag);
    RegConsoleCmd("sm_removetag", Command_RemoveTag);
    RegConsoleCmd("sm_changetag", Command_ChangeTag);
    RegConsoleCmd("sm_forcechangetag", Command_ForceChangeTag);
    RegConsoleCmd("sm_showtags", Command_ShowTags);
}

public void OnMapStart() {
    LoadChatTags();
}

public void OnClientDisconnect(int client) {
    g_LastTagChangeTime[client] = 0.0; // Reset the cooldown timer
}

public Action Command_ReloadTags(int client, int args) {
    if (!IsClientAdmin(client)) {
        PrintToChat(client, "[ChatTags] You don't have permission to use this command.");
        return Plugin_Handled;
    }

    LoadChatTags();
    PrintToChat(client, "[ChatTags] Tags reloaded successfully.");
    return Plugin_Handled;
}

public Action Command_AddTag(int client, int args) {
    if (!IsClientAdmin(client)) {
        PrintToChat(client, "[ChatTags] You don't have permission to use this command.");
        return Plugin_Handled;
    }

    if (args < 2) {
        PrintToChat(client, "[ChatTags] Usage: !addtag <SteamID> <Tag>");
        return Plugin_Handled;
    }

    char steamID[32], tag[64];
    GetCmdArgString(steamID, sizeof(steamID)); // Get the entire argument string

    // Split the argument string into SteamID and tag
    int splitIndex = FindCharInString(steamID, ' '); // Find the first space
    if (splitIndex == -1) {
        PrintToChat(client, "[ChatTags] Invalid format. Usage: !addtag <SteamID> <Tag>");
        return Plugin_Handled;
    }

    steamID[splitIndex] = '\0'; // Terminate the SteamID string at the space
    strcopy(tag, sizeof(tag), steamID[splitIndex + 1]); // Copy the tag part

    // Trim any extra spaces
    TrimString(steamID);
    TrimString(tag);

    // Check if the SteamID already has a tag
    for (int i = 0; i < g_TotalTags; i++) {
        if (StrEqual(steamID, g_SteamIDs[i], false)) {
            PrintToChat(client, "[ChatTags] This SteamID already has a tag.");
            return Plugin_Handled;
        }
    }

    // Add the tag to the config file
    Handle file = OpenFile(CONFIG_FILE, "a");
    if (file == null) {
        PrintToChat(client, "[ChatTags] Failed to open the config file.");
        return Plugin_Handled;
    }

    WriteFileLine(file, "%s=%s", steamID, tag);
    CloseHandle(file);

    // Reload the tags
    LoadChatTags();
    PrintToChat(client, "[ChatTags] Tag added successfully.");
    return Plugin_Handled;
}

public Action Command_RemoveTag(int client, int args) {
    if (!IsClientAdmin(client)) {
        PrintToChat(client, "[ChatTags] You don't have permission to use this command.");
        return Plugin_Handled;
    }

    if (args < 1) {
        PrintToChat(client, "[ChatTags] Usage: !removetag <SteamID>");
        return Plugin_Handled;
    }

    char steamID[32];
    GetCmdArgString(steamID, sizeof(steamID)); // Get the full argument string
    TrimString(steamID); // Trim any extra spaces

    // Remove the tag from the config file
    Handle file = OpenFile(CONFIG_FILE, "r");
    if (file == null) {
        PrintToChat(client, "[ChatTags] Failed to open the config file.");
        return Plugin_Handled;
    }

    Handle tempFile = OpenFile("addons/sourcemod/configs/chat_tags_temp.cfg", "w");
    if (tempFile == null) {
        PrintToChat(client, "[ChatTags] Failed to create a temporary file.");
        CloseHandle(file);
        return Plugin_Handled;
    }

    char line[256];
    bool found = false;

    while (ReadFileLine(file, line, sizeof(line))) {
        TrimString(line); // Trim the line to remove extra spaces

        if (line[0] == '\0' || line[0] == ';' || line[0] == '/') {
            WriteFileLine(tempFile, line); // Keep comments and empty lines
            continue;
        }

        char parts[2][64];
        ExplodeString(line, "=", parts, 2, 64);

        TrimString(parts[0]); // Trim the SteamID part
        TrimString(parts[1]); // Trim the tag part

        if (StrEqual(parts[0], steamID, false)) { // Case-insensitive comparison
            found = true;
            continue; // Skip writing this line to the temp file
        }

        WriteFileLine(tempFile, line);
    }

    CloseHandle(file);
    CloseHandle(tempFile);

    if (!found) {
        PrintToChat(client, "[ChatTags] SteamID not found in the config.");
        DeleteFile("addons/sourcemod/configs/chat_tags_temp.cfg");
        return Plugin_Handled;
    }

    // Replace the old config file with the new one
    if (!DeleteFile(CONFIG_FILE)) {
        PrintToChat(client, "[ChatTags] Failed to delete the old config file.");
        return Plugin_Handled;
    }

    if (!RenameFile(CONFIG_FILE, "addons/sourcemod/configs/chat_tags_temp.cfg")) {
        PrintToChat(client, "[ChatTags] Failed to rename the temporary file.");
        return Plugin_Handled;
    }

    // Reload the tags
    LoadChatTags();
    PrintToChat(client, "[ChatTags] Tag removed successfully.");
    return Plugin_Handled;
}

public Action Command_ChangeTag(int client, int args) {
    if (args < 1) {
        PrintToChat(client, "[ChatTags] Usage: !changetag \"New Tag\"");
        return Plugin_Handled;
    }

    char steamID[32];
    GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID));

    // Check if the player already has a tag
    bool hasTag = false;
    for (int i = 0; i < g_TotalTags; i++) {
        if (StrEqual(steamID, g_SteamIDs[i], false)) {
            hasTag = true;
            break;
        }
    }

    if (!hasTag) {
        PrintToChat(client, "[ChatTags] You must have a valid tag already before you can change your tag.");
        return Plugin_Handled;
    }

    // Check cooldown
    float currentTime = GetEngineTime();
    float lastChangeTime = g_LastTagChangeTime[client];
    float cooldown = 60.0; // 1 minute in seconds

    if (currentTime - lastChangeTime < cooldown) {
        float remainingTime = cooldown - (currentTime - lastChangeTime);
        PrintToChat(client, "[ChatTags] Access Denied. You must wait %.0f seconds before changing your tag again.", remainingTime);
        return Plugin_Handled;
    }

    char newTag[64];
    GetCmdArgString(newTag, sizeof(newTag));
    TrimString(newTag);

    // Remove quotes if present
    if (newTag[0] == '"' && newTag[strlen(newTag) - 1] == '"') {
        newTag[strlen(newTag) - 1] = '\0';
        strcopy(newTag, sizeof(newTag), newTag[1]);
    }

    // Check if the new tag is restricted
    if (IsTagRestricted(newTag)) {
        if (StrEqual(newTag, "VIP", false) || StrEqual(newTag, "Vip", false) || StrEqual(newTag, "vip", false)) {
            PrintToChat(client, "[ChatTags] Access Denied. Contact an admin for a tag like this.");
        } else {
            PrintToChat(client, "[ChatTags] Access Denied. Choose a different tag.");
        }
        return Plugin_Handled; // Block the command if the tag is restricted
    }

    // Update the tag in the config file
    Handle file = OpenFile(CONFIG_FILE, "r");
    if (file == null) {
        PrintToChat(client, "[ChatTags] Failed to open the config file.");
        return Plugin_Handled;
    }

    Handle tempFile = OpenFile("addons/sourcemod/configs/chat_tags_temp.cfg", "w");
    if (tempFile == null) {
        PrintToChat(client, "[ChatTags] Failed to create a temporary file.");
        CloseHandle(file);
        return Plugin_Handled;
    }

    char line[256];
    bool found = false;

    while (ReadFileLine(file, line, sizeof(line))) {
        TrimString(line);

        if (line[0] == '\0' || line[0] == ';' || line[0] == '/') {
            WriteFileLine(tempFile, line); // Keep comments and empty lines
            continue;
        }

        char parts[2][64];
        ExplodeString(line, "=", parts, 2, 64);

        TrimString(parts[0]); // Trim the SteamID part
        TrimString(parts[1]); // Trim the tag part

        if (StrEqual(parts[0], steamID, false)) {
            found = true;
            WriteFileLine(tempFile, "%s=%s", steamID, newTag); // Write the new tag
        } else {
            WriteFileLine(tempFile, line); // Write the original line
        }
    }

    CloseHandle(file);
    CloseHandle(tempFile);

    if (!found) {
        PrintToChat(client, "[ChatTags] Your SteamID was not found in the config.");
        DeleteFile("addons/sourcemod/configs/chat_tags_temp.cfg");
        return Plugin_Handled;
    }

    // Replace the old config file with the new one
    if (!DeleteFile(CONFIG_FILE)) {
        PrintToChat(client, "[ChatTags] Failed to delete the old config file.");
        return Plugin_Handled;
    }

    if (!RenameFile(CONFIG_FILE, "addons/sourcemod/configs/chat_tags_temp.cfg")) {
        PrintToChat(client, "[ChatTags] Failed to rename the temporary file.");
        return Plugin_Handled;
    }

    // Update the last change time
    g_LastTagChangeTime[client] = currentTime;

    // Reload the tags
    LoadChatTags();
    PrintToChat(client, "[ChatTags] Your tag has been changed to: %s", newTag);
    return Plugin_Handled;
}

public Action Command_ForceChangeTag(int client, int args) {
    if (!IsClientAdmin(client)) {
        PrintToChat(client, "[ChatTags] You don't have permission to use this command.");
        return Plugin_Handled;
    }

    if (args < 2) {
        PrintToChat(client, "[ChatTags] Usage: !forcechangetag <SteamID> \"New Tag\"");
        return Plugin_Handled;
    }

    char steamID[32], newTag[64];
    char argString[256];
    GetCmdArgString(argString, sizeof(argString)); // Get the full argument string

    // Split the argument string into SteamID and tag
    int splitIndex = FindCharInString(argString, ' '); // Find the first space
    if (splitIndex == -1) {
        PrintToChat(client, "[ChatTags] Invalid format. Usage: !forcechangetag <SteamID> \"New Tag\"");
        return Plugin_Handled;
    }

    strcopy(steamID, sizeof(steamID), argString); // Copy the SteamID part
    steamID[splitIndex] = '\0'; // Terminate the SteamID string at the space
    strcopy(newTag, sizeof(newTag), argString[splitIndex + 1]); // Copy the tag part

    // Trim any extra spaces
    TrimString(steamID);
    TrimString(newTag);

    // Update the tag in the config file
    Handle file = OpenFile(CONFIG_FILE, "r");
    if (file == null) {
        PrintToChat(client, "[ChatTags] Failed to open the config file.");
        return Plugin_Handled;
    }

    Handle tempFile = OpenFile("addons/sourcemod/configs/chat_tags_temp.cfg", "w");
    if (tempFile == null) {
        PrintToChat(client, "[ChatTags] Failed to create a temporary file.");
        CloseHandle(file);
        return Plugin_Handled;
    }

    char line[256];
    bool found = false;

    while (ReadFileLine(file, line, sizeof(line))) {
        TrimString(line);

        if (line[0] == '\0' || line[0] == ';' || line[0] == '/') {
            WriteFileLine(tempFile, line); // Keep comments and empty lines
            continue;
        }

        char parts[2][64];
        ExplodeString(line, "=", parts, 2, 64);

        TrimString(parts[0]); // Trim the SteamID part
        TrimString(parts[1]); // Trim the tag part

        if (StrEqual(parts[0], steamID, false)) {
            found = true;
            WriteFileLine(tempFile, "%s=%s", steamID, newTag); // Write the new tag
        } else {
            WriteFileLine(tempFile, line); // Write the original line
        }
    }

    CloseHandle(file);
    CloseHandle(tempFile);

    if (!found) {
        PrintToChat(client, "[ChatTags] SteamID not found in the config.");
        DeleteFile("addons/sourcemod/configs/chat_tags_temp.cfg");
        return Plugin_Handled;
    }

    // Replace the old config file with the new one
    if (!DeleteFile(CONFIG_FILE)) {
        PrintToChat(client, "[ChatTags] Failed to delete the old config file.");
        return Plugin_Handled;
    }

    if (!RenameFile(CONFIG_FILE, "addons/sourcemod/configs/chat_tags_temp.cfg")) {
        PrintToChat(client, "[ChatTags] Failed to rename the temporary file.");
        return Plugin_Handled;
    }

    // Reload the tags
    LoadChatTags();
    PrintToChat(client, "[ChatTags] Tag for SteamID %s has been changed to: %s", steamID, newTag);
    return Plugin_Handled;
}

public Action Command_ShowTags(int client, int args) {
    if (!IsClientAdmin(client)) {
        PrintToChat(client, "[ChatTags] You don't have permission to use this command.");
        return Plugin_Handled;
    }

    if (g_TotalTags == 0) {
        PrintToChat(client, "[ChatTags] No tags are currently loaded.");
        return Plugin_Handled;
    }

    PrintToChat(client, "[ChatTags] Listing all SteamIDs and their associated tags:");

    for (int i = 0; i < g_TotalTags; i++) {
        PrintToChat(client, "%s=%s", g_SteamIDs[i], g_Tags[i]);
    }

    return Plugin_Handled;
}

public bool IsClientAdmin(int client) {
    return IsClientInGame(client) && CheckCommandAccess(client, "sm_reloadtags", ADMFLAG_ROOT);
}

bool IsTagRestricted(const char[] tag) {
    for (int i = 0; i < sizeof(g_RestrictedTags); i++) {
        if (StrEqual(tag, g_RestrictedTags[i], false)) {
            return true;
        }
    }
    return false;
}

void LoadChatTags() {
    Handle file = OpenFile(CONFIG_FILE, "r");

    if (file == null) {
        CreateDefaultConfig();
        file = OpenFile(CONFIG_FILE, "r");
        if (file == null) {
            PrintToServer("[ChatTags] Failed to create and open the config file.");
            return;
        }
    }

    g_TotalTags = 0;
    g_PluginEnabled = true;

    char line[256];
    while (ReadFileLine(file, line, sizeof(line))) {
        TrimString(line);
        if (line[0] == '\0' || line[0] == ';' || line[0] == '/') {
            continue; // Skip empty or commented lines
        }

        char parts[2][64];
        ExplodeString(line, "=", parts, 2, 64);

        TrimString(parts[0]);
        TrimString(parts[1]);

        if (StrEqual(parts[0], "Enabled")) {
            g_PluginEnabled = StringToInt(parts[1]) != 0;
        } else if (g_TotalTags < MAX_TAGS) {
            strcopy(g_SteamIDs[g_TotalTags], sizeof(g_SteamIDs[]), parts[0]);
            strcopy(g_Tags[g_TotalTags], sizeof(g_Tags[]), parts[1]);
            g_TotalTags++;
        }
    }

    CloseHandle(file);
    PrintToServer("[ChatTags] Loaded %d tags. Plugin is %s.", g_TotalTags, g_PluginEnabled ? "enabled" : "disabled");
}

void CreateDefaultConfig() {
    Handle file = OpenFile(CONFIG_FILE, "w");

    if (file == null) {
        PrintToServer("[ChatTags] Failed to create the config file.");
        return;
    }

    WriteFileLine(file, "// Chat Tags Configuration");
    WriteFileLine(file, "// Format: SteamID=Tag");
    WriteFileLine(file, "// Example: STEAM_1:1:12345678=[Admin]");
    WriteFileLine(file, "");
    WriteFileLine(file, "Enabled=1");
    WriteFileLine(file, "");
    WriteFileLine(file, "STEAM_1:1:12345678=[Owner]");
    WriteFileLine(file, "STEAM_1:0:87654321=[Admin]");
    WriteFileLine(file, "STEAM_1:0:11223344=[VIP]");

    CloseHandle(file);
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs) {
    if (!g_PluginEnabled) {
        return Plugin_Continue; // Plugin disabled; allow the game to handle the chat.
    }

    char steamID[32];
    GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID));

    char tag[64] = "";
    bool hasTag = false;

    // Check if the player's SteamID matches any tags
    for (int i = 0; i < g_TotalTags; i++) {
        if (StrEqual(steamID, g_SteamIDs[i], false)) {
            strcopy(tag, sizeof(tag), g_Tags[i]);
            hasTag = true;
            break;
        }
    }

    // If the player doesn't have a tag, use the game's default chat behavior
    if (!hasTag) {
        return Plugin_Continue;
    }

    // Prepare the formatted message for players with a tag
    char nameBuffer[64];
    GetClientName(client, nameBuffer, sizeof(nameBuffer));

    // Clean up the player's name by removing unwanted characters
    ReplaceString(nameBuffer, sizeof(nameBuffer), "(Survivor)", "");
    ReplaceString(nameBuffer, sizeof(nameBuffer), "(Infected)", "");
    ReplaceString(nameBuffer, sizeof(nameBuffer), "", ""); // Remove control characters

    char formatted[256];

    if (StrEqual(command, "say_team")) {
        // Format for team chat
        Format(formatted, sizeof(formatted), "{blue}[%s] {green}%s: {default}%s", tag, nameBuffer, sArgs);

        // Send the message only to the player's team
        for (int i = 1; i <= MaxClients; i++) {
            if (IsClientInGame(i) && GetClientTeam(i) == GetClientTeam(client)) {
                CPrintToChat(i, "%s", formatted);
            }
        }
    } else {
        // Format for global chat
        Format(formatted, sizeof(formatted), "{blue}[%s] {default}%s: %s", tag, nameBuffer, sArgs);

        // Send the message to all players
        CPrintToChatAll("%s", formatted);
    }

    // Block the original game message for players with tags
    return Plugin_Handled;
}