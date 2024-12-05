#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/utils.h"
#include "../../includes/socket.h"
#include "../../includes/transport.h"

module TransportP {
    provides interface Transport;

    uses interface IP;
    uses interface Timer<TMilli> as Timer;
}

implementation {
    // Define socket storage
    socket_store_t sockets[MAX_NUM_OF_SOCKETS];

    // Helper function to get socket by fd
    socket_store_t* getSocket(socket_t fd) {
        if (fd >= 0 && fd < MAX_NUM_OF_SOCKETS && sockets[fd].flag == 1) {
            return &sockets[fd];
        }
        return NULL;
    }

    command socket_t Transport.socket() {
        // Find an available socket
        socket_t fd;

        uint8_t j;
        dbg(TRANSPORT_CHANNEL, "Listing socket states before Transport.socket: \n");
        for (j = 0; j < MAX_NUM_OF_SOCKETS; j++) {
            dbg(TRANSPORT_CHANNEL, "        Socket %d: state %d, flag %d\n", j, sockets[j].state, sockets[j].flag);
        }

        for (fd = 0; fd < MAX_NUM_OF_SOCKETS; fd++) {
            if (sockets[fd].flag == 0) {
                sockets[fd].flag = 1;
                sockets[fd].state = CLOSED;

                // Basic socket initialization
                sockets[fd].lastWritten = 0;
                sockets[fd].lastAck = 0;
                sockets[fd].lastSent = 0;
                sockets[fd].lastRead = 0;
                sockets[fd].lastRcvd = 0;
                sockets[fd].nextExpected = 0;
                
                // Initialize sender sliding window
                sockets[fd].sendWindowBase = 0;
                sockets[fd].sendWindowSize = SOCKET_BUFFER_SIZE;
                sockets[fd].numUnAcked = 0;
                
                // Initialize receiver sliding window
                sockets[fd].rcvWindowBase = 0;
                sockets[fd].rcvWindowSize = SOCKET_BUFFER_SIZE;
                sockets[fd].numOutOfOrder = 0;

                dbg(TRANSPORT_CHANNEL, "Listing socket states after Transport.socket: \n");
                for (j = 0; j < MAX_NUM_OF_SOCKETS; j++) {
                    dbg(TRANSPORT_CHANNEL, "        Socket %d: state %d, flag %d\n", j, sockets[j].state, sockets[j].flag);
                }

                dbg(TRANSPORT_CHANNEL, "Socket %d allocated\n", fd);

                return fd;
            }
        }
        return -1; // No available sockets
    }

    command error_t Transport.bind(socket_t fd, socket_addr_t *addr) {
        socket_store_t* sock = getSocket(fd);
        if (sock == NULL) return FAIL;

        dbg(TRANSPORT_CHANNEL, "Before BIND | socket %d: state-%d, flag-%d, src-%d\n", fd, sockets[fd].state, sockets[fd].flag, sockets[fd].src);
        sock->src = addr->port;
        dbg(TRANSPORT_CHANNEL, "After BIND | socket %d: state-%d, flag-%d, src-%d\n", fd, sockets[fd].state, sockets[fd].flag, sockets[fd].src);

        return SUCCESS;
    }

    command error_t Transport.listen(socket_t fd) {
        socket_store_t* sock = getSocket(fd);
        if (sock == NULL) return FAIL;

        dbg(TRANSPORT_CHANNEL, "Before LISTEN | socket %d: state-%d, flag-%d, src-%d\n", fd, sockets[fd].state, sockets[fd].flag, sockets[fd].src);
        sock->state = LISTEN;
        dbg(TRANSPORT_CHANNEL, "After LISTEN | socket %d: state-%d, flag-%d, src-%d\n", fd, sockets[fd].state, sockets[fd].flag, sockets[fd].src);

        return SUCCESS;
    }

    command socket_t Transport.accept(socket_t fd) {
        uint8_t i;

        socket_store_t* sock = getSocket(fd);
        if (sock == NULL || sock->state != LISTEN) return -1;

        // Check for pending connections
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].flag == 1 && sockets[i].parentFd == fd && sockets[i].state == SYN_RCVD) {

                dbg(TRANSPORT_CHANNEL, "Before ACCEPT | socket %d: state-%d, flag-%d, src-%d\n", fd, sockets[fd].state, sockets[fd].flag, sockets[fd].src);
                sockets[i].state = ESTABLISHED;
                dbg(TRANSPORT_CHANNEL, "After ACCEPT | socket %d: state-%d, flag-%d, src-%d\n", fd, sockets[fd].state, sockets[fd].flag, sockets[fd].src);

                return i;
            }
        }
        return -1; // No pending connections
    }

    command error_t Transport.connect(socket_t fd, socket_addr_t *addr) {
        transport tHeader;
        pack pck;

        socket_store_t* sock = getSocket(fd);
        if (sock == NULL) return FAIL;

        sock->dest = *addr;
        // sock->dest = addr->port;
        // sock->destAddr = addr->addr;

        // Initialize sequence numbers
        sock->lastSent = 0;
        sock->lastAck = 0;

        // Send SYN packet
        tHeader.srcPort = sock->src;
        tHeader.destPort = sock->dest.port;
        tHeader.seq = sock->lastSent;
        tHeader.ack = 0;
        tHeader.flags = SYN;
        tHeader.window = SOCKET_BUFFER_SIZE - sock->lastRcvd;
        tHeader.length = 0;

        // makePack(&pck, TOS_NODE_ID, sock->destAddr, MAX_TTL, PROTOCOL_TCP, 0, (uint8_t*)&tHeader, sizeof(transport));
        makePack(&pck, TOS_NODE_ID, sock->dest.addr, MAX_TTL, PROTOCOL_TCP, 0, (uint8_t*)&tHeader, sizeof(transport));

        call IP.send(&pck);

        // dbg(TRANSPORT_CHANNEL, "Client received SYN-ACK from %d:%d\n", sock->dest.addr, sock->dest.port);

        dbg(TRANSPORT_CHANNEL, "Before CONNECT | socket %d: state-%d, flag-%d, src-%d\n", fd, sockets[fd].state, sockets[fd].flag, sockets[fd].src);
        sock->state = SYN_SENT;
        dbg(TRANSPORT_CHANNEL, "After CONNECT | socket %d: state-%d, flag-%d, src-%d\n", fd, sockets[fd].state, sockets[fd].flag, sockets[fd].src);

        // Start timer for retransmission if necessary

        return SUCCESS;
    }

    command error_t Transport.close(socket_t fd) {
        transport tHeader;
        pack pck;

        socket_store_t* sock = getSocket(fd);
        if(sock == NULL) return FAIL;

        // Only allow close on ESTABLISHED sockets
        if(sock->state != ESTABLISHED) {
            dbg(TRANSPORT_CHANNEL, "Cannot close socket %d - not in ESTABLISHED state (current state: %d)\n", 
                fd, sock->state);
            return FAIL;
        }


        // Send FIN packet
        tHeader.srcPort = sock->src;
        tHeader.destPort = sock->dest.port;
        tHeader.seq = sock->lastSent;
        tHeader.ack = sock->lastAck;
        tHeader.flags = FIN;
        tHeader.window = SOCKET_BUFFER_SIZE - sock->lastRcvd;
        tHeader.length = 0;

        makePack(&pck, TOS_NODE_ID, sock->dest.addr, MAX_TTL, 
                PROTOCOL_TCP, 0, (uint8_t*)&tHeader, sizeof(transport));

        call IP.send(&pck);
        sock->state = FIN_WAIT_1;
        
        return SUCCESS;
    }

    command error_t Transport.receive(pack* package) {
        transport tResponse;
        pack pck;
        transport* tHeader = (transport*) package->payload;
        socket_t new_fd;

        // Find matching socket
        socket_store_t* sock = NULL;
        socket_t fd = -1;
        uint8_t i, j;

        dbg(TRANSPORT_CHANNEL, "Transport: Received packet with flags %d from %d:%d to %d:%d\n", 
            tHeader->flags, package->src, tHeader->srcPort, package->dest, tHeader->destPort);

        // First try to find an established socket
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].flag == 1 &&
                sockets[i].src == tHeader->destPort &&
                sockets[i].dest.port == tHeader->srcPort &&
                sockets[i].dest.addr == package->src) {
                    sock = &sockets[i];
                    fd = i;
                    break;
            }
        }

        // If no socket found and this is a SYN packet, look for listening socket
        if (sock == NULL && (tHeader->flags & SYN)) {
            for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
                if (sockets[i].flag == 1 &&
                    sockets[i].state == LISTEN &&
                    sockets[i].src == tHeader->destPort) {
                    
                    dbg(TRANSPORT_CHANNEL, "Listing socket states before Transport.socket: \n");
                    for (j = 0; j < MAX_NUM_OF_SOCKETS; j++) {
                        dbg(TRANSPORT_CHANNEL, "        Socket %d: state %d, flag %d\n", j, sockets[j].state, sockets[j].flag);
                    }
                    
                    // Create new socket for connection
                    new_fd = call Transport.socket();
                    
                    dbg(TRANSPORT_CHANNEL, "Listing socket states after Transport.socket: \n");
                    for (j = 0; j < MAX_NUM_OF_SOCKETS; j++) {
                        dbg(TRANSPORT_CHANNEL, "        Socket %d: state %d, flag %d\n", j, sockets[j].state, sockets[j].flag);
                    }

                    if (new_fd != (socket_t)-1) {
                        sockets[new_fd].src = sockets[i].src;
                        sockets[new_fd].dest.addr = package->src;
                        sockets[new_fd].dest.port = tHeader->srcPort;
                        sockets[new_fd].parentFd = i;
                        sock = &sockets[new_fd];
                        fd = new_fd;
                        dbg(TRANSPORT_CHANNEL, "Created new socket %d for incoming connection\n", new_fd);

                        dbg(TRANSPORT_CHANNEL, "Before, if tHeader=SYN, then socket %d: state-%d, flag-%d, src-%d\n", 
                            fd, sock->state, sock->flag, sock->src);
                        sock->state = SYN_RCVD;
                        dbg(TRANSPORT_CHANNEL, "After, if tHeader=SYN, then socket %d: state-%d, flag-%d, src-%d\n", 
                            fd, sock->state, sock->flag, sock->src);

                        // Send SYN-ACK
                        tResponse.srcPort = sock->src;
                        tResponse.destPort = sock->dest.port;
                        tResponse.seq = sock->lastSent;
                        tResponse.ack = tHeader->seq + 1;
                        tResponse.flags = SYN | ACK;
                        tResponse.window = SOCKET_BUFFER_SIZE;
                        tResponse.length = 0;

                        makePack(&pck, TOS_NODE_ID, sock->dest.addr, MAX_TTL, PROTOCOL_TCP, 0, 
                                (uint8_t*)&tResponse, sizeof(transport));

                        call IP.send(&pck);
                        dbg(TRANSPORT_CHANNEL, "Server sent SYN-ACK to %d:%d\n", 
                            sock->dest.addr, sock->dest.port);
                        break;
                    }
                }
            }
        }

        if (sock == NULL) return FAIL;

        // Handle ACK packets
        if (tHeader->flags & ACK) {
            if (sock->state == SYN_SENT) {
                dbg(TRANSPORT_CHANNEL, "Before, if tHeader=ACK && sockState=SYN_SENT, then socket %d: state-%d, flag-%d, src-%d\n", 
                    fd, sock->state, sock->flag, sock->src);
                sock->state = ESTABLISHED;
                signal Transport.clientConnected(fd);
                dbg(TRANSPORT_CHANNEL, "After, if tHeader=ACK && sockState=SYN_SENT, then socket %d: state-%d, flag-%d, src-%d\n", 
                    fd, sock->state, sock->flag, sock->src);
                
                dbg(TRANSPORT_CHANNEL, "Connection established with %d:%d\n", 
                    sock->dest.addr, sock->dest.port);
            }
            else if (sock->state == SYN_RCVD) {
                dbg(TRANSPORT_CHANNEL, "Before, if tHeader=ACK && sockState=SYN_RCVD, then socket %d: state-%d, flag-%d, src-%d\n", 
                    fd, sock->state, sock->flag, sock->src);
                sock->state = ESTABLISHED;
                dbg(TRANSPORT_CHANNEL, "After, if tHeader=ACK && sockState=SYN_RCVD, then socket %d: state-%d, flag-%d, src-%d\n", 
                    fd, sock->state, sock->flag, sock->src);
                
                dbg(TRANSPORT_CHANNEL, "Connection established with %d:%d\n", 
                    sock->dest.addr, sock->dest.port);
            }
            else if (sock->state == FIN_WAIT_1) {
                dbg(TRANSPORT_CHANNEL, "Before, if tHeader=ACK && sockState=FIN_WAIT_1, then socket %d: state-%d, flag-%d, src-%d\n", 
                    fd, sock->state, sock->flag, sock->src);
                sock->state = FIN_WAIT_2;
                dbg(TRANSPORT_CHANNEL, "After, if tHeader=ACK && sockState=FIN_WAIT_1, then socket %d: state-%d, flag-%d, src-%d\n", 
                    fd, sock->state, sock->flag, sock->src);
            }
        }
        // Handle FIN packets
        else if (tHeader->flags & FIN) {
            if (sock->state == ESTABLISHED) {
                dbg(TRANSPORT_CHANNEL, "Before, if tHeader=FIN, then socket %d: state-%d, flag-%d, src-%d\n", 
                    fd, sock->state, sock->flag, sock->src);
                sock->state = CLOSE_WAIT;
                dbg(TRANSPORT_CHANNEL, "Middle, if tHeader=FIN, then socket %d: state-%d, flag-%d, src-%d\n", 
                    fd, sock->state, sock->flag, sock->src);

                // Send ACK for FIN
                tResponse.srcPort = sock->src;
                tResponse.destPort = sock->dest.port;
                tResponse.seq = sock->lastSent;
                tResponse.ack = tHeader->seq + 1;
                tResponse.flags = ACK;
                tResponse.window = SOCKET_BUFFER_SIZE;
                tResponse.length = 0;

                makePack(&pck, TOS_NODE_ID, sock->dest.addr, MAX_TTL, PROTOCOL_TCP, 0, 
                        (uint8_t*)&tResponse, sizeof(transport));

                call IP.send(&pck);

                sock->state = CLOSED;
                dbg(TRANSPORT_CHANNEL, "After, if tHeader=FIN, then socket %d: state-%d, flag-%d, src-%d\n", 
                    fd, sock->state, sock->flag, sock->src);
            }
        }
        // Handle data packets
        else if (sock->state == ESTABLISHED) {
            uint16_t dataLen = tHeader->length;
            
            if (dataLen > 0) {
                dbg(TRANSPORT_CHANNEL, "Transport.receive: Received %d bytes on socket %d\n", dataLen, fd);
                
                // Check if this is the next expected sequence number
                if (tHeader->seq == sock->rcvWindowBase) {
                    // In-order segment, add to receive buffer
                    memcpy(sock->rcvdBuff + sock->lastRcvd, tHeader->payload, dataLen);
                    sock->lastRcvd += dataLen;
                    sock->rcvWindowBase += dataLen;
                    
                    // Process any buffered out-of-order segments that are now in order
                    while (sock->numOutOfOrder > 0) {
                        if (sock->outOfOrderSeqNums[0] == sock->rcvWindowBase) {
                            uint16_t len = strlen((char*)&sock->outOfOrderData[0]);
                            memcpy(sock->rcvdBuff + sock->lastRcvd, 
                                &sock->outOfOrderData[0], len);
                            sock->lastRcvd += len;
                            sock->rcvWindowBase += len;
                            
                            // Shift remaining out-of-order segments
                            for (i = 0; i < sock->numOutOfOrder - 1; i++) {
                                memcpy(&sock->outOfOrderData[i], 
                                    &sock->outOfOrderData[i+1],
                                    SOCKET_BUFFER_SIZE);
                                sock->outOfOrderSeqNums[i] = sock->outOfOrderSeqNums[i+1];
                            }
                            sock->numOutOfOrder--;
                        } else {
                            break;
                        }
                    }
                } 
                else if (tHeader->seq > sock->rcvWindowBase) {
                    // Out-of-order segment, store it if we have space
                    if (sock->numOutOfOrder < SOCKET_BUFFER_SIZE) {
                        memcpy(&sock->outOfOrderData[sock->numOutOfOrder], 
                            tHeader->payload, dataLen);
                        sock->outOfOrderSeqNums[sock->numOutOfOrder] = tHeader->seq;
                        sock->numOutOfOrder++;
                    }
                }
                
                // Send ACK
                tResponse.srcPort = sock->src;
                tResponse.destPort = sock->dest.port;
                tResponse.seq = sock->lastSent;
                tResponse.ack = sock->rcvWindowBase;  // ACK next expected byte
                tResponse.flags = ACK;
                tResponse.window = SOCKET_BUFFER_SIZE - sock->lastRcvd;  // Advertise available buffer
                tResponse.length = 0;
                
                makePack(&pck, TOS_NODE_ID, sock->dest.addr, MAX_TTL,
                        PROTOCOL_TCP, 0, (uint8_t*)&tResponse, sizeof(transport));
                
                call IP.send(&pck);
            }
        }

        return SUCCESS;
    }

    command error_t Transport.release(socket_t fd) {
        // Implement as needed
        return SUCCESS;
    }

    command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        uint16_t bytesAvailable;
        uint16_t bytesToRead;

        socket_store_t* sock = getSocket(fd);
        if (sock == NULL || sock->state != ESTABLISHED) return 0;

        bytesAvailable = sock->lastRcvd - sock->lastRead;
        bytesToRead = (bufflen < bytesAvailable) ? bufflen : bytesAvailable;

        memcpy(buff, sock->rcvdBuff + sock->lastRead, bytesToRead);
        sock->lastRead += bytesToRead;

        dbg(TRANSPORT_CHANNEL, "Transport.read: Socket %d, read %d bytes\n", fd, bytesToRead);

        return bytesToRead;
    }

    command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        transport tHeader;
        pack pck;
        uint16_t bytesToWrite;
        socket_store_t* sock = getSocket(fd);
        
        if (sock == NULL || sock->state != ESTABLISHED) return 0;
        
        // Check if we can send more data (window not full)
        if (sock->numUnAcked >= sock->sendWindowSize) {
            dbg(TRANSPORT_CHANNEL, "Transport.write: Window full, cannot send more data\n");
            return 0;
        }
        
        // Calculate how much we can send
        bytesToWrite = MIN(bufflen, sock->sendWindowSize - sock->numUnAcked);
        
        // Store data for potential retransmission
        memcpy(&sock->unAckedData[sock->numUnAcked], buff, bytesToWrite);
        sock->unAckedSeqNums[sock->numUnAcked] = sock->lastSent;
        sock->numUnAcked++;
        
        // Send data packet
        tHeader.srcPort = sock->src;
        tHeader.destPort = sock->dest.port;
        tHeader.seq = sock->lastSent;
        tHeader.ack = sock->lastAck;
        tHeader.flags = 0;
        tHeader.window = sock->rcvWindowSize;
        tHeader.length = bytesToWrite;
        memcpy(tHeader.payload, buff, bytesToWrite);
        
        makePack(&pck, TOS_NODE_ID, sock->dest.addr, MAX_TTL, PROTOCOL_TCP, 0, 
                (uint8_t*)&tHeader, sizeof(transport));
        
        call IP.send(&pck);
        sock->lastSent += bytesToWrite;
        
        dbg(TRANSPORT_CHANNEL, "Transport.write: Socket %d, writing %d bytes\n", fd, bytesToWrite);
        
        return bytesToWrite;
    }

    event void Timer.fired() {
        // Implement timer event handler
    }
}
