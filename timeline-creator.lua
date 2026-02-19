-- ================================================
-- Timeline Creator
-- Part of PostFlows toolkit for DaVinci Resolve
-- https://github.com/postflows
-- ================================================

--[[
    RMT Timeline Creator with Custom Tracks
    A DaVinci Resolve script for creating timelines with custom video and audio tracks
    
    Description:
    This script provides a GUI interface for creating new timelines in DaVinci Resolve
    with customizable track configurations. Users can specify the number of video and audio
    tracks, assign custom names to each track, and save/load presets for quick setup.
    
    Features:
    - Create timelines with custom names
    - Configure number of video tracks (1-20)
    - Configure number of audio tracks (1-20)
    - Assign custom names to each track
    - Save and load track configuration presets
    - Dynamic window resizing based on track count
    - Automatic track naming with sensible defaults
    
    Usage:
    1. Enter a timeline name
    2. Set the number of video and audio tracks using spinboxes
    3. Optionally rename tracks in the provided fields
    4. Click "Create Timeline" to create the timeline with specified configuration
    5. Use presets to save and quickly load common track configurations
    
    Presets:
    - Save current track configuration as a preset for future use
    - Load saved presets to quickly apply track setups
    - Delete unwanted presets
    
    Requirements:
    - DaVinci Resolve Studio
    - An open project
    
    Version: 1.1
    Author: Sergey Knyazkov
--]]

-- Initialize Resolve
local resolve = Resolve()
if not resolve then
    print("Error: DaVinci Resolve is not running")
    return
end

local projectManager = resolve:GetProjectManager()
local project = projectManager:GetCurrentProject()
if not project then
    print("Error: No project is open")
    return
end

local mediaPool = project:GetMediaPool()
if not mediaPool then
    print("Error: Media Pool is not available")
    return
end

-- Constants: preset file path (macOS/Linux: HOME; Windows: APPDATA)
local function get_presets_path()
    local home = os.getenv("HOME")
    local appdata = os.getenv("APPDATA")
    if appdata and appdata ~= "" then
        return appdata:gsub("\\", "/") .. "/DaVinci Resolve Timeline Presets.lua"
    end
    if home and home ~= "" then
        return home .. "/.davinci_resolve_timeline_presets.lua"
    end
    return ".davinci_resolve_timeline_presets.lua"
end
local PRESETS_FILE = get_presets_path()
local DEFAULT_TIMECODE = "00:00:00:00"

-- UI Manager
local ui = fu.UIManager
local disp = bmd.UIDispatcher(ui)

-- Utility: Serialize table to Lua code
local function serializeTable(tbl, indent)
    indent = indent or 0
    local serialized = "{\n"
    local padding = string.rep("    ", indent)
    
    for key, value in pairs(tbl) do
        local keyStr = type(key) == "string" and string.format("[%q]", key) or "[" .. key .. "]"
        if type(value) == "table" then
            serialized = serialized .. padding .. keyStr .. " = " .. serializeTable(value, indent + 1) .. ",\n"
        else
            local valueStr = type(value) == "string" and string.format("%q", value) or tostring(value)
            serialized = serialized .. padding .. keyStr .. " = " .. valueStr .. ",\n"
        end
    end
    
    serialized = serialized .. string.rep("    ", indent - 1) .. "}"
    return serialized
end

-- Validate and normalize SMPTE timecode strings
local function normalize_timecode(input)
    if not input then
        return DEFAULT_TIMECODE, false
    end
    local trimmed = input:match("^%s*(.-)%s*$")
    if trimmed == "" then
        return DEFAULT_TIMECODE, false
    end
    local hours, minutes, seconds, frames = trimmed:match("^(%d+):(%d%d):(%d%d)[:;](%d%d)$")
    if not hours then
        hours, minutes, seconds, frames = trimmed:match("^(%d+):(%d%d):(%d%d):(%d%d)$")
    end
    if not hours then
        return DEFAULT_TIMECODE, false
    end
    local h = tonumber(hours) or 0
    local m = math.min(tonumber(minutes) or 0, 59)
    local s = math.min(tonumber(seconds) or 0, 59)
    local f = math.min(tonumber(frames) or 0, 59)
    local normalized = string.format("%02d:%02d:%02d:%02d", h, m, s, f)
    return normalized, true
end

-- Utility: Load presets from file
local function load_presets()
    local presets = {}
    local file = io.open(PRESETS_FILE, "r")
    if file then
        local chunk = file:read("*a")
        file:close()
        if chunk and chunk ~= "" then
            if not chunk:match("^return") then
                chunk = "return " .. chunk
            end
            local loaded, err = load(chunk)
            if loaded then
                local ok, result = pcall(loaded)
                if ok then
                    presets = result or {}
                end
            end
        end
    end
    return presets
end

-- Utility: Save presets to file
local function save_presets(presets)
    local file = io.open(PRESETS_FILE, "w")
    if file then
        file:write("return " .. serializeTable(presets))
        file:close()
        return true
    end
    return false
end

-- Create UI with all track name fields pre-created
local function create_ui()
    local maxTracks = 20
    
    -- Build video track name fields
    local videoTrackFields = {}
    for i = 1, maxTracks do
        local defaultName = ""
        if i == 1 then defaultName = "Video"
        elseif i == 2 then defaultName = "VFX"
        elseif i == 3 then defaultName = "Titles"
        else defaultName = "Video " .. i end
        
        videoTrackFields[i] = ui:LineEdit{
            ID = "videoTrackName" .. i,
            Text = defaultName,
            PlaceholderText = "Track " .. i .. " name",
            MaximumHeight = 24,
            StyleSheet = "font-size: 11px; padding: 2px 4px;"
        }
    end
    
    -- Build audio track name fields
    local audioTrackFields = {}
    for i = 1, maxTracks do
        local defaultName = ""
        if i == 1 then defaultName = "VO"
        elseif i == 2 then defaultName = "SFX"
        else defaultName = "Audio " .. i end
        
        audioTrackFields[i] = ui:LineEdit{
            ID = "audioTrackName" .. i,
            Text = defaultName,
            PlaceholderText = "Track " .. i .. " name",
            MaximumHeight = 24,
            StyleSheet = "font-size: 11px; padding: 2px 4px;"
        }
    end
    
    -- Build video container VGroup - elements must be passed as array
    local videoContainer = {ID = "videoTrackContainer", Spacing = 2}
    for i = 1, maxTracks do
        table.insert(videoContainer, videoTrackFields[i])
    end
    
    -- Build audio container VGroup - elements must be passed as array
    local audioContainer = {ID = "audioTrackContainer", Spacing = 2}
    for i = 1, maxTracks do
        table.insert(audioContainer, audioTrackFields[i])
    end
    
    local window = disp:AddWindow({
        ID = 'MainWindow',
        WindowTitle = 'Timeline Creator',
        Geometry = {100, 100, 420, 500},
        Spacing = 8,
        
        ui:VGroup{
            ID = 'root',
            Spacing = 8,
            
            -- Timeline name
            ui:HGroup{
                Weight = 0,
                ui:Label{Text = "Timeline Name:", Weight = 0.35},
                ui:LineEdit{ID = "timelineName", Text = "New Timeline", Weight = 0.65}
            },
            
            -- Track counts
            ui:HGroup{
                Weight = 0,
                ui:Label{Text = "Video Tracks:", Weight = 0.35},
                ui:SpinBox{ID = "videoTrackCount", Value = 3, Minimum = 1, Maximum = 20, Weight = 0.65, MaximumWidth = 80}
            },
            ui:HGroup{
                Weight = 0,
                ui:Label{Text = "Audio Tracks:", Weight = 0.35},
                ui:SpinBox{ID = "audioTrackCount", Value = 2, Minimum = 1, Maximum = 20, Weight = 0.65, MaximumWidth = 80}
            },
            ui:HGroup{
                Weight = 0,
                ui:Label{Text = "Start Timecode:", Weight = 0.35},
                ui:LineEdit{
                    ID = "timelineStartTimecode",
                    Text = DEFAULT_TIMECODE,
                    Weight = 0.65,
                    MaximumWidth = 110,
                    PlaceholderText = "HH:MM:SS:FF",
                    StyleSheet = "font-size: 11px; padding: 2px 4px;"
                }
            },
            
            -- Video track names section
            ui:Label{Text = "Video Track Names:", StyleSheet = "font-weight: bold; font-size: 11px;", Weight = 0},
            ui:VGroup{
                ID = "videoTrackContainerWrapper",
                Weight = 0,
                StyleSheet = "border: 1px solid #444; border-radius: 3px; padding: 3px; background-color: #1e1e1e;",
                ui:VGroup(videoContainer)
            },
            
            -- Audio track names section
            ui:Label{Text = "Audio Track Names:", StyleSheet = "font-weight: bold; font-size: 11px;", Weight = 0},
            ui:VGroup{
                ID = "audioTrackContainerWrapper",
                Weight = 0,
                StyleSheet = "border: 1px solid #444; border-radius: 3px; padding: 3px; background-color: #1e1e1e;",
                ui:VGroup(audioContainer)
            },
            
            -- Presets section
            ui:Label{Text = "Presets:", StyleSheet = "font-weight: bold; font-size: 12px; margin-top: 5px;", Weight = 0},
            ui:HGroup{
                Weight = 0,
                ui:Label{Text = "Preset:", Weight = 0.25},
                ui:ComboBox{ID = "presetCombo", Weight = 0.75}
            },
            ui:HGroup{
                Weight = 0,
                ui:LineEdit{ID = "presetNameInput", PlaceholderText = "Preset name", Weight = 0.5},
                ui:Button{ID = "savePresetBtn", Text = "Save", Weight = 0.16, MaximumWidth = 60},
                ui:Button{ID = "loadPresetBtn", Text = "Load", Weight = 0.16, MaximumWidth = 60},
                ui:Button{ID = "deletePresetBtn", Text = "Del", Weight = 0.16, MaximumWidth = 50}
            },
            
            -- Status label
            ui:Label{ID = "statusLabel", Text = "Ready", StyleSheet = "color: #686A6C; font-style: italic; font-size: 11px;", Weight = 0},
            
            -- Create button
            ui:Button{ID = "createBtn", Text = "Create Timeline", Weight = 1, StyleSheet = [[
                QPushButton {
                    border: 1px solid #2C6E49;
                    max-height: 32px;
                    border-radius: 16px;
                    background-color: #4C956C;
                    color: #FFFFFF;
                    min-height: 32px;
                    font-size: 14px;
                    font-weight: bold;
                }
                QPushButton:hover {
                    border: 1px solid #c0c0c0;
                    background-color: #61B15A;
                }
                QPushButton:pressed {
                    border: 2px solid #c0c0c0;
                    background-color: #76C893;
                }
            ]]}
        }
    })
    
    return window
end

-- Main execution
local window = create_ui()
local itm = window:GetItems()

-- Calculate window height based on visible track fields
local function calculate_window_height()
    local videoCount = itm.videoTrackCount.Value or 3
    local audioCount = itm.audioTrackCount.Value or 2
    
    -- Base height for fixed UI elements (Timeline name, track counts, labels, presets, status, button, spacing)
    local baseHeight = 300
    
    -- Height per track field (field height + spacing)
    local fieldHeight = 26  -- 24px field + 2px spacing
    
    -- Calculate height for video track section
    local videoLabelHeight = 18  -- Label height
    local videoContainerPadding = 6  -- Top + bottom padding
    local videoFieldsHeight = videoCount * fieldHeight
    local videoSectionHeight = videoLabelHeight + videoContainerPadding + videoFieldsHeight
    
    -- Calculate height for audio track section
    local audioLabelHeight = 18  -- Label height
    local audioContainerPadding = 6  -- Top + bottom padding
    local audioFieldsHeight = audioCount * fieldHeight
    local audioSectionHeight = audioLabelHeight + audioContainerPadding + audioFieldsHeight
    
    -- Total height
    local totalHeight = baseHeight + videoSectionHeight + audioSectionHeight
    
    -- Enforce minimum and maximum heights
    totalHeight = math.max(400, totalHeight)  -- Minimum height
    totalHeight = math.min(900, totalHeight)   -- Maximum height (increased for more tracks)
    
    return totalHeight
end

-- Update window size based on visible track fields
local function update_window_size()
    if not window then return end
    
    local currentWidth = 420
    local success, geometry = pcall(function() return window:GetGeometry() end)
    if success and geometry and geometry.width and geometry.width > 0 then
        currentWidth = geometry.width
    end
    
    local newHeight = calculate_window_height()
    
    -- Resize the window
    pcall(function() 
        window:Resize({currentWidth, newHeight})
    end)
end

-- Update visibility of track name fields based on count
local function update_track_fields_visibility()
    local videoCount = itm.videoTrackCount.Value or 3
    local audioCount = itm.audioTrackCount.Value or 2
    
    -- Show/hide video track fields
    for i = 1, 20 do
        local field = itm["videoTrackName" .. i]
        if field then
            local isVisible = (i <= videoCount)
            field.Visible = isVisible
            field.Hidden = not isVisible
        end
    end
    
    -- Show/hide audio track fields
    for i = 1, 20 do
        local field = itm["audioTrackName" .. i]
        if field then
            local isVisible = (i <= audioCount)
            field.Visible = isVisible
            field.Hidden = not isVisible
        end
    end
    
    -- Update window size after visibility change
    update_window_size()
end

-- Get current settings from UI
local function get_current_settings()
    local settings = {
        timelineName = itm.timelineName.Text or "New Timeline",
        videoTrackCount = itm.videoTrackCount.Value or 3,
        audioTrackCount = itm.audioTrackCount.Value or 2,
        videoTrackNames = {},
        audioTrackNames = {},
        startTimecode = DEFAULT_TIMECODE
    }
    
    local rawTimecode = itm.timelineStartTimecode.Text or DEFAULT_TIMECODE
    rawTimecode = rawTimecode:match("^%s*(.-)%s*$")
    if rawTimecode == "" then
        rawTimecode = DEFAULT_TIMECODE
    end
    settings.startTimecode = normalize_timecode(rawTimecode)
    
    -- Collect video track names
    for i = 1, settings.videoTrackCount do
        local field = itm["videoTrackName" .. i]
        if field then
            local name = field.Text or ""
            if name == "" then
                name = "Video " .. i
            end
            table.insert(settings.videoTrackNames, name)
        end
    end
    
    -- Collect audio track names
    for i = 1, settings.audioTrackCount do
        local field = itm["audioTrackName" .. i]
        if field then
            local name = field.Text or ""
            if name == "" then
                name = "Audio " .. i
            end
            table.insert(settings.audioTrackNames, name)
        end
    end
    
    return settings
end

-- Apply settings to UI
local function apply_settings_to_ui(settings)
    if settings.timelineName then
        itm.timelineName.Text = settings.timelineName
    end
    
    if settings.videoTrackCount then
        itm.videoTrackCount.Value = settings.videoTrackCount
    end
    
    if settings.audioTrackCount then
        itm.audioTrackCount.Value = settings.audioTrackCount
    end
    
    itm.timelineStartTimecode.Text = settings.startTimecode or DEFAULT_TIMECODE
    
    -- Apply track names
    if settings.videoTrackNames then
        for i = 1, math.min(#settings.videoTrackNames, 20) do
            local field = itm["videoTrackName" .. i]
            if field then
                field.Text = settings.videoTrackNames[i]
            end
        end
    end
    
    if settings.audioTrackNames then
        for i = 1, math.min(#settings.audioTrackNames, 20) do
            local field = itm["audioTrackName" .. i]
            if field then
                field.Text = settings.audioTrackNames[i]
            end
        end
    end
    
    update_track_fields_visibility()
end

-- Load preset list
local function load_preset_list()
    local presets = load_presets()
    itm.presetCombo:Clear()
    
    if next(presets) == nil then
        itm.presetCombo:AddItem("No presets available")
    else
        local presetNames = {}
        for name, _ in pairs(presets) do
            table.insert(presetNames, name)
        end
        table.sort(presetNames)
        for _, name in ipairs(presetNames) do
            itm.presetCombo:AddItem(name)
        end
    end
end

-- Save preset
local function save_preset()
    local presetName = itm.presetNameInput.Text or ""
    if presetName == "" then
        itm.statusLabel.Text = "Preset name cannot be empty"
        return
    end
    
    local settings = get_current_settings()
    local presets = load_presets()
    
    -- Check if preset exists
    if presets[presetName] then
        local result = fu:AskQuestion("Overwrite Preset", 
            "Preset '" .. presetName .. "' already exists. Overwrite?")
        if not result then
            itm.statusLabel.Text = "Preset save cancelled"
            return
        end
    end
    
    presets[presetName] = settings
    if save_presets(presets) then
        load_preset_list()
        itm.presetCombo.CurrentText = presetName
        itm.presetNameInput.Text = ""
        itm.statusLabel.Text = "Preset '" .. presetName .. "' saved successfully"
    else
        itm.statusLabel.Text = "Error saving preset"
    end
end

-- Load preset
local function load_preset()
    local presetName = itm.presetCombo.CurrentText or ""
    if presetName == "" or presetName == "No presets available" then
        itm.statusLabel.Text = "No preset selected"
        return
    end
    
    local presets = load_presets()
    if presets[presetName] then
        apply_settings_to_ui(presets[presetName])
        update_window_size()  -- Update window size after loading preset
        itm.statusLabel.Text = "Preset '" .. presetName .. "' loaded successfully"
    else
        itm.statusLabel.Text = "Preset '" .. presetName .. "' not found"
    end
end

-- Delete preset
local function delete_preset()
    local presetName = itm.presetCombo.CurrentText or ""
    if presetName == "" or presetName == "No presets available" then
        itm.statusLabel.Text = "No preset selected"
        return
    end
    
    local presets = load_presets()
    if presets[presetName] then
        presets[presetName] = nil
        if save_presets(presets) then
            load_preset_list()
            itm.statusLabel.Text = "Preset '" .. presetName .. "' deleted successfully"
        else
            itm.statusLabel.Text = "Error deleting preset"
        end
    else
        itm.statusLabel.Text = "Preset '" .. presetName .. "' not found"
    end
end

-- Create timeline with current settings
local function create_timeline()
    local settings = get_current_settings()
    local timecodeWarning = nil
    
    -- Validate timeline name
    if settings.timelineName == "" then
        itm.statusLabel.Text = "Error: Timeline name cannot be empty"
        return
    end
    
    -- Check if timeline name already exists
    local timelineCount = project:GetTimelineCount()
    for i = 1, timelineCount do
        local tl = project:GetTimelineByIndex(i)
        if tl and tl:GetName() == settings.timelineName then
            itm.statusLabel.Text = "Error: Timeline '" .. settings.timelineName .. "' already exists"
            return
        end
    end
    
    itm.statusLabel.Text = "Creating timeline..."
    
    -- Create empty timeline
    local timeline = mediaPool:CreateEmptyTimeline(settings.timelineName)
    if not timeline then
        itm.statusLabel.Text = "Error: Failed to create timeline"
        return
    end
    
    -- Set as current timeline
    project:SetCurrentTimeline(timeline)
    
    -- Apply start timecode
    local desiredTimecode = settings.startTimecode or DEFAULT_TIMECODE
    local normalizedTimecode, isValidInput = normalize_timecode(desiredTimecode)
    if not isValidInput then
        timecodeWarning = "Invalid start timecode format. Using " .. normalizedTimecode
    end
    local startSuccess = timeline.SetStartTimecode and timeline:SetStartTimecode(normalizedTimecode)
    if not startSuccess then
        local warning = "Unable to set start timecode to " .. normalizedTimecode
        print("Warning: " .. warning)
        timecodeWarning = warning
    end
    
    -- Get current track counts
    local currentVideoCount = timeline:GetTrackCount("video")
    local currentAudioCount = timeline:GetTrackCount("audio")
    
    -- Add video tracks if needed
    if settings.videoTrackCount > currentVideoCount then
        for i = currentVideoCount + 1, settings.videoTrackCount do
            timeline:AddTrack("video")
        end
    end
    
    -- Add audio tracks if needed
    if settings.audioTrackCount > currentAudioCount then
        for i = currentAudioCount + 1, settings.audioTrackCount do
            timeline:AddTrack("audio")
        end
    end
    
    -- Rename video tracks
    for i = 1, math.min(settings.videoTrackCount, #settings.videoTrackNames) do
        local trackName = settings.videoTrackNames[i]
        if trackName and trackName ~= "" then
            timeline:SetTrackName("video", i, trackName)
        end
    end
    
    -- Rename audio tracks
    for i = 1, math.min(settings.audioTrackCount, #settings.audioTrackNames) do
        local trackName = settings.audioTrackNames[i]
        if trackName and trackName ~= "" then
            timeline:SetTrackName("audio", i, trackName)
        end
    end
    
    -- Final verification
    local finalVideoCount = timeline:GetTrackCount("video")
    local finalAudioCount = timeline:GetTrackCount("audio")
    
    local statusText = "Timeline created successfully! Video: " .. finalVideoCount .. ", Audio: " .. finalAudioCount
    if timecodeWarning then
        statusText = statusText .. " | " .. timecodeWarning
    end
    itm.statusLabel.Text = statusText
    
    print("Timeline created: " .. settings.timelineName)
    print("Video tracks: " .. finalVideoCount)
    print("Audio tracks: " .. finalAudioCount)
end

-- Initialize UI
update_track_fields_visibility()
load_preset_list()

-- Initial window size adjustment
update_window_size()

-- Event handlers
function window.On.videoTrackCount.ValueChanged(ev)
    update_track_fields_visibility()
end

function window.On.audioTrackCount.ValueChanged(ev)
    update_track_fields_visibility()
end

function window.On.savePresetBtn.Clicked(ev)
    save_preset()
end

function window.On.loadPresetBtn.Clicked(ev)
    load_preset()
end

function window.On.deletePresetBtn.Clicked(ev)
    delete_preset()
end

function window.On.createBtn.Clicked(ev)
    create_timeline()
end

function window.On.MainWindow.Close(ev)
    disp:ExitLoop()
end

-- Show window
window:Show()
disp:RunLoop()
window:Hide()
