#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"

module IPP {
    provides interface IP;
    provides interface Receive;     // Provide Receive to higher layers

    uses interface SimpleSend as Sender;
    uses interface Routing;

    uses interface Receive as LowerReceive;     // Receive from lower layers
}

implementation {
    // Command to send a packet
    command void IP.send(pack* myMsg) {
        uint8_t nextHop;

        // Decrement TTL and check for expiration
        if (myMsg->TTL == 0) {
            dbg(GENERAL_CHANNEL, "IP.send: Packet TTL expired, dropping packet\n");
            return;
        }
        myMsg->TTL--;

        nextHop = call Routing.getNextHop(myMsg->dest);
        if (nextHop != 0) {
            dbg(GENERAL_CHANNEL, "IP.send: Forwarding packet to next hop %d\n", nextHop);
            call Sender.send(*myMsg, nextHop);
        } else {
            dbg(GENERAL_CHANNEL, "IP.send: No route to destination %d, packet dropped\n", myMsg->dest);
        }
    }

    // Event to receive packets from lower layers
    event message_t* LowerReceive.receive(message_t* msg, void* payload, uint8_t len) {
        pack* myMsg = (pack*) payload;
        uint8_t nextHop;

        if (len != sizeof(pack)) {
            dbg(GENERAL_CHANNEL, "IP: Unknown Packet Type %d, dropping packet\n", len);
            return msg;
        }

        if (myMsg->TTL == 0) {
            dbg(GENERAL_CHANNEL, "IP: Packet TTL expired, dropping packet\n");
            return msg;
        }
        myMsg->TTL--;

        if (myMsg->dest == TOS_NODE_ID) {
            dbg(GENERAL_CHANNEL, "IP: Packet delivered to local node %d\n", TOS_NODE_ID);
            // Deliver the packet to higher layers
            signal Receive.receive(msg, payload, len);
        } else {
            // Forward the packet
            nextHop = call Routing.getNextHop(myMsg->dest);
            if (nextHop != 0) {
                dbg(GENERAL_CHANNEL, "IP: Forwarding packet to next hop %d\n", nextHop);
                call Sender.send(*myMsg, nextHop);
            } else {
                dbg(GENERAL_CHANNEL, "IP: No route to destination %d, packet dropped\n", myMsg->dest);
            }
        }

        return msg;
    }
}


// implementation {
//     pack pck;

//     // Forward packet based on routing table
//     command void IP.send(pack* myMsg) {
//         if (myMsg->dest == TOS_NODE_ID) {
//             dbg(GENERAL_CHANNEL, "Packet delivered to local node %d\n", TOS_NODE_ID);
//             // Deliver the packet locally
//         } else {
//             call IP.forward(myMsg);
//         }
//     }

//     command void IP.forward(pack* myMsg) {
//         uint8_t nextHop = call Routing.getNextHop(myMsg->dest);
//         if (nextHop != 0) {
//             dbg(GENERAL_CHANNEL, "Forwarding packet to next hop %d\n", nextHop);
//             call Sender.send(*myMsg, nextHop);
//         } else {
//             dbg(GENERAL_CHANNEL, "No route to destination %d, packet dropped\n", myMsg->dest);
//         }
//     }
// }
