#include "DataMsg.h"

configuration MulticastAppC {
}

implementation {
  components MulticastC, MainC, ActiveMessageC, RandomC, LocalTimeMilliC;
  components CollectionC as Collector;
  components new CollectionSenderC(AM_DATAMSG);
  components new TimerMilliC() as TimerColor;
  components new TimerMilliC() as TimerData;
  components new TimerMilliC() as TimerReset;
  components new TimerMilliC() as ReactiveColor;
  components new TimerMilliC() as CtpRetransmit;
  components new AMSenderC(AM_DATAMSG);
  components new AMReceiverC(AM_DATAMSG);
  components new QueueC(DataMsg, AM_DATAMSG) as DataQueue;
  components new QueueC(ResetMsg, AM_DATAMSG) as ResetQueue;
  components new TimerMilliC() as AMRetransmit;
  
  MulticastC.Boot -> MainC.Boot;
  MulticastC.RadioControl -> ActiveMessageC;
  MulticastC.RootControl -> Collector;
  MulticastC.RoutingControl -> Collector;
  MulticastC.Random -> RandomC;
  MulticastC.LocalTime -> LocalTimeMilliC; 
  
  MulticastC.CtpInfo -> Collector;
  MulticastC.CtpSend -> CollectionSenderC;
  MulticastC.CtpReceive -> Collector.Receive[AM_DATAMSG];
  MulticastC.CtpForward -> Collector.Intercept[AM_DATAMSG];
  MulticastC.TimerColor -> TimerColor;
  MulticastC.TimerData -> TimerData;
  MulticastC.TimerReset -> TimerReset;
  MulticastC.ReactiveColor -> ReactiveColor;
  MulticastC.CtpRetransmit -> CtpRetransmit;
  
  MulticastC.Packet -> AMSenderC;
  MulticastC.AMSend -> AMSenderC;
  MulticastC.AMReceive -> AMReceiverC;
  MulticastC.DataQueue -> DataQueue;
  MulticastC.ResetQueue -> ResetQueue;
  MulticastC.AMRetransmit -> AMRetransmit;
}