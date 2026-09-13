local j=require('luci.jsonc');local nixio=require('nixio')
local function read(p)local f=io.open(p);if not f then return nil end;local s=f:read('*a');f:close();return s:gsub('%s+','')end
local function apply()
 local r={epoch=os.time(),profile='physical-e',scope={'wan','lan4'},expected=16,readable=0,changed=0,errors={},values={}}
 for _,dev in ipairs(r.scope)do
  for _,kind in ipairs(dev:match('^rpwan')and{'rx'}or{'rx','tx'})do for n=0,(dev:match('^rpwan')and 0 or 3)do
   local file='/sys/class/net/'..dev..'/queues/'..kind..'-'..n..'/'..(kind=='rx'and'rps_cpus'or'xps_cpus')
   local want=kind=='rx'and(dev=='wan'and'e'or(dev=='lan4'and'f'or'e'))or({'1','2','4','8'})[n+1];local v=read(file)
   if v then
    r.readable=r.readable+1
    if tonumber(v,16)~=tonumber(want,16)then local f,e=io.open(file,'w');if f then local ok,err=f:write(want..'\n');f:close();if ok then r.changed=r.changed+1 else r.errors[#r.errors+1]=file..': '..tostring(err)end else r.errors[#r.errors+1]=file..': '..tostring(e)end end
    local actual=read(file);r.values[file]=actual;if tonumber(actual,16)~=tonumber(want,16)then r.errors[#r.errors+1]=file..': readback mismatch'end
   else r.errors[#r.errors+1]=file..': unavailable'end
  end end
 end
 local f=assert(io.open('/tmp/router-project-steering.json.new','w'));f:write(j.stringify(r));f:close();os.rename('/tmp/router-project-steering.json.new','/tmp/router-project-steering.json')
 return #r.errors==0 and r.readable==r.expected
end
if arg[1]=='once'then os.exit(apply()and 0 or 1)end
while true do apply();nixio.nanosleep(5)end
