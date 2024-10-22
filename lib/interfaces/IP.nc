interface IP {
    command void send(pack *msg);
    event void receive(pack *msg);
}
