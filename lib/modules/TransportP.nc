#include "../../includes/socket.h"
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/utils.h"
#include "../../includes/transport.h"

module TransportP {
    provides interface Transport;
    uses interface Boot;
    uses interface Timer<TMilli> as RetransmitTimer;
    uses interface Hashmap<uint8_t> as SocketMap; // For tracking socket states.
    uses interface SimpleSend as Sender;
    uses interface Receive;
}

implementation {
    #define WINDOW_SIZE 4                       // Sliding window size
    #define MAX_RETRIES 5                       // Maximum retransmission attempts
    #define RETRANSMIT_TIMEOUT 1500             // Timeout for retransmissions in milliseconds

    uint8_t base = 0;                           // Sequence number of the first unacknowledged packet
    uint8_t nextSeqNum = 0;                     // Sequence number of the next packet to send
    bool acked[WINDOW_SIZE];                    // Tracks acknowledgment for each packet in the window
    pack window[WINDOW_SIZE];                   // Buffer to store packets in the window
    uint8_t retries[WINDOW_SIZE] = {0};         // Retransmission attempts for each packet

    socket_store_t sockets[MAX_NUM_OF_SOCKETS]; // Array of socket structures
    socket_metadata_t socketMetadata[MAX_NUM_OF_SOCKETS]; // Transport-specific metadata
    uint8_t numSockets = 0;

    static bool initialized = FALSE;

    event void Boot.booted() {
        uint8_t i;

        if (!initialized) {
            dbg(TRANSPORT_CHANNEL, "TransportP initializing sockets for the first time.\n");
            initialized = TRUE;
        } else {
            dbg(TRANSPORT_CHANNEL, "TransportP already initialized. Skipping re-initialization.\n");
        }

        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            sockets[i].state = CLOSED;         // Initialize state to CLOSED
            sockets[i].flag = 0;              // Clear socket flag
            sockets[i].src = 0;               // Reset source port
            sockets[i].dest.addr = 0;         // Clear destination address
            sockets[i].dest.port = 0;         // Clear destination port
            memset(&socketMetadata[i], 0, sizeof(socket_metadata_t)); // Clear metadata
        }
        dbg(TRANSPORT_CHANNEL, "TransportP initialized with %d sockets.\n", MAX_NUM_OF_SOCKETS);
        dbg(TRANSPORT_CHANNEL, "Address of sockets array: %p\n", &sockets);
    }

    // Helper function to find a socket by its descriptor
    uint8_t findSocket(socket_t fd) {
        uint8_t i;

        if (fd == 0 || fd > MAX_NUM_OF_SOCKETS) {
            // dbg(TRANSPORT_CHANNEL, "Invalid socket descriptor: %d\n", fd);
            return MAX_NUM_OF_SOCKETS; // Indicate failure (invalid descriptor)
        }

        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].flag == fd && sockets[i].state != CLOSED) {
                return i; // Return the socket index if found
            }
        }

        dbg(TRANSPORT_CHANNEL, "Socket %d not found\n", fd);
        return MAX_NUM_OF_SOCKETS; // Indicate failure (not found)
    }

    // Updated socket lookup to consider both source and destination information
    uint8_t findSocketByAddress(uint16_t srcPort, uint16_t destPort) {
        uint8_t i;

        dbg(TRANSPORT_CHANNEL, "Looking for socket with srcPort: %d, destPort: %d.\n", srcPort, destPort);

        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            dbg(TRANSPORT_CHANNEL, "Checking socket %d: src %d, dest %d\n", i, sockets[i].src, sockets[i].dest.port);

            if (sockets[i].src == srcPort && sockets[i].dest.port == destPort && sockets[i].state != CLOSED) {
                dbg(TRANSPORT_CHANNEL, "Match found for srcPort %d and destPort %d at socket %d\n", srcPort, destPort, i);
                return i;
            }
        }
        

        dbg(TRANSPORT_CHANNEL, "Socket not found for srcPort %d and destPort %d\n", srcPort, destPort);
        return MAX_NUM_OF_SOCKETS; // Indicate failure (not found)
    }

    // Allocate a new socket
    command socket_t Transport.socket() {
        uint8_t i, j;

        dbg(TRANSPORT_CHANNEL, "Address of sockets array in Transport.socket: %p\n", &sockets); // Add this line
        dbg(TRANSPORT_CHANNEL, "Listing socket states before Transport.socket: \n");
        for (j = 0; j < MAX_NUM_OF_SOCKETS; j++) {
            dbg(TRANSPORT_CHANNEL, "        Socket %d's state is %d\n", j, sockets[j].state);
        }

        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].state == CLOSED) {
                dbg(TRANSPORT_CHANNEL, "Before SOCKET FUNCTION: socket %d's state is ------ %d\n", i, sockets[i].state);
                sockets[i].state = ALLOCATED;       // Set to ALLOCATED state
                dbg(TRANSPORT_CHANNEL, "After SOCKET FUNCTION: socket %d's state is ------ %d\n", i, sockets[i].state);


                sockets[i].flag = i + 1;           // Assign a unique socket ID
                sockets[i].src = 0;                // Clear source port
                sockets[i].dest.addr = 0;          // Clear destination address
                sockets[i].dest.port = 0;          // Clear destination port

                memset(&socketMetadata[i], 0, sizeof(socket_metadata_t)); // Reset metadata
                socketMetadata[i].socketId = i + 1;

                dbg(TRANSPORT_CHANNEL, "Socket %d allocated\n", i + 1);

                dbg(TRANSPORT_CHANNEL, "Listing socket states after Transport.socket: \n");
                for (j = 0; j < MAX_NUM_OF_SOCKETS; j++) {
                    dbg(TRANSPORT_CHANNEL, "        Socket %d's state is %d\n", j, sockets[j].state);
                }

                return i + 1;                      // Return socket ID
            }
        }
        dbg(TRANSPORT_CHANNEL, "No available sockets\n");
        return NULL_SOCKET; // Indicate failure (no sockets available)
    }

    // Bind a socket to a port
    command error_t Transport.bind(socket_t fd, socket_addr_t *addr) {
        uint8_t i;

        uint8_t socketIndex = findSocket(fd);
        if (socketIndex == MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "Socket %d not found for binding.\n", fd);
            return FAIL;
        }

        // Ensure the socket is in a valid state to bind
        if (sockets[socketIndex].state != ALLOCATED) {
            dbg(TRANSPORT_CHANNEL, "Socket %d not in ALLOCATED state. Cannot bind.\n", fd);
            return FAIL;
        }

        // Ensure the port is not already in use
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].src == addr->port && sockets[i].state != CLOSED) {
                dbg(TRANSPORT_CHANNEL, "Port %d is already in use by socket %d.\n", addr->port, i);
                return FAIL;
            }
        }

        dbg(TRANSPORT_CHANNEL, "Before BIND FUNCTION: socket %d's SRC is ------ %d\n", fd, sockets[socketIndex].src);
        sockets[socketIndex].src = addr->port; // Assign the source port
        dbg(TRANSPORT_CHANNEL, "After BIND FUNCTION: socket %d's SRC is ------ %d\n", fd, sockets[socketIndex].src);

        dbg(TRANSPORT_CHANNEL, "Before BIND FUNCTION: socket %d's state is ------ %d\n", fd, sockets[socketIndex].state);
        sockets[socketIndex].state = BOUND;   // Transition to BOUND state
        dbg(TRANSPORT_CHANNEL, "After BIND FUNCTION: socket %d's state is ------ %d\n", fd, sockets[socketIndex].state);

        dbg(TRANSPORT_CHANNEL, "Socket %d bound to port %d\n", fd, addr->port);
        return SUCCESS;
    }

    // Transition a socket to LISTEN state
    command error_t Transport.listen(socket_t fd) {
        uint8_t socketIndex = findSocket(fd);
        if (socketIndex == MAX_NUM_OF_SOCKETS) return FAIL;

        if (sockets[socketIndex].state != BOUND) return FAIL;

        dbg(TRANSPORT_CHANNEL, "Before LISTEN FUNCTION: socket %d's state is ------ %d\n", fd, sockets[socketIndex].state);
        sockets[socketIndex].state = LISTEN; // Transition to LISTEN state
        dbg(TRANSPORT_CHANNEL, "After LISTEN FUNCTION: socket %d's state is ------ %d\n", fd, sockets[socketIndex].state);

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

        if (sockets[socketIndex].state != BOUND) {
            dbg(TRANSPORT_CHANNEL, "Socket %d not in BOUND state. Cannot connect.\n", fd);
            return FAIL;
        }

        // Ensure destination address is valid
        if (addr->addr == 0 || addr->port == 0) {
            dbg(TRANSPORT_CHANNEL, "Invalid destination address for socket %d.\n", fd);
            return FAIL;
        }

        dbg(TRANSPORT_CHANNEL, "Before CONNECT FUNCTION: socket %d's state is ------ %d\n", fd, sockets[socketIndex].state);
        sockets[socketIndex].state = SYN_SENT;
        dbg(TRANSPORT_CHANNEL, "After CONNECT FUNCTION: socket %d's state is ------ %d\n", fd, sockets[socketIndex].state);

        sockets[socketIndex].dest = *addr;

        dbg(TRANSPORT_CHANNEL, "Socket %d initiating connection to %d:%d\n", fd, addr->addr, addr->port);

        // Updated call with correct arguments
        createTransportHeader(&synPacket, TOS_NODE_ID, addr->addr, FLAG_SYN, nextSeqNum, WINDOW_SIZE);

        dbg(TRANSPORT_CHANNEL, "SYN packet created with srcPort: %d, destPort: %d, flags: %x, seqNum: %d, advertisedWindow: %d\n",
            synPacket.src, synPacket.dest, FLAG_SYN, nextSeqNum, WINDOW_SIZE);


        if (call Sender.send(synPacket, addr->addr) != SUCCESS) {
            dbg(TRANSPORT_CHANNEL, "Failed to send SYN packet\n");
            return FAIL;
        }

        dbg(TRANSPORT_CHANNEL, "SYN packet sent from socket %d\n", fd);
        return SUCCESS;
    }

    // Close a socket
    command error_t Transport.close(socket_t fd) {
        uint8_t socketIndex = findSocket(fd);
        pack finPacket;

        if (socketIndex == MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "Socket %d not found for closing\n", fd);
            return FAIL;
        }

        switch (sockets[socketIndex].state) {

            case ESTABLISHED:
                dbg(TRANSPORT_CHANNEL, "Socket %d in ESTABLISHED. Sending FIN.\n", fd);
                makePack(&finPacket, TOS_NODE_ID, sockets[socketIndex].dest.addr, 1, PROTOCOL_TCP | FLAG_FIN, 0, NULL, 0);

                if (call Sender.send(finPacket, sockets[socketIndex].dest.addr) == SUCCESS) {
                    dbg(TRANSPORT_CHANNEL, "FIN packet sent for socket %d\n", fd);

                    dbg(TRANSPORT_CHANNEL, "Before ESTABLISHED SWITCH: socket state is ------ %d\n", sockets[socketIndex].state);
                    sockets[socketIndex].state = FIN_WAIT;
                    dbg(TRANSPORT_CHANNEL, "After ESTABLISHED SWITCH: socket state is ------ %d\n", sockets[socketIndex].state);

                    return SUCCESS;
                }
                break;

            case FIN_WAIT:
                dbg(TRANSPORT_CHANNEL, "Socket %d in FIN_WAIT. Transitioning to CLOSED.\n", fd);

                dbg(TRANSPORT_CHANNEL, "Before FIN_WAIT SWITCH: socket state is ------ %d\n", sockets[socketIndex].state);
                sockets[socketIndex].state = CLOSED;
                dbg(TRANSPORT_CHANNEL, "After FIN_WAIT SWITCH: socket state is ------ %d\n", sockets[socketIndex].state);

                return SUCCESS;

            default:
                dbg(TRANSPORT_CHANNEL, "Socket %d not in a valid state for closing\n", fd);
                return FAIL;
        }

        return FAIL;
    }

    // Event: Handle retransmissions
    // event void RetransmitTimer.fired() {
    //     uint8_t i;

    //     dbg(TRANSPORT_CHANNEL, "Timeout! Checking packets for retransmission\n");

    //     for (i = base; i < nextSeqNum; i++) {
    //         if (acked[i % WINDOW_SIZE]) {
    //             dbg(TRANSPORT_CHANNEL, "Skipping retransmit for Seq: %d (already ACKed)\n", i);
    //             continue;
    //         }

    //         if (retries[i % WINDOW_SIZE] < MAX_RETRIES) {
    //             dbg(TRANSPORT_CHANNEL, "Retransmitting Seq: %d\n", i);
    //             call Sender.send(window[i % WINDOW_SIZE], window[i % WINDOW_SIZE].dest);
    //             retries[i % WINDOW_SIZE]++;
    //             dbg(TRANSPORT_CHANNEL, "Retry count for Seq: %d is now %d\n", i, retries[i % WINDOW_SIZE]);
    //         } else {
    //             dbg(TRANSPORT_CHANNEL, "Max retries reached for Seq: %d. Dropping packet.\n", i);
    //         }
    //     }

    //     dbg(TRANSPORT_CHANNEL, "Retransmission state: Base %d, NextSeqNum %d\n", base, nextSeqNum);

    //     if (base < nextSeqNum) {
    //         call RetransmitTimer.startOneShot(RETRANSMIT_TIMEOUT);
    //         dbg(TRANSPORT_CHANNEL, "Retransmit timer restarted.\n");
    //     } else {
    //         dbg(TRANSPORT_CHANNEL, "No unacknowledged packets. Stopping retransmit timer.\n");
    //     }
    // }


    event void RetransmitTimer.fired() {
        uint8_t i;

        dbg(TRANSPORT_CHANNEL, "Timeout! Checking packets for retransmission\n");

        for (i = base; i < nextSeqNum; i++) {
            if (acked[i % WINDOW_SIZE]) {
                dbg(TRANSPORT_CHANNEL, "Skipping retransmit for Seq: %d (already ACKed)\n", i);
                continue;
            }

            if (retries[i % WINDOW_SIZE] < MAX_RETRIES) {
                dbg(TRANSPORT_CHANNEL, "Retransmitting Seq: %d\n", i);
                call Sender.send(window[i % WINDOW_SIZE], window[i % WINDOW_SIZE].dest);
                retries[i % WINDOW_SIZE]++;
                dbg(TRANSPORT_CHANNEL, "Retry count for Seq: %d is now %d\n", i, retries[i % WINDOW_SIZE]);
            } else {
                dbg(TRANSPORT_CHANNEL, "Max retries reached for Seq: %d. Dropping packet.\n", i);
            }
        }

        dbg(TRANSPORT_CHANNEL, "Retransmission state: Base %d, NextSeqNum %d\n", base, nextSeqNum);

        if (base < nextSeqNum) {
            call RetransmitTimer.startOneShot(RETRANSMIT_TIMEOUT);
            dbg(TRANSPORT_CHANNEL, "Retransmit timer restarted.\n");
        } else {
            dbg(TRANSPORT_CHANNEL, "No unacknowledged packets. Stopping retransmit timer.\n");
        }
    
    }

    // Event: Handle incoming packets
    // event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
    //     pack* receivedPacket = (pack*)payload;
    //     pack synAckPacket;
    //     pack ackPacket;

    //     uint8_t socketIndex;

    //     transport_header_t header;
    //     parseTransportHeader(receivedPacket, &header);

    //     // dbg(TRANSPORT_CHANNEL, "Processing packet: Flags %x, Seq %d, Protocol %d\n",
    //     //     header.flags, header.seqNum, receivedPacket->protocol);

    //     if (receivedPacket->protocol == PROTOCOL_TCP) {
    //         // Process SYN
    //         if (header.flags & FLAG_SYN) {
    //             dbg(TRANSPORT_CHANNEL, "SYN received. Sending SYN-ACK.\n");
    //             createTransportHeader(&synAckPacket, receivedPacket->dest, receivedPacket->src, FLAG_SYN | FLAG_ACK, 0, WINDOW_SIZE);
    //             call Sender.send(synAckPacket, receivedPacket->src);
    //         }

    //         // Process SYN-ACK
    //         if ((header.flags & FLAG_SYN) && (header.flags & FLAG_ACK)) {
    //             dbg(TRANSPORT_CHANNEL, "SYN-ACK received. Connection established.\n");
                
    //             socketIndex = findSocket(receivedPacket->dest);
    //             if (socketIndex != MAX_NUM_OF_SOCKETS) {
    //                 sockets[socketIndex].state = ESTABLISHED;
    //             }
    //         }

    //         // Process ACK
    //         if (header.flags & FLAG_ACK) {
    //             dbg(TRANSPORT_CHANNEL, "ACK received for Seq: %d\n", header.seqNum);
    //             if (header.seqNum >= base && header.seqNum < nextSeqNum) {
    //                 acked[header.seqNum % WINDOW_SIZE] = TRUE;

    //                 //slide the window
    //                 while (acked[base % WINDOW_SIZE]) {
    //                     acked[base % WINDOW_SIZE] = FALSE;
    //                     base++;
    //                     dbg(TRANSPORT_CHANNEL, "Sliding window. New base: %d\n", base);
    //                 }

    //                 if (base == nextSeqNum) {
    //                     call RetransmitTimer.stop();
    //                     dbg(TRANSPORT_CHANNEL, "All packets acknowledged. Stopping timer.\n");
    //                 }
    //             } else {
    //                 dbg(TRANSPORT_CHANNEL, "Unexpected ACK SeqNum: %d (Base: %d, NextSeqNum: %d)\n",
    //                     header.seqNum, base, nextSeqNum);
    //             }

    //             dbg(TRANSPORT_CHANNEL, "(a) Processing ACK for Seq: %d\n", header.seqNum);
    //         }


    //         // Process FIN
    //         if (header.flags & FLAG_FIN) {
    //             dbg(TRANSPORT_CHANNEL, "FIN received. Closing connection.\n");
                
    //             socketIndex = findSocket(receivedPacket->dest);
    //             if (socketIndex != MAX_NUM_OF_SOCKETS) {
    //                 sockets[socketIndex].state = CLOSED;
    //             }
    //         }

    //         // **Process Data Packet and Send ACK**
    //         if ((header.flags & FLAG_ACK) == 0) { // If this is a data packet (no ACK flag set)
    //             dbg(TRANSPORT_CHANNEL, "Data packet received. Sending ACK for Seq: %d\n", header.seqNum);
    //             createTransportHeader(&ackPacket, receivedPacket->dest, receivedPacket->src, FLAG_ACK, header.seqNum, WINDOW_SIZE);
    //             call Sender.send(ackPacket, receivedPacket->src);
    //         }
    //     }

    //     return msg;
    // }

    // Event: Handle incoming packets (enhance existing Receive.receive)
    // event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
    //     pack* receivedPacket = (pack*) payload;
    //     pack responsePacket;

    //     uint8_t socketIndex = findSocket(receivedPacket->dest);

    //     transport_header_t header;
    //     parseTransportHeader(receivedPacket, &header);

    //     // Check if it's a valid TCP packet
    //     if (receivedPacket->protocol == PROTOCOL_TCP) {
    //         // Handle SYN (connection initiation)
    //         if (header.flags & FLAG_SYN) {
    //             dbg(TRANSPORT_CHANNEL, "SYN received on port %d. Preparing SYN-ACK.\n", receivedPacket->dest);
    //             if (socketIndex != MAX_NUM_OF_SOCKETS && sockets[socketIndex].state == LISTEN) {
    //                 sockets[socketIndex].state = SYN_RCVD;

    //                 // Prepare and send SYN-ACK
    //                 createTransportHeader(&responsePacket, receivedPacket->dest, receivedPacket->src, FLAG_SYN | FLAG_ACK, 0, WINDOW_SIZE);
    //                 call Sender.send(responsePacket, receivedPacket->src);
    //                 dbg(TRANSPORT_CHANNEL, "SYN-ACK sent from port %d to %d.\n", receivedPacket->dest, receivedPacket->src);
    //             }
    //         }

    //         // Handle SYN-ACK (client response to server)
    //         if ((header.flags & FLAG_SYN) && (header.flags & FLAG_ACK)) {
    //             dbg(TRANSPORT_CHANNEL, "SYN-ACK received. Connection established.\n");
    //             if (socketIndex != MAX_NUM_OF_SOCKETS && sockets[socketIndex].state == SYN_SENT) {
    //                 sockets[socketIndex].state = ESTABLISHED;

    //                 // Send ACK to complete handshake
    //                 createTransportHeader(&responsePacket, receivedPacket->dest, receivedPacket->src, FLAG_ACK, header.seqNum + 1, WINDOW_SIZE);
    //                 call Sender.send(responsePacket, receivedPacket->src);
    //                 dbg(TRANSPORT_CHANNEL, "ACK sent. Connection established.\n");
    //             }
    //         }

    //         // Handle FIN (connection teardown)
    //         if (header.flags & FLAG_FIN) {
    //             dbg(TRANSPORT_CHANNEL, "FIN received on socket %d. Sending ACK and transitioning.\n", receivedPacket->dest);
    //             if (socketIndex != MAX_NUM_OF_SOCKETS) {
    //                 if (sockets[socketIndex].state == ESTABLISHED) {
    //                     sockets[socketIndex].state = FIN_WAIT;

    //                     // Send ACK
    //                     createTransportHeader(&responsePacket, receivedPacket->dest, receivedPacket->src, FLAG_ACK, header.seqNum + 1, WINDOW_SIZE);
    //                     call Sender.send(responsePacket, receivedPacket->src);

    //                     // Send FIN
    //                     createTransportHeader(&responsePacket, receivedPacket->dest, receivedPacket->src, FLAG_FIN, header.seqNum + 1, WINDOW_SIZE);
    //                     call Sender.send(responsePacket, receivedPacket->src);

    //                     dbg(TRANSPORT_CHANNEL, "FIN sent. Transitioned to TIME_WAIT.\n");
    //                     sockets[socketIndex].state = TIME_WAIT;
    //                 }
    //             }
    //         }

    //         // Handle ACK (finalize teardown)
    //         if (header.flags & FLAG_ACK) {
    //             dbg(TRANSPORT_CHANNEL, "ACK received for socket %d. Closing connection.\n", receivedPacket->dest);
    //             if (socketIndex != MAX_NUM_OF_SOCKETS && sockets[socketIndex].state == TIME_WAIT) {
    //                 sockets[socketIndex].state = CLOSED;
    //                 dbg(TRANSPORT_CHANNEL, "Socket %d is now CLOSED.\n", receivedPacket->dest);
    //             }
    //         }
    //     }
    //     return msg;
    // }

    // event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
    //     pack* receivedPacket = (pack*) payload;
    //     pack responsePacket;
    //     uint8_t socketIndex;

    //     transport_header_t header;
    //     parseTransportHeader(receivedPacket, &header);

    //     socketIndex = findSocket(receivedPacket->dest);
    //     if (receivedPacket->protocol != PROTOCOL_TCP) {
    //         // dbg(TRANSPORT_CHANNEL, "Non-TCP packet received. Ignoring.\n");
    //         return msg; // Ignore non-TCP packets
    //     }

    //     // Validate socket index
    //     if (socketIndex == MAX_NUM_OF_SOCKETS) {
    //         dbg(TRANSPORT_CHANNEL, "Invalid socket for destination %d. Packet dropped.\n", receivedPacket->dest);
    //         return msg; // Drop packet for invalid sockets
    //     }

    //     switch (sockets[socketIndex].state) {
    //         case LISTEN:
    //             if (header.flags & FLAG_SYN) {
    //                 dbg(TRANSPORT_CHANNEL, "SYN received on port %d. Transitioning to SYN_RCVD.\n", receivedPacket->dest);
    //                 sockets[socketIndex].state = SYN_RCVD;

    //                 // Prepare and send SYN-ACK
    //                 createTransportHeader(&responsePacket, receivedPacket->dest, receivedPacket->src, FLAG_SYN | FLAG_ACK, 0, WINDOW_SIZE);
    //                 call Sender.send(responsePacket, receivedPacket->src);

    //                 dbg(TRANSPORT_CHANNEL, "SYN-ACK sent from port %d to %d.\n", receivedPacket->dest, receivedPacket->src);
    //             }
    //             break;

    //         case SYN_SENT:
    //             if ((header.flags & FLAG_SYN) && (header.flags & FLAG_ACK)) {
    //                 dbg(TRANSPORT_CHANNEL, "SYN-ACK received. Transitioning to ESTABLISHED.\n");
    //                 sockets[socketIndex].state = ESTABLISHED;

    //                 // Send ACK to complete handshake
    //                 createTransportHeader(&responsePacket, receivedPacket->dest, receivedPacket->src, FLAG_ACK, header.seqNum + 1, WINDOW_SIZE);
    //                 call Sender.send(responsePacket, receivedPacket->src);

    //                 dbg(TRANSPORT_CHANNEL, "ACK sent. Connection established.\n");
    //             }
    //             break;

    //         case ESTABLISHED:
    //             if (header.flags & FLAG_FIN) {
    //                 dbg(TRANSPORT_CHANNEL, "FIN received on socket %d. Transitioning to FIN_WAIT.\n", receivedPacket->dest);
    //                 sockets[socketIndex].state = FIN_WAIT;

    //                 // Send ACK for FIN
    //                 createTransportHeader(&responsePacket, receivedPacket->dest, receivedPacket->src, FLAG_ACK, header.seqNum + 1, WINDOW_SIZE);
    //                 call Sender.send(responsePacket, receivedPacket->src);

    //                 // Send FIN to initiate teardown
    //                 createTransportHeader(&responsePacket, receivedPacket->dest, receivedPacket->src, FLAG_FIN, header.seqNum + 1, WINDOW_SIZE);
    //                 call Sender.send(responsePacket, receivedPacket->src);

    //                 dbg(TRANSPORT_CHANNEL, "FIN sent. Transitioned to TIME_WAIT.\n");
    //                 sockets[socketIndex].state = TIME_WAIT;
    //             }
    //             break;

    //         case FIN_WAIT:
    //             if (header.flags & FLAG_ACK) {
    //                 dbg(TRANSPORT_CHANNEL, "ACK received for socket %d. Transitioning to CLOSED.\n", receivedPacket->dest);
    //                 sockets[socketIndex].state = CLOSED;
    //                 dbg(TRANSPORT_CHANNEL, "Socket %d is now CLOSED.\n", receivedPacket->dest);
    //             }
    //             break;

    //         case TIME_WAIT:
    //             if (header.flags & FLAG_ACK) {
    //                 dbg(TRANSPORT_CHANNEL, "ACK received during TIME_WAIT. Socket %d is now CLOSED.\n", receivedPacket->dest);
    //                 sockets[socketIndex].state = CLOSED;
    //             }
    //             break;

    //         default:
    //             dbg(TRANSPORT_CHANNEL, "Unhandled state %d for socket %d. Packet ignored.\n", sockets[socketIndex].state, receivedPacket->dest);
    //             break;
    //     }

    //     return msg;
    // }

    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
        pack* receivedPacket = (pack*) payload;
        pack responsePacket;
        uint8_t socketIndex;

        transport_header_t header;
        parseTransportHeader(receivedPacket, &header);

        if (receivedPacket->protocol != PROTOCOL_TCP) {
            return msg; // Ignore non-TCP packets
        }

        socketIndex = findSocketByAddress(receivedPacket->dest, receivedPacket->src);
        if (socketIndex == MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "Invalid socket for destination %d. Packet dropped.\n", receivedPacket->dest);
            return msg; // Drop packet for invalid sockets
        }


        dbg(TRANSPORT_CHANNEL, "Handling packet for socket %d in state %d\n", socketIndex, sockets[socketIndex].state);
        switch (sockets[socketIndex].state) {
            case LISTEN:
                if (header.flags & FLAG_SYN) {
                    dbg(TRANSPORT_CHANNEL, "SYN received on port %d. Transitioning to SYN_RCVD.\n", receivedPacket->dest);


                    dbg(TRANSPORT_CHANNEL, "Before LISTEN CASE: socket state is ------ %d\n", sockets[socketIndex].state);
                    sockets[socketIndex].state = SYN_RCVD;
                    dbg(TRANSPORT_CHANNEL, "After LISTEN CASE: socket state is ------ %d\n", sockets[socketIndex].state);

                    // Prepare and send SYN-ACK
                    createTransportHeader(&responsePacket, receivedPacket->dest, receivedPacket->src, FLAG_SYN | FLAG_ACK, 0, WINDOW_SIZE);
                    call Sender.send(responsePacket, receivedPacket->src);

                    dbg(TRANSPORT_CHANNEL, "SYN-ACK sent from port %d to %d.\n", receivedPacket->dest, receivedPacket->src);
                }
                break;

            case SYN_SENT:
                if ((header.flags & FLAG_SYN) && (header.flags & FLAG_ACK)) {
                    dbg(TRANSPORT_CHANNEL, "SYN-ACK received. Transitioning to ESTABLISHED.\n");


                    dbg(TRANSPORT_CHANNEL, "Before SYN_SENT CASE: socket state is ------ %d\n", sockets[socketIndex].state);
                    sockets[socketIndex].state = ESTABLISHED;
                    dbg(TRANSPORT_CHANNEL, "After SY_SENT CASE: socket state is ------ %d\n", sockets[socketIndex].state);

                    // Send ACK to complete handshake
                    createTransportHeader(&responsePacket, receivedPacket->dest, receivedPacket->src, FLAG_ACK, header.seqNum + 1, WINDOW_SIZE);
                    call Sender.send(responsePacket, receivedPacket->src);

                    dbg(TRANSPORT_CHANNEL, "ACK sent. Connection established.\n");
                }
                break;

            case ESTABLISHED:
                if (header.flags & FLAG_FIN) {
                    dbg(TRANSPORT_CHANNEL, "FIN received on socket %d. Transitioning to FIN_WAIT.\n", receivedPacket->dest);

                    dbg(TRANSPORT_CHANNEL, "Before ESTABLISHED CASE: socket state is ------ %d\n", sockets[socketIndex].state);
                    sockets[socketIndex].state = FIN_WAIT;
                    dbg(TRANSPORT_CHANNEL, "After ESTABLISHED CASE: socket state is ------ %d\n", sockets[socketIndex].state);

                    // Send ACK for FIN
                    createTransportHeader(&responsePacket, receivedPacket->dest, receivedPacket->src, FLAG_ACK, header.seqNum + 1, WINDOW_SIZE);
                    call Sender.send(responsePacket, receivedPacket->src);

                    dbg(TRANSPORT_CHANNEL, "ACK sent for FIN.\n");
                } else if (header.flags & FLAG_ACK) {
                    // Handle ACK for data packets
                    if (header.seqNum >= base && header.seqNum < nextSeqNum) {
                        acked[header.seqNum % WINDOW_SIZE] = TRUE;
                        dbg(TRANSPORT_CHANNEL, "ACK received for Seq: %d\n", header.seqNum);

                        // Slide the window if the base packet is acknowledged
                        while (acked[base % WINDOW_SIZE]) {
                            dbg(TRANSPORT_CHANNEL, "Sliding window: Base %d acknowledged\n", base);
                            acked[base % WINDOW_SIZE] = FALSE;
                            base++;
                        }
                    }else {
                        dbg(TRANSPORT_CHANNEL, "Unexpected ACK for Seq: %d. Ignored.\n", header.seqNum);
                    }
                }
                break;

            case FIN_WAIT:
                if (header.flags & FLAG_ACK) {
                    dbg(TRANSPORT_CHANNEL, "ACK received for socket %d. Transitioning to CLOSED.\n", receivedPacket->dest);

                    dbg(TRANSPORT_CHANNEL, "Before FIN_WAIT CASE: socket state is ------ %d\n", sockets[socketIndex].state);
                    sockets[socketIndex].state = CLOSED;
                    dbg(TRANSPORT_CHANNEL, "After FIN_WAIT CASE: socket state is ------ %d\n", sockets[socketIndex].state);

                    dbg(TRANSPORT_CHANNEL, "Socket %d is now CLOSED.\n", receivedPacket->dest);
                }
                break;

            case TIME_WAIT:
                if (header.flags & FLAG_ACK) {
                    dbg(TRANSPORT_CHANNEL, "ACK received during TIME_WAIT. Socket %d is now CLOSED.\n", receivedPacket->dest);
                    
                    dbg(TRANSPORT_CHANNEL, "Before TIME_WAIT CASE: socket state is ------ %d\n", sockets[socketIndex].state);
                    sockets[socketIndex].state = CLOSED;
                    dbg(TRANSPORT_CHANNEL, "After TIME_WAIT CASE: socket state is ------ %d\n", sockets[socketIndex].state);
                }
                break;

            default:
                dbg(TRANSPORT_CHANNEL, "Unhandled state %d for socket %d. Packet ignored.\n", sockets[socketIndex].state, receivedPacket->dest);
                break;
        }

        return msg;
    }


    // command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen) {
    //     transport_header_t header;

    //     uint8_t socketIndex = findSocket(fd);
    //     if (socketIndex == MAX_NUM_OF_SOCKETS) {
    //         dbg(TRANSPORT_CHANNEL, "Socket %d not found for writing\n", fd);
    //         return FAIL;
    //     }

    //     if ((nextSeqNum - base) >= WINDOW_SIZE) {
    //         dbg(TRANSPORT_CHANNEL, "Write failed: Window full! Cannot send more packets.\n");
    //         return EBUSY;
    //     }

    //     // Initialize the packet with default values
    //     initTransportHeader(&window[nextSeqNum % WINDOW_SIZE]);

    //     // Customize the header
    //     header.flags = 0; // Add relevant flags
    //     header.seqNum = nextSeqNum;
    //     header.advertisedWindow = WINDOW_SIZE - (nextSeqNum - base);;

    //     memcpy(window[nextSeqNum % WINDOW_SIZE].payload, &header, sizeof(transport_header_t));
    //     memcpy(&window[nextSeqNum % WINDOW_SIZE].payload[sizeof(transport_header_t)], buff, bufflen);

    //     // dbg(TRANSPORT_CHANNEL, "Packet Seq: %d created with payload length: %d\n", nextSeqNum, bufflen);
    //     dbg(TRANSPORT_CHANNEL, "Packet created: Seq %d, WindowSize %d, Payload: %s\n",
    //         header.seqNum, header.advertisedWindow, window[nextSeqNum % WINDOW_SIZE].payload);

    //     // Send the packet
    //     if (call Sender.send(window[nextSeqNum % WINDOW_SIZE], sockets[socketIndex].dest.addr) != SUCCESS) {
    //         dbg(TRANSPORT_CHANNEL, "Failed to send packet Seq: %d\n", nextSeqNum);
    //         return FAIL;
    //     }

    //     acked[nextSeqNum % WINDOW_SIZE] = FALSE;
    //     if (base == nextSeqNum) {
    //         call RetransmitTimer.startOneShot(1000);
    //         dbg(TRANSPORT_CHANNEL, "Starting retransmit timer for base Seq: %d\n", base);
    //     }

    //     nextSeqNum++;
    //     dbg(TRANSPORT_CHANNEL, "Sliding window updated: Base %d, NextSeqNum %d\n", base, nextSeqNum);
    //     return SUCCESS;
    // }

    command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        uint16_t bytesToSend;
        uint16_t chunkSize;

        uint8_t socketIndex = findSocket(fd);
        if (socketIndex == MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "Socket %d not found for writing.\n", fd);
            return FAIL;
        }

        if ((nextSeqNum - base) >= WINDOW_SIZE) {
            dbg(TRANSPORT_CHANNEL, "Write failed: Window full! Cannot send more packets.\n");
            return EBUSY;
        }

        // Fragment data based on available window size
        bytesToSend = bufflen;
        while (bytesToSend > 0 && (nextSeqNum - base) < WINDOW_SIZE) {
            chunkSize = MIN(bytesToSend, WINDOW_SIZE - (nextSeqNum - base));

            // Prepare transport header and packet
            createTransportHeader(&window[nextSeqNum % WINDOW_SIZE], sockets[socketIndex].src, sockets[socketIndex].dest.port, 0, nextSeqNum, WINDOW_SIZE);
            memcpy(&window[nextSeqNum % WINDOW_SIZE].payload[sizeof(transport_header_t)], buff, chunkSize);

            // Attempt to send packet
            if (call Sender.send(window[nextSeqNum % WINDOW_SIZE], sockets[socketIndex].dest.addr) != SUCCESS) {
                dbg(TRANSPORT_CHANNEL, "Failed to send packet Seq: %d.\n", nextSeqNum);
                return FAIL;
            }

            acked[nextSeqNum % WINDOW_SIZE] = FALSE;
            if (base == nextSeqNum) {
                call RetransmitTimer.startOneShot(RETRANSMIT_TIMEOUT);
                dbg(TRANSPORT_CHANNEL, "Retransmit timer started for base Seq: %d.\n", base);
            }

            nextSeqNum++;
            bytesToSend -= chunkSize;
            buff += chunkSize;
        }

        dbg(TRANSPORT_CHANNEL, "Sliding window updated: Base %d, NextSeqNum %d.\n", base, nextSeqNum);
        return bufflen - bytesToSend;
    }

    command socket_t Transport.accept(socket_t fd) {
        uint8_t socketIndex = findSocket(fd);
        if (socketIndex == MAX_NUM_OF_SOCKETS || sockets[socketIndex].state != LISTEN) {
            dbg(TRANSPORT_CHANNEL, "Socket %d not in LISTEN state for accept.\n", fd);
            return NULL_SOCKET;
        }


        dbg(TRANSPORT_CHANNEL, "Before ACCEPT FUNCTION: socket state is ------ %d\n", sockets[socketIndex].state);
        sockets[socketIndex].state = ESTABLISHED;
        dbg(TRANSPORT_CHANNEL, "After ACCEPT FUNCTION: socket state is ------ %d\n", sockets[socketIndex].state);

        dbg(TRANSPORT_CHANNEL, "Socket %d transitioned to ESTABLISHED state.\n", fd);
        return fd;
    }

    command error_t Transport.release(socket_t fd) {
        uint8_t socketIndex = findSocket(fd);
        if (socketIndex == MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "Socket %d not found for release.\n", fd);
            return FAIL;
        }

        dbg(TRANSPORT_CHANNEL, "Before RELEASE FUNCTION: socket state is ------ %d\n", sockets[socketIndex].state);
        sockets[socketIndex].state = CLOSED;
        dbg(TRANSPORT_CHANNEL, "After RELEASE FUNCTION: socket state is ------ %d\n", sockets[socketIndex].state);

        dbg(TRANSPORT_CHANNEL, "Socket %d resources released and state set to CLOSED.\n", fd);
        return SUCCESS;
    }

    command error_t Transport.receive(pack *package) {
        uint16_t payloadLen;
        pack ackPacket;

        uint8_t socketIndex = findSocket(package->dest);

        transport_header_t header;
        parseTransportHeader(package, &header);

        if (socketIndex == MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "Socket %d not found for receiving data.\n", package->dest);
            return FAIL;
        }

        // Store the payload in the socket's receive buffer
        payloadLen = sizeof(package->payload) - sizeof(transport_header_t);
        memcpy(&sockets[socketIndex].rcvdBuff[sockets[socketIndex].nextExpected], &package->payload[sizeof(transport_header_t)], payloadLen);

        sockets[socketIndex].nextExpected += payloadLen;
        dbg(TRANSPORT_CHANNEL, "Data received: Seq %d, Payload: %s\n", header.seqNum, &package->payload[sizeof(transport_header_t)]);

        // Send acknowledgment
        createTransportHeader(&ackPacket, package->dest, package->src, FLAG_ACK, header.seqNum + 1, WINDOW_SIZE);
        call Sender.send(ackPacket, package->src);

        return SUCCESS;
    }

    command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        uint16_t bytesToRead;

        uint8_t socketIndex = findSocket(fd);
        if (socketIndex == MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "Socket %d not found for reading.\n", fd);
            return 0;
        }

        bytesToRead = MIN(bufflen, sockets[socketIndex].nextExpected - sockets[socketIndex].lastRead);
        memcpy(buff, &sockets[socketIndex].rcvdBuff[sockets[socketIndex].lastRead], bytesToRead);

        sockets[socketIndex].lastRead += bytesToRead;
        dbg(TRANSPORT_CHANNEL, "Read %d bytes from socket %d.\n", bytesToRead, fd);
        return bytesToRead;
    }

    // command bool Transport.getSocketData(uint8_t socketIndex, socket_t *socketData) {
    //     if (socketIndex >= MAX_NUM_OF_SOCKETS) {
    //         return FALSE; // Invalid socketIndex
    //     }

    //     *socketData = sockets[socketIndex]; // Copy socketData data
    //     return TRUE;
    // }

    command bool Transport.getSocketData(uint8_t sockIndex, socket_store_t *sockData) {
        if (sockIndex >= MAX_NUM_OF_SOCKETS) {
            return FALSE; // Invalid index
        }
        *sockData = sockets[sockIndex]; // Copy socket data
        return TRUE;
    }
}
