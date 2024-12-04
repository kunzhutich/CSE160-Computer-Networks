#include "../../includes/channels.h"
#include "../../includes/packet.h"

module IPP {
    provides interface IP;
    uses interface SimpleSend as Sender;
    uses interface Routing;
}

implementation {
    command error_t IP.send(pack* packet) {
        uint8_t nextHop;
        
        // If packet is destined for this node, don't forward
        if (packet->dest == TOS_NODE_ID) {
            return SUCCESS;
        }

        // Get next hop from routing table using your existing routing implementation
        nextHop = call Routing.getNextHop(packet->dest);
        
        if (nextHop == 0) {  // Using your routing's convention for no route
            dbg(ROUTING_CHANNEL, "IP: No route to host %d\n", packet->dest);
            return FAIL;
        }

        // Forward packet to next hop
        dbg(ROUTING_CHANNEL, "IP: Forwarding packet dest=%d via next_hop=%d\n", 
            packet->dest, nextHop);
        
        // Decrement TTL
        if (packet->TTL <= 0) {
            dbg(ROUTING_CHANNEL, "IP: Dropping packet - TTL expired\n");
            return FAIL;
        }
        packet->TTL--;
        
        call Sender.send(*packet, nextHop);
        return SUCCESS;
    }
}