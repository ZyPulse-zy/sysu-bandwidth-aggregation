-- Equal account scheduling for NEW connections only; retain health hysteresis and recovery ramp.
local json=require('luci.jsonc')
local nixio=require('nixio')
local root='/root/router-project'
local dir='/tmp/router-project-health'
local function read(p) local f=io.open(p);if not f then return nil end;local v=f:read('*a');f:close();return v end
local function write(p,v) local f=assert(io.open(p..'.new','w'));f:write(v);f:close();assert(os.rename(p..'.new',p)) end
local function number(p) return tonumber(read(p)) or 0 end
local function command(s) local p=io.popen(s);local v=p:read('*a');p:close();return v end
local function median(a) if #a==0 then return 0 end;local b={};for i,v in ipairs(a)do b[i]=v end;table.sort(b);return b[math.floor((#b+1)/2)] end
local function quote(s) return "'"..s:gsub("'","'\\''").."'" end
local function log(v)
 local p=dir..'/telemetry.jsonl';local f=io.open(p,'a');if f then f:write(json.stringify(v),'\n');local size=f:seek('end');f:close();if size>2097152 then os.rename(p,p..'.1') end end
end
assert(os.execute('mkdir -p '..dir..'; chmod 700 '..dir)==0)
local state={};local previousOwners={};local previousSignature='';local previousWeights={};local lastMapAt=-60;local first=true
for n=1,5 do state[n]={wan=n,healthy=false,ramp=0,goodRounds=0,badRounds=0,baseline={},jitter=0,loss=0,observedPeakDown=0,observedPeakUp=0} end
while true do
 local start=tonumber((read('/proc/uptime') or '0'):match('^[%d.]+')) or 0
 local rc=os.execute('sh '..root..'/scripts/health-probes.sh')
 local weights={};local healthy={};local report={uptime=start,mode='equal-per-connection',bucketCount=300,baseWeights={1,1,1,1,1},wan={}}
 local counts={0,0,0,0,0}
 local ct=io.open('/proc/net/nf_conntrack')
 if ct then for line in ct:lines() do local m=tonumber(line:match('mark=(%d+)'));if m then local n=math.floor(m/65536)%256;if n>=1 and n<=5 then counts[n]=counts[n]+1 end end end;ct:close() end
 for n=1,5 do
  local s=state[n];local p=json.parse(read(dir..'/probe'..n..'.json') or '{}') or {}
  local good=rc==0 and p.present==1 and ((p.good or 0)>=2 or p.httpFallback==1)
  if good then s.goodRounds=s.goodRounds+1;s.badRounds=0 else s.goodRounds=0;s.badRounds=s.badRounds+1 end
  if p.present~=1 or s.badRounds>=3 then s.healthy=false;s.ramp=0 end
  if good and (first or s.goodRounds>=2) then
   if not s.healthy then s.healthy=true;s.ramp=first and 10 or 1;s.recoveredAt=start
   elseif s.ramp<10 then s.ramp=s.ramp+1 end
  end
  local delays={};local rtts={}
  for k,rtt in ipairs(p.rtts or {}) do if rtt>0 then
   local b=s.baseline[k] or rtt;b=math.min(rtt,b*.999+rtt*.001);s.baseline[k]=b
   rtts[#rtts+1]=rtt;delays[#delays+1]=math.max(0,rtt-b)
  end end
  local current=median(rtts)
  if current>0 and s.lastRtt then s.jitter=s.jitter*.8+math.abs(current-s.lastRtt)*.2 end
  if current>0 then s.lastRtt=current end
  s.loss=s.loss*.8+(1-(p.good or 0)/3)*.2
  local rx=number('/sys/class/net/rpwan'..n..'/statistics/rx_bytes')
  local tx=number('/sys/class/net/rpwan'..n..'/statistics/tx_bytes')
  local dt=s.at and start-s.at or 0
  local down=dt>0 and math.max(0,rx-(s.rx or rx))*8/dt/1000000 or 0
  local up=dt>0 and math.max(0,tx-(s.tx or tx))*8/dt/1000000 or 0
  s.at=start;s.rx=rx;s.tx=tx;s.observedPeakDown=math.max(s.observedPeakDown,down);s.observedPeakUp=math.max(s.observedPeakUp,up)
  -- Equal normal share; only health and gradual recovery affect eligibility/share.
  weights[n]=s.healthy and s.ramp*10 or 0
  if weights[n]>0 then healthy[#healthy+1]=tostring(n*65536) end
  report.wan[n]={wan=n,healthy=s.healthy,weight=weights[n],goodRounds=s.goodRounds,badRounds=s.badRounds,rttMs=current,baselineRttMs=median(s.baseline),queueDelayMs=median(delays),jitterMs=s.jitter,icmpLossEwma=s.loss,httpFallback=p.httpFallback,downMbps=down,upMbps=up,observedPeakDownMbps=s.observedPeakDown,observedPeakUpMbps=s.observedPeakUp,activeConnections=counts[n],capacityMeasured=false,capacityScope='equal-account-policy-no-capacity-inference',recoveryProgress=s.ramp/10}
  for _,d in ipairs({{'up','rpwan'..n},{'down','rpifb'..n}})do
   local q=json.parse(command('tc -j qdisc show dev '..d[2]..' 2>/dev/null')) or {}
   for _,entry in ipairs(q)do if entry.kind=='cake' and entry.root then report.wan[n][d[1]..'ShaperMbps']=(entry.options.bandwidth or 0)*8/1000000 end end
  end
  report.wan[n].shaperInstalled=report.wan[n].upShaperMbps~=nil and report.wan[n].downShaperMbps~=nil
 end
 local sum=0;for _,w in ipairs(weights) do sum=sum+w end
 local target={};local remainders={};local assigned=0
 for n=1,5 do local exact=sum>0 and weights[n]*300/sum or 0;target[n]=math.floor(exact);assigned=assigned+target[n];remainders[n]=exact-target[n] end
 if sum>0 then for _=assigned+1,300 do local best=1;for n=2,5 do if remainders[n]>remainders[best] then best=n end end;target[best]=target[best]+1;remainders[best]=-1 end end
 local owners={};local retained={0,0,0,0,0};local free={}
 for b=0,299 do local n=previousOwners[b] or b%5+1;if retained[n]<target[n] then owners[b]=n;retained[n]=retained[n]+1 else free[#free+1]=b end end
 for _,b in ipairs(free) do local best=1;for n=2,5 do if target[n]-retained[n]>target[best]-retained[best] then best=n end end;if target[best]>retained[best] then owners[b]=best;retained[best]=retained[best]+1 end end
 local entries={};for b=0,299 do if owners[b] then entries[#entries+1]=b..' : jump mark_w'..owners[b] end end
 local signature=table.concat(weights,',')
 if signature~=previousSignature or start-lastMapAt>60 then
  local script='flush map inet rp_pbr buckets\nflush set inet rp_pbr healthy\n'
  for n=1,5 do if weights[n]==0 then script=script..'flush set inet rp_pbr sticky_w'..n..'\n' end end
  if #entries>0 then script=script..'add element inet rp_pbr buckets { '..table.concat(entries,', ')..' }\n' end
  if #healthy>0 then script=script..'add element inet rp_pbr healthy { '..table.concat(healthy,', ')..' }\n' end
  write(dir..'/update.nft',script)
  if os.execute('nft -c -f '..dir..'/update.nft >/dev/null 2>&1 && nft -f '..dir..'/update.nft')==0 then
   previousSignature=signature;previousOwners=owners;previousWeights=weights;lastMapAt=start;report.mapUpdated=true
  else report.mapUpdateError=true end
 end
 -- Preserve local-output primary while healthy; replace only when it is no longer eligible.
 local route=command('ip -4 route show table main default')
 local primary=tonumber(route:match('dev rpwan([1-5])'))
 if not primary or weights[primary]==0 then
  local chosen
  for n=1,5 do if weights[n]>0 then chosen=n;break end end
  if chosen then
   local st=json.parse(command('ubus call network.interface.wan'..chosen..' status 2>/dev/null')) or {}
   local addr=st['ipv4-address'] and st['ipv4-address'][1] and st['ipv4-address'][1].address
   local gw=command('ip -4 route show table '..(100+chosen)..' default'):match('default via ([%d.]+)')
   if addr and addr:match('^[%d.]+$') and gw then os.execute('ip -4 route replace default via '..gw..' dev rpwan'..chosen..' onlink src '..addr..' metric 9000') end
  elseif not route:match('blackhole') then os.execute('ip -4 route replace blackhole default metric 9000') end
 end
 -- luci.jsonc renders repeated table references as null. Snapshot applied weights
 -- separately and distinguish a requested distribution from a successful update.
 report.requestedWeights=weights;report.weights={}
 for n=1,5 do
  report.weights[n]=previousWeights[n] or 0
  report.wan[n].requestedWeight=weights[n]
  report.wan[n].weight=report.weights[n]
 end
 write(dir..'/status.json',json.stringify(report));log(report)
 first=false
 nixio.nanosleep(5)
end
