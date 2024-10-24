#include "../../includes/packet.h"

interface LinkState {
    command error_t start();
    command void ping(uint16_t destination, uint8_t *payload);
    command void routePacket(pack* myMsg);
    command void handleLS(pack* myMsg, uint8_t len);
    command void handleNeighborLost(uint16_t lostNeighbor);
    command void handleNeighborFound();
    command void printRouteTable();
}