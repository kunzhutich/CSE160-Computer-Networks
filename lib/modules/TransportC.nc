#include <Timer.h>
#include "../../includes/CommandMsg.h"
#include "../../includes/packet.h"

configuration TransportC {
    provides interface Transport;
}

implementation {
    components TransportP;
    Transport = TransportP;

    components new TimerMilliC() as ConnectionTimer;
    TransportP.Timer -> ConnectionTimer;
    
    components RoutingC;
    TransportP.Routing -> RoutingC;

}