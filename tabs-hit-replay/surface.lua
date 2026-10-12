-- Read-only voxel contour reconstruction. Rasterized faces are temporary;
-- only silhouettes, part boundaries and creases are drawn, never filled faces.
ReplaySurface={}
local S=ReplaySurface
local W,H,PIXEL=464,236,1
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function valid(h) return h and h~=0 and IsHandleValid(h) end
local vehicleViews={}
function S.resetFraming() vehicleViews={} end
local function projection(rec)
    local key=rec.vehicle and rec.vehicle~=0 and rec.vehicle or nil
    if key and vehicleViews[key] then
        local saved=vehicleViews[key]
        return {c=saved.c,s=saved.s,scale=saved.scale,cx=saved.cx,cy=saved.cy}
    end
    local yaw=math.atan2(rec.direction[1],rec.direction[3])+0.75
    local v={c=math.cos(yaw),s=math.sin(yaw)}
    local loX,hiX,loY,hiY=math.huge,-math.huge,math.huge,-math.huge
    local function add(p)
        local x=p[1]*v.c-p[3]*v.s
        local y=-p[2]*.9+(p[1]*v.s+p[3]*v.c)*.43
        loX=math.min(loX,x); hiX=math.max(hiX,x); loY=math.min(loY,y); hiY=math.max(hiY,y)
    end
    for _,box in ipairs(rec.framingBoxes or rec.boxes) do for _,p in ipairs(box.points) do add(p) end end
    if loX==math.huge then
        -- No geometry: use a finite neutral view, but do not cache it.
        return {c=v.c,s=v.s,scale=30,cx=0,cy=0}
    end
    v.scale=math.min(422/math.max(1,hiX-loX),220/math.max(1,hiY-loY))
    v.cx=(loX+hiX)/2; v.cy=(loY+hiY)/2
    if key then
        -- Clear dead vehicles when a new one is encountered. Existing replay
        -- records own their view so F9 remains stable after deletion.
        for vehicle in pairs(vehicleViews) do if not valid(vehicle) then vehicleViews[vehicle]=nil end end
        vehicleViews[key]={c=v.c,s=v.s,scale=v.scale,cx=v.cx,cy=v.cy}
    end
    return v
end
function S.project(rec,p)
    local v=rec.surface.view
    local z=p[1]*v.s+p[3]*v.c
    return 244+(p[1]*v.c-p[3]*v.s-v.cx)*v.scale,
        182+(-p[2]*.9+z*.43-v.cy)*v.scale, p[2]*.43+z*.9
end
local function paintTriangle(job,a,b,c,tone,module)
    local function edge(p,q,x,y) return (q[1]-p[1])*(y-p[2])-(q[2]-p[2])*(x-p[1]) end
    local area=edge(a,b,c[1],c[2])
    if math.abs(area)<1e-8 then return end
    local x0=clamp(math.floor(math.min(a[1],b[1],c[1])),0,W-1)
    local x1=clamp(math.ceil(math.max(a[1],b[1],c[1])),0,W-1)
    local y0=clamp(math.floor(math.min(a[2],b[2],c[2])),0,H-1)
    local y1=clamp(math.ceil(math.max(a[2],b[2],c[2])),0,H-1)
    local layer=module and job.modules or job.shell
    for y=y0,y1 do for x=x0,x1 do
        local u=edge(b,c,x+.5,y+.5)/area
        local v=edge(c,a,x+.5,y+.5)/area
        local w=1-u-v
        if u>=-1e-7 and v>=-1e-7 and w>=-1e-7 then
            local z=u*a[3]+v*b[3]+w*c[3]
            local key=y*W+x+1
            local old=layer[key]
            if not old or z>old.z then layer[key]={z=z,tone=tone,owner=job.index} end
        end
    end end
end
local function face(rec,shape,axis,plane,u0,v0,u1,v1,sign)
    local job=rec.surface
    local axes={{2,3},{1,3},{1,2}}
    local u,v=axes[axis][1],axes[axis][2]
    local dims={shape.x,shape.y,shape.z}
    local function point(a,b)
        local t={0,0,0}; t[axis]=plane; t[u]=a; t[v]=b
        local p=shape.points[1]
        local out=Vec(p[1],p[2],p[3])
        for k=1,3 do out=VecAdd(out,VecScale(shape.basis[k],t[k]/dims[k])) end
        local x,y,z=S.project(rec,out)
        return {(x-12)/PIXEL,(y-64)/PIXEL,z}
    end
    local normal=VecScale(shape.basis[axis],sign/math.max(VecLength(shape.basis[axis]),1e-8))
    local light=clamp(.65+.3*(normal[1]*.3+normal[2]*.8+normal[3]*.4),.4,1)
    local shade=math.floor(light*7+.5)
    local base=shape.category=="ammo" and 16 or (shape.category=="module" and 32 or 0)
    local tone=base+shade
    local a,b,c,d=point(u0,v0),point(u1,v0),point(u1,v1),point(u0,v1)
    paintTriangle(job,a,b,c,tone,shape.category~=nil)
    paintTriangle(job,a,c,d,tone,shape.category~=nil)
    job.faces=job.faces+1
end
local function setupShape(job,shape)
    local quota=math.max(256,math.floor(240000/math.max(1,#job.shapes)))
    local stride=1
    while math.ceil(shape.x/stride)*math.ceil(shape.y/stride)*math.ceil(shape.z/stride)>quota do stride=stride+1 end
    if stride>1 then job.simplified=true end
    shape.stride=stride; shape.n={math.ceil(shape.x/stride),math.ceil(shape.y/stride),math.ceil(shape.z/stride)}
    shape.grid={}; shape.scan=0; shape.axis=1; shape.slice=0
    shape.basis={VecSub(shape.points[2],shape.points[1]),VecSub(shape.points[3],shape.points[1]),VecSub(shape.points[5],shape.points[1])}
    local eye=Vec(job.view.s*.9,.43,job.view.c*.9)
    shape.sign={}
    for k=1,3 do shape.sign[k]=VecDot(shape.basis[k],eye)>=0 and 1 or -1 end
end
local function occupied(shape,x,y,z)
    local n=shape.n
    if x<0 or y<0 or z<0 or x>=n[1] or y>=n[2] or z>=n[3] then return false end
    return shape.grid[(z*n[2]+y)*n[1]+x+1] or false
end
local function meshPlane(rec,shape)
    local axis=shape.axis
    local axes={{2,3},{1,3},{1,2}}
    local u,v=axes[axis][1],axes[axis][2]
    local nu,nv=shape.n[u],shape.n[v]
    local mask={}; local sign=shape.sign[axis]
    for j=0,nv-1 do for i=0,nu-1 do
        local p={0,0,0}; p[axis]=shape.slice; p[u]=i; p[v]=j
        if occupied(shape,p[1],p[2],p[3]) then
            p[axis]=p[axis]+sign
            if not occupied(shape,p[1],p[2],p[3]) then mask[j*nu+i+1]=true end
        end
    end end
    -- Merge adjacent exposed voxels into rectangles before projection.
    for j=0,nv-1 do for i=0,nu-1 do
        if mask[j*nu+i+1] then
            local width,height=1,1
            while i+width<nu and mask[j*nu+i+width+1] do width=width+1 end
            local extend=true
            while j+height<nv and extend do
                for k=0,width-1 do if not mask[(j+height)*nu+i+k+1] then extend=false; break end end
                if extend then height=height+1 end
            end
            for y=j,j+height-1 do for x=i,i+width-1 do mask[y*nu+x+1]=nil end end
            local dims={shape.x,shape.y,shape.z}; local step=shape.stride
            local plane=math.min(dims[axis],(shape.slice+(sign>0 and 1 or 0))*step)
            face(rec,shape,axis,plane,i*step,j*step,math.min(dims[u],(i+width)*step),math.min(dims[v],(j+height)*step),sign)
        end
    end end
    shape.slice=shape.slice+1
    if shape.slice>=shape.n[axis] then shape.axis=axis+1; shape.slice=0 end
    return nu*nv
end
local function color(tone)
    local base=math.floor(tone/16)
    if base==1 then return {1,.10,.12,1} end
    if base==2 then return {1,.52,.08,1} end
    return {.60,.76,.84,.65}
end
local function finish(job)
    -- Depth buffers keep rear armor from cluttering the drawing. Modules have
    -- their own layer so their contours remain visible through the shell.
    local pixels={}
    local function outlines(layer)
        for y=0,H-1 do for x=0,W-1 do
            local key=y*W+x+1
            local p=layer[key]
            if p then
                local left=x>0 and layer[key-1] or nil
                local right=x<W-1 and layer[key+1] or nil
                local up=y>0 and layer[key-W] or nil
                local down=y<H-1 and layer[key+W] or nil
                -- Silhouette on all sides; interior boundaries on one side
                -- only, avoiding a doubled stroke on coplanar part seams.
                local function different(q,delta,room)
                    if not q then return false end
                    if q.owner~=p.owner then return true end
                    if q.tone==p.tone or not room then return false end
                    -- Ignore alternating voxel stair faces on curved/sloped
                    -- surfaces; keep creases between broad, stable faces.
                    for k=1,2 do
                        local a,b=layer[key-k*delta],layer[key+(k+1)*delta]
                        if not a or not b or a.owner~=p.owner or b.owner~=p.owner
                            or a.tone~=p.tone or b.tone~=q.tone then return false end
                    end
                    return true
                end
                if not left or not right or not up or not down
                    or different(right,1,x>=2 and x<W-3) or different(down,W,y>=2 and y<H-3) then
                    pixels[key]=math.floor(p.tone/16)*16
                end
            end
        end end
    end
    outlines(job.shell); outlines(job.modules)
    job.runs={}
    local previous={}
    for y=0,H-1 do
        local current={}
        local x=0
        while x<W do
            local key=pixels[y*W+x+1]; local start=x
            x=x+1
            while x<W and pixels[y*W+x+1]==key do x=x+1 end
            if key then
                local id=start..":"..(x-start)..":"..key
                local run=previous[id]
                if run then run.h=run.h+PIXEL
                else
                    run={x=12+start*PIXEL,y=64+y*PIXEL,w=(x-start)*PIXEL,h=PIXEL,color=color(key)}
                    job.runs[#job.runs+1]=run
                end
                current[id]=run
            end
        end
        previous=current
    end
    job.shell=nil; job.modules=nil; job.shapes=nil; job.done=true
end
-- Initial wire view needs only the same projection, with no voxel sampling.
function S.beginOutline(rec)
    rec.surface={view=projection(rec)}
    rec.surfaceShapes=nil
end
function S.begin(rec)
    rec.surface={view=projection(rec),shapes=rec.surfaceShapes or {},index=1,reads=0,faces=0,shell={},modules={}}
    rec.surface.total=#rec.surface.shapes
    rec.surfaceShapes=nil
end
function S.step(rec)
    local job=rec.surface
    if not job or job.done then return end
    local reads,cells=0,0
    while job.index<=#job.shapes do
        local shape=job.shapes[job.index]
        if not valid(shape.shape) then job.index=job.index+1; job.missing=true
        else
            if not shape.grid then setupShape(job,shape) end
            local n=shape.n; local count=n[1]*n[2]*n[3]
            while shape.scan<count and reads<8192 do
                local k=shape.scan; local x=k%n[1]; local y=math.floor(k/n[1])%n[2]; local z=math.floor(k/(n[1]*n[2]))
                local stride=shape.stride
                local ix=math.min(shape.x-1,x*stride+math.floor(stride/2))
                local iy=math.min(shape.y-1,y*stride+math.floor(stride/2))
                local iz=math.min(shape.z-1,z*stride+math.floor(stride/2))
                local mat,_,_,_,_,entry=GetShapeMaterialAtIndex(shape.shape,ix,iy,iz)
                if (entry and entry~=0) or (entry==nil and mat and mat~="" and mat~="none") then shape.grid[k+1]=true end
                shape.scan=k+1; reads=reads+1; job.reads=job.reads+1
            end
            if shape.scan<count then return end
            while shape.axis<=3 and cells<12000 do cells=cells+meshPlane(rec,shape) end
            if shape.axis<=3 then return end
            shape.grid=nil; job.index=job.index+1
            if reads>=8192 or cells>=12000 then return end
        end
    end
    finish(job)
end
function S.draw(rec)
    local job=rec.surface
    if not job or not job.done then return end
    for _,run in ipairs(job.runs) do
        local c=run.color
        UiPush(); UiTranslate(run.x,run.y); UiColor(c[1],c[2],c[3],c[4]); UiRect(run.w,run.h); UiPop()
    end
end
