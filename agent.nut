// WxImp Agent Code
// Version 0.9.3
// Copyright 2017 - Richard Milewski
// Released under the Mozilla Public License v2.0
// https://www.mozilla.org/en-US/MPL/2.0/
// 
//

minVoltage <- 3.25;   // Voltage at which battery check notice appears

wind <- {};
wind.current <- 0;
wind.adjusted <- 0;
wind.fiveMin <- null;
wind.oneHour <- null;
wind.twelveHour <- null;
wind.oneDay <- null;
wind.weighted <- 0;
wind.history <- [];
wind.history.push(0);

gust <- {}; 
gust.fiveMin <- null;
gust.oneHour <- null;
gust.twelveHour <- null;
gust.oneDay <- null;

temp <- {};
temp.min <- null;
temp.max <- null;
temp.timespan <- (24 * 60);       // Time in minutes over which temperature highs and lows are reported
temp.history <- [];
temp.history.push(0);

pressure <- {};
pressure.history <- [];
pressure.history.push(0);
pressure.timespan <- (60);     // Time in minutes over which to measure pressure changes to determine trend.
pressure.delta <- 0.2;        // Minimum pressure difference in millibars to determine trend.

humidity <- {};
humidity.dewpoint <- null;
humidity.cloudbase <- null;
humidity.history <- [];
humidity.history.push(0);

timeStamps <- [];
timeStamps.push(time());

historySpan <- 0;

refresh <- 10;
lastRefresh <- time();


month   <- ["January ","February ","March ","April ","May ","June ","July ","August ","September ","October ","November ","December "];
weekday <- ["Sunday, ", "Monday, ","Tuesday, ","Wednesday, ","Thursday, ","Friday, ","Saturday, "];

// HTML output
html <- null;

html_head1 <- @"<html>
<head>
	<meta charset='utf-8'>
	<meta name='viewport' content='width=device-width, initial-scale=1'>"
	
	
html_head2 <- @"<title>Weather Imp</title>
	<link rel='stylesheet' href='https://code.jquery.com/mobile/1.4.5/jquery.mobile-1.4.5.min.css' />
    <script src='https://code.jquery.com/jquery-1.11.1.min.js'></script>
    <script src='https://code.jquery.com/mobile/1.4.5/jquery.mobile-1.4.5.min.js'></script>
    <style>
        .ui-header { 
	        font-size: 1.2em;
        }
	   
	    .ui-header p {
	        margin-top: 0;
	        padding-top: 0;
	    }
        
        img {
        	margin: 0 auto;
        }
        
        .center {
        	text-align: center;
        }
        
        .cropbox {
            margin: 0 auto;
            width: 49px;
            height: 50 px;
            overflow: hidden;
        }
        
        p {
            line-height: 1.1;
        }
    </style>
</head>";

html_body1 <- @"<body>
<div data-role='page'>
	<div data-role='header' class='center'>
		<img src='https://electricimp.com/public/img/logomobile.png'>
		<p>Weather Imp</p>
	</div><!-- /header -->
	<div role='main' class='ui-content center'>"
    
html_body2 <- @"</div><!-- /content -->

	<div data-role='footer'>
	    <div class='cropbox'>
	        <img src='https://electricimp.com/public/img/logomobile.png'>
	   </div>
	</div><!-- /footer -->

</div><!-- /page -->

</body>
</html>";


function Fahrenheit(TempC) {
    return TempC * 1.8 + 32;
}

function Kelvin(TempC) {
    return TempC + 273;
}


// Dewpoint calculation from https://cals.arizona.edu/azmet/dewpoint.html
function dewpoint(T, RH) {      
     local B = (math.log(RH / 100) + ((17.27 * T) / (237.3 + T))) / 17.27;
     return (237.3 * B) / (1 - B);
}

// Cloudbase calculation from https://en.wikipedia.org/wiki/Cloud_base
function cloudbase (T, DP) {
    return(format("%i", (400 * (T - DP))));
}


// ...a hack to selectively log stuff.
function logPerhaps(logstring, caller) {
    if (logThis.find(caller) != null) {
        server.log(logString);
    }
}

//Function to find the start of history samples for a given time span in minutes.
function historyStart(span, caller) {
    local now = time();
    historySpan = now - timeStamps[1];
    if (historySpan < (span * 60)) {
        return (0);  // Not enough history
    } else {
        local i = timeStamps.len() - 1;
        while ((now - timeStamps[i]) < (span * 60)) {
            i--;
        }
        return(i);
    }
}

//Function to return average wind data for a given time span in minutes.
function windAvg(span) {
    local start = historyStart(span, "windAvG");
    local count = timeStamps.len() - start; 
    // server.log("windAvg Debug - span: " + span + " start: " + start + " count: " + count);
    
    if (start) {
        local proxy = wind.history.slice(start);
        local sum = proxy.reduce(function(prev,current){
            return (prev + current);
        });
        return (sum/count);
    } else {
        return ("Not enough history.") ;
    }
}

//Function to return peak wind data for a given time span in minutes.
function windGust(span) {
    local start = historyStart(span, "windGust");
    local count = timeStamps.len() - start; 
    // server.log("windGust Debug - span: " + span + " start: " + start + " count: " + count);
    if (start) {
        local proxy = wind.history.slice(start);
        local gust = proxy.reduce(function(prev,current){
            if (prev > current) {
                return (prev);
          } else {
              return (current);
            }
        });
        return ("/" + gust);
    } else {
        return ("");
    }
}

//Function to return mininimum temperature for a time span in minutes
function minTemp(span) {
    local start = historyStart(span, "minTemp");
    local count = timeStamps.len() - start; 
    // server.log("minTemp Debug - span: " + span + " start: " + start + " count: " + count);
    if (start) {
        local proxy = temp.history.slice(start);
        local theTemp = proxy.reduce(function(prev,current){
            if (prev > current) {
                return (current);
          } else {
              return (prev);
            }
        });
        return (theTemp.tofloat());
    } else {
        return ("Not enough History");
    }
}

//Function to return maximum temperature for a time span in minutes
function maxTemp(span) {
    local start = historyStart(span, "maxTemp");
    local count = timeStamps.len() - start; 
    // server.log("manTemp Debug - span: " + span + " start: " + start + " count: " + count);
    if (start) {
        local proxy = temp.history.slice(start);
        local theTemp = proxy.reduce(function(prev,current){
            if (prev > current) {
                return (prev);
          } else {
              return (current);
            }
        });
        return (theTemp.tofloat());
    } else {
        return ("Not enough History");
    }
}


//Function to determine the trend of the barometric pressure.
function pressureTrend(currentPressure) {
    local start = historyStart(pressure.timespan, "pressureTrend");
    local count = pressure.history.len(); 
    // server.log("******** Pressure Debug - time: " + pressure.timespan + " start: " + start + " count: " + count);
    if (start) {
        local pastPressure = pressure.history[start];
        // server.log("******** Pressure Debug - past: " + pastPressure + " current: " + currentPressure + " delta: " + pressure.delta);
        if ((pastPressure - pressure.delta) > currentPressure) { return(" falling."); }
        if ((pastPressure + pressure.delta) < currentPressure) { return(" rising.");  } 
        return "steady";
    } else {
        return ("");
    }
}


// Function to handle imp explorer built-in sensor data and build html string

function manageReading(data) {
 
    server.log("Imp Explorer Sensors Read");
    timeStamps.push(time());   // We do the timestamp here because wind events precede other data events in the device code.
   
    temp.history.push(data.temp);
    humidity.history.push(data.humidity);
    pressure.history.push(data.pressure);
    
    wind.current = data.wind.max;
    wind.history.push(wind.current);
    wind.fiveMin = windAvg(5);
    gust.fiveMin = windGust(5);
    wind.oneHour = windAvg(60);
    gust.oneHour = windGust(60);
    wind.twelveHour = windAvg(12*60);
    gust.twelveHour = windGust(12*60);
    wind.oneDay = windAvg(24*60);
    gust.oneDay = windGust(24*60);

    
    //server.log("temp.timespan: " + temp.timespan + " historyStart: " + historyStart(temp.timespan) + " timeStamps.len(): " + timeStamps.len() + " History Span: " + historySpan);
    
    temp.max = maxTemp(temp.timespan);   
    temp.min = minTemp(temp.timespan);  
    
    humidity.dewpoint = dewpoint(data.temp, data.humidity);
    humidity.cloudbase = cloudbase(data.temp, humidity.dewpoint);
    local now = date();
    

    refresh = (time() - lastRefresh);
    lastRefresh = time();
   
    // Create HTML strings
    local metatag = "<meta http-equiv='refresh' content='"+ refresh + "' >";
    
    local dataDiv =  "<p><b>" + data.stationName + "</b></p>";
          dataDiv += "<p><b>Temperature: </b> " + format("%.1f", data.temp) + "&deg;C &nbsp; " + format("%.1f", Fahrenheit(data.temp)) + "&deg;F </p>";
          // dataDiv += "<p><b>Temperature 2: </b> " + format("%.1f", data.temp2) + "&deg;C &nbsp; " + format("%.1f", Fahrenheit(data.temp2)) + "&deg;F </p>";
         
          if (historySpan > (temp.timespan * 60)) { 
              dataDiv += "<p><b>" + (temp.timespan / 60) + "-Hour Temperature Range: </b>" + format("%.1f", temp.min) + " | " + format("%.1f", temp.max) + "&deg;C &nbsp; ";
              dataDiv += format("%.1f", Fahrenheit(temp.min)) + " | " + format("%.1f", Fahrenheit(temp.max)) + "&deg;F </p>";
          }
          dataDiv += "<p><b>Humidity: </b> "    + format("%.1f", data.humidity) + "%</p>";
          dataDiv += "<p><b>Dew Point: </b> "   + format("%.1f", humidity.dewpoint) + "&deg;C &nbsp; " + format("%.1f", Fahrenheit(humidity.dewpoint)) + "&deg;F </p>";
          dataDiv += "<p><b>Cumulus Cloudbase: </b> " + humidity.cloudbase + " feet. (calculated) </p>";
          dataDiv += "<p><b>Pressure: </b> "    + format("%.1f", data.pressure) + " mb  - " + format("%.2f", data.pressure * 0.02953) + " inches Hg </p>";
        //  dataDiv += "<p><b>Pressure (MSL): </b> "    + format("%.1f", data.mslPressure) + " mb  - " + format("%.2f", data.mslPressure * 0.02953) + " inches Hg " + pressureTrend(data.pressure) + "</p>";
          dataDiv += "<p class='centered'><b>Experimental wind data is, as yet, uncalibrated.</b></p>";
          dataDiv += "<p><b>Wind: </b>" + wind.current + "</p>";
          dataDiv += "<p><b>Wind avg/gust: </b> 5 min: " + wind.fiveMin + gust.fiveMin + " - 1 Hour: " + wind.oneHour + gust.oneHour + " </p>"; 
          dataDiv += "<p><b>Wind avg/gust: </b> 12 Hour: " + wind.twelveHour + gust.twelveHour + " - 24 Hour: " + wind.oneDay + gust.oneDay + " </p>";
          dataDiv += "<p><b>Battery: </b> " + format("%.2f", data.voltage) + " volts ";
          if (data.voltage < minVoltage) { dataDiv += "<b> CHECK BATTERIES ! </b>" };
          dataDiv += "</p>";
          dataDiv += "<p><b>" + data.ssid + " WiFi Signal Strength: </b> " + data.rssi + " db </p>";
          dataDiv += "<p><b>Sampled at: </b>" + format("%02u",now.hour) + ":" + format("%02u",now.min) + ":" + format("%02u",now.sec) + " UTC ";
          dataDiv += weekday[now.wday] + " " + month[now.month] + now.day + ", " + now.year + "</p>";  
          dataDiv += "<p>This page refreshes after " +refresh + " seconds.</p>";   
          
    html = html_head1 + metatag + html_head2 + html_body1 + dataDiv + html_body2;
    
    local dataLog = "\n";
    dataLog += data.stationName + "\n";
    dataLog += "Time:  " + format("%05d", historySpan) + " sec. " + timeStamps.len() + " timestamps\n";
    dataLog += "Wind:  " + format("%03d", wind.current) + "        " + wind.history.len() + " samples\n";
    dataLog += "Temp:  " + format("%.2f", data.temp) + "°C    " + temp.history.len() + " samples\n";
    dataLog += "Temp2: " + format("%.2f", data.temp2) + "°C    " + temp.history.len() + " samples\n";
    dataLog += "RH:    " + format("%.1f", data.humidity) + "%      " + humidity.history.len() + " samples\n";
    dataLog += "Baro:  " + format("%.1f", data.pressure) + " mb  " + pressure.history.len() + " samples\n";
    dataLog += "MSLP:  " + format("%.1f", data.mslPressure) + " mb \n";
    dataLog += "Vin:   " + format("%.2f", data.voltage) + " volts.\n";
    dataLog += "SSID:  " + data.ssid + "\n";
    dataLog += "RSSI:  " + data.rssi + " db\n";
    dataLog += "Cycle:  " + format("%2d", refresh) + " seconds\n";
    dataLog += "Memory: " + format("%03d", (imp.getmemoryfree() / 1024)) + " K free.\n";
    //dataLog += "1 hour avg/gust: " + wind.oneHour + gust.oneHour + "\n";
    //dataLog += "12 hour avg/gust: " + wind.twelveHour + gust.twelveHour + " ";
    //dataLog += "24 hour avg/gust: " + wind.oneDay + gust.oneDay + "\n";
    dataLog += "\n";
   
   server.log(dataLog);
}

function webServer(request, response) {
    // Serve up the HTML page with the weather data
    response.send(200, html);
}

// Register the function to handle requests from a web browser
http.onrequest(webServer);

// Register the function to handle data messages from the device
device.on("reading", manageReading);

