#include <Timer.h>
#include "../../includes/CommandMsg.h"
#include "../../includes/packet.h"

configuration RoutingC {
    provides interface Routing;
}

implementation {
    components RoutingP;
    Routing = RoutingP;

    components new SimpleSendC(AM_PACK);
    RoutingP.Sender -> SimpleSendC;

    components FloodC;
    RoutingP.Flood -> FloodC;

    components NDiscC;
    RoutingP.NDisc -> NDiscC;

    components new TimerMilliC() as RoutingTimer;
    RoutingP.Timer -> RoutingTimer;

    components new HashmapC(uint16_t, 20);
    RoutingP.Hashmap -> HashmapC;

    components IPC;
    RoutingP.IP -> IPC;
}