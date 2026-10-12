-- Data-only length-prefixed transport. Never evaluates code from the registry.
WTRWire={}
function WTRWire.encode(value)
    local parts={}
    local function put(v)
        local t=type(v)
        if t=="table" then
            local n=0; for _ in pairs(v) do n=n+1 end
            parts[#parts+1]="t"..n..":"
            for k,item in pairs(v) do put(k); put(item) end
        elseif t=="boolean" then parts[#parts+1]=v and "y" or "n"
        else
            local s=t=="number" and string.format("%.9g",v) or tostring(v)
            parts[#parts+1]=(t=="number" and "d" or "s")..#s..":"..s
        end
    end
    put(value); return table.concat(parts)
end
function WTRWire.decode(data)
    if #data>1000000 then return nil end
    local cursor,nodes=1,0
    local function get(depth)
        nodes=nodes+1
        assert(depth<12 and nodes<100000)
        local tag=data:sub(cursor,cursor); cursor=cursor+1
        if tag=="y" then return true elseif tag=="n" then return false end
        assert(tag=="t" or tag=="d" or tag=="s")
        local stop=assert(data:find(":",cursor,true))
        local n=assert(tonumber(data:sub(cursor,stop-1)))
        assert(n>=0 and n<=1000000 and n==math.floor(n)); cursor=stop+1
        if tag=="t" then
            assert(n<=10000)
            local out={}
            for i=1,n do
                local k=get(depth+1); assert(type(k)=="string" or type(k)=="number")
                out[k]=get(depth+1)
            end
            return out
        end
        assert(cursor+n-1<=#data)
        local s=data:sub(cursor,cursor+n-1); cursor=cursor+n
        if tag=="s" then return s end
        local v=assert(tonumber(s)); assert(v==v and math.abs(v)<math.huge); return v
    end
    local ok,value=pcall(get,0)
    if ok and cursor==#data+1 and type(value)=="table" then return value end
    return nil
end
