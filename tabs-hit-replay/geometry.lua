-- Client-side visual enrichment. Does not change the TABS recorder or physics.
ReplayGeometry={}
local LIMIT=384
local function valid(h) return h and h~=0 and IsHandleValid(h) end
local MODULES={Engine=true,Transmission=true,Breech=true,Turret_Ring=true,Sight=true}
local function crewRole(shape)
    if not valid(shape) then return nil end
    local body=GetShapeBody(shape)
    if not valid(body) or not HasTag(body,"tabscrew") then return nil end
    local role=GetTagValue(body,"role")
    if role=="crew" or role=="driver" then return role,body end
end
function ReplayGeometry.category(shape)
    if crewRole(shape) then return "crew" end
    -- Match shape-level TABS component tags, not broad body Part=Turret tags.
    if HasTag(shape,"Ammo_Size") and not HasTag(shape,"Blowout_Panel") then return "ammo" end
    if HasTag(shape,"Fuel_Size") or HasTag(shape,"Barrel") or MODULES[GetTagValue(shape,"Part")] then
        return "module"
    end
    return nil
end
local function signature(box)
    local values={}
    for _,p in ipairs(box.points) do for k=1,3 do values[#values+1]=string.format("%.2f",p[k]) end end
    return table.concat(values,",")
end
function ReplayGeometry.enrich(rec)
    -- Keep the pre-impact snapshot separate from post-impact enrichment.
    -- Flying fragments must never change the framing on the first replay.
    rec.framingBoxes=rec.framingBoxes or rec.boxes
    local moduleByShape={}
    for _,m in ipairs(rec.modules or {}) do
        for _,s in ipairs(m.shapes) do moduleByShape[s]=m end
    end
    for _,box in ipairs(rec.boxes) do
        local m=moduleByShape[box.shape]
        if m then box.module=m.id; box.category=m.category end
        local role,body=crewRole(box.shape)
        if role then box.category="crew"; box.crewRole=role; box.crewBody=body end
    end
    if not valid(rec.vehicle) then return end
    local hull=GetVehicleBody(rec.vehicle)
    if not valid(hull) then return end
    -- Local coordinates remove vehicle translation/rotation since the hit.
    -- Turret articulation is sampled on receipt, then frozen for all replays.
    local frame=GetBodyTransform(hull)
    local groups,byBody,seenShape={},{},{}
    local function addShape(s)
        if not valid(s) or seenShape[s] or HasTag(s,"invisible") then return end
        seenShape[s]=true
        local b=GetShapeBody(s)
        local owner=GetBodyVehicle(b)
        if owner~=0 and owner~=rec.vehicle then return end
        local x,y,z,scale=GetShapeSize(s)
        if x*y*z==0 then return end
        if not byBody[b] then byBody[b]={}; groups[#groups+1]=byBody[b] end
        local group=byBody[b]
        group[#group+1]={shape=s,x=x,y=y,z=z,scale=scale,volume=x*y*z*scale^3,category=ReplayGeometry.category(s)}
    end
    for _,s in ipairs(GetBodyShapes(hull)) do addShape(s) end
    for _,s in ipairs(GetEntityChildren(rec.vehicle,"",true,"shape")) do addShape(s) end
    for _,b in ipairs(GetJointedBodies(hull)) do
        if valid(b) then for _,s in ipairs(GetBodyShapes(b)) do addShape(s) end end
    end
    -- The Crew mod uses the reverse joint relationship to associate seats.
    -- This also covers crew not parented under the vehicle entity hierarchy.
    if FindBodies then for _,b in ipairs(FindBodies("tabscrew",true)) do
        if valid(b) then
            local attached=GetBodyVehicle(b)==rec.vehicle
            if not attached then for _,jointed in ipairs(GetJointedBodies(b)) do
                if valid(jointed) and GetBodyVehicle(jointed)==rec.vehicle then attached=true; break end
            end end
            if attached then for _,s in ipairs(GetBodyShapes(b)) do addShape(s) end end
        end
    end end
    table.sort(groups,function(a,b)
        local function hasCrew(group)
            for _,item in ipairs(group) do if item.category=="crew" then return true end end
            return false
        end
        return hasCrew(a) and not hasCrew(b)
    end)
    for _,group in ipairs(groups) do
        table.sort(group,function(a,b)
            if (a.category~=nil)~=(b.category~=nil) then return a.category~=nil end
            if a.volume==b.volume then return a.shape<b.shape end
            return a.volume>b.volume
        end)
    end
    local boxes,seen,surfaceShapes={},{},{}
    -- Preserve every original hit-time box, particularly destroyed hit shapes.
    for _,box in ipairs(rec.boxes) do
        local key=signature(box)
        if not seen[key] then boxes[#boxes+1]=box; seen[key]=box end
    end
    local index,more=1,true
    while more and #boxes<LIMIT do
        more=false
        -- Round robin over bodies: dense hull detail cannot starve the turret.
        for _,group in ipairs(groups) do
            local item=group[index]
            if item then
                more=true
                local s=item.shape
                local t=GetShapeWorldTransform(s)
                local box={points={},hit=false,category=item.category,component=HasTag(s,"component") or HasTag(s,"Ammo_Size") or HasTag(s,"Part")}
                box.shape=s
                box.crewRole,box.crewBody=crewRole(s)
                local m=moduleByShape[s]
                if m then box.module=m.id; box.category=m.category end
                for iz=0,1 do for iy=0,1 do for ix=0,1 do
                    box.points[#box.points+1]=TransformToLocalPoint(frame,TransformToParentPoint(t,
                        Vec(ix*item.x*item.scale,iy*item.y*item.scale,iz*item.z*item.scale)))
                end end end
                local key=signature(box)
                surfaceShapes[#surfaceShapes+1]={shape=s,x=item.x,y=item.y,z=item.z,
                    points=box.points,category=item.category}
                if not seen[key] then boxes[#boxes+1]=box; seen[key]=box
                elseif box.category then
                    -- Enrich existing hit-time boxes too; dedup must not drop tags.
                    if seen[key].category~="ammo" then seen[key].category=box.category end
                    if box.module then seen[key].module=box.module end
                    if box.crewRole then seen[key].crewRole=box.crewRole; seen[key].crewBody=box.crewBody end
                end
                if #boxes>=LIMIT then break end
            end
        end
        index=index+1
    end
    rec.boxes=boxes
    rec.surfaceShapes=surfaceShapes
end
