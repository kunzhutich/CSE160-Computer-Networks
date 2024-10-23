
// #include <Timer.h>
// #include "../../includes/CommandMsg.h"
// #include "../../includes/packet.h"
// configuration NDiscC {
//     provides interface NDisc;
// }


// implementation {
//     components NDiscP;
//     NDisc = NDiscP;
//     components new SimpleSendC(AM_PACK);
//     NDiscP.Sender -> SimpleSendC;
//     components new TimerMilliC() as NeighborTimer;
//     NDiscP.Timer -> NeighborTimer;

//     components RoutingC;
//     NDiscP.Routing -> RoutingC;

//     // Use data structure for neighbor list
//     components new HashmapC(uint32_t, 20) as HashMap;
//     NDiscP.ndMap -> HashMap;
// }

/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

#include <Timer.h>
#include "../../includes/CommandMsg.h"
#include "../../includes/packet.h"

configuration NeighborDiscoveryC {
    provides interface NeighborDiscovery;
}

implementation {
    components NeighborDiscoveryP;
    NeighborDiscovery = NeighborDiscoveryP;

    components new SimpleSendC(AM_PACK);
    NeighborDiscoveryP.Sender -> SimpleSendC;
    
    components new TimerMilliC() as NeighborDiscoveryTimer;
    NeighborDiscoveryP.NeighborDiscoveryTimer -> NeighborDiscoveryTimer;

    components RandomC as Random;
    NeighborDiscoveryP.Random -> Random;

    components new HashmapC(uint32_t, 20);
    NeighborDiscoveryP.NeighborMap -> HashmapC;

    
    components RoutingC;
    NeighborDiscoveryP.Routing -> RoutingC;
}
