#if defined _tank_panel_included
 #endinput
#endif
#define _tank_panel_included

/**
 * Displays the Tank performance panel to the client.
 *
 * @param client        The client to display the panel to.
 * @param tankPoints    The Tank's current points.
 * @param rocksHit      The number of successful rock hits.
 * @param tankHP        The Tank's current health.
 * @noreturn
 */
void DisplayTankPanel(int client, int tankPoints, int rocksHit, int tankHP)
{
    char buffer[128];
    Panel panel = new Panel();

    // Title with futuristic style
    panel.DrawText("■■■■■■■■■■■■■■■■■■■■■■■■■■");
    panel.DrawText("■   TANK PERFORMANCE   ■");
    panel.DrawText("■■■■■■■■■■■■■■■■■■■■■■■■■■");

    // Points with star
    Format(buffer, sizeof(buffer), "★ Points: %d", tankPoints);
    panel.DrawText(buffer);

    // Next Level with star
    Format(buffer, sizeof(buffer), "★ Next Level: %d", GetPointsUntilNextRating(tankPoints));
    panel.DrawText(buffer);

    // Progress Bar with star
    int progress = (tankPoints * 100) / 2800; // Assuming 2800 is the max points
    char progressBar[32];
    Format(progressBar, sizeof(progressBar), "[%-10s]", RepeatChar('=', progress / 10));
    Format(buffer, sizeof(buffer), "★ Progress: %s", progressBar);
    panel.DrawText(buffer);

    // Rating with star
    Format(buffer, sizeof(buffer), "★ Rating: %s", GetRating(tankPoints));
    panel.DrawText(buffer);

    // Rocks with star
    Format(buffer, sizeof(buffer), "★ Rocks: %d", rocksHit);
    panel.DrawText(buffer);

    // HP with star
    Format(buffer, sizeof(buffer), "★ HP: %d", tankHP);
    panel.DrawText(buffer);

    // Footer with futuristic style
    panel.DrawText("■■■■■■■■■■■■■■■■■■■■■■■■■■");

    // Send the panel to the client
    panel.Send(client, PanelHandler, 1);

    delete panel;
}

/**
 * Handles the panel menu action.
 *
 * @param menu      The menu handle.
 * @param action    The menu action.
 * @param param1    The first parameter (client).
 * @param param2    The second parameter (item selected).
 * @noreturn
 */
public void PanelHandler(Menu menu, MenuAction action, int param1, int param2) { }

/**
 * Returns the points needed to reach the next rating.
 *
 * @param points    The current points.
 * @return          The points needed to reach the next rating.
 */
int GetPointsUntilNextRating(int points)
{
    if (points < 676) return 676 - points;
    if (points < 1376) return 1376 - points;
    if (points < 2101) return 2101 - points;
    if (points < 2801) return 2801 - points;
    return 0;
}

/**
 * Returns the rating based on the points.
 *
 * @param points    The current points.
 * @return          The rating string.
 */
char[] GetRating(int points)
{
    if (points <= 675) return "Need more practice";
    if (points <= 1375) return "good";
    if (points <= 2100) return "excellent";
    if (points <= 2800) return "pro";
    return "Legendary";
}

/**
 * Repeats a character a specified number of times.
 *
 * @param character The character to repeat.
 * @param count     The number of times to repeat the character.
 * @return          The resulting string.
 */
char[] RepeatChar(char character, int count)
{
    char buffer[32];
    for (int i = 0; i < count; i++)
    {
        Format(buffer, sizeof(buffer), "%s%c", buffer, character);
    }
    return buffer;
}