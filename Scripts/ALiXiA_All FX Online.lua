-- @description Bring All Project FX Online (Tracks, Master, Input, Monitoring, and Takes)
-- @author ALiXiA
-- @version 1.0.0
-- @donation https://www.paypal.com/donate/?hosted_button_id=GXEUXZN7GD7W4
-- @about
--  Brings all track Fx, take Fx, input Fx in project online.

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

-- Helper function to bring all FX (standard and input/monitoring) online for a given track
local function SetTrackFXOnline(track, is_master)
    if not track then return end
    
    -- 1. Standard Track FX chain
    local fx_count = reaper.TrackFX_GetCount(track)
    for i = 0, fx_count - 1 do
        if reaper.TrackFX_GetOffline(track, i) then
            reaper.TrackFX_SetOffline(track, i, false)
        end
    end
    
    -- 2. Input FX chain (or Monitoring FX if on Master Track)
    -- In REAPER's API, Input/Monitoring FX indices are accessed by adding 0x1000000
    local rec_fx_count = reaper.TrackFX_GetRecCount(track)
    for i = 0, rec_fx_count - 1 do
        local rec_idx = i + 0x1000000
        if reaper.TrackFX_GetOffline(track, rec_idx) then
            reaper.TrackFX_SetOffline(track, rec_idx, false)
        end
    end
end

-- 1. Process Master Track (Master FX + Monitoring FX)
local master_track = reaper.GetMasterTrack(0)
SetTrackFXOnline(master_track, true)

-- 2. Process all regular tracks (Track FX + Input FX)
local track_count = reaper.CountTracks(0)
for i = 0, track_count - 1 do
    local track = reaper.GetTrack(0, i)
    SetTrackFXOnline(track, false)
end

-- 3. Process all Media Items and all of their Takes (Take FX)
local item_count = reaper.CountMediaItems(0)
for i = 0, item_count - 1 do
    local item = reaper.GetMediaItem(0, i)
    local take_count = reaper.CountTakes(item)
    
    for j = 0, take_count - 1 do
        local take = reaper.GetTake(item, j)
        if take then
            local take_fx_count = reaper.TakeFX_GetCount(take)
            for k = 0, take_fx_count - 1 do
                if reaper.TakeFX_GetOffline(take, k) then
                    reaper.TakeFX_SetOffline(take, k, false)
                end
            end
        end
    end
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Bring All Project and Take FX Online", -1)
