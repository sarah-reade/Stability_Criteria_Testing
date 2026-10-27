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