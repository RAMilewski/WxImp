
// Device code to put calibration data into persistent storage in the Imp

#require "HTS221.device.lib.nut:2.0.1"
#require "LPS22HB.class.nut:1.0.0"
#require "WS2812.class.nut:2.0.2"

// Create one case for each WxImp you wish to configure.

imp.enableblinkup(true);

deviceid <- hardware.getdeviceid();// WxImp Device Code
// Version 0.9.3
// Copyright 2017 - Richard Milewski
// Released under the Mozilla Public License v2.0
// https://www.mozilla.org/en-US/MPL/2.0/
// 
// Removed deprecated network calls, replaced with net.info()
// Moved calibration data to persistant storage in the Imp


// Define constants
const sampleTime = 5; // The length of time the anemometer is sampled.
const timeZone = -7;  

// Declare Global Variables

tempSensor <- null;
pressureSensor <- null;
led   <- null;

sleepTime <- 15;  //Default cycle Time - Reset by device config.

data  <- {};
data.stationName <- "This WxImp has not been calibrated."; // Name of this WxImp weather station
data.temp <- 0;                     // Temperature from the temp/humidity sensor
data.humidity <- 0;                 // Relative Humidity from the temp/humidity sensor
data.temp2 <- 0;                    // Temperature from the pressure/temp sensor 
data.pressure <- 0;                 // Atmospheric pressure from the pressure/temp sensor
data.light <- 0;                    // Light level from the Imp blink-up sensor
data.voltage <- 0;                  // Supply voltage (should be 3.3v nominal)
data.dewpoint <- 0;                 // Calculated dew point based on temp and humidity
data.cloudbase <- 0;                // Calculated base of Cumulus clouds (if present)
data.rssi <- 0;                     // WiFi signal strength
data.ssid <- "Unknown";             // WiFi network name
data.latitude <- 0;                 // Latitude of station (Useful for joining weather reporting networks)
data.longitude <- 0;                // Longitude of station
data.elevation <- 0;                // Elevation in Meters 
data.t1correction <- 0;             // Correction for Temp Sensor 1
data.t2correction <- 0;             // Correction for Temp Sensor 2
data.RHcorrection <- 0;             // Humidity Sensore Correctoin
data.pressureCorrection <- 0;       // Barometer correction to mean sea level pressure in Millibars
data.wind  <- {};                   // Anemometer parameters
data.wind.zero <- 0;                // Correction for anemometer amplifier input bias
data.wind.max <- 0;                 // Wind sample result
data.wind.start <- 0;               // Time stamp for wind sample
data.wind.sampleTime <- 0;          // Time to sample anemometer data
data.wind.sampleCount <- 0;         // Number of wind sample readings

// Read Calibration Data from Imp Persistant Storage
configid <- null;
config <- imp.getuserconfiguration();

if (!config) {
    server.log("No Device Config Found");
}else{
    if (configid = hardware.getdeviceid()) {        // If the calibration info is for this device...
    local strlen = config.readn('b');
    configid <- config.readstring(strlen);
    strlen = config.readn('b');
    configformat <- config.readstring(strlen);
    sleepTime <- config.readn('s');
    strlen = config.readn('b');
    data.stationName <- config.readstring(strlen);
    data.wind.zero <- config.readn('s');
    data.latitude <- config.readn('f');
    data.longitude <- config.readn('f');
    data.elevation <- config.readn('s');
    data.t1correction <- config.readn('f');
    data.t2correction <- config.readn('f');
    data.RHcorrection <- config.readn('f');
    data.pressureCorrection <- config.readn('f');
    }
}

// Define the disconnection handler
function disconnectHandler(reason) {
    if (reason != SERVER_CONNECTED) {
        // Attempt to reconnect
        // Note that we pass in the same callback we use
        // for unexpected disconnections
        server.connect(disconnectHandler, 30);
        
        // Set the state flag so that other parts of the
        // application know that the device is offline
        disconnectedFlag = true;
    } else {
        // Server is connected, so update the state flag
        disconnectedFlag = false;
    }
}


function Fahrenheit(TempC) {
    return TempC * 1.8 + 32;
}

function Kelvin(TempC) {
    return TempC + 273;

}

function DewPoint(t1, rh1) 
{
	t1 = Kelvin(t1);
			
	local p0 = 7.5152E8;
	local deltaH = 42809
	local R = 8.314;
			
	local sat_p1 = p0 * math.exp(-deltaH/(R*t1));
	local vapor = sat_p1 * rh1/100
    return (-deltaH/(R*math.log(vapor/p0)) - 273);
}

// ************** This Function appears to be inaccurate.  It overcorrects when compared to METAR pressure differences.

function mslPressure(pressure, temp, elevation) {  // see https://www.sandhurstweather.org.uk/wx4.php
    local correctionFactor = math.pow(2.7182818284, (elevation * -1)/(Kelvin(temp) * 29.263));
    return (pressure/correctionFactor);
}  // **************************************************************************************************************


function sampleData()
{
    local reading = tempSensor.read();
    
        data.temp <- reading.temperature + data.t1correction;
        data.humidity <- reading.humidity + data.RHcorrection;
    
    reading = pressureSensor.read();
    
        data.pressure <- reading.pressure + data.pressureCorrection;
        data.mslPressure <- mslPressure(data.pressure,data.temp,data.elevation)
        data.temp2 <- reading.temperature + data.t2correction;

    data.voltage <- hardware.voltage();
    data.light <- hardware.lightlevel();
  
    data.dewpoint <- DewPoint(data.temp, data.humidity);
    data.cloudbase <- (250 * ((Fahrenheit(data.temp) - Fahrenheit(data.dewpoint)))/100).tointeger()*100;
    
    
    local i = 0;
    local a = 0;
    local total = 0 
    local windSample = 0;
    data.wind.start = time();

    // Read the anemometer input pin for sampleTime seconds and keep the maximum 
    while (time() < (data.wind.start + sampleTime)) {
        
        a = anemometer.read()
        if (a > windSample) { windSample = a; }
        i ++;
        imp.sleep(0.002);
            //
            /////////////////////// W A R N I N G ! ! ///////////////////////////////
            // imp.sleep() blocks interrupts and messages from other functions.
            // Rewrite this using imp.wakeup() before adding additonal sensors.
    }
    
    data.wind.max = (windSample/16) - data.wind.zero;   
    if (data.wind.max < 0) {data.wind.max = 0; }
    data.wind.sampleTime = time() - data.wind.start;
    data.wind.sampleCount = i;
}




 // Deep Sleep
    imp.onidle(function() {
        server.sleepfor(sleepTime);
    });

//Begin executing program

    imp.enableblinkup(false);

    // Configure I2C bus for sensors
    local i2c = hardware.i2c89;
    i2c.configure(CLOCK_SPEED_400_KHZ);
    
    tempSensor = HTS221(i2c);
    tempSensor.setMode(HTS221_MODE.ONE_SHOT);
    tempSensor.setResolution(8,16);
    
    pressureSensor = LPS22HB(i2c);
    pressureSensor.softReset();
    
    // Turn on 3.3v for Grove Analog Connectors
    hardware.pin1.configure(DIGITAL_OUT, 1);

    // Configure Analog Port for Anemometer
    anemometer <- hardware.pin5;
    anemometer.configure(ANALOG_IN);
    
    sampleData();
    server.connect();       //explicitly turning on the WiFi so we can measure rssi.
    local netData = imp.net.info();
    if ("active" in netData) {
        // We have an active network connection
        data.rssi = netData.interface[netData.active].rssi;
        data.ssid = netData.interface[netData.active].connectedssid;
    }
    agent.send("reading", data);
  
    
   
    
    
blobformat <- null;

switch (deviceid) {
    case  "Imp Device ID Goes Here":    // We use setting the config based on device ID.    
        blobformat = "0.9.3";           // This must match the format in the WxImp code (Currently the WxImp revision)
        sleepTime <- 60;                // Time between readings.
        stationName <- "A WxImp"        // Station Name
        windZero <- 127;                // The value reported when the anemometer is still
        deviceLat <- 37.335369;         // Latitude of station (Useful for joining weather reporting networks)
        deviceLon <- -121.886938;       // Longitude of station
        deviceElev <- 46;               // Elevation in Meters 
        temp1correction <- -1.3;        // Temp sensor 1 correction  (deg. C)
        temp2correction <- -5.6;        // Temp sensor 2 correction  (deg. C)       
        RHcorrection <- -23;            // Humidity sensor correction (%RH)
        pressureCorrection <- 2.1;     // Barometer sensor correction (hPa/mb)
                                             
    break
    
    case  "238e52e22c4d8aee":
        blobformat = "0.9.3"
        sleepTime <- 60;
        stationName <- "Yellow WxImp";
        windZero <- 130;
        deviceLat <- 37.335369;         
        deviceLon <- -121.886938;
        deviceElev <- 46;   
        temp1correction <- -0.4;
        temp2correction <- 0;
        RHcorrection <- -22.5;
        pressureCorrection <- -2.9;
        
    break 
    
    case  "238e52e22c4d8aee":
        blobformat = "0.9.3"
        sleepTime <- 60;
        stationName <- "Green WxImp";
        windZero <- 130;
        deviceLat <- 37.335369;         
        deviceLon <- -121.886938;
        deviceElev <- 46;   
        temp1correction <- -0.4;
        temp2correction <- 0;
        RHcorrection <- -22.5;
        pressureCorrection <- -2.9;
        
    break 
}


if (blobformat) {
    local config = blob();
    config.writen(deviceid.len(),'b');
    config.writestring(deviceid);
    config.writen(blobformat.len(), 'b');
    config.writestring(blobformat);
    config.writen(sleepTime, 's');
    config.writen(stationName.len(),'b');
    config.writestring(stationName);
    config.writen(windZero, 's');
    config.writen(deviceLat, 'f');
    config.writen(deviceLon, 'f');
    config.writen(deviceElev, 's');
    config.writen(temp1correction, 'f');
    config.writen(temp2correction, 'f');
    config.writen(RHcorrection, 'f');
    config.writen(pressureCorrection, 'f');

    imp.setuserconfiguration(config);
    server.log ("\n\nConfiguration saved for device " + deviceid + "\n\n");
} else {
    server.log("\nThere is no configuration information for this device.");
    server.log("\nThe device id for this device is: " + deviceid );
    imp.setuserconfiguration(null);
    server.log("\nConfiguration storage cleared.\n\n");
}



