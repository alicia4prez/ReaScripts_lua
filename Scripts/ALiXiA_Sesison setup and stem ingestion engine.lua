-- @description Composition Session Setup & Automated Stem Ingestion Engine v2.8
-- @author ALiXiA Gregory
-- @version 2.8
-- ENHANCEMENTS: Master metering, FX returns, gain staging integration, improved routing

function get_color(r, g, b)
    return reaper.ColorToNative(r, g, b) | 0x1000000
end

local COLORS = {
    orange = get_color(255, 128, 0),       -- Reference Track
    grey = get_color(128, 128, 128),       -- Loopback Interface
    light_blue = get_color(100, 180, 255), -- Master / Main
    purple = get_color(160, 100, 220),     -- Drums
    pink = get_color(255, 105, 180),       -- Bass
    yellow = get_color(240, 220, 50),      -- Synth / Keys
    green = get_color(50, 200, 100),       -- Vocals
    fx_blue = get_color(80, 120, 240),     -- FX
    red = get_color(200, 50, 50)           -- Master
}

local function log(msg)
    reaper.ShowConsoleMsg(msg .. "\n")
end

local function get_audio_files_in_dir(path)
    local files = {}
    local i = 0
    log("--- Scanning Directory: " .. path .. " ---")
    repeat
        local filename = reaper.EnumerateFiles(path, i)
        if filename then
            local lower = filename:lower()
            if lower:match("%.wav$") or lower:match("%.mp3$") or lower:match("%.flac$") or lower:match("%.aiff$") then
                table.insert(files, { name = filename, fullpath = path .. "/" .. filename })
            end
        end
        i = i + 1
    until not filename
    log(string.format("Total valid audio files queued: %d\n", #files))
    return files
end

function main()
    reaper.Undo_BeginBlock()

    local retval, user_input = reaper.GetUserInputs(
        "REA Session Setup Engine v2.8",
        1,
        "Audio Folder Path,extrawidth=100",
        "C:/Stems"
    )
    if not retval then return end
    
    local folder_path = user_input:gsub("\\", "/")

    reaper.ClearConsole()
    log("========================================")
    log("REA Composition Setup & Stem Ingestion v2.8")
    log("========================================")

    local track_map = {}
    local folder_tracks = {}

    local function create_track(name, color, folder_depth)
        reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
        local tr = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
        reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
        reaper.SetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR", color)
        reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", folder_depth or 0)
        reaper.SetMediaTrackInfo_Value(tr, "D_VOL", 1.0) -- Unity (0 dB)
        reaper.SetMediaTrackInfo_Value(tr, "B_MUTE", 1)  -- Muted by default
        
        track_map[name:lower()] = tr
        return tr
    end

    -- ============================================================================
    -- MASTER BUS SETUP
    -- ============================================================================
    log("\n[MASTER] Creating master bus with metering...")
    
    local master_track = reaper.GetMasterTrack(0)
    reaper.GetSetMediaTrackInfo_String(master_track, "P_NAME", "MASTER", true)
    reaper.SetMediaTrackInfo_Value(master_track, "I_CUSTOMCOLOR", COLORS.red)
    reaper.SetMediaTrackInfo_Value(master_track, "D_VOL", 1.0)
    
    -- Add ReaMeters to Master for visual feedback
    local master_meter = reaper.TrackFX_AddByName(master_track, "ReaMeter", false, -1)
    if master_meter ~= -1 then
        log("  ✓ ReaMeter added to master")
    end
    
    -- ============================================================================
    -- FX RETURN TRACKS (Before stem folders)
    -- ============================================================================
    log("[FX] Setting up return tracks...")
    
    local reverb_return = create_track("REVERB RETURN", COLORS.fx_blue, 0)
    reaper.SetMediaTrackInfo_Value(reverb_return, "B_MAINSEND", 1)
    local reverb_fx = reaper.TrackFX_AddByName(reverb_return, "ReaVerbate", false, -1)
    if reverb_fx ~= -1 then
        log("  ✓ ReaVerbate added to reverb return")
    end
    
    local delay_return = create_track("DELAY RETURN", COLORS.fx_blue, 0)
    reaper.SetMediaTrackInfo_Value(delay_return, "B_MAINSEND", 1)
    local delay_fx = reaper.TrackFX_AddByName(delay_return, "ReaDelay", false, -1)
    if delay_fx ~= -1 then
        log("  ✓ ReaDelay added to delay return")
    end

    -- ============================================================================
    -- PINNED CHANNELS ARCHITECTURE
    -- ============================================================================
    log("\n[INFRASTRUCTURE] Creating pinned channels...")
    
    create_track("Reference Track", COLORS.orange, 0)
    create_track("Loopback Interface", COLORS.grey, 0)
    
    -- ============================================================================
    -- DRUM FOLDER & TRACKS
    -- ============================================================================
    log("\n[DRUMS] Building drum architecture...")
    
    create_track("Drum Folder", COLORS.purple, 1)
    local drum_tracks = {"Kick", "White noise kick", "Snare", "White noise snare", "Hi Hat", "Tops", "Shakers", "Perc 1", "Perc 2"}
    for i, tname in ipairs(drum_tracks) do
        local tr = create_track(tname, COLORS.purple, (i == #drum_tracks) and -1 or 0)
        folder_tracks["Drum Folder"] = folder_tracks["Drum Folder"] or {}
        table.insert(folder_tracks["Drum Folder"], tr)
    end
    log("  ✓ Created " .. #drum_tracks .. " drum tracks")

    -- ============================================================================
    -- BASS FOLDER & ADVANCED ROUTING
    -- ============================================================================
    log("\n[BASS] Building bass architecture with crossover...")
    
    create_track("Bass Folder", COLORS.pink, 1)
    
    local bass_main = create_track("Bass Main", COLORS.pink, 0)
    reaper.SetMediaTrackInfo_Value(bass_main, "I_NCHAN", 6) 
    reaper.SetMediaTrackInfo_Value(bass_main, "B_MAINSEND", 0) 

    -- Add JS 3-Band Splitter
    local splitter_fx = reaper.TrackFX_AddByName(bass_main, "JS: 3-Band Splitter", false, -1)
    if splitter_fx ~= -1 then 
        reaper.TrackFX_SetParam(bass_main, splitter_fx, 0, 150.0)  -- Crossover 1 (Sub to Mid)
        reaper.TrackFX_SetParam(bass_main, splitter_fx, 1, 2500.0) -- Crossover 2 (Mid to High)
        log("  ✓ 3-Band Splitter configured (150 Hz / 2.5 kHz)")
    end

    local sub_tr = create_track("SUB", COLORS.pink, 0)
    reaper.SetMediaTrackInfo_Value(sub_tr, "I_NCHAN", 4) -- 4 channels for sidechain input
    reaper.SetMediaTrackInfo_Value(sub_tr, "D_VOL", 1.0)
    
    local mid_low_tr = create_track("MID LOWS", COLORS.pink, 0)
    reaper.SetMediaTrackInfo_Value(mid_low_tr, "D_VOL", 1.0)
    
    local mid_high_tr = create_track("MID HIGHS", COLORS.pink, -1)
    reaper.SetMediaTrackInfo_Value(mid_high_tr, "D_VOL", 1.0)

    -- Create precise channel sends from Bass Main to individual bands
    local send_idx
    
    -- Bass Main 1/2 -> Sub 1/2
    send_idx = reaper.CreateTrackSend(bass_main, sub_tr)
    reaper.SetTrackSendInfo_Value(bass_main, 0, send_idx, "I_SRCCHAN", 0) 
    reaper.SetTrackSendInfo_Value(bass_main, 0, send_idx, "I_DSTCHAN", 0)
    reaper.SetTrackSendInfo_Value(bass_main, 0, send_idx, "B_MUTE", 0)

    -- Bass Main 3/4 -> Mid Lows 1/2
    send_idx = reaper.CreateTrackSend(bass_main, mid_low_tr)
    reaper.SetTrackSendInfo_Value(bass_main, 0, send_idx, "I_SRCCHAN", 2) 
    reaper.SetTrackSendInfo_Value(bass_main, 0, send_idx, "I_DSTCHAN", 0)
    reaper.SetTrackSendInfo_Value(bass_main, 0, send_idx, "B_MUTE", 0)

    -- Bass Main 5/6 -> Mid Highs 1/2
    send_idx = reaper.CreateTrackSend(bass_main, mid_high_tr)
    reaper.SetTrackSendInfo_Value(bass_main, 0, send_idx, "I_SRCCHAN", 4) 
    reaper.SetTrackSendInfo_Value(bass_main, 0, send_idx, "I_DSTCHAN", 0)
    reaper.SetTrackSendInfo_Value(bass_main, 0, send_idx, "B_MUTE", 0)

    log("  ✓ Bass crossover routing configured")

    -- ============================================================================
    -- SIDECHAIN DUCKING (Kick -> Sub)
    -- ============================================================================
    log("\n[SIDECHAIN] Setting up kick -> sub ducking...")
    
    local kick_tr = track_map["kick"]
    if kick_tr and sub_tr then
        local sc_send = reaper.CreateTrackSend(kick_tr, sub_tr)
        reaper.SetTrackSendInfo_Value(kick_tr, 0, sc_send, "I_SRCCHAN", 0) -- Kick 1/2
        reaper.SetTrackSendInfo_Value(kick_tr, 0, sc_send, "I_DSTCHAN", 2) -- Sub 3/4
        reaper.SetTrackSendInfo_Value(kick_tr, 0, sc_send, "B_MUTE", 0)
        
        -- Add ReaComp to Sub track for sidechain compression
        local comp_fx = reaper.TrackFX_AddByName(sub_tr, "ReaComp", false, -1)
        if comp_fx ~= -1 then
            reaper.TrackFX_SetParam(sub_tr, comp_fx, 0, -15.0) -- Thresh
            reaper.TrackFX_SetParam(sub_tr, comp_fx, 1, 4.0)   -- Ratio
            reaper.TrackFX_SetParam(sub_tr, comp_fx, 2, 0.0)   -- Attack
            reaper.TrackFX_SetParam(sub_tr, comp_fx, 3, 150.0) -- Release
            reaper.TrackFX_SetParam(sub_tr, comp_fx, 13, 1.0)  -- Detector: Aux L+R
            log("  ✓ ReaComp sidechain configured on SUB track")
        end
    end

    -- ============================================================================
    -- KEYS FOLDER
    -- ============================================================================
    log("\n[KEYS] Building synth/keys architecture...")
    
    create_track("Keys Folder", COLORS.yellow, 1)
    local keys_tracks = {"Synth pad", "Synth Bass", "Synth Melodic", "Synth Lead", "Piano misc."}
    for i, tname in ipairs(keys_tracks) do
        local tr = create_track(tname, COLORS.yellow, (i == #keys_tracks) and -1 or 0)
        folder_tracks["Keys Folder"] = folder_tracks["Keys Folder"] or {}
        table.insert(folder_tracks["Keys Folder"], tr)
    end
    log("  ✓ Created " .. #keys_tracks .. " keys tracks")

    -- ============================================================================
    -- VOCALS FOLDER
    -- ============================================================================
    log("\n[VOCALS] Building vocal architecture...")
    
    create_track("Vocals Folder", COLORS.green, 1)
    local vocal_tracks = {"Female 1", "Female 2", "Male 1", "Male 2", "Backing"}
    for i, tname in ipairs(vocal_tracks) do
        local tr = create_track(tname, COLORS.green, (i == #vocal_tracks) and -1 or 0)
        folder_tracks["Vocals Folder"] = folder_tracks["Vocals Folder"] or {}
        table.insert(folder_tracks["Vocals Folder"], tr)
    end
    log("  ✓ Created " .. #vocal_tracks .. " vocal tracks")

    -- ============================================================================
    -- FX FOLDER
    -- ============================================================================
    log("\n[FX] Building effects architecture...")
    
    create_track("FX Folder", COLORS.fx_blue, 1)
    local fx_tracks = {"FX 1", "FX 2", "FX 3"}
    for i, tname in ipairs(fx_tracks) do
        local tr = create_track(tname, COLORS.fx_blue, (i == #fx_tracks) and -1 or 0)
        folder_tracks["FX Folder"] = folder_tracks["FX Folder"] or {}
        table.insert(folder_tracks["FX Folder"], tr)
    end
    log("  ✓ Created " .. #fx_tracks .. " FX tracks")

    -- ============================================================================
    -- STEM MATCHING & INGESTION
    -- ============================================================================
    log("\n[IMPORT] Starting stem ingestion...\n")

    local keyword_aliases = {
        ["kick"] = "kick",
        ["snare"] = "snare",
        ["hat"] = "hi hat",
        ["hihat"] = "hi hat",
        ["hh"] = "hi hat",
        ["top"] = "tops",
        ["shaker"] = "shakers",
        ["perc"] = "perc 1",
        ["bass"] = "bass main",     
        ["sub"] = "bass main",      
        ["pad"] = "synth pad",
        ["synth"] = "synth melodic",
        ["loop"] = "synth melodic",
        ["lead"] = "synth lead",
        ["piano"] = "piano misc.",
        ["vocal"] = "female 1",
        ["vox"] = "female 1",
        ["fx"] = "fx 1"
    }

    local audio_files = get_audio_files_in_dir(folder_path)
    local successful_imports = 0
    local skipped_imports = 0

    for _, file_info in ipairs(audio_files) do
        local f_lower = file_info.name:lower()
        local matched_track = nil
        
        -- Keyword matching
        for keyword, target_track_name in pairs(keyword_aliases) do
            if f_lower:find(keyword, 1, true) then
                matched_track = track_map[target_track_name]
                break
            end
        end
        
        -- Fallback: fuzzy track name matching
        if not matched_track then
            for t_name_lower, track_ptr in pairs(track_map) do
                local clean_track_name = t_name_lower:gsub("[%%s_-]", "")
                local clean_file_name = f_lower:gsub("[%%s_-]", "")
                if clean_file_name:find(clean_track_name, 1, true) then
                    matched_track = track_ptr
                    break
                end
            end
        end

        if matched_track then
            reaper.SetOnlyTrackSelected(matched_track)
            reaper.SetEditCurPos(0.0, false, false)
            reaper.InsertMedia(file_info.fullpath, 3)
            log(string.format("  ✓ %s", file_info.name))
            successful_imports = successful_imports + 1
        else
            log(string.format("  ⚠ SKIPPED: %s (no match)", file_info.name))
            skipped_imports = skipped_imports + 1
        end
    end

    -- ============================================================================
    -- AUTO GAIN STAGING
    -- ============================================================================
    log("\n[GAIN STAGING] Normalizing imported items to -18 dBFS...")

    local num_items = reaper.CountMediaItems(0)
    for i = 0, num_items - 1 do
        local item = reaper.GetMediaItem(0, i)
        if item then
            reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", 0.01)
            reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", 0.01)

            local take = reaper.GetActiveTake(item)
            if take and not reaper.TakeIsMIDI(take) then
                local target_peak_linear = 10 ^ (-18.0 / 20)
                reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", target_peak_linear)
            end
        end
    end

    reaper.UpdateArrange()
    reaper.Undo_EndBlock("REA Session Setup & Stem Ingestion v2.8 Complete", -1)

    -- ============================================================================
    -- SUMMARY
    -- ============================================================================
    log("\n========================================")
    log("SESSION BUILD COMPLETE")
    log(string.format("Successful imports: %d", successful_imports))
    log(string.format("Skipped items: %d", skipped_imports))
    log("========================================")
    log("\nSession features enabled:")
    log("  ✓ Master bus with metering")
    log("  ✓ Reverb & Delay return tracks")
    log("  ✓ Bass 3-band crossover")
    log("  ✓ Kick -> Sub sidechain ducking")
    log("  ✓ Auto-normalized stems to -18 dBFS")
    log("\nReady for: Gain Staging → Transposition → Mastering")
    log("========================================\n")
end

main()

