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
                clients[i].nodeId = TOS_NODE_ID;

                signal ChatServer.clientConnected(i, NULL);
                return;
            }
        }

        dbg(TRANSPORT_CHANNEL, "ChatServer: No space for new clients.\n");
    }

    void processMessage(uint16_t clientId, uint8_t *message, uint16_t len) {
        char buffer[SOCKET_BUFFER_SIZE];
        uint8_t cmd[16], content[SOCKET_BUFFER_SIZE];
        uint16_t i;
        bool found;
        uint8_t nextHop;
        
        message[len] = '\0';  // Ensure null-termination
        dbg(CHAT_CHANNEL, "Server: Processing message from client %d (socket %d): '%s'\n", 
            clientId, clients[clientId].socket, message);

        if (sscanf((char*)message, "%15s %[^\r\n]", cmd, content) < 1) {
            dbg(CHAT_CHANNEL, "Server: Malformed message from client %d\n", clientId);
            return;
        }

        if (strcmp((char*)cmd, "hello") == 0) {
            strncpy((char*)clients[clientId].username, content, 15);
            clients[clientId].username[15] = '\0';
            dbg(CHAT_CHANNEL, "Server: Client %d registered as '%s'\n", clientId, clients[clientId].username);
            signal ChatServer.clientConnected(clientId, clients[clientId].username);

            // Send welcome message back to the client
            snprintf(buffer, sizeof(buffer), "Welcome %s!\r\n", clients[clientId].username);
            call Transport.write(clients[clientId].socket, (uint8_t*)buffer, strlen(buffer));

            dbg(CHAT_CHANNEL, "Server: Active users after registration:");
            for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
                if (clients[i].isActive) {
                    dbg(CHAT_CHANNEL, "  Client %d: %s (socket %d)\n", 
                        i, clients[i].username, clients[i].socket);
                }
            }
        } 
        else if (strcmp((char*)cmd, "msg") == 0) {
            dbg(CHAT_CHANNEL, "Server: Processing broadcast from %s on socket %d\n", 
                clients[clientId].username, clients[clientId].socket);

            if (clients[clientId].username[0] == '\0') {
                snprintf(buffer, sizeof(buffer), "Error: Please register with 'hello' first\r\n");
                call Transport.write(clients[clientId].socket, (uint8_t*)buffer, strlen(buffer));
                return;
            }

            snprintf(buffer, sizeof(buffer), "%s: %s\r\n", clients[clientId].username, content);
            dbg(CHAT_CHANNEL, "Server: Broadcasting message: %s", buffer);

            // Broadcast the message to all other clients
            for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
                if (clients[i].isActive && i != clientId) {
                    snprintf(buffer, sizeof(buffer), "%s: %s\r\n", clients[clientId].username, content);
                    nextHop = call Routing.getNextHop(clients[i].nodeId);
                    if (nextHop != 0) {
                        call Transport.write(clients[i].socket, (uint8_t*)buffer, strlen(buffer));
                        dbg(CHAT_CHANNEL, "Server: Sent message to client %d (node %d): %s\n", 
                            i, clients[i].nodeId, buffer);
                    }
                }
            }
        } 
        else if (strcmp((char*)cmd, "whisper") == 0) {
            char target[16];
            char message_content[SOCKET_BUFFER_SIZE];  // New buffer for message
            
            if (sscanf((char*)content, "%15s %[^\r\n]", target, message_content) == 2) {
                found = FALSE;
                for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
                    if (clients[i].isActive && strcmp((char*)clients[i].username, target) == 0) {
                        snprintf(buffer, sizeof(buffer), "[whisper from %s]: %s\r\n", 
                                clients[clientId].username, message_content);

                        call Transport.write(clients[i].socket, (uint8_t*)buffer, strlen(buffer));
                        dbg(CHAT_CHANNEL, "Server: Whisper sent to '%s': %s\n", target, buffer);
                        found = TRUE;
                        break;
                    }
                }

                if (!found) {
                    snprintf(buffer, sizeof(buffer), "Error: User '%s' not found\r\n", target);
                    call Transport.write(clients[clientId].socket, (uint8_t*)buffer, strlen(buffer));
                }
            } else {
                snprintf(buffer, sizeof(buffer), "Error: Invalid whisper format\r\n");
                call Transport.write(clients[clientId].socket, (uint8_t*)buffer, strlen(buffer));
            }
        }
        else if (strcmp((char*)cmd, "listusr") == 0) {
            uint16_t pos = 0;
            bool first = TRUE;

            pos += snprintf(buffer, sizeof(buffer), "Connected users: ");
            for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
                if (clients[i].isActive && clients[i].username[0] != '\0') {
                    if (!first) {
                        pos += snprintf(buffer + pos, sizeof(buffer) - pos, ", ");
                    }
                    pos += snprintf(buffer + pos, sizeof(buffer) - pos, "%s", clients[i].username);
                    first = FALSE;
                }
            }
            snprintf(buffer + pos, sizeof(buffer) - pos, "\r\n");
            
            call Transport.write(clients[clientId].socket, (uint8_t*)buffer, strlen(buffer));
            dbg(CHAT_CHANNEL, "Server: Sent user list to client %d\n", clientId);
        } 
        else {
            snprintf(buffer, sizeof(buffer), "Error: Unknown command '%s'\r\n", cmd);
            call Transport.write(clients[clientId].socket, (uint8_t*)buffer, strlen(buffer));
        }
    }


    void handleReceivedData(uint16_t clientId, uint8_t *data, uint16_t len) {
        uint8_t buffer[SOCKET_BUFFER_SIZE];
        uint16_t i;
        char *cmd, *content;

        // Ensure null termination
        data[len] = '\0';
        
        dbg(CHAT_CHANNEL, "Server: Received data from client %d: %s\n", clientId, data);
        
        cmd = strtok((char*)data, " ");
        if(cmd == NULL) return;

        if(strcmp(cmd, "hello") == 0) {
            // Handle hello message
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
            // Handle broadcast message
            content = strtok(NULL, "\r\n");
            if(content != NULL) {
                sprintf((char*)buffer, "%s: %s\r\n", clients[clientId].username, content);
                dbg(CHAT_CHANNEL, "Server: Broadcasting message from %s: %s", 
                    clients[clientId].username, content);
                
                // Broadcast to all other clients
                for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
                    if(clients[i].isActive && i != clientId) {
                        call Transport.write(clients[i].socket, buffer, strlen((char*)buffer));
                    }
                }
            }
        }
    }

    // event void ServerTimer.fired() {
    //     uint8_t buffer[SOCKET_BUFFER_SIZE];
    //     uint16_t bytesRead;
    //     uint16_t i;
    //     socket_t client_socket;

    //     if (!isRunning) return;

    //     client_socket = call Transport.accept(server_socket);
    //     if (client_socket != -1) {
    //         for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
    //             if (!clients[i].isActive) {
    //                 clients[i].socket = client_socket;
    //                 clients[i].isActive = TRUE;
    //                 memset(clients[i].username, 0, sizeof(clients[i].username));
    //                 dbg(CHAT_CHANNEL, "Server: Client %d connected on socket %d\n", i, client_socket);
    //                 break;
    //             }
    //         }
    //     }

    //     for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
    //         if (clients[i].isActive) {
    //             bytesRead = call Transport.read(clients[i].socket, buffer, sizeof(buffer) - 1);
    //             // if (bytesRead > 0) {
    //             //     buffer[bytesRead] = '\0';
    //             //     processMessage(i, buffer, bytesRead);
    //             // }
    //             if (bytesRead > 0) {
    //                 dbg(CHAT_CHANNEL, "Server: Read %d bytes from client %d on socket %d\n", 
    //                     bytesRead, i, clients[i].socket);
    //                 buffer[bytesRead] = '\0';
    //                 processMessage(i, buffer, bytesRead);
    //             }
    //         }
    //     }
    // }

    event void ServerTimer.fired() {
        uint8_t buffer[SOCKET_BUFFER_SIZE];
        uint16_t bytesRead;
        uint16_t i;
        socket_t client_socket;

        if (!isRunning) return;

        // Accept new connections
        client_socket = call Transport.accept(server_socket);
        if (client_socket != 255) {  // Change from -1 to 255
            for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
                if (!clients[i].isActive) {
                    clients[i].socket = client_socket;
                    clients[i].isActive = TRUE;
                    memset(clients[i].username, 0, sizeof(clients[i].username));
                    dbg(CHAT_CHANNEL, "Server: Client %d connected on socket %d\n", i, client_socket);
                    break;
                }
            }
        }

        // Check for data from connected clients
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (clients[i].isActive && clients[i].socket != 255) {  // Add check for valid socket
                bytesRead = call Transport.read(clients[i].socket, buffer, sizeof(buffer) - 1);
                if (bytesRead > 0) {
                    dbg(CHAT_CHANNEL, "Server: Read %d bytes from client %d (socket %d)\n", 
                        bytesRead, i, clients[i].socket);
                    buffer[bytesRead] = '\0';
                    processMessage(i, buffer, bytesRead);
                }
            }
        }
    }
}
