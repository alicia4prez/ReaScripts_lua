-- @description ALiXiA_Diatonic major minor mode transposer
-- @author ALiXiA
-- @version 1.0
-- @about
--   Transposes a file from Root source and mode (GMin example)
--   another Root Sourse and mode (C#Min)
-- @changelog
--   - Initial release
local function msg(text)
  reaper.ShowConsoleMsg(text .. "\n")
end

-- ============================================================================
-- NOTE MAPPING & SCALE DEFINITIONS
-- ============================================================================

local note_map = {
  ["C"] = 0, ["C#"] = 1, ["DB"] = 1, ["D"] = 2, ["D#"] = 3, ["EB"] = 3,
  ["E"] = 4, ["F"] = 5, ["F#"] = 6, ["GB"] = 6, ["G"] = 7, ["G#"] = 8,
  ["AB"] = 8, ["A"] = 9, ["A#"] = 10, ["BB"] = 10, ["B"] = 11
}

local note_names = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}

local mode_intervals = {
  ["major"]       = {0, 2, 4, 5, 7, 9, 11},
  ["ionian"]      = {0, 2, 4, 5, 7, 9, 11},
  ["minor"]       = {0, 2, 3, 5, 7, 8, 10},
  ["aeolian"]     = {0, 2, 3, 5, 7, 8, 10},
  ["dorian"]      = {0, 2, 3, 5, 7, 9, 10},
  ["phrygian"]    = {0, 1, 3, 5, 7, 8, 10},
  ["lydian"]      = {0, 2, 4, 6, 7, 9, 11},
  ["mixolydian"]  = {0, 2, 4, 5, 7, 9, 10},
  ["locrian"]     = {0, 1, 3, 5, 6, 8, 10}
}

local mode_order = {"major", "minor", "dorian", "phrygian", "lydian", "mixolydian", "locrian"}

-- ============================================================================
-- TRANSPOSITION LOGIC
-- ============================================================================

local function normalize_input(str)
  return str:upper():gsub("%s+", "")
end

local function validate_note(note_str)
  return note_map[normalize_input(note_str)] ~= nil
end

local function map_to_target_scale(pitch_class, src_val, src_scale, tgt_val, tgt_scale)
  local interval = (pitch_class - src_val) % 12
  
  -- Find closest scale degree in source mode
  local degree_index = 1
  local min_diff = 12
  for idx, semitone in ipairs(src_scale) do
    local diff = math.abs(semitone - interval)
    if diff < min_diff then
      min_diff = diff
      degree_index = idx
    end
  end
  
  -- Map to target scale
  local target_interval = tgt_scale[degree_index]
  return (tgt_val + target_interval) % 12
end

local function transpose_midi_take(take, src_val, src_scale, tgt_val, tgt_scale)
  local _, num_notes = reaper.MIDI_CountEvts(take)
  local transposed = 0
  
  for n = 0, num_notes - 1 do
    local _, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, n)
    
    local pitch_class = pitch % 12
    local octave = math.floor(pitch / 12)
    local new_pitch_class = map_to_target_scale(pitch_class, src_val, src_scale, tgt_val, tgt_scale)
    local new_pitch = (octave * 12) + new_pitch_class
    
    -- Clamp to MIDI range
    new_pitch = math.max(0, math.min(127, new_pitch))
    
    reaper.MIDI_SetNote(take, n, selected, muted, startppq, endppq, chan, new_pitch, vel, true)
    transposed = transposed + 1
  end
  
  reaper.MIDI_Sort(take)
  return transposed
end

local function transpose_audio_take(take, src_val, tgt_val)
  local root_shift = tgt_val - src_val
  if root_shift > 6 then root_shift = root_shift - 12
  elseif root_shift < -6 then root_shift = root_shift + 12 end
  
  reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", root_shift)
  reaper.SetMediaItemTakeInfo_Value(take, "I_PITCHMODE", 3) -- elastique Pro
  return 1
end

-- ============================================================================
-- TRANSPOSER MAIN FUNCTION
-- ============================================================================

local function main()
  reaper.Undo_BeginBlock()

  -- Get all selected tracks or active track
  local tracks = {}
  local track_count = reaper.CountSelectedTracks(0)
  
  if track_count == 0 then
    local active_track = reaper.GetSelectedTrack(0, 0)
    if not active_track then
      reaper.ShowMessageBox("Please select at least one track with media items.", "Error", 0)
      reaper.Undo_EndBlock("Modal Transposition (cancelled)", -1)
      return
    end
    tracks = {active_track}
  else
    for i = 0, track_count - 1 do
      table.insert(tracks, reaper.GetSelectedTrack(0, i))
    end
  end

  msg("\n" .. string.rep("=", 60))
  msg("ADVANCED MODAL TRANSPOSER v4.1")
  msg(string.rep("=", 60))

  -- Input dialog with better defaults
  local retval, inputs = reaper.GetUserInputs(
    "Modal Transposer - v4.1",
    4,
    "Source Root (C,F#,Bb...),Source Mode (Major/Minor/Dorian/Phrygian/Lydian/Mixolydian/Locrian),Target Root,Target Mode",
    "G,Minor,C,Major"
  )
  
  if not retval then
    reaper.Undo_EndBlock("Modal Transposition (cancelled)", -1)
    return
  end

  local src_root, src_mode, tgt_root, tgt_mode = inputs:match("([^,]+),([^,]+),([^,]+),(.*)")
  
  if not src_root or not tgt_root then
    reaper.ShowMessageBox("Invalid input format.", "Error", 0)
    reaper.Undo_EndBlock("Modal Transposition (cancelled)", -1)
    return
  end

  src_root = normalize_input(src_root)
  src_mode = src_mode:lower():gsub("%s+", "")
  tgt_root = normalize_input(tgt_root)
  tgt_mode = tgt_mode:lower():gsub("%s+", "")

  -- Validation
  if not validate_note(src_root) then
    reaper.ShowMessageBox("Invalid source root note: " .. src_root, "Error", 0)
    reaper.Undo_EndBlock("Modal Transposition (cancelled)", -1)
    return
  end
  
  if not validate_note(tgt_root) then
    reaper.ShowMessageBox("Invalid target root note: " .. tgt_root, "Error", 0)
    reaper.Undo_EndBlock("Modal Transposition (cancelled)", -1)
    return
  end

  if not mode_intervals[src_mode] then
    reaper.ShowMessageBox("Invalid source mode: " .. src_mode, "Error", 0)
    reaper.Undo_EndBlock("Modal Transposition (cancelled)", -1)
    return
  end

  if not mode_intervals[tgt_mode] then
    reaper.ShowMessageBox("Invalid target mode: " .. tgt_mode, "Error", 0)
    reaper.Undo_EndBlock("Modal Transposition (cancelled)", -1)
    return
  end

  local src_val = note_map[src_root]
  local tgt_val = note_map[tgt_root]
  local src_scale = mode_intervals[src_mode]
  local tgt_scale = mode_intervals[tgt_mode]

  msg(string.format("\nSource: %s %s", src_root, src_mode:upper()))
  msg(string.format("Target: %s %s", tgt_root, tgt_mode:upper()))
  msg(string.format("Tracks selected: %d\n", #tracks))

  -- Process all selected tracks
  local total_midi_notes = 0
  local total_audio_items = 0

  for _, track in ipairs(tracks) do
    local track_name = ({reaper.GetTrackName(track)})[2]
    msg(string.format("\nProcessing track: %s", track_name))

    local num_items = reaper.CountTrackMediaItems(track)
    if num_items == 0 then
      msg("  (no media items)")
    else
      for i = 0, num_items - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local take = reaper.GetActiveTake(item)
        
        if take then
          if reaper.TakeIsMIDI(take) then
            local notes = transpose_midi_take(take, src_val, src_scale, tgt_val, tgt_scale)
            total_midi_notes = total_midi_notes + notes
            msg(string.format("  ✓ MIDI item: %d notes transposed", notes))
          else
            transpose_audio_take(take, src_val, tgt_val)
            total_audio_items = total_audio_items + 1
            msg(string.format("  ✓ Audio item: pitch shifted %.0f semitones", tgt_val - src_val))
          end
          reaper.UpdateItemInProject(item)
        end
      end
    end
  end

  reaper.UpdateArrange()
  
  -- Summary
  msg("\n" .. string.rep("=", 60))
  msg("TRANSPOSITION COMPLETE")
  msg(string.format("MIDI notes transposed: %d", total_midi_notes))
  msg(string.format("Audio items processed: %d", total_audio_items))
  msg(string.rep("=", 60) .. "\n")

  reaper.Undo_EndBlock(
    string.format("Modal Transposition: %s %s → %s %s", src_root, src_mode, tgt_root, tgt_mode),
    -1
  )
end

-- ============================================================================
-- RUN
-- ============================================================================

main()
