// #include "../../includes/socket.h"
// #include "../../includes/channels.h"
// #include "../../includes/packet.h"
// #include "../../includes/protocol.h"


// module TransportP {
//     provides interface Transport;
//     uses interface Timer<TMilli> as ConnectionTimer;
// }

// implementation {
//     socket_store_t sockets[MAX_NUM_OF_SOCKETS];
//     uint8_t global_fd = 0;  // File descriptor counter for active connections

//     command socket_t Transport.socket() {
//         // Find an available socket slot
//         for (int i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
//             if (sockets[i].state == CLOSED) {
//                 sockets[i].state = LISTEN;
//                 return i;
//             }
//         }
//         return -1;  // No available socket
//     }

//     command error_t Transport.bind(socket_t fd, socket_addr_t *addr) {
//         if (fd < 0 || fd >= MAX_NUM_OF_SOCKETS) return FAIL;
//         sockets[fd].src = addr->port;
//         sockets[fd].dest = *addr;
//         return SUCCESS;
//     }

//     command error_t Transport.connect(socket_t fd, socket_addr_t *dest) {
//         if (fd < 0 || fd >= MAX_NUM_OF_SOCKETS) return FAIL;

//         sockets[fd].state = SYN_SENT;
//         sockets[fd].seq = 1;  // Initial sequence number
//         sockets[fd].ack_num = 0;
//         sockets[fd].dest = *dest;

//         // Send SYN packet to initiate connection
//         pack synPacket;
//         makePack(&synPacket, sockets[fd].src, dest->port, MAX_TTL, PROTOCOL_TCP, sockets[fd].seq, NULL, 0);
//         synPacket.flags |= SYN;
//         call SimpleSend.send(synPacket, dest->addr);
//         dbg(TRANSPORT_CHANNEL, "SYN packet sent to node %d, port %d\n", dest->addr, dest->port);
        
//         return SUCCESS;
//     }

//     command error_t Transport.close(socket_t fd) {
//         if (fd < 0 || fd >= MAX_NUM_OF_SOCKETS) return FAIL;

//         // Send FIN packet to close connection
//         pack finPacket;
//         makePack(&finPacket, sockets[fd].src, sockets[fd].dest.port, MAX_TTL, PROTOCOL_TCP, sockets[fd]. , NULL, 0);
//         finPacket.flags |= FIN;
//         call SimpleSend.send(finPacket, sockets[fd].dest.addr);
//         sockets[fd].state = FIN_WAIT;
//         dbg(TRANSPORT_CHANNEL, "FIN packet sent to node %d, port %d\n", sockets[fd].dest.addr, sockets[fd].dest.port);

//         return SUCCESS;
//     }

//     command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t len) {
//         if (fd < 0 || fd >= MAX_NUM_OF_SOCKETS || sockets[fd].state != ESTABLISHED) return 0;

//         // Prepare data packet
//         pack dataPacket;
//         makePack(&dataPacket, sockets[fd].src, sockets[fd].dest.port, MAX_TTL, PROTOCOL_TCP, sockets[fd].seq, buff, len);
//         dataPacket.flags |= PSH;  // Use PSH to signify data packet

//         // Send data packet
//         call SimpleSend.send(dataPacket, sockets[fd].dest.addr);
//         dbg(TRANSPORT_CHANNEL, "Data packet sent with sequence number %d\n", sockets[fd].seq);

//         // Update sequence number and buffer state
//         sockets[fd].seq += len;
//         return len;
//     }

//     event void Receive.receive(pack* packet) {
//         socket_t fd = findSocket(packet->src, packet->dest);

//         // Ignore if no matching socket
//         if (fd == -1) return;

//         // **Connection Setup and Teardown Handling**
//         if (packet->flags & SYN) {
//             if (sockets[fd].state == LISTEN) {
//                 sockets[fd].state = SYN_RCVD;
//                 sockets[fd].ack_num = packet->seq + 1;

//                 // Send SYN-ACK response
//                 pack synAckPacket;
//                 makePack(&synAckPacket, sockets[fd].src, packet->src, MAX_TTL, PROTOCOL_TCP, sockets[fd].seq, NULL, 0);
//                 synAckPacket.flags |= SYN | ACK;
//                 call SimpleSend.send(synAckPacket, packet->src);
//                 dbg(TRANSPORT_CHANNEL, "SYN-ACK packet sent to node %d\n", packet->src);
//             }
//         } else if (packet->flags & ACK && sockets[fd].state == SYN_SENT) {
//             sockets[fd].state = ESTABLISHED;
//             dbg(TRANSPORT_CHANNEL, "Connection established with node %d\n", packet->src);
//         } else if (packet->flags & FIN) {
//             sockets[fd].state = CLOSED_WAIT;
//             sockets[fd].ack_num = packet->seq + 1;

//             // Send ACK for FIN
//             pack ackPacket;
//             makePack(&ackPacket, sockets[fd].src, packet->src, MAX_TTL, PROTOCOL_TCP, sockets[fd].seq, NULL, 0);
//             ackPacket.flags |= ACK;
//             call SimpleSend.send(ackPacket, packet->src);
//             dbg(TRANSPORT_CHANNEL, "ACK for FIN packet sent to node %d\n", packet->src);

//             return;  // End connection teardown handling
//         }

//         // **Data Transfer Handling (Stop-and-Wait)**
//         if (packet->flags & PSH) {
//             // Data packet received, send ACK
//             pack ackPacket;
//             makePack(&ackPacket, sockets[fd].src, packet->src, MAX_TTL, PROTOCOL_TCP, sockets[fd].seq, NULL, 0);
//             ackPacket.flags |= ACK;
//             call SimpleSend.send(ackPacket, packet->src);

//             dbg(TRANSPORT_CHANNEL, "ACK sent for data packet from node %d\n", packet->src);

//             // Optional: Pass received data to application layer
//             memcpy(sockets[fd].recvBuff, packet->payload, len);
//         }
//     }
//     // event void Receive.receive(pack* packet) {
//     //     // Handle incoming packets for connection setup/teardown
//     //     socket_t fd = findSocket(packet->src, packet->dest);
//     //     if (fd == -1) return; // Ignore if no matching socket

//     //     if (packet->flags & SYN) {
//     //         if (sockets[fd].state == LISTEN) {
//     //             sockets[fd].state = SYN_RCVD;
//     //             sockets[fd].ack_num = packet->seq + 1;

//     //             // Send SYN-ACK response
//     //             pack synAckPacket;
//     //             makePack(&synAckPacket, sockets[fd].src, packet->src, MAX_TTL, PROTOCOL_TCP, sockets[fd].seq, NULL, 0);
//     //             synAckPacket.flags |= SYN | ACK;
//     //             call SimpleSend.send(synAckPacket, packet->src);
//     //             dbg(TRANSPORT_CHANNEL, "SYN-ACK packet sent to node %d\n", packet->src);
//     //         }
//     //     } else if (packet->flags & ACK && sockets[fd].state == SYN_SENT) {
//     //         sockets[fd].state = ESTABLISHED;
//     //         dbg(TRANSPORT_CHANNEL, "Connection established with node %d\n", packet->src);
//     //     } else if (packet->flags & FIN) {
//     //         sockets[fd].state = CLOSED_WAIT;
//     //         sockets[fd].ack_num = packet->seq + 1;

//     //         // Send ACK for FIN
//     //         pack ackPacket;
//     //         makePack(&ackPacket, sockets[fd].src, packet->src, MAX_TTL, PROTOCOL_TCP, sockets[fd].seq, NULL, 0);
//     //         ackPacket.flags |= ACK;
//     //         call SimpleSend.send(ackPacket, packet->src);
//     //         dbg(TRANSPORT_CHANNEL, "ACK for FIN packet sent to node %d\n", packet->src);
//     //     }
//     // }
// }



#include "../../includes/socket.h"
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"

module TransportP {
    provides interface Transport;
    uses interface Timer<TMilli> as ConnectionTimer;
    uses interface SimpleSend;
}

implementation {
    socket_store_t sockets[MAX_NUM_OF_SOCKETS];
    uint8_t global_fd = 0;  // File descriptor counter for active connections

    socket_t findSocket(uint16_t src, uint16_t dest) {
        int i;

        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].src == src && sockets[i].dest.port == dest && sockets[i].state != CLOSED) {
                return i;
            }
        }
        return NULL_SOCKET;
    }

    command error_t Transport.listen(socket_t fd) {
        if (fd < 0 || fd >= MAX_NUM_OF_SOCKETS) return FAIL;
        sockets[fd].state = LISTEN;
        return SUCCESS;
    }

    command socket_t Transport.accept(socket_t fd) {
        if (sockets[fd].state == SYN_RCVD) {
            sockets[fd].state = ESTABLISHED;
            return fd;
        }
        return NULL_SOCKET;
    }

    command error_t Transport.receive(pack* packet) {
        socket_t fd = findSocket(packet->src, packet->dest.port);
        if (fd == NULL_SOCKET) return FAIL;

        if (sockets[fd].state == ESTABLISHED) {
            // Handle the received data
            memcpy(sockets[fd].recvBuff, packet->payload, sizeof(packet->payload));
            return SUCCESS;
        }
        return FAIL;
    }

    command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t len) {
        uint16_t dataLen;

        if (fd < 0 || fd >= MAX_NUM_OF_SOCKETS || sockets[fd].state != ESTABLISHED) return 0;

        dataLen = (len < TRANSFER_SIZE) ? len : TRANSFER_SIZE;
        memcpy(buff, sockets[fd].recvBuff, dataLen);
        return dataLen;
    }

    command error_t Transport.release(socket_t fd) {
        if (fd < 0 || fd >= MAX_NUM_OF_SOCKETS) return FAIL;
        sockets[fd].state = CLOSED;
        return SUCCESS;
    }

    command socket_t Transport.socket() {
        int i;
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].state == CLOSED) {
                sockets[i].state = LISTEN;
                return i;
            }
        }
        return NULL_SOCKET;  // Return NULL_SOCKET if no socket is available
    }

    command error_t Transport.bind(socket_t fd, socket_addr_t *addr) {
        if (fd < 0 || fd >= MAX_NUM_OF_SOCKETS) return FAIL;
        sockets[fd].src = addr->port;
        sockets[fd].dest = *addr;
        return SUCCESS;
    }

    command error_t Transport.connect(socket_t fd, socket_addr_t *dest) {
        pack synPacket;

        if (fd < 0 || fd >= MAX_NUM_OF_SOCKETS) return FAIL;

        sockets[fd].state = SYN_SENT;
        sockets[fd].seq = 1;  // Initial sequence number
        sockets[fd].ack_num = 0;
        sockets[fd].dest = *dest;

        makePack(&synPacket, sockets[fd].src, dest->port, MAX_TTL, PROTOCOL_TCP, sockets[fd].seq, NULL, 0);
        synPacket.flags |= SYN;
        call SimpleSend.send(synPacket, dest->addr);
        dbg(TRANSPORT_CHANNEL, "SYN packet sent to node %d, port %d\n", dest->addr, dest->port);
        
        return SUCCESS;
    }

    command error_t Transport.close(socket_t fd) {
        pack finPacket;

        if (fd < 0 || fd >= MAX_NUM_OF_SOCKETS) return FAIL;

        makePack(&finPacket, sockets[fd].src, sockets[fd].dest.port, MAX_TTL, PROTOCOL_TCP, sockets[fd].seq, NULL, 0);
        finPacket.flags |= FIN;
        call SimpleSend.send(finPacket, sockets[fd].dest.addr);
        sockets[fd].state = FIN_WAIT;
        dbg(TRANSPORT_CHANNEL, "FIN packet sent to node %d, port %d\n", sockets[fd].dest.addr, sockets[fd].dest.port);

        return SUCCESS;
    }

    command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t len) {
        pack dataPacket;

        if (fd < 0 || fd >= MAX_NUM_OF_SOCKETS || sockets[fd].state != ESTABLISHED) return 0;

        makePack(&dataPacket, sockets[fd].src, sockets[fd].dest.port, MAX_TTL, PROTOCOL_TCP, sockets[fd].seq, buff, len);
        dataPacket.flags |= PSH;

        call SimpleSend.send(dataPacket, sockets[fd].dest.addr);
        dbg(TRANSPORT_CHANNEL, "Data packet sent with sequence number %d\n", sockets[fd].seq);

        sockets[fd].seq += len;
        return len;
    }

    // Event handler for incoming packets
    event void Receive.receive(pack* packet) {
        socket_t fd = findSocket(packet->src, packet->dest);

        if (fd == NULL_SOCKET) return;

        if (packet->flags & SYN) {
            if (sockets[fd].state == LISTEN) {
                sockets[fd].state = SYN_RCVD;
                sockets[fd].ack_num = packet->seq + 1;

                pack synAckPacket;
                makePack(&synAckPacket, sockets[fd].src, packet->src, MAX_TTL, PROTOCOL_TCP, sockets[fd].seq, NULL, 0);
                synAckPacket.flags |= SYN | ACK;
                call SimpleSend.send(synAckPacket, packet->src);
                dbg(TRANSPORT_CHANNEL, "SYN-ACK packet sent to node %d\n", packet->src);
            }
        } else if (packet->flags & ACK && sockets[fd].state == SYN_SENT) {
            sockets[fd].state = ESTABLISHED;
            dbg(TRANSPORT_CHANNEL, "Connection established with node %d\n", packet->src);
        } else if (packet->flags & FIN) {
            sockets[fd].state = CLOSED_WAIT;
            sockets[fd].ack_num = packet->seq + 1;

            pack ackPacket;
            makePack(&ackPacket, sockets[fd].src, packet->src, MAX_TTL, PROTOCOL_TCP, sockets[fd].seq, NULL, 0);
            ackPacket.flags |= ACK;
            call SimpleSend.send(ackPacket, packet->src);
            dbg(TRANSPORT_CHANNEL, "ACK for FIN packet sent to node %d\n", packet->src);
        }

        if (packet->flags & PSH) {
            pack ackPacket;
            makePack(&ackPacket, sockets[fd].src, packet->src, MAX_TTL, PROTOCOL_TCP, sockets[fd].seq, NULL, 0);
            ackPacket.flags |= ACK;
            call SimpleSend.send(ackPacket, packet->src);

            dbg(TRANSPORT_CHANNEL, "ACK sent for data packet from node %d\n", packet->src);
        }
    }
}
