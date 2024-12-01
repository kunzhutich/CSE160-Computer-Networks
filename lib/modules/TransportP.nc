#include "../../includes/socket.h"
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/utils.h"

module TransportP {
    provides interface Transport;
    uses interface Timer<TMilli> as RetransmitTimer;
    uses interface Hashmap<uint8_t> as SocketMap; // For tracking socket states.
    uses interface SimpleSend as Sender;
    uses interface Receive;
}

implementation {
    #define WINDOW_SIZE 4 // Sliding window size
    uint8_t base = 0; // Sequence number of the first unacknowledged packet
    uint8_t nextSeqNum = 0; // Sequence number of the next packet to send
    bool acked[WINDOW_SIZE]; // Tracks acknowledgment for each packet in the window
    pack window[WINDOW_SIZE]; // Buffer to store packets in the window

    socket_store_t sockets[MAX_NUM_OF_SOCKETS]; // Array of socket structures
    uint8_t numSockets = 0;

    // Helper function to find a socket by its descriptor
    uint8_t findSocket(socket_t fd) {
        uint8_t i;
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].flag == fd && sockets[i].state != CLOSED) {
                return i; // Return the socket index if found
            }
        }
        dbg(TRANSPORT_CHANNEL, "Socket %d not found\n", fd);
        return MAX_NUM_OF_SOCKETS; // Indicate failure (not found)
    }

    // Allocate a new socket
    command socket_t Transport.socket() {
        uint8_t i;
        dbg(TRANSPORT_CHANNEL, "Transport.socket(): Allocating a new socket\n");

        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].state == CLOSED) {
                sockets[i].state = ALLOCATED;       // Set to ALLOCATED state
                sockets[i].flag = i + 1;           // Assign a unique socket ID
                sockets[i].src = 0;                // Clear source port
                sockets[i].dest.addr = 0;          // Clear destination address
                sockets[i].dest.port = 0;          // Clear destination port

                dbg(TRANSPORT_CHANNEL, "Socket %d allocated\n", i + 1);
                return i + 1;                      // Return socket ID
            }
        }

        dbg(TRANSPORT_CHANNEL, "No available sockets\n");
        return 0; // Indicate failure (no sockets available)
    }

    // Bind a socket to a port
    command error_t Transport.bind(socket_t fd, socket_addr_t *addr) {
        uint8_t socketIndex = findSocket(fd);
        if (socketIndex == MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "Socket %d not found for binding\n", fd);
            return FAIL;
        }

        // Ensure the socket is in ALLOCATED state before binding
        if (sockets[socketIndex].state != ALLOCATED) {
            dbg(TRANSPORT_CHANNEL, "Socket %d is not in ALLOCATED state, cannot bind\n", fd);
            return FAIL;
        }

        sockets[socketIndex].src = addr->port;   // Assign the source port
        sockets[socketIndex].state = BOUND;     // Transition to BOUND state
        dbg(TRANSPORT_CHANNEL, "Socket %d bound to port %d\n", fd, addr->port);
        return SUCCESS;
    }

    // Transition a socket to LISTEN state
    command error_t Transport.listen(socket_t fd) {
        uint8_t socketIndex = findSocket(fd);
        if (socketIndex == MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "Socket %d not found for listening\n", fd);
            return FAIL;
        }

        // Ensure the socket is in BOUND state before listening
        if (sockets[socketIndex].state != BOUND) {
            dbg(TRANSPORT_CHANNEL, "Socket %d is not in BOUND state, cannot listen\n", fd);
            return FAIL;
        }

        sockets[socketIndex].state = LISTEN; // Transition to LISTEN state
        dbg(TRANSPORT_CHANNEL, "Socket %d is now in LISTEN state\n", fd);
        return SUCCESS;
    }

    // Connect a socket to a remote address
    command error_t Transport.connect(socket_t fd, socket_addr_t *addr) {
        pack synPacket;

        uint8_t socketIndex = findSocket(fd);
        if (socketIndex == MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "Socket %d not found for connecting\n", fd);
            return FAIL;
        }

        // Ensure the socket is in ALLOCATED or BOUND state before connecting
        if (sockets[socketIndex].state != ALLOCATED && sockets[socketIndex].state != BOUND) {
            dbg(TRANSPORT_CHANNEL, "Socket %d is not in a valid state to connect\n", fd);
            return FAIL;
        }

        sockets[socketIndex].state = SYN_SENT;
        sockets[socketIndex].dest = *addr;
        dbg(TRANSPORT_CHANNEL, "Socket %d initiating connection to %d:%d\n", fd, addr->addr, addr->port);

        // Send SYN packet
        makePack(&synPacket, TOS_NODE_ID, addr->addr, 1, PROTOCOL_TCP, 0, NULL, 0);
        if (call Sender.send(synPacket, addr->addr) != SUCCESS) {
            dbg(TRANSPORT_CHANNEL, "Failed to send SYN packet\n");
            return FAIL;
        }

        dbg(TRANSPORT_CHANNEL, "SYN packet sent from socket %d\n", fd);
        return SUCCESS;
    }

    // Close a socket
    command error_t Transport.close(socket_t fd) {
        pack finPacket;

        uint8_t socketIndex = findSocket(fd);
        if (socketIndex == MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "Socket %d not found for closing\n", fd);
            return FAIL;
        }

        makePack(&finPacket, TOS_NODE_ID, sockets[socketIndex].dest.addr, 1, PROTOCOL_TCP, 0, NULL, 0);
        if (call Sender.send(finPacket, sockets[socketIndex].dest.addr) != SUCCESS) {
            dbg(TRANSPORT_CHANNEL, "Failed to send FIN packet\n");
            return FAIL;
        }

        sockets[socketIndex].state = CLOSED; // Transition to CLOSED state
        dbg(TRANSPORT_CHANNEL, "Socket %d closed\n", fd);
        return SUCCESS;
    }

    // Retransmission timer event
    event void RetransmitTimer.fired() {
        uint8_t i;

        dbg(TRANSPORT_CHANNEL, "Timeout! Retransmitting packets in the window\n");

        for (i = base; i < nextSeqNum; i++) {
            if (!acked[i % WINDOW_SIZE]) {
                dbg(TRANSPORT_CHANNEL, "Retransmitting Seq: %d\n", i);
                call Sender.send(window[i % WINDOW_SIZE], window[i % WINDOW_SIZE].dest);
            }
        }

        // Restart the timer
        call RetransmitTimer.startOneShot(1000);
    }

    // Handle received messages
    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
        pack* receivedPacket = (pack*)payload;

        if (receivedPacket->protocol == PROTOCOL_TCP) {
            uint8_t ackSeq = receivedPacket->seq;

            if (ackSeq >= base && ackSeq < nextSeqNum) {
                dbg(TRANSPORT_CHANNEL, "ACK received for Seq: %d\n", ackSeq);
                acked[ackSeq % WINDOW_SIZE] = TRUE;

                // Slide the window forward
                while (acked[base % WINDOW_SIZE]) {
                    acked[base % WINDOW_SIZE] = FALSE; // Reset the slot
                    base++;
                    dbg(TRANSPORT_CHANNEL, "Sliding window. New base: %d\n", base);
                }

                if (base == nextSeqNum) {
                    call RetransmitTimer.stop(); // Stop timer if all packets are acknowledged
                } else {
                    call RetransmitTimer.startOneShot(1000); // Restart timer for remaining unacknowledged packets
                }
            }
        }

        return msg;
    }

    command socket_t Transport.accept(socket_t fd) {
        dbg(TRANSPORT_CHANNEL, "Transport.accept: Accepting connection on socket %d\n", fd);
        // Placeholder: Logic for accepting a new connection
        return -1; // Return an error or the new socket
    }

    command error_t Transport.receive(pack* package) {
        dbg(TRANSPORT_CHANNEL, "Packet received: Protocol %d, Seq %d\n", package->protocol, package->seq);
        // TODO: Add implementation
        return SUCCESS;
    }

    command error_t Transport.release(socket_t fd) {
        // TODO: Add implementation
        return SUCCESS;
    }

    command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        // TODO: Add implementation
        return 0;
    }

    command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        uint8_t socketIndex = findSocket(fd);
        if (socketIndex == MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "Invalid socket %d\n", fd);
            return FAIL;
        }

        dbg(TRANSPORT_CHANNEL, "Writing to socket %d, state: %d\n", fd, sockets[socketIndex].state);

        if ((nextSeqNum - base) >= WINDOW_SIZE) {
            dbg(TRANSPORT_CHANNEL, "Window full! Cannot send more packets\n");
            return EBUSY;
        }

        // Prepare the packet
        makePack(&window[nextSeqNum % WINDOW_SIZE], TOS_NODE_ID, sockets[socketIndex].dest.addr, 1, PROTOCOL_TCP, nextSeqNum, buff, bufflen);
        dbg(TRANSPORT_CHANNEL, "Sending packet with Seq: %d\n", nextSeqNum);

        // Send the packet
        if (call Sender.send(window[nextSeqNum % WINDOW_SIZE], sockets[socketIndex].dest.addr) != SUCCESS) {
            dbg(TRANSPORT_CHANNEL, "Failed to send packet Seq: %d\n", nextSeqNum);
            return FAIL;
        }

        acked[nextSeqNum % WINDOW_SIZE] = FALSE; // Mark as not yet acknowledged
        if (base == nextSeqNum) {
            call RetransmitTimer.startOneShot(1000); // Start the timer for the base packet
        }
        nextSeqNum++;
        return SUCCESS;
    }
}
