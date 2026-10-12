#include "wire.lua"
#include "geometry.lua"
#include "surface.lua"
#include "burst.lua"
#include "crew.lua"
-- Independent global mod. All controls and replay drawing live here.
local R={enabled=true,ownOnly=false,now=0,sequence=0}
local EDGES = {{1,2},{1,3},{2,4},{3,4},{5,6},{5,7},{6,8},{7,8},{1,5},{2,6},{3,7},{4,8}}
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function publish()
    SetBool("level.wtr.enabled",R.enabled)
    SetBool("level.wtr.ownOnly",R.ownOnly)
    SetFloat("level.wtr.clientTime",GetTime())
    SetInt("level.wtr.ack",R.sequence)
end
function init()
    ReplaySurface.resetFraming()
    ReplayBurst.reset()
    ReplayCrew.reset()
    if HasKey("savegame.mod.enabled") then R.enabled=GetBool("savegame.mod.enabled") end
    R.ownOnly=GetBool("savegame.mod.ownOnly")
    R.sequence=GetInt("level.wtr.sequence")
    publish()
end
local function start(rec,live)
    local clock=rec.latest or 0
    if live and R.active and R.active.live and R.active.vehicle==rec.vehicle then
        clock=math.max(clock,R.active.clockBase+R.now-R.active.receivedAt)
    end
    rec.clockBase=clock
    rec.playDuration=rec.burst and math.max(2.5,rec.maxTime) or 2.5
    rec.live=live or false; rec.receivedAt=R.now
    if not rec.crewJobs then ReplayCrew.prepare(rec) end
    R.active=rec; R.last=rec; R.elapsed=0
end
function tick(dt)
    R.now=R.now+dt
    if InputPressed("f8") then
        R.enabled=not R.enabled
        SetBool("savegame.mod.enabled",R.enabled)
        if not R.enabled then R.active=nil; ReplayBurst.reset() end
        R.notice=R.now+3
    end
    if InputPressed("f10") then
        R.ownOnly=not R.ownOnly; R.notice=R.now+3
        SetBool("savegame.mod.ownOnly",R.ownOnly)
    end
    if InputPressed("f9") and R.last and R.enabled then start(R.last) end
    local dismiss=InputPressed("backspace")
    if dismiss then
        R.active=nil
        ReplayBurst.reset()
        SetInt("level.wtr.cancel",GetInt("level.wtr.cancel")+1)
    end
    publish()
    local sequence=GetInt("level.wtr.sequence")
    if sequence~=R.sequence then
        R.sequence=sequence
        if R.enabled and not dismiss then
            local packet=WTRWire.decode(GetString("level.wtr.payload"))
            for _,rec in ipairs(packet and (packet.records or {packet}) or {}) do
            if rec and rec.lines and rec.lines[1] and rec.boxes and rec.holes
                and rec.direction and rec.impact and rec.maxTime and rec.name and rec.ammo and rec.caliber then
                rec.truncated=rec.truncated or GetBool("level.wtr.limited")
                local merged=ReplayBurst.accept(rec)
                if merged then
                    merged.truncated=merged.truncated or GetBool("level.wtr.limited")
                    ReplaySurface.beginOutline(merged)
                    start(merged,true)
                end
            end
            end
        end
        SetInt("level.wtr.ack",R.sequence)
    end
    if R.active then
        ReplayCrew.step(R.active)
        R.elapsed=R.elapsed+dt
        local lifetime=R.active.live and 3.5 or (R.active.playDuration+.85)
        if R.elapsed>lifetime then R.active=nil end
    end
end

local function line2(x1,y1,x2,y2,width)
    local dx,dy=x2-x1,y2-y1
    UiPush(); UiTranslate(x1,y1); UiRotate(-math.deg(math.atan2(dy,dx)))
    UiAlign("left middle"); UiRect(math.sqrt(dx*dx+dy*dy),width or 1); UiPop()
end
local function label(x,y,text,size,r,g,b)
    UiPush(); UiTranslate(x,y); UiFont("regular.ttf",size); UiColor(r or 1,g or 1,b or 1)
    UiAlign("left top"); UiText(text); UiPop()
end
local STATUS_COLORS={ok={.25,.9,.94},damaged={1,.84,.2},critical={1,.48,.12},
    disabled={1,.18,.19},destroyed={1,.18,.19},burning={1,.28,.08},unknown={.66,.7,.73}}
local function moduleVisual(m,tm,elapsed,rec)
    if m.events then
        local state=m.before; local arrived,flash=false,false
        local stateOrder=-1
        for _,e in ipairs(m.events) do
            if e.t<=tm then
                -- Overlapping slow-motion shots must not restore an older
                -- damage snapshot after a newer shot has already arrived.
                if (e.order or 0)>=stateOrder then state=e.state; stateOrder=e.order or 0 end
                if e.hit then
                    arrived=true
                    local age=rec.live and (tm-e.t) or (elapsed-(.15+rec.playDuration*e.t/math.max(rec.maxTime,.0001)))
                    if age>=0 and age<.25 then flash=true end
                end
            end
        end
        local name=state and state.state or "unknown"
        return STATUS_COLORS[name] or STATUS_COLORS.unknown,flash,name,arrived
    end
    local arrived=m.hitTime~=nil and tm>=m.hitTime
    local state=(tm>=0 and (m.hitTime==nil or arrived)) and m.after or m.before
    local c=STATUS_COLORS[state and state.state or "unknown"] or STATUS_COLORS.unknown
    local flash=false
    if arrived then
        local at=.15+.625+1.875*m.hitTime/math.max(rec.maxTime,.015)
        flash=elapsed-at>=0 and elapsed-at<.32
    end
    return c,flash,state and state.state or "unknown",arrived
end
local function render(rec)
    local function screen(p) return ReplaySurface.project(rec,p) end
    local progress=clamp((R.elapsed-0.15)/(rec.playDuration or 2.5),0,1)
    -- Reserve time for the approach, then expand sub-frame penetration detail.
    local tm
    if rec.burst then
        if rec.live then tm=rec.clockBase-rec.windowStart+R.now-rec.receivedAt
        else tm=progress*rec.maxTime end
    elseif progress<0.25 then tm=-0.04+progress/0.25*0.04
    else tm=(progress-0.25)/0.75*math.max(rec.maxTime,0.015) end
    local hit=tm>=0
    UiColor(0.035,0.048,0.06,0.94); UiRect(488,412)
    UiColor(0.95,0.57,0.22); UiRect(488,3)
    label(18,15,"HIT REPLAY",20)
    local result=not hit and "INCOMING" or (rec.penetrated and "PENETRATION" or (rec.ricochet and "RICOCHET" or "IMPACT"))
    if rec.burst then
        result="INCOMING"
        for _,impact in ipairs(rec.impacts) do
            if tm>=impact.t then result=impact.penetrated and "PENETRATION" or (impact.ricochet and "RICOCHET" or "IMPACT") end
        end
    end
    label(285,18,result,16,1,0.65,0.3)
    local detail=rec.burst and (rec.shots.." SHOTS / LAST 3s"..(rec.truncated and " / LIMIT" or "")) or (math.floor(rec.caliber).."mm "..rec.ammo)
    label(18,42,string.sub(rec.name,1,25).." / "..detail,13,0.64,0.73,0.78)
    local summary={}
    for _,m in ipairs(rec.modules or {}) do summary[#summary+1]=m end
    table.sort(summary,function(a,b)
        local function priority(m)
            if m.hitTime~=nil then return 0 end
            if m.after and m.after.state~="ok" then return 1 end
            return 2
        end
        local pa,pb=priority(a),priority(b)
        return pa<pb or (pa==pb and a.id<b.id)
    end)
    UiPush(); UiTranslate(12,64); UiWindow(464,236,true); UiTranslate(-12,-64)
    -- Keep the initial wire appearance throughout playback and F9 replay.
    -- Draw module outlines after armor so small internal parts remain visible.
    for pass=1,2 do
    for _,box in ipairs(rec.boxes) do
      if (pass==2)==(box.category~=nil) then
        local m=box.module and rec.modules and rec.modules[box.module]
        local flash=false
        if box.category=="crew" then
            if box.crewDead then UiColor(1,.15,.15,1) else UiColor(.2,1,.35,1) end
        elseif m then
            local c; c,flash=moduleVisual(m,tm,R.elapsed,rec)
            if flash then UiColor(1,1,1,1) else UiColor(c[1],c[2],c[3],.95) end
        elseif box.category then UiColor(.66,.7,.73,.8)
        elseif box.hit and hit then UiColor(1,0.86,0.35,0.85)
        elseif box.component then UiColor(.35,.48,.57,.38)
        else UiColor(.35,.48,.57,.25) end
        local crewLines=ReplayCrew.lines(box)
        if crewLines then
            for _,edge in ipairs(crewLines) do
                local x,y=screen(edge.a); local u,v=screen(edge.b)
                line2(x,y,u,v,1.1)
            end
        else
        for _,edge in ipairs(EDGES) do
            local x,y=screen(box.points[edge[1]]); local u,v=screen(box.points[edge[2]])
            line2(x,y,u,v,flash and 2.5 or (box.category and 1.8 or (box.hit and 1.5 or 1)))
        end
      end
    end
    end
    -- Small IDs tie the three detail rows to their wireframe modules.
    for i=1,math.min(3,#summary) do
        local m=summary[i]
        for _,box in ipairs(rec.boxes) do
            if box.module==m.id then
                local center=Vec()
                for _,p in ipairs(box.points) do center=VecAdd(center,VecScale(p,1/8)) end
                local x,y=screen(center)
                label(x+3,y-6,"#"..m.id,10,.88,.94,.96)
                break
            end
        end
    end
    end
    for _,l in ipairs(rec.lines) do
        if tm>=l.t then
            local fraction=clamp((tm-l.t)/l.d,0,1)
            local p=VecLerp(l.a,l.b,fraction)
            local x,y=screen(l.a); local u,v=screen(p)
            if l.fragment then UiColor(1,0.30,0.10,0.75) else UiColor(1,0.83,0.25,1) end
            line2(x,y,u,v,l.fragment and 1 or 2.2)
            if fraction<1 then UiPush(); UiTranslate(u,v); UiAlign("center middle"); UiRect(4,4); UiPop() end
        end
    end
    UiColor(1,0.2,0.1,0.8)
    for _,h in ipairs(rec.holes) do if tm>=h.t then
        local x,y=screen(h.p); UiPush(); UiTranslate(x,y); UiAlign("center middle"); UiRect(3,3); UiPop()
    end end
    for _,impact in ipairs(rec.impacts or {{p=rec.impact,t=0}}) do if tm>=impact.t then
        local x,y=screen(impact.p); UiColor(1,0.7,0.2)
        line2(x-5,y,x+5,y,2); line2(x,y-5,x,y+5,2)
    end end
    UiPop()
    label(18,304,"CYAN OK / YELLOW-ORANGE DAMAGE / RED DISABLED",10,.75,.78,.8)
    for i=1,math.min(3,#summary) do
        local m=summary[i]; local c,flash,state,arrived=moduleVisual(m,tm,R.elapsed,rec)
        local prefix=arrived and (m.damagedByShot and (rec.burst and "BURST DAMAGE " or "SHOT DAMAGE ") or "HIT ") or ""
        local status=state:upper()
        if arrived and m.before and m.before.state~=state then status=m.before.state:upper().." > "..status end
        label(18,320+(i-1)*17,prefix..m.label.." #"..m.id..": "..status,11,c[1],c[2],c[3])
    end
    if #summary==0 then label(18,323,"MODULE STATUS UNKNOWN / RECORDER DATA UNAVAILABLE",11,.66,.7,.73) end
    if #summary>3 then label(18,372,"+"..(#summary-3).." MODULES SHOWN BY STATE COLOR",10,.66,.7,.73) end
    label(18,390,"F9 REPLAY   |   BACKSPACE DISMISS   |   F8 ON/OFF",12,0.77,0.82,0.84)
    UiPush(); UiTranslate(0,409); UiColor(0.95,0.57,0.22); UiRect(488*progress,3); UiPop()
end
function draw(dt)
    UiPush(); UiAlign("left top")
    local scale=math.min(1,UiWidth()/1100,UiHeight()/650)
    UiTranslate(UiWidth()-508*scale,64*scale); UiScale(scale)
    if R.active then render(R.active)
    elseif R.now<8 or (R.notice and R.now<R.notice) then
        UiColor(0.035,0.048,0.06,0.90); UiRect(488,70)
        label(14,12,"TABS HIT REPLAY  "..((GetInt("level.wtr.bridgeVersion")~=3 or math.abs(GetTime()-GetFloat("level.wtr.bridgeTime"))>0.5) and "BRIDGE MISSING" or (R.enabled and "ON" or "OFF")),18)
        label(14,39,"F8 TOGGLE / F9 REPLAY / F10: "..(R.ownOnly and "OWN VEHICLE" or "NEARBY VEHICLES"),12,0.7,0.8,0.85)
    end
    UiPop()
end
