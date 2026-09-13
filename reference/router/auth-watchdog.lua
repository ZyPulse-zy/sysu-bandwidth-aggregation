local json=require('luci.jsonc');local nixio=require('nixio')
local root='/root/router-project';local state={}
local function read(p)local f=io.open(p);if not f then return ''end;local v=f:read('*a');f:close();return v end
local function cmd(s)local p=io.popen(s);local v=p:read('*a');p:close();return v end
local function write(p,v)local f=assert(io.open(p..'.new','w'));f:write(v);f:close();os.rename(p..'.new',p)end
local function log(e)
 local p='/tmp/router-project-auth-recovery.jsonl';local f=io.open(p,'a');f:write(json.stringify(e),'\n');local sz=f:seek('end');f:close();if sz>131072 then os.rename(p,p..'.1')end
end
for n=1,5 do state[n]={attempts={},last=0,badSince=nil,stoppedSince=nil}end
while true do
 local now=tonumber(read('/proc/uptime'):match('^[%d.]+')) or 0
 local h=json.parse(read('/tmp/router-project-health/status.json')) or {}
 local sv=json.parse(cmd("ubus call service list '{\"name\":\"router-project-minieap\"}'")) or {}
 local instances=sv['router-project-minieap'] and sv['router-project-minieap'].instances or {}
 local healthy=0;for _,w in ipairs(h.wan or {})do if w.healthy then healthy=healthy+1 end end
 local carrier=read('/sys/class/net/wan/carrier'):match('1')~=nil
 for n=1,5 do
  local s=state[n];local inst=instances['wan'..n] or {};local pid=tonumber(inst.pid)
  local enabled=io.open(root..'/policy/wan'..n..'.enabled');if enabled then enabled:close()end
  local fresh=h.uptime and now-h.uptime<25
  local good=fresh and h.wan and h.wan[n] and h.wan[n].healthy
  local stopped=pid and read('/proc/'..pid..'/stat'):match('%) ([Tt]) ')~=nil
  if not enabled or not carrier or now<120 or not fresh then s.badSince=nil;s.stoppedSince=nil
  else
   if stopped then s.stoppedSince=s.stoppedSince or now else s.stoppedSince=nil end
   if good then s.badSince=nil else s.badSince=s.badSince or now end
   local reason
   if s.stoppedSince and now-s.stoppedSince>=20 then reason='auth-process-stopped'
   elseif s.badSince and now-s.badSince>=120 and healthy>=3 then reason='isolated-health-failure-120s' end
   local recent={};for _,t in ipairs(s.attempts)do if now-t<3600 then recent[#recent+1]=t end end;s.attempts=recent
   local cooldown=math.min(900,120*2^#recent)
   if reason and #recent<3 and now-s.last>=cooldown then
    s.last=now;s.attempts[#s.attempts+1]=now
    local rc=os.execute('sh '..root..'/scripts/auth-recover.sh '..n..' >/tmp/router-project-auth-recover-'..n..'.log 2>&1')
    log({uptime=now,wan=n,reason=reason,result=rc,attemptsLastHour=#s.attempts})
    s.badSince=nil;s.stoppedSince=nil
   end
  end
 end
 write('/tmp/router-project-auth-watchdog.json',json.stringify({uptime=now,wan=state}))
 nixio.nanosleep(10)
end
