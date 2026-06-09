// Generated with assistance from OpenAI's ChatGPT for easy TCP communication.
//#define DEBUG_TCP_CLIENT

#include <iostream>
#include <boost/asio.hpp>
#include <vector>
#include <string>
#include <iomanip>
#include <iostream>
#include <fstream>
#include <thread>
using namespace std::chrono_literals;

// Constants
#define BUFFER_SIZE 256
#define PAYLOAD_SIZE 27  // 1 (sensorID) + 24 (6 floats) + 2 (2 uint8_t)

// TCPClient class provides an abstraction for creating a TCP connection,
// sending packets, and receiving packets using Boost.Asio.
class TCPClient {
public:
    // Constructor to initialize with server IP and port.
    TCPClient(const std::string& server_ip, int port);

    // Destructor ensures proper cleanup of resources.
    ~TCPClient();

    // Connect to the server.
    bool connect();

    // Disconnect from the server.
    void disconnect();

    // Check if the client is connected.
    bool isConnected() const;

    // Send a packet of data to the server.
    bool sendPacket(const std::vector<uint8_t>& packet);

    // Receive a packet of specified size from the server.
    bool receivePacket(std::vector<uint8_t>& packet, size_t size);

private:
    std::string server_ip_;  // Server IP address.
    int port_;               // Port number.
    bool connected_;         // Connection state.

    boost::asio::io_context io_context_;   // IO context for Boost.Asio operations.
    boost::asio::ip::tcp::socket socket_; // TCP socket.
};

// Constructor initializes the server IP and port, and sets up the socket.
TCPClient::TCPClient(const std::string& server_ip, int port)
    : server_ip_(server_ip), port_(port), connected_(false), socket_(io_context_) {}

// Destructor ensures any open connection is closed.
TCPClient::~TCPClient() {
    if (connected_) {
        disconnect();
    }
}

// Connect to the specified server and port.
bool TCPClient::connect() {
    try {
        // Resolve the server address and port.
        boost::asio::ip::tcp::resolver resolver(io_context_);
        boost::asio::ip::tcp::resolver::results_type endpoints = resolver.resolve(server_ip_, std::to_string(port_));

        // Connect the socket to the resolved endpoint.
        boost::asio::connect(socket_, endpoints);
        connected_ = true;
        std::cout << "Connected to " << server_ip_ << " on port " << port_ << "\n";
    } catch (std::exception& e) {
        std::cerr << "Connection failed: " << e.what() << "\n";
        connected_ = false;
    }
    return connected_;
}

// Disconnect the client by closing the socket.
void TCPClient::disconnect() {
    if (connected_) {
        socket_.close();
        connected_ = false;
        std::cout << "Disconnected.\n";
    }
}

// Check if the client is currently connected to the server.
bool TCPClient::isConnected() const {
    return connected_;
}

// Send a packet to the server.
bool TCPClient::sendPacket(const std::vector<uint8_t>& packet) {
    if (!connected_) {
        std::cerr << "Not connected. Cannot send packet.\n";
        return false;
    }

    try {
        boost::asio::write(socket_, boost::asio::buffer(packet));
#ifdef DEBUG_TCP_CLIENT
        std::cout << "Packet sent.\n";
        std::cout << "Packet contents: ";
        for (auto byte : packet) {
            std::cout << std::hex << static_cast<int>(byte) << " ";
        }
        std::cout << std::dec << "\n"; 
#endif
        return true;
    } catch (std::exception& e) {
        std::cerr << "Failed to send packet: " << e.what() << "\n";
        return false;
    }
}

// Receive a packet of a specific size from the server.
bool TCPClient::receivePacket(std::vector<uint8_t>& packet, size_t size) {
    if (!connected_) {
        std::cerr << "Not connected. Cannot receive packet.\n";
        return false;
    }

    // if (socket_.available() < size) {
    //     return false;
    // }

    try {
        // Resize the packet buffer to accommodate the incoming data.
        uint8_t len;
        boost::asio::read(socket_, boost::asio::buffer(&len, 1));
        packet.resize(len);
        boost::asio::read(socket_, boost::asio::buffer(packet, len));
#ifdef DEBUG_TCP_CLIENT
        std::cout << "Packet received.\n";
#endif
        return true;
    } catch (std::exception& e) {
        std::cerr << "Failed to receive packet: " << e.what() << "\n";
        return false;
    }
}


// Global flag for graceful shutdown
volatile bool running = true;

void signal_handler(int sig) {
    running = false;
    std::cout << "\nShutdown signal received. Closing connections..." << std::endl;
}

// Parse binary IMU data from packet
struct IMUReading {
    uint8_t sensorID;
    float linX, linY, linZ;
    float gyrX, gyrY, gyrZ;
    uint8_t linAcc, gyrAcc;

    bool parse(const uint8_t* buffer, size_t length) {
        if (length < PAYLOAD_SIZE) {
            return false;
        }

        size_t offset = 0;

        // Parse sensorID
        sensorID = buffer[offset++];

        // Parse linear acceleration (3 floats)
        std::memcpy(&linX, buffer + offset, sizeof(float)); offset += sizeof(float);
        std::memcpy(&linY, buffer + offset, sizeof(float)); offset += sizeof(float);
        std::memcpy(&linZ, buffer + offset, sizeof(float)); offset += sizeof(float);

        // Parse gyroscope (3 floats)
        std::memcpy(&gyrX, buffer + offset, sizeof(float)); offset += sizeof(float);
        std::memcpy(&gyrY, buffer + offset, sizeof(float)); offset += sizeof(float);
        std::memcpy(&gyrZ, buffer + offset, sizeof(float)); offset += sizeof(float);

        // Parse accuracy values (2 uint8_t)
        linAcc = buffer[offset++];
        gyrAcc = buffer[offset++];

        return true;
    }
};

// Generate CSV filename with current date/time
std::string generate_filename(const std::string& folder) {
    auto now = std::chrono::system_clock::now();
    auto time = std::chrono::system_clock::to_time_t(now);
    std::tm* timeinfo = std::localtime(&time);

    std::ostringstream oss;
    oss << folder << "/";
    oss << std::put_time(timeinfo, "%Y%m%d_%H%M%S") << "_IMULog.csv";

    return oss.str();
}

// Write CSV header
void write_csv_header(std::ofstream& file) {
    file << "Date,Time_ms,SensorID,LinX,LinY,LinZ,GyrX,GyrY,GyrZ,LinAcc,GyrAcc" << std::endl;
}

// Write IMU reading to CSV
void write_imu_to_csv(std::ofstream& file, const IMUReading& reading) {
    auto now = std::chrono::system_clock::now();
    auto duration = now.time_since_epoch();
    auto millis = std::chrono::duration_cast<std::chrono::milliseconds>(duration);
    auto seconds = std::chrono::duration_cast<std::chrono::seconds>(duration);

    std::chrono::system_clock::time_point tp(seconds);

    auto time = std::chrono::system_clock::to_time_t(tp);
    std::tm* timeinfo = std::localtime(&time);

    uint64_t ms = millis.count() % 1000;

    // Write date and time with milliseconds
    file << std::put_time(timeinfo, "%Y-%m-%d") << ","
         << std::put_time(timeinfo, "%H:%M:%S") << "." << std::setfill('0') << std::setw(3) << ms << ",";

    // Write IMU data with 6 decimal places
    file << std::fixed << std::setprecision(6)
         << static_cast<int>(reading.sensorID) << ","
         << reading.linX << ","
         << reading.linY << ","
         << reading.linZ << ","
         << reading.gyrX << ","
         << reading.gyrY << ","
         << reading.gyrZ << ","
         << static_cast<int>(reading.linAcc) << ","
         << static_cast<int>(reading.gyrAcc) << std::endl;
}

int main(int argc, char* argv[]) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " <output_folder>" << std::endl;
        return 1;
    }

    std::string folder = argv[1];

    // Set up signal handler for graceful shutdown
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    // Generate output filename
    std::string filename = generate_filename(folder);
    std::cout << "Logging IMU data to: " << filename << std::endl;

    // Open CSV file
    std::ofstream csv_file(filename);
    if (!csv_file.is_open()) {
        std::cerr << "Error: Could not open file " << filename << std::endl;
        return 1;
    }

    write_csv_header(csv_file);

    // Setup TCP client (Ethernet data source)
    std::string server_ip = "192.168.1.177";
    int port  = 23;
    TCPClient client(server_ip,port);

    std::vector<uint8_t> buffer;

    while (running) {
        
        // Attempt to connect to the server.
        if (!client.isConnected()) {
            if (!client.connect()) {
                std::cerr << "Failed to connect to the server. Retrying in 1 second." << std::endl;
                std::this_thread::sleep_for(1s);
                continue;
            }
            
        }
        
        // Get Ethernet Data
        if (client.receivePacket(buffer, BUFFER_SIZE)) {
            
            size_t start = std::string::npos;

            for (size_t i = 0; i + 1 < buffer.size(); i++) {
                if (buffer[i] == 0xAA && buffer[i + 1] == 0x55) {
                    start = i;
                    break;
                }
            }

            if (start == std::string::npos) {
                continue; // no frame found
            }

            const uint8_t* payload = buffer.data() + start + 2;
            size_t payload_size = buffer.size() - (start + 2);

            IMUReading reading;
            if (reading.parse(payload, payload_size)) {

                write_imu_to_csv(csv_file, reading);
                csv_file.flush();

                std::cout << "Sensor " << static_cast<int>(reading.sensorID)
                        << " Lin(" << reading.linX << ", " << reading.linY << ", " << reading.linZ << ")"
                        << " Gyro(" << reading.gyrX << ", " << reading.gyrY << ", " << reading.gyrZ << ")\n";
            }
        }

        //std::this_thread::sleep_for(1ms); // Sleep briefly to avoid busy waiting
    }

    client.disconnect();

    std::cout << "CSV file saved: " << filename << std::endl;
    return 0;
}