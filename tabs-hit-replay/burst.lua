-- Independent-client rolling history. Shot coordinates are already hull-local,
-- so vehicle movement between impacts must not be reapplied to the traces.
ReplayBurst={}
local B=ReplayBurst
-- Display time only: preserve inter-shot spacing, but stretch each shot's
-- approach and penetration so overlapping automatic-fire paths remain visible.
function B.flightTime(shot,t)
    if t<0 then return .55*math.max(0,math.min(1,(t+.04)/.04)) end
    return .55+.9*math.max(0,math.min(1,t/math.max(shot.maxTime,.0001)))
end
local histories={}
function B.reset() histories={} end
local function moduleKey(m)
    local ids={}; for _,s in ipairs(m.shapes or {}) do ids[#ids+1]=s end
    table.sort(ids)
    return m.label..":"..table.concat(ids,",")
end
function B.accept(rec)
    local history=histories[rec.vehicle] or {}
    histories[rec.vehicle]=history
    for _,old in ipairs(history) do if old.shotId and old.shotId==rec.shotId then return end end
    history[#history+1]=rec
    table.sort(history,function(a,b) return a.created<b.created or (a.created==b.created and (a.shotId or 0)<(b.shotId or 0)) end)
    local newest=history[#history].created
    while #history>0 and history[1].created<newest-3 do table.remove(history,1) end
    local limited=false
    while #history>96 do table.remove(history,1); limited=true end
    for vehicle,list in pairs(histories) do
        if vehicle~=rec.vehicle and list[#list].created<newest-3 then histories[vehicle]=nil end
    end
    local first,last=history[1],history[#history]
    if not last.prepared then
        ReplayGeometry.enrich(last); last.prepared=true
    end
    local out={vehicle=last.vehicle,name=last.name,ammo="BURST",caliber=last.caliber,
        direction=first.direction,impact=last.impact,boxes={},lines={},holes={},modules={},impacts={},
        framingBoxes=first.framingBoxes or first.boxes,windowStart=first.created,
        latest=last.created,shots=#history,burst=true,maxTime=0,truncated=limited}
    local byKey={}; local lastMap={}
    for shotIndex,shot in ipairs(history) do
        local offset=shot.created-first.created
        out.maxTime=math.max(out.maxTime,offset+1.45)
        out.penetrated=out.penetrated or shot.penetrated
        out.ricochet=out.ricochet or shot.ricochet
        out.truncated=out.truncated or shot.truncated
        out.impacts[#out.impacts+1]={p=shot.impact,t=offset+B.flightTime(shot,0),penetrated=shot.penetrated,ricochet=shot.ricochet}
        for _,m in ipairs(shot.modules or {}) do
            local key=moduleKey(m); local combined=byKey[key]
            if not combined then
                combined={id=#out.modules+1,label=m.label,category=m.category,shapes=m.shapes,
                    before=m.before,after=m.after,events={}}
                byKey[key]=combined; out.modules[#out.modules+1]=combined
            end
            combined.after=m.after
            if m.hitTime~=nil then
                local t=offset+B.flightTime(shot,m.hitTime)
                combined.hitTime=combined.hitTime or t
                combined.damagedByShot=combined.damagedByShot or m.damagedByShot
                combined.events[#combined.events+1]={t=t,state=m.shotAfter or m.after,
                    hit=true,damage=m.damagedByShot or false,order=shotIndex}
            end
            combined.events[#combined.events+1]={t=offset+1.45,state=m.after,order=shotIndex}
            if shot==last then lastMap[m.id]=combined.id end
        end
        for _,h in ipairs(shot.holes) do
            if #out.holes<360 then out.holes[#out.holes+1]={p=h.p,t=offset+B.flightTime(shot,h.t)}
            else out.truncated=true end
        end
    end
    for _,m in ipairs(out.modules) do
        table.sort(m.events,function(a,b)
            if a.t~=b.t then return a.t<b.t end
            if a.order~=b.order then return a.order<b.order end
            return a.hit==true and b.hit~=true
        end)
    end
    -- Reserve capacity for main projectile trajectories before adding spall.
    for pass=1,2 do for _,shot in ipairs(history) do
        local offset=shot.created-first.created
        for _,l in ipairs(shot.lines) do if (pass==2)==(l.fragment==true) then
            if #out.lines<6000 then
                local begin=B.flightTime(shot,l.t)
                local finish=B.flightTime(shot,l.t+l.d)
                out.lines[#out.lines+1]={a=l.a,b=l.b,t=offset+begin,d=math.max(.0001,finish-begin),fragment=l.fragment}
            else out.truncated=true end
        end end
    end end
    local visibleModules={}
    for _,box in ipairs(last.boxes) do
        local id=lastMap[box.module]
        out.boxes[#out.boxes+1]={points=box.points,shape=box.shape,hit=box.hit,
            category=box.category,component=box.component,module=id,crewRole=box.crewRole,crewBody=box.crewBody}
        if id then visibleModules[id]=true end
    end
    -- Keep an earlier outline for modules that disappeared during the burst.
    for _,shot in ipairs(history) do
        local shapeMap={}
        for _,m in ipairs(shot.modules or {}) do
            local combined=byKey[moduleKey(m)]
            if combined and not visibleModules[combined.id] then
                for _,s in ipairs(m.shapes) do shapeMap[s]=combined end
            end
        end
        for _,box in ipairs(shot.boxes) do
            local m=shapeMap[box.shape]
            if m and #out.boxes<480 then
                out.boxes[#out.boxes+1]={points=box.points,shape=box.shape,category=m.category,module=m.id}
                visibleModules[m.id]=true
            end
        end
    end
    return out
end
