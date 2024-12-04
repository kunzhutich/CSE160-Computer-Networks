#ifndef __SOCKET_H__
#define __SOCKET_H__

enum{
    MAX_NUM_OF_SOCKETS = 10,
    ROOT_SOCKET_ADDR = 255,
    ROOT_SOCKET_PORT = 255,
    SOCKET_BUFFER_SIZE = 128,
};

enum socket_state{
    CLOSED,
    LISTEN,
    SYN_SENT,
    SYN_RCVD,
    ESTABLISHED,
    FIN_WAIT_1,
    FIN_WAIT_2,
    CLOSE_WAIT,
    LAST_ACK,
};


typedef nx_uint8_t nx_socket_port_t;
typedef uint8_t socket_port_t;

// socket_addr_t is a simplified version of an IP connection.
typedef nx_struct socket_addr_t{
    nx_socket_port_t port;
    nx_uint16_t addr;
}socket_addr_t;


// File descripter id. Each id is associated with a socket_store_t
typedef uint8_t socket_t;

// State of a socket. 
typedef struct socket_store_t{
    uint8_t flag;
    enum socket_state state;
    socket_port_t src;
    socket_addr_t dest;

    // This is the sender portion.
    uint8_t sendBuff[SOCKET_BUFFER_SIZE];
    uint8_t lastWritten;
    uint8_t lastAck;
    uint8_t lastSent;

    // This is the receiver portion
    uint8_t rcvdBuff[SOCKET_BUFFER_SIZE];
    uint8_t lastRead;
    uint8_t lastRcvd;
    uint8_t nextExpected;

    uint16_t RTT;
    uint8_t effectiveWindow;

    socket_t parentFd;  // For accept()


    // Sender sliding window
    uint16_t sendWindowBase;    // First sequence number in window
    uint16_t sendWindowSize;    // Current window size
    uint8_t* unAckedData[SOCKET_BUFFER_SIZE];  // Buffer for unacknowledged data
    uint16_t unAckedSeqNums[SOCKET_BUFFER_SIZE]; // Sequence numbers of unacked data
    uint16_t numUnAcked;       // Number of unacknowledged packets
    
    // Receiver sliding window
    uint16_t rcvWindowBase;    // Expected next sequence number
    uint16_t rcvWindowSize;    // Remaining buffer space
    uint8_t* outOfOrderData[SOCKET_BUFFER_SIZE];  // Buffer for out-of-order segments
    uint16_t outOfOrderSeqNums[SOCKET_BUFFER_SIZE]; // Sequence numbers of out-of-order segments
    uint16_t numOutOfOrder;    // Number of out-of-order segments
}socket_store_t;

// typedef struct socket_store_t{
//     uint8_t flag;
//     enum socket_state state;
//     socket_port_t src;
//     socket_addr_t dest;

//     uint16_t seqNum;
//     uint16_t ackNum;

//     uint8_t sendBuff[SOCKET_BUFFER_SIZE];
//     uint16_t sendBuffLen;
//     uint16_t lastAck;

//     uint8_t rcvdBuff[SOCKET_BUFFER_SIZE];
//     uint16_t rcvdBuffLen;
//     uint16_t nextExpectedSeq;

//     socket_t parentFd;  // For accept()
// } socket_store_t;

#endif
