#ifndef ETHERNET_WRAP_HPP
#define ETHERNET_WRAP_HPP


#include <NativeEthernet.h>

struct EthernetWrapperMsg
{
  uint8_t* data;
  size_t length;
};

struct EthernetWrapper
{
  private:
     // server object
    EthernetServer server_;

    // one client only at set address
    EthernetClient client_;

    // address of desired control client
    IPAddress client_ip_;

    // buffer for packets not yet processed
    std::vector<std::vector<byte>>  loose_packets_;

  public:
    // Initialise
    EthernetWrapper (const int& port, const IPAddress& client_ip):  server_(port), client_(), client_ip_(client_ip), loose_packets_(){}

    // Setup
    bool setup(const byte* mac, const IPAddress& ip, const IPAddress& dns, const IPAddress& gateway, const IPAddress& subnet)
    {
      Ethernet.begin(static_cast<uint8_t*>(const_cast<byte*>(mac)), ip, dns, gateway, subnet);

      // Check for Ethernet hardware present
      if (Ethernet.hardwareStatus() == EthernetNoHardware) {
        return false;
      }
      if (Ethernet.linkStatus() == LinkOFF) {
        return false;
      }

      // Start listening for clients
      server_.begin();
      
      return true;
    }

    // Connect to client with timeout in seconds. TODO: Fix timeout
    bool connect_client(const float& client_timeout)
    {
      float timeout = 1;
      // return if client connected
      if (client_.connected())
      {
        return true;
      }
      else
      {
        client_.stop();
      }
      
      // get start time
      unsigned long start_time = millis();

      // for timeout, loop to check for new clients
      while(millis() - start_time < timeout*1000)
      {
        // check for new client
        EthernetClient new_client = server_.accept();

        // if new client, check if it is the desired client
        if(new_client)
        {
          // check if client is the desired client
          if(new_client.remoteIP() == client_ip_)
          {
            // if it is, set the client to the new client
            client_ = new_client;
            return true;
          }
        }
        delay(10);
      }

      return false;
    }
    

    bool send_packets(const EthernetWrapperMsg &packet)
    {
      
      // check client connected
      if(!connect_client(0.1))
      {
        return false;
      }

      if (client_.write(packet.data,packet.length) < packet.length) {return false;}
      return true;
    }
};

#endif