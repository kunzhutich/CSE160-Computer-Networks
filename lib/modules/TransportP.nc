#include "../../includes/socket.h"
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/utils.h"
#include "../../includes/transport.h"

module TransportP {
    provides interface Transport;
    uses interface Timer<TMilli> as RetransmitTimer;
    uses interface Hashmap<uint8_t> as SocketMap; // For tracking socket states.
    uses interface SimpleSend as Sender;
    uses interface Receive;
}

implementation {
    #define WINDOW_SIZE 4                       // Sliding window size
    #define MAX_RETRIES 5                       // Maximum retransmission attempts
    #define RETRANSMIT_TIMEOUT 1000             // Timeout for retransmissions in milliseconds

    uint8_t base = 0;                           // Sequence number of the first unacknowledged packet
    uint8_t nextSeqNum = 0;                     // Sequence number of the next packet to send
    bool acked[WINDOW_SIZE];                    // Tracks acknowledgment for each packet in the window
    pack window[WINDOW_SIZE];                   // Buffer to store packets in the window
    uint8_t retries[WINDOW_SIZE] = {0};         // Retransmission attempts for each packet

    socket_store_t sockets[MAX_NUM_OF_SOCKETS]; // Array of socket structures
    socket_metadata_t socketMetadata[MAX_NUM_OF_SOCKETS]; // Transport-specific metadata
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
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].state == CLOSED) {
                sockets[i].state = ALLOCATED;       // Set to ALLOCATED state
                sockets[i].flag = i + 1;           // Assign a unique socket ID
                sockets[i].src = 0;                // Clear source port
                sockets[i].dest.addr = 0;          // Clear destination address
                sockets[i].dest.port = 0;          // Clear destination port

                memset(&socketMetadata[i], 0, sizeof(socket_metadata_t)); // Reset metadata
                socketMetadata[i].socketId = i + 1;

                dbg(TRANSPORT_CHANNEL, "Socket %d allocated\n", i + 1);
                return i + 1;                      // Return socket ID
            }
        }
        dbg(TRANSPORT_CHANNEL, "No available sockets\n");
        return NULL_SOCKET; // Indicate failure (no sockets available)
    }

    // Bind a socket to a port
    command error_t Transport.bind(socket_t fd, socket_addr_t *addr) {
        uint8_t socketIndex = findSocket(fd);
        if (socketIndex == MAX_NUM_OF_SOCKETS) return FAIL;

        sockets[socketIndex].src = addr->port; // Assign the source port
        sockets[socketIndex].state = BOUND;   // Transition to BOUND state
        dbg(TRANSPORT_CHANNEL, "Socket %d bound to port %d\n", fd, addr->port);
        return SUCCESS;
    }

    // Transition a socket to LISTEN state
    command error_t Transport.listen(socket_t fd) {
        uint8_t socketIndex = findSocket(fd);
        if (socketIndex == MAX_NUM_OF_SOCKETS) return FAIL;

        if (sockets[socketIndex].state != BOUND) return FAIL;
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

        sockets[socketIndex].state = SYN_SENT;
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
                    sockets[socketIndex].state = FIN_WAIT;
                    return SUCCESS;
                }
                break;

            case FIN_WAIT:
                dbg(TRANSPORT_CHANNEL, "Socket %d in FIN_WAIT. Transitioning to CLOSED.\n", fd);
                sockets[socketIndex].state = CLOSED;
                return SUCCESS;

            default:
                dbg(TRANSPORT_CHANNEL, "Socket %d not in a valid state for closing\n", fd);
                return FAIL;
        }

        return FAIL;
    }

    // Event: Handle retransmissions
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

        if (base < nextSeqNum) {
            call RetransmitTimer.startOneShot(RETRANSMIT_TIMEOUT);
            dbg(TRANSPORT_CHANNEL, "Retransmit timer restarted.\n");
        } else {
            dbg(TRANSPORT_CHANNEL, "No unacknowledged packets. Stopping retransmit timer.\n");
        }
    }


    // Event: Handle incoming packets
    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
        pack* receivedPacket = (pack*)payload;
        pack synAckPacket;
        pack ackPacket;

        uint8_t socketIndex;

        transport_header_t header;
        parseTransportHeader(receivedPacket, &header);

        // dbg(TRANSPORT_CHANNEL, "Processing packet: Flags %x, Seq %d, Protocol %d\n",
        //     header.flags, header.seqNum, receivedPacket->protocol);

        if (receivedPacket->protocol == PROTOCOL_TCP) {
            // Process SYN
            if (header.flags & FLAG_SYN) {
                dbg(TRANSPORT_CHANNEL, "SYN received. Sending SYN-ACK.\n");
                createTransportHeader(&synAckPacket, receivedPacket->dest, receivedPacket->src, FLAG_SYN | FLAG_ACK, 0, WINDOW_SIZE);
                call Sender.send(synAckPacket, receivedPacket->src);
            }

            // Process SYN-ACK
            if ((header.flags & FLAG_SYN) && (header.flags & FLAG_ACK)) {
                dbg(TRANSPORT_CHANNEL, "SYN-ACK received. Connection established.\n");
                
                socketIndex = findSocket(receivedPacket->dest);
                if (socketIndex != MAX_NUM_OF_SOCKETS) {
                    sockets[socketIndex].state = ESTABLISHED;
                }
            }

            // Process ACK
            if (header.flags & FLAG_ACK) {
                dbg(TRANSPORT_CHANNEL, "ACK received for Seq: %d\n", header.seqNum);
                if (header.seqNum >= base && header.seqNum < nextSeqNum) {
                    acked[header.seqNum % WINDOW_SIZE] = TRUE;

                    //slide the window
                    while (acked[base % WINDOW_SIZE]) {
                        acked[base % WINDOW_SIZE] = FALSE;
                        base++;
                        dbg(TRANSPORT_CHANNEL, "Sliding window. New base: %d\n", base);
                    }

                    if (base == nextSeqNum) {
                        call RetransmitTimer.stop();
                        dbg(TRANSPORT_CHANNEL, "All packets acknowledged. Stopping timer.\n");
                    }
                }
                dbg(TRANSPORT_CHANNEL, "(a) Processing ACK for Seq: %d\n", header.seqNum);

            }

            dbg(TRANSPORT_CHANNEL, "(b) Processing ACK for Seq: %d\n", header.seqNum);


            // Process FIN
            if (header.flags & FLAG_FIN) {
                dbg(TRANSPORT_CHANNEL, "FIN received. Closing connection.\n");
                
                socketIndex = findSocket(receivedPacket->dest);
                if (socketIndex != MAX_NUM_OF_SOCKETS) {
                    sockets[socketIndex].state = CLOSED;
                }
            }

            // **Process Data Packet and Send ACK**
            if ((header.flags & FLAG_ACK) == 0) { // If this is a data packet (no ACK flag set)
                dbg(TRANSPORT_CHANNEL, "Data packet received. Sending ACK for Seq: %d\n", header.seqNum);
                createTransportHeader(&ackPacket, receivedPacket->dest, receivedPacket->src, FLAG_ACK, header.seqNum, WINDOW_SIZE);
                call Sender.send(ackPacket, receivedPacket->src);
            }
        }

        return msg;
    }


    command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        transport_header_t header;

        uint8_t socketIndex = findSocket(fd);
        if (socketIndex == MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "Socket %d not found for writing\n", fd);
            return FAIL;
        }

        if ((nextSeqNum - base) >= WINDOW_SIZE) {
            dbg(TRANSPORT_CHANNEL, "Write failed: Window full! Cannot send more packets.\n");
            return EBUSY;
        }

        // Initialize the packet with default values
        initTransportHeader(&window[nextSeqNum % WINDOW_SIZE]);

        // Customize the header
        header.flags = 0; // Add relevant flags
        header.seqNum = nextSeqNum;
        header.advertisedWindow = WINDOW_SIZE - (nextSeqNum - base);;

        memcpy(window[nextSeqNum % WINDOW_SIZE].payload, &header, sizeof(transport_header_t));
        memcpy(&window[nextSeqNum % WINDOW_SIZE].payload[sizeof(transport_header_t)], buff, bufflen);

        dbg(TRANSPORT_CHANNEL, "Packet Seq: %d created with payload length: %d\n", nextSeqNum, bufflen);

        // Send the packet
        if (call Sender.send(window[nextSeqNum % WINDOW_SIZE], sockets[socketIndex].dest.addr) != SUCCESS) {
            dbg(TRANSPORT_CHANNEL, "Failed to send packet Seq: %d\n", nextSeqNum);
            return FAIL;
        }

        acked[nextSeqNum % WINDOW_SIZE] = FALSE;
        if (base == nextSeqNum) {
            call RetransmitTimer.startOneShot(1000);
            dbg(TRANSPORT_CHANNEL, "Starting retransmit timer for base Seq: %d\n", base);
        }

        nextSeqNum++;
        dbg(TRANSPORT_CHANNEL, "Sliding window updated: Base %d, NextSeqNum %d\n", base, nextSeqNum);
        return SUCCESS;
    }


    command error_t Transport.receive(pack *package) {
        dbg(TRANSPORT_CHANNEL, "Transport.receive called but not implemented.\n");
        return SUCCESS;
    }

    command error_t Transport.release(socket_t fd) {
        dbg(TRANSPORT_CHANNEL, "Transport.release called but not implemented.\n");
        return SUCCESS;
    }

    command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        dbg(TRANSPORT_CHANNEL, "Transport.read called but not implemented.\n");
        return 0;
    }

    command socket_t Transport.accept(socket_t fd) {
        dbg(TRANSPORT_CHANNEL, "Transport.accept called but not implemented.\n");
        return NULL_SOCKET;
    }

}
