// Test program to show contents of stored WxImp calibration data


config <- imp.getuserconfiguration();

if (config) {
    local strlen = 0;
    
    strlen = config.readn('b');
    deviceid <- config.readstring(strlen);
    strlen = config.readn('b');
    configformat <- config.readstring(strlen);
    sleepTime <- config.readn('s');
    strlen = config.readn('b');
    stationName <- config.readstring(strlen);
    windZero <- config.readn('s');
    deviceLat <- config.readn('f');
    deviceLon <- config.readn('f');
    deviceElev <- config.readn('s');
    temp1correction <- config.readn('f');
    temp2correction <- config.readn('f');
    RHcorrection <- config.readn('f');
    pressureCorrection <- config.readn('f');

    server.log("Calibration for: " + deviceid);
    server.log("Configuration format: " + configformat);
    server.log("Sleep time: " + sleepTime);
    server.log("Station Name: " + stationName);
    server.log("Wind Correction: " + windZero);
    server.log("Latitude: " + deviceLat);
    server.log("Longitude:" + deviceLon);
    server.log("Elevation: " + deviceElev);
    server.log("Temp. Correction 1: " + temp1correction);
    server.log("Temp. Correction 2: " + temp2correction);
    server.log("Humidity Correction: " + RHcorrection);
    server.log("Pressure Correction: " + pressureCorrection);
} else {
    server.log("No Device Config Found");
}    