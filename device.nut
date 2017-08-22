// WxImp Device Code
// Version 0.9 (build 525)
// Copyright 2017 - Richard Milewski
// Released under the Mozilla Public License v2.0
// https://www.mozilla.org/en-US/MPL/2.0/
// 
//

#require "HTS221.device.lib.nut:2.0.1"
#require "LPS22HB.class.nut:1.0.0"
#require "WS2812.class.nut:2.0.2"

// Define constants
const sleepTime = 15;
const sampleTime = 5; // The length of time the anemometer is sampled.
const timeZone = -8;  

// Sensor calibration constants
const temp1correction = 0;
const temp2correction = 0;
const humidityCorrection = 0;
const pressureCorrection = 0;


// Declare Global Variables
tempSensor <- null;
pressureSensor <- null;
led   <- null;

data  <- {};
data.temp <- null;     //temperature from the temp/humidity sensor (preferred)
data.humidity <- null;
data.temp2 <- null;    //temperature from the pressure/temp sensor 
data.pressure <- null; //temp is preferred over temp2 because of thermal issues
                       //inherent in the Imp Explorer and WxImp box designs.
data.light <- null;
data.voltage <- null;
data.dewpoint <- null;
data.cloudbase <- null;
data.rssi <- null;
data.refresh <- sleepTime;
data.wind  <- {};
data.wind.max <- null;
data.wind.start <- null;
data.wind.sampleTime <- null;
data.wind.sampleCount <- null;


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




function sampleAnemometer()
{

} 

function sampleData()
{
    local reading = tempSensor.read();
    
        data.temp <- reading.temperature + temp1correction;
        data.humidity <- reading.humidity + humidityCorrection;
    
    reading = pressureSensor.read();
    
        data.pressure <- reading.pressure + pressureCorrection;
        data.temp2 <- reading.temperature + temp2correction;

    data.voltage <- hardware.voltage();
    data.light <- hardware.lightlevel();
  
    data.dewpoint <- DewPoint(data.temp, data.humidity);
    data.cloudbase <- (250 * ((Fahrenheit(data.temp) - Fahrenheit(data.dewpoint)))/100).tointeger()*100;
    
    
    local i = 0;
    local a = 0;
    local total = 0 
    data.wind.max = 0;
    data.wind.start = time();

    // Read the anemometer input pin for sampleTime seconds and keep the maximum 
    while (time() < (data.wind.start + sampleTime)) {
        a = anemometer.read()
        if (a > data.wind.max) { data.wind.max = a; }
        i ++;
        imp.sleep(0.002);
            //
            /////////////////////// W A R N I N G ! ! ///////////////////////////////
            // imp.sleep() blocks interrupts and messages from other functions.
            // Rewrite this using imp.wakeup() before adding additonal sensors.
    }
    data.wind.sampleTime = time() - data.wind.start;
    data.wind.sampleCount = i;
}



function logData()
{
    local theData =  "\n";
    theData += "Temperature: " + format("%.3f", data.temp) + "°C  " + format("%.1f", Fahrenheit(data.temp)) + "°F " + format("%.1f", Kelvin(data.temp)) + "°K \n";
    theData += "Temperature-2: " + format("%.3f", data.temp2) + "°C  " + format("%.1f", Fahrenheit(data.temp2)) + "°F " + format("%.1f", Kelvin(data.temp2)) + "°K \n";
    theData += "Relative Humidity: " + format("%.0f", data.humidity) + "% \n";
    theData += "Dew Point: " + format("%.1f",data.dewpoint) +  "°C  " + format("%.1f",Fahrenheit(data.dewpoint)) + "°F " + format("%.2f",Kelvin(data.dewpoint)) + "°K \n";
    theData += "Cumulus Cloud Base: " + format("%i", data.cloudbase) + " ft. (calculated) \n";
    theData += "Barometer: " + format("%.1f", data.pressure) + " mb " + format("%.2f", data.pressure * 0.02953) + " in. HG \n";
    theData += "Wind: " + data.wind.max + " " + data.wind.sampleTime + " sec sample " + data.wind.sampleCount + " data points \n";
    theData += "Battery: " + (data.voltage) + "v  WiFi: " + data.rssi + " db \n";
    theData += "\n";
    server.log(theData);
}


//Begin executing program

    // Operate in WiFi Power Save Mode
    
    imp.setpowersave(true);

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
    data.rssi = imp.rssi(); 
    agent.send("reading", data);
    //logData();
    
    // Deep Sleep
    imp.onidle(function() {
        server.sleepfor(sleepTime);
    });

    
    
