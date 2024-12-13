interface ChatServer {
    // Start the chat server
    command error_t start(uint16_t node);
    
    // Stop the chat server
    command error_t stop();
    
    // Events
    event void clientConnected(uint16_t clientId, uint8_t *username);
    event void clientDisconnected(uint16_t clientId);
    event void messageReceived(uint16_t clientId, uint8_t *message);
}