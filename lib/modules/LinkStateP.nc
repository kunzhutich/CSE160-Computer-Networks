#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"

#define LS_MAX_ROUTES 256
#define LS_MAX_COST 17
#define LS_TTL 17

module LinkStateP {
    provides interface LinkState;
    
    uses interface SimpleSend as Sender;
    uses interface Hashmap<uint32_t> as rMap;
    uses interface NDisc;
    uses interface Flood ;
    uses interface Timer<TMilli> as LSRTimer;
    uses interface Random as Random;
}

implementation {

    uint32_t createKey(uint16_t src, uint16_t seq) {
        return ((uint32_t)src << 16) | (uint32_t)seq;
    }

    typedef struct {
        uint8_t nextHop;
        uint8_t cost;
    } Route;

    typedef struct {
        uint8_t neighbor;
        uint8_t cost;
    } LSP;

    uint8_t linkState[LS_MAX_ROUTES][LS_MAX_ROUTES];
    Route routingTable[LS_MAX_ROUTES];
    uint16_t numKnownNodes = 0;
    uint16_t numRoutes = 0;
    uint16_t sequenceNum = 0;
    pack LSPack;

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, void* payload, uint8_t length);
    void initilizeRoutingTable();
    bool updateState(pack* myMsg, uint8_t payloadLen);
    bool updateRoute(uint8_t dest, uint8_t nextHop, uint8_t cost);
    void addRoute(uint8_t dest, uint8_t nextHop, uint8_t cost);
    void removeRoute(uint8_t dest);
    void sendLSP(uint8_t lostNeighbor);
    void handleForward(pack* myMsg);
    void djikstra();

    command error_t LinkState.start() {
        // Initialize routing table and neighbor state structures
        // Start one-shot
        dbg(ROUTING_CHANNEL, "Link State Routing Started on node %u!\n", TOS_NODE_ID);
        initilizeRoutingTable();
        call LSRTimer.startOneShot(5000);
    }

    event void LSRTimer.fired() {
        if(call LSRTimer.isOneShot()) {
            call LSRTimer.startPeriodic(30000 + (uint16_t) (call Random.rand16()%5000));
        } else {
            // Send flooding packet w/neighbor list
            sendLSP(0);
        }
    }

    command void LinkState.ping(uint16_t destination, uint8_t *payload) {
        makePack(&LSPack, TOS_NODE_ID, destination, 0, PROTOCOL_PING, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
        dbg(ROUTING_CHANNEL, "PING FROM %d TO %d\n", TOS_NODE_ID, destination);
        logPack(&LSPack);
        call LinkState.routePacket(&LSPack);
    }    

    command void LinkState.routePacket(pack* myMsg) {
        // Look up value in table and forward
        uint8_t nextHop;
        if(myMsg->dest == TOS_NODE_ID && myMsg->protocol == PROTOCOL_PING) {
            dbg(ROUTING_CHANNEL, "PING Packet has reached destination %d!!!\n", TOS_NODE_ID);
            makePack(&LSPack, myMsg->dest, myMsg->src, 0, PROTOCOL_PINGREPLY, 0,(uint8_t *) myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
            call LinkState.routePacket(&LSPack);
            return;
        } else if(myMsg->dest == TOS_NODE_ID && myMsg->protocol == PROTOCOL_PINGREPLY) {
            dbg(ROUTING_CHANNEL, "PING_REPLY Packet has reached destination %d!!!\n", TOS_NODE_ID);
            return;
        }
        if(routingTable[myMsg->dest].cost < LS_MAX_COST) {
            nextHop = routingTable[myMsg->dest].nextHop;
            dbg(ROUTING_CHANNEL, "Node %d routing packet through %d\n", TOS_NODE_ID, nextHop);
            logPack(myMsg);
            call Sender.send(*myMsg, nextHop);
        } else {
            dbg(ROUTING_CHANNEL, "No route to destination. Dropping packet...\n");
            logPack(myMsg);
        }
    }

    command void LinkState.handleLS(pack* myMsg, uint8_t len) {
        uint32_t key = createKey(myMsg->src, myMsg->seq);
        uint8_t payloadLen = len - (sizeof(pack) - PACKET_MAX_PAYLOAD_SIZE);

        // debugging stuff
        uint8_t numEntries = payloadLen / sizeof(LSP);
        uint8_t i;
        LSP *lsp = (LSP *)myMsg->payload;
        dbg(ROUTING_CHANNEL, "Node %d received LSP from %d with seq %u\n", TOS_NODE_ID, myMsg->src, myMsg->seq);

        for(i = 0; i < numEntries; i++) {
            dbg(ROUTING_CHANNEL, "Received LSP Entry %d: Neighbor %d, Cost %d\n", i, lsp[i].neighbor, lsp[i].cost);
        }

        // Check seq number
        if(myMsg->src == TOS_NODE_ID || call rMap.contains(key)) {
            dbg(ROUTING_CHANNEL, "(MAP) Node %d already processed LSP from %d with seq %u\n", TOS_NODE_ID, myMsg->src, myMsg->seq);
            return;
        } else {
            dbg(ROUTING_CHANNEL, "(MAP) Node %d inserting LSP from %d with seq %u into rMap\n", TOS_NODE_ID, myMsg->src, myMsg->seq);
            call rMap.insert(key, 1);
        }
        // If state changed -> rerun djikstra
        if(updateState(myMsg, payloadLen)) {
            djikstra();
        }
        // Forward to all neighbors
        call Sender.send(*myMsg, AM_BROADCAST_ADDR);
    }

    command void LinkState.handleNeighborLost(uint16_t lostNeighbor) {
        // dbg(ROUTING_CHANNEL, "Neighbor lost %u\n", lostNeighbor);
        dbg(ROUTING_CHANNEL, "Node %d handling neighbor lost: %d\n", TOS_NODE_ID, lostNeighbor);

        if(linkState[TOS_NODE_ID][lostNeighbor] != LS_MAX_COST) {
            linkState[TOS_NODE_ID][lostNeighbor] = LS_MAX_COST;
            linkState[lostNeighbor][TOS_NODE_ID] = LS_MAX_COST;
            numKnownNodes--;
            removeRoute(lostNeighbor);
        }
        sendLSP(lostNeighbor);
        djikstra();
    }

    command void LinkState.handleNeighborFound() {
        uint32_t* neighbors = call NDisc.getNeighbors();
        uint16_t neighborsListSize = call NDisc.getSize();
        uint16_t i = 0;

        dbg(ROUTING_CHANNEL, "Node %d handling neighbor found.\n", TOS_NODE_ID);

        for(i = 0; i < neighborsListSize; i++) {
            linkState[TOS_NODE_ID][neighbors[i]] = 1;
            linkState[neighbors[i]][TOS_NODE_ID] = 1;
        }
        sendLSP(0);
        djikstra();
    }

    command void LinkState.printRouteTable() {
        uint16_t i;
        dbg(ROUTING_CHANNEL, "DEST  HOP  COST\n");
        for(i = 1; i < LS_MAX_ROUTES; i++) {
            if(routingTable[i].cost != LS_MAX_COST)
                dbg(ROUTING_CHANNEL, "%4d%5d%6d\n", i, routingTable[i].nextHop, routingTable[i].cost);
        }
    }

    void initilizeRoutingTable() {
        uint16_t i, j;
        for(i = 0; i < LS_MAX_ROUTES; i++) {
            routingTable[i].nextHop = 0;
            routingTable[i].cost = LS_MAX_COST;
        }
        for(i = 0; i < LS_MAX_ROUTES; i++) {
            linkState[i][0] = 0;
        }
        for(i = 0; i < LS_MAX_ROUTES; i++) {
            linkState[0][i] = 0;
        }
        for(i = 1; i < LS_MAX_ROUTES; i++) {
            for(j = 1; j < LS_MAX_ROUTES; j++) {
                linkState[i][j] = LS_MAX_COST;
            }
        }
        routingTable[TOS_NODE_ID].nextHop = TOS_NODE_ID;
        routingTable[TOS_NODE_ID].cost = 0;
        linkState[TOS_NODE_ID][TOS_NODE_ID] = 0;
        numKnownNodes++;
        numRoutes++;
    }

    bool updateState(pack* myMsg, uint8_t payloadLen) {
        uint16_t i;
        uint8_t numEntries = payloadLen / sizeof(LSP);

        LSP *lsp = (LSP *)myMsg->payload;
        bool isStateUpdated = FALSE;

        uint8_t x, y;

        for(i = 0; i < numEntries; i++) {
            if (lsp[i].neighbor == 0) {
                continue; // Skip empty entries
            }

            if(linkState[myMsg->src][lsp[i].neighbor] != lsp[i].cost) {
                dbg(ROUTING_CHANNEL, "Node %d updating linkState[%d][%d] from %d to %d\n",
                    TOS_NODE_ID, myMsg->src, lsp[i].neighbor, linkState[myMsg->src][lsp[i].neighbor], lsp[i].cost);

                if(linkState[myMsg->src][lsp[i].neighbor] == LS_MAX_COST) {
                    numKnownNodes++;
                } else if(lsp[i].cost == LS_MAX_COST) {
                    numKnownNodes--;
                }
                linkState[myMsg->src][lsp[i].neighbor] = lsp[i].cost;
                linkState[lsp[i].neighbor][myMsg->src] = lsp[i].cost;
                isStateUpdated = TRUE;
            }
        }

        dbg(ROUTING_CHANNEL, "Link State Matrix for Node %d:\n", TOS_NODE_ID);
        for(x = 1; x < LS_MAX_ROUTES; x++) {
            for(y = 1; y < LS_MAX_ROUTES; y++) {
                if(linkState[x][y] < LS_MAX_COST) {
                    dbg(ROUTING_CHANNEL, "linkState[%d][%d] = %d\n", x, y, linkState[x][y]);
                }
            }
        }

        return isStateUpdated;
    }

    void sendLSP(uint8_t lostNeighbor) {
        uint32_t* neighbors = call NDisc.getNeighbors();
        uint16_t neighborsListSize = call NDisc.getSize();
        uint16_t i = 0, j = 0, k = 0, counter = 0;
        LSP linkStatePayload[10];

        // Zero out the array
        for(i = 0; i < 10; i++) {
            linkStatePayload[i].neighbor = 0;
            linkStatePayload[i].cost = 0;
        }

        // i = 0;
        counter = 0;
        // If neighbor lost -> send out infinite cost
        if(lostNeighbor != 0) {
            dbg(ROUTING_CHANNEL, "Sending out lost neighbor %u\n", lostNeighbor);
            linkStatePayload[counter].neighbor = lostNeighbor;
            linkStatePayload[counter].cost = LS_MAX_COST;
            // i++;
            counter++;
        }

        // Add neighbors in groups of 10 and flood LSP to all neighbors
        for(; i < neighborsListSize; i++) {
            linkStatePayload[counter].neighbor = neighbors[i];
            linkStatePayload[counter].cost = 1;
            counter++;
            // if(counter == 10 || i == neighborsListSize-1) {
            if(counter == 10) {
                dbg(ROUTING_CHANNEL, "Node %d is sending LSP with seq %u\n", TOS_NODE_ID, sequenceNum);
                // Send LSP to each neighbor                
                // makePack(&LSPack, TOS_NODE_ID, 0, LS_TTL, PROTOCOL_LINKSTATE, sequenceNum++, &linkStatePayload, sizeof(linkStatePayload));
                makePack(&LSPack, TOS_NODE_ID, 0, LS_TTL, PROTOCOL_LINKSTATE, sequenceNum++, &linkStatePayload, counter * sizeof(LSP));
                call Sender.send(LSPack, AM_BROADCAST_ADDR);
                // Zero the array
                // while(counter > 0) {
                //     counter--;
                //     linkStatePayload[i].neighbor = 0;
                //     linkStatePayload[i].cost = 0;
                // }

                // uint16_t j;
                for(j = 0; j < counter; j++) {
                    linkStatePayload[j].neighbor = 0;
                    linkStatePayload[j].cost = 0;
                }
                counter = 0; // Reset counter
            }
        }

        if(counter > 0) {
            dbg(ROUTING_CHANNEL, "Node %d is sending LSP with seq %u\n", TOS_NODE_ID, sequenceNum);
            makePack(&LSPack, TOS_NODE_ID, 0, LS_TTL, PROTOCOL_LINKSTATE, sequenceNum++, &linkStatePayload, counter * sizeof(LSP));
            call Sender.send(LSPack, AM_BROADCAST_ADDR);
        }

        for(k = 0; k < counter; k++) {
            dbg(ROUTING_CHANNEL, "LSP Entry %d: Neighbor %d, Cost %d\n", k, linkStatePayload[k].neighbor, linkStatePayload[k].cost);
        }
    }

    void djikstra() {
        uint16_t i = 0;
        uint8_t currentNode = TOS_NODE_ID, minCost = LS_MAX_COST, nextNode = 0, prevNode = 0;
        uint8_t prev[LS_MAX_ROUTES];
        uint8_t cost[LS_MAX_ROUTES];
        bool visited[LS_MAX_ROUTES];
        uint16_t count = numKnownNodes;
        for(i = 0; i < LS_MAX_ROUTES; i++) {
            cost[i] = LS_MAX_COST;
            prev[i] = 0;
            visited[i] = FALSE;
        }
        cost[currentNode] = 0;
        prev[currentNode] = 0;
        while(TRUE) {
            for(i = 1; i < LS_MAX_ROUTES; i++) {
                if(i != currentNode && linkState[currentNode][i] < LS_MAX_COST && cost[currentNode] + linkState[currentNode][i] < cost[i]) {
                    cost[i] = cost[currentNode] + linkState[currentNode][i];
                    prev[i] = currentNode;
                }
            }
            visited[currentNode] = TRUE;            
            minCost = LS_MAX_COST;
            nextNode = 0;
            for(i = 1; i < LS_MAX_ROUTES; i++) {
                if(cost[i] < minCost && !visited[i]) {
                    minCost = cost[i];
                    nextNode = i;
                }
            }
            currentNode = nextNode;
            if(--count == 0) {
                break;
            }
        }
        // NEED: add route to table
        for(i = 1; i < LS_MAX_ROUTES; i++) {
            if(i == TOS_NODE_ID) {
                continue;
            }
            if(cost[i] != LS_MAX_COST) {
                prevNode = i;
                while(prev[prevNode] != TOS_NODE_ID) {
                    prevNode = prev[prevNode];
                }
                addRoute(i, prevNode, cost[i]);
            } else {
                removeRoute(i);
            }
        }

        dbg(ROUTING_CHANNEL, "Dijkstra Results for Node %d:\n", TOS_NODE_ID);
        for(i = 1; i < LS_MAX_ROUTES; i++) {
            if(cost[i] < LS_MAX_COST) {
                dbg(ROUTING_CHANNEL, "Node %d: Cost = %d, Prev = %d\n", i, cost[i], prev[i]);
            }
        }
    }

    void addRoute(uint8_t dest, uint8_t nextHop, uint8_t cost) {
        if(cost < routingTable[dest].cost) {
            routingTable[dest].nextHop = nextHop;
            routingTable[dest].cost = cost;
            numRoutes++;
        }
    }

    void removeRoute(uint8_t dest) {
        routingTable[dest].nextHop = 0;
        routingTable[dest].cost = LS_MAX_COST;
        numRoutes--;
    }

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, void* payload, uint8_t length) {
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }                            
}