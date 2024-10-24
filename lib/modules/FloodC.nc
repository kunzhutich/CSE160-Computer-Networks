#include <Timer.h>
#include "../../includes/CommandMsg.h"
#include "../../includes/packet.h"

configuration FloodC {
    provides interface Flood;
}

implementation {
    components FloodP;
    Flood = FloodP;

    components new SimpleSendC(AM_PACK);
    FloodP.Sender -> SimpleSendC;
    
    components new HashmapC(uint16_t, 20);
    FloodP.Hashmap -> HashmapC;
}