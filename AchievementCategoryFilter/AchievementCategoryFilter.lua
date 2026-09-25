local ADDON_NAME = "AchievementCategoryFilter"

local DEFAULTS =
{
    filterType = SI_ACHIEVEMENT_FILTER_SHOW_UNEARNED,
}

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

-- Prehooks: returning true skips the original, so the node is never added to the tree.
local function OnAddTopLevelCategory(self, categoryIndex)
    if categoryIndex == nil then return false end -- Summary
    local filterType = GetFilterType()
    if filterType == SI_ACHIEVEMENT_FILTER_SHOW_ALL then return false end
    return not CategoryHasVisibleAchievement(filterType, categoryIndex, true)
end

local function OnAddCategory(self, lookup, tree, nodeTemplate, parent, categoryIndex, name, hidesUnearned, normalIcon, pressedIcon, mouseoverIcon, isSummary, isFakedSubcategory)
    if nodeTemplate ~= "ZO_TreeLabelSubCategory" or not parent then return false end
    local filterType = GetFilterType()
    if filterType == SI_ACHIEVEMENT_FILTER_SHOW_ALL then return false end
    local subcategoryIndex = not isFakedSubcategory and categoryIndex or nil
    return not HasVisibleAchievement(filterType, parent.data.categoryIndex, subcategoryIndex, true)
end

-- Rebuild the category tree the same way the base game does after a search change,
-- so the selected subcategory is reselected and its content refreshed if it still exists.
local function RebuildCategories()
    ACHIEVEMENTS.forceUpdateContentOnCategoryReselect = true
    ACHIEVEMENTS:BuildCategories()
    ACHIEVEMENTS.forceUpdateContentOnCategoryReselect = false
end

-- The base game's filter callback only refreshes the achievement list, never the tree.
-- ACHIEVEMENTS:InitializeFilters has already run by the time addons load, so wrap the
-- existing combo box entries instead of hooking InitializeFilters.
local function HookFilterComboBox()
    local comboBox = ZO_ComboBox_ObjectFromContainer(ACHIEVEMENTS.categoryFilter)
    for _, entry in ipairs(comboBox:GetItems()) do
        local originalCallback = entry.callback
        entry.callback = function(...)
            if originalCallback then originalCallback(...) end
            if not isResettingFilters then
                sv.filterType = entry.filterType
            end
            RebuildCategories()
        end
    end
    return comboBox
end

local function SelectSavedFilter(comboBox)
    for index, entry in ipairs(comboBox:GetItems()) do
        if entry.filterType == sv.filterType then
            comboBox:SelectItemByIndex(index)
            return
        end
    end
end

-- Summary progress bars: only list categories that are visible in the tree under the
-- current filter (e.g. hide 100% complete categories when showing unearned), and pass the
-- real category index so clicking a bar still opens that category.
local SUMMARY_CATEGORY_BAR_HEIGHT = 16
local SUMMARY_CATEGORY_PADDING = 50
local FORCE_HIDE_PROGRESS_TEXT = true
local function UpdateSummary(self)
    self.summaryStatusBarPool:ReleaseAllObjects()
    self:UpdateStatusBar(self.summaryTotal, nil, GetEarnedAchievementPoints(), GetTotalAchievementPoints(), 0, nil, FORCE_HIDE_PROGRESS_TEXT)

    local filterType = GetFilterType()
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

local function OnAddonLoaded(event, addonName)
    if addonName ~= ADDON_NAME then return end
    EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED)

    sv = ZO_SavedVars:NewAccountWide("AchievementCategoryFilter_SV", 1, nil, DEFAULTS)

    ZO_PreHook(ACHIEVEMENTS, "AddTopLevelCategory", OnAddTopLevelCategory)
    ZO_PreHook(ACHIEVEMENTS, "AddCategory", OnAddCategory)
    ACHIEVEMENTS.UpdateSummary = UpdateSummary

    -- Clicking an achievement link resets the filter to "All"; don't remember that as the user's choice.
    ZO_PreHook(ACHIEVEMENTS, "ResetFilters", function() isResettingFilters = true end)
    SecurePostHook(ACHIEVEMENTS, "ResetFilters", function() isResettingFilters = false end)

    local comboBox = HookFilterComboBox()
    SelectSavedFilter(comboBox)
end
EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddonLoaded)
