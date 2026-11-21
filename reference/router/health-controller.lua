-- Equal account scheduling for NEW connections only; retain health hysteresis and recovery ramp.
local json=require('luci.jsonc')
local nixio=require('nixio')
local fs=require('nixio.fs')
local nativeSource='/usr/lib/athena-dorm-native'
local root='/root/router-project'
local enabled6=io.open(root..'/policy/wan6.enabled');local wanCount=enabled6 and 6 or 5;if enabled6 then enabled6:close()end
local dir='/tmp/router-project-health'
local gameControl=dofile('/usr/lib/athena-dorm-native/game_wan6_control.lua').runtime()
local nativeRecovery=dofile('/usr/lib/athena-dorm-native/native_recovery.lua').runtime()
local function read(p,cap) local f=io.open(p);if not f then return nil end;local v=f:read((cap or 65536)+1);f:close();if not v or #v>(cap or 65536)then return nil end;return v end
local function write(p,v) local f=assert(io.open(p..'.new','w'));f:write(v);f:close();assert(os.rename(p..'.new',p)) end
local function number(p) return tonumber(read(p)) or 0 end
local function median(a) if #a==0 then return 0 end;local b={};for i,v in ipairs(a)do b[i]=v end;table.sort(b);return b[math.floor((#b+1)/2)] end
local function quote(s) return "'"..s:gsub("'","'\\''").."'" end
local function now()return assert(tonumber(assert(read('/proc/uptime')):match('^[%d.]+')))end
local function finite(v)return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge end
local boot=assert(read('/proc/sys/kernel/random/boot_id')):match('%S+')
local process=dofile(nativeSource..'/process_control.lua').new(nativeSource,nixio,read,now)
local collector=dofile(nativeSource..'/collector.lua')
local queries={}
local function command(s)
 local began=now();local ok,body,code=pcall(process.command,s,2000)
 queries[#queries+1]={seconds=now()-began,exitCode=ok and code or nil,ok=ok and code==0}
 return ok and code==0 and body or nil
end
local function budgetCurrent(b,at)
 if type(b)~='table'or b.version~=1 or b.source~='software-cake'or b.boot~=boot or b.wanCount~=wanCount or b.complete~=true
  or not finite(b.startedAtUptime)or not finite(b.finishedAtUptime)or b.startedAtUptime<0
  or b.finishedAtUptime<b.startedAtUptime or b.finishedAtUptime-b.startedAtUptime>2.75
  or at<b.finishedAtUptime or at-b.startedAtUptime>=6 or type(b.values)~='table'then return false end
 for _,direction in ipairs{'up','down'}do
  local values=b.values[direction];if type(values)~='table'or #values~=wanCount then return false end
  for w=1,wanCount do if not finite(values[w])or values[w]<1000 or values[w]>200000 then return false end end
 end
 return true
end
local function log(v)
 local p=dir..'/telemetry.jsonl';local f=io.open(p,'a');if f then f:write(json.stringify(v),'\n');local size=f:seek('end');f:close();if size>2097152 then os.rename(p,p..'.1') end end
end
assert(os.execute('mkdir -p '..dir..'; chmod 700 '..dir)==0)
local state={};local previousOwners={};local previousSignature='';local previousWeights={};local lastMapAt=-60;local first=true
local session=assert(read('/proc/sys/kernel/random/boot_id')):match('%S+')..':'..nixio.getpid()..':'..now();local round=0
for n=1,wanCount do state[n]={wan=n,healthy=false,ramp=0,goodRounds=0,badRounds=0,baseline={},jitter=0,loss=0,observedPeakDown=0,observedPeakUp=0} end
while true do
 local start=now();round=round+1;local probeRound=session..':'..round;queries={}
 local rc=os.execute('sh '..root..'/scripts/health-probes.sh '..quote(probeRound))
 local weights={};local healthy={};local report={uptime=start,mode='equal-per-connection',bucketCount=300,dedicatedWan6=true,baseWeights={1,1,1,1,1},wan={}}
 -- Connection counts are diagnostic, never routing input. Read the global
 -- kernel scalar rather than scanning every tuple again in the health owner.
 report.connectionCounts={source='nf_conntrack_count',total=tonumber(read('/proc/sys/net/netfilter/nf_conntrack_count',128)),perWanAvailable=false}
 local native=json.parse(read('/tmp/athena-dorm-native/status.json',524288)or'')or{}
 if type(native)~='table'then native={}end
 local softwareIdle=not fs.stat('/tmp/athena-dorm-native/lock')and not fs.stat('/sys/module/athena_ecm_gate')
  and not fs.stat('/sys/module/athena_nss_receipts')and(native.boot~=boot or native.phase=='restored'and native.running==false and native.rollbackConfirmed==true)
 local budget=json.parse(read('/tmp/athena-dorm-native/software-budgets.json')or'')
 local budgetSource='native-budget-reader'
 if not budgetCurrent(budget,now())and softwareIdle then
  budgetSource='health-software-fallback'
  local ok,value=pcall(collector.software_budgets,wanCount,nil,process.command)
  budget=ok and value or nil;if budget then budget.boot=boot end
 end
 local budgetReady=budgetCurrent(budget,now())
 if type(budget)~='table'then budget=nil end
 report.budgetObservation={available=budgetReady,source=budgetSource,sequence=budget and budget.sequence,
  startedAtUptime=budget and budget.startedAtUptime,finishedAtUptime=budget and budget.finishedAtUptime}
 -- Collect diagnostics first, then assess every probe at the same completion
 -- time. Slow tc reads cannot make an old probe appear current at publication.
 local samples={}
 for n=1,wanCount do
  local sample={probe=json.parse(read(dir..'/probe'..n..'.json')or'{}')or{},rx=number('/sys/class/net/rpwan'..n..'/statistics/rx_bytes'),tx=number('/sys/class/net/rpwan'..n..'/statistics/tx_bytes')}
  if budgetReady then for _,direction in ipairs{'up','down'}do sample[direction..'ShaperMbps']=budget.values[direction][n]/1000 end end
  -- The software WAN6 gate still requires its complete, current CAKE options.
  -- Query only these two queues after confirmed native absence; a rate-only
  -- shared snapshot must never stand in for that separate contract.
  if n==6 and softwareIdle then
   sample.softwareQueues={probeRound=probeRound,startedAtUptime=now()}
   for _,d in ipairs({{'up','rpwan6'},{'down','rpifb6'}})do
    sample.softwareQueues[d[1]]=json.parse(command('tc -j qdisc show dev '..d[2]..' 2>/dev/null')or'')
   end
   sample.softwareQueues.finishedAtUptime=now()
  end
  samples[n]=sample
 end
 local completed=now();report.probeRound=probeRound;report.collectedAtUptime=completed
 budgetReady=budgetCurrent(budget,completed);report.budgetObservation.available=budgetReady
 if not budgetReady then for _,sample in ipairs(samples)do sample.upShaperMbps=nil;sample.downShaperMbps=nil end end
 for n=1,wanCount do
  local s=state[n];local sample=samples[n];local p=type(sample.probe)=='table' and sample.probe or {}
  local probeFresh=rc==0 and p.round==probeRound and finite(p.startedAtUptime) and finite(p.finishedAtUptime)
   and p.startedAtUptime>=start and p.finishedAtUptime>=p.startedAtUptime and completed>=p.finishedAtUptime and completed-p.finishedAtUptime<6
  local valid=(p.present==0 or p.present==1) and finite(p.good) and p.good>=0 and p.good<=3 and p.good==math.floor(p.good)
   and (p.httpFallback==0 or p.httpFallback==1) and type(p.rtts)=='table' and #p.rtts==3
  if valid then for _,v in ipairs(p.rtts)do if not finite(v)or v<0 then valid=false end end end
  probeFresh=probeFresh and valid or false
  local good=probeFresh and p.present==1 and (p.good>=2 or p.httpFallback==1)
  if good then s.goodRounds=s.goodRounds+1;s.badRounds=0 else s.goodRounds=0;s.badRounds=s.badRounds+1 end
  if p.present~=1 or s.badRounds>=3 then s.healthy=false;s.ramp=0 end
  if good and (first or s.goodRounds>=2) then
   if not s.healthy then s.healthy=true;s.ramp=first and 10 or 1;s.recoveredAt=start
   elseif s.ramp<10 then s.ramp=s.ramp+1 end
  end
  local delays={};local rtts={}
  for k,rtt in ipairs(probeFresh and p.rtts or {}) do if rtt>0 then
   local b=s.baseline[k] or rtt;b=math.min(rtt,b*.999+rtt*.001);s.baseline[k]=b
   rtts[#rtts+1]=rtt;delays[#delays+1]=math.max(0,rtt-b)
  end end
  local current=median(rtts)
  if current>0 and s.lastRtt then s.jitter=s.jitter*.8+math.abs(current-s.lastRtt)*.2 end
  if current>0 then s.lastRtt=current end
  s.loss=s.loss*.8+(1-(probeFresh and p.good or 0)/3)*.2
  local rx=sample.rx;local tx=sample.tx
  local dt=s.at and start-s.at or 0
  local down=dt>0 and math.max(0,rx-(s.rx or rx))*8/dt/1000000 or 0
  local up=dt>0 and math.max(0,tx-(s.tx or tx))*8/dt/1000000 or 0
  s.at=start;s.rx=rx;s.tx=tx;s.observedPeakDown=math.max(s.observedPeakDown,down);s.observedPeakUp=math.max(s.observedPeakUp,up)
  -- Equal normal share; only health and gradual recovery affect eligibility/share.
  weights[n]=s.healthy and s.ramp*10 or 0
  if n<=5 and weights[n]>0 then healthy[#healthy+1]=tostring(n*65536) end
  report.wan[n]={wan=n,healthy=s.healthy,weight=weights[n],goodRounds=s.goodRounds,badRounds=s.badRounds,rttMs=current,baselineRttMs=median(s.baseline),queueDelayMs=median(delays),jitterMs=s.jitter,icmpLossEwma=s.loss,httpFallback=p.httpFallback,downMbps=down,upMbps=up,observedPeakDownMbps=s.observedPeakDown,observedPeakUpMbps=s.observedPeakUp,activeConnectionsAvailable=false,capacityMeasured=false,capacityScope='equal-account-policy-no-capacity-inference',recoveryProgress=s.ramp/10}
  report.wan[n].probeFresh=probeFresh;report.wan[n].probeHealthy=good
  report.wan[n].probeStartedAtUptime=p.startedAtUptime;report.wan[n].probeFinishedAtUptime=p.finishedAtUptime
  if n==6 then report.wan[n].probeRound=probeRound;report.wan[n].softwareQueues=sample.softwareQueues end
  report.wan[n].upShaperMbps=sample.upShaperMbps;report.wan[n].downShaperMbps=sample.downShaperMbps
  report.wan[n].shaperInstalled=report.wan[n].upShaperMbps~=nil and report.wan[n].downShaperMbps~=nil
 end
 local sum=0;for n=1,5 do sum=sum+weights[n] end
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
 local primary=route and tonumber(route:match('dev rpwan([1-5])'))
 if route and(not primary or weights[primary]==0)then
  local chosen
  for n=1,5 do if weights[n]>0 then chosen=n;break end end
  if chosen then
   local st=json.parse(command('ubus call network.interface.wan'..chosen..' status 2>/dev/null')or'') or {}
   local addr=st['ipv4-address'] and st['ipv4-address'][1] and st['ipv4-address'][1].address
   local accountRoute=command('ip -4 route show table '..(100+chosen)..' default')
   local gw=accountRoute and accountRoute:match('default via ([%d.]+)')
   if addr and addr:match('^[%d.]+$') and gw then os.execute('ip -4 route replace default via '..gw..' dev rpwan'..chosen..' onlink src '..addr..' metric 9000') end
  elseif not route:match('blackhole') then os.execute('ip -4 route replace blackhole default metric 9000') end
 end
 -- luci.jsonc renders repeated table references as null. Snapshot applied weights
 -- separately and distinguish a requested distribution from a successful update.
 report.requestedWeights=weights;report.weights={}
 for n=1,wanCount do
  report.weights[n]=previousWeights[n] or 0
  report.wan[n].requestedWeight=weights[n]
  report.wan[n].weight=report.weights[n]
 end
 -- Never publish WAN6 game eligibility from a stale cached native status.
 -- Rule installation and reviewed exclusion configuration remain a separate stage.
 if read(root..'/policy/wan6-game.enabled') then
  local ok,result=pcall(gameControl.tick,report.wan[6])
  report.wan6GameReady=ok and result.ready==true or false
  report.wan6GamePolicy=ok and result or {error='game-only-policy-update-refused'}
  if not ok then report.wan6GameGateError=true end
 end
 local recoveryOk,recoveryState=pcall(nativeRecovery.tick,report.wan,budgetReady and budget or nil)
 report.nssRecovery=recoveryOk and recoveryState or {enabled=true,reason='recovery-check-failed'}
 report.readQueries=queries
 write(dir..'/status.json',json.stringify(report));log(report)
 first=false
 nixio.nanosleep(5)
end
