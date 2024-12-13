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
    uint16_t numClients = 0;
    
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

    command error_t ChatServer.start(uint16_t node) {
        socket_addr_t addr;
        uint16_t i;
        
        if(isRunning) {
            dbg(CHAT_CHANNEL, "Chat server already running on node %d\n", node);
            return SUCCESS;
        }
        
        dbg(CHAT_CHANNEL, "Starting chat server on node %d...\n", node);

        // Initialize networking
        call Routing.start();
        call NDisc.start();
        
        // Initialize client array
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            clients[i].isActive = FALSE;
            memset(clients[i].username, 0, 16);
        }
        
        // Create server socket
        server_socket = call Transport.socket();
        if(server_socket < 0) {
            dbg(CHAT_CHANNEL, "Failed to create server socket\n");
            return FAIL;
        }
        dbg(CHAT_CHANNEL, "Created server socket: %d\n", server_socket);
        
        // Bind to port 41
        addr.addr = node;
        addr.port = 41;
        
        if(call Transport.bind(server_socket, &addr) != SUCCESS) {
            dbg(CHAT_CHANNEL, "Failed to bind server socket\n");
            return FAIL;
        }
        dbg(CHAT_CHANNEL, "Bound server socket to port 41\n");
        
        // Start listening
        if(call Transport.listen(server_socket) != SUCCESS) {
            dbg(CHAT_CHANNEL, "Failed to listen on server socket\n");
            return FAIL;
        }
        dbg(CHAT_CHANNEL, "Server listening on port 41\n");
        
        isRunning = TRUE;
        call ServerTimer.startPeriodic(1000);
        
        dbg(CHAT_CHANNEL, "Chat server successfully started on node %d\n", node);
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

    void processMessage(uint16_t clientId, uint8_t *message) {
        uint16_t i;
        uint8_t buffer[SOCKET_BUFFER_SIZE];
        char *cmd, *target, *content;

        cmd = strtok((char*)message, " ");
        if(cmd == NULL) return;

        if(strcmp(cmd, "hello") == 0) {
            content = strtok(NULL, "\r\n");
            if(content != NULL) {
                strncpy((char*)clients[clientId].username, content, 15);
                clients[clientId].username[15] = '\0';
                dbg(CHAT_CHANNEL, "Server: Client %d registered as '%s'\n", 
                    clientId, clients[clientId].username);
                signal ChatServer.clientConnected(clientId, clients[clientId].username);
            }
        }
        else if(strcmp(cmd, "msg") == 0) {
            content = strtok(NULL, "\r\n");
            if(content != NULL) {
                signal ChatServer.messageReceived(clientId, (uint8_t*)content);
                sprintf((char*)buffer, "%s: %s\r\n", clients[clientId].username, content);
                
                // Broadcast to all other connected clients
                for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
                    if(clients[i].isActive && i != clientId) {
                        call Transport.write(clients[i].socket, buffer, strlen((char*)buffer));
                    }
                }
            }
        }
        else if(strcmp(cmd, "whisper") == 0) {
            target = strtok(NULL, " ");
            content = strtok(NULL, "\r\n");
            
            if(target != NULL && content != NULL) {
                // Find target client by username
                for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
                    if(clients[i].isActive && strcmp((char*)clients[i].username, target) == 0) {
                        sprintf((char*)buffer, "[whisper from %s]: %s\r\n", 
                            clients[clientId].username, content);
                        call Transport.write(clients[i].socket, buffer, strlen((char*)buffer));
                        break;
                    }
                }
            }
        }
        else if(strcmp(cmd, "listusr") == 0) {
            uint16_t pos = 0;
            bool first = TRUE;
            
            // Build list of users
            memset(buffer, 0, SOCKET_BUFFER_SIZE);
            pos += sprintf((char*)buffer, "listUsrRply ");
            
            for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
                if(clients[i].isActive && clients[i].username[0] != '\0') {
                    if(!first) {
                        pos += sprintf((char*)buffer + pos, ", ");
                    }
                    pos += sprintf((char*)buffer + pos, "%s", clients[i].username);
                    first = FALSE;
                }
            }
            
            sprintf((char*)buffer + pos, "\r\n");
            call Transport.write(clients[clientId].socket, buffer, strlen((char*)buffer));
        }
    }

    // void handleReceivedData(uint16_t clientId, uint8_t *data, uint16_t len) {
    //     uint8_t buffer[SOCKET_BUFFER_SIZE];
    //     uint16_t i;
    //     char *cmd, *content;

    //     // Ensure null termination
    //     data[len] = '\0';
        
    //     dbg(CHAT_CHANNEL, "Server: Received data from client %d: %s\n", clientId, data);
        
    //     cmd = strtok((char*)data, " ");
    //     if(cmd == NULL) return;

    //     if(strcmp(cmd, "hello") == 0) {
    //         // Handle hello message
    //         content = strtok(NULL, "\r\n");
    //         if(content != NULL) {
    //             strncpy((char*)clients[clientId].username, content, 15);
    //             clients[clientId].username[15] = '\0';
    //             dbg(CHAT_CHANNEL, "Server: Client %d registered as '%s'\n", 
    //                 clientId, clients[clientId].username);
    //             signal ChatServer.clientConnected(clientId, clients[clientId].username);
    //         }
    //     }
    //     else if(strcmp(cmd, "msg") == 0) {
    //         // Handle broadcast message
    //         content = strtok(NULL, "\r\n");
    //         if(content != NULL) {
    //             sprintf((char*)buffer, "%s: %s\r\n", clients[clientId].username, content);
    //             dbg(CHAT_CHANNEL, "Server: Broadcasting message from %s: %s", 
    //                 clients[clientId].username, content);
                
    //             // Broadcast to all other clients
    //             for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
    //                 if(clients[i].isActive && i != clientId) {
    //                     call Transport.write(clients[i].socket, buffer, strlen((char*)buffer));
    //                 }
    //             }
    //         }
    //     }
    // }

    // event void ServerTimer.fired() {
    //     socket_t client_socket;
    //     uint16_t i;
    //     uint8_t buffer[SOCKET_BUFFER_SIZE];
    //     uint16_t bytesRead;
        
    //     if(!isRunning) return;
        
    //     // Accept new connections
    //     client_socket = call Transport.accept(server_socket);
    //     if(client_socket != -1 && client_socket != 255) {
    //         bool slotFound = FALSE;
            
    //         dbg(CHAT_CHANNEL, "Server: New connection accepted on socket %d\n", client_socket);
            
    //         // Find empty slot
    //         for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
    //             if(!clients[i].isActive) {
    //                 clients[i].socket = client_socket;
    //                 clients[i].isActive = TRUE;
    //                 memset(clients[i].username, 0, 16);
    //                 slotFound = TRUE;
    //                 dbg(CHAT_CHANNEL, "Server: Added client to slot %d\n", i);
    //                 break;
    //             }
    //         }
            
    //         if(!slotFound) {
    //             dbg(CHAT_CHANNEL, "Server: No slots available for new client\n");
    //             call Transport.close(client_socket);
    //         }
    //     }

    //     // Check for data from existing clients
    //     for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
    //         if(clients[i].isActive) {
    //             bytesRead = call Transport.read(clients[i].socket, buffer, SOCKET_BUFFER_SIZE);
    //             if(bytesRead > 0) {
    //                 handleReceivedData(i, buffer, bytesRead);
    //             }
    //         }
    //     }
    // }
    
    event void ServerTimer.fired() {
        socket_t client_socket;
        uint16_t i;
        
        if(!isRunning) return;
        
        // Accept new connections
        client_socket = call Transport.accept(server_socket);
        if(client_socket != -1) {
            bool slotFound = FALSE;
            
            // Only accept connections on valid socket numbers
            if(client_socket != 255) {  // 255 is invalid
                dbg(CHAT_CHANNEL, "Server: New connection accepted on socket %d\n", client_socket);
                
                // Find an empty slot
                for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
                    if(!clients[i].isActive) {
                        clients[i].socket = client_socket;
                        clients[i].isActive = TRUE;
                        memset(clients[i].username, 0, 16);
                        numClients++;
                        slotFound = TRUE;
                        dbg(CHAT_CHANNEL, "Server: Added client to slot %d\n", i);
                        break;
                    }
                }
                
                if(!slotFound) {
                    dbg(CHAT_CHANNEL, "Server: No slots available for new client\n");
                    call Transport.close(client_socket);
                }
            }
        }
        
        // Clean up disconnected clients
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if(clients[i].isActive) {
                // Check if client is still connected
                // You might want to add more sophisticated connection checking here
                if(clients[i].socket == 255) {  // Invalid socket
                    clients[i].isActive = FALSE;
                    numClients--;
                    dbg(CHAT_CHANNEL, "Server: Client %d disconnected\n", i);
                    signal ChatServer.clientDisconnected(i);
                }
            }
        }
    }
}
