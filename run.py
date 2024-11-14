# Ensure TestSim is imported correctly
from TestSim import TestSim

def main():
    s = TestSim()
    s.runTime(1)

    # Set up and run tests as before
    s.loadTopo("example.topo")
    s.loadNoise("some_noise.txt")
    s.bootAll()

    s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.GENERAL_CHANNEL)
    s.addChannel(s.TRANSPORT_CHANNEL)  # Updated from PROJECT3_CHANNEL

    print("Setting up the server on Node 2...")
    s.cmdTestServer(2, 80)  # Node 2 listening on port 80
    s.runTime(5)

    print("Client (Node 1) connecting to Server (Node 2)...")
    s.cmdTestClient(1, 81, 80, 1)  # Node 1 client connecting to Node 2
    s.runTime(10)

    print("Sending data from Client to Server...")
    s.cmdClientSend(1, 81, 80, "Hello from Client!")
    s.runTime(10)

    print("Closing the connection...")
    s.cmdKillClient(1, 2, 81, 80)
    s.runTime(10)

    print("Test completed. Check debug outputs for details.")

if __name__ == "__main__":
    main()
