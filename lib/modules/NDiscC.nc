#include <Timer.h>
#include "../../includes/CommandMsg.h"
#include "../../includes/packet.h"


configuration NDiscC {
    provides interface NDisc;
}

implementation {
    components NDiscP;
    NDisc = NDiscP;

    components new SimpleSendC(AM_PACK);
    NDiscP.Sender -> SimpleSendC;

    components new TimerMilliC() as NeighborTimer;
    NDiscP.Timer -> NeighborTimer;

    // Use data structure for neighbor list
    components new HashmapC(uint32_t, 20) as HashMap;
    NDiscP.Hashmap -> HashMap;

    components RoutingC;
    NDiscP.Routing -> RoutingC;
}

