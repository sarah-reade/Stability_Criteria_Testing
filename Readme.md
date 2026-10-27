# Data Processing

## Overview

This project uses MATLAB to process the collected force sensor data. All processing scripts, raw data, and generated results are organized into the following folders:

- **`Data_Processing/`** — Contains all MATLAB scripts used for data processing.
- **`Force_Sensor_Data/`** — Contains all collected force sensor data.
- **`Results/`** — Stores the processing results, organized by the method used. This folder is automatically updated whenever new data is processed.

## Getting Started

### Requirements

- MATLAB R2023b (the version used for testing)

### Running the Data Processing

1. Open MATLAB.
2. Add the `Data_Processing/` folder to the MATLAB path.
3. Run the `process_data` script without any input arguments to process the data using the default method.

This will post process and generate graphs depending on your selection on the UI.

### Processing All Data with All Methods

To process all collected data using all available methods automatically, call `process_data` with a `false` input argument.

This will run the processing methods and update the corresponding results in the `Results/` folder.

## Compatibility

This project has been tested with **MATLAB R2023b**. Compatibility with other MATLAB versions has not been verified.

# Teensy Code

## Overview

Data from IMU is collected using a teensy. This is connected to the control PC using an ethernet interface and recorded into a csv file. All files for the teensy are stored in **Teensy_Code/**

## Getting Started

### Requirements

- Teensy 4.1 with Ethernet
- Ethernet Kit for Teensy 4.1
- 2 x BNO086 9-dof IMU
- [Arduino IDE with teensy package installed](https://www.pjrc.com/teensy/td_download.html) and the following libraries:
  - NativeEthernet
  - SparkFun_BNO08x_Arduino_Library

### Preparation

1. Install the copy of the SparkFun_BNO08x_Arduino_Library in the Arduino libraries folder
2. Using the arduino IDE install the Eth_IMU_Interface onto the teensy
3. Build the log_imu.cpp locally. For linux you can use the command:
```bash
cd Teensy_Code
g++ log_imu.cpp -o log_imu
sudo chmod +x log_imu
```
4. Setup the teensy local ethernet network up to match the ino code. If using the default, set your network to:

The network can be edited to be on the same network as any other sensors you are using in the Eth_IMT_Interface.ino file:
```hpp
IPAddress ip(192, 168, 1, 177);
IPAddress myDns(192, 168, 1, 1);
IPAddress gateway(192, 168, 1, 1);
IPAddress subnet(255, 255, 0, 0);
IPAddress cmd_ip(192, 168, 1, 2);
```

### Running

To collect data simply power the teensy over USB and connect the ethernet cable. Run the log_imu script:
```bash
cd Teensy_Code
log_imu ../Force_Sensor_Data/
```
If data is being recorded then it will start printing in the terminal.

*Note: For new data to be registered for processing, make sure to add the new data file name to the Data_Reg.csv along with the conditions*

