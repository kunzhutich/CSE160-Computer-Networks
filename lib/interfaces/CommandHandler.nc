interface CommandHandler{
    // Events
    event void ping(uint16_t destination, uint8_t *payload);
    event void printNeighbors();
    event void printRouteTable();
    event void printLinkState();
    event void printDistanceVector();
    event void setTestServer(uint8_t src, uint8_t port);
    event void setTestClient(uint8_t src, uint8_t dest, uint8_t srcPort, uint8_t destPort, uint16_t transfer);
    // event void clientWrite(uint16_t dest, uint8_t *payload);
    event void clientClose(uint8_t src, uint16_t dest, uint8_t srcPort, uint8_t destPort);
    event void setAppServer();
    event void setAppClient();
}
