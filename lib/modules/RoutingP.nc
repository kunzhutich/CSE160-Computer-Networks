#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"
#define maxRoutes 256
#define maxCost 17
#define LS_TTL 17


module RoutingP {
    provides interface Routing;
    uses interface SimpleSend as Sender;
    uses interface Hashmap<uint16_t> as rMap;
    uses interface Flood as flo;
    uses interface Timer<TMilli> as rTimer;
    uses interface NDisc as ND;
}

implementation{

    uint32_t createKey(uint16_t src, uint16_t seq) {
        return ((uint32_t)src << 16) | (uint32_t)seq;
    }
    uint8_t sequenceNum = 0;
    uint16_t numNodes = 0;
    uint16_t numRoutes = 0;

    pack rt;

    typedef struct {
        uint8_t nextHop;
        uint8_t cost;
    } Route;

    typedef struct {
        uint8_t neighbor;
        uint8_t cost;
    } LSP;

    void djikstra();
    bool updateState(pack* myMsg);
    void sendLSP(uint8_t lost);
    void removeRoute(uint8_t dest);
    void addRoute(uint8_t dest, uint8_t nextHop, uint8_t cost);
    void init();

    uint8_t linkState[maxRoutes][maxRoutes];
    Route routingTable[maxRoutes];

    // Route RoutingTable[100];
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length) {
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }

    command void Routing.start(){
        // call ND.start();
        call rTimer.startPeriodic(10000);
        init();
        dbg(ROUTING_CHANNEL, "Starting Routing\n");
    }

    command void Routing.ping(uint16_t destination, uint8_t *payload) {
        makePack(&rt, TOS_NODE_ID, destination, 0, PROTOCOL_PING, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
        dbg(ROUTING_CHANNEL, "PING FROM %d TO %d\n", TOS_NODE_ID, destination);
        logPack(&rt);
        call Routing.routed(&rt);
    }    


    command void Routing.routed(pack *myMsg){
        uint8_t nextHop;
        if(myMsg->dest == TOS_NODE_ID && myMsg->protocol == PROTOCOL_PING) {
            dbg(ROUTING_CHANNEL, "PING at %d!\n", TOS_NODE_ID);
            makePack(&rt, myMsg->dest, myMsg->src, 0, PROTOCOL_PINGREPLY, 0,(uint8_t *) myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
            call Routing.routed(&rt);
            return;
        } else if(myMsg->dest == TOS_NODE_ID && myMsg->protocol == PROTOCOL_PINGREPLY) {
            dbg(ROUTING_CHANNEL, "PING_REPLY at  %d!!!\n", TOS_NODE_ID);
            return;
        }
        if(routingTable[myMsg->dest].cost < maxCost) {
            nextHop = routingTable[myMsg->dest].nextHop;
            dbg(ROUTING_CHANNEL, "Node %d routing to %d\n", TOS_NODE_ID, nextHop);
            logPack(myMsg);
            call Sender.send(*myMsg, nextHop);
        } else {
            dbg(ROUTING_CHANNEL, "Not most efficient route. Packet dropped!\n");
            logPack(myMsg);
        }
    
    }   
    command void Routing.linkState(pack* myMsg) {
        uint32_t key = createKey(myMsg->src, myMsg->seq);
        // Check seq number
        if(myMsg->src == TOS_NODE_ID || call rMap.contains(key)) {
            return;
        } else {
            call rMap.insert(myMsg->src, myMsg->seq);
        }
        // If state changed -> rerun djikstra
        if(updateState(myMsg)) {
            djikstra();
        }
        // Forward to all neighbors
        call Sender.send(*myMsg, AM_BROADCAST_ADDR);
    }
    command void Routing.lostNeighbor(uint16_t lost) {
        dbg(ROUTING_CHANNEL, "Lost Neighbor %u\n", lost);
        if(linkState[TOS_NODE_ID][lost] != maxCost) {
            linkState[TOS_NODE_ID][lost] = maxCost;
            linkState[lost][TOS_NODE_ID] = maxCost;
            numNodes--;
            removeRoute(lost);
        }
        sendLSP(lost);
        djikstra();
    }

    command void Routing.foundNeighbor() {
        uint32_t* neighbors = call ND.getNeighbors();
        uint16_t nSize = call ND.getSize();
        uint16_t i = 0;
        for(i = 0; i < nSize; i++) {
            linkState[TOS_NODE_ID][neighbors[i]] = 1;
            linkState[neighbors[i]][TOS_NODE_ID] = 1;
        }
        sendLSP(0);
        djikstra();
    }

    command void Routing.printTable() {
        uint16_t i;
        dbg(ROUTING_CHANNEL, "DESTINATION  HOP  COST\n");
        for(i = 1; i < maxRoutes; i++) {
            if(routingTable[i].cost != maxCost)
                dbg(ROUTING_CHANNEL, "%4d%5d%6d\n", i, routingTable[i].nextHop, routingTable[i].cost);
        }
    }

    void init() {
        uint16_t i, j;
        for(i = 0; i < maxRoutes; i++) {
            routingTable[i].nextHop = 0;
            routingTable[i].cost = maxCost;
        }
        for(i = 0; i < maxRoutes; i++) {
            linkState[i][0] = 0;
        }
        for(i = 0; i < maxRoutes; i++) {
            linkState[0][i] = 0;
        }
        for(i = 1; i < maxRoutes; i++) {
            for(j = 1; j < maxRoutes; j++) {
                linkState[i][j] = maxCost;
            }
        }
        routingTable[TOS_NODE_ID].nextHop = TOS_NODE_ID;
        routingTable[TOS_NODE_ID].cost = 0;
        linkState[TOS_NODE_ID][TOS_NODE_ID] = 0;
        numNodes++;
        numRoutes++;
    }

    bool updateState(pack* myMsg) {
        uint16_t i;
        LSP *lsp = (LSP *)myMsg->payload;
        bool state = FALSE;
        for(i = 0; i < 10; i++) {
            if(linkState[myMsg->src][lsp[i].neighbor] != lsp[i].cost) {
                if(linkState[myMsg->src][lsp[i].neighbor] == maxCost) {
                    numNodes++;
                } else if(lsp[i].cost == maxCost) {
                    numNodes--;
                }
                linkState[myMsg->src][lsp[i].neighbor] = lsp[i].cost;
                linkState[lsp[i].neighbor][myMsg->src] = lsp[i].cost;
                state = TRUE;
            }
        }
        return state;
    }

    void sendLSP(uint8_t lost) {
        uint32_t* neighbors = call ND.getNeighbors();
        uint16_t nSize = call ND.getSize();
        uint16_t i = 0, counter = 0;
        LSP linkStatePayload[10];
        // Zero out the array
        for(i = 0; i < 10; i++) {
            linkStatePayload[i].neighbor = 0;
            linkStatePayload[i].cost = 0;
        }
        i = 0;
        // If neighbor lost -> send out infinite cost
        if(lost != 0) {
            dbg(ROUTING_CHANNEL, "Sending out lost neighbor %u\n", lost);
            linkStatePayload[counter].neighbor = lost;
            linkStatePayload[counter].cost = maxCost;
            i++;
            counter++;
        }
        // Add neighbors in groups of 10 and flood LSP to all neighbors
        for(; i < nSize; i++) {
            linkStatePayload[counter].neighbor = neighbors[i];
            linkStatePayload[counter].cost = 1;
            counter++;
            if(counter == 10 || i == nSize - 1) {
                // Send LSP to each neighbor                
                makePack(&rt, TOS_NODE_ID, 0, LS_TTL, PROTOCOL_PING, sequenceNum++, &linkStatePayload, sizeof(linkStatePayload));
                call Sender.send(rt, AM_BROADCAST_ADDR);
                // Zero the array
                while(counter > 0) {
                    counter--;
                    linkStatePayload[i].neighbor = 0;
                    linkStatePayload[i].cost = 0;
                }
            }
        }
    }
    // void djikstra() {
    //     uint16_t i = 0;
    //     uint8_t currentNode = TOS_NODE_ID, minCost = maxCost, nextNode = 0, prevNode = 0;
    //     uint8_t prev[maxRoutes];
    //     uint8_t cost[maxRoutes];
    //     bool visited[maxRoutes];
    //     uint16_t count = numNodes;
    //     for(i = 0; i < maxRoutes; i++) {
    //         cost[i] = maxCost;
    //         prev[i] = 0;
    //         visited[i] = FALSE;
    //     }
    //     cost[currentNode] = 0;
    //     prev[currentNode] = 0;
    //     while(TRUE) {
    //         for(i = 1; i < maxRoutes; i++) {
    //             if(i != currentNode && linkState[currentNode][i] < maxCost && cost[currentNode] + linkState[currentNode][i] < cost[i]) {
    //                 cost[i] = cost[currentNode] + linkState[currentNode][i];
    //                 prev[i] = currentNode;
    //             }
    //         }
    //         visited[currentNode] = TRUE;            
    //         minCost = maxCost;
    //         nextNode = 0;
    //         for(i = 1; i < maxRoutes; i++) {
    //             if(cost[i] < minCost && !visited[i]) {
    //                 minCost = cost[i];
    //                 nextNode = i;
    //             }
    //         }
    //         currentNode = nextNode;
    //         if(--count == 0) {
    //             break;
    //         }
    //     }
    //     // NEED: add route to table
    //     for(i = 1; i < maxRoutes; i++) {
    //         if(i == TOS_NODE_ID) {
    //             continue;
    //         }
    //         if(cost[i] != maxCost) {
    //             prevNode = i;
    //             while(prev[prevNode] != TOS_NODE_ID) {
    //                 prevNode = prev[prevNode];
    //             }
    //             addRoute(i, prevNode, cost[i]);
    //         } else {
    //             removeRoute(i);
    //         }
    //     }
    // }

    void djikstra() {
        uint16_t i = 0;
        uint8_t currentNode = TOS_NODE_ID, minCost = maxCost, nextNode = 0, prevNode = 0;
        uint8_t prev[maxRoutes];
        uint8_t cost[maxRoutes];
        bool visited[maxRoutes];
        uint16_t count = numNodes;

        // Initialize cost and previous node arrays
        for(i = 0; i < maxRoutes; i++) {
            cost[i] = maxCost;     // Initialize all nodes to max cost
            prev[i] = 0;           // No previous node at the start
            visited[i] = FALSE;    // No node has been visited
        }

        // Set the starting node (currentNode is the source, i.e., TOS_NODE_ID)
        cost[currentNode] = 0;     // Cost to reach itself is zero
        prev[currentNode] = TOS_NODE_ID; // Start at itself

        while(count > 0) {
            // Find the next unvisited node with the minimum cost
            minCost = maxCost;
            nextNode = 0;
            for(i = 1; i < maxRoutes; i++) {
                if(!visited[i] && cost[i] < minCost) {
                    minCost = cost[i];
                    nextNode = i;
                }
            }

            // If no valid next node is found, break
            if(nextNode == 0) {
                break;
            }

            // Mark the current node as visited
            currentNode = nextNode;
            visited[currentNode] = TRUE;

            // Update the cost for each neighboring node
            for(i = 1; i < maxRoutes; i++) {
                if(i != currentNode && linkState[currentNode][i] < maxCost && !visited[i]) {
                    uint8_t newCost = cost[currentNode] + linkState[currentNode][i];
                    if(newCost < cost[i]) {
                        cost[i] = newCost;
                        prev[i] = currentNode;  // Update the previous node
                    }
                }
            }

            // Decrease the number of unvisited nodes
            count--;
        }

        // Now, add the routes to the routing table based on the `prev` array
        for(i = 1; i < maxRoutes; i++) {
            if(i == TOS_NODE_ID) {
                continue;
            }
            if(cost[i] != maxCost) {
                // Trace back to find the next hop
                prevNode = i;
                while(prev[prevNode] != TOS_NODE_ID) {
                    prevNode = prev[prevNode];
                }
                // Add the route with the correct nextHop and cost
                addRoute(i, prevNode, cost[i]);
                dbg(ROUTING_CHANNEL, "Route added to %d with nextHop %d and cost %d\n", i, prevNode, cost[i]);
            } else {
                // No route found, remove it
                removeRoute(i);
            }
        }
    }



    event void rTimer.fired(){
        if(call rTimer.isOneShot()) {
            call rTimer.startPeriodic(30000 + (uint16_t) (call Random.rand16()%5000));
        } else {
            // Send flooding packet w/neighbor list
            sendLSP(0);
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
        routingTable[dest].cost = maxCost;
        numRoutes--;
    }
    // command void Routing.print(){
	// 	uint32_t i = 0;
		
	// 	dbg(ROUTING_CHANNEL, "Printing Routing Table\n");
	// 	dbg(ROUTING_CHANNEL, "Dest\tHop\tCount\n");
    // }
}