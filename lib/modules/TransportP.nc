#include "../../includes/socket.h"
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"


module TransportP {
    provides interface Transport;
    uses interface Timer<TMilli> as ConnectionTimer;
}

implementation {
    socket_store_t sockets[MAX_NUM_OF_SOCKETS];
    uint8_t global_fd = 0;  // File descriptor counter for active connections

    command socket_t Transport.socket() {
        // Find an available socket slot
        for (int i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].state == CLOSED) {
                sockets[i].state = LISTEN;
                return i;
            }
        }
        return -1;  // No available socket
    }

    command error_t Transport.bind(socket_t fd, socket_addr_t *addr) {
        if (fd < 0 || fd >= MAX_NUM_OF_SOCKETS) return FAIL;
        sockets[fd].src = addr->port;
        sockets[fd].dest = *addr;
        return SUCCESS;
    }

    command error_t Transport.connect(socket_t fd, socket_addr_t *dest) {
        if (fd < 0 || fd >= MAX_NUM_OF_SOCKETS) return FAIL;

        sockets[fd].state = SYN_SENT;
        sockets[fd].seq_num = 1;  // Initial sequence number
        sockets[fd].ack_num = 0;
        sockets[fd].dest = *dest;

        // Send SYN packet to initiate connection
        pack synPacket;
        makePack(&synPacket, sockets[fd].src, dest->port, MAX_TTL, PROTOCOL_TCP, sockets[fd].seq_num, NULL, 0);
        synPacket.flags |= SYN;
        call SimpleSend.send(synPacket, dest->addr);
        dbg(PROJECT3_CHANNEL, "SYN packet sent to node %d, port %d\n", dest->addr, dest->port);
        
        return SUCCESS;
    }

    command error_t Transport.close(socket_t fd) {
        if (fd < 0 || fd >= MAX_NUM_OF_SOCKETS) return FAIL;

        // Send FIN packet to close connection
        pack finPacket;
        makePack(&finPacket, sockets[fd].src, sockets[fd].dest.port, MAX_TTL, PROTOCOL_TCP, sockets[fd].seq_num, NULL, 0);
        finPacket.flags |= FIN;
        call SimpleSend.send(finPacket, sockets[fd].dest.addr);
        sockets[fd].state = FIN_WAIT;
        dbg(PROJECT3_CHANNEL, "FIN packet sent to node %d, port %d\n", sockets[fd].dest.addr, sockets[fd].dest.port);

        return SUCCESS;
    }

    command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t len) {
        if (fd < 0 || fd >= MAX_NUM_OF_SOCKETS || sockets[fd].state != ESTABLISHED) return 0;

        // Prepare data packet
        pack dataPacket;
        makePack(&dataPacket, sockets[fd].src, sockets[fd].dest.port, MAX_TTL, PROTOCOL_TCP, sockets[fd].seq_num, buff, len);
        dataPacket.flags |= PSH;  // Use PSH to signify data packet

        // Send data packet
        call SimpleSend.send(dataPacket, sockets[fd].dest.addr);
        dbg(PROJECT3_CHANNEL, "Data packet sent with sequence number %d\n", sockets[fd].seq_num);

        // Update sequence number and buffer state
        sockets[fd].seq_num += len;
        return len;
    }

    event void Receive.receive(pack* packet) {
        socket_t fd = findSocket(packet->src, packet->dest);

        // Ignore if no matching socket
        if (fd == -1) return;

        // **Connection Setup and Teardown Handling**
        if (packet->flags & SYN) {
            if (sockets[fd].state == LISTEN) {
                sockets[fd].state = SYN_RCVD;
                sockets[fd].ack_num = packet->seq_num + 1;

                // Send SYN-ACK response
                pack synAckPacket;
                makePack(&synAckPacket, sockets[fd].src, packet->src, MAX_TTL, PROTOCOL_TCP, sockets[fd].seq_num, NULL, 0);
                synAckPacket.flags |= SYN | ACK;
                call SimpleSend.send(synAckPacket, packet->src);
                dbg(PROJECT3_CHANNEL, "SYN-ACK packet sent to node %d\n", packet->src);
            }
        } else if (packet->flags & ACK && sockets[fd].state == SYN_SENT) {
            sockets[fd].state = ESTABLISHED;
            dbg(PROJECT3_CHANNEL, "Connection established with node %d\n", packet->src);
        } else if (packet->flags & FIN) {
            sockets[fd].state = CLOSED_WAIT;
            sockets[fd].ack_num = packet->seq_num + 1;

            // Send ACK for FIN
            pack ackPacket;
            makePack(&ackPacket, sockets[fd].src, packet->src, MAX_TTL, PROTOCOL_TCP, sockets[fd].seq_num, NULL, 0);
            ackPacket.flags |= ACK;
            call SimpleSend.send(ackPacket, packet->src);
            dbg(PROJECT3_CHANNEL, "ACK for FIN packet sent to node %d\n", packet->src);

            return;  // End connection teardown handling
        }

        // **Data Transfer Handling (Stop-and-Wait)**
        if (packet->flags & PSH) {
            // Data packet received, send ACK
            pack ackPacket;
            makePack(&ackPacket, sockets[fd].src, packet->src, MAX_TTL, PROTOCOL_TCP, sockets[fd].seq_num, NULL, 0);
            ackPacket.flags |= ACK;
            call SimpleSend.send(ackPacket, packet->src);

            dbg(PROJECT3_CHANNEL, "ACK sent for data packet from node %d\n", packet->src);

            // Optional: Pass received data to application layer
            memcpy(sockets[fd].recvBuff, packet->payload, len);
        }
    }
    // event void Receive.receive(pack* packet) {
    //     // Handle incoming packets for connection setup/teardown
    //     socket_t fd = findSocket(packet->src, packet->dest);
    //     if (fd == -1) return; // Ignore if no matching socket

    //     if (packet->flags & SYN) {
    //         if (sockets[fd].state == LISTEN) {
    //             sockets[fd].state = SYN_RCVD;
    //             sockets[fd].ack_num = packet->seq_num + 1;

    //             // Send SYN-ACK response
    //             pack synAckPacket;
    //             makePack(&synAckPacket, sockets[fd].src, packet->src, MAX_TTL, PROTOCOL_TCP, sockets[fd].seq_num, NULL, 0);
    //             synAckPacket.flags |= SYN | ACK;
    //             call SimpleSend.send(synAckPacket, packet->src);
    //             dbg(PROJECT3_CHANNEL, "SYN-ACK packet sent to node %d\n", packet->src);
    //         }
    //     } else if (packet->flags & ACK && sockets[fd].state == SYN_SENT) {
    //         sockets[fd].state = ESTABLISHED;
    //         dbg(PROJECT3_CHANNEL, "Connection established with node %d\n", packet->src);
    //     } else if (packet->flags & FIN) {
    //         sockets[fd].state = CLOSED_WAIT;
    //         sockets[fd].ack_num = packet->seq_num + 1;

    //         // Send ACK for FIN
    //         pack ackPacket;
    //         makePack(&ackPacket, sockets[fd].src, packet->src, MAX_TTL, PROTOCOL_TCP, sockets[fd].seq_num, NULL, 0);
    //         ackPacket.flags |= ACK;
    //         call SimpleSend.send(ackPacket, packet->src);
    //         dbg(PROJECT3_CHANNEL, "ACK for FIN packet sent to node %d\n", packet->src);
    //     }
    // }
}
