interface IP {
    command void send(pack *msg);
    event void packetReceived(pack *msg);  // Signal when a packet is received
}
