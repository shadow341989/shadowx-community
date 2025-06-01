#include <sourcemod>
#include <sdktools>
#include <colors>

#define CONFIG_FILE "addons/sourcemod/configs/chat_tags.cfg"
#define MAX_TAGS 64

bool g_PluginEnabled = true;
char g_Tags[MAX_TAGS][64];
char g_SteamIDs[MAX_TAGS][32];
int g_TotalTags = 0;

float g_LastTagChangeTime[MAXPLAYERS + 1];

// List of restricted tags
char g_RestrictedTags[][] = {
    "admin",
    "community dir",
    "moderator",
    "mod",
    "VIP",
    "Vip",
    "vip",
    "Owner",
    "owner"
};

public Plugin myinfo = {
    name = "L4D2 Chat Tags",
    author = "ShadowX",
    description = "A plugin to add custom chat tags based on SteamID",
    version = "3.7.0",
    url = "https://yourwebsite.com"
};

public void OnPluginStart() {
    LoadChatTags();
    
    // Register admin commands
    RegAdminCmd("sm_reloadtags", Command_ReloadTags, ADMFLAG_ROOT);
    RegAdminCmd("sm_addtag", Command_AddTag, ADMFLAG_ROOT);
    RegAdminCmd("sm_removetag", Command_RemoveTag, ADMFLAG_ROOT);
    RegAdminCmd("sm_forcechangetag", Command_ForceChangeTag, ADMFLAG_ROOT);
    RegAdminCmd("sm_showtags", Command_ShowTags, ADMFLAG_ROOT);
    
    // Player command
    RegConsoleCmd("sm_changetag", Command_ChangeTag);
}

public void OnMapStart() {
    LoadChatTags();
}

public void OnClientDisconnect(int client) {
    g_LastTagChangeTime[client] = 0.0;
}

public Action Command_ReloadTags(int client, int args) {
    LoadChatTags();
    PrintToChat(client, "[ChatTags] Tags reloaded successfully.");
    return Plugin_Handled;
}

public Action Command_AddTag(int client, int args) {
    if (args < 2) {
        PrintToChat(client, "[ChatTags] Usage: !addtag <SteamID> <Tag>");
        return Plugin_Handled;
    }

    char steamID[32], tag[64];
    GetCmdArgString(steamID, sizeof(steamID));

    int splitIndex = FindCharInString(steamID, ' ');
    if (splitIndex == -1) {
        PrintToChat(client, "[ChatTags] Invalid format. Usage: !addtag <SteamID> <Tag>");
        return Plugin_Handled;
    }

    steamID[splitIndex] = '\0';
    strcopy(tag, sizeof(tag), steamID[splitIndex + 1]);

    TrimString(steamID);
    TrimString(tag);

    for (int i = 0; i < g_TotalTags; i++) {
        if (StrEqual(steamID, g_SteamIDs[i], false)) {
            PrintToChat(client, "[ChatTags] This SteamID already has a tag.");
            return Plugin_Handled;
        }
    }

    Handle file = OpenFile(CONFIG_FILE, "a");
    if (file == null) {
        PrintToChat(client, "[ChatTags] Failed to open the config file.");
        return Plugin_Handled;
    }

    WriteFileLine(file, "%s=%s", steamID, tag);
    CloseHandle(file);

    LoadChatTags();
    PrintToChat(client, "[ChatTags] Tag added successfully.");
    return Plugin_Handled;
}

public Action Command_RemoveTag(int client, int args) {
    if (args < 1) {
        PrintToChat(client, "[ChatTags] Usage: !removetag <SteamID>");
        return Plugin_Handled;
    }

    char steamID[32];
    GetCmdArgString(steamID, sizeof(steamID));
    TrimString(steamID);

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
            WriteFileLine(tempFile, line);
            continue;
        }

        char parts[2][64];
        ExplodeString(line, "=", parts, 2, 64);

        TrimString(parts[0]);
        TrimString(parts[1]);

        if (StrEqual(parts[0], steamID, false)) {
            found = true;
            continue;
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

    if (!DeleteFile(CONFIG_FILE)) {
        PrintToChat(client, "[ChatTags] Failed to delete the old config file.");
        return Plugin_Handled;
    }

    if (!RenameFile(CONFIG_FILE, "addons/sourcemod/configs/chat_tags_temp.cfg")) {
        PrintToChat(client, "[ChatTags] Failed to rename the temporary file.");
        return Plugin_Handled;
    }

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

    float currentTime = GetEngineTime();
    float lastChangeTime = g_LastTagChangeTime[client];
    float cooldown = 60.0;

    if (currentTime - lastChangeTime < cooldown) {
        float remainingTime = cooldown - (currentTime - lastChangeTime);
        PrintToChat(client, "[ChatTags] Access Denied. You must wait %.0f seconds before changing your tag again.", remainingTime);
        return Plugin_Handled;
    }

    char newTag[64];
    GetCmdArgString(newTag, sizeof(newTag));
    TrimString(newTag);

    if (newTag[0] == '"' && newTag[strlen(newTag) - 1] == '"') {
        newTag[strlen(newTag) - 1] = '\0';
        strcopy(newTag, sizeof(newTag), newTag[1]);
    }

    if (IsTagRestricted(newTag)) {
        if (StrEqual(newTag, "VIP", false) || StrEqual(newTag, "Vip", false) || StrEqual(newTag, "vip", false)) {
            PrintToChat(client, "[ChatTags] Access Denied. Contact an admin for a tag like this.");
        } else {
            PrintToChat(client, "[ChatTags] Access Denied. Choose a different tag.");
        }
        return Plugin_Handled;
    }

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
            WriteFileLine(tempFile, line);
            continue;
        }

        char parts[2][64];
        ExplodeString(line, "=", parts, 2, 64);

        TrimString(parts[0]);
        TrimString(parts[1]);

        if (StrEqual(parts[0], steamID, false)) {
            found = true;
            WriteFileLine(tempFile, "%s=%s", steamID, newTag);
        } else {
            WriteFileLine(tempFile, line);
        }
    }

    CloseHandle(file);
    CloseHandle(tempFile);

    if (!found) {
        PrintToChat(client, "[ChatTags] Your SteamID was not found in the config.");
        DeleteFile("addons/sourcemod/configs/chat_tags_temp.cfg");
        return Plugin_Handled;
    }

    if (!DeleteFile(CONFIG_FILE)) {
        PrintToChat(client, "[ChatTags] Failed to delete the old config file.");
        return Plugin_Handled;
    }

    if (!RenameFile(CONFIG_FILE, "addons/sourcemod/configs/chat_tags_temp.cfg")) {
        PrintToChat(client, "[ChatTags] Failed to rename the temporary file.");
        return Plugin_Handled;
    }

    g_LastTagChangeTime[client] = currentTime;

    LoadChatTags();
    PrintToChat(client, "[ChatTags] Your tag has been changed to: %s", newTag);
    return Plugin_Handled;
}

public Action Command_ForceChangeTag(int client, int args) {
    if (args < 2) {
        PrintToChat(client, "[ChatTags] Usage: !forcechangetag <SteamID> \"New Tag\"");
        return Plugin_Handled;
    }

    char steamID[32], newTag[64];
    char argString[256];
    GetCmdArgString(argString, sizeof(argString));

    int splitIndex = FindCharInString(argString, ' ');
    if (splitIndex == -1) {
        PrintToChat(client, "[ChatTags] Invalid format. Usage: !forcechangetag <SteamID> \"New Tag\"");
        return Plugin_Handled;
    }

    strcopy(steamID, sizeof(steamID), argString);
    steamID[splitIndex] = '\0';
    strcopy(newTag, sizeof(newTag), argString[splitIndex + 1]);

    TrimString(steamID);
    TrimString(newTag);

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
            WriteFileLine(tempFile, line);
            continue;
        }

        char parts[2][64];
        ExplodeString(line, "=", parts, 2, 64);

        TrimString(parts[0]);
        TrimString(parts[1]);

        if (StrEqual(parts[0], steamID, false)) {
            found = true;
            WriteFileLine(tempFile, "%s=%s", steamID, newTag);
        } else {
            WriteFileLine(tempFile, line);
        }
    }

    CloseHandle(file);
    CloseHandle(tempFile);

    if (!found) {
        PrintToChat(client, "[ChatTags] SteamID not found in the config.");
        DeleteFile("addons/sourcemod/configs/chat_tags_temp.cfg");
        return Plugin_Handled;
    }

    if (!DeleteFile(CONFIG_FILE)) {
        PrintToChat(client, "[ChatTags] Failed to delete the old config file.");
        return Plugin_Handled;
    }

    if (!RenameFile(CONFIG_FILE, "addons/sourcemod/configs/chat_tags_temp.cfg")) {
        PrintToChat(client, "[ChatTags] Failed to rename the temporary file.");
        return Plugin_Handled;
    }

    LoadChatTags();
    PrintToChat(client, "[ChatTags] Tag for SteamID %s has been changed to: %s", steamID, newTag);
    return Plugin_Handled;
}

public Action Command_ShowTags(int client, int args) {
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
            continue;
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
        return Plugin_Continue;
    }

    char steamID[32];
    GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID));

    char tag[64] = "";
    bool hasTag = false;

    for (int i = 0; i < g_TotalTags; i++) {
        if (StrEqual(steamID, g_SteamIDs[i], false)) {
            strcopy(tag, sizeof(tag), g_Tags[i]);
            hasTag = true;
            break;
        }
    }

    if (!hasTag) {
        return Plugin_Continue;
    }

    char nameBuffer[64];
    GetClientName(client, nameBuffer, sizeof(nameBuffer));

    ReplaceString(nameBuffer, sizeof(nameBuffer), "(Survivor)", "");
    ReplaceString(nameBuffer, sizeof(nameBuffer), "(Infected)", "");
    ReplaceString(nameBuffer, sizeof(nameBuffer), "", "");

    char formatted[256];

    if (StrEqual(command, "say_team")) {
        Format(formatted, sizeof(formatted), "{blue}[%s] {green}%s: {default}%s", tag, nameBuffer, sArgs);

        for (int i = 1; i <= MaxClients; i++) {
            if (IsClientInGame(i) && GetClientTeam(i) == GetClientTeam(client)) {
                CPrintToChat(i, "%s", formatted);
            }
        }
    } else {
        Format(formatted, sizeof(formatted), "{blue}[%s] {default}%s: %s", tag, nameBuffer, sArgs);
        CPrintToChatAll("%s", formatted);
    }

    return Plugin_Handled;
}
