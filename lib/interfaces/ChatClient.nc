interface ChatClient {
    // Connect to server with username
    command error_t connect(uint8_t *username, uint8_t port);
    
    // Send broadcast message
    command error_t sendMessage(uint8_t *message);
    
    // Send private message
    command error_t whisper(uint8_t *username, uint8_t *message);
    
    // Request list of users
    command error_t listUsers();
    
    // Disconnect from server
    command error_t disconnect();
    
    // Events that can be signaled back
    event void messageReceived(uint8_t *sender, uint8_t *message);
    event void connectionComplete();
    event void userListReceived(uint8_t *users);
}