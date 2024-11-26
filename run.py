from TestSim import TestSim

def cmdTestServer(sim, address, port):
    """Initiates the server at a given node and port."""
    print("Debug({}): Setting up server on Node {}, Port {}".format(address, address, port))

    # Allocate a socket and bind it to the port
    socket_address = chr(address) + chr(port)  # Pack node ID and port
    sim.sendCMD(sim.CMD_BIND, address, socket_address)  # Bind socket
    sim.sendCMD(sim.CMD_LISTEN, address, "")  # Start listening

    # Simulate connection attempts with events
    sim.runTime(10)  # Step the simulation for connection attempts
    print("Debug({}): Server setup complete.".format(address))


def cmdTestClient(sim, dest, src_port, dest_port, transfer):
    """Initiates a client, connects to the server, and transfers data."""
    print("Debug({}): Client attempting connection to Node {}, Port {}".format(dest, dest, dest_port))

    # Bind client socket to source port
    src_address = chr(dest) + chr(src_port)
    dest_address = chr(dest) + chr(dest_port)

    sim.sendCMD(sim.CMD_BIND, dest, src_address)  # Bind client socket
    sim.sendCMD(sim.CMD_CONNECT, dest, dest_address)  # Attempt connection
    sim.runTime(10)  # Step the simulation for connection setup

    print("Debug({}): Connection established. Starting data transfer...".format(dest))

    # Transfer data in chunks of up to 16 bytes
    data = [i for i in range(transfer)]
    while data:
        chunk = data[:16]
        del data[:16]
        sim.sendCMD(sim.CMD_WRITE, dest, "".join(chr(x) for x in chunk))
        sim.runTime(5)  # Simulate time for data transfer


def cmdClientClose(sim, client_address, dest, src_port, dest_port):
    """Closes the client connection."""
    print("Debug({}): Closing connection to Node {}, Port {}".format(client_address, dest, dest_port))

    # Create source and destination addresses
    src_address = chr(client_address) + chr(src_port)
    dest_address = chr(dest) + chr(dest_port)

    # Issue close command
    sim.sendCMD(sim.CMD_CLOSE, client_address, src_address + dest_address)
    sim.runTime(10)  # Simulate connection teardown


def main():
    # Initialize the simulation
    sim = TestSim()
    sim.loadTopo("long_line.topo")
    sim.loadNoise("no_noise.txt")
    sim.bootAll()
    sim.addChannel(sim.COMMAND_CHANNEL)
    sim.addChannel(sim.GENERAL_CHANNEL)
    sim.addChannel(sim.TRANSPORT_CHANNEL)

    # Test server setup
    cmdTestServer(sim, address=1, port=80)

    # Test client setup and data transfer
    cmdTestClient(sim, dest=1, src_port=20, dest_port=80, transfer=128)

    # Test connection teardown
    cmdClientClose(sim, client_address=2, dest=1, src_port=20, dest_port=80)

    # Run for additional time to observe final outputs
    sim.runTime(20)


if __name__ == '__main__':
    main()
