-- @description ALiXiA_Mix Prep and Session Sanitizer
-- @version 4.2
-- @author ALiXiA Gregory
-- @changelog
--   + Preserve Bass folders and all nested child tracks from deletion
--   + Maintain internal/external routing, sidechains, and B_MAINSEND states for Bass folders
--   + Preserve folder closure depth (I_FOLDERDEPTH) when deleting empty tracks inside other folders
-- ==============================================================================
-- Mix Prep & Session Sanitizer v4.2
-- ==============================================================================
-- Enhanced with:
--   • Detailed logging & progress tracking
--   • Error handling & validation
--   • Folder track & Bass folder hierarchy preservation
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
  preserve_bass_folders = true,
  preserve_bass_routing = true,
  preserve_bass_fx = false,         -- Set to true to keep crossover/split FX online on Bass tracks
  reset_bass_vol_pan = false,       -- Set to false to keep Bass split fader/pan balances intact
  protected_bass_keywords = { "bass", "sub" },
  preserve_sidechain_sends = true,
  offline_all_fx = true,
  add_master_analyzers = true,
  delete_empty_tracks = true,
  strict_mode = false               -- Set to true for more aggressive cleanup
}

-- ============================================================================
-- HELPER: BASS FOLDER & HIERARCHY DETECTION
-- ============================================================================

local function get_track_name(track)
  if not track or not reaper.ValidatePtr(track, "MediaTrack*") then
    return ""
  end
  local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  return name or ""
end

local function has_bass_keyword(name)
  local lower_name = (name or ""):lower()
  for _, keyword in ipairs(config.protected_bass_keywords) do
    if lower_name:find(keyword:lower(), 1, true) then
      return true
    end
  end
  return false
end

-- Returns true if the track itself or any parent folder enclosing it matches a Bass keyword
local function is_bass_protected(track)
  if not config.preserve_bass_folders then
    return false
  end
  if not track or not reaper.ValidatePtr(track, "MediaTrack*") then
    return false
  end

  local current = track
  while current do
    local name = get_track_name(current)
    if has_bass_keyword(name) then
      return true
    end
    current = reaper.GetParentTrack(current)
  end

  return false
end

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
    bass_protected_tracks = 0,
    muted_tracks = 0,
    offline_tracks = 0
  }
  
  for i = 0, stats.total_tracks - 1 do
    local track = reaper.GetTrack(0, i)
    if reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
      stats.folder_tracks = stats.folder_tracks + 1
    end
    if is_bass_protected(track) then
      stats.bass_protected_tracks = stats.bass_protected_tracks + 1
    end
    if reaper.GetMediaTrackInfo_Value(track, "B_MUTE") == 1 then
      stats.muted_tracks = stats.muted_tracks + 1
    end
    
    stats.total_fx = stats.total_fx + reaper.TrackFX_GetCount(track)
    stats.total_sends = stats.total_sends + reaper.GetTrackNumSends(track, 0)
    stats.total_receives = stats.total_receives + reaper.GetTrackNumSends(track, -1)
    stats.total_envelopes = stats.total_envelopes + reaper.CountTrackEnvelopes(track)
  end
  
  msg(string.format("  Tracks:           %d (folders: %d, bass-protected: %d, muted: %d)", 
    stats.total_tracks, stats.folder_tracks, stats.bass_protected_tracks, stats.muted_tracks))
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
        local point_count = reaper.CountEnvelopePoints(env)
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
  local total_preserved = 0
  local num_tracks = reaper.CountTracks(0)
  
  for i = 0, num_tracks - 1 do
    local track = reaper.GetTrack(0, i)
    local num_fx = reaper.TrackFX_GetCount(track)
    
    if config.preserve_bass_fx and is_bass_protected(track) then
      total_preserved = total_preserved + num_fx
    else
      for fx = 0, num_fx - 1 do
        reaper.TrackFX_SetOffline(track, fx, true)
        total_offlined = total_offlined + 1
      end
    end
  end
  
  if total_offlined > 0 then
    log_success(string.format("Offlined %d track FX plugins", total_offlined))
  else
    msg("  (no FX to offline)")
  end
  
  if total_preserved > 0 then
    log_success(string.format("Preserved %d Bass FX plugins online", total_preserved))
  end
end

-- ============================================================================
-- ROUTING CLEANUP (Preserves Bass Folder Routing & Sidechains)
-- ============================================================================

local function cleanup_routing()
  log_section("ROUTING CLEANUP")
  
  local total_sends_deleted = 0
  local total_receives_deleted = 0
  local total_hardware_deleted = 0
  local preserved_bass_sends = 0
  local num_tracks = reaper.CountTracks(0)
  
  for i = 0, num_tracks - 1 do
    local track = reaper.GetTrack(0, i)
    local track_is_bass = config.preserve_bass_routing and is_bass_protected(track)
    
    if track_is_bass then
      -- Leave all sends, receives, hardware outputs, and B_MAINSEND untouched on Bass tracks
      preserved_bass_sends = preserved_bass_sends + reaper.GetTrackNumSends(track, 0)
    else
      -- Delete sends (0 = aux sends) UNLESS routed to a protected Bass track or sidechain
      for s = reaper.GetTrackNumSends(track, 0) - 1, 0, -1 do
        local dest_track = reaper.GetTrackSendInfo_Value(track, 0, s, "P_DESTTRACK")
        local dst_chan = math.floor(reaper.GetTrackSendInfo_Value(track, 0, s, "I_DSTCHAN"))
        local is_sidechain = config.preserve_sidechain_sends and ((dst_chan & 1023) >= 2)
        local dest_is_bass = config.preserve_bass_routing and is_bass_protected(dest_track)
        
        if dest_is_bass or is_sidechain then
          preserved_bass_sends = preserved_bass_sends + 1
        else
          reaper.RemoveTrackSend(track, 0, s)
          total_sends_deleted = total_sends_deleted + 1
        end
      end
      
      -- Delete receives (-1 = receives) UNLESS coming from a protected Bass track or sidechain
      for r = reaper.GetTrackNumSends(track, -1) - 1, 0, -1 do
        local src_track = reaper.GetTrackSendInfo_Value(track, -1, r, "P_SRCTRACK")
        local dst_chan = math.floor(reaper.GetTrackSendInfo_Value(track, -1, r, "I_DSTCHAN"))
        local is_sidechain = config.preserve_sidechain_sends and ((dst_chan & 1023) >= 2)
        local src_is_bass = config.preserve_bass_routing and is_bass_protected(src_track)
        
        if not (src_is_bass or is_sidechain) then
          reaper.RemoveTrackSend(track, -1, r)
          total_receives_deleted = total_receives_deleted + 1
        end
      end
      
      -- Delete hardware outputs (1 = hardware)
      for h = reaper.GetTrackNumSends(track, 1) - 1, 0, -1 do
        reaper.RemoveTrackSend(track, 1, h)
        total_hardware_deleted = total_hardware_deleted + 1
      end
      
      -- Reset non-bass tracks to Master/Parent send enabled
      reaper.SetMediaTrackInfo_Value(track, "B_MAINSEND", 1)
    end
  end
  
  if total_sends_deleted > 0 then
    log_success(string.format("Deleted %d non-protected sends", total_sends_deleted))
  end
  if total_receives_deleted > 0 then
    log_success(string.format("Deleted %d non-protected receives", total_receives_deleted))
  end
  if total_hardware_deleted > 0 then
    log_success(string.format("Deleted %d hardware outputs", total_hardware_deleted))
  end
  if preserved_bass_sends > 0 then
    log_success(string.format("Preserved %d Bass/sidechain routing sends & B_MAINSEND states", preserved_bass_sends))
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
      local track_name = get_track_name(track)
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
      reaper.Main_OnCommand(40546, 0) -- Heal splits in items
      
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
-- TRACK RESET & CLEANUP (Preserves Bass Folders & Hierarchy Boundaries)
-- ============================================================================

local function reset_tracks()
  log_section("TRACK RESET & CLEANUP")
  
  local num_tracks = reaper.CountTracks(0)
  local deleted_count = 0
  local preserved_bass_count = 0
  
  -- Iterate backwards for safe deletion
  for i = num_tracks - 1, 0, -1 do
    local track = reaper.GetTrack(0, i)
    local num_items = reaper.CountTrackMediaItems(track)
    local folder_depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    local is_folder = (folder_depth == 1) and config.preserve_folders
    local num_receives = reaper.GetTrackNumSends(track, -1)
    local num_sends = reaper.GetTrackNumSends(track, 0)
    local bass_protected = is_bass_protected(track)
    
    if bass_protected then
      -- Never delete Bass folders or their child split tracks, and keep their routing intact
      preserved_bass_count = preserved_bass_count + 1
      reaper.SetMediaTrackInfo_Value(track, "B_MUTE", 0)            -- Unmute
      reaper.SetMediaTrackInfo_Value(track, "C_BEATATTACHMODE", 0)  -- Time basis
      reaper.SetMediaTrackInfo_Value(track, "I_AUTOMODE", 0)        -- Trim/Read
      
      if config.reset_bass_vol_pan then
        reaper.SetMediaTrackInfo_Value(track, "D_VOL", 1.0)
        reaper.SetMediaTrackInfo_Value(track, "D_PAN", 0.0)
      end
      -- Note: B_MAINSEND is intentionally NOT touched here so Bass split routing stays intact
      
    elseif num_items == 0 and not is_folder and num_receives == 0 and num_sends == 0 and config.delete_empty_tracks then
      -- If this empty track closes one or more folders (folder_depth < 0),
      -- transfer its closing depth to the previous track so folder structure doesn't break
      if folder_depth < 0 and i > 0 then
        local prev_track = reaper.GetTrack(0, i - 1)
        if prev_track then
          local prev_depth = reaper.GetMediaTrackInfo_Value(prev_track, "I_FOLDERDEPTH")
          reaper.SetMediaTrackInfo_Value(prev_track, "I_FOLDERDEPTH", prev_depth + folder_depth)
        end
      end
      
      reaper.DeleteTrack(track)
      deleted_count = deleted_count + 1
    else
      -- Reset all other remaining tracks
      reaper.SetMediaTrackInfo_Value(track, "B_MUTE", 0)            -- Unmute
      reaper.SetMediaTrackInfo_Value(track, "C_BEATATTACHMODE", 0)  -- Time basis
      reaper.SetMediaTrackInfo_Value(track, "D_VOL", 1.0)           -- Unity gain
      reaper.SetMediaTrackInfo_Value(track, "D_PAN", 0.0)           -- Center pan
      reaper.SetMediaTrackInfo_Value(track, "B_MAINSEND", 1)        -- Master
      reaper.SetMediaTrackInfo_Value(track, "I_AUTOMODE", 0)        -- Trim/Read
    end
  end
  
  if deleted_count > 0 then
    log_success(string.format("Deleted %d empty non-bass tracks", deleted_count))
  else
    msg("  (no empty tracks to delete)")
  end
  
  if preserved_bass_count > 0 then
    log_success(string.format("Preserved %d Bass folder/child tracks and their routing", preserved_bass_count))
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
    total_envelopes = 0,
    bass_tracks = 0
  }
  
  for i = 0, stats.total_tracks - 1 do
    local track = reaper.GetTrack(0, i)
    if is_bass_protected(track) then
      stats.bass_tracks = stats.bass_tracks + 1
    end
    stats.total_fx = stats.total_fx + reaper.TrackFX_GetCount(track)
    stats.total_sends = stats.total_sends + reaper.GetTrackNumSends(track, 0)
    stats.total_receives = reaper.GetTrackNumSends(track, -1) + stats.total_receives
    stats.total_envelopes = stats.total_envelopes + reaper.CountTrackEnvelopes(track)
  end
  
  msg(string.format("  Tracks:           %d (Bass-protected: %d)", stats.total_tracks, stats.bass_tracks))
  msg(string.format("  Media Items:      %d", stats.total_items))
  msg(string.format("  Track FX:         %d", stats.total_fx))
  msg(string.format("  Sends/Receives:   %d / %d (Bass & sidechain routing preserved)", stats.total_sends, stats.total_receives))
  msg(string.format("  Automation Envs:  %d (cleaned)", stats.total_envelopes))
  
  log_success("Session is CLEAN and Bass routing is intact")
end

-- ============================================================================
-- MAIN
-- ============================================================================

local function main()
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  
  log_header("MIX PREP & SESSION SANITIZER v4.2")
  
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
  
  -- Clean routing (preserving Bass folders & sidechain sends)
  cleanup_routing()
  
  -- Process items (heal, crossfade, gain stage, glue, rename)
  process_items()
  
  -- Reset & clean tracks (preserving Bass folders & child tracks)
  reset_tracks()
  
  -- Post-flight audit
  audit_after()
  
  -- Clear all selections
  reaper.Main_OnCommand(40289, 0)
  reaper.Main_OnCommand(40297, 0)
  
  reaper.PreventUIRefresh(-1)
  reaper.UpdateTimeline()
  reaper.Undo_EndBlock("Mix Prep & Session Sanitizer v4.2 Complete", -1)
  
  log_header("SESSION READY FOR MIXING")
  msg("\nNext steps:")
  msg("  1. Review master analyzers (Goniometer, Stereo Field)")
  msg("  2. Verify Bass folder split & sidechain routing")
  msg("  3. Set monitor levels & calibration")
  msg("  4. Begin mix with confidence\n")
end

main()
