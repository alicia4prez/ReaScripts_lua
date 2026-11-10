-- @description Complete Master Session Setup & Automated Stem Ingestion Engine.
-- @version 3.0.1
-- @donation https://www.paypal.com/donate/?hosted_button_id=GXEUXZN7GD7W4
-- @about
--   Complete Master Session Setup & Automated Stem Ingestion Engine.
--   Features isolated Hardware Reference routing, Master Bus summing,
--   3-Band Bass Splitter + Kick Sidechain, keyword alias stem matching,
--   10ms fades, and -18 dBFS auto-gain staging on imported stems.

local TARGET_NORM_DB = -18.0
local FADE_LEN_SEC   = 0.010 -- 10ms fades

-- Helper: Convert R, G, B to REAPER native color integer
local function rgb(r, g, b)
    return reaper.ColorToNative(r, g, b) | 0x1000000
end

-- Color Palette
local COLORS = {
    MASTER = rgb(30, 58, 138),   -- Navy Blue
    REF    = rgb(0, 180, 216),   -- Cyan
    DRUMS  = rgb(220, 38, 38),   -- Crimson Red
    BASS   = rgb(217, 119, 6),   -- Deep Amber / Orange
    SYNTHS = rgb(124, 58, 237),  -- Royal Purple
    VOCALS = rgb(219, 39, 119),  -- Magenta / Pink
    FX     = rgb(16, 185, 129)   -- Emerald Teal
}

-- Track Creation Helper
-- folder_depth: 1 = open folder, 0 = normal/child track, -1 = last child in folder
local function create_track(name, color, folder_depth, nchan, master_send)
    local idx = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(idx, true)
    local tr = reaper.GetTrack(0, idx)
    
    reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
    if color then
        reaper.SetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR", color)
    end
    reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", folder_depth or 0)
    if nchan then
        reaper.SetMediaTrackInfo_Value(tr, "I_NCHAN", nchan)
    end
    if master_send ~= nil then
        reaper.SetMediaTrackInfo_Value(tr, "B_MASTERSEND", master_send and 1 or 0)
    end
    return tr
end

-- Create Track-to-Track Audio Send
local function create_audio_send(src_tr, dst_tr, src_chan, dst_chan, send_mode)
    local send_idx = reaper.CreateTrackSend(src_tr, dst_tr)
    reaper.SetTrackSendInfo_Value(src_tr, 0, send_idx, "I_SRCCHAN", src_chan or 0)
    reaper.SetTrackSendInfo_Value(src_tr, 0, send_idx, "I_DSTCHAN", dst_chan or 0)
    reaper.SetTrackSendInfo_Value(src_tr, 0, send_idx, "D_VOL", 1.0)
    reaper.SetTrackSendInfo_Value(src_tr, 0, send_idx, "I_SENDMODE", send_mode or 0) -- 0 = Post-Fader
    return send_idx
end

-- Keyword Alias Dictionary for Stem Ingestion
local keyword_aliases = {
    { target = "REFERENCE",            keys = { "ref", "reference", "master_ref" } },
    { target = "Kick",                 keys = { "kick", "kck", "bd", "bassdrum" } },
    { target = "Snare",                keys = { "snare", "snr", "sd", "rim" } },
    { target = "Clap",                 keys = { "clap", "clp", "snap" } },
    { target = "Hi-Hats",              keys = { "hat", "hh", "chh", "ohh", "hihat", "cymbal", "ride", "crash" } },
    { target = "Percussion",           keys = { "perc", "percussion", "tom", "conga", "bongo", "shaker", "tamb" } },
    { target = "Tops / Loops",         keys = { "top", "tops", "drumloop", "brk", "break", "loop" } },
    { target = "Bass Source",          keys = { "bass", "reese", "acid", "808", "midbass", "synthbass" } },
    { target = "Sub",                  keys = { "sub", "subbass", "lowend" } },
    { target = "Leads",                keys = { "lead", "ld", "hook", "main_synth" } },
    { target = "Chords / Keys",        keys = { "chord", "chords", "keys", "piano", "rhodes", "organ", "stab" } },
    { target = "Plucks / Arp",         keys = { "pluck", "plk", "arp", "arpeggio", "seq", "sequence" } },
    { target = "Pads / Atmos",         keys = { "pad", "pads", "strings", "drone", "texture", "warm" } },
    { target = "Lead Vox",             keys = { "leadvox", "vox_lead", "mainvox", "vocal", "vox", "acapella" } },
    { target = "Backing Vox",          keys = { "bgv", "bvox", "backing", "harmony", "harm", "double", "dbl" } },
    { target = "Vox Chops / Adlibs",   keys = { "chop", "voxchop", "adlib", "shout", "phrase", "spoken" } },
    { target = "Risers / Sweeps",      keys = { "riser", "uplifter", "sweep", "noise_up", "buildup" } },
    { target = "Impacts / Downlifters",keys = { "impact", "downlifter", "downer", "subdrop", "boom", "hit", "crash_fx" } },
    { target = "Misc FX",              keys = { "fx", "sfx", "foley", "glitch", "stutter", "transition", "atmos" } }
}

-- Match a filename to a target track name
local function match_stem_to_track(filename, track_map)
    local lower_name = filename:lower()
    -- Strip extension
    lower_name = lower_name:gsub("%.%w+$", "")
    
    -- Check specific aliases
    for _, group in ipairs(keyword_aliases) do
        for _, kw in ipairs(group.keys) do
            -- Match whole word or bounded by underscores/hyphens/spaces/numbers
            if lower_name:find(kw, 1, true) then
                if track_map[group.target] then
                    return track_map[group.target], group.target
                end
            end
        end
    end
    return track_map["Misc FX"], "Misc FX"
end

-- Normalize item to target dBFS peak and apply 10ms fades
local function process_imported_item(item, is_reference)
    if not item then return end
    
    -- Apply 10ms fade-in and fade-out
    reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", FADE_LEN_SEC)
    reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", FADE_LEN_SEC)
    
    -- Leave commercial reference track at unity gain (0 dB)
    if is_reference then
        reaper.SetMediaItemInfo_Value(item, "D_VOL", 1.0)
        return
    end
    
    -- Select only this item and normalize to 0 dBFS peak, then scale to -18 dBFS
    reaper.SelectAllMediaItems(0, false)
    reaper.SetMediaItemSelected(item, true)
    reaper.Main_OnCommand(40108, 0) -- Item properties: Normalize items (to 0 dBFS peak)
    
    local norm_vol = reaper.GetMediaItemInfo_Value(item, "D_VOL")
    local target_scale = 10 ^ (TARGET_NORM_DB / 20)
    reaper.SetMediaItemInfo_Value(item, "D_VOL", norm_vol * target_scale)
    reaper.SetMediaItemSelected(item, false)
end

-- Prompt for Stem Folder and Ingest Audio Files
local function ingest_stems(track_map)
    local choice = reaper.ShowMessageBox(
        "Session architecture is ready!\n\nWould you like to ingest a folder of audio stems now?",
        "ALiXiA Stem Ingestion Engine v3.0",
        4 -- Yes/No
    )
    if choice ~= 6 then return end

    local folder_path = nil

    -- Use JS_ReaScriptAPI folder browser if installed, otherwise native file picker
    if reaper.JS_Dialog_BrowseForFolder then
        local retval, path = reaper.JS_Dialog_BrowseForFolder("Select Stem Folder to Ingest", "")
        if retval == 1 and path and path ~= "" then
            folder_path = path
        end
    else
        local retval, filepath = reaper.GetUserFileNameForRead("", "Select ANY audio stem inside your stem folder", ".wav")
        if retval and filepath ~= "" then
            folder_path = filepath:match("^(.*)[/\\]")
        end
    end

    if not folder_path or folder_path == "" then return end

    local valid_exts = { wav = true, flac = true, aif = true, aiff = true, mp3 = true, ogg = true }
    local file_idx = 0
    local ingested_count = 0

    while true do
        local file = reaper.EnumerateFiles(folder_path, file_idx)
        if not file then break end
        
        local ext = file:match("%.([^%.]+)$")
        if ext and valid_exts[ext:lower()] then
            local full_path = folder_path .. "/" .. file
            local target_tr, target_name = match_stem_to_track(file, track_map)
            
            if target_tr then
                -- Select solely the target track and place edit cursor at 0.0
                reaper.Main_OnCommand(40297, 0) -- Track: Unselect all tracks
                reaper.SetOnlyTrackSelected(target_tr)
                reaper.SetEditCurPos(0.0, false, false)
                
                local before_items = reaper.CountTrackMediaItems(target_tr)
                reaper.InsertMedia(full_path, 0) -- 0 = add to current track
                local after_items = reaper.CountTrackMediaItems(target_tr)
                
                if after_items > before_items then
                    local new_item = reaper.GetTrackMediaItem(target_tr, after_items - 1)
                    process_imported_item(new_item, target_name == "REFERENCE")
                    ingested_count = ingested_count + 1
                end
            end
        end
        file_idx = file_idx + 1
    end

    reaper.SetEditCurPos(0.0, true, false)
    reaper.ShowConsoleMsg(string.format("ALiXiA Stem Engine: Ingested %d stems normalized to %.1f dBFS with 10ms fades.\n", ingested_count, TARGET_NORM_DB))
end

-- ==============================================================================
-- MAIN SESSION ARCHITECTURE & ROUTING ENGINE
-- ==============================================================================
local function BuildALiXiASession()
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    local track_map = {}

    -- 1. MASTER BUS (Track 1 - Top-Level Summing Bus -> REAPER Hardware Master)
    local tr_master_bus = create_track("MASTER BUS", COLORS.MASTER, 0, 2, true)
    track_map["MASTER BUS"] = tr_master_bus

    -- 2. ISOLATED REFERENCE TRACK (Bypasses Master Bus -> Direct Hardware Out 1/2)
    local tr_ref = create_track("REFERENCE", COLORS.REF, 0, 2, false)
    track_map["REFERENCE"] = tr_ref
    -- Purge any existing sends and create direct hardware output send (dest_tr = nil)
    local hw_send = reaper.CreateTrackSend(tr_ref, nil)
    reaper.SetTrackSendInfo_Value(tr_ref, 0, hw_send, "I_SRCCHAN", 0) -- Ch 1/2
    reaper.SetTrackSendInfo_Value(tr_ref, 0, hw_send, "I_DSTCHAN", 0) -- Hardware Out 1/2
    reaper.SetTrackSendInfo_Value(tr_ref, 0, hw_send, "D_VOL", 1.0)   -- Unity Gain

    -- 3. DRUMS FOLDER (Folder Parent -> Routed to MASTER BUS)
    local tr_drums_folder = create_track("--- DRUMS ---", COLORS.DRUMS, 1, 2, false)
    create_audio_send(tr_drums_folder, tr_master_bus, 0, 0, 0)
    
    track_map["Kick"]         = create_track("Kick", COLORS.DRUMS, 0, 2, true)
    track_map["Snare"]        = create_track("Snare", COLORS.DRUMS, 0, 2, true)
    track_map["Clap"]         = create_track("Clap", COLORS.DRUMS, 0, 2, true)
    track_map["Hi-Hats"]      = create_track("Hi-Hats", COLORS.DRUMS, 0, 2, true)
    track_map["Percussion"]   = create_track("Percussion", COLORS.DRUMS, 0, 2, true)
    track_map["Tops / Loops"] = create_track("Tops / Loops", COLORS.DRUMS, -1, 2, true) -- Closes DRUMS folder!

    -- 4. BASS FOLDER (3-Band Crossover Architecture -> Routed to MASTER BUS)
    local tr_bass_folder = create_track("--- BASS ---", COLORS.BASS, 1, 2, false)
    create_audio_send(tr_bass_folder, tr_master_bus, 0, 0, 0)

    -- Bass Source: 6 Channels, Parent Send OFF (splits signal to Sub, Mid Lows, Mid Highs)
    local tr_bass_src  = create_track("Bass Source", COLORS.BASS, 0, 6, false)
    local tr_bass_sub  = create_track("Sub", COLORS.BASS, 0, 4, true)      -- 4ch for Sidechain input on 3/4
    local tr_bass_midL = create_track("Mid Lows", COLORS.BASS, 0, 2, true)
    local tr_bass_midH = create_track("Mid Highs", COLORS.BASS, -1, 2, true) -- Closes BASS folder!

    track_map["Bass Source"] = tr_bass_src
    track_map["Sub"]         = tr_bass_sub
    track_map["Mid Lows"]    = tr_bass_midL
    track_map["Mid Highs"]   = tr_bass_midH

    -- Insert JS: 3-Band Splitter on Bass Source (150 Hz and 2500 Hz crossovers)
    local fx_splitter = reaper.TrackFX_AddByName(tr_bass_src, "JS: 3-Band Splitter", false, -1)
    if fx_splitter >= 0 then
        reaper.TrackFX_SetParam(tr_bass_src, fx_splitter, 0, 150)  -- Low/Mid Crossover: 150 Hz
        reaper.TrackFX_SetParam(tr_bass_src, fx_splitter, 1, 2500) -- Mid/High Crossover: 2.5 kHz
    end

    -- Route 3-Band Splitter outputs: Ch 1/2 -> Sub, Ch 3/4 -> Mid Lows, Ch 5/6 -> Mid Highs
    create_audio_send(tr_bass_src, tr_bass_sub,  0, 0, 0) -- Src 1/2 -> Dst 1/2
    create_audio_send(tr_bass_src, tr_bass_midL, 2, 0, 0) -- Src 3/4 -> Dst 1/2
    create_audio_send(tr_bass_src, tr_bass_midH, 4, 0, 0) -- Src 5/6 -> Dst 1/2

    -- Add Saturation to Mid Lows and ReaComp Sidechain (from Kick) to Sub
    reaper.TrackFX_AddByName(tr_bass_midL, "JS: Saturation", false, -1)
    create_audio_send(track_map["Kick"], tr_bass_sub, 0, 2, 0) -- Kick Ch 1/2 -> Sub Ch 3/4 (Aux Sidechain)
    local fx_comp = reaper.TrackFX_AddByName(tr_bass_sub, "VST: ReaComp (Cockos)", false, -1)
    if fx_comp >= 0 then
        -- Set Detector Input to Auxiliary Input L+R
        reaper.TrackFX_SetParamNormalized(tr_bass_sub, fx_comp, 8, 0.002)
    end

    -- 5. SYNTHS & KEYS FOLDER (Folder Parent -> Routed to MASTER BUS)
    local tr_synths_folder = create_track("--- SYNTHS & KEYS ---", COLORS.SYNTHS, 1, 2, false)
    create_audio_send(tr_synths_folder, tr_master_bus, 0, 0, 0)

    track_map["Leads"]         = create_track("Leads", COLORS.SYNTHS, 0, 2, true)
    track_map["Chords / Keys"] = create_track("Chords / Keys", COLORS.SYNTHS, 0, 2, true)
    track_map["Plucks / Arp"]  = create_track("Plucks / Arp", COLORS.SYNTHS, 0, 2, true)
    track_map["Pads / Atmos"]  = create_track("Pads / Atmos", COLORS.SYNTHS, -1, 2, true) -- Closes SYNTHS folder!

    -- 6. VOCALS FOLDER (Folder Parent -> Routed to MASTER BUS)
    local tr_vocals_folder = create_track("--- VOCALS ---", COLORS.VOCALS, 1, 2, false)
    create_audio_send(tr_vocals_folder, tr_master_bus, 0, 0, 0)

    track_map["Lead Vox"]           = create_track("Lead Vox", COLORS.VOCALS, 0, 2, true)
    track_map["Backing Vox"]        = create_track("Backing Vox", COLORS.VOCALS, 0, 2, true)
    track_map["Vox Chops / Adlibs"] = create_track("Vox Chops / Adlibs", COLORS.VOCALS, -1, 2, true) -- Closes VOCALS folder!

    -- 7. FX & TRANSITIONS FOLDER (Folder Parent -> Routed to MASTER BUS)
    local tr_fx_folder = create_track("--- FX & TRANSITIONS ---", COLORS.FX, 1, 2, false)
    create_audio_send(tr_fx_folder, tr_master_bus, 0, 0, 0)

    track_map["Risers / Sweeps"]       = create_track("Risers / Sweeps", COLORS.FX, 0, 2, true)
    track_map["Impacts / Downlifters"] = create_track("Impacts / Downlifters", COLORS.FX, 0, 2, true)
    track_map["Misc FX"]               = create_track("Misc FX", COLORS.FX, -1, 2, true) -- Closes FX folder!

    reaper.PreventUIRefresh(-1)
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()

    -- Trigger optional Stem Ingestion prompt
    ingest_stems(track_map)

    reaper.Undo_EndBlock("ALiXiA Master Session Setup & Stem Ingestion v3.0", -1)
end

-- Execute Engine
BuildALiXiASession()
