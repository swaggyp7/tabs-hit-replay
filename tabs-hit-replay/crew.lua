-- Read-only voxel feature edges, only for small Crew shapes. Geometry remains
-- shape-local in the cache; each record supplies its own frozen world pose.
ReplayCrew={}
local C=ReplayCrew
local cache={}
local known={}
function C.reset() cache={}; known={} end
local function valid(s) return s and s~=0 and IsHandleValid(s) end
local function dead(body,vehicle)
    if not body then return false end
    if not valid(body) or (IsBodyBroken and IsBodyBroken(body)) then return true end
    if GetBodyVehicle(body)==vehicle then return false end
    for _,b in ipairs(GetJointedBodies(body)) do
        if valid(b) and GetBodyVehicle(b)==vehicle then return false end
    end
    return true
end
local function remember(rec)
    if not rec.vehicle then return end
    local roster=known[rec.vehicle] or {}; known[rec.vehicle]=roster
    local seen={}
    for _,box in ipairs(rec.boxes) do if box.category=="crew" and box.crewBody and box.shape then
        local old=roster[box.shape]
        box.crewDead=(old and old.crewDead) or dead(box.crewBody,rec.vehicle)
        -- Retain an intact frozen outline when the member is destroyed.
        if box.crewDead and old and old.crewWire and old.crewWire.done then
            box.points=old.points; box.crewWire=old.crewWire; box.crewLines=old.crewLines
        end
        roster[box.shape]=box; seen[box.shape]=true
    end end
    for shape,old in pairs(roster) do if not seen[shape] and #rec.boxes<512 then
        local box={points=old.points,shape=shape,category="crew",crewBody=old.crewBody,crewRole=old.crewRole,
            crewWire=old.crewWire,crewLines=old.crewLines,
            crewDead=old.crewDead or dead(old.crewBody,rec.vehicle) or not valid(shape)}
        rec.boxes[#rec.boxes+1]=box; roster[shape]=box
    end end
    for vehicle in pairs(known) do
        if vehicle~=rec.vehicle and not valid(vehicle) then known[vehicle]=nil end
    end
end
local function mesh(job)
    local n=job.n; local edges={}
    local function filled(x,y,z)
        if x<0 or y<0 or z<0 or x>=n[1] or y>=n[2] or z>=n[3] then return false end
        return job.grid[(z*n[2]+y)*n[1]+x] or false
    end
    local function edge(p,axis,normal)
        local key=axis..":"..table.concat(p,",")
        local e=edges[key]
        if not e then edges[key]={p=p,axis=axis,normal=normal,count=1}
        else e.count=e.count+1; if e.normal~=normal then e.crease=true end end
    end
    for index in pairs(job.grid) do
        local p={index%n[1],math.floor(index/n[1])%n[2],math.floor(index/(n[1]*n[2]))}
        for axis=1,3 do
            local u=axis%3+1; local v=u%3+1
            for _,sign in ipairs({-1,1}) do
                local q={p[1],p[2],p[3]}; q[axis]=q[axis]+sign
                if not filled(q[1],q[2],q[3]) then
                    local normal=axis*sign
                    local a={p[1],p[2],p[3]}; a[axis]=a[axis]+(sign>0 and 1 or 0)
                    edge(a,u,normal); edge(a,v,normal)
                    local b={a[1],a[2],a[3]}; b[v]=b[v]+1; edge(b,u,normal)
                    local c={a[1],a[2],a[3]}; c[u]=c[u]+1; edge(c,v,normal)
                end
            end
        end
    end
    local rows={}
    for _,e in pairs(edges) do if e.count==1 or e.crease then
        local u=e.axis%3+1; local v=u%3+1
        local key=e.axis..":"..e.p[u]..":"..e.p[v]
        local row=rows[key]
        if not row then row={axis=e.axis,p=e.p,values={}}; rows[key]=row end
        row.values[#row.values+1]=e.p[e.axis]
    end end
    job.edges={}
    for _,row in pairs(rows) do
        table.sort(row.values)
        local i=1
        while i<=#row.values do
            local start=row.values[i]; local finish=start+1; i=i+1
            while i<=#row.values and row.values[i]==finish do finish=finish+1; i=i+1 end
            local a={row.p[1],row.p[2],row.p[3]}; local b={a[1],a[2],a[3]}
            a[row.axis]=start; b[row.axis]=finish
            job.edges[#job.edges+1]={a=a,b=b}
        end
    end
    job.grid=nil; job.done=true
end
function C.prepare(rec)
    remember(rec)
    rec.crewJobs={}
    for _,box in ipairs(rec.boxes) do if box.category=="crew" and valid(box.shape)
        and not (box.crewDead and box.crewWire and box.crewWire.done) then
        local x,y,z=GetShapeSize(box.shape)
        -- Other/custom Crew models can fall back to boxes instead of causing
        -- unbounded sampling or drawing load. Installed Crew is only 68 voxels.
        if x*y*z>0 and x*y*z<=32768 then
            local count=GetShapeVoxelCount(box.shape)
            local key=x..":"..y..":"..z..":"..count
            local job=cache[box.shape]
            if not job or job.key~=key then
                job={shape=box.shape,key=key,n={x,y,z},scan=0,grid={}}
                cache[box.shape]=job
            end
            box.crewWire=job; rec.crewJobs[#rec.crewJobs+1]=job
        end
    end end
    for shape in pairs(cache) do if not valid(shape) then cache[shape]=nil end end
end
function C.step(rec)
    local budget=4096
    for _,job in ipairs(rec.crewJobs or {}) do
        if not job.done and valid(job.shape) then
            local n=job.n; local total=n[1]*n[2]*n[3]
            while job.scan<total and budget>0 do
                local i=job.scan
                local mat,_,_,_,_,entry=GetShapeMaterialAtIndex(job.shape,i%n[1],math.floor(i/n[1])%n[2],math.floor(i/(n[1]*n[2])))
                if (entry and entry~=0) or (entry==nil and mat and mat~="" and mat~="none") then job.grid[i]=true end
                job.scan=i+1; budget=budget-1
            end
            if job.scan==total then mesh(job) end
        end
        if budget==0 then break end
    end
end
function C.lines(box)
    local job=box.crewWire
    if not job or not job.done or #job.edges==0 or #job.edges>1800 then return nil end
    if box.crewLines then return box.crewLines end
    local basis={VecSub(box.points[2],box.points[1]),VecSub(box.points[3],box.points[1]),VecSub(box.points[5],box.points[1])}
    local function point(p)
        local out=Vec(box.points[1][1],box.points[1][2],box.points[1][3])
        for k=1,3 do out=VecAdd(out,VecScale(basis[k],p[k]/job.n[k])) end
        return out
    end
    box.crewLines={}
    for _,e in ipairs(job.edges) do box.crewLines[#box.crewLines+1]={a=point(e.a),b=point(e.b)} end
    return box.crewLines
end
