#include "../../includes/constants.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"
#include "../../includes/channels.h"


module LinkStateP {
    provides interface LinkState;
    uses interface Flood;
    uses interface Timer<TMilli> as Timer;
    uses interface Hashmap<uint16_t> as LSASeqMap;
    uses interface Hashmap<uint16_t> as RoutingTable;
}

implementation {
    typedef struct {
        uint16_t neighbor;
        uint16_t cost;
    } NeighborInfo;

    typedef struct {
        uint16_t nodeID;
        uint16_t seqNum;
        uint8_t numNeighbors;
        NeighborInfo neighbors[MAX_NEIGHBORS];
    } LSAPayload;

    uint16_t sequenceNumber = 0;
    bool initialized = FALSE;

    void sendLSA();
    void runDijkstra();

    // Link State Database: Mapping nodeID to LSAPayload
    LSAPayload linkStateDatabase[MAX_NODES];

    // Function to get LSA for a node
    LSAPayload* getLSA(uint16_t nodeID) {
        uint16_t i;
        for (i = 0; i < MAX_NODES; i++) {
            if (linkStateDatabase[i].nodeID == nodeID) {
                return &linkStateDatabase[i];
            }
        }
        return NULL; // LSA not found
    }


    command void LinkState.init() {
        if (!initialized) {
            initialized = TRUE;
            call Timer.startPeriodic(60000); // Send LSA every 60 seconds
            sequenceNumber = 0;

            // Initialize linkStateDatabase
            // uint16_t i;
            for (; i < MAX_NODES; i++) {
                linkStateDatabase[i].nodeID = UNDEFINED;
            }

            dbg(LINKSTATE_CHANNEL, "Link State Routing initialized.\n");
        }
    }

    // Function to update LSA in the database
    void updateLSA(LSAPayload *lsa) {
        uint16_t i;
        for (i = 0; i < MAX_NODES; i++) {
            if (linkStateDatabase[i].nodeID == lsa->nodeID) {
                linkStateDatabase[i] = *lsa; // Update existing entry
                return;
            } else if (linkStateDatabase[i].nodeID == UNDEFINED) {
                linkStateDatabase[i] = *lsa; // Add new entry
                return;
            }
        }
        // If the database is full, you might want to handle this case
    }

    command void LinkState.handleNeighborUpdate() {
        // Increment sequence number
        sequenceNumber++;

        // Create and flood LSA packet
        sendLSA();
    }

    void sendLSA() {
        // Build LSA payload
        LSAPayload lsa;
        lsa.nodeID = TOS_NODE_ID;
        lsa.seqNum = sequenceNumber;

        // Get neighbor list from Neighbor Discovery module
        // (Assuming you have a function to get neighbors)
        // For illustration, let's assume we have a function:
        // NeighborInfo[] getNeighborList(uint8_t *numNeighbors);

        // Placeholder code:
        lsa.numNeighbors = 0; // Set the actual number of neighbors
        // Fill lsa.neighbors array with actual neighbor data

        // Create pack
        pack msg;
        msg.src = TOS_NODE_ID;
        msg.dest = AM_BROADCAST_ADDR;
        msg.TTL = MAX_TTL;
        msg.protocol = PROTOCOL_LINKSTATE;
        msg.seq = sequenceNumber;
        memcpy(msg.payload, &lsa, sizeof(LSAPayload));

        // Flood the LSA packet
        call Flood.flood(&msg);
        dbg(LINKSTATE_CHANNEL, "LSA sent with sequence number %d\n", sequenceNumber);
    }

    command void LinkState.receiveLSA(pack *msg) {
        // Process received LSA
        LSAPayload *lsa = (LSAPayload *)msg->payload;

        uint16_t senderID = lsa->nodeID;
        uint16_t receivedSeqNum = lsa->seqNum;

        if (call LSASeqMap.contains(senderID)) {
            uint16_t knownSeqNum = call LSASeqMap.get(senderID);
            if (receivedSeqNum <= knownSeqNum) {
                // Discard outdated LSA
                dbg(LINKSTATE_CHANNEL, "Discarding outdated LSA from %d\n", senderID);
                return;
            }
        }

        // Update sequence number map
        call LSASeqMap.insert(senderID, receivedSeqNum);

        // Update link state database
        updateLSA(lsa);

        // Recalculate routing table
        runDijkstra();
    }

    void runDijkstra() {
        uint16_t dist[MAX_NODES];
        uint16_t prev[MAX_NODES];
        bool visited[MAX_NODES];
        uint16_t i;

        for (i = 0; i < MAX_NODES; i++) {
            dist[i] = INFINITY_COST;
            prev[i] = UNDEFINED;
            visited[i] = FALSE;
        }
        dist[TOS_NODE_ID] = 0;

        // Priority queue can be implemented as a simple array for small networks
        while (TRUE) {
            // Find the unvisited node with the smallest distance
            uint16_t minDist = INFINITY_COST;
            uint16_t u = UNDEFINED;

            for (i = 0; i < MAX_NODES; i++) {
                if (!visited[i] && dist[i] < minDist) {
                    minDist = dist[i];
                    u = i;
                }
            }

            if (u == UNDEFINED) {
                break; // All reachable nodes have been visited
            }

            visited[u] = TRUE;

            // For each neighbor v of u
            // Retrieve neighbor list of u from the link state database
            LSAPayload* lsa = getLSA(u);
            if (lsa != NULL) {
                uint8_t j;
                for (j = 0; j < lsa->numNeighbors; j++) {
                    uint16_t v = lsa->neighbors[j].neighbor;
                    uint16_t cost = lsa->neighbors[j].cost;
                    if (!visited[v] && dist[u] + cost < dist[v]) {
                        dist[v] = dist[u] + cost;
                        prev[v] = u;
                    }
                }
            }
        }

        // Build the routing table from prev[]
        for (i = 0; i < MAX_NODES; i++) {
            if (dist[i] != INFINITY_COST && i != TOS_NODE_ID) {
                // Determine the next hop
                uint16_t nextHop = i;
                while (prev[nextHop] != TOS_NODE_ID) {
                    nextHop = prev[nextHop];
                }
                call RoutingTable.insert(i, nextHop);
            }
        }
    }


    command uint16_t LinkState.getNextHop(uint16_t destination) {
        if (call RoutingTable.contains(destination)) {
            return call RoutingTable.get(destination);
        } else {
            return AM_BROADCAST_ADDR; // Default to broadcasting if no route
        }
    }

    command void LinkState.printRoutingTable() {
        uint16_t* keys = call RoutingTable.getKeys();
        uint16_t size = call RoutingTable.size();
        uint16_t i;

        dbg(LINKSTATE_CHANNEL, "Routing Table:\n");
        for (i = 0; i < size; i++) {
            uint16_t dest = keys[i];
            uint16_t nextHop = call RoutingTable.get(dest);
            dbg(LINKSTATE_CHANNEL, "Destination: %d, Next Hop: %d\n", dest, nextHop);
        }
    }

    event void Timer.fired() {
        // Periodic LSA update
        sendLSA();
    }
}
