# Achievement Category Filter

An Elder Scrolls Online addon that hides achievement categories with nothing matching the selected filter (All / Earned / Unearned), and brings them back when you change the filter.

It updates [Improved Achievement Categories](https://www.esoui.com/downloads/info3114-ImprovedAchievementCategories.html). That addon never unhides categories when you switch back to "All Achievements". It tries to hook `ACHIEVEMENTS:InitializeFilters`, but the game has already run that function by the time addons load, so the game's own filter callback stays in place, and that callback never rebuilds the category tree.

## Features

- Rebuilds the category tree whenever the filter changes, and keeps your current subcategory selected if it's still shown.
- Remembers your last filter choice across sessions (defaults to Unearned).
- The summary page only shows progress bars for categories visible under the current filter, and clicking a bar still opens its category.
- Works with the achievement search box.

## Settings

Settings > Add-Ons > Achievement Category Filter (needs [LibAddonMenu-2.0](https://www.esoui.com/downloads/info7-LibAddonMenu.html), optional): **Filter on open**, **Remember last filter**, and **Filter summary page**. Chat commands work without it: `/acf all|earned|unearned`, `/acf settings`.
