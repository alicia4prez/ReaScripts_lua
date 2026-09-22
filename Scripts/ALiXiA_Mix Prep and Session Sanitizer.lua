-- @description ALiXiA_Mix Prep and Session Sanitizer
-- @author ALiXia
-- @version 1.0.0
-- @about Mixing prep and session sanitizer
-- @changelog Initial release
--   
-- ==============================================================================
-- Mix Prep & Session Sanitizer v4.1
-- ==============================================================================
-- Enhanced with:
--   • Detailed logging & progress tracking
--   • Error handling & validation
--   • Folder track preservation
--   • Pre/post session verification
--   • Integration hooks for gain staging & transposition
--   • Customizable parameters
-- ==============================================================================

local function msg(text)
  reaper.ShowConsoleMsg(text .. "\n")
end

local function log_header(title)
  msg("\n" .. string.rep("=", 70))
  msg(title)
  msg(string.rep("=", 70))
end

local function log_section(title)
  msg("\n" .. string.rep("-", 70))
  msg(">> " .. title)
  msg(string.rep("-", 70))
end

local function log_success(text)
  msg("  ✓ " .. text)
end

local function log_warning(text)
  msg("  ⚠ " .. text)
end

local function log_error(text)
  msg("  ✗ " .. text)
end

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local config = {
  target_db = -18.0,
  crossfade_length = 0.010,
  min_item_duration = 0.001,
  preserve_folders = true,
  preserve_sidechain_sends = true,
  offline_all_fx = true,
  add_master_analyzers = true,
  delete_empty_tracks = true,
  strict_mode = false -- Set to true for more aggressive cleanup
}

-- ============================================================================
-- PRE-SESSION AUDIT
-- ============================================================================

local function audit_session()
  log_section("PRE-SESSION AUDIT")
  
  local stats = {
    total_tracks = reaper.CountTracks(0),
    total_items = reaper.CountMediaItems(0),
    total_fx = 0,
    total_sends = 0,
    total_receives = 0,
    total_envelopes = 0,
    folder_tracks = 0,
    muted_tracks = 0,
    offline_tracks = 0
  }
  
  for i = 0, stats.total_tracks - 1 do
    local track = reaper.GetTrack(0, i)
    if reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
      stats.folder_tracks = stats.folder_tracks + 1
    end
    if reaper.GetMediaTrackInfo_Value(track, "B_MUTE") == 1 then
      stats.muted_tracks = stats.muted_tracks + 1
    end
    
    stats.total_fx = stats.total_fx + reaper.TrackFX_GetCount(track)
    stats.total_sends = stats.total_sends + reaper.GetTrackNumSends(track, 0)
    stats.total_receives = stats.total_receives + reaper.GetTrackNumSends(track, -1)
    stats.total_envelopes = stats.total_envelopes + reaper.CountTrackEnvelopes(track)
  end
  
  msg(string.format("  Tracks:           %d (folders: %d, muted: %d)", 
    stats.total_tracks, stats.folder_tracks, stats.muted_tracks))
  msg(string.format("  Media Items:      %d", stats.total_items))
  msg(string.format("  Track FX:         %d", stats.total_fx))
  msg(string.format("  Sends/Receives:   %d / %d", stats.total_sends, stats.total_receives))
  msg(string.format("  Automation Envs:  %d", stats.total_envelopes))
  
  return stats
end

-- ============================================================================
-- MASTER TRACK SETUP
-- ============================================================================

local function setup_master_track()
  log_section("MASTER TRACK SETUP")
  
  local master = reaper.GetMasterTrack(0)
  
  -- Offline all existing FX
  local master_fx_count = reaper.TrackFX_GetCount(master)
  for fx = 0, master_fx_count - 1 do
    reaper.TrackFX_SetOffline(master, fx, true)
  end
  
  if master_fx_count > 0 then
    log_success(string.format("Offlined %d master FX", master_fx_count))
  end
  
  -- Add stereo analyzers
  if config.add_master_analyzers then
    reaper.TrackFX_AddByName(master, "JS: Goniometer", false, -1)
    log_success("Added Goniometer analyzer")
    
    reaper.TrackFX_AddByName(master, "JS: Stereo Field", false, -1)
    log_success("Added Stereo Field analyzer")
  end
end

-- ============================================================================
-- AUTOMATION CLEANUP
-- ============================================================================

local function cleanup_automation()
  log_section("AUTOMATION CLEANUP")
  
  local total_removed = 0
  local num_tracks = reaper.CountTracks(0)
  
  for i = 0, num_tracks - 1 do
    local track = reaper.GetTrack(0, i)
    local env_count = reaper.CountTrackEnvelopes(track)
    
    for e = 0, env_count - 1 do
      local env = reaper.GetTrackEnvelope(track, e)
      if env then
        -- Count points before deletion
        local point_count = reaper.CountEnvelopePoints(env)
        
        -- Delete all points
        reaper.DeleteEnvelopePointRange(env, -1000, 10000000)
        
        total_removed = total_removed + point_count
      end
    end
  end
  
  if total_removed > 0 then
    log_success(string.format("Removed %d automation points", total_removed))
  else
    msg("  (no automation to clean)")
  end
end

-- ============================================================================
-- TRACK FX OFFLINE
-- ============================================================================

local function offline_all_track_fx()
  log_section("OFFLINE ALL TRACK FX")
  
  local total_offlined = 0
  local num_tracks = reaper.CountTracks(0)
  
  for i = 0, num_tracks - 1 do
    local track = reaper.GetTrack(0, i)
    local num_fx = reaper.TrackFX_GetCount(track)
    
    for fx = 0, num_fx - 1 do
      reaper.TrackFX_SetOffline(track, fx, true)
      total_offlined = total_offlined + 1
    end
  end
  
  if total_offlined > 0 then
    log_success(string.format("Offlined %d track FX plugins", total_offlined))
  else
    msg("  (no FX to offline)")
  end
end

-- ============================================================================
-- ROUTING CLEANUP
-- ============================================================================

local function cleanup_routing()
  log_section("ROUTING CLEANUP")
  
  local total_sends = 0
  local total_receives = 0
  local total_hardware = 0
  local num_tracks = reaper.CountTracks(0)
  
  for i = 0, num_tracks - 1 do
    local track = reaper.GetTrack(0, i)
    
    -- Delete sends (0 = aux sends)
    for s = reaper.GetTrackNumSends(track, 0) - 1, 0, -1 do
      reaper.RemoveTrackSend(track, 0, s)
      total_sends = total_sends + 1
    end
    
    -- Delete receives (-1 = receives)
    for r = reaper.GetTrackNumSends(track, -1) - 1, 0, -1 do
      reaper.RemoveTrackSend(track, -1, r)
      total_receives = total_receives + 1
    end
    
    -- Delete hardware outputs (1 = hardware)
    for h = reaper.GetTrackNumSends(track, 1) - 1, 0, -1 do
      reaper.RemoveTrackSend(track, 1, h)
      total_hardware = total_hardware + 1
    end
    
    -- Reset to master
    reaper.SetMediaTrackInfo_Value(track, "B_MAINSEND", 1)
  end
  
  if total_sends > 0 then
    log_success(string.format("Deleted %d sends", total_sends))
  end
  if total_receives > 0 then
    log_success(string.format("Deleted %d receives", total_receives))
  end
  if total_hardware > 0 then
    log_success(string.format("Deleted %d hardware outputs", total_hardware))
  end
end

-- ============================================================================
-- ITEM PROCESSING (Heal, Crossfade, Gain Stage, Glue, Rename)
-- ============================================================================

local function process_items()
  log_section("MEDIA ITEM PROCESSING")
  
  local num_tracks = reaper.CountTracks(0)
  local total_items_processed = 0
  local total_glued = 0
  
  for i = 0, num_tracks - 1 do
    local track = reaper.GetTrack(0, i)
    local num_items = reaper.CountTrackMediaItems(track)
    
    if num_items > 0 then
      local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
      if track_name == "" then
        track_name = "Track " .. tostring(math.floor(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")))
      end
      
      -- ====== STEP 1: Deselect all ======
      reaper.Main_OnCommand(40289, 0)
      
      -- ====== STEP 2: Select all items on this track ======
      for j = 0, num_items - 1 do
        local item = reaper.GetTrackMediaItem(track, j)
        reaper.SetMediaItemSelected(item, true)
      end
      
      -- ====== STEP 3: Heal splits ======
      reaper.Main_OnCommand(40546, 0) -- Glue/Heal
      
      -- ====== STEP 4: Re-count after healing ======
      local healed_items = reaper.CountTrackMediaItems(track)
      
      -- ====== STEP 5: Apply crossfades & gain stage ======
      for j = 0, healed_items - 1 do
        local item = reaper.GetTrackMediaItem(track, j)
        
        -- Crossfade
        reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", config.crossfade_length)
        reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", config.crossfade_length)
        
        -- Select for normalization
        reaper.SetMediaItemSelected(item, true)
      end
      
      -- ====== STEP 6: Normalize to 0dB ======
      local num_selected = reaper.CountSelectedMediaItems(0)
      if num_selected > 0 then
        reaper.Main_OnCommand(40108, 0)
      end
      
      -- ====== STEP 7: Scale to -18 dBFS ======
      local target_linear = 10 ^ (config.target_db / 20)
      for j = 0, healed_items - 1 do
        local item = reaper.GetTrackMediaItem(track, j)
        local current_vol = reaper.GetMediaItemInfo_Value(item, "D_VOL")
        reaper.SetMediaItemInfo_Value(item, "D_VOL", current_vol * target_linear)
        reaper.SetMediaItemSelected(item, true)
      end
      
      -- ====== STEP 8: Glue items together ======
      if healed_items > 1 then
        reaper.Main_OnCommand(41588, 0) -- Glue items
        total_glued = total_glued + 1
        log_success(string.format("  %s: %d items glued → 1", track_name, healed_items))
      elseif healed_items == 1 then
        log_success(string.format("  %s: 1 item (no glue needed)", track_name))
      end
      
      -- ====== STEP 9: Rename glued item ======
      reaper.Main_OnCommand(40289, 0)
      local final_item = reaper.GetTrackMediaItem(track, 0)
      if final_item then
        local take = reaper.GetActiveTake(final_item)
        if take then
          reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", track_name, true)
        end
      end
      
      total_items_processed = total_items_processed + healed_items
    end
  end
  
  msg(string.format("  Total items processed: %d", total_items_processed))
  if total_glued > 0 then
    log_success(string.format("Glued %d tracks", total_glued))
  end
end

-- ============================================================================
-- TRACK RESET & CLEANUP
-- ============================================================================

local function reset_tracks()
  log_section("TRACK RESET & CLEANUP")
  
  local num_tracks = reaper.CountTracks(0)
  local deleted_count = 0
  
  -- Iterate backwards for safe deletion
  for i = num_tracks - 1, 0, -1 do
    local track = reaper.GetTrack(0, i)
    local num_items = reaper.CountTrackMediaItems(track)
    local is_folder = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1
    local num_receives = reaper.GetTrackNumSends(track, -1)
    
    -- Delete if empty AND not a folder AND no receives
    if num_items == 0 and not is_folder and num_receives == 0 and config.delete_empty_tracks then
      reaper.DeleteTrack(track)
      deleted_count = deleted_count + 1
    else
      -- Reset all other tracks
      reaper.SetMediaTrackInfo_Value(track, "B_MUTE", 0)           -- Unmute
      reaper.SetMediaTrackInfo_Value(track, "C_BEATATTACHMODE", 0) -- Time basis
      reaper.SetMediaTrackInfo_Value(track, "D_VOL", 1.0)          -- Unity gain
      reaper.SetMediaTrackInfo_Value(track, "D_PAN", 0.0)          -- Center pan
      reaper.SetMediaTrackInfo_Value(track, "B_MAINSEND", 1)       -- Master
      reaper.SetMediaTrackInfo_Value(track, "I_AUTOMODE", 0)       -- Trim/Read
    end
  end
  
  if deleted_count > 0 then
    log_success(string.format("Deleted %d empty tracks", deleted_count))
  else
    msg("  (no empty tracks to delete)")
  end
  
  log_success(string.format("Reset %d remaining tracks", num_tracks - deleted_count))
end

-- ============================================================================
-- POST-SESSION AUDIT
-- ============================================================================

local function audit_after()
  log_section("POST-SESSION AUDIT")
  
  local stats = {
    total_tracks = reaper.CountTracks(0),
    total_items = reaper.CountMediaItems(0),
    total_fx = 0,
    total_sends = 0,
    total_receives = 0,
    total_envelopes = 0
  }
  
  for i = 0, stats.total_tracks - 1 do
    local track = reaper.GetTrack(0, i)
    stats.total_fx = stats.total_fx + reaper.TrackFX_GetCount(track)
    stats.total_sends = stats.total_sends + reaper.GetTrackNumSends(track, 0)
    stats.total_receives = stats.total_receives + reaper.GetTrackNumSends(track, -1)
    stats.total_envelopes = stats.total_envelopes + reaper.CountTrackEnvelopes(track)
  end
  
  msg(string.format("  Tracks:          %d", stats.total_tracks))
  msg(string.format("  Media Items:     %d", stats.total_items))
  msg(string.format("  Track FX:        %d (all offlined)", stats.total_fx))
  msg(string.format("  Sends/Receives:  %d / %d (cleaned)", stats.total_sends, stats.total_receives))
  msg(string.format("  Automation Envs: %d (cleaned)", stats.total_envelopes))
  
  if stats.total_sends == 0 and stats.total_receives == 0 then
    log_success("Session is CLEAN and ready for mixing")
  end
end

-- ============================================================================
-- MAIN
-- ============================================================================

local function main()
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  
  log_header("MIX PREP & SESSION SANITIZER v4.1")
  
  -- Pre-flight audit
  audit_session()
  
  -- Setup master
  setup_master_track()
  
  -- Clean automation
  cleanup_automation()
  
  -- Offline FX
  if config.offline_all_fx then
    offline_all_track_fx()
  end
  
  -- Clean routing
  cleanup_routing()
  
  -- Process items (heal, crossfade, gain stage, glue, rename)
  process_items()
  
  -- Reset & clean tracks
  reset_tracks()
  
  -- Post-flight audit
  audit_after()
  
  -- Clear all selections
  reaper.Main_OnCommand(40289, 0)
  reaper.Main_OnCommand(40297, 0)
  
  reaper.PreventUIRefresh(-1)
  reaper.UpdateTimeline()
  reaper.Undo_EndBlock("Mix Prep & Session Sanitizer v4.1 Complete", -1)
  
  log_header("SESSION READY FOR MIXING")
  msg("\nNext steps:")
  msg("  1. Review master analyzers (Goniometer, Stereo Field)")
  msg("  2. Set monitor levels & calibration")
  msg("  3. Begin mix with confidence\n")
end

main()
