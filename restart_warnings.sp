#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <restart_timer>

#define PLUGIN_VERSION "2.5"
#define TIMEZONE_OFFSET -7 // America/Phoenix (UTC-7)
#define COUNTDOWN_START 600 // 10 minutes in seconds

int g_iRestartHour = 4;
int g_iRestartMinute = 0;
int g_iWarningTimes[] = {600, 300, 60, 30, 10, 5, 4, 3, 2, 1};

public Plugin myinfo = {
    name = "Restart Warnings",
    author = "ShadowX",
    description = "Server restart warnings with live countdown",
    version = PLUGIN_VERSION,
    url = "shadowcommunity.us"
};

public void OnPluginStart() {
    RegAdminCmd("sm_updaterestarttime", Command_UpdateRestartTime, ADMFLAG_RCON);
    RegConsoleCmd("sm_restarttime", Command_ShowRestartTime);
    CreateTimer(1.0, Timer_CheckWarnings, _, TIMER_REPEAT);
    
    HookEvent("player_spawn", Event_PlayerSpawn);
    LoadRestartTime();
}

public void OnMapStart() {
    PrecacheSound("buttons/button10.wav");
}

public void OnMapEnd() {
    StopRestartCountdown();
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsClientInGame(client)) {
        UpdateClientTimerDisplay(client);
    }
    return Plugin_Continue;
}

public Action Command_ShowRestartTime(int client, int args) {
    char timeStr[32];
    FormatTime(timeStr, sizeof(timeStr), "%H:%M", GetTimeOfDay(g_iRestartHour, g_iRestartMinute));
    ReplyToCommand(client, "Next restart at %s", timeStr);
    return Plugin_Handled;
}

public Action Command_UpdateRestartTime(int client, int args) {
    if (args < 1) {
        ReplyToCommand(client, "Usage: sm_updaterestarttime <HHMM>");
        return Plugin_Handled;
    }

    char timeStr[8];
    GetCmdArg(1, timeStr, sizeof(timeStr));
    
    int time = StringToInt(timeStr);
    g_iRestartHour = time / 100;
    g_iRestartMinute = time % 100;
    
    if (g_iRestartHour < 0 || g_iRestartHour > 23 || g_iRestartMinute < 0 || g_iRestartMinute > 59) {
        ReplyToCommand(client, "Invalid time format (use HHMM)");
        return Plugin_Handled;
    }
    
    SaveRestartTime();
    
    char formattedTime[32];
    FormatTime(formattedTime, sizeof(formattedTime), "%H:%M", GetTimeOfDay(g_iRestartHour, g_iRestartMinute));
    PrintToChatAll("[Restart] Time set to %s", formattedTime);
    return Plugin_Handled;
}

public Action Timer_CheckWarnings(Handle timer) {
    int timeLeft = GetTimeUntilRestart();
    
    if (timeLeft <= COUNTDOWN_START && !g_bCountdownActive) {
        StartRestartCountdown(timeLeft);
    }
    
    for (int i = 0; i < sizeof(g_iWarningTimes); i++) {
        if (timeLeft == g_iWarningTimes[i]) {
            char message[128];
            int mins = g_iWarningTimes[i] / 60;
            int secs = g_iWarningTimes[i] % 60;
            
            if (mins > 0) {
                Format(message, sizeof(message), "Restart in %d minute%s!", mins, mins==1?"":"s");
            } else {
                Format(message, sizeof(message), "Restart in %d second%s!", secs, secs==1?"":"s");
            }
            
            PrintToChatAll("[WARNING] %s", message);
            PrintCenterTextAll(message);
            break;
        }
    }
    return Plugin_Continue;
}

int GetTimeUntilRestart() {
    int now = GetTime();
    int restartTime = GetTimeOfDay(g_iRestartHour, g_iRestartMinute);
    return (now > restartTime) ? (restartTime + 86400 - now) : (restartTime - now);
}

int GetTimeOfDay(int hour, int minute) {
    int current = GetTime() + (TIMEZONE_OFFSET * 3600);
    char date[12];
    FormatTime(date, sizeof(date), "%Y-%m-%d", current);
    
    char parts[3][5];
    ExplodeString(date, "-", parts, sizeof(parts), sizeof(parts[]));
    
    return GetTimestamp(
        StringToInt(parts[0]), 
        StringToInt(parts[1]), 
        StringToInt(parts[2]), 
        hour, 
        minute, 
        0
    ) - (TIMEZONE_OFFSET * 3600);
}

int GetTimestamp(int year, int month, int day, int hour, int minute, int second) {
    int days = 0;
    for (int y = 1970; y < year; y++) {
        days += IsLeapYear(y) ? 366 : 365;
    }
    for (int m = 1; m < month; m++) {
        days += GetDaysInMonth(m, year);
    }
    days += day - 1;
    return (days * 86400) + (hour * 3600) + (minute * 60) + second;
}

int GetDaysInMonth(int month, int year) {
    switch (month) {
        case 1,3,5,7,8,10,12: return 31;
        case 4,6,9,11: return 30;
        case 2: return IsLeapYear(year) ? 29 : 28;
    }
    return 30;
}

bool IsLeapYear(int year) {
    return (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0));
}

void LoadRestartTime() {
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/restart_schedule.cfg");
    
    KeyValues kv = new KeyValues("RestartSchedule");
    if (kv.ImportFromFile(path)) {
        g_iRestartHour = kv.GetNum("hour", 4);
        g_iRestartMinute = kv.GetNum("minute", 0);
    }
    delete kv;
}

void SaveRestartTime() {
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/restart_schedule.cfg");
    
    KeyValues kv = new KeyValues("RestartSchedule");
    kv.SetNum("hour", g_iRestartHour);
    kv.SetNum("minute", g_iRestartMinute);
    kv.ExportToFile(path);
    delete kv;
}