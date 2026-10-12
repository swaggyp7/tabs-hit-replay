-- TABS-side recorder bridge. Inert unless the standalone mod supplies a live lease.
WTR = {enabled=false, ownOnly=false, now=0, context=nil, fragment=false, queue={}, shotId=0}
local R = WTR
local function valid(h) return h and h ~= 0 and IsHandleValid(h) end
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function vehicleOf(shape)
    if not valid(shape) then return 0 end
    local b = GetShapeBody(shape)
    local v = GetBodyVehicle(b)
    if not valid(v) then v = GetEntityParent(b,"","vehicle") end
    if not valid(v) and IsBodyDynamic(b) then
        for _,j in ipairs(GetJointedBodies(b)) do
            local candidate = GetBodyVehicle(j)
            if valid(candidate) and HasTag(candidate,"TABS") then v=candidate; break end
        end
    end
    return valid(v) and HasTag(v,"TABS") and v or 0
end
local function localPoint(rec,p) return TransformToLocalPoint(rec.transform,p) end
-- References to TABS tables stay private: only plain snapshots cross the registry.
local moduleSources=setmetatable({},{__mode="k"})
local function moduleState(source)
    local total,initial=0,0
    for _,s in ipairs(source.shapes) do
      if not source.body or (valid(s.shape) and GetShapeBody(s.shape)==source.body) then
        total=total+(valid(s.shape) and GetShapeVoxelCount(s.shape) or 0)
        initial=initial+(s.initialvoxcount or 0)
      end
    end
    local obj=source.object
    local ratio=initial>0 and clamp(total/initial,0,1) or nil
    local burning=obj.onFire==true or obj.fire==true or (tonumber(obj.firetimer) or 0)>0
    local broken=obj.broken==true or obj.disconnected==true or (source.kind=="breech" and source.weapon and (source.weapon.broken or source.weapon.disconnected)) or false
    local state,hp="unknown",nil
    if ratio then
        if source.kind=="ammo" then
            -- Ammo's original formula divides by (1-1); do not export that NaN.
            hp=ratio
            state=total==0 and "destroyed" or (ratio<1 and "damaged" or "ok")
        elseif source.threshold and source.threshold<1 then
            hp=clamp((ratio-source.threshold)/(1-source.threshold),0,1)
            state=(broken or ratio<source.threshold) and "disabled" or (hp<.35 and "critical" or (ratio<1 and "damaged" or "ok"))
        end
    end
    if broken then state="disabled" end
    if burning then state="burning" end
    if total==0 and initial>0 then state="destroyed" end
    local nativeHp=tonumber(obj.hp)
    if nativeHp and (nativeHp~=nativeHp or math.abs(nativeHp)==math.huge) then nativeHp=nil end
    return {state=state,hp=hp,nativeHp=nativeHp,voxels=total,burning=burning,broken=not not broken}
end
local function collectModules(rec)
    rec.modules={}
    local sources={}; moduleSources[rec]=sources
    local vehicle=TABSVehicles and TABSVehicles[rec.vehicle]
    if not vehicle or not GetShapeVoxelCount then return end
    local function add(label,kind,obj,shapes,threshold,weapon)
        if not obj or not shapes or #shapes==0 or #sources>=96 then return end
        local m={id=#sources+1,label=label,category=kind=="ammo" and "ammo" or "module",shapes={}}
        local frozenShapes={}
        for _,s in ipairs(shapes) do frozenShapes[#frozenShapes+1]={shape=s.shape,initialvoxcount=s.initialvoxcount} end
        local source={object=obj,shapes=frozenShapes,threshold=threshold,kind=kind,weapon=weapon,
            body=kind=="barrel" and weapon and weapon.body or nil}
        for _,s in ipairs(shapes) do m.shapes[#m.shapes+1]=s.shape end
        sources[#sources+1]=source; m.before=moduleState(source); m.after=m.before
        rec.modules[#rec.modules+1]=m
    end
    local parts=vehicle.parts or {}
    for _,key in ipairs({"engine","transmission"}) do
        local obj=parts[key]; if obj then add(key:upper(),key,obj,obj.shapes,obj.threshold) end
    end
    for _,w in pairs(parts.weapons or {}) do
        local b=w.breech
        if b and b.brshape and b.brshape~=0 then add("BREECH","breech",b,{{shape=b.brshape,initialvoxcount=b.brinitialvoxcount}},.85,w) end
        b=w.barrel; if b then add("BARREL","barrel",b,b.shapes,.8,w) end
    end
    for _,t in pairs(parts.turrets or {}) do
        local ring=t.turretring; if ring then add("TURRET RING","ring",ring,ring.shapes,.9) end
        for _,o in pairs(t.optics or {}) do
            if o.sightShape and o.sightShape~=0 then add("SIGHT","sight",o,{{shape=o.sightShape,initialvoxcount=o.initialvoxcount}},.5) end
        end
    end
    for _,a in pairs(vehicle.ammorack and vehicle.ammorack.ammoShapes or {}) do
        add("AMMO","ammo",a,{{shape=a.shape,initialvoxcount=a.initialvoxcount}})
    end
    for _,f in pairs(vehicle.fuelstorage and vehicle.fuelstorage.fuelTanks or {}) do
        add("FUEL","fuel",f,{{shape=f.shape,initialvoxcount=f.initialvoxcount}},.8)
    end
end
local function captureOpen(rec)
    return rec and R.enabled and not rec.sealed and R.now-rec.created<=.3
end
local function checkpoint(rec)
    if not captureOpen(rec) then return end
    local out={}
    for i,s in ipairs(moduleSources[rec] or {}) do out[i]=moduleState(s).voxels end
    return out
end
local function moduleTime(rec,projectile)
    return clamp(((projectile and projectile.frametime or rec.originTime)-rec.originTime)/60,0,.25)
end
local function changes(rec,before,projectile,fragment)
    if not before or not captureOpen(rec) then return end
    for i,s in ipairs(moduleSources[rec] or {}) do
        local m=rec.modules[i]; local now=moduleState(s)
        if now.voxels<before[i] then
            local time=moduleTime(rec,projectile)
            if not m.hitTime then m.hitTime=time; m.fragment=not not fragment end
            m.damagedByShot=true
        end
        m.after=now; m.shotAfter=now
    end
end
local function directHit(rec,shape,projectile)
    if not captureOpen(rec) then return end
    for _,m in ipairs(rec.modules or {}) do for _,s in ipairs(m.shapes) do
        if s==shape then m.hitTime=m.hitTime or moduleTime(rec,projectile); m.direct=true end
    end end
end
local function snapshot(v,hitShape)
    local hull = GetVehicleBody(v)
    local rec = {transform=GetBodyTransform(hull), boxes={}, lines={}, holes={},
        vehicle=v, created=R.now, maxTime=0, minTime=0, penetrated=false, ricochet=false}
    local seen={}
    local function add(s)
        if not valid(s) or seen[s] or #rec.boxes>=96 or HasTag(s,"invisible") then return end
        seen[s]=true
        local x,y,z,scale = GetShapeSize(s)
        if x*y*z==0 then return end
        local t=GetShapeWorldTransform(s)
        local box={points={},shape=s,hit=s==hitShape,
            component=HasTag(s,"component") or HasTag(s,"Ammo_Size") or HasTag(s,"Part")}
        for iz=0,1 do for iy=0,1 do for ix=0,1 do
            box.points[#box.points+1]=localPoint(rec,TransformToParentPoint(t,Vec(ix*x*scale,iy*y*scale,iz*z*scale)))
        end end end
        rec.boxes[#rec.boxes+1]=box
    end
    collectModules(rec)
    add(hitShape)
    -- Preserve critical module geometry before a projectile destroys it.
    for _,m in ipairs(rec.modules) do for _,s in ipairs(m.shapes) do add(s) end end
    for _,s in ipairs(GetBodyShapes(hull)) do add(s) end
    for _,s in ipairs(GetEntityChildren(v,"",true,"shape")) do add(s) end
    for _,b in ipairs(GetJointedBodies(hull)) do
        local owner=GetBodyVehicle(b)
        if owner==0 or owner==v then for _,s in ipairs(GetBodyShapes(b)) do add(s) end end
    end
    return rec
end

function WTRImpactBegin(projectile,info)
    if not R.enabled or R.fragment or projectile.type=="spall" or (projectile.caliber or 0)<=0 then return end
    if projectile._wtr then R.context=projectile._wtr; directHit(R.context,info.shape,projectile); return end
    if not valid(info.shape) then return end
    local v=vehicleOf(info.shape)
    if v==0 or (R.ownOnly and v~=GetPlayerVehicle()) then return end
    if #R.queue>=128 then R.limited=true; return end
    local rec=snapshot(v,info.shape)
    R.shotId=R.shotId+1; rec.shotId=R.shotId
    rec.originTime=projectile.frametime or 0
    rec._baseline=checkpoint(rec)
    directHit(rec,info.shape,projectile)
    rec.impact=localPoint(rec,info.hitPos)
    rec.name=GetDescription(v)
    if rec.name=="" then rec.name="TABS VEHICLE" end
    rec.ammo=tostring(projectile.type or "shell"):upper()
    rec.caliber=projectile.caliber or 0
    rec.initialRicochet=projectile.ricochetCount or 0
    rec.direction=TransformToLocalVec(rec.transform,info.dir)
    -- Actual approach segment, clipped to three metres to keep the inset legible.
    local distance=math.min(3,VecLength(VecSub(info.hitPos,projectile.pos)))
    local approach=VecSub(info.hitPos,VecScale(info.dir,distance))
    rec.lines[1]={a=localPoint(rec,approach),b=rec.impact,t=-0.04,d=0.04,fragment=false}
    rec.minTime=-0.04
    projectile._wtr=rec
    R.context=rec; R.pending=rec; R.queue[#R.queue+1]=rec
end
function WTRImpactEnd(projectile)
    local rec=projectile._wtr
    if rec then rec.ricochet=(projectile.ricochetCount or 0)>rec.initialRicochet end
end
function WTRPenetrated(projectile)
    if projectile and projectile._wtr then projectile._wtr.penetrated=true end
end
function WTRTagSpall(projectile)
    if R.context then projectile._wtr=R.context end
end
local function record(time,pos,hitpos,color,duration)
    local rec=R.context
    if not R.enabled or not rec or R.now-rec.created>0.3 then return end
    local t=clamp(((time or rec.originTime)-rec.originTime)/60,0,0.25)
    if hitpos then
        if #rec.lines>=1000 then rec.truncated=true; return end
        local a,b=localPoint(rec,pos),localPoint(rec,hitpos)
        -- Ignore far-away continuation and cap long outgoing segments.
        if VecLength(VecSub(a,rec.impact))>14 then return end
        local diff=VecSub(b,a); local length=VecLength(diff)
        if length>14 then b=VecAdd(a,VecScale(diff,14/length)) end
        local d=clamp((duration or 0.1)/60,0.0001,0.1)
        rec.lines[#rec.lines+1]={a=a,b=b,t=t,d=d,fragment=R.fragment}
        rec.maxTime=math.max(rec.maxTime,t+d)
    elseif #rec.holes<120 then
        local p=localPoint(rec,pos)
        if VecLength(VecSub(p,rec.impact))<14 then rec.holes[#rec.holes+1]={p=p,t=t} end
    end
end

local originalSave=SaveDebugInfo
function SaveDebugInfo(...)
    record(...)
    return originalSave(...)
end
local originalProjectile=ProjectileOperations
function ProjectileOperations(projectile)
    local previous,fragment=R.context,R.fragment
    R.context=projectile._wtr; R.fragment=false
    local before=checkpoint(R.context)
    originalProjectile(projectile)
    local rec=projectile._wtr
    changes(rec,before or (rec and rec._baseline),projectile,false)
    if rec then rec._baseline=nil end
    R.context=previous; R.fragment=fragment
end
local originalSpallOp=SpallOperations
function SpallOperations(projectile)
    local previous,fragment=R.context,R.fragment
    R.context=projectile._wtr; R.fragment=true
    local before=checkpoint(R.context)
    originalSpallOp(projectile)
    changes(R.context,before,projectile,true)
    R.context=previous; R.fragment=fragment
end
local originalSpall=Spall
function Spall(...)
    local previous=R.fragment; R.fragment=true
    local before=checkpoint(R.context)
    originalSpall(...)
    local time=select(6,...)
    changes(R.context,before,{frametime=time},true)
    R.fragment=previous
end

local originalTick=tick
function tick(dt)
    R.now=R.now+dt
    local lease=GetFloat("level.wtr.clientTime")
    local enabled=GetBool("level.wtr.enabled") and math.abs(GetTime()-lease)<0.5
    if not enabled then
        for _,rec in ipairs(R.queue) do rec.sealed=true end
        R.queue={}; R.pending=nil; R.context=nil
    end
    R.enabled=enabled
    R.ownOnly=GetBool("level.wtr.ownOnly")
    local cancel=GetInt("level.wtr.cancel")
    if cancel~=R.cancel then
        for _,rec in ipairs(R.queue) do rec.sealed=true end
        R.queue={}; R.pending=nil; R.cancel=cancel
    end
    SetInt("level.wtr.bridgeVersion",3)
    SetFloat("level.wtr.bridgeTime",GetTime())
    originalTick(dt)
    for _,rec in ipairs(R.queue) do
        if not rec.sealed and R.now-rec.created>=.32 then
            for i,s in ipairs(moduleSources[rec] or {}) do rec.modules[i].after=moduleState(s) end
            rec.sealed=true; rec._baseline=nil
        end
    end
    -- Do not overwrite a packet before the independent UI acknowledges it.
    if R.enabled and GetInt("level.wtr.ack")>=GetInt("level.wtr.sequence") then
        local batch={}; local payload=nil
        while #R.queue>0 and R.queue[1].sealed and #batch<2 do
            batch[#batch+1]=R.queue[1]
            local nextPayload=WTRWire.encode(#batch==1 and batch[1] or {records=batch})
            if #nextPayload>900000 then
                batch[#batch]=nil
                if #batch==0 then table.remove(R.queue,1); R.limited=true end
                break
            end
            payload=nextPayload; table.remove(R.queue,1)
        end
        if payload then
        SetBool("level.wtr.limited",R.limited or false); R.limited=false
        SetString("level.wtr.payload",payload)
        SetInt("level.wtr.sequence",GetInt("level.wtr.sequence")+1)
        end
    end
    R.pending=R.queue[#R.queue]
end
