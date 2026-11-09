-- @description ALiXiA Insert Tension Macro Ramp (0% -> 100% -> 0% across Time Selection)
-- @author Rea & Alixia
-- @version 1.0
-- @about
--   Finds (or inserts) the ALiXiA MauP Tension Transition Macro JSFX on the selected
--   track (or Master track if none selected), reveals the Tension Macro envelope,
--   and draws a tight 0% -> 100% exponential build-up ramp with an instant 0% drop cliff
--   across the current Time Selection.

local r = reaper

local FX_MATCH_1 = "MauP Tension Transition"
local FX_MATCH_2 = "ALiXiA_MauP_Tension_Transition"
local JSFX_FILE  = "ALiXiA/ALiXiA_MauP_Tension_Transition.jsfx"

function main()
  -- 1. Verify Time Selection exists
  local start_time, end_time = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  if not start_time or not end_time or (end_time - start_time) < 0.05 then
    r.ShowMessageBox(
      "Please highlight a Time Selection over your build-up first!\n\nTip: Highlight from the start of the build-up right up to Beat 1 of the Drop.",
      "ALiXiA Tension Ramp",
      0
    )
    return
  end

  -- 2. Determine Target Track (Selected Track, or fallback to Master Track)
  local tr = r.GetSelectedTrack(0, 0)
  if not tr then
    tr = r.GetMasterTrack(0)
  end

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  -- 3. Search for the ALiXiA MauP Tension Transition JSFX on the track
  local fx_idx = -1
  local fx_count = r.TrackFX_GetCount(tr)
  for i = 0, fx_count - 1 do
    local retval, fx_name = r.TrackFX_GetFXName(tr, i, "")
    if retval and (fx_name:find(FX_MATCH_1, 1, true) or fx_name:find(FX_MATCH_2, 1, true)) then
      fx_idx = i
      break
    end
  end

  -- If not found on the track, try to auto-insert it
  if fx_idx == -1 then
    fx_idx = r.TrackFX_AddByName(tr, JSFX_FILE, false, -1)
    if fx_idx == -1 then
      fx_idx = r.TrackFX_AddByName(tr, "ALiXiA_MauP_Tension_Transition.jsfx", false, -1)
    end
    if fx_idx == -1 then
      fx_idx = r.TrackFX_AddByName(tr, "ALiXiA MauP Tension Transition Macro", false, -1)
    end
  end

  if fx_idx == -1 then
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("ALiXiA: Tension Ramp Failed (FX Not Found)", -1)
    r.ShowMessageBox(
      "Could not find 'ALiXiA_MauP_Tension_Transition.jsfx' on the selected track or in Effects!\n\nMake sure the JSFX is saved in your REAPER/Effects/ALiXiA/ folder or loaded on the track.",
      "ALiXiA Tension Ramp",
      0
    )
    return
  end

  -- 4. Get or create the Track Envelope for Parameter 0 (slider1: TENSION MACRO %)
  local param_idx = 0
  local env = r.GetFXEnvelope(tr, fx_idx, param_idx, true)
  if not env then
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("ALiXiA: Tension Ramp Failed (Envelope Error)", -1)
    return
  end

  -- Ensure the envelope is visible & armed in the arrange view via state chunk
  local retval, env_chunk = r.GetEnvelopeStateChunk(env, "", false)
  if retval then
    env_chunk = env_chunk:gsub("VIS %d+", "VIS 1")
    env_chunk = env_chunk:gsub("ACT %d+", "ACT 1")
    r.SetEnvelopeStateChunk(env, env_chunk, false)
  end

  -- 5. Detect envelope scaling and normalize 0% and 100% values
  local scale_mode = r.GetEnvelopeScalingMode(env)
  local _, min_val, max_val = r.TrackFX_GetParamEx(tr, fx_idx, param_idx)
  if not max_val or max_val <= min_val then
    min_val = 0.0
    max_val = 100.0
  end

  -- REAPER JSFX parameter envelopes sometimes store normalized 0..1 or raw slider 0..100
  -- We check the existing baseline point or TrackFX_GetParamNormalized behavior
  local val_zero = r.ScaleToEnvelopeMode(scale_mode, 0.0)
  local val_peak = r.ScaleToEnvelopeMode(scale_mode, 1.0)

  -- Verify by testing if the envelope max exceeds 1.0 (raw JSFX slider range 0..100)
  local br_test = r.GetEnvelopePointByTime(env, 0)
  if br_test >= 0 then
    -- Insert a temporary normalized probe to see how REAPER clamps this JSFX envelope
    r.DeleteEnvelopePointRange(env, start_time - 0.002, end_time + 0.002)
  else
    r.DeleteEnvelopePointRange(env, start_time - 0.002, end_time + 0.002)
  end

  -- Set the slider itself to 0% so baseline playback outside the ramp stays at 0%
  r.TrackFX_SetParamNormalized(tr, fx_idx, param_idx, 0.0)

  -- Check if this REAPER version expects raw slider values (0..100) or normalized (0..1) on JSFX envelopes
  -- Standard REAPER GetFXEnvelope on JSFX uses raw slider values (min_val to max_val)
  val_zero = r.ScaleToEnvelopeMode(scale_mode, min_val)
  val_peak = r.ScaleToEnvelopeMode(scale_mode, max_val)

  -- 6. Insert the 4 Surgical Automation Points:
  --    Point 1: Anchor 0% just outside the start of the build-up
  --    Point 2: Start of build-up at 0% with Bezier/Exponential tension (+0.35)
  --    Point 3: Peak of build-up at 100% right at the end of the Time Selection
  --    Point 4: Instant Drop Cliff back to 0% (+0.5ms after the end of the Time Selection)
  local eps = 0.0005

  r.InsertEnvelopePoint(env, start_time - eps, val_zero, 0, 0.0,  false, true)
  r.InsertEnvelopePoint(env, start_time,       val_zero, 5, 0.35, true,  true) -- Shape 5 = Bezier curve (+0.35 exponential rise)
  r.InsertEnvelopePoint(env, end_time,         val_peak, 0, 0.0,  true,  true) -- 100% Peak right before drop
  r.InsertEnvelopePoint(env, end_time + eps,   val_zero, 0, 0.0,  true,  true) -- 0% Instant Drop reset

  r.Envelope_SortPoints(env)

  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.Undo_EndBlock("ALiXiA: Insert 0-100-0% Tension Macro Ramp", -1)
end

main()
