// #include "../../includes/socket.h"
// #include "../../includes/packet.h"
// #include "../../includes/channels.h"

// module ChatClientP {
//     provides interface ChatClient;
//     uses interface Transport;
//     uses interface SimpleSend as Sender;
//     uses interface Timer<TMilli> as ClientTimer;
// }

// implementation {
//     // Client state
//     socket_t client_socket;
//     uint8_t username[16];
//     uint8_t client_port;
//     bool isConnected = FALSE;
    
//     // Buffer for receiving messages
//     uint8_t receiveBuff[SOCKET_BUFFER_SIZE];
    
//     void formatMessage(uint8_t *buffer, const char *cmd, uint8_t *payload) {
//         sprintf((char *)buffer, "%s %s\r\n", cmd, payload);
//     }

//     command error_t ChatClient.connect(uint8_t *uname, uint8_t port) {
//         socket_addr_t addr;
//         socket_addr_t bindAddr;
//         uint8_t buffer[SOCKET_BUFFER_SIZE];
        
//         // Store username and port
//         memcpy(username, uname, strlen((char *)uname) + 1);
//         client_port = port;
        
//         // Create socket
//         client_socket = call Transport.socket();
        
//         if (client_socket < 0) {
//             dbg(TRANSPORT_CHANNEL, "Failed to create socket\n");
//             return FAIL;
//         }
        
//         // Set up connection to server (Node 1, Port 41)
//         addr.addr = 1;  // Server node
//         addr.port = 41; // Server port
        
//         // Bind to our port
//         bindAddr.addr = TOS_NODE_ID;
//         bindAddr.port = port;
        
//         if (call Transport.bind(client_socket, &bindAddr) != SUCCESS) {
//             dbg(TRANSPORT_CHANNEL, "Failed to bind socket\n");
//             return FAIL;
//         }
        
//         // Connect to server
//         if (call Transport.connect(client_socket, &addr) != SUCCESS) {
//             dbg(TRANSPORT_CHANNEL, "Failed to connect\n");
//             return FAIL;
//         }
        
//         // Send hello message
//         formatMessage(buffer, "hello", username);
//         call Transport.write(client_socket, buffer, strlen((char *)buffer));
        
//         return SUCCESS;
//     }
    
//     command error_t ChatClient.sendMessage(uint8_t *message) {
//         uint8_t buffer[SOCKET_BUFFER_SIZE];

//         if (!isConnected) return FAIL;
        
//         formatMessage(buffer, "msg", message);
//         return call Transport.write(client_socket, buffer, strlen((char *)buffer));
//     }
    
//     command error_t ChatClient.whisper(uint8_t *target, uint8_t *message) {
//         uint8_t buffer[SOCKET_BUFFER_SIZE];
//         uint8_t whisperCmd[SOCKET_BUFFER_SIZE];

//         if (!isConnected) return FAIL;
        
//         sprintf((char *)whisperCmd, "whisper %s", target);
//         formatMessage(buffer, whisperCmd, message);
//         return call Transport.write(client_socket, buffer, strlen((char *)buffer));
//     }
    
//     command error_t ChatClient.listUsers() {
//         uint8_t buffer[SOCKET_BUFFER_SIZE];

//         if (!isConnected) return FAIL;
        
//         sprintf((char *)buffer, "listusr\r\n");
//         return call Transport.write(client_socket, buffer, strlen((char *)buffer));
//     }
    
//     command error_t ChatClient.disconnect() {
//         if (!isConnected) return SUCCESS;
        
//         isConnected = FALSE;
//         return call Transport.close(client_socket);
//     }

//     event void Transport.clientConnected(socket_t clientSocket) {
//         dbg(TRANSPORT_CHANNEL, "ChatClient: Connected to server on socket %d\n", clientSocket);
//         isConnected = TRUE;
//         signal ChatClient.connectionComplete();
//     }


//     event void ClientTimer.fired() {
//         // Handle periodic client tasks if needed
//         if (!isConnected) {
//             // Retry connection logic could go here
//         }
//     }
// }





#include "../../includes/socket.h"
#include "../../includes/packet.h"
#include "../../includes/channels.h"
#include "../../includes/transport.h"

module ChatClientP {
    provides interface ChatClient;
    uses interface Transport;
    uses interface SimpleSend as Sender;
    uses interface Timer<TMilli> as ClientTimer;
    uses interface Routing;     // For routing to server
    uses interface NDisc;       // For network discovery
}

implementation {
    // Client state
    socket_t client_socket;
    uint8_t username[16];
    uint8_t client_port;
    bool isConnected = FALSE;
    
    // Buffer for receiving messages
    uint8_t receiveBuff[SOCKET_BUFFER_SIZE];
    
    void formatMessage(uint8_t *buffer, const char *cmd, uint8_t *payload) {
        sprintf((char *)buffer, "%s %s\r\n", cmd, payload);
    }

    command error_t ChatClient.connect(uint8_t *uname, uint8_t port) {
        socket_addr_t addr;
        socket_addr_t bindAddr;
        uint8_t buffer[SOCKET_BUFFER_SIZE];
        uint8_t nextHop;
        
        // Store username and port
        memcpy(username, uname, strlen((char *)uname) + 1);
        client_port = port;

        // Check if we have a route to the server (node 1)
        nextHop = call Routing.getNextHop(1);
        if(nextHop == 0) {
            dbg(GENERAL_CHANNEL, "No route to server found\n");
            return FAIL;
        }
        
        // Create socket
        client_socket = call Transport.socket();
        
        if (client_socket < 0) {
            dbg(TRANSPORT_CHANNEL, "Failed to create socket\n");
            return FAIL;
        }
        
        // Set up connection to server (Node 1, Port 41)
        addr.addr = 1;  // Server node
        addr.port = 41; // Server port
        
        // Bind to our port
        bindAddr.addr = TOS_NODE_ID;
        bindAddr.port = port;
        
        if (call Transport.bind(client_socket, &bindAddr) != SUCCESS) {
            dbg(TRANSPORT_CHANNEL, "Failed to bind socket\n");
            return FAIL;
        }
        
        // Connect to server
        if (call Transport.connect(client_socket, &addr) != SUCCESS) {
            dbg(TRANSPORT_CHANNEL, "Failed to connect\n");
            return FAIL;
        }
        
        // Send hello message
        formatMessage(buffer, "hello", username);
        call Transport.write(client_socket, buffer, strlen((char *)buffer));
        
        // Start network discovery for better routing
        call NDisc.start();
        
        return SUCCESS;
    }
    
    command error_t ChatClient.sendMessage(uint8_t *message) {
        uint8_t buffer[SOCKET_BUFFER_SIZE];

        if (!isConnected) return FAIL;
        
        formatMessage(buffer, "msg", message);
        return call Transport.write(client_socket, buffer, strlen((char *)buffer));
    }
    
    command error_t ChatClient.whisper(uint8_t *target, uint8_t *message) {
        uint8_t buffer[SOCKET_BUFFER_SIZE];
        uint8_t whisperCmd[SOCKET_BUFFER_SIZE];

        if (!isConnected) return FAIL;
        
        sprintf((char *)whisperCmd, "whisper %s", target);
        formatMessage(buffer, whisperCmd, message);
        return call Transport.write(client_socket, buffer, strlen((char *)buffer));
    }
    
    command error_t ChatClient.listUsers() {
        uint8_t buffer[SOCKET_BUFFER_SIZE];

        if (!isConnected) return FAIL;
        
        sprintf((char *)buffer, "listusr\r\n");
        return call Transport.write(client_socket, buffer, strlen((char *)buffer));
    }
    
    command error_t ChatClient.disconnect() {
        if (!isConnected) return SUCCESS;
        
        isConnected = FALSE;
        call NDisc.stop();
        return call Transport.close(client_socket);
    }

    event void Transport.clientConnected(socket_t clientSocket) {
        dbg(TRANSPORT_CHANNEL, "ChatClient: Connected to server on socket %d\n", clientSocket);
        isConnected = TRUE;
        signal ChatClient.connectionComplete();
    }
    
    event void ClientTimer.fired() {
        uint8_t nextHop;
        
        if (!isConnected) {
            // Check if we have a route to server
            nextHop = call Routing.getNextHop(1);
            if (nextHop != 0) {
                // We could attempt to reconnect here
                dbg(GENERAL_CHANNEL, "Route to server available\n");
            }
        }
    }
}