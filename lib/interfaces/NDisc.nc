interface NDisc {
    command void start();
    command void stop();
    command void nDiscovery(pack* ndMsg); 
    command void print();

    // New event for LSA
    event void neighborUpdate();
}