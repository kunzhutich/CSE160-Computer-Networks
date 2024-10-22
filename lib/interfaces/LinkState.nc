interface LinkState {
    command void init();
    command void handleNeighborUpdate();
    command void receiveLSA(pack *msg);
    command uint16_t getNextHop(uint16_t destination);
    command void printRoutingTable();
}
