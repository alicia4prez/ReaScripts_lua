--@description ALiXiA_Gain Staging Utility
--@author ALiXiA Gregory
--@version 2.0
--@about 
--   Real-time selected-track gain staging monitor.
--   Peak dbFS, average level, crest factor, difference.  
--[[
===========================================================
      REAPER GAIN STAGING ANALYZER
===========================================================

 Real-time selected-track gain staging monitor.

Displays:
    • Peak dBFS
   • Smoothed average level
    • Left / Right peak
    • Crest factor
    • Distance from -18 dBFS target
    • Visual dBFS meter
    • Gain-staging status
 IMPORTANT:
 REAPER's standard ReaScript API exposes real-time peak
 meter information, but not a true post-FX RMS meter.

 Therefore:
    PEAK       = actual REAPER track peak
     AVERAGE    = smoothed energy representation

The average is NOT falsely labeled RMS.

 TARGET:
     -18 dBFS 
No audio is altered.
No plugins are inserted.
No track settings are changed.
===========================================================
]]
-----------------------------------------------------------
-- SETTINGS
-----------------------------------------------------------

local TARGET_DB = -18.0

-- Sweet spot width around target
local SWEET_RANGE = 3.0

-- Status thresholds
local LOW_THRESHOLD = -24.0
local HOT_THRESHOLD = -12.0
local CLIP_THRESHOLD = -0.1

-- Meter range
local MIN_DB = -60.0
local MAX_DB = 0.0

-- Smoothing
-- Lower = faster response
-- Higher = smoother
local ATTACK = 0.20
local RELEASE = 0.08

-- Window
local WINDOW_W = 700
local WINDOW_H = 500

-----------------------------------------------------------
-- STATE
-----------------------------------------------------------

local average_level = -60.0
local previous_time = reaper.time_precise()

local last_track = nil

-----------------------------------------------------------
-- INITIALIZE WINDOW
-----------------------------------------------------------

gfx.init(
    "Gain Staging Analyzer",
    WINDOW_W,
    WINDOW_H,
    0
)

-----------------------------------------------------------
-- FUNCTIONS
-----------------------------------------------------------

local function amp_to_db(amp)

    if not amp or amp <= 0 then
        return -150.0
    end

    return 20.0 * math.log(amp, 10)

end


local function clamp(value, minimum, maximum)

    if value < minimum then
        return minimum
    end

    if value > maximum then
        return maximum
    end

    return value

end


local function get_selected_track()

    if reaper.CountSelectedTracks(0) == 0 then
        return nil
    end

    return reaper.GetSelectedTrack(0, 0)

end


local function get_track_name(track)

    if not track then
        return "No track selected"
    end

    local retval, name =
        reaper.GetTrackName(track)

    if not retval or name == "" then
        return "Unnamed Track"
    end

    return name

end


local function draw_text(
    x,
    y,
    text,
    size
)

    gfx.setfont(
        1,
        "Arial",
        size
    )

    gfx.x = x
    gfx.y = y

    gfx.drawstr(text)

end


-----------------------------------------------------------
-- SMOOTH LEVEL
-----------------------------------------------------------

local function update_average(peak_db)

    local now =
        reaper.time_precise()

    local dt =
        now - previous_time

    previous_time = now

    if dt < 0 then
        dt = 0
    end

    if dt > 0.25 then
        dt = 0.25
    end

    local coefficient

    if peak_db > average_level then

        coefficient =
            1.0 - math.exp(
                -dt / ATTACK
            )

    else

        coefficient =
            1.0 - math.exp(
                -dt / RELEASE
            )

    end

    average_level =
        average_level +
        (peak_db - average_level) *
        coefficient

end


-----------------------------------------------------------
-- STATUS
-----------------------------------------------------------

local function get_status(avg_db, peak_db)

    if peak_db >= CLIP_THRESHOLD then

        return "CLIPPING"

    elseif peak_db >= HOT_THRESHOLD then

        return "HOT"

    elseif math.abs(
        avg_db - TARGET_DB
    ) <= SWEET_RANGE then

        return "SWEET SPOT"

    elseif avg_db < LOW_THRESHOLD then

        return "LOW"

    else

        return "GOOD"

    end

end


-----------------------------------------------------------
-- DRAW MAIN METER
-----------------------------------------------------------

local function draw_meter(
    db,
    x,
    y,
    width,
    height
)

    -------------------------------------------------------
    -- Background
    -------------------------------------------------------

    gfx.set(
        0.12,
        0.12,
        0.12,
        1
    )

    gfx.rect(
        x,
        y,
        width,
        height,
        1
    )

    -------------------------------------------------------
    -- Convert dB to position
    -------------------------------------------------------

    local normalized =
        (db - MIN_DB) /
        (MAX_DB - MIN_DB)

    normalized =
        clamp(
            normalized,
            0,
            1
        )

    local fill =
        width * normalized

    -------------------------------------------------------
    -- Meter level
    -------------------------------------------------------

    if db >= CLIP_THRESHOLD then

        gfx.set(
            1.0,
            0.05,
            0.05,
            1
        )

    elseif db >= HOT_THRESHOLD then

        gfx.set(
            1.0,
            0.45,
            0.05,
            1
        )

    elseif math.abs(
        db - TARGET_DB
    ) <= SWEET_RANGE then

        gfx.set(
            0.15,
            0.85,
            0.25,
            1
        )

    else

        gfx.set(
            0.25,
            0.60,
            1.0,
            1
        )

    end

    gfx.rect(
        x,
        y,
        fill,
        height,
        1
    )

    -------------------------------------------------------
    -- -18 dBFS target
    -------------------------------------------------------

    local target_normalized =
        (TARGET_DB - MIN_DB) /
        (MAX_DB - MIN_DB)

    local target_x =
        x +
        width *
        target_normalized

    gfx.set(
        1,
        1,
        1,
        1
    )

    gfx.line(
        target_x,
        y - 10,
        target_x,
        y + height + 10
    )

    draw_text(
        target_x - 20,
        y + height + 12,
        "-18",
        14
    )

end


-----------------------------------------------------------
-- DRAW SCALE
-----------------------------------------------------------

local function draw_scale(
    x,
    y,
    width
)

    local values = {
        -60,
        -48,
        -36,
        -30,
        -24,
        -18,
        -12,
        -6,
        0
    }

    gfx.set(
        0.55,
        0.55,
        0.55,
        1
    )

    for _, db in ipairs(values) do

        local normalized =
            (db - MIN_DB) /
            (MAX_DB - MIN_DB)

        local px =
            x +
            width *
            normalized

        gfx.line(
            px,
            y,
            px,
            y + 6
        )

        draw_text(
            px - 12,
            y + 10,
            tostring(db),
            11
        )

    end

end


-----------------------------------------------------------
-- RESET WHEN TRACK CHANGES
-----------------------------------------------------------

local function handle_track_change(track)

    if track ~= last_track then

        last_track = track

        average_level = -60.0

        previous_time =
            reaper.time_precise()

    end

end


-----------------------------------------------------------
-- MAIN
-----------------------------------------------------------

local function main()

    -------------------------------------------------------
    -- Close window
    -------------------------------------------------------

    if gfx.getchar() < 0 then
        return
    end

    -------------------------------------------------------
    -- Selected track
    -------------------------------------------------------

    local track =
        get_selected_track()

    handle_track_change(track)

    -------------------------------------------------------
    -- Clear background
    -------------------------------------------------------

    gfx.set(
        0.055,
        0.055,
        0.055,
        1
    )

    gfx.rect(
        0,
        0,
        gfx.w,
        gfx.h,
        1
    )

    -------------------------------------------------------
    -- HEADER
    -------------------------------------------------------

    gfx.set(
        1,
        1,
        1,
        1
    )

    draw_text(
        25,
        20,
        "GAIN STAGING ANALYZER",
        24
    )

    gfx.set(
        0.55,
        0.55,
        0.55,
        1
    )

    draw_text(
        25,
        50,
        "Selected track output",
        13
    )

    -------------------------------------------------------
    -- NO TRACK
    -------------------------------------------------------

    if not track then

        gfx.set(
            0.75,
            0.75,
            0.75,
            1
        )

        draw_text(
            25,
            100,
            "Select a track to begin monitoring.",
            18
        )

        gfx.update()

        reaper.defer(main)

        return

    end

    -------------------------------------------------------
    -- TRACK NAME
    -------------------------------------------------------

    gfx.set(
        0.85,
        0.85,
        0.85,
        1
    )

    draw_text(
        25,
        78,
        get_track_name(track),
        18
    )

    -------------------------------------------------------
    -- GET REAL-TIME PEAKS
    -------------------------------------------------------

    local left_peak =
        reaper.Track_GetPeakInfo(
            track,
            0
        )

    local right_peak =
        reaper.Track_GetPeakInfo(
            track,
            1
        )

    left_peak =
        left_peak or 0

    right_peak =
        right_peak or 0

    local left_db =
        amp_to_db(left_peak)

    local right_db =
        amp_to_db(right_peak)

    local peak_db =
        math.max(
            left_db,
            right_db
        )

    -------------------------------------------------------
    -- UPDATE SMOOTHED AVERAGE
    -------------------------------------------------------

    update_average(
        peak_db
    )

    -------------------------------------------------------
    -- MAIN READOUT
    -------------------------------------------------------

    gfx.set(
        1,
        1,
        1,
        1
    )

    draw_text(
        25,
        110,
        "AVERAGE",
        13
    )

    draw_text(
        25,
        130,
        string.format(
            "%.1f dBFS",
            average_level
        ),
        32
    )

    -------------------------------------------------------
    -- PEAK READOUT
    -------------------------------------------------------

    gfx.set(
        0.75,
        0.75,
        0.75,
        1
    )

    draw_text(
        250,
        110,
        "PEAK",
        13
    )

    gfx.set(
        1,
        1,
        1,
        1
    )

    draw_text(
        250,
        130,
        string.format(
            "%.1f dBFS",
            peak_db
        ),
        32
    )

    -------------------------------------------------------
    -- TARGET
    -------------------------------------------------------

    gfx.set(
        0.55,
        0.55,
        0.55,
        1
    )

    draw_text(
        500,
        110,
        "TARGET",
        13
    )

    gfx.set(
        0.15,
        0.9,
        0.3,
        1
    )

    draw_text(
        500,
        130,
        "-18.0",
        25
    )

    -------------------------------------------------------
    -- MAIN METER
    -------------------------------------------------------

    draw_meter(
        average_level,
        25,
        185,
        650,
        40
    )

    draw_scale(
        25,
        230,
        650
    )

    -------------------------------------------------------
    -- LEFT / RIGHT
    -------------------------------------------------------

    gfx.set(
        0.65,
        0.65,
        0.65,
        1
    )

    draw_text(
        25,
        275,
        "LEFT PEAK",
        13
    )

    draw_text(
        25,
        295,
        string.format(
            "%.1f dBFS",
            left_db
        ),
        22
    )

    draw_text(
        230,
        275,
        "RIGHT PEAK",
        13
    )

    draw_text(
        230,
        295,
        string.format(
            "%.1f dBFS",
            right_db
        ),
        22
    )

    -------------------------------------------------------
    -- CREST FACTOR
    -------------------------------------------------------

    local crest =
        peak_db - average_level

    draw_text(
        450,
        275,
        "CREST",
        13
    )

    gfx.set(
        1,
        1,
        1,
        1
    )

    draw_text(
        450,
        295,
        string.format(
            "%.1f dB",
            crest
        ),
        22
    )

    -------------------------------------------------------
    -- DISTANCE FROM TARGET
    -------------------------------------------------------

    local target_difference =
        average_level - TARGET_DB

    gfx.set(
        0.65,
        0.65,
        0.65,
        1
    )

    draw_text(
        25,
        335,
        "DISTANCE FROM -18 dBFS",
        13
    )

    gfx.set(
        1,
        1,
        1,
        1
    )

    local difference_text

    if target_difference >= 0 then

        difference_text =
            string.format(
                "+%.1f dB",
                target_difference
            )

    else

        difference_text =
            string.format(
                "%.1f dB",
                target_difference
            )

    end

    draw_text(
        25,
        355,
        difference_text,
        25
    )

    -------------------------------------------------------
    -- STATUS
    -------------------------------------------------------

    local status =
        get_status(
            average_level,
            peak_db
        )

    if status == "SWEET SPOT" then

        gfx.set(
            0.15,
            1.0,
            0.25,
            1
        )

    elseif status == "HOT" then

        gfx.set(
            1.0,
            0.45,
            0.05,
            1
        )

    elseif status == "CLIPPING" then

        gfx.set(
            1.0,
            0.05,
            0.05,
            1
        )

    elseif status == "LOW" then

        gfx.set(
            0.3,
            0.65,
            1.0,
            1
        )

    else

        gfx.set(
            0.8,
            0.8,
            0.8,
            1
        )

    end

    draw_text(
        300,
        340,
        status,
        25
    )

    -------------------------------------------------------
    -- FOOTER
    -------------------------------------------------------

    gfx.set(
        0.4,
        0.4,
        0.4,
        1
    )

    draw_text(
        25,
        420,
        "PEAK = actual track meter",
        12
    )

    draw_text(
        25,
        440,
        "AVERAGE = smoothed energy reference",
        12
    )

    draw_text(
        25,
        460,
        "Target = -18 dBFS",
        12
    )

    -------------------------------------------------------
    -- UPDATE
    -------------------------------------------------------

    gfx.update()

    reaper.defer(main)

end


-----------------------------------------------------------
-- START
-----------------------------------------------------------

main()
