module IPP {
    provides interface IP;
    uses interface SimpleSend as Sender;
    uses interface LinkState;
}

implementation {
    command void IP.send(pack *msg) {
        uint16_t nextHop = call LinkState.getNextHop(msg->dest);
        if (nextHop != AM_BROADCAST_ADDR) {
            call Sender.send(*msg, nextHop);
        } else {
            dbg("IP", "No route to destination %d\n", msg->dest);
        }
    }

    event void Sender.sendDone(message_t *msg, error_t error) {
        // Handle sendDone if necessary
    }

    event void receive(pack *msg) {
        // Handle incoming packets
    }
}
