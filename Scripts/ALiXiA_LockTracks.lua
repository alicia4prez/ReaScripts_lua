-- @description ALiXiA Folder Track Lock (Locks child tracks in folders)
-- @author ALiXiA
-- @version 2.0.2
-- @link Repository https://github.com/alicia4prez/ReaScripts_lua
-- @donation https://www.paypal.com/donate/?hosted_button_id=GXEUXZN7GD7W4
-- @about
--   Keeps folders locked so childs are not moved around.
-- @changelog 
--   + Fixed Metadata in file

local _, _, sectionID, cmdID = reaper.get_action_context()
local ext_section = "Rea_TrackHierarchyLock"

local function get_track_snapshot()
    local snap = {}
    local count = reaper.CountTracks(0)
    for i = 0, count - 1 do
        local tr = reaper.GetTrack(0, i)
        local guid = reaper.GetTrackGUID(tr)
        local depth = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
        snap[#snap + 1] = { guid = guid, depth = depth }
    end
    return snap
end

local function restore_snapshot(target_snap)
    local guid_to_track = {}
    local count = reaper.CountTracks(0)
    for i = 0, count - 1 do
        local tr = reaper.GetTrack(0, i)
        guid_to_track[reaper.GetTrackGUID(tr)] = tr
    end

    -- Verify all snapshotted tracks still exist
    for _, item in ipairs(target_snap) do
        if not guid_to_track[item.guid] then return end
    end

    reaper.PreventUIRefresh(1)
    reaper.Undo_BeginBlock()

    -- Re-order tracks back into original sequence
    for i, item in ipairs(target_snap) do
        local tr = guid_to_track[item.guid]
        local current_idx = reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") - 1
        local target_idx = i - 1
        if current_idx ~= target_idx then
            reaper.ReorderSelectedTracks(target_idx, 0)
        end
        reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", item.depth)
    end

    reaper.TrackList_AdjustWindows(false)
    reaper.Undo_EndBlock("Restore Locked Track Hierarchy", -1)
    reaper.PreventUIRefresh(-1)
end

local function is_snapshot_modified(base_snap)
    local current_count = reaper.CountTracks(0)
    if current_count ~= #base_snap then return false end -- User created/deleted tracks intentionally

    for i = 0, current_count - 1 do
        local tr = reaper.GetTrack(0, i)
        local guid = reaper.GetTrackGUID(tr)
        local depth = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
        if guid ~= base_snap[i + 1].guid or depth ~= base_snap[i + 1].depth then
            return true
        end
    end
    return false
end

-- Initialize or Toggle Off
local running = reaper.GetExtState(ext_section, "running")
if running == "1" then
    reaper.SetExtState(ext_section, "running", "0", false)
    reaper.SetToggleCommandState(sectionID, cmdID, 0)
    reaper.RefreshToolbar2(sectionID, cmdID)
    return
end

-- Engage Lock
reaper.SetExtState(ext_section, "running", "1", false)
reaper.SetToggleCommandState(sectionID, cmdID, 1)
reaper.RefreshToolbar2(sectionID, cmdID)

local saved_snapshot = get_track_snapshot()

local function main_loop()
    if reaper.GetExtState(ext_section, "running") ~= "1" then
        reaper.SetToggleCommandState(sectionID, cmdID, 0)
        reaper.RefreshToolbar2(sectionID, cmdID)
        return
    end

    if is_snapshot_modified(saved_snapshot) then
        restore_snapshot(saved_snapshot)
    end

    reaper.defer(main_loop)
end

reaper.defer(main_loop)
