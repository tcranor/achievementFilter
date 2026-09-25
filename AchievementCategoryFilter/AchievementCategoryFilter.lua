local ADDON_NAME = "AchievementCategoryFilter"
local TITLE = "Achievement Category Filter"
local VERSION = "1.0.0"

local DEFAULTS =
{
    filterOnOpen = SI_ACHIEVEMENT_FILTER_SHOW_UNEARNED,
    rememberLastFilter = true,
    filterSummary = true,
    -- filterType: the last filter picked in the journal, nil until one is picked
}

local FILTER_TYPES = { SI_ACHIEVEMENT_FILTER_SHOW_ALL, SI_ACHIEVEMENT_FILTER_SHOW_EARNED, SI_ACHIEVEMENT_FILTER_SHOW_UNEARNED }
local FILTER_COMMANDS = { all = SI_ACHIEVEMENT_FILTER_SHOW_ALL, earned = SI_ACHIEVEMENT_FILTER_SHOW_EARNED, unearned = SI_ACHIEVEMENT_FILTER_SHOW_UNEARNED }

local sv
local isResettingFilters = false

local function GetFilterType()
    return ACHIEVEMENTS.categoryFilter.filterType or SI_ACHIEVEMENT_FILTER_SHOW_ALL
end

-- Returns the achievement ids of one (sub)category. subcategoryIndex == nil means the
-- category's own top-level achievements (the "General" entry in the tree).
-- Unlike calling ZO_GetAchievementIds directly, a subcategory missing from the search
-- results yields nothing instead of every achievement in it.
local function GetIds(categoryIndex, subcategoryIndex, considerSearchResults)
    local numAchievements
    if subcategoryIndex then
        numAchievements = select(2, GetAchievementSubCategoryInfo(categoryIndex, subcategoryIndex))
    else
        numAchievements = select(3, GetAchievementCategoryInfo(categoryIndex))
    end

    local searchResults = considerSearchResults and ACHIEVEMENTS_MANAGER:GetSearchResults()
    if searchResults then
        local categoryResults = searchResults[categoryIndex]
        if not (categoryResults and categoryResults[subcategoryIndex or ZO_ACHIEVEMENTS_ROOT_SUBCATEGORY]) then
            return {}
        end
    end

    return ZO_GetAchievementIds(categoryIndex, subcategoryIndex, numAchievements or 0, considerSearchResults)
end

local function HasVisibleAchievement(filterType, categoryIndex, subcategoryIndex, considerSearchResults)
    local ids = GetIds(categoryIndex, subcategoryIndex, considerSearchResults)
    for i = 1, #ids do
        if ZO_ShouldShowAchievement(filterType, ids[i]) then
            return true
        end
    end
    return false
end

local function CategoryHasVisibleAchievement(filterType, categoryIndex, considerSearchResults)
    if HasVisibleAchievement(filterType, categoryIndex, nil, considerSearchResults) then
        return true
    end
    local numSubCategories = select(2, GetAchievementCategoryInfo(categoryIndex))
    for subcategoryIndex = 1, numSubCategories do
        if HasVisibleAchievement(filterType, categoryIndex, subcategoryIndex, considerSearchResults) then
            return true
        end
    end
    return false
end

-- Counters for /acf debug
local stats = { builds = 0, filterChanges = 0, hiddenCategories = 0, hiddenSubcategories = 0 }

-- Prehooks: returning true skips the original, so the node is never added to the tree.
local function OnBuildCategories()
    stats.builds = stats.builds + 1
    stats.lastBuildFilter = GetFilterType()
    stats.hiddenCategories = 0
    stats.hiddenSubcategories = 0
end

local function OnAddTopLevelCategory(self, categoryIndex)
    if categoryIndex == nil then return false end -- Summary
    local filterType = GetFilterType()
    if filterType == SI_ACHIEVEMENT_FILTER_SHOW_ALL then return false end
    local hide = not CategoryHasVisibleAchievement(filterType, categoryIndex, true)
    if hide then stats.hiddenCategories = stats.hiddenCategories + 1 end
    return hide
end

local function OnAddCategory(self, lookup, tree, nodeTemplate, parent, categoryIndex, name, hidesUnearned, normalIcon, pressedIcon, mouseoverIcon, isSummary, isFakedSubcategory)
    if nodeTemplate ~= "ZO_TreeLabelSubCategory" or not parent then return false end
    local filterType = GetFilterType()
    if filterType == SI_ACHIEVEMENT_FILTER_SHOW_ALL then return false end
    local subcategoryIndex = not isFakedSubcategory and categoryIndex or nil
    local hide = not HasVisibleAchievement(filterType, parent.data.categoryIndex, subcategoryIndex, true)
    if hide then stats.hiddenSubcategories = stats.hiddenSubcategories + 1 end
    return hide
end

-- Rebuild the category tree the same way the base game does after a search change,
-- so the selected subcategory is reselected and its content refreshed if it still exists.
local function RebuildCategories()
    ACHIEVEMENTS.forceUpdateContentOnCategoryReselect = true
    ACHIEVEMENTS:BuildCategories()
    ACHIEVEMENTS.forceUpdateContentOnCategoryReselect = false
end

-- The base game's filter callback sets the filter and calls RefreshVisibleCategoryFilter,
-- which only refreshes the achievement list, never the tree. Nothing else calls it, so
-- rebuild the tree right after it.
local function OnFilterChanged()
    stats.filterChanges = stats.filterChanges + 1
    if not isResettingFilters then
        sv.filterType = GetFilterType()
    end
    RebuildCategories()
end

local function SelectFilter(filterType)
    local comboBox = ZO_ComboBox_ObjectFromContainer(ACHIEVEMENTS.categoryFilter)
    for index, entry in ipairs(comboBox:GetItems()) do
        if entry.filterType == filterType then
            comboBox:SelectItemByIndex(index)
            return
        end
    end
end

-- Summary progress bars: with "Filter summary page" on, only list categories that are
-- visible in the tree under the current filter (e.g. hide 100% complete categories when
-- showing unearned). Either way, pass the real category index so clicking a bar still
-- opens that category.
local SUMMARY_CATEGORY_BAR_HEIGHT = 16
local SUMMARY_CATEGORY_PADDING = 50
local FORCE_HIDE_PROGRESS_TEXT = true
local function UpdateSummary(self)
    self.summaryStatusBarPool:ReleaseAllObjects()
    self:UpdateStatusBar(self.summaryTotal, nil, GetEarnedAchievementPoints(), GetTotalAchievementPoints(), 0, nil, FORCE_HIDE_PROGRESS_TEXT)

    local filterType = sv.filterSummary and GetFilterType() or SI_ACHIEVEMENT_FILTER_SHOW_ALL
    local yOffset = SUMMARY_CATEGORY_PADDING
    local barIndex = 1
    for categoryIndex = 1, GetNumAchievementCategories() do
        local name, _, numAchievements, earnedPoints, totalPoints, hidesPoints = GetAchievementCategoryInfo(categoryIndex)
        local visible = totalPoints > 0
            and (filterType == SI_ACHIEVEMENT_FILTER_SHOW_ALL or CategoryHasVisibleAchievement(filterType, categoryIndex, false))
        if visible then
            local statusBar = self.summaryStatusBarPool:AcquireObject()
            self:UpdateStatusBar(statusBar, name, earnedPoints, totalPoints, numAchievements, hidesPoints, FORCE_HIDE_PROGRESS_TEXT, categoryIndex)
            statusBar:ClearAnchors()

            if barIndex % 2 == 0 then
                statusBar:SetAnchor(TOPRIGHT, self.summaryTotal, BOTTOMRIGHT, 0, yOffset)
                yOffset = yOffset + SUMMARY_CATEGORY_PADDING + SUMMARY_CATEGORY_BAR_HEIGHT
            else
                statusBar:SetAnchor(TOPLEFT, self.summaryTotal, BOTTOMLEFT, 0, yOffset)
            end
            barIndex = barIndex + 1
        end
    end
end

-- Settings > Addons page. It needs the optional LibAddonMenu-2.0; /acf works without it.
local SETTINGS_PANEL_ID = "AchievementCategoryFilterSettings"
local settingsPanel

local function CreateSettingsPanel()
    local LAM = LibAddonMenu2
    if not LAM then return end

    settingsPanel = LAM:RegisterAddonPanel(SETTINGS_PANEL_ID, {
        type = "panel",
        name = TITLE,
        author = "TheGodDrums",
        version = VERSION,
        registerForRefresh = true,
        registerForDefaults = true,
    })

    local filterNames = {}
    for i, filterType in ipairs(FILTER_TYPES) do
        filterNames[i] = GetString(filterType)
    end

    LAM:RegisterOptionControls(SETTINGS_PANEL_ID, {
        {
            type = "dropdown",
            name = "Filter on open",
            tooltip = "The filter the achievement journal starts with after logging in or reloading the UI. With \"Remember last filter\" on, this only applies until you pick a filter in the journal.",
            choices = filterNames,
            choicesValues = FILTER_TYPES,
            default = DEFAULTS.filterOnOpen,
            getFunc = function() return sv.filterOnOpen end,
            setFunc = function(value) sv.filterOnOpen = value end,
        },
        {
            type = "checkbox",
            name = "Remember last filter",
            tooltip = "Start the journal on the filter you picked last, instead of \"Filter on open\".",
            default = DEFAULTS.rememberLastFilter,
            getFunc = function() return sv.rememberLastFilter end,
            setFunc = function(value) sv.rememberLastFilter = value end,
        },
        {
            type = "checkbox",
            name = "Filter summary page",
            tooltip = "Hide progress bars on the summary page for categories the filter hides, such as 100% complete categories when showing unearned achievements. Off shows every category, like the base game.",
            default = DEFAULTS.filterSummary,
            getFunc = function() return sv.filterSummary end,
            setFunc = function(value)
                sv.filterSummary = value
                ACHIEVEMENTS:UpdateSummary()
            end,
        },
    })
end

local function Print(message)
    d("[" .. TITLE .. "] " .. message)
end

local function FilterName(filterType)
    return filterType and GetString(filterType) or "none"
end

local function PrintDebug()
    Print(string.format("version %s, filter now: %s, tree last built with: %s",
        VERSION, FilterName(GetFilterType()), FilterName(stats.lastBuildFilter)))
    Print(string.format("hooks: BuildCategories %s, AddCategory %s, RefreshVisibleCategoryFilter %s",
        tostring(rawget(ACHIEVEMENTS, "BuildCategories") ~= nil),
        tostring(rawget(ACHIEVEMENTS, "AddCategory") ~= nil),
        tostring(rawget(ACHIEVEMENTS, "RefreshVisibleCategoryFilter") ~= nil)))
    Print(string.format("tree builds: %d, filter changes: %d, last build hid %d categories and %d subcategories",
        stats.builds, stats.filterChanges, stats.hiddenCategories, stats.hiddenSubcategories))

    local data = ACHIEVEMENTS.categoryTree:GetSelectedData()
    if not data or data.summary then
        Print("selected: summary (select a subcategory for details)")
        return
    end
    local categoryIndex, subcategoryIndex
    if data.parentData then
        categoryIndex = data.parentData.categoryIndex
        subcategoryIndex = not data.isFakedSubcategory and data.categoryIndex or nil
    else
        categoryIndex = data.categoryIndex
    end
    local ids = GetIds(categoryIndex, subcategoryIndex, true)
    local passing = 0
    for i = 1, #ids do
        if ZO_ShouldShowAchievement(GetFilterType(), ids[i]) then
            passing = passing + 1
        end
    end
    Print(string.format("selected: %s (category %d, subcategory %s): %d achievements, %d match the filter",
        tostring(data.name), categoryIndex, tostring(subcategoryIndex), #ids, passing))
end

local function HandleSlash(argument)
    local command = zo_strlower(zo_strtrim(argument or ""))
    if FILTER_COMMANDS[command] then
        SelectFilter(FILTER_COMMANDS[command])
        Print("Filter set to " .. GetString(FILTER_COMMANDS[command]) .. ".")
    elseif command == "debug" then
        PrintDebug()
    elseif command == "settings" then
        if settingsPanel then
            LibAddonMenu2:OpenToPanel(settingsPanel)
        else
            Print("Install LibAddonMenu-2.0 to get a settings page.")
        end
    else
        Print("commands (/acf):")
        Print("  /acf all | earned | unearned - change the achievement filter")
        Print("  /acf settings - open the settings page (needs LibAddonMenu-2.0)")
        Print("  /acf debug - print troubleshooting details")
    end
end

local function OnAddonLoaded(event, addonName)
    if addonName ~= ADDON_NAME then return end
    EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED)

    sv = ZO_SavedVars:NewAccountWide("AchievementCategoryFilter_SV", 1, nil, DEFAULTS)

    ZO_PreHook(ACHIEVEMENTS, "BuildCategories", OnBuildCategories)
    ZO_PreHook(ACHIEVEMENTS, "AddTopLevelCategory", OnAddTopLevelCategory)
    ZO_PreHook(ACHIEVEMENTS, "AddCategory", OnAddCategory)
    SecurePostHook(ACHIEVEMENTS, "RefreshVisibleCategoryFilter", OnFilterChanged)
    ACHIEVEMENTS.UpdateSummary = UpdateSummary

    -- Clicking an achievement link resets the filter to "All"; don't remember that as the user's choice.
    ZO_PreHook(ACHIEVEMENTS, "ResetFilters", function() isResettingFilters = true end)
    SecurePostHook(ACHIEVEMENTS, "ResetFilters", function() isResettingFilters = false end)

    SelectFilter(sv.rememberLastFilter and sv.filterType or sv.filterOnOpen)

    CreateSettingsPanel()
    SLASH_COMMANDS["/acf"] = HandleSlash
end
EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddonLoaded)
