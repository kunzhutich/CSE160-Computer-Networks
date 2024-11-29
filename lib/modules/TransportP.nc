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
    // uses interface CommandHandler;
}

implementation {
    // sliding window variables
    #define WINDOW_SIZE 4 // Sliding window size
    uint8_t base = 0; // Sequence number of the first unacknowledged packet
    uint8_t nextSeqNum = 0; // Sequence number of the next packet to send
    bool acked[WINDOW_SIZE]; // Tracks acknowledgment for each packet in the window
    pack window[WINDOW_SIZE]; // Buffer to store packets in the window

    // Stop-and-Wait variables
    uint8_t lastSentSeq = 0; // Sequence number of the last packet sent
    uint8_t lastAckedSeq = 255; // Sequence number of the last ACK received (255 = no ACK yet)
    bool waitingForAck = FALSE; // Flag to check if waiting for an ACK
    pack currentPacket; // The current packet being sent

    // command error_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen) {
    //     uint8_t socketIndex = findSocket(fd);
    //     if (socketIndex == MAX_NUM_OF_SOCKETS || waitingForAck) {
    //         dbg(TRANSPORT_CHANNEL, "Socket %d is busy or invalid\n", fd);
    //         return EBUSY;
    //     }

    //     // Prepare the packet
    //     makePack(&currentPacket, TOS_NODE_ID, sockets[socketIndex].dest.addr, 1, PROTOCOL_TCP, lastSentSeq, buff, bufflen);
    //     lastSentSeq++; // Increment sequence number
    //     waitingForAck = TRUE; // Set waiting for ACK flag

    //     dbg(TRANSPORT_CHANNEL, "Sending packet with Seq: %d\n", lastSentSeq - 1);

    //     // Send the packet
    //     if (call Sender.send(currentPacket, sockets[socketIndex].dest.addr) != SUCCESS) {
    //         dbg(TRANSPORT_CHANNEL, "Failed to send packet\n");
    //         return FAIL;
    //     }

    //     // Start retransmission timer
    //     call RetransmitTimer.startOneShot(1000); // 1-second timeout
    //     return SUCCESS;
    // }


    // Variables for socket states.
    socket_store_t sockets[MAX_NUM_OF_SOCKETS];
    uint8_t numSockets = 0;

    // uint8_t findSocket(socket_t fd) {
    //     uint8_t i;
    //     for (i = 0; i < numSockets; i++) {
    //         if (sockets[i].flag == fd) {
    //             return i;
    //         }
    //     }
    //     return MAX_NUM_OF_SOCKETS; // Not found.
    // }

    uint8_t findSocket(socket_t fd) {
        uint8_t i;
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].flag == fd && sockets[i].state != CLOSED) {
                return i;
            }
        }
        dbg(TRANSPORT_CHANNEL, "Socket %d not found\n", fd);
        return MAX_NUM_OF_SOCKETS; // Not found.
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

    // command socket_t Transport.socket() {
    //     uint8_t i;
    //     for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
    //         if (sockets[i].flag == CLOSED) {
    //             sockets[i].flag = i + 1; // Assign a unique socket ID.
    //             sockets[i].state = CLOSED; // Initialize socket state.
    //             sockets[i].src = 0; // Clear source port.
    //             sockets[i].dest.addr = 0; // Clear destination address.
    //             sockets[i].dest.port = 0; // Clear destination port.
    //             return i + 1;
    //         }
    //     }
    //     dbg(TRANSPORT_CHANNEL, "No available sockets\n");
    //     return 0; // No available sockets.
    // }

    command socket_t Transport.socket() {
        uint8_t i;
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].state == CLOSED) {
                sockets[i].state = BOUND; // Change the initial state to BOUND
                return i; // Return the index as the socket descriptor
            }
        }
        return -1; // Return error if no sockets are available
    }


    // command error_t Transport.bind(socket_t fd, socket_addr_t *addr) {
    //     uint8_t socketIndex = findSocket(fd);
    //     if (socketIndex == MAX_NUM_OF_SOCKETS) return FAIL;

    //     sockets[socketIndex].state = LISTEN;
    //     sockets[socketIndex].src = addr->port;
    //     sockets[socketIndex].dest.addr = ROOT_SOCKET_ADDR; // Default to broadcast.
    //     sockets[socketIndex].dest.port = addr->port;
    //     dbg(TRANSPORT_CHANNEL, "Socket %d bound to port %d\n", fd, addr->port);
    //     return SUCCESS;
    // }

    command error_t Transport.bind(socket_t fd, socket_addr_t *addr) {
        uint8_t socketIndex = findSocket(fd);
        if (socketIndex == MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "Socket %d not found for binding\n", fd);
            return FAIL;
        }

        // Transition socket state to BOUND
        sockets[socketIndex].state = BOUND;

        dbg(TRANSPORT_CHANNEL, "Binding socket %d to port %d\n", fd, addr->port);

        sockets[socketIndex].src = addr->port;
        // sockets[socketIndex].dest.addr = 0;  // Clear destination for now
        // sockets[socketIndex].dest.port = 0;  // Clear destination port
        dbg(TRANSPORT_CHANNEL, "Socket %d bound to port %d, state set to BOUND\n", fd, addr->port);
        return SUCCESS;
    }

    // command error_t Transport.listen(socket_t fd) {
    //     uint8_t socketIndex = findSocket(fd);
    //     if (socketIndex == MAX_NUM_OF_SOCKETS) return FAIL;

    //     if (sockets[socketIndex].state != LISTEN) {
    //         dbg(TRANSPORT_CHANNEL, "Socket %d not in LISTEN state\n", fd);
    //         return FAIL;
    //     }
    //     sockets[socketIndex].state = SYN_RCVD;
    //     dbg(TRANSPORT_CHANNEL, "Socket %d is now listening\n", fd);
    //     return SUCCESS;
    // }

    command error_t Transport.listen(socket_t fd) {
        uint8_t socketIndex = findSocket(fd);
        if (socketIndex == MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "Socket %d not found for listening\n", fd);
            return FAIL;
        }

        // if (sockets[socketIndex].state != BOUND) {
        //     dbg(TRANSPORT_CHANNEL, "Socket %d is not in BOUND state, cannot listen\n", fd);
        //     return FAIL;
        // }

        // // Transition to LISTEN state
        // sockets[socketIndex].state = LISTEN;
        // dbg(TRANSPORT_CHANNEL, "Socket %d is now in LISTEN state\n", fd);
        // return SUCCESS;

        if (sockets[socketIndex].state == BOUND) {
            sockets[socketIndex].state = LISTEN;
            return SUCCESS;
        }

        return FAIL; // Only sockets in BOUND state can listen
    }

    command socket_t Transport.accept(socket_t fd) {
        uint8_t socketIndex = findSocket(fd);
        socket_t newSocket;
        uint8_t newIndex;

        if (socketIndex == MAX_NUM_OF_SOCKETS) return 0;

        if (sockets[socketIndex].state != SYN_RCVD) return 0;

        // Create a new socket for the accepted connection.
        newSocket = call Transport.socket();
        if (newSocket == 0) return 0;

        newIndex = findSocket(newSocket);
        sockets[newIndex] = sockets[socketIndex]; // Copy socket details.
        sockets[newIndex].state = ESTABLISHED;
        dbg(TRANSPORT_CHANNEL, "Socket %d accepted connection, new socket %d\n", fd, newSocket);
        return newSocket;
    }

    command error_t Transport.connect(socket_t fd, socket_addr_t *addr) {
        pack synPacket;

        uint8_t socketIndex = findSocket(fd);
        if (socketIndex == MAX_NUM_OF_SOCKETS) return FAIL;

        sockets[socketIndex].state = SYN_SENT;
        sockets[socketIndex].dest = *addr;
        dbg(TRANSPORT_CHANNEL, "Socket %d initiating connection to port %d\n", fd, addr->port);

        // Send SYN packet.
        makePack(&synPacket, TOS_NODE_ID, addr->addr, 1, PROTOCOL_TCP, 0, NULL, 0);
        if (call Sender.send(synPacket, addr->addr) != SUCCESS) {
            dbg(TRANSPORT_CHANNEL, "Failed to send SYN packet\n");
            return FAIL;
        }

        dbg(TRANSPORT_CHANNEL, "SYN packet sent from socket %d\n", fd);
        return SUCCESS;
    }

    command error_t Transport.close(socket_t fd) {
        pack finPacket;

        uint8_t socketIndex = findSocket(fd);
        if (socketIndex == MAX_NUM_OF_SOCKETS) return FAIL;

        makePack(&finPacket, TOS_NODE_ID, sockets[socketIndex].dest.addr, 1, PROTOCOL_TCP, 0, NULL, 0);
        if (call Sender.send(finPacket, sockets[socketIndex].dest.addr) != SUCCESS) {
            dbg(TRANSPORT_CHANNEL, "Failed to send FIN packet\n");
            return FAIL;
        }

        sockets[socketIndex].state = CLOSED;
        dbg(TRANSPORT_CHANNEL, "Socket %d closed\n", fd);
        return SUCCESS;
    }

    // event void Timer.fired() {
    //     dbg(TRANSPORT_CHANNEL, "Retransmit timer fired\n");
        
    //     if (waitingForAck) {
    //         // Retransmit the current packet
    //         dbg(TRANSPORT_CHANNEL, "Timeout! Retransmitting packet with Seq: %d\n", lastSentSeq - 1);
    //         call Sender.send(currentPacket, currentPacket.dest);
    //         call RetransmitTimer.startOneShot(1000); // Restart timer
    //     }
    // }

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

    // event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
    //     pack* receivedPacket = (pack*)payload;

    //     // Check if it's an ACK for the current sequence number
    //     if (receivedPacket->protocol == PROTOCOL_TCP && receivedPacket->seq == lastSentSeq - 1) {
    //         dbg(TRANSPORT_CHANNEL, "ACK received for Seq: %d\n", receivedPacket->seq);
    //         waitingForAck = FALSE; // Reset waiting for ACK
    //         call RetransmitTimer.stop(); // Stop the retransmission timer
    //     } else {
    //         dbg(TRANSPORT_CHANNEL, "Unexpected packet received\n");
    //     }

    //     return msg;
    // }

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

    // event void CommandHandler.clientWrite(uint16_t dest, uint8_t *payload) {
    //     dbg(TRANSPORT_CHANNEL, "Client Write: Dest: %d, Payload: %s\n", dest, payload);
    //     call Transport.write(dest, payload, strlen(payload));
    // }

    // event void CommandHandler.clientClose(uint16_t dest) {
    //     dbg(TRANSPORT_CHANNEL, "Client Close: Dest: %d\n", dest);
    //     call Transport.close(dest);
    // }
}
