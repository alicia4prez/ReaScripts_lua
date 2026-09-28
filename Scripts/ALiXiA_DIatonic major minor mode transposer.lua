-- @description ALiXiA_DIatonic major minor mode transposer.lua
-- @author Rea and ALiXiA - The Reaper Queens
-- @version 4.0
-- @about
--    A simple tool that transposes any key or mode into another
--    into another key or mode
-- @changelog
--    intitial release under 4.0 to the community
-- Requires: ReaImGui extension

function main()
    reaper.Undo_BeginBlock()

    -- 1. Get selected track
    local track = reaper.GetSelectedTrack(0, 0)
    if not track then
        reaper.ShowMessageBox("Please select a track containing media items first.", "Error", 0)
        return
    end

    -- 2. Prompt user for Source and Target Key + Mode
    local retval, inputs = reaper.GetUserInputs("Modal Transposer", 4, 
        "Source Root (C, F#...),Source Mode (Major/Minor/Dorian/Phrygian/Lydian/Mixolydian/Locrian),Target Root (C, F#...),Target Mode (Major/Minor/Dorian/Phrygian/Lydian/Mixolydian/Locrian)", 
        "G,Minor,G,Phrygian")
    if not retval then return end

    local src_root, src_mode, tgt_root, tgt_mode = inputs:match("([^,]+),([^,]+),([^,]+),(.*)")
    if not src_root or not tgt_root then
        reaper.ShowMessageBox("Invalid input format. Use comma separation.", "Error", 0)
        return
    end

    src_root = src_root:upper():gsub("%s+", "")
    src_mode = src_mode:lower():gsub("%s+", "")
    tgt_root = tgt_root:upper():gsub("%s+", "")
    tgt_mode = tgt_mode:lower():gsub("%s+", "")

    local note_map = {
        ["C"] = 0, ["C#"] = 1, ["DB"] = 1, ["D"] = 2, ["D#"] = 3, ["EB"] = 3,
        ["E"] = 4, ["F"] = 5, ["F#"] = 6, ["GB"] = 6, ["G"] = 7, ["G#"] = 8,
        ["AB"] = 8, ["A"] = 9, ["A#"] = 10, ["BB"] = 10, ["B"] = 11
    }

    local src_val = note_map[src_root]
    local tgt_val = note_map[tgt_root]

    if not src_val or not tgt_val then
        reaper.ShowMessageBox("Invalid root note name. Use C, F#, Bb, etc.", "Error", 0)
        return
    end

    -- Define scale degree intervals (semitones from root) for each mode
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

    local src_scale = mode_intervals[src_mode]
    local tgt_scale = mode_intervals[tgt_mode]

    if not src_scale or not tgt_scale then
        reaper.ShowMessageBox("Unknown mode specified. Use: Major, Minor, Dorian, Phrygian, Lydian, Mixolydian, or Locrian.", "Error", 0)
        return
    end

    -- Helper function to find scale degree or nearest match
    local function map_to_target_scale(pitch_class)
        local interval = (pitch_class - src_val) % 12
        
        -- Find which scale degree this interval belongs to in the source mode
        local degree_index = 1
        local min_diff = 12
        for idx, semitone in ipairs(src_scale) do
            local diff = math.abs(semitone - interval)
            if diff < min_diff then
                min_diff = diff
                degree_index = idx
            end
        end
        
        -- Map to the corresponding degree in the target mode
        local target_interval = tgt_scale[degree_index]
        return (tgt_val + target_interval) % 12
    end

    -- 3. Loop through media items on the track
    local num_items = reaper.CountTrackMediaItems(track)
    for i = 0, num_items - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local take = reaper.GetActiveTake(item)
        
        if take then
            if reaper.TakeIsMIDI(take) then
                -- MIDI Processing: Modal mapping note by note
                local _, num_notes = reaper.MIDI_CountEvts(take)
                for n = 0, num_notes - 1 do
                    local _, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, n)
                    
                    local pitch_class = pitch % 12
                    local octave = math.floor(pitch / 12)
                    
                    local new_pitch_class = map_to_target_scale(pitch_class)
                    local new_pitch = (octave * 12) + new_pitch_class
                    
                    if new_pitch < 0 then new_pitch = 0 elseif new_pitch > 127 then new_pitch = 127 end

                    reaper.MIDI_SetNote(take, n, selected, muted, startppq, endppq, chan, new_pitch, vel, true)
                end
                reaper.MIDI_Sort(take)
            else
                -- Audio Processing: Calculate root shift for audio takes
                local root_shift = tgt_val - src_val
                if root_shift > 6 then root_shift = root_shift - 12
                elseif root_shift < -6 then root_shift = root_shift + 12 end

                reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", root_shift)
                reaper.SetMediaItemTakeInfo_Value(take, "I_PITCHMODE", 3) -- elastique Pro
            end
            reaper.UpdateItemInProject(item)
        end
    end

    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Modal Transposition & Scale Conversion", -1)
    reaper.ShowConsoleMsg(string.format("Successfully transposed track from %s %s to %s %s.\n", src_root, src_mode, tgt_root, tgt_mode))
end

main()
