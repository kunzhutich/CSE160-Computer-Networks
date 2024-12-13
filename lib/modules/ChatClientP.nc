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
    bool isRunning = FALSE;  
    
    // Buffer for receiving messages
    uint8_t receiveBuff[SOCKET_BUFFER_SIZE];
    
    void formatMessage(uint8_t *buffer, const char *cmd, uint8_t *payload) {
        sprintf((char *)buffer, "%s %s\r\n", cmd, payload);
    }

    // command error_t ChatClient.start(uint16_t node, uint8_t port) {
    //     socket_addr_t addr;
        
    //     if(isRunning) {
    //         dbg(CHAT_CHANNEL, "Chat client already running on node %d\n", node);
    //         return SUCCESS;
    //     }
        
    //     dbg(CHAT_CHANNEL, "Starting chat client on node %d with port %d...\n", node, port);

    //     // Initialize state
    //     isRunning = FALSE;
    //     isConnected = FALSE;
    //     memset(username, 0, sizeof(username));
    //     client_socket = -1;
        
    //     // Initialize networking
    //     call Routing.start();
    //     call NDisc.start();
        
    //     // Create client socket
    //     client_socket = call Transport.socket();
    //     if(client_socket < 0) {
    //         dbg(CHAT_CHANNEL, "Failed to create client socket\n");
    //         return FAIL;
    //     }
    //     dbg(CHAT_CHANNEL, "Created client socket: %d\n", client_socket);
        
    //     // Store the port for later use
    //     client_port = port;
        
    //     // Bind to our port
    //     addr.addr = node;
    //     addr.port = port;
        
    //     if(call Transport.bind(client_socket, &addr) != SUCCESS) {
    //         dbg(CHAT_CHANNEL, "Failed to bind client socket\n");
    //         return FAIL;
    //     }
    //     dbg(CHAT_CHANNEL, "Bound client socket to port %d\n", port);
        
    //     isRunning = TRUE;
    //     call ClientTimer.startPeriodic(1000);
        
    //     dbg(CHAT_CHANNEL, "Chat client successfully started on node %d\n", node);
    //     return SUCCESS;
    // }
    
    command error_t ChatClient.start(uint16_t node, uint8_t port) {
        socket_addr_t addr;
        
        if(isRunning) {
            dbg(CHAT_CHANNEL, "Chat client already running on node %d\n", node);
            return SUCCESS;
        }
        
        // Initialize state
        isRunning = FALSE;
        isConnected = FALSE;
        memset(username, 0, sizeof(username));
        
        // Start networking components
        call Routing.start();
        call NDisc.start();
        
        // Create socket
        client_socket = call Transport.socket();
        if(client_socket < 0) {
            dbg(CHAT_CHANNEL, "Failed to create client socket\n");
            return FAIL;
        }
        dbg(CHAT_CHANNEL, "Created client socket: %d\n", client_socket);
        
        // Store port and bind socket
        client_port = port;
        addr.addr = node;
        addr.port = port;
        
        if(call Transport.bind(client_socket, &addr) != SUCCESS) {
            dbg(CHAT_CHANNEL, "Failed to bind client socket\n");
            return FAIL;
        }
        dbg(CHAT_CHANNEL, "Bound client socket to port %d\n", port);
        
        isRunning = TRUE;
        call ClientTimer.startPeriodic(1000);
        
        dbg(CHAT_CHANNEL, "Chat client successfully started on node %d\n", node);
        return SUCCESS;
    }

//     command error_t ChatClient.connect(uint8_t *uname, uint8_t port) {
//         socket_addr_t addr;
//         socket_addr_t bindAddr;
//         uint8_t buffer[SOCKET_BUFFER_SIZE];
//         uint8_t nextHop;
//         uint16_t written;

//         if (isConnected) {
//             dbg(CHAT_CHANNEL, "Client already connected\n");
//             return FAIL;
//         }
        
//         // dbg(CHAT_CHANNEL, "Attempting to connect to server as user '%s' on port %d\n", uname, port);
//         dbg(CHAT_CHANNEL, "Node %d attempting to connect as user '%s' on port %d\n", 
//             TOS_NODE_ID, uname, port);


//         // Store username and port
//         memcpy(username, uname, strlen((char *)uname) + 1);
//         client_port = port;

//         // Check if we have a route to the server (node 1)
//         nextHop = call Routing.getNextHop(1);
//         if(nextHop == 0) {
//             dbg(CHAT_CHANNEL, "No route to server found\n");
//             return FAIL;
//         }
        
//         dbg(CHAT_CHANNEL, "Found route to server via node %d\n", nextHop);


//         // Create socket
//         client_socket = call Transport.socket();
        
//         if (client_socket < 0) {
//             dbg(CHAT_CHANNEL, "Node %d: Failed to create client socket\n", TOS_NODE_ID);
//             return FAIL;
//         }
//         dbg(CHAT_CHANNEL, "Created client socket: %d\n", client_socket);
        
//         // Set up connection to server (Node 1, Port 41)
//         addr.addr = 1;  // Server node
//         addr.port = 41; // Server port
        
//         // Bind to our port
//         bindAddr.addr = TOS_NODE_ID;
//         bindAddr.port = port;
        
//         if (call Transport.bind(client_socket, &bindAddr) != SUCCESS) {
//             // dbg(CHAT_CHANNEL, "Failed to bind client socket to port %d\n", port);
//             dbg(CHAT_CHANNEL, "Node %d: Failed to bind to port %d\n", TOS_NODE_ID, port);
//             return FAIL;
//         }
//         dbg(CHAT_CHANNEL, "Bound client socket to port %d\n", port);
        
//         if (call Transport.connect(client_socket, &addr) != SUCCESS) {
//             // dbg(CHAT_CHANNEL, "Failed to connect to server\n");
//             dbg(CHAT_CHANNEL, "Node %d: Failed to connect to server\n", TOS_NODE_ID);
//             return FAIL;
//         }


//         // Connection is now established, wait for clientConnected event
//         dbg(CHAT_CHANNEL, "Connected to server, waiting for establishment\n");
//         return SUCCESS;
        
//         // // Send hello message
//         // formatMessage(buffer, "hello", username);
//         // call Transport.write(client_socket, buffer, strlen((char *)buffer));



// //
//         // // Format and send hello message
//         // sprintf((char*)buffer, "hello %s %d\r\n", username, port);
//         // if (call Transport.write(client_socket, buffer, strlen((char*)buffer)) == 0) {
//         //     dbg(CHAT_CHANNEL, "Node %d: Failed to send hello message\n", TOS_NODE_ID);
//         //     return FAIL;
//         // }
        
//         // // dbg(CHAT_CHANNEL, "Sent hello message to server\n");

//         // // Start network discovery for better routing
//         // // call NDisc.start();
        
//         // dbg(CHAT_CHANNEL, "Node %d: Successfully initialized connection\n", TOS_NODE_ID);
//         // return SUCCESS;



//         // // Format and send hello message
//         // memset(buffer, 0, SOCKET_BUFFER_SIZE);
//         // sprintf((char*)buffer, "hello %s %d\r\n", username, port);
//         // written = call Transport.write(client_socket, buffer, strlen((char*)buffer));
        
//         // if (written == 0) {
//         //     dbg(CHAT_CHANNEL, "Node %d: Failed to send hello message\n", TOS_NODE_ID);
//         //     return FAIL;
//         // }
        
//         // dbg(CHAT_CHANNEL, "Node %d: Successfully sent hello message (%d bytes)\n", 
//         //     TOS_NODE_ID, written);
//         // return SUCCESS;
//     }

    // command error_t ChatClient.connect(uint8_t *uname) {  // Remove port parameter
    //     socket_addr_t addr;
    //     uint8_t nextHop;
    //     uint16_t written;

    //     if (isConnected) {
    //         dbg(CHAT_CHANNEL, "Client already connected\n");
    //         return FAIL;
    //     }

    //     if (!isRunning) {
    //         dbg(CHAT_CHANNEL, "Client not started\n");
    //         return FAIL;
    //     }
        
    //     dbg(CHAT_CHANNEL, "Node %d attempting to connect as user '%s' on port %d\n", 
    //         TOS_NODE_ID, uname, client_port);  // Use stored port

    //     // Store username
    //     memcpy(username, uname, strlen((char *)uname) + 1);

    //     // Check if we have a route to the server (node 1)
    //     nextHop = call Routing.getNextHop(1);
    //     if(nextHop == 0) {
    //         dbg(CHAT_CHANNEL, "No route to server found\n");
    //         return FAIL;
    //     }
        
    //     dbg(CHAT_CHANNEL, "Found route to server via node %d\n", nextHop);

    //     // Set up connection to server (Node 1, Port 41)
    //     addr.addr = 1;  // Server node
    //     addr.port = 41; // Server port
        
    //     if (call Transport.connect(client_socket, &addr) != SUCCESS) {
    //         dbg(CHAT_CHANNEL, "Node %d: Failed to connect to server\n", TOS_NODE_ID);
    //         return FAIL;
    //     }

    //     // Connection is now established, wait for clientConnected event
    //     dbg(CHAT_CHANNEL, "Connected to server, waiting for establishment\n");
    //     return SUCCESS;
    // }
    
    command error_t ChatClient.connect(uint8_t *uname) {
        socket_addr_t addr;
        uint8_t nextHop;

        if (!isRunning) {
            dbg(CHAT_CHANNEL, "Client not started\n");
            return FAIL;
        }

        if (isConnected) {
            dbg(CHAT_CHANNEL, "Already connected\n");
            return FAIL;
        }

        // Store username
        memcpy(username, uname, strlen((char *)uname) + 1);

        dbg(CHAT_CHANNEL, "Node %d attempting to connect as user '%s' on port %d\n", 
            TOS_NODE_ID, uname, client_port);

        // Check route to server
        nextHop = call Routing.getNextHop(1);
        if(nextHop == 0) {
            dbg(CHAT_CHANNEL, "No route to server, will retry later\n");
            return SUCCESS;  // Return SUCCESS so we can retry
        }

        // Connect to server
        addr.addr = 1;  // Server node
        addr.port = 41; // Server port
        
        if (call Transport.connect(client_socket, &addr) != SUCCESS) {
            dbg(CHAT_CHANNEL, "Failed to connect to server\n");
            return FAIL;
        }

        dbg(CHAT_CHANNEL, "Connection initiated, waiting for establishment\n");
        return SUCCESS;
    }
    // command error_t ChatClient.sendMessage(uint8_t *message) {
    //     uint8_t buffer[SOCKET_BUFFER_SIZE];

    //     if (!isConnected) return FAIL;
        
    //     formatMessage(buffer, "msg", message);
    //     return call Transport.write(client_socket, buffer, strlen((char *)buffer));
    // }

    command error_t ChatClient.sendMessage(uint8_t *message) {
        uint8_t buffer[SOCKET_BUFFER_SIZE];
        uint16_t written;

        if (!isConnected) return FAIL;

        memset(buffer, 0, SOCKET_BUFFER_SIZE);
        snprintf((char*)buffer, SOCKET_BUFFER_SIZE, "msg %s\r\n", message);

        written = call Transport.write(client_socket, buffer, strlen((char*)buffer));
        if (written == 0) {
            dbg(CHAT_CHANNEL, "Node %d: Failed to send message\n", TOS_NODE_ID);
            return FAIL;
        }

        dbg(CHAT_CHANNEL, "Node %d: Sent message (%d bytes): %s\n", TOS_NODE_ID, written, buffer);
        return SUCCESS;
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
        if (!isRunning) return SUCCESS;
        
        isConnected = FALSE;
        isRunning = FALSE;
        call NDisc.stop();
        call ClientTimer.stop();  // Add this
        return call Transport.close(client_socket);
    }

    event void Transport.clientConnected(socket_t clientSocket) {
        uint8_t buffer[SOCKET_BUFFER_SIZE];
        uint16_t written;
        
        dbg(TRANSPORT_CHANNEL, "ChatClient: Connected to server on socket %d\n", clientSocket);
        isConnected = TRUE;

        // Now send the hello message
        memset(buffer, 0, SOCKET_BUFFER_SIZE);
        sprintf((char*)buffer, "hello %s %d\r\n", username, client_port);
        
        written = call Transport.write(client_socket, buffer, strlen((char*)buffer));
        if (written == 0) {
            dbg(CHAT_CHANNEL, "Node %d: Failed to send hello message after connection\n", TOS_NODE_ID);
        } else {
            dbg(CHAT_CHANNEL, "Node %d: Successfully sent hello message (%d bytes)\n", TOS_NODE_ID, written);
        }
        
        signal ChatClient.connectionComplete();
    }
    
    event void ClientTimer.fired() {
        uint8_t nextHop;
        socket_addr_t addr;
        
        if (!isConnected && username[0] != '\0') {  // If we have a username but not connected
            nextHop = call Routing.getNextHop(1);
            if (nextHop != 0) {
                addr.addr = 1;  // Server node
                addr.port = 41; // Server port
                
                // Try to connect
                if (call Transport.connect(client_socket, &addr) == SUCCESS) {
                    dbg(TRANSPORT_CHANNEL, "Node %d: Retrying connection to server\n", TOS_NODE_ID);
                }
            }
        } else if (isConnected) {
            // Maybe add heartbeat/keepalive functionality here
            // Or check if we're still connected to server
            dbg(TRANSPORT_CHANNEL, "Node %d: Connected and running (socket: %d)\n", 
                TOS_NODE_ID, client_socket);
        }
    }
}