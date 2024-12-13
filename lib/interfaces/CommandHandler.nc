interface CommandHandler{
    // Events
    event void ping(uint16_t destination, uint8_t *payload);
    event void printNeighbors();
    event void printRouteTable();
    event void printLinkState();
    event void printDistanceVector();
    event void setTestServer(uint16_t src, uint8_t port);
    event void setTestClient(uint16_t src, uint8_t dest, uint8_t srcPort, uint8_t destPort, uint16_t transfer);
    event void clientClose(uint16_t src, uint8_t dest, uint8_t srcPort, uint8_t destPort);
    event void setAppServer(uint16_t node);
    event void setAppClient(uint16_t node);

    event void handleHello(uint16_t src, uint8_t *username, uint8_t port);
    event void handleMsg(uint16_t src, uint8_t *message);
    event void handleWhisper(uint16_t src, uint8_t *username, uint8_t *message);
    event void handleListUsers(uint16_t src);
}
