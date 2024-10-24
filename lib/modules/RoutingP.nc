#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"


module RoutingP {
    provides interface Routing;
    uses interface SimpleSend as Sender;
    uses interface Hashmap<uint32_t> as SeqHashmap; // For src-seq hashmap
    uses interface Hashmap<uint32_t> as LinkStateMap; // For LSDB
    uses interface Flood;
    uses interface Timer<TMilli> as Timer;
    uses interface NDisc;
    uses interface IP;
}

implementation{
    uint32_t createSeqKey(uint16_t src, uint16_t seq) {
        return ((uint32_t)src << 16) | (uint32_t)seq;
    }
    
    uint32_t createLinkKey(uint16_t src, uint16_t dest) {
        return ((uint32_t)src << 16) | (uint32_t)dest;
    }

    uint8_t sequenceNum = 0;
    uint16_t numNodes = 0;
    uint16_t numRoutes = 0;

    pack pck;

    typedef struct {
        uint8_t nextHop;
        uint8_t cost;
    } Route;

    typedef struct {
        uint8_t neighborID;
        uint8_t cost;
    } LSP;

    #define MAX_ROUTES 256
    #define INFINITY_COST 17

    // Declare routing table for storing routes
    Route routeTable[MAX_ROUTES];

    void djikstra();
    bool updateState(pack* myMsg);
    void broadcastLSA(uint8_t lost);
    void removeRoute(uint8_t dest);
    void addRoute(uint8_t dest, uint8_t nextHop, uint8_t cost);
    // void initializeRouting();

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length) {
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }

    void initializeRouting() {
        uint16_t i;

        // Clear the routing table by setting initial values
        for(i = 0; i < MAX_ROUTES; i++) {
            routeTable[i].nextHop = 0;
            routeTable[i].cost = INFINITY_COST;  // Set to maximum cost initially
        }

        // Clear the sequence number hashmap and link-state hashmap
        call SeqHashmap.clear();  // Clear src-seq hashmap
        call LinkStateMap.clear();  // Clear link-state hashmap

        // Initialize the routing table for this node
        routeTable[TOS_NODE_ID].nextHop = TOS_NODE_ID;  // The node should always route to itself
        routeTable[TOS_NODE_ID].cost = 0;  // Cost to itself is zero
        numNodes = 1;  // Start with one node (this node)
        numRoutes = 1;  // One valid route (to itself)
    }


    command void Routing.start(){
        initializeRouting();
        call Timer.startOneShot(60000);
        dbg(ROUTING_CHANNEL, "Starting Routing\n");
    }

    command void Routing.ping(uint16_t destination, uint8_t *payload) {
        makePack(&pck, TOS_NODE_ID, destination, 0, PROTOCOL_PING, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
        dbg(ROUTING_CHANNEL, "PING FROM %d TO %d\n", TOS_NODE_ID, destination);
        logPack(&pck);
        call Routing.routed(&pck);
    }

    command void Routing.routed(pack *myMsg){
        dbg(ROUTING_CHANNEL, "Routing: Received packet from %d to %d with protocol %d\n", myMsg->src, myMsg->dest, myMsg->protocol);

        if(myMsg->dest == TOS_NODE_ID && myMsg->protocol == PROTOCOL_PING) {
            dbg(ROUTING_CHANNEL, "PING at %d!\n", TOS_NODE_ID);
            makePack(&pck, myMsg->dest, myMsg->src, 0, PROTOCOL_PINGREPLY, 0, (uint8_t *) myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
            call Routing.routed(&pck);
            return;
        } else if(myMsg->dest == TOS_NODE_ID && myMsg->protocol == PROTOCOL_PINGREPLY) {
            dbg(ROUTING_CHANNEL, "PING_REPLY at  %d!!!\n", TOS_NODE_ID);
            return;
        }

        call IP.send(myMsg);
    }

    command void Routing.linkState(pack* myMsg) {
        uint32_t seqKey = createSeqKey(myMsg->src, myMsg->seq);
        // dbg(ROUTING_CHANNEL, "LinkState: Received packet from %d, running Dijkstra\n", myMsg->src);

        if(myMsg->src == TOS_NODE_ID || call SeqHashmap.contains(seqKey)) {
            return;
        } else {
            call SeqHashmap.insert(seqKey, 1);  // Track processed packets
        }

        if(updateState(myMsg)) {
            djikstra();
        }

        call Sender.send(*myMsg, AM_BROADCAST_ADDR);
    }

    bool updateState(pack* myMsg) {
        uint16_t i;
        LSP *lsp = (LSP*)myMsg->payload;
        bool stateChanged = FALSE;
        uint8_t cost;
        uint32_t linkKey;

        for(i = 0; i < 10; i++) {
            linkKey = createLinkKey(myMsg->src, lsp[i].neighborID);

            if (call LinkStateMap.contains(linkKey)) {
                // Get the current cost
                cost = call LinkStateMap.get(linkKey);

                // If the cost has changed, update it
                if (cost != lsp[i].cost) {
                    cost = lsp[i].cost;
                    call LinkStateMap.insert(linkKey, cost); // Update the hashmap
                    stateChanged = TRUE;
                }
            } else {
                // Insert a new entry if it doesn't exist
                cost = lsp[i].cost;
                call LinkStateMap.insert(linkKey, cost);
                stateChanged = TRUE;
            }
        }
        return stateChanged;
    }

    void broadcastLSA(uint8_t lost) {
        uint32_t* neighbors = call NDisc.getNeighbors();
        uint16_t nSize = call NDisc.getSize();
        uint16_t i = 0, counter = 0;
        LSP linkStatePayload[10];
        uint32_t linkKey;

        // dbg(ROUTING_CHANNEL, "Found %d neighbors\n", call NDisc.getSize());
        // dbg(ROUTING_CHANNEL, "Sending Link-State Packet (LSP) with %d neighbors\n", nSize);

        // Send LSP only when there's a valid neighbor set
        if (nSize == 0) {
            dbg(ROUTING_CHANNEL, "No neighbors found, not sending LSP\n");
            return;
        }

        // Zero out the array
        for(i = 0; i < 10; i++) {
            linkStatePayload[i].neighborID = 0;
            linkStatePayload[i].cost = 0;
        }
        i = 0;

        // Add neighbors in groups of 10 and flood LSP to all neighbors
        for(; i < nSize; i++) {
            linkKey = createLinkKey(TOS_NODE_ID, neighbors[i]);
            if (call LinkStateMap.contains(linkKey)) {
                linkStatePayload[counter].neighborID = neighbors[i];
                linkStatePayload[counter].cost = call LinkStateMap.get(linkKey);
                counter++;
            }
            if(counter == 10 || i == nSize - 1) {
                // Send LSP to each neighbor
                makePack(&pck, TOS_NODE_ID, 0, 17, PROTOCOL_LINKSTATE, sequenceNum++, (uint8_t *)linkStatePayload, sizeof(linkStatePayload));
                call Sender.send(pck, AM_BROADCAST_ADDR);
                
                // Reset the counter
                counter = 0;
            }
        }
    }

    void djikstra() {
        uint16_t i;
        uint8_t currentNode = TOS_NODE_ID;
        uint8_t minCost;
        uint8_t nextNode;
        uint8_t prev[MAX_ROUTES];
        uint8_t cost[MAX_ROUTES];
        bool visited[MAX_ROUTES];
        bool foundNext;

        // Initialize
        for (i = 0; i < MAX_ROUTES; i++) {
            cost[i] = INFINITY_COST;
            prev[i] = 0;
            visited[i] = FALSE;
        }

        cost[currentNode] = 0;
        // dbg(ROUTING_CHANNEL, "Dijkstra starting at node %d\n", currentNode);

        while (TRUE) {
            minCost = INFINITY_COST;
            foundNext = FALSE;

            // Find the next node with the smallest cost
            for (i = 1; i < MAX_ROUTES; i++) {
                if (!visited[i] && cost[i] < minCost) {
                    minCost = cost[i];
                    nextNode = i;
                    foundNext = TRUE;
                }
            }

            if (!foundNext) {
                break;  // No more reachable nodes found
            }

            visited[nextNode] = TRUE;
            // dbg(ROUTING_CHANNEL, "Visiting node %d, cost = %d\n", nextNode, minCost);

            // Update costs for neighbors of the current node
            for (i = 1; i < MAX_ROUTES; i++) {
                uint32_t linkKey = createLinkKey(nextNode, i);
                if (call LinkStateMap.contains(linkKey)) {
                    uint8_t linkCost = call LinkStateMap.get(linkKey);
                    if (!visited[i] && linkCost < INFINITY_COST) {  // Check if link is valid
                        uint8_t newCost = cost[nextNode] + linkCost;
                        if (newCost < cost[i]) {  // Check for overflow
                            cost[i] = newCost;
                            prev[i] = nextNode;
                            // dbg(ROUTING_CHANNEL, "Updating cost for node %d, new cost = %d\n", i, cost[i]);
                        }
                    }
                }
            }
        }

        // Update routing table with shortest paths
        for (i = 1; i < MAX_ROUTES; i++) {
            if (cost[i] < INFINITY_COST) {
                uint8_t nextHop = i;
                // Trace back to find the first hop
                while (prev[nextHop] != currentNode && prev[nextHop] != 0) {
                    nextHop = prev[nextHop];
                }
                if (prev[nextHop] == currentNode) {  // Only add valid routes
                    addRoute(i, nextHop, cost[i]);
                    // dbg(ROUTING_CHANNEL, "Added route: Dest = %d, NextHop = %d, Cost = %d\n", i, nextHop, cost[i]);
                }
            } else {
                removeRoute(i);  // If a node is unreachable, remove its route
            }
        }
    }

    event void Timer.fired() {
        static bool hasStateChanged = FALSE;

        if(call Timer.isOneShot()) {
            call Timer.startPeriodic(30000);  // Start a periodic timer
        }

        // Check if there has been a state change
        if (hasStateChanged) {
            // dbg(ROUTING_CHANNEL, "Sending Link-State Packet (LSP)\n");
            broadcastLSA(0);  // Flood LSP
            hasStateChanged = FALSE;  // Reset the state change flag
        }
    }

    command void Routing.printTable() {
        uint16_t i;
        dbg(ROUTING_CHANNEL, "DEST\t  HOP\t  COST\n");
        for(i = 1; i < MAX_ROUTES; i++) {
            if(routeTable[i].cost != INFINITY_COST)
                dbg(ROUTING_CHANNEL, "%4d\t%5d\t%6d\n", i, routeTable[i].nextHop, routeTable[i].cost);
        }
    }
    
    command uint8_t Routing.getNextHop(uint16_t dest) {
        if (routeTable[dest].cost < INFINITY_COST) {
            return routeTable[dest].nextHop;
        }
        return 0;  // Return 0 if no valid route exists
    }

    command void Routing.foundNeighbor() {
        uint32_t* neighbors = call NDisc.getNeighbors();
        uint16_t nSize = call NDisc.getSize();
        uint16_t i;
        
        for(i = 0; i < nSize; i++) {
            uint32_t linkKey = createLinkKey(TOS_NODE_ID, neighbors[i]);
            uint8_t cost = 1;  // Assign a cost of 1 for direct neighbors
            call LinkStateMap.insert(linkKey, cost);
        }

        broadcastLSA(0);
        djikstra();
    }

    command void Routing.lostNeighbor(uint16_t lost) {
        uint32_t linkKey = createLinkKey(TOS_NODE_ID, lost);
        dbg(ROUTING_CHANNEL, "Lost Neighbor %u\n", lost);
        
        if(call LinkStateMap.contains(linkKey)) {
            uint8_t cost = INFINITY_COST;  // Set cost to maximum (infinity)
            call LinkStateMap.insert(linkKey, cost);  // Update the link state
            
            broadcastLSA(lost);  // Notify other nodes
            djikstra();  // Recalculate routes
        }
    }

    void addRoute(uint8_t dest, uint8_t nextHop, uint8_t cost) {
        if (cost < routeTable[dest].cost) {  // Only update if the new cost is lower
            routeTable[dest].nextHop = nextHop;  // Set the next hop for this destination
            routeTable[dest].cost = cost;        // Update the cost for this destination
            // dbg(ROUTING_CHANNEL, "Route added: Dest = %d, NextHop = %d, Cost = %d\n", dest, nextHop, cost);
        }
    }

    void removeRoute(uint8_t dest) {
        // Only remove the route if it was previously reachable
        if (routeTable[dest].cost < INFINITY_COST) {
            routeTable[dest].nextHop = 0;    // Reset next hop to 0 (invalid)
            routeTable[dest].cost = INFINITY_COST; // Set the cost to INFINITY_COST (infinity)
            // dbg(ROUTING_CHANNEL, "Route removed: Dest = %d\n", dest);
        }
    }

}