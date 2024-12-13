interface ChatClient {
    command error_t start(uint16_t node, uint8_t port);
    command error_t connect(uint8_t *username);
    command error_t sendMessage(uint8_t *message);
    command error_t whisper(uint8_t *username, uint8_t *message);
    command error_t listUsers();
    command error_t disconnect();
    
    // Events that can be signaled back
    event void messageReceived(uint8_t *sender, uint8_t *message);
    event void connectionComplete();
    event void userListReceived(uint8_t *users);
}