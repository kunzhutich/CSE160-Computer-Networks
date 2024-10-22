interface NDisc {
    command void start();
    command void stop();
    command void nDiscovery(pack* ndMsg); 
    command void print();
    command uint32_t getNeighbors();
    command uint16_t getSize();
}