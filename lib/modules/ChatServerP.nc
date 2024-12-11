// #include "../../includes/socket.h"
// #include "../../includes/packet.h"
// #include "../../includes/channels.h"

// module ChatServerP {
//     provides interface ChatServer;
//     uses interface Transport;
//     uses interface SimpleSend as Sender;
//     uses interface Timer<TMilli> as ServerTimer;
//     uses interface Hashmap<socket_store_t*> as ConnectedClients;
// }

// implementation {
//     // Server state
//     socket_t server_socket;
//     bool isRunning = FALSE;
    
//     // Client info structure
//     typedef struct {
//         uint8_t username[16];
//         socket_t socket;
//         bool isActive;
//     } client_info_t;
    
//     client_info_t clients[MAX_NUM_OF_SOCKETS];
    
//     void broadcastMessage(uint8_t *message, uint16_t excludeClient) {
//         uint16_t i;
//         for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
//             if(clients[i].isActive && i != excludeClient) {
//                 call Transport.write(clients[i].socket, message, strlen((char *)message));
//             }
//         }
//     }

//     command error_t ChatServer.start() {
//         socket_addr_t addr;
//         uint16_t i;
        
//         if(isRunning) return SUCCESS;
        
//         // Initialize client array
//         for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
//             clients[i].isActive = FALSE;
//         }
        
//         // Create server socket
//         server_socket = call Transport.socket();
//         if(server_socket < 0) return FAIL;
        
//         // Bind to port 41
//         addr.addr = TOS_NODE_ID;
//         addr.port = 41;
        
//         if(call Transport.bind(server_socket, &addr) != SUCCESS) {
//             return FAIL;
//         }
        
//         // Start listening
//         if(call Transport.listen(server_socket) != SUCCESS) {
//             return FAIL;
//         }
        
//         isRunning = TRUE;
//         call ServerTimer.startPeriodic(1000); // Check for new connections every second
        
//         return SUCCESS;
//     }
    
//     command error_t ChatServer.stop() {
//         uint16_t i;
        
//         if(!isRunning) return SUCCESS;
        
//         // Close all client connections
//         for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
//             if(clients[i].isActive) {
//                 call Transport.close(clients[i].socket);
//                 clients[i].isActive = FALSE;
//             }
//         }
        
//         // Close server socket
//         call Transport.close(server_socket);
//         call ServerTimer.stop();
        
//         isRunning = FALSE;
//         return SUCCESS;
//     }

//     event void Transport.clientConnected(socket_t clientSocket) {
//         uint16_t i;

//         dbg(TRANSPORT_CHANNEL, "ChatServer: New client connected on socket %d\n", clientSocket);

//         // Add the client to the active clients list
//         for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
//             if (!clients[i].isActive) {
//                 clients[i].socket = clientSocket;
//                 clients[i].isActive = TRUE;
//                 signal ChatServer.clientConnected(i, NULL); // Send client ID and optional username.
//                 return;
//             }
//         }

//         dbg(TRANSPORT_CHANNEL, "ChatServer: No space for new clients.\n");
//     }


//     event void ServerTimer.fired() {
//         // Variable declarations at top
//         socket_t client_socket;
//         uint16_t i;
        
//         if(!isRunning) return;
        
//         client_socket = call Transport.accept(server_socket);
        
//         if(client_socket != -1) {
//             for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
//                 if(!clients[i].isActive) {
//                     clients[i].socket = client_socket;
//                     clients[i].isActive = TRUE;
//                     signal ChatServer.clientConnected(i, NULL);
//                     break;
//                 }
//             }
//         }
//     }
// }



#include "../../includes/socket.h"
#include "../../includes/packet.h"
#include "../../includes/channels.h"
#include "../../includes/transport.h"

module ChatServerP {
    provides interface ChatServer;
    uses interface Transport;
    uses interface SimpleSend as Sender;
    uses interface Timer<TMilli> as ServerTimer;
    uses interface Hashmap<socket_store_t*> as ConnectedClients;
    uses interface Routing;
    uses interface NDisc;
}

implementation {
    // Server state
    socket_t server_socket;
    bool isRunning = FALSE;
    
    // Client info structure
    typedef struct {
        uint8_t username[16];
        socket_t socket;
        bool isActive;
        uint16_t nodeId;  // Added to track physical node
    } client_info_t;
    
    client_info_t clients[MAX_NUM_OF_SOCKETS];
    
    void broadcastMessage(uint8_t *message, uint16_t excludeClient) {
        uint16_t i;
        uint8_t nextHop;
        
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if(clients[i].isActive && i != excludeClient) {
                // Use routing to find path to client
                nextHop = call Routing.getNextHop(clients[i].nodeId);
                if(nextHop != 0) {
                    call Transport.write(clients[i].socket, message, strlen((char *)message));
                }
            }
        }
    }

    command error_t ChatServer.start() {
        socket_addr_t addr;
        uint16_t i;
        
        if(isRunning) return SUCCESS;
        
        // Initialize networking
        call Routing.start();
        call NDisc.start();
        
        // Initialize client array
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            clients[i].isActive = FALSE;
        }
        
        // Create server socket
        server_socket = call Transport.socket();
        if(server_socket < 0) return FAIL;
        
        // Bind to port 41
        addr.addr = TOS_NODE_ID;
        addr.port = 41;
        
        if(call Transport.bind(server_socket, &addr) != SUCCESS) {
            return FAIL;
        }
        
        // Start listening
        if(call Transport.listen(server_socket) != SUCCESS) {
            return FAIL;
        }
        
        isRunning = TRUE;
        call ServerTimer.startPeriodic(1000);
        
        return SUCCESS;
    }
    
    command error_t ChatServer.stop() {
        uint16_t i;
        
        if(!isRunning) return SUCCESS;
        
        call NDisc.stop();
        
        // Close all client connections
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if(clients[i].isActive) {
                call Transport.close(clients[i].socket);
                clients[i].isActive = FALSE;
            }
        }
        
        // Close server socket
        call Transport.close(server_socket);
        call ServerTimer.stop();
        
        isRunning = FALSE;
        return SUCCESS;
    }

    event void Transport.clientConnected(socket_t clientSocket) {
        uint16_t i;

        dbg(TRANSPORT_CHANNEL, "ChatServer: New client connected on socket %d\n", clientSocket);

        // Add the client to the active clients list
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (!clients[i].isActive) {
                clients[i].socket = clientSocket;
                clients[i].isActive = TRUE;
                signal ChatServer.clientConnected(i, NULL);
                return;
            }
        }

        dbg(TRANSPORT_CHANNEL, "ChatServer: No space for new clients.\n");
    }

    event void ServerTimer.fired() {
        socket_t client_socket;
        uint16_t i, j;
        uint32_t* activeNodes;
        bool found;
        
        if(!isRunning) return;
        
        // Check for new connections
        client_socket = call Transport.accept(server_socket);
        
        if(client_socket != -1) {
            for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
                if(!clients[i].isActive) {
                    clients[i].socket = client_socket;
                    clients[i].isActive = TRUE;
                    signal ChatServer.clientConnected(i, NULL);
                    break;
                }
            }
        }

        // Check client connectivity using NDisc's getNeighbors
        activeNodes = call NDisc.getNeighbors();
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if(clients[i].isActive) {
                found = FALSE;
                
                // Check if client's node is still in neighbor list
                for(j = 0; j < call NDisc.getSize(); j++) {
                    if(activeNodes[j] == clients[i].nodeId) {
                        found = TRUE;
                        break;
                    }
                }
                
                if(!found) {
                    clients[i].isActive = FALSE;
                    signal ChatServer.clientDisconnected(i);
                }
            }
        }
    }
}
