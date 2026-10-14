-- Pip: a desktop penguin with no function. Most of the time it is hidden below the screen edge or
-- off to the side; every 20-90 s it waddles in or peeks up, does one to three silly things, may say
-- something, and leaves. Grab and throw it while it is out; click it for a giggle, or to wake it.
-- Hidden, its panel is unmapped: nothing is drawn, animated or composited. Each visit maps it again on
-- the output the compositor picks.

fonts { "Noto Sans" }

local VISIT_MIN, VISIT_MAX = 20000, 90000 -- ms hidden between visits
local GAP_MIN, GAP_MAX = 2500, 6500 -- ms between antics
local WALK_SPEED, STEP_MS = 140, 210 -- px/s along the floor, ms a step

math.randomseed(os.time())

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Size of the mascot's box, and the gap it keeps from the screen edge.
local W, H, EDGE, FLOOR_GAP = 104, 112, 8, 20

-- Tux colours: glossy black, white eye patches and belly, a gold beak and feet.
local BODY_TOP, BODY_BOT = "#3C3C44", "#09090C"
local PATCH, LID, DARK = "#FFFFFF", "#ECEDF1", "#0B0B0E"
local BEAK, BEAK_D = "#F2C230", "#B07A06"
local FOOT_TOP, FOOT_BOT = "#F7CF2A", "#C99606"

-- State -----------------------------------------------------------------------------------------

local present = state("mascot_present", false) -- drawn at all
local say = state("mascot_say", "")
local bubble_on = state("mascot_bubble", false)
local rest = state("mascot_rest", false) -- false until placed on the floor
local grab = state("mascot_grab", false)
local tilt = state("mascot_tilt", 0)
local phys = state("mascot_phys", "drag") -- motion set: drag, walk, coast, fall, or throw
local flight = state("mascot_flight", false) -- a throw's keyframes, while `phys` is "throw"
local air = state("mascot_air", false) -- thrown and not yet down
local walk_ms = state("mascot_walk_ms", 1000) -- length of the walk under way
local squish = state("mascot_squish", { x = 1, y = 1 })
local mood = state("mascot_mood", "normal")
local antic = state("mascot_antic", "")
local asleep = state("mascot_asleep", false)

local at = pointer("screen")
local screen = geometry("screen")

local function floor_y(s) return s.height - H - FLOOR_GAP end

local pos = computed({ at, grab, rest }, function(p, g, r)
    if g and p then return { x = g.ox + p.x - g.px, y = g.oy + p.y - g.py } end
    return r or { x = 0, y = 0 }
end)

-- Where the box is drawn, from a pointer handler's node-local point. A spring's live value cannot be
-- read, but the pointer is over the pixels it hit.
local function drawn_at(local_pt)
    local p = at:get()
    if not (p and local_pt) then return rest:get() end
    return { x = p.x - local_pt.x, y = p.y - local_pt.y }
end

-- Timers ----------------------------------------------------------------------------------------

-- Timers in a bucket that can be cancelled together.
local function bucket()
    local list = {}
    return function(ms, fn) list[#list + 1] = timer(math.max(1, ms), fn) end,
        function()
            for _, h in ipairs(list) do h:cancel() end
            list = {}
        end
end
-- `later`: an antic's steps and the visit's plan, which a poke or a grab replaces. `in_flight`: a
-- throw's landing, which only a grab or the end of the visit cuts short.
local later, cancel_pending = bucket()
local in_flight, cancel_flight = bucket()

-- Keyframe helpers ------------------------------------------------------------------------------

-- kf { {first}, {value, ms, easing?}, ... } is a keyframe entry; its run time is kept in TOTAL.
local TOTAL = setmetatable({}, { __mode = "k" })
local function kf(spec)
    local frames, total = {}, 0
    for i, f in ipairs(spec) do
        if i == 1 then
            frames[1] = f[1]
        else
            frames[i] = { value = f[1], duration = f[2], easing = f[3] }
            total = total + f[2]
        end
    end
    local entry = { duration = 200, easing = "in_out_sine", keyframes = frames }
    TOTAL[entry] = total
    return entry
end

local function T(x, y) return { x = x, y = y } end
local REST_SCALE = T(1, 1)

local GRAVITY = 3200 -- px/s²
local function ms(t) return math.max(1, math.floor(t * 1000 + 0.5)) end

-- A stretch of parabola as a CSS bezier. `a` is the start speed times the duration over the distance:
-- 0 starts from rest, 2 ends at rest.
local function arc(a) return { 1 / 3, a / 3, 2 / 3, (a + 1) / 3 } end

local ANTICS = {}
-- parts: layer name -> { property -> kf }. script: { { ms, mood?, line? } }. opts.after: lines it
-- may say once done; opts.props(n): nodes shown for the run, ids suffixed with `n`. The run lasts as
-- long as the longest track, plus 80 ms of slack.
local function def(name, parts, script, opts)
    local dur = 0
    for _, props in pairs(parts) do
        for _, entry in pairs(props) do dur = math.max(dur, TOTAL[entry]) end
    end
    opts = opts or {}
    ANTICS[name] = { parts = parts, script = script or {}, dur = dur + 80, after = opts.after, props = opts.props }
end

-- The antics ------------------------------------------------------------------------------------
-- Layers: `spin` turns about the centre, `act` moves and squashes about the feet. Both end where
-- they began, so dropping the entry at the end of a run changes nothing.

def("hop", {
    act = {
        translate = kf { { T(0, 0) }, { T(0, 0), 120 }, { T(0, -34), 220, "out_quad" }, { T(0, 0), 220, "in_quad" }, { T(0, -14), 130, "out_quad" }, { T(0, 0), 130, "in_quad" } },
        scale = kf { { REST_SCALE }, { T(1.14, 0.84), 120 }, { T(0.9, 1.14), 220 }, { T(1.16, 0.8), 220 }, { T(0.94, 1.08), 130 }, { T(1.08, 0.9), 130 }, { REST_SCALE, 160 } },
    },
    ground = { scale = kf { { REST_SCALE }, { REST_SCALE, 120 }, { T(0.6, 0.6), 220 }, { REST_SCALE, 220 } } },
}, { { 1, "happy" } })

def("double_take", {
    pupil = { translate = kf { { T(0, 0) }, { T(-4, 0), 120 }, { T(-4, 0), 500 }, { T(4, 0), 160 }, { T(4, 0), 500 }, { T(0, 0), 160 } } },
    spin = { rotate = kf { { 0 }, { -7, 140 }, { -7, 500 }, { 7, 180 }, { 7, 500 }, { 0, 160 } } },
    act = { scale = kf { { REST_SCALE }, { REST_SCALE, 1580 }, { T(0.9, 1.15), 120, "out_back" }, { REST_SCALE, 260 } } },
}, { { 1580, "surprised" }, { 2100, "normal" } })

def("spin", {
    -- The lift is on `spin` too: `translate` applies after `rotate`, so it turns about its own centre.
    spin = {
        rotate = kf { { 0 }, { 0, 220 }, { 360, 700, "out_cubic" } },
        translate = kf { { T(0, 0) }, { T(0, 0), 220 }, { T(0, -40), 300, "out_quad" }, { T(0, 0), 400, "in_quad" } },
    },
    act = {
        scale = kf { { REST_SCALE }, { T(1.12, 0.82), 220 }, { T(0.92, 1.12), 300 }, { T(1.16, 0.8), 400 }, { REST_SCALE, 160 } },
    },
    ground = { scale = kf { { REST_SCALE }, { REST_SCALE, 220 }, { T(0.6, 0.6), 300 }, { REST_SCALE, 400 } } },
}, { { 1, "happy" }, { 1100, "dizzy" }, { 1700, "normal" } })

def("sneeze", {
    spin = { rotate = kf { { 0 }, { -12, 650 }, { -12, 200 }, { 18, 90, "out_cubic" }, { 18, 160 }, { 0, 420 } } },
    act = {
        translate = kf { { T(0, 0) }, { T(0, 0), 850 }, { T(14, 4), 90, "out_cubic" }, { T(14, 4), 160 }, { T(0, 0), 420 } },
        scale = kf { { REST_SCALE }, { T(0.94, 1.12), 650 }, { T(0.94, 1.12), 200 }, { T(1.14, 0.86), 90 }, { T(1.14, 0.86), 160 }, { REST_SCALE, 420 } },
    },
    puff = {
        opacity = kf { { 0 }, { 0, 940 }, { 0.95, 40 }, { 0.95, 220 }, { 0, 360 } },
        scale = kf { { 0.3 }, { 0.3, 940 }, { 0.5, 40 }, { 1.8, 580 } },
        translate = kf { { T(0, 0) }, { T(0, 0), 940 }, { T(0, 0), 40 }, { T(34, -6), 580, "out_cubic" } },
    },
}, { { 1, "yawn" }, { 850, "sneeze", "achoo!", 1400 }, { 1500, "normal" } })

def("sleep", {
    spin = { rotate = kf { { 0 }, { 6, 500 }, { 1, 350 }, { 9, 450 }, { 3, 300 }, { 8, 500 } } },
    act = { scale = kf { { REST_SCALE }, { T(1.04, 0.92), 2100 } }, translate = kf { { T(0, 0) }, { T(0, 6), 2100 } } },
}, { { 1, "sleepy" }, { 1500, "sleep", "zzz...", 2500 } })

def("jelly", {
    act = {
        scale = kf { { REST_SCALE }, { T(1.24, 0.78), 110 }, { T(0.84, 1.2), 150 }, { T(1.16, 0.86), 150 }, { T(0.9, 1.12), 150 }, { T(1.1, 0.92), 150 }, { T(0.95, 1.06), 150 }, { T(1.04, 0.97), 150 }, { REST_SCALE, 150 } },
    },
    spin = { rotate = kf { { 0 }, { 5, 150 }, { -5, 300 }, { 4, 300 }, { -3, 300 }, { 0, 300 } } },
}, { { 1, "dizzy" }, { 1500, "normal" } })

def("stretch", {
    act = {
        scale = kf { { REST_SCALE }, { T(0.88, 1.24), 700, "out_cubic" }, { T(0.88, 1.24), 1100 }, { T(1.1, 0.9), 220 }, { REST_SCALE, 260, "out_back" } },
        translate = kf { { T(0, 0) }, { T(0, 0), 2020 }, { T(0, 0), 260 } },
    },
    arm_l = { rotate = kf { { 8 }, { 168, 700, "out_cubic" }, { 168, 1100 }, { 8, 380 } } },
    arm_r = { rotate = kf { { -8 }, { -168, 700, "out_cubic" }, { -168, 1100 }, { -8, 380 } } },
}, { { 600, "yawn" }, { 1800, "sleepy" }, { 2300, "normal" } })

def("shimmy", {
    spin = { rotate = kf { { 0 }, { -11, 130 }, { 11, 260 }, { -11, 260 }, { 11, 260 }, { -11, 260 }, { 11, 260 }, { -11, 260 }, { 0, 130 } } },
    act = {
        translate = kf { { T(0, 0) }, { T(-7, -4), 130 }, { T(7, 0), 260 }, { T(-7, -4), 260 }, { T(7, 0), 260 }, { T(-7, -4), 260 }, { T(7, 0), 260 }, { T(-7, -4), 260 }, { T(0, 0), 130 } },
        scale = kf { { REST_SCALE }, { T(0.96, 1.05), 130 }, { T(1.05, 0.95), 260 }, { T(0.96, 1.05), 260 }, { T(1.05, 0.95), 260 }, { T(0.96, 1.05), 260 }, { T(1.05, 0.95), 260 }, { T(0.96, 1.05), 260 }, { REST_SCALE, 130 } },
    },
    arm_l = { rotate = kf { { 8 }, { 60, 130 }, { 130, 260 }, { 60, 260 }, { 130, 260 }, { 60, 260 }, { 130, 260 }, { 60, 260 }, { 8, 130 } } },
    arm_r = { rotate = kf { { -8 }, { -130, 130 }, { -60, 260 }, { -130, 260 }, { -60, 260 }, { -130, 260 }, { -60, 260 }, { -130, 260 }, { -8, 130 } } },
}, { { 1, "happy" }, { 2100, "normal" } })

def("faceplant", {
    act = {
        rotate = kf { { 0 }, { 14, 250 }, { 90, 300, "in_quad" }, { 84, 90, "out_quad" }, { 90, 90, "in_quad" }, { 90, 1000 }, { 0, 520, "out_back" } },
        translate = kf { { T(0, 0) }, { T(8, 0), 250 }, { T(30, -34), 300, "in_quad" }, { T(30, -34), 90 }, { T(30, -34), 90 }, { T(30, -34), 1000 }, { T(0, 0), 520 } },
    },
    spin = { rotate = kf { { 0 }, { -6, 250 }, { 0, 300 } } },
}, { { 1, "surprised", "oof." }, { 560, "dizzy" }, { 1900, "sleepy" }, { 2300, "normal" } })

def("wave", {
    arm_r = { rotate = kf { { -8 }, { -140, 280, "out_cubic" }, { -105, 170 }, { -150, 170 }, { -105, 170 }, { -150, 170 }, { -105, 170 }, { -150, 170 }, { -8, 320 } } },
    spin = { rotate = kf { { 0 }, { -4, 280 }, { -4, 1020 }, { 0, 320 } } },
}, { { 1, "happy", "hi!", 1400 }, { 1700, "normal" } })

-- A pupil circling the eye, three-quarters of a turn twice, with a bored lid.
local ROLL = { T(0, -4), T(4, 0), T(0, 4), T(-4, 0) }
local function roll()
    local spec = { { T(0, 0) }, { ROLL[4], 150 } }
    for lap = 1, 2 do
        for i = 1, 4 do spec[#spec + 1] = { ROLL[i], 230, "linear" } end
    end
    spec[#spec + 1] = { T(0, 0), 200 }
    return kf(spec)
end
def("eye_roll", {
    pupil = { translate = roll() },
    spin = { rotate = kf { { 0 }, { 3, 400 }, { 3, 1500 }, { 0, 300 } } },
}, { { 1, "bored" }, { 2400, "normal" } })

def("peek", {
    act = {
        scale = kf { { REST_SCALE }, { T(1.15, 0.85), 140 }, { T(0.02, 0.02), 360, "in_back" }, { T(0.02, 0.02), 1400 }, { T(1.2, 0.8), 140, "out_quad" }, { T(0.9, 1.15), 160 }, { REST_SCALE, 220, "out_back" } },
    },
}, { { 1, "surprised" }, { 2200, "happy" }, { 2800, "normal" } })

-- Reactions to a click; not drawn at random.
def("giggle", {
    act = {
        scale = kf { { REST_SCALE }, { T(1.22, 0.78), 90 }, { T(0.92, 1.1), 130 }, { T(1.1, 0.92), 130 }, { T(0.96, 1.04), 130 }, { REST_SCALE, 130 } },
        translate = kf { { T(0, 0) }, { T(0, 0), 90 }, { T(0, -10), 130 }, { T(0, 0), 130 }, { T(0, -6), 130 }, { T(0, 0), 130 } },
    },
    spin = { rotate = kf { { 0 }, { -6, 90 }, { 6, 130 }, { -6, 130 }, { 6, 130 }, { 0, 130 } } },
}, { { 1, "happy" }, { 1000, "normal" } })

def("wake", {
    act = {
        translate = kf { { T(0, 6) }, { T(0, -30), 200, "out_quad" }, { T(0, 0), 220, "in_quad" } },
        scale = kf { { T(1.04, 0.92) }, { T(0.88, 1.2), 200 }, { T(1.16, 0.82), 220 }, { REST_SCALE, 180 } },
    },
}, { { 1, "surprised" }, { 800, "normal" } })

-- Steps, in place or along a walk: the body rocks onto one foot while the other lifts, and the
-- flippers swing against it. `sway` slides the body onto the standing foot too.
local function gait(steps, step_ms, rock, sway)
    local half = step_ms / 2
    local rot, bob, al, ar = { { 0 } }, { { T(0, 0) } }, { { 8 } }, { { -8 } }
    local fl, fr = { { T(0, 0) } }, { { T(0, 0) } }
    for i = 1, steps do
        local s = i % 2 == 1 and 1 or -1 -- 1: standing on the right foot, the left one up
        rot[#rot + 1] = { rock * s, step_ms, "in_out_sine" }
        bob[#bob + 1] = { T(sway * s, -3), half, "out_quad" }
        bob[#bob + 1] = { T(sway * s, 0), half, "in_quad" }
        fl[#fl + 1] = { s > 0 and T(-1, -5) or T(0, 0), half, "out_quad" }
        fl[#fl + 1] = { T(0, 0), half, "in_quad" }
        fr[#fr + 1] = { s < 0 and T(1, -5) or T(0, 0), half, "out_quad" }
        fr[#fr + 1] = { T(0, 0), half, "in_quad" }
        al[#al + 1] = { 8 + 12 * s, step_ms, "in_out_sine" }
        ar[#ar + 1] = { -8 + 12 * s, step_ms, "in_out_sine" }
    end
    rot[#rot + 1] = { 0, 160 }
    bob[#bob + 1] = { T(0, 0), 160 }
    al[#al + 1] = { 8, 160 }
    ar[#ar + 1] = { -8, 160 }
    return {
        spin = { rotate = kf(rot) },
        act = { translate = kf(bob) },
        foot_l = { translate = kf(fl) },
        foot_r = { translate = kf(fr) },
        arm_l = { rotate = kf(al) },
        arm_r = { rotate = kf(ar) },
    }
end
def("waddle", gait(6, 180, 10, 14), { { 1, "happy" }, { 1100, "normal" } }, { after = { "waddle waddle", "that's the penguin shuffle." } })

local function flap_arms(sign, n)
    local f = { { sign * 8 } }
    for i = 1, n do f[#f + 1] = { sign * (i % 2 == 1 and 80 or 8), 120 } end
    f[#f + 1] = { sign * 8, 160 }
    return kf(f)
end
def("flap", {
    arm_l = { rotate = flap_arms(1, 12) },
    arm_r = { rotate = flap_arms(-1, 12) },
    act = {
        translate = kf { { T(0, 0) }, { T(0, -8), 300 }, { T(0, -14), 600 }, { T(0, -8), 300 }, { T(0, 0), 400 } },
        scale = kf { { REST_SCALE }, { T(0.95, 1.08), 300 }, { T(0.95, 1.08), 900 }, { REST_SCALE, 400 } },
    },
    ground = { scale = kf { { REST_SCALE }, { T(0.75, 0.75), 600 }, { T(0.75, 0.75), 600 }, { REST_SCALE, 400 } } },
}, { { 1, "happy" }, { 1600, "normal" } })

-- Flop onto the belly and slide out and back; `dir` is -1 or 1.
local function slide(dir)
    return {
        act = {
            rotate = kf { { 0 }, { dir * 88, 260, "in_quad" }, { dir * 88, 1900 }, { 0, 500, "out_back" } },
            translate = kf { { T(0, 0) }, { T(dir * 8, -36), 260 }, { T(dir * 150, -36), 100 + 700, "out_cubic" }, { T(dir * 150, -36), 300 }, { T(dir * 8, -36), 700 }, { T(dir * 8, -36), 100 }, { T(0, 0), 500 } },
        },
        arm_l = { rotate = kf { { 8 }, { 160, 260 }, { 160, 1900 }, { 8, 500 } } },
        arm_r = { rotate = kf { { -8 }, { -160, 260 }, { -160, 1900 }, { -8, 500 } } },
    }
end
def("belly_slide_r", slide(1), { { 1, "happy" }, { 2700, "normal" } })
def("belly_slide_l", slide(-1), { { 1, "happy" }, { 2700, "normal" } })

def("slip", {
    act = {
        rotate = kf { { 0 }, { -12, 180 }, { -35, 150 }, { -92, 280, "in_quad" }, { -86, 90 }, { -90, 90 }, { -90, 900 }, { 0, 520, "out_back" } },
        translate = kf { { T(0, 0) }, { T(-10, 0), 180 }, { T(-24, -8), 150 }, { T(-44, -36), 280 }, { T(-44, -36), 90 }, { T(-44, -36), 90 }, { T(-44, -36), 900 }, { T(0, 0), 520 } },
    },
    arm_l = { rotate = kf { { 8 }, { 8, 610 }, { 100, 150 }, { 20, 150 }, { 100, 150 }, { 20, 150 }, { 100, 150 }, { 20, 150 }, { 8, 300 } } },
    arm_r = { rotate = kf { { -8 }, { -8, 610 }, { -20, 150 }, { -100, 150 }, { -20, 150 }, { -100, 150 }, { -20, 150 }, { -100, 150 }, { -8, 300 } } },
}, { { 1, "surprised", "waaah!" }, { 560, "dizzy" }, { 1900, "sleepy" }, { 2300, "normal" } })

-- Props: nodes an antic brings along, new each run so their keyframes start over.
local function prop(kind, id, n, t)
    t.id = id .. n
    t.hittable = false
    return kind(t)
end

local function fish(n)
    return prop(path, "fish", n, {
        width = 26,
        height = 14,
        align_h = "center",
        margin = { top = 42 },
        fill = "#7FB8E6",
        stroke = "#4C86B8",
        stroke_width = 1.2,
        commands = {
            { op = "M", points = { 1, 7 } },
            { op = "Q", points = { 9, -1, 18, 7 } },
            { op = "L", points = { 25, 1 } },
            { op = "L", points = { 25, 13 } },
            { op = "L", points = { 18, 7 } },
            { op = "Q", points = { 9, 15, 1, 7 } },
            { op = "Z", points = {} },
        },
        translate = T(0, 0),
        opacity = 1,
        rotate = 0,
        animate = {
            translate = { duration = 100, keyframes = { T(0, -120), { value = T(0, -120), duration = 250 }, { value = T(0, 0), duration = 520, easing = "in_quad" } } },
            rotate = { duration = 100, keyframes = { 0, { value = 0, duration = 250 }, { value = 540, duration = 520, easing = "in_quad" } } },
            opacity = { duration = 100, keyframes = { 1, { value = 1, duration = 770 }, { value = 0, duration = 60 } } },
        },
    })
end

local function heart(n, wait)
    return prop(path, "heart", n .. "_" .. wait, {
        width = 20,
        height = 18,
        align_h = "center",
        margin = { top = 4 },
        fill = "#FF6B8B",
        commands = {
            { op = "M", points = { 10, 17 } },
            { op = "C", points = { 3, 12, 0, 8, 0, 5 } },
            { op = "C", points = { 0, 2, 2, 0, 5, 0 } },
            { op = "C", points = { 7, 0, 9, 1, 10, 3 } },
            { op = "C", points = { 11, 1, 13, 0, 15, 0 } },
            { op = "C", points = { 18, 0, 20, 2, 20, 5 } },
            { op = "C", points = { 20, 8, 17, 12, 10, 17 } },
            { op = "Z", points = {} },
        },
        translate = T(0, 0),
        opacity = 0,
        scale = 0.4,
        animate = {
            translate = { duration = 1300, delay = wait, easing = "out_sine", keyframes = { T(0, 0), T(wait > 0 and 10 or -8, -46) } },
            opacity = { duration = 1300, delay = wait, keyframes = { 0, 1, 1, 0 } },
            scale = { duration = 1300, delay = wait, easing = "out_back", keyframes = { 0.4, 1.1 } },
        },
    })
end

local function mark(n, content, color)
    return prop(text, "mark", n, {
        content = content,
        font_size = 22,
        font_weight = 800,
        foreground = color,
        align_h = "end",
        margin = { top = -6, right = 10 },
        scale = 1,
        rotate = 0,
        animate = {
            scale = { duration = 100, keyframes = { 0, { value = 0, duration = 200 }, { value = 1, duration = 260, easing = "out_back" } } },
            rotate = { duration = 500, easing = "in_out_sine", loops = 3, keyframes = { 0, 12, -12, 0 } },
        },
    })
end

local function note(n, wait, dx)
    return prop(rect, "note", n .. "_" .. wait, {
        width = 10,
        height = 16,
        align_h = dx > 0 and "end" or "start",
        margin = { top = 10, left = 6, right = 6 },
        opacity = 0,
        translate = T(0, 0),
        animate = {
            translate = { duration = 1400, delay = wait, easing = "out_sine", keyframes = { T(0, 0), T(dx, -40) } },
            opacity = { duration = 1400, delay = wait, keyframes = { 0, 1, 1, 0 } },
        },
        children = {
            rect { width = 8, height = 6, radius = 3, align_v = "end", background = "#9CC8FF" },
            rect { width = 2, height = 14, align_h = "end", margin = { right = 1 }, background = "#9CC8FF" },
        },
    })
end

local function sparkle(n, i)
    local a = math.rad(i * 72 - 90)
    return prop(rect, "spark", n .. "_" .. i, {
        width = 8,
        height = 8,
        rotate = 45,
        background = "#FFE066",
        align_h = "center",
        margin = { top = 10 },
        opacity = 0,
        translate = T(0, 0),
        animate = {
            translate = { duration = 100, keyframes = { T(0, 0), { value = T(0, 0), duration = 300 }, { value = T(math.cos(a) * 44, math.sin(a) * 34), duration = 600, easing = "out_cubic" } } },
            opacity = { duration = 100, keyframes = { 0, { value = 0, duration = 300 }, { value = 1, duration = 60 }, { value = 1, duration = 300 }, { value = 0, duration = 300 } } },
        },
    })
end

local function dust(n, i, dx)
    return prop(rect, "dust", n .. "_" .. i, {
        width = 12,
        height = 12,
        radius = 999,
        background = "#FFFFFFB0",
        align_h = "center",
        align_v = "end",
        opacity = 0,
        scale = 0.4,
        translate = T(0, 0),
        animate = {
            translate = { duration = 500, delay = i * 400, easing = "out_cubic", keyframes = { T(0, 0), T(dx, -10) } },
            opacity = { duration = 500, delay = i * 400, keyframes = { 0.9, 0 } },
            scale = { duration = 500, delay = i * 400, keyframes = { 0.4, 1.4 } },
        },
    })
end

-- Repeats `frames` (pairs of value and ms) `n` times after the first frame, then returns to `rest_`.
local function rep(first, n, frames, rest_, back_ms)
    local f = { { first } }
    for _ = 1, n do
        for _, fr in ipairs(frames) do f[#f + 1] = fr end
    end
    f[#f + 1] = { rest_, back_ms or 200 }
    return kf(f)
end

def("foot_tap", {
    foot_r = { rotate = rep(0, 7, { { -24, 110, "out_quad" }, { 0, 110, "in_quad" } }, 0) },
    spin = { rotate = kf { { 0 }, { 4, 300 }, { 4, 1440 }, { 0, 300 } } },
    arm_l = { rotate = kf { { 8 }, { -20, 300 }, { -20, 1440 }, { 8, 300 } } },
    pupil = { translate = kf { { T(0, 0) }, { T(3, -3), 300 }, { T(3, -3), 1440 }, { T(0, 0), 300 } } },
}, { { 1, "bored" }, { 2000, "normal" } }, { after = { "any day now.", "I'm not impatient. you're slow.", "is my fish ready yet?" } })

def("look_around", {
    pupil = { translate = kf { { T(0, 0) }, { T(-4, 0), 140 }, { T(-4, 0), 700 }, { T(4, 0), 180 }, { T(4, 0), 700 }, { T(0, -4), 160 }, { T(0, -4), 500 }, { T(0, 0), 160 } } },
    spin = { rotate = kf { { 0 }, { -6, 200 }, { -6, 640 }, { 6, 260 }, { 6, 620 }, { 0, 200 }, { 0, 520 } } },
}, { { 600, "think" }, { 2300, "normal" } }, { after = { "coast is clear.", "nobody's watching. good.", "I sense... fish." } })

do
    local sp, tr, al, ar, fl, fr = { { 0 } }, { { T(0, 0) } }, { { 8 } }, { { -8 } }, { { T(0, 0) } }, { { T(0, 0) } }
    for i = 1, 8 do
        local s = i % 2 == 1 and 1 or -1
        sp[#sp + 1] = { 10 * s, 300, "out_back" }
        tr[#tr + 1] = { T(8 * s, -6), 150, "out_quad" }
        tr[#tr + 1] = { T(8 * s, 0), 150, "in_quad" }
        al[#al + 1] = { s > 0 and 140 or 30, 300, "out_back" }
        ar[#ar + 1] = { s > 0 and -30 or -140, 300, "out_back" }
        fl[#fl + 1] = { T(0, s > 0 and -6 or 0), 150 }
        fl[#fl + 1] = { T(0, 0), 150 }
        fr[#fr + 1] = { T(0, s < 0 and -6 or 0), 150 }
        fr[#fr + 1] = { T(0, 0), 150 }
    end
    sp[#sp + 1] = { 0, 200 }
    tr[#tr + 1] = { T(0, 0), 200 }
    al[#al + 1] = { 8, 200 }
    ar[#ar + 1] = { -8, 200 }
    def("dance", {
        spin = { rotate = kf(sp) },
        act = { translate = kf(tr) },
        arm_l = { rotate = kf(al) },
        arm_r = { rotate = kf(ar) },
        foot_l = { translate = kf(fl) },
        foot_r = { translate = kf(fr) },
    }, { { 1, "happy", "dance break!" }, { 2500, "normal" } }, { after = { "I've still got it.", "nobody puts Pip in a corner." } })
end

def("backflip", {
    -- Lift and turn on the same layer, so it flips about its own middle.
    spin = {
        rotate = kf { { 0 }, { 0, 260 }, { -360, 620, "in_out_cubic" } },
        translate = kf { { T(0, 0) }, { T(0, 0), 260 }, { T(0, -80), 310, "out_quad" }, { T(0, 0), 310, "in_quad" } },
    },
    act = { scale = kf { { REST_SCALE }, { T(1.18, 0.78), 240, "out_quad" }, { T(0.9, 1.12), 120 }, { T(0.9, 1.12), 520 }, { T(1.24, 0.76), 90 }, { REST_SCALE, 320, "out_back" } } },
    ground = { scale = kf { { REST_SCALE }, { REST_SCALE, 260 }, { T(0.5, 0.5), 310 }, { REST_SCALE, 310 } } },
}, { { 1, "effort" }, { 280, "surprised" }, { 900, "smug" }, { 2000, "normal" } }, { after = { "nailed it.", "I do my own stunts.", "the judges give it a 10." } })

def("bow", {
    act = { scale = kf { { REST_SCALE }, { T(1.06, 0.84), 380, "out_cubic" }, { T(1.06, 0.84), 600 }, { REST_SCALE, 360, "out_back" } } },
    arm_r = { rotate = kf { { -8 }, { -75, 380 }, { -75, 600 }, { -8, 360 } } },
    arm_l = { rotate = kf { { 8 }, { 35, 380 }, { 35, 600 }, { 8, 360 } } },
    pupil = { translate = kf { { T(0, 0) }, { T(0, 4), 380 }, { T(0, 4), 600 }, { T(0, 0), 360 } } },
}, { { 1, "happy" }, { 1340, "normal" } }, { after = { "thank you, thank you.", "I'll be here all week." } })

def("shiver", {
    act = {
        translate = rep(T(0, 0), 15, { { T(2, 0), 45, "linear" }, { T(-2, 0), 45, "linear" } }, T(0, 0), 60),
        scale = kf { { REST_SCALE }, { T(0.94, 0.97), 200 }, { T(0.94, 0.97), 1150 }, { REST_SCALE, 200 } },
    },
    arm_l = { rotate = kf { { 8 }, { -18, 200 }, { -18, 1150 }, { 8, 200 } } },
    arm_r = { rotate = kf { { -8 }, { 18, 200 }, { 18, 1150 }, { -8, 200 } } },
}, { { 1, "cold", "brrr" }, { 1500, "normal" } }, { after = { "who left the window open?", "I'm a penguin. I'm FINE.", "need... tiny scarf" } })

do
    -- Three hiccups at uneven gaps; each one jolts it up.
    local tr, sc, script = { { T(0, 0) } }, { { REST_SCALE } }, {}
    local at_ms = 0
    for i, gap in ipairs { 300, 700, 450 } do
        local up = i == 3 and -18 or -13
        tr[#tr + 1] = { T(0, 0), gap }
        tr[#tr + 1] = { T(0, up), 90, "out_quad" }
        tr[#tr + 1] = { T(0, 0), 150, "in_quad" }
        sc[#sc + 1] = { REST_SCALE, gap }
        sc[#sc + 1] = { T(0.9, 1.14), 90 }
        sc[#sc + 1] = { REST_SCALE, 150, "out_back" }
        at_ms = at_ms + gap
        script[#script + 1] = { at_ms, "surprised", i == 3 and "HIC!" or "hic!" }
        script[#script + 1] = { at_ms + 240, "normal" }
        at_ms = at_ms + 240
    end
    def("hiccup", { act = { translate = kf(tr), scale = kf(sc) } }, script, { after = { "...is it over?", "excuse me.", "I swallowed a bubble." } })
end

def("moonwalk", {
    act = { translate = kf { { T(0, 0) }, { T(48, 0), 1600, "linear" }, { T(48, 0), 300 }, { T(0, 0), 600, "in_out_sine" } } },
    spin = { rotate = kf { { 0 }, { -6, 200 }, { -6, 1400 }, { 0, 300 } } },
    foot_l = { translate = rep(T(0, 0), 4, { { T(-6, -3), 200 }, { T(0, 0), 200 } }, T(0, 0)) },
    foot_r = { translate = rep(T(0, 0), 4, { { T(0, 0), 200 }, { T(-6, -3), 200 } }, T(0, 0)) },
}, { { 1, "smug" }, { 1700, "happy", "hee-hee!" }, { 2500, "normal" } })

def("snack", {
    pupil = { translate = kf { { T(0, 0) }, { T(0, -4), 200 }, { T(0, -4), 400 }, { T(0, 3), 250 }, { T(0, 0), 300 } } },
    act = { scale = kf { { REST_SCALE }, { REST_SCALE, 770 }, { T(1.12, 0.9), 80 }, { T(0.97, 1.04), 160 }, { T(1.04, 0.97), 160 }, { T(0.98, 1.02), 160 }, { REST_SCALE, 160 } } },
}, { { 250, "surprised" }, { 850, "happy", "nom" }, { 1900, "normal" } }, {
    after = { "tastes like Tuesday.", "five stars. would gulp again.", "more where that came from?" },
    props = function(n) return { fish(n) } end,
})

def("love", {
    spin = { rotate = kf { { 0 }, { 5, 450, "in_out_sine" }, { -5, 600, "in_out_sine" }, { 5, 600, "in_out_sine" }, { 0, 450 } } },
    arm_l = { rotate = kf { { 8 }, { -22, 300 }, { -22, 1500 }, { 8, 300 } } },
    arm_r = { rotate = kf { { -8 }, { 22, 300 }, { 22, 1500 }, { -8, 300 } } },
    act = { scale = kf { { REST_SCALE }, { T(1.03, 0.97), 300 }, { REST_SCALE, 300 }, { T(1.03, 0.97), 300 }, { REST_SCALE, 300 } } },
}, { { 1, "happy" }, { 2100, "normal" } }, {
    after = { "you're alright, you know.", "don't make it weird." },
    props = function(n) return { heart(n, 0), heart(n, 500) } end,
})

def("zoomies", {
    act = { translate = kf { { T(0, 0) }, { T(70, 0), 260, "in_out_quad" }, { T(-70, 0), 420, "in_out_quad" }, { T(60, 0), 400, "in_out_quad" }, { T(-40, 0), 360, "in_out_quad" }, { T(0, 0), 320, "out_back" } } },
    spin = { rotate = kf { { 0 }, { 14, 260 }, { -14, 420 }, { 14, 400 }, { -10, 360 }, { 0, 320 } } },
    foot_l = { translate = rep(T(0, 0), 9, { { T(0, -5), 90 }, { T(0, 0), 90 } }, T(0, 0), 140) },
    foot_r = { translate = rep(T(0, 0), 9, { { T(0, 0), 90 }, { T(0, -5), 90 } }, T(0, 0), 140) },
}, { { 1, "happy", "ZOOMIES" }, { 1800, "dizzy" }, { 2500, "normal" } }, {
    after = { "*pant pant*", "I don't know why I did that." },
    props = function(n) return { dust(n, 0, -30), dust(n, 1, 30), dust(n, 2, -30) } end,
})

def("ponder", {
    spin = { rotate = kf { { 0 }, { 9, 300 }, { 9, 1600 }, { 0, 300 } } },
    pupil = { translate = kf { { T(0, 0) }, { T(-3, -4), 300 }, { T(-3, -4), 1600 }, { T(0, 0), 300 } } },
    arm_r = { rotate = rep(-8, 4, { { -40, 200 }, { -25, 200 } }, -8, 300) },
}, { { 1, "think" }, { 2200, "normal" } }, {
    after = { "hmm.", "what if... fish, but bigger?", "where do icebergs go at night?", "I forgot what I was thinking." },
    props = function(n) return { mark(n, "?", "#7FB8FF") } end,
})

def("tada", {
    act = {
        translate = kf { { T(0, 0) }, { T(0, 0), 220 }, { T(0, -26), 220, "out_quad" }, { T(0, 0), 220, "in_quad" }, { T(0, 0), 800 } },
        scale = kf { { REST_SCALE }, { T(1.15, 0.82), 220 }, { T(0.9, 1.12), 220 }, { T(1.12, 0.88), 220 }, { REST_SCALE, 260, "out_back" } },
    },
    arm_l = { rotate = kf { { 8 }, { 8, 220 }, { 145, 220, "out_back" }, { 145, 900 }, { 8, 300 } } },
    arm_r = { rotate = kf { { -8 }, { -8, 220 }, { -145, 220, "out_back" }, { -145, 900 }, { -8, 300 } } },
}, { { 1, "effort" }, { 240, "happy", "ta-da!" }, { 1700, "normal" } }, {
    after = { "you may applaud.", "and for my next trick..." },
    props = function(n) return { sparkle(n, 0), sparkle(n, 1), sparkle(n, 2), sparkle(n, 3), sparkle(n, 4) } end,
})

def("squats", {
    act = { scale = rep(REST_SCALE, 4, { { T(1.1, 0.8), 350, "in_out_sine" }, { REST_SCALE, 350, "in_out_sine" } }, REST_SCALE) },
    arm_l = { rotate = kf { { 8 }, { 80, 250 }, { 80, 2550 }, { 8, 300 } } },
    arm_r = { rotate = kf { { -8 }, { -80, 250 }, { -80, 2550 }, { -8, 300 } } },
}, { { 1, "effort", "one..." }, { 700, nil, "two..." }, { 1400, nil, "three..." }, { 2100, nil, "...four" }, { 2900, "normal" } }, {
    after = { "never skip leg day.", "these are thighs. trust me." },
})

def("sing", {
    spin = { rotate = kf { { 0 }, { 6, 450, "in_out_sine" }, { -6, 600, "in_out_sine" }, { 6, 600, "in_out_sine" }, { -6, 600, "in_out_sine" }, { 0, 450 } } },
    act = { scale = rep(REST_SCALE, 3, { { T(0.97, 1.05), 300 }, { REST_SCALE, 300 } }, REST_SCALE) },
}, { { 1, "sing", "la la laaa" }, { 600, "happy" }, { 1000, "sing" }, { 1600, "happy" }, { 2000, "sing" }, { 2700, "normal" } }, {
    after = { "the acoustics in here are great.", "I'm available for weddings." },
    props = function(n) return { note(n, 0, -16), note(n, 700, 16), note(n, 1400, -12) } end,
})

-- Jumps clean off the top of the screen and comes back down a while later; built for where it stands.
local function boing(y)
    local h = y + H + 40
    local t = ms(math.sqrt(2 * h / GRAVITY))
    def("boing", {
        act = {
            translate = kf { { T(0, 0) }, { T(0, 0), 260 }, { T(0, -h), t, arc(2) }, { T(0, -h), 900 }, { T(0, 0), t, arc(0) }, { T(0, 0), 330 } },
            scale = kf { { REST_SCALE }, { T(1.2, 0.76), 260, "out_quad" }, { T(0.84, 1.2), 120 }, { T(0.92, 1.08), math.max(1, t - 120) }, { T(0.92, 1.08), 900 }, { T(0.86, 1.18), t }, { T(1.3, 0.7), 70 }, { REST_SCALE, 260, "out_back" } },
        },
        ground = { scale = kf { { REST_SCALE }, { REST_SCALE, 260 }, { T(0.2, 0.2), t }, { T(0.2, 0.2), 900 }, { REST_SCALE, t } } },
    }, { { 1, "effort" }, { 260, "happy", "boing!" }, { 260 + 2 * t + 900, "dizzy" }, { 260 + 2 * t + 2200, "normal" } }, {
        after = { "I touched the sky.", "the ceiling is a lie.", "...did I miss anything?" },
    })
    return "boing"
end

-- Idle fidgets between antics: short, so they cost little.
def("glance", { pupil = { translate = kf { { T(0, 0) }, { T(4, 1), 120 }, { T(4, 1), 900 }, { T(0, 0), 160 } } } })
def("look_up", {
    pupil = { translate = kf { { T(0, 0) }, { T(-1, -4), 160 }, { T(-1, -4), 900 }, { T(0, 0), 200 } } },
    spin = { rotate = kf { { 0 }, { -4, 200 }, { -4, 860 }, { 0, 200 } } },
})
def("shuffle", {
    foot_l = { translate = kf { { T(0, 0) }, { T(-2, -4), 120 }, { T(0, 0), 120 }, { T(0, 0), 240 }, { T(-2, -4), 120 }, { T(0, 0), 120 } } },
    foot_r = { translate = kf { { T(0, 0) }, { T(0, 0), 240 }, { T(2, -4), 120 }, { T(0, 0), 120 } } },
    spin = { rotate = kf { { 0 }, { 3, 240 }, { -3, 240 }, { 0, 240 } } },
})
def("sigh", { act = { scale = kf { { REST_SCALE }, { T(0.97, 1.05), 700, "in_out_sine" }, { T(1.03, 0.97), 800, "in_out_sine" }, { REST_SCALE, 500, "in_out_sine" } } } })
def("blink_twice", { pupil = { translate = kf { { T(0, 0) }, { T(0, 0), 420 } } } }, { { 1, "sleep" }, { 90, "normal" }, { 220, "sleep" }, { 310, "normal" } })
def("preen", {
    arm_l = { rotate = kf { { 8 }, { 40, 140 }, { 10, 140 }, { 40, 140 }, { 8, 160 } } },
    spin = { rotate = kf { { 0 }, { -5, 200 }, { -5, 300 }, { 0, 220 } } },
})

local POOL = {
    "hop", "double_take", "spin", "sneeze", "sleep", "jelly", "stretch", "shimmy", "faceplant", "wave", "eye_roll", "peek",
    "waddle", "belly_slide", "flap", "slip", "foot_tap", "look_around", "dance", "backflip", "bow", "shiver", "hiccup",
    "moonwalk", "snack", "love", "zoomies", "ponder", "tada", "squats", "boing", "sing",
}

-- Playing an antic -------------------------------------------------------------------------------

local LINES = {
    "is it fish o'clock?", "I've seen things.", "don't look at me", "*honk*", "who moved my iceberg",
    "I was promised herring.", "it's not a tuxedo.", "nobody saw that.", "my feet are cold.",
    "I demand a smaller ocean.", "waddle waddle", "have you seen Gary?", "I am 40% fish.",
    "the cursor looks edible", "this is my screen now", "I'm not lost, I'm exploring",
    "ice to meet you", "flippers are not hands", "tell no one", "do penguins get tabs?",
    "just passing through", "I could go for a sardine", "meetings could be emails", "brb, snacks",
    "I'm just a little guy", "what does this button do?", "squawk.", "I saw a bird once",
    "cold feet, warm heart", "sliding is my cardio", "no, I won't carry your luggage",
    "is this a good iceberg?", "where is everyone?", "your windows look cozy",
    "have you tried turning the ocean off?", "this desktop needs more snow", "I do my own stunts",
    "reply-all was a mistake", "per my last honk", "that deadline looks fishy",
    "your wallpaper has no fish in it", "I'm on a seafood diet.", "is the cloud made of snow?",
    "a penguin's work is never done", "I identify as a small iceberg", "don't mind me, just loitering",
    "who's a good bird? me.", "I've been waiting all day for this", "are these pixels heated?",
    "how many tabs is too many? asking for a friend", "Antarctica called. I didn't pick up.",
    "flap flap. nothing. as usual.", "I have opinions about krill", "do you ever just... waddle?",
    "this screen is 90% not ocean", "I'm small, but I'm loud.",
}
local POKE_LINES = { "hehe", "that tickles!", "boop", "hey!", "eep", "again!", "ok ok ok", "wheee" }

-- Speech --------------------------------------------------------------------------------------------

-- Each line gets a fresh bubble id, so a new line pops in while the old one shrinks away.
local bubble_timer, last_line, lines_said = nil, nil, 0
local function speak(line)
    if bubble_timer then bubble_timer:cancel() end
    lines_said = lines_said + 1
    say:set(line)
    bubble_on:set(true)
    -- Long enough to read: 0.9 s plus 60 ms a character.
    bubble_timer = timer(clamp(900 + 60 * #line, 1400, 4500), function()
        bubble_timer = nil
        bubble_on:set(false)
    end)
end

local function chatter()
    local line
    repeat line = LINES[math.random(#LINES)] until line ~= last_line
    last_line = line
    speak(line)
end

-- Reload clears every timer, so a visit cut short would leave Pip, a bubble or a grab on screen for
-- good: each evaluation starts hidden.
local function reset()
    present:set(false)
    rest:set(false)
    grab:set(false)
    bubble_on:set(false)
    asleep:set(false)
    antic:set("")
    mood:set("normal")
    phys:set("drag")
    tilt:set(0)
    squish:set(T(1, 1))
    air:set(false)
end
reset()

-- Throw: a projectile under gravity, played as keyframes -------------------------------------------

local THROW_MAX = 3200 -- px/s, the fastest flick it keeps
local WALL_KEEP = 0.5 -- share of the speed kept off a side wall
local BOUNCE_KEEP = 0.12 -- share of the fall's energy bounced back up
local SLIDE = 0.12 -- s of its landing speed it slides on
local TURN_SPEED = 1600 -- px/s of sideways flick per somersault
local SQUASH_MS = 70


-- Keyframes per axis for a release at (x, y) with velocity (vx, vy), its tilt `turn` at release.
local function flight_path(x, y, vx, vy, turn, s)
    local floor, right = floor_y(s), math.max(EDGE, s.width - W - EDGE)
    vx, vy = clamp(vx, -THROW_MAX, THROW_MAX), clamp(vy, -THROW_MAX, THROW_MAX)

    local ys, t_air, impact = { T(0, y) }, 0, 0
    if vy < 0 then
        -- Up to an apex that stays on screen.
        vy = math.max(vy, -math.sqrt(2 * GRAVITY * math.max(0, y - EDGE)))
        local t = -vy / GRAVITY
        y = y - vy * vy / (2 * GRAVITY)
        ys[#ys + 1] = { value = T(0, y), duration = ms(t), easing = arc(2) }
        t_air, vy = t, 0
    end
    local h = floor - y
    if h > 1 then
        local t = (math.sqrt(vy * vy + 2 * GRAVITY * h) - vy) / GRAVITY
        ys[#ys + 1] = { value = T(0, floor), duration = ms(t), easing = arc(vy * t / h) }
        t_air, impact = t_air + t, vy + GRAVITY * t
    else
        -- Let go below the floor: it steps back up.
        ys[#ys + 1] = { value = T(0, floor), duration = 160, easing = "out_back" }
        t_air = t_air + 0.16
    end
    local t_after = 0.25
    local hop = math.min(60, BOUNCE_KEEP * impact * impact / (2 * GRAVITY))
    if hop >= 4 then
        local t = math.sqrt(2 * hop / GRAVITY)
        ys[#ys + 1] = { value = T(0, floor), duration = SQUASH_MS }
        ys[#ys + 1] = { value = T(0, floor - hop), duration = ms(t), easing = arc(2) }
        ys[#ys + 1] = { value = T(0, floor), duration = ms(t), easing = arc(0) }
        t_after = SQUASH_MS / 1000 + 2 * t
    end

    -- Sideways at a constant speed, off the walls, then a short slide.
    local xs, v, t = { T(x, 0) }, vx, 0
    for _ = 1, 8 do
        if t >= t_air then break end
        local wall = v > 0 and right or v < 0 and EDGE or nil
        local hit = wall and (wall - x) / v
        if hit and hit <= 0 then
            v = -v * WALL_KEEP -- let go past that wall: back it comes
        elseif hit and t + hit < t_air then
            x, t, v = wall, t + hit, -v * WALL_KEEP
            xs[#xs + 1] = { value = T(x, 0), duration = ms(hit), easing = "linear" }
        else
            x = x + v * (t_air - t)
            xs[#xs + 1] = { value = T(x, 0), duration = ms(t_air - t), easing = "linear" }
            t = t_air
        end
    end
    local x_end = clamp(x + v * SLIDE, EDGE, right)
    xs[#xs + 1] = { value = T(x_end, 0), duration = ms(t_after), easing = "out_quad" }

    -- A hard sideways flick somersaults it, upright again at touchdown.
    local turns = math.min(2, math.floor(math.abs(vx) / TURN_SPEED))
    local rs = { turn }
    if turns > 0 and t_air > 0.3 then
        rs[2] = { value = (vx > 0 and 360 or -360) * turns, duration = ms(t_air), easing = "in_out_sine" }
        rs[3] = { value = 0, duration = 0 }
    else
        rs[2] = { value = 0, duration = 260, easing = "out_back" }
    end

    return {
        motion = {
            x = { duration = 100, keyframes = xs },
            y = { duration = 100, keyframes = ys },
            rotate = { duration = 100, keyframes = rs },
        },
        rest = { x = x_end, y = floor },
        contact = ms(t_air),
        total = ms(t_air + t_after),
        impact = impact,
        turns = turns,
    }
end

-- Throws from (x, y); `landed(path)` runs once it has settled.
local function throw(x, y, vx, vy, turn, landed)
    local f = flight_path(x, y, vx, vy, turn, screen:get())
    flight:set(f.motion)
    phys:set("throw")
    rest:set(f.rest)
    air:set(true)
    in_flight(f.contact, function()
        air:set(false)
        squish:set(T(1.3, 0.72))
        in_flight(SQUASH_MS + 60, function() squish:set(T(0.92, 1.1)) end)
        in_flight(SQUASH_MS + 240, function() squish:set(T(1, 1)) end)
    end)
    in_flight(f.total, function()
        phys:set("fall")
        if landed then landed(f) end
    end)
end

-- A visit: appear, one to three antics, leave ------------------------------------------------------

local last
local out, leaving, left, on_done = false, false, 0, nil

local next_step, leave, schedule_visit

local IDLE = { "glance", "shuffle", "sigh", "blink_twice", "look_up", "preen" }
local BEAT_MS = 450 -- the pause before a punchline
local plays = 0 -- each run's props are new nodes, so their keyframes start over

-- Sets the antic and runs its script. The same keyframes restart only after a pass without them.
local function start(name)
    plays = plays + 1
    if antic:get() == name then
        antic:set("")
        later(1, function() antic:set(name) end)
    else
        antic:set(name)
    end
    for _, s in ipairs(ANTICS[name].script) do
        later(s[1], function()
            if s[2] then mood:set(s[2]) end
            if s[3] then speak(s[3]) end
        end)
    end
end

local function play(name)
    cancel_pending()
    local a = ANTICS[name]
    start(name)
    later(a.dur, function()
        antic:set("")
        if name == "sleep" then
            asleep:set(true)
            mood:set("sleep")
            -- Asleep until poked, or 25 s, then it tucks itself away.
            later(25000, function()
                asleep:set(false)
                mood:set("normal")
                leave()
            end)
            return
        end
        mood:set("normal")
        local f = on_done
        on_done = nil
        if f then return f() end
        if a.after and math.random() < 0.6 then later(BEAT_MS, function() speak(a.after[math.random(#a.after)]) end) end
        next_step()
    end)
end

-- A small idle motion between antics; it leaves the plan alone.
local function fidget()
    if antic:get() ~= "" or asleep:get() or grab:get() then return end
    local name = IDLE[math.random(#IDLE)]
    start(name)
    later(ANTICS[name].dur, function()
        if antic:get() ~= name then return end
        antic:set("")
        mood:set("normal")
    end)
end

-- Antics built when picked, for where Pip stands.
local CHOOSE = {
    belly_slide = function()
        local s, r = screen:get(), rest:get()
        return r.x > s.width / 2 and "belly_slide_l" or "belly_slide_r"
    end,
    boing = function() return boing(rest:get().y) end,
}

-- An antic that says its own line skips the chatter, so the two do not talk over each other.
local function speaks(name)
    for _, s in ipairs(ANTICS[name].script) do
        if s[3] then return true end
    end
    return false
end

function next_step()
    if not out or leaving or grab:get() then return end
    if left <= 0 then return later(math.random(1500, 3500), leave) end
    left = left - 1
    local gap = math.random(GAP_MIN, GAP_MAX)
    if math.random() < 0.75 then later(gap * 0.45, fidget) end
    later(gap, function()
        local pick
        repeat pick = POOL[math.random(#POOL)] until pick ~= last
        last = pick
        pick = CHOOSE[pick] and CHOOSE[pick]() or pick
        if not bubble_on:get() and not speaks(pick) and math.random() < 0.35 then chatter() end
        play(pick)
    end)
end

-- Waddles to `x` along the floor at walking pace, the steps timed to the distance.
local function walk_to(x, done)
    local r = rest:get()
    local steps = math.max(2, math.floor(math.abs(x - r.x) / WALK_SPEED * 1000 / STEP_MS + 0.5))
    def("walk", gait(steps, STEP_MS, 8, 0))
    walk_ms:set(steps * STEP_MS)
    phys:set("walk")
    rest:set({ x = x, y = r.y })
    play("walk")
    on_done = done
end

local function hide()
    cancel_pending()
    cancel_flight()
    out, leaving, on_done = false, false, nil
    reset()
    schedule_visit()
end

function leave()
    if grab:get() or not out then return end
    leaving = true
    local s, r = screen:get(), rest:get()
    if math.random() < 0.5 and r.y <= floor_y(s) + 2 then
        walk_to(r.x < s.width / 2 and -W - 20 or s.width + 20, hide)
    else
        play("wave")
        on_done = function()
            phys:set("coast")
            rest:set({ x = r.x, y = s.height + 10 })
            later(1100, hide)
        end
    end
end

local function arrived()
    if math.random() < 0.5 then chatter() end
    next_step()
end

-- The panel is mapped by now; its size is known once it has laid out on the picked output.
local function enter(tries)
    local s = screen:get()
    if not s or s.width < 200 then
        if tries < 10 then return later(50, function() enter(tries + 1) end) end
        return hide()
    end
    local fy = floor_y(s)
    local how = math.random()
    if how < 0.4 then
        -- Waddle in from a side, placed off-screen first.
        local from_left = math.random() < 0.5
        local tx = from_left and math.random(80, 400) or s.width - W - math.random(80, 400)
        phys:set("drag")
        rest:set({ x = from_left and -W - 20 or s.width + 20, y = fy })
        later(60, function() walk_to(tx, arrived) end)
    elseif how < 0.8 then
        -- Peek over the bottom edge, look around, then climb up.
        local x = math.random(EDGE, s.width - W - EDGE)
        phys:set("coast")
        rest:set({ x = x, y = s.height + 10 })
        later(60, function()
            rest:set({ x = x, y = s.height - 84 })
            later(700, function()
                play("double_take")
                on_done = function()
                    phys:set("fall")
                    rest:set({ x = x, y = fy })
                    later(900, arrived)
                end
            end)
        end)
    else
        -- Drop in from above the top edge.
        local x, y = math.random(EDGE, s.width - W - EDGE), -H - 40
        phys:set("drag")
        rest:set({ x = x, y = y })
        later(60, function()
            mood:set("surprised")
            throw(x, y, 0, 0, 0, function() later(400, arrived) end)
        end)
    end
end

local function appear()
    out, leaving, left, on_done = true, false, math.random(1, 3), nil
    present:set(true)
    later(120, function() enter(1) end)
end

function schedule_visit() timer(math.random(VISIT_MIN, VISIT_MAX), appear) end

-- `mantle set mascot_present true|false` starts or ends a visit.
present:on_change(function(on)
    if on and not out then
        appear()
    elseif not on and out then
        hide()
    end
end)

-- Stops the running antic and, mid-walk, plants it where it is drawn.
local function stop(local_pt)
    cancel_pending()
    antic:set("")
    leaving, on_done = false, nil
    local p = phys:get()
    if p == "walk" or p == "coast" then
        phys:set("drag")
        rest:set(drawn_at(local_pt))
    end
end

-- Grab and throw ------------------------------------------------------------------------------------

local THROWN_LINES = {
    "I can fly!", "again! again!", "10/10, would fly again", "my lawyer will hear about this",
    "was that necessary?", "I regret nothing", "stuck the landing.", "penguins can't fly. I checked.",
}

local moved = false

-- Down after a throw: it shakes it off, may comment, and leaves a few seconds later.
local function thrown(f)
    local woozy = f.turns > 0 or f.impact > 3000
    mood:set(woozy and "dizzy" or "normal")
    later(woozy and 1400 or 1, function() mood:set("normal") end)
    if math.random() < 0.6 then later(woozy and 900 or 250, function() speak(THROWN_LINES[math.random(#THROWN_LINES)]) end) end
    later(math.random(4000, 8000), leave)
end

local function drag(_, local_pt, phase, _, velocity)
    local p = at:get()
    if phase == "start" then
        moved = false
        if not p then return end
        stop()
        cancel_flight()
        out = true
        local r = drawn_at(local_pt)
        local was_asleep = asleep:get()
        asleep:set(false)
        air:set(false)
        phys:set("drag")
        grab:set({ px = p.x, py = p.y, ox = r.x, oy = r.y })
        squish:set(T(0.94, 1.08))
        mood:set(was_asleep and "surprised" or "normal")
        return
    end
    local g = grab:get()
    if not g then return end
    if phase == "move" then
        if p and not moved and math.abs(p.x - g.px) + math.abs(p.y - g.py) > 4 then
            moved = true
            mood:set("surprised")
            squish:set(T(0.88, 1.16)) -- stretched by the scruff of the neck
            speak("put me down!!")
        end
        tilt:set(clamp(velocity.x / 90, -28, 28))
        return
    end
    -- End. A press without motion is a click, and on_click follows.
    local here = p and { x = g.ox + p.x - g.px, y = g.oy + p.y - g.py } or { x = g.ox, y = g.oy }
    local turn = tilt:get()
    grab:set(false)
    tilt:set(0)
    squish:set(T(1, 1))
    if moved then
        mood:set("surprised")
        throw(here.x, here.y, velocity.x, velocity.y, turn, thrown)
    elseif here.y < floor_y(screen:get()) - 2 then
        throw(here.x, here.y, 0, 0, turn) -- caught mid-air and let go: it drops
    else
        rest:set(here)
        mood:set("normal")
    end
end

-- Clicks: left giggles (or wakes it), four quick ones make it cross, right chats, double spins ------

local pokes, poke_reset = 0, nil
local function poke(_, button, local_pt)
    if moved then
        moved = false
        return
    end
    stop(local_pt)
    left = 0
    if button == "right" then
        asleep:set(false)
        chatter()
        return play("hop")
    end
    pokes = pokes + 1
    if poke_reset then poke_reset:cancel() end
    poke_reset = timer(3000, function() pokes = 0 end)
    if pokes >= 4 then
        pokes = 0
        asleep:set(false)
        speak("STOP POKING ME")
        return play("jelly")
    end
    if asleep:get() then
        asleep:set(false)
        speak("I was dreaming of fish!")
        return play("wake")
    end
    if math.random() < 0.5 then speak(POKE_LINES[math.random(#POKE_LINES)]) end
    play("giggle")
end

local function spin_up(_, _, local_pt)
    asleep:set(false)
    stop(local_pt)
    left = 0
    speak("wheee!")
    play("spin")
end

-- Scrolling over it tickles; only while it is idle, so a flick does not restart the antic.
local function tickle()
    if antic:get() ~= "" or asleep:get() then return end
    left = 0
    speak("hehe, stop!")
    play("jelly")
end

-- Look: pupils follow the pointer -----------------------------------------------------------------

local look = computed({ at, pos }, function(p, q)
    if not p then return T(0, 0) end
    local dx, dy = p.x - (q.x + 52), p.y - (q.y + 70)
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return T(0, 0) end
    local reach = math.min(3.5, len / 30)
    return T(dx / len * reach, dy / len * reach * 0.8)
end)

-- Moods ---------------------------------------------------------------------------------------

-- top/bot: eyelid height in px of the 20 px eye. es/ps: eye and pupil scale.
-- br/by: brow tilt (inner end down, degrees) and lift (px, up is negative).
local MOODS = {
    normal = { top = 0, bot = 0, es = 1, ps = 1, mouth = "smile", cheek = 0.5, br = 0, by = 0 },
    surprised = { top = 0, bot = 0, es = 1.25, ps = 0.55, mouth = "o", cheek = 0.3, br = -6, by = -5 },
    happy = { top = 0, bot = 13, es = 1, ps = 1, mouth = "grin", cheek = 1, br = -4, by = -3 },
    sleep = { top = 20, bot = 0, es = 1, ps = 1, mouth = "flat", cheek = 0.4, br = 0, by = 2 },
    sleepy = { top = 10, bot = 0, es = 1, ps = 1, mouth = "flat", cheek = 0.4, br = -8, by = 1 },
    yawn = { top = 15, bot = 0, es = 1, ps = 1, mouth = "yawn", cheek = 0.5, br = -6, by = 0 },
    sneeze = { top = 20, bot = 0, es = 1, ps = 1, mouth = "sneeze", cheek = 0.5, br = 10, by = 3 },
    dizzy = { top = 0, bot = 0, es = 1.1, ps = 0.4, mouth = "wobble", cheek = 0.5, br = -12, by = -1 },
    bored = { top = 8, bot = 0, es = 1, ps = 1, mouth = "flat", cheek = 0.3, br = 4, by = 3 },
    cold = { top = 5, bot = 0, es = 0.92, ps = 1, mouth = "wobble", cheek = 0.1, br = -14, by = -2 },
    think = { top = 7, bot = 0, es = 1, ps = 0.85, mouth = "flat", cheek = 0.4, br = 8, by = 1 },
    effort = { top = 9, bot = 5, es = 1, ps = 1, mouth = "flat", cheek = 1, br = 16, by = 3 },
    smug = { top = 9, bot = 0, es = 1, ps = 1, mouth = "grin", cheek = 0.8, br = 10, by = 1 },
    sing = { top = 0, bot = 13, es = 1, ps = 1, mouth = "o", cheek = 0.9, br = -6, by = -3 },
}

-- A mouth is always M, Q, Q, Z so one shape morphs into the next point by point.
local function mouth(x0, x1, y0, top, bot)
    return {
        { op = "M", points = { x0, y0 } },
        { op = "Q", points = { (x0 + x1) / 2, top, x1, y0 } },
        { op = "Q", points = { (x0 + x1) / 2, bot, x0, y0 } },
        { op = "Z", points = {} },
    }
end
local MOUTHS = {
    smile = mouth(6, 22, 6, 2, 25),
    grin = mouth(2, 26, 4, 7, 36),
    o = mouth(9, 19, 11, -3, 23),
    flat = mouth(7, 21, 10, 9, 12),
    yawn = mouth(6, 22, 6, -6, 38),
    sneeze = mouth(9, 19, 12, 4, 17),
    wobble = mouth(5, 23, 13, 4, 12),
}

local function of(key) return mood:map(function(m) return MOODS[m][key] end) end
local lid_top, lid_bot, eye_scale, pupil_scale, cheek = of("top"), of("bot"), of("es"), of("ps"), of("cheek")
local EYE_H = 30
local LID_PX = EYE_H / 20 -- mood lids are in px of a 20 px eye
local mouth_shape = mood:map(function(m) return MOUTHS[MOODS[m].mouth] end)

-- Antic tracks: a layer's base motion, overridden by the running antic's keyframes ------------------

local function track(part, base)
    return antic:map(function(a)
        local t = ANTICS[a] and ANTICS[a].parts[part]
        if not t then return base end
        local m = {}
        for k, v in pairs(base) do m[k] = v end
        for k, v in pairs(t) do m[k] = v end
        return m
    end)
end

local SPRING = function(k, d) return { spring = { stiffness = k, damping = d } } end

-- Pieces ----------------------------------------------------------------------------------------

-- One blink every 3.8 s: a lid slides down over the patch and back. The hold asks for no frames.
local BLINK = {
    duration = 100,
    loops = "infinite",
    keyframes = {
        T(0, -EYE_H - 2),
        { value = T(0, -EYE_H - 2), duration = 3600 },
        { value = T(0, 0), duration = 70 },
        { value = T(0, -EYE_H - 2), duration = 120 },
    },
}

local pupil_anim = track("pupil", { translate = SPRING(260, 20), scale = SPRING(400, 24) })

local function lid_edge() return rect { width = "fill", height = 2.5, align_v = "end", background = DARK } end

-- A big white patch with a small black pupil looking slightly inward, as on Tux. `side`: 1 left, -1 right.
local function eye(side)
    return rect {
        width = 24,
        height = EYE_H,
        radius = 999,
        clip = "rounded",
        background = { gradient = "radial", stops = { { 0, PATCH }, { 0.7, "#F2F3F6" }, { 1, "#BFC2CC" } } },
        scale = eye_scale:map(function(s) return T(s, s) end),
        animate = { scale = SPRING(500, 16) },
        children = {
            rect {
                width = 9,
                height = 11,
                radius = 999,
                background = DARK,
                align_h = "center",
                align_v = "center",
                margin = side > 0 and { left = 7, top = 4 } or { right = 7, top = 4 },
                translate = look,
                scale = pupil_scale:map(function(s) return T(s, s) end),
                animate = pupil_anim,
                children = { rect { width = 3, height = 3, radius = 2, background = "#FFFFFF", margin = { top = 2, left = 2 } } },
            },
            rect {
                width = "fill",
                height = lid_top:map(function(h) return h * LID_PX end),
                background = LID,
                animate = { height = 110 },
                children = { lid_edge() },
            },
            rect {
                width = 30,
                height = lid_bot:map(function(h) return h * LID_PX end),
                radius = 999,
                background = LID,
                border_width = 2.5,
                border_color = DARK,
                align_h = "center",
                align_v = "end",
                margin = { bottom = -2 },
                animate = { height = 110 },
            },
            rect { width = "fill", height = EYE_H, background = LID, translate = T(0, -EYE_H - 2), animate = { translate = BLINK }, children = { lid_edge() } },
        },
    }
end

-- A heavy brow over each patch; moods tilt and lift it.
local function brow(side)
    return path {
        width = 26,
        height = 10,
        origin = { x = 0.5, y = 1 },
        stroke = DARK,
        stroke_width = 4,
        stroke_cap = "round",
        commands = { { op = "M", points = { 3, 8 } }, { op = "Q", points = { 13, 0, 23, 8 } } },
        rotate = mood:map(function(m) return side * MOODS[m].br end),
        translate = mood:map(function(m) return T(0, MOODS[m].by) end),
        animate = { rotate = SPRING(300, 18), translate = SPRING(300, 18) },
    }
end

-- A short flipper angled out and down from its shoulder, with a grey sheen; antics turn it from there.
local function arm(side, part)
    return rect {
        width = 14,
        height = 36,
        origin = { x = 0.5, y = 0.1 },
        rotate = side * 28,
        children = { rect {
            width = 14,
            height = 36,
            radius = { top_left = 7, top_right = 7, bottom_right = 9, bottom_left = 9 },
            origin = { x = 0.5, y = 0.1 },
            background = { gradient = "linear", angle = side > 0 and 100 or 260, stops = { { 0, "#6A6A74" }, { 0.45, "#1A1A20" }, { 1, BODY_BOT } } },
            rotate = side * 8,
            animate = track(part, {}),
        } },
    }
end

local function foot(swing, part)
    return rect {
        width = 39,
        height = 16,
        radius = 999,
        background = { gradient = "linear", angle = 180, stops = { { 0, FOOT_TOP }, { 1, FOOT_BOT } } },
        children = { rect { width = 24, height = 7, radius = 999, align_h = "center", margin = { top = 2 }, background = "#FFE680" } },
        origin = { x = 0.5, y = 0 },
        rotate = tilt:map(function(t) return swing * t * 0.9 end),
        translate = grab:map(function(g) return T(0, g and 5 or 0) end),
        animate = track(part, { rotate = SPRING(120, 5), translate = SPRING(300, 14) }),
    }
end

local function cheek_dot()
    return rect {
        width = 11,
        height = 8,
        radius = 4,
        background = "#FF8FA0",
        opacity = cheek,
        animate = { opacity = 200 },
    }
end

local function circle(cx, cy, r) return { left = cx - r, top = cy - r, right = cx + r, bottom = cy + r, radius = 999 } end

-- Tux-shaped: a glossy black egg, wider at the bottom, a big white belly, two white eye patches that
-- touch under heavy brows, and a chunky gold beak over them.
local body = rect {
    width = 88,
    height = 92,
    align_h = "center",
    align_v = "end",
    margin = { bottom = 9 },
    shape = { melt = 16, parts = { circle(44, 34, 32), { left = 0, top = 32, right = 88, bottom = 92, radius = 44 } } },
    background = { gradient = "linear", angle = 160, stops = { { 0, BODY_TOP }, { 0.55, "#141418" }, { 1, BODY_BOT } } },
    shadows = grab:map(function(g)
        return { { color = "#00000060", blur = g and 30 or 14, offset = { y = g and 16 or 6 } } }
    end),
    animate = { shadows = 200 },
    children = {
        -- The gloss on the crown, top left.
        rect { width = 46, height = 32, margin = { top = 2, left = 10 }, background = { gradient = "radial", stops = { { 0, "#FFFFFFA0" }, { 1, "#FFFFFF00" } } } },
        rect {
            width = 66,
            height = 50,
            radius = 999,
            align_h = "center",
            align_v = "end",
            margin = { bottom = 3 },
            background = { gradient = "radial", stops = { { 0, "#FFFFFF" }, { 0.75, "#F1F1F3" }, { 1, "#C8C9D0" } } },
        },
        row { align_h = "center", margin = { top = 14 }, spacing = -1, children = { eye(1), eye(-1) } },
        row { align_h = "center", margin = { top = 7 }, spacing = -2, children = { brow(1), brow(-1) } },
        row { align_h = "center", margin = { top = 48 }, spacing = 30, children = { cheek_dot(), cheek_dot() } },
        path {
            width = 28,
            height = 24,
            align_h = "center",
            margin = { top = 35 },
            origin = { x = 0.5, y = 0 },
            scale = 1.12,
            fill = { gradient = "linear", angle = 180, stops = { { 0, "#FFE36A" }, { 0.5, BEAK }, { 1, "#D9940A" } } },
            stroke = BEAK_D,
            stroke_width = 1.5,
            stroke_join = "round",
            commands = mouth_shape,
            animate = { commands = 120 },
        },
    },
}

local function puff_dot(dx, dy, size)
    return rect { width = size, height = size, radius = 999, background = "#FFFFFFE6", translate = T(dx, dy) }
end

local puff = row {
    align_h = "end",
    margin = { top = 58, right = -10 },
    opacity = 0,
    scale = 0.3,
    translate = T(0, 0),
    hittable = false,
    animate = track("puff", {}),
    children = { puff_dot(0, 0, 11), puff_dot(-2, -6, 8), puff_dot(-4, 3, 7) },
}

local function zzz(content, size, wait)
    return text {
        content = content,
        font_size = size,
        font_weight = 700,
        foreground = "#9CC8FF",
        align_h = "end",
        margin = { top = 18, right = 6 },
        opacity = 0,
        hittable = false,
        animate = {
            translate = { duration = 2400, easing = "out_sine", loops = "infinite", delay = wait, keyframes = { T(0, 0), T(14, -26) } },
            opacity = { duration = 2400, loops = "infinite", delay = wait, keyframes = { 0, 1, 0 } },
        },
    }
end

-- The z's, stars and "!" are built each time they show: a finished keyframe run never replays, and a
-- hidden one freezes where it was.
local sleeping = rect {
    width = W,
    height = H,
    hittable = false,
    children = asleep:map(function(a) return a and { zzz("z", 14, 0), zzz("Z", 18, 800), zzz("Z", 22, 1600) } or {} end),
}

local alert = rect {
    width = W,
    height = H,
    hittable = false,
    children = mood:map(function(m)
        if m ~= "surprised" then return {} end
        return { text {
            content = "!",
            font_size = 24,
            font_weight = 800,
            foreground = "#FF5C5C",
            align_h = "center",
            opacity = 1,
            scale = 1,
            animate = { scale = { spring = { stiffness = 600, damping = 12 }, from = 0.3 }, opacity = { duration = 100, from = 0 } },
        } }
    end),
}

local function star(delay_ms, radius)
    return rect {
        width = 9,
        height = 9,
        rotate = 45,
        background = "#FFE066",
        hittable = false,
        translate = T(0, 0),
        animate = {
            translate = { duration = 700, easing = "linear", loops = "infinite", delay = delay_ms, keyframes = {
                T(-radius, 0), T(0, -radius * 0.45), T(radius, 0), T(0, radius * 0.45), T(-radius, 0),
            } },
        },
    }
end

local stars = rect {
    width = 40,
    height = 20,
    align_h = "center",
    margin = { top = 8 },
    hittable = false,
    children = mood:map(function(m) return m == "dizzy" and { star(0, 26), star(233, 26), star(466, 26) } or {} end),
}

-- The mascot: spin (about the centre) > act (about the feet) > squash (grab and landing) -----------

local ground = rect {
    width = 74,
    height = 12,
    radius = 999,
    align_h = "center",
    align_v = "end",
    background = "#00000040",
    opacity = computed({ grab, air }, function(g, a) return (g or a) and 0 or 1 end),
    scale = T(1, 1),
    animate = track("ground", { opacity = 200 }),
}

local squash = rect {
    width = W,
    height = H,
    origin = { x = 0.5, y = 1 },
    scale = squish,
    animate = { scale = SPRING(420, 15) },
    on_drag = drag,
    on_click = poke,
    on_double_click = spin_up,
    on_wheel = tickle,
    children = {
        row { width = W, height = 40, margin = { top = 54 }, padding = { left = 4, right = 4 }, children = {
            arm(1, "arm_l"),
            rect { width = "fill", height = 1 },
            arm(-1, "arm_r"),
        } },
        body,
        -- Big flat feet in front of the belly, as on Tux.
        rect { align_h = "center", align_v = "end", margin = { bottom = 1 }, width = 84, height = 17, children = {
            row { spacing = 6, children = { foot(1, "foot_l"), foot(-1, "foot_r") } },
        } },
        -- Whatever the running antic brings along: a fish, a heart, notes.
        rect {
            width = W,
            height = H,
            hittable = false,
            children = antic:map(function(a)
                local d = ANTICS[a]
                return d and d.props and d.props(plays) or {}
            end),
        },
        puff,
        stars,
        alert,
        sleeping,
    },
}

-- Resting pose of the asleep mascot is the sleep antic's last frame.
local act = rect {
    width = W,
    height = H,
    origin = { x = 0.5, y = 1 },
    translate = asleep:map(function(a) return T(0, a and 6 or 0) end),
    scale = asleep:map(function(a) return a and T(1.04, 0.92) or T(1, 1) end),
    rotate = 0,
    animate = track("act", { translate = SPRING(300, 18), scale = SPRING(300, 18) }),
    children = { squash },
}

local spin = rect {
    width = W,
    height = H,
    rotate = 0,
    animate = track("spin", {}),
    children = { act },
}

-- Speech bubble: above the head, or below it near the top edge; kept on screen, its tail at Pip -----

local BUBBLE_H = 26
local ROOM = 40 -- above and below the box, for the bubble and its tail
local SPEECH_W = 480 -- wider than any line, so the bubble sizes to its text without wrapping
local bubble_box = geometry("mascot_bubble")

-- The bubble's width is measured by layout, one pass after a new line appears.
local shift = computed({ pos, screen, bubble_box }, function(p, sc, b)
    if not (sc and b) then return 0 end
    local left = p.x + (W - b.width) / 2
    return clamp(left, 6, math.max(6, sc.width - b.width - 6)) - left
end)
local tail_x = computed({ shift, bubble_box }, function(d, b)
    local reach = math.max(0, (b and b.width or 0) / 2 - 14)
    return T(clamp(-d, -reach, reach), 0)
end)
local below = pos:map(function(p) return p.y < ROOM end)

local function bubble_of(line, under, n)
    return rect {
        id = "bubble" .. n,
        align_h = "center",
        align_v = under and "end" or "start",
        hittable = false,
        origin = { x = 0.5, y = under and 0 or 1 },
        scale = 1,
        opacity = 1,
        translate = shift:map(function(d) return T(d, 0) end),
        animate = {
            scale = { spring = { stiffness = 500, damping = 14 }, from = 0.2 },
            opacity = { duration = 90, from = 0 },
            exit = { duration = 140, scale = 0.2, opacity = 0 },
        },
        children = {
            rect {
                width = 12,
                height = 12,
                rotate = 45,
                background = "#FFFFFF",
                align_h = "center",
                align_v = under and "start" or "end",
                margin = under and { top = 1 } or { bottom = 1 },
                translate = tail_x,
            },
            rect {
                geometry = bubble_box,
                height = BUBBLE_H,
                padding = { left = 12, right = 12 },
                margin = under and { top = 7 } or { bottom = 7 },
                radius = 13,
                background = "#FFFFFF",
                shadows = { { color = "#00000040", blur = 10, offset = { y = 3 } } },
                children = { text { content = line, font_size = 12, font_weight = 600, foreground = "#1F2431", align_v = "center" } },
            },
        },
    }
end

local speech = rect {
    width = SPEECH_W,
    height = H + 2 * ROOM,
    translate = T((W - SPEECH_W) / 2, -ROOM),
    hittable = false,
    children = computed({ bubble_on, say, below }, function(on, line, under)
        if not on then return {} end
        return { bubble_of(line, under, lines_said) }
    end),
}

-- Each axis and the tilt has its own entry, so a throw's rise, fall and drift each keep their curve.
local MOTION = {
    drag = { x = SPRING(520, 34), y = SPRING(520, 34), rotate = SPRING(260, 16) },
    coast = { x = SPRING(70, 15), y = SPRING(70, 15), rotate = SPRING(120, 8) },
    fall = { x = SPRING(260, 12), y = SPRING(260, 12), rotate = SPRING(200, 9) },
}
local motion = computed({ phys, flight, walk_ms }, function(p, f, walk)
    if p == "throw" then return f end
    if p == "walk" then return { x = { duration = walk, easing = "in_out_sine" }, y = MOTION.drag.y, rotate = MOTION.drag.rotate } end
    return MOTION[p]
end)

schedule_visit()

return {
    panel {
        id = "mascot",
        layer = "top",
        output = "active",
        anchor = { top = true, bottom = true, left = true, right = true },
        visible = present,
        child = rect {
            width = "fill",
            height = "fill",
            pointer = at,
            geometry = screen,
            children = {
                rect {
                    width = W,
                    height = H,
                    visible = rest:map(function(r) return r ~= false end),
                    translate = pos:map(function(p) return T(p.x, 0) end),
                    animate = motion:map(function(m) return { translate = m.x } end),
                    children = { rect {
                        width = W,
                        height = H,
                        translate = pos:map(function(p) return T(0, p.y) end),
                        animate = motion:map(function(m) return { translate = m.y } end),
                        children = {
                            ground,
                            rect {
                                width = W,
                                height = H,
                                rotate = tilt,
                                animate = motion:map(function(m) return { rotate = m.rotate } end),
                                children = { spin },
                            },
                            speech,
                        },
                    } },
                },
            },
        },
    },
}
