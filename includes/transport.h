#ifndef TRANSPORT_H
#define TRANSPORT_H

#define TRANSPORT_MAX_PAYLOAD_SIZE 20  // Adjust based on packet size constraints
#define MIN(a,b) ((a) < (b) ? (a) : (b))

enum {
    SYN = 0x01,
    ACK = 0x02,
    FIN = 0x04
};

typedef nx_struct transport {
    nx_uint8_t srcPort;
    nx_uint8_t destPort;
    nx_uint16_t seq;
    nx_uint16_t ack;
    nx_uint8_t flags;
    nx_uint16_t window;
    nx_uint8_t length; // Length of payload data
    nx_uint8_t payload[TRANSPORT_MAX_PAYLOAD_SIZE];
} transport;

#endif /* TRANSPORT_H */
