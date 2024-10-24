#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"

module IPP {
    provides interface IP;
    uses interface SimpleSend as Sender;
    uses interface Routing;
}

implementation {
    pack pck;

    // Forward packet based on routing table
    command void IP.send(pack* myMsg) {
        if (myMsg->dest == TOS_NODE_ID) {
            dbg(GENERAL_CHANNEL, "Packet delivered to local node %d\n", TOS_NODE_ID);
            // Deliver the packet locally
        } else {
            call IP.forward(myMsg);
        }
    }

    command void IP.forward(pack* myMsg) {
        uint8_t nextHop = call Routing.getNextHop(myMsg->dest);
        if (nextHop != 0) {
            dbg(GENERAL_CHANNEL, "Forwarding packet to next hop %d\n", nextHop);
            call Sender.send(*myMsg, nextHop);
        } else {
            dbg(GENERAL_CHANNEL, "No route to destination %d, packet dropped\n", myMsg->dest);
        }
    }
}
