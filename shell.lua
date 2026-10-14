-- Pip: a desktop penguin with no function. Most of the time it is hidden below the screen edge or
-- off to the side; every 20-90 s it waddles in or peeks up, does one to three silly things, may say
-- something, and leaves. Grab and throw it while it is out; click it for a giggle, or to wake it.
-- Hidden, its panel is unmapped: nothing is drawn, animated or composited. Each visit maps it again on
-- the output the compositor picks.

fonts { "Noto Sans" }

local VISIT_MIN, VISIT_MAX = 20000, 90000 -- ms hidden between visits

math.randomseed(os.time())

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Size of the mascot's box, and the gap it keeps from the screen edge.
local W, H, EDGE, FLOOR_GAP = 104, 112, 8, 20

local BODY_TOP, BODY_BOT = "#566897", "#2C3656"
local PATCH = "#FFF9F3" -- face patch; the eyelids match it
local DARK, BELLY = "#10131A", "#ECEFF6"
local BEAK, BEAK_D = "#FF9E2C", "#D9701A"

-- State -----------------------------------------------------------------------------------------

local present = state("mascot_present", false) -- drawn at all
local say = state("mascot_say", "")
local bubble_on = state("mascot_bubble", false)
local rest = state("mascot_rest", false) -- false until placed on the floor
local grab = state("mascot_grab", false)
local tilt = state("mascot_tilt", 0)
local phys = state("mascot_phys", "drag") -- spring set: drag, coast, fall
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

-- Everything an antic or a landing arms goes here, so a grab can cancel it all.
local pending = {}
local function later(ms, fn) pending[#pending + 1] = timer(math.max(1, ms), fn) end
local function cancel_pending()
    for _, h in ipairs(pending) do h:cancel() end
    pending = {}
end

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

local ANTICS = {}
-- parts: layer name -> { property -> kf }. script: { { ms, mood } }. The run lasts as long as the
-- longest track, plus 80 ms of slack.
local function def(name, parts, script)
    local dur = 0
    for _, props in pairs(parts) do
        for _, entry in pairs(props) do dur = math.max(dur, TOTAL[entry]) end
    end
    ANTICS[name] = { parts = parts, script = script or {}, dur = dur + 80 }
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

-- Penguin antics. `walk` is played while the rest spring carries it along the floor.
local function wob(spec_len, step, amp)
    local r, y = { { 0 } }, { { T(0, 0) } }
    for i = 1, spec_len do
        r[#r + 1] = { (i % 2 == 0 and -amp or amp), step }
        y[#y + 1] = { T(0, i % 2 == 0 and 0 or -3), step }
    end
    r[#r + 1] = { 0, 160 }
    y[#y + 1] = { T(0, 0), 160 }
    return kf(r), kf(y)
end
do
    local r, y = wob(11, 200, 9)
    def("walk", { spin = { rotate = r }, act = { translate = y } })
    local r2, y2 = wob(6, 180, 11)
    local x = { { T(0, 0) } }
    for i = 1, 6 do x[#x + 1] = { T(i % 2 == 0 and -18 or 18, i % 2 == 0 and 0 or -3), 180 } end
    x[#x + 1] = { T(0, 0), 180 }
    def("waddle", { spin = { rotate = r2 }, act = { translate = kf(x) } }, { { 1, "happy" } })
end

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

local POOL = { "hop", "double_take", "spin", "sneeze", "sleep", "jelly", "stretch", "shimmy", "faceplant", "wave", "eye_roll", "peek", "waddle", "belly_slide", "flap", "slip" }

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
end
reset()

-- A visit: appear, one to three antics, leave ------------------------------------------------------

local last
local out, leaving, left, on_done = false, false, 0, nil

local next_step, leave, schedule_visit

local function play(name)
    cancel_pending()
    local a = ANTICS[name]
    if antic:get() == name then
        -- The same keyframes restart only after a pass without them.
        antic:set("")
        later(1, function() antic:set(name) end)
    else
        antic:set(name)
    end
    for _, s in ipairs(a.script) do
        later(s[1], function()
            mood:set(s[2])
            if s[3] then speak(s[3]) end
        end)
    end
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
        if f then f() else next_step() end
    end)
end

-- An antic that says its own line skips the chatter, so the two do not talk over each other.
local function speaks(name)
    for _, s in ipairs(ANTICS[name].script) do
        if s[3] then return true end
    end
    return false
end

function next_step()
    if not out or leaving or grab:get() then return end
    if left > 0 then
        left = left - 1
        later(math.random(2000, 6000), function()
            local pick
            repeat pick = POOL[math.random(#POOL)] until pick ~= last
            last = pick
            if pick == "belly_slide" then
                local s, r = screen:get(), rest:get()
                pick = (r and s and r.x > s.width / 2) and "belly_slide_l" or "belly_slide_r"
            end
            if not bubble_on:get() and not speaks(pick) and math.random() < 0.4 then chatter() end
            play(pick)
        end)
    else
        later(math.random(1500, 3500), leave)
    end
end

local function hide()
    cancel_pending()
    out, leaving, on_done = false, false, nil
    reset()
    schedule_visit()
end

function leave()
    if grab:get() or not out then return end
    leaving = true
    local s, r = screen:get(), rest:get()
    if math.random() < 0.5 and r.y <= floor_y(s) + 2 then
        phys:set("walk")
        rest:set({ x = r.x < s.width / 2 and -W - 20 or s.width + 20, y = r.y })
        play("walk")
        on_done = hide
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
    if math.random() < 0.5 then
        -- Waddle in from a side, placed off-screen first.
        local from_left = math.random() < 0.5
        local tx = from_left and math.random(80, 400) or s.width - W - math.random(80, 400)
        phys:set("walk")
        rest:set({ x = from_left and -W - 20 or s.width + 20, y = fy })
        later(60, function()
            rest:set({ x = tx, y = fy })
            play("walk")
            on_done = arrived
        end)
    else
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

-- Grab, throw, land ---------------------------------------------------------------------------------

local moved = false

local function land()
    squish:set(T(1.32, 0.68))
    later(130, function() squish:set(T(0.92, 1.1)) end)
    later(300, function() squish:set(T(1, 1)) end)
    later(700, function() mood:set("normal") end)
    -- Settled: it stays a few seconds, then leaves.
    later(math.random(4000, 8000), leave)
end

local function drag(_, local_pt, phase, _, velocity)
    local p = at:get()
    if phase == "start" then
        moved = false
        if not p then return end
        stop()
        out = true
        local r = drawn_at(local_pt)
        local was_asleep = asleep:get()
        asleep:set(false)
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
    -- End. A press without motion is a click; on_click follows.
    local here = p and { x = g.ox + p.x - g.px, y = g.oy + p.y - g.py } or { x = g.ox, y = g.oy }
    local s = screen:get()
    grab:set(false)
    tilt:set(0)
    if not moved then
        rest:set({ x = g.ox, y = g.oy })
        squish:set(T(1, 1))
        mood:set("normal")
        return
    end
    local x = clamp(here.x + velocity.x * 0.18, EDGE, math.max(EDGE, s.width - W - EDGE))
    local y = clamp(here.y + velocity.y * 0.12, EDGE, floor_y(s))
    squish:set(T(1, 1))
    mood:set("surprised")
    if floor_y(s) - y > 6 then
        -- Coast to the end of the throw on a soft spring, then fall.
        phys:set("coast")
        rest:set({ x = x, y = y })
        later(420, function()
            phys:set("fall")
            rest:set({ x = x, y = floor_y(s) })
            later(210, land)
        end)
    else
        phys:set("fall")
        rest:set({ x = x, y = floor_y(s) })
        later(210, land)
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
local MOODS = {
    normal = { top = 0, bot = 0, es = 1, ps = 1, mouth = "smile", cheek = 0.5 },
    surprised = { top = 0, bot = 0, es = 1.25, ps = 0.55, mouth = "o", cheek = 0.3 },
    happy = { top = 0, bot = 13, es = 1, ps = 1, mouth = "grin", cheek = 1 },
    sleep = { top = 20, bot = 0, es = 1, ps = 1, mouth = "flat", cheek = 0.4 },
    sleepy = { top = 10, bot = 0, es = 1, ps = 1, mouth = "flat", cheek = 0.4 },
    yawn = { top = 15, bot = 0, es = 1, ps = 1, mouth = "yawn", cheek = 0.5 },
    sneeze = { top = 20, bot = 0, es = 1, ps = 1, mouth = "sneeze", cheek = 0.5 },
    dizzy = { top = 0, bot = 0, es = 1.1, ps = 0.4, mouth = "wobble", cheek = 0.5 },
    bored = { top = 8, bot = 0, es = 1, ps = 1, mouth = "flat", cheek = 0.3 },
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
    smile = mouth(4, 24, 7, 11, 22),
    grin = mouth(2, 26, 4, 7, 36),
    o = mouth(9, 19, 11, -3, 23),
    flat = mouth(7, 21, 10, 9, 12),
    yawn = mouth(6, 22, 6, -6, 38),
    sneeze = mouth(9, 19, 12, 4, 17),
    wobble = mouth(5, 23, 13, 4, 12),
}

local function of(key) return mood:map(function(m) return MOODS[m][key] end) end
local lid_top, lid_bot, eye_scale, pupil_scale, cheek = of("top"), of("bot"), of("es"), of("ps"), of("cheek")
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

local BLINK = { -- one blink every 3.8 s; the hold between asks for no frames
    duration = 100,
    loops = "infinite",
    keyframes = {
        T(1, 1),
        { value = T(1, 1), duration = 3600 },
        { value = T(1, 0.1), duration = 70 },
        { value = T(1, 1), duration = 120 },
    },
}

local pupil_anim = track("pupil", { translate = SPRING(260, 20), scale = SPRING(400, 24) })

local function eye()
    return rect {
        width = 15,
        height = 20,
        radius = 8,
        clip = "rounded",
        background = DARK,
        scale = eye_scale:map(function(s) return T(s, s) end),
        animate = { scale = SPRING(500, 16) },
        children = {
            rect { width = 3, height = 3, radius = 2, background = "#FFFFFFB0", align_h = "center", align_v = "end", margin = { bottom = 3, left = 4 } },
            rect {
                width = 7,
                height = 7,
                radius = 4,
                background = "#FFFFFF",
                align_h = "center",
                align_v = "start",
                margin = { top = 3 },
                translate = look,
                scale = pupil_scale:map(function(s) return T(s, s) end),
                animate = pupil_anim,
            },
            rect { width = 15, height = lid_top, background = PATCH, align_v = "start", animate = { height = 110 } },
            rect { width = 19, height = lid_bot, radius = 999, background = PATCH, align_v = "end", align_h = "center", animate = { height = 110 } },
        },
    }
end

local function arm(side, part)
    return rect {
        width = 14,
        height = 30,
        radius = { top_left = 7, top_right = 7, bottom_right = 12, bottom_left = 12 },
        origin = { x = 0.5, y = 0.12 },
        background = "#3E4B78",
        rotate = side * 8,
        animate = track(part, {}),
    }
end

local function foot(swing)
    return rect {
        width = 24,
        height = 11,
        radius = 999,
        background = BEAK,
        origin = { x = 0.5, y = 0 },
        rotate = tilt:map(function(t) return swing * t * 0.9 end),
        translate = grab:map(function(g) return T(0, g and 5 or 0) end),
        animate = { rotate = SPRING(120, 5), translate = SPRING(300, 14) },
    }
end

local function cheek_dot()
    return rect {
        width = 13,
        height = 9,
        radius = 5,
        background = "#FF8FA0",
        opacity = cheek,
        animate = { opacity = 200 },
    }
end

local function tuft(angle, h)
    return rect { width = 6, height = h, radius = 3, rotate = angle, origin = { x = 0.5, y = 1 }, background = BODY_BOT }
end

-- A round, chubby penguin: wide-set glossy eyes low on a heart-shaped mask, a small beak, big cheeks.
local body = rect {
    width = 84,
    height = 76,
    align_h = "center",
    align_v = "end",
    margin = { bottom = 13 },
    radius = { top_left = 42, top_right = 42, bottom_right = 36, bottom_left = 36 },
    background = { gradient = "linear", angle = 180, stops = { { 0, BODY_TOP }, { 1, BODY_BOT } } },
    shadows = grab:map(function(g)
        return {
            { color = "#00000055", blur = g and 30 or 14, offset = { y = g and 16 or 6 } },
            { inset = true, color = "#FFFFFF30", blur = 8, offset = { y = 3 } },
        }
    end),
    animate = { shadows = 200 },
    children = {
        rect { width = 52, height = 36, radius = 999, align_h = "center", align_v = "end", margin = { bottom = 2 }, background = BELLY },
        row { align_h = "center", margin = { top = 12 }, spacing = -10, children = {
            rect { width = 40, height = 40, radius = 999, background = PATCH },
            rect { width = 40, height = 40, radius = 999, background = PATCH },
        } },
        row {
            align_h = "center",
            margin = { top = 22 },
            spacing = 20,
            animate = { scale = BLINK },
            scale = T(1, 1),
            children = { eye(), eye() },
        },
        row { align_h = "center", margin = { top = 44 }, spacing = 48, children = { cheek_dot(), cheek_dot() } },
        path {
            width = 28,
            height = 24,
            align_h = "center",
            margin = { top = 42 },
            origin = { x = 0.5, y = 0 },
            scale = 0.78,
            fill = BEAK,
            stroke = BEAK_D,
            stroke_width = 1.5,
            stroke_join = "round",
            commands = mouth_shape,
            animate = { commands = 120 },
        },
        row { align_h = "center", margin = { top = -8 }, spacing = 0, children = { tuft(-24, 12), tuft(0, 15), tuft(24, 12) } },
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
    opacity = grab:map(function(g) return g and 0.35 or 1 end),
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
        rect { align_h = "center", align_v = "end", margin = { bottom = 3 }, width = 66, height = 14, children = {
            row { spacing = 18, children = { foot(1), foot(-1) } },
        } },
                row { width = W, height = 40, margin = { top = 50 }, padding = { left = 3, right = 3 }, children = {
            arm(1, "arm_l"),
            rect { width = "fill", height = 1 },
            arm(-1, "arm_r"),
        } },
        body,
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

local motion = phys:map(function(p)
    if p == "drag" then return { translate = SPRING(520, 34), rotate = SPRING(260, 12) } end
    if p == "walk" then return { translate = SPRING(12, 7), rotate = SPRING(120, 8) } end
    if p == "coast" then return { translate = SPRING(70, 15), rotate = SPRING(120, 8) } end
    return { translate = SPRING(260, 12), rotate = SPRING(200, 9) }
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
                    translate = pos,
                    rotate = tilt,
                    animate = motion,
                    children = { ground, spin, speech },
                },
            },
        },
    },
}
