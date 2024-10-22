module IPP {
    provides interface IP;
    uses interface LSRouting;  // For retrieving the next hop from the routing table
    uses interface SimpleSend;

    event void IP.send(pack *msg) {
        uint16_t nextHop = call LSRouting.getNextHop(msg->dest);
        if (nextHop != TOS_NODE_ID) {
            call SimpleSend.send(*msg, nextHop);  // Forward the packet to the next hop
        } else {
            // Packet is for this node, deliver locally
            signal IP.packetReceived(msg);
        }
    }

    event void SimpleSend.sendDone(pack *msg, error_t error) {
        if (error == SUCCESS) {
            dbg(ROUTING_CHANNEL, "Packet successfully sent!\n");
        }
    }
}
