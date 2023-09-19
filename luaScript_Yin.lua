-- digital i/o registers w/ 550 ohm source impedence
-- 0 = Low; 1 = High
local FIO0 = 2000
local FIO1 = 2001
local FIO2 = 2002
local FIO3 = 2003
local FIO4 = 2004
local FIO5 = 2005
local FIO7 = 2007

local pfet_wire = FIO0
local V_wire = AIN2
local max_d = 120  -- Don't change this
local p_term = false

-- User modifiable
local num_p = 10-- Number of pulses to log, each SMA wire counts as an individual pulse
local max_pw = 375 -- time in ms
local wait_t = 2000

-- Labjack Registers
local AIN0 = 0
local AIN2 = 4
local AIN4 = 8

-- clock registers
local CLOCK10KHZ = 61502 -- synched to RTC gives 0.1ms resolution
local RTC = 61510 -- record of current time

-- Configure inputs to use the faster resolution index and be differential measurements
MB.W(41500, 0 , 1) -- Resolution index of 1 (fastest; noisier)
MB.W(41502, 0 , 1) -- ??? Not in manual likely trying to do resolution things but I'm not sure 
MB.W(41504, 0 , 1) -- ???

MB.W(41002, 0, 3) -- negative channel; set up for differential reading
MB.W(41004, 0, 5) -- ???

-- Variables to hold measurements / calculated values
local V_array = {} -- Voltage for SMA1 or SMA2 whichever is being pulsed
local I_array = {} -- Current
local R_array = {}
local SW1_array = {}
local SW2_array = {}
local drdt_array = 0 -- 1st order approximation of resistance
local drdt_filt = {}
local ts = {}   -- Timestamp of the measurements
local RTC_dat = {} -- hold the data read from RTC
local ms_ts    -- Variable to hold the milliseconds read from 10KHZ counter
local me_prev  -- Variable to hold the previous milliseconds
local R = 0 -- Current resistance
local R_prev = 0
local R_prev2 = 0
local s_prev = 0
local sample_count = 0 -- Counter for samples

-- Local functions
local function clear()
  collectgarbage("collect")
  for i = 0, max_d do -- Intitalize all values in arrays. Prevents resizing of array during sampling
    V_array[i] = 0
    I_array[i] = 0
    R_array[i] = 0
    drdt_filt[i] = 0
    ts[i] = 0
    SW1_array[i] = 0
    SW2_array[i] = 0
  end
  collectgarbage("collect")
end 

-- Setup
RTC_dat = MB.RA(RTC, 0, 6) -- get time at start of run [yr, mth, day, hr, min, sec]
s_prev = RTC_dat[6] -- seconds at start of run
local Filename = "/"..string.format("%02d.%02d_%02d.%02d.%02d", RTC_dat[2], RTC_dat[3], RTC_dat[4], RTC_dat[5], RTC_dat[6]) .. "_swdet_resistance_data.csv"
-- makes file labled from month to second called switch detect resistance data
clear() -- removes lua: [string "-- User modifiable..."]:120.000000: attempt to perform arithmetic on field '?' (a nil value) from console and continues

--local file = io.open(Filename, "w") --opens the file we just made in a write mode indicated by "w" 
print("setup complete")

-- Mainloop
while num_p > 0 do
    -- Pre-pulse setup
    local ms_initial = MB.R(CLOCK10KHZ, 1)
	-- read the frequency as a 16 bit unsigned integer
    sample_count = 0 -- Reset sample count
    p_term = false
    LJ.IntervalConfig(0, max_pw)
	--set interval timer out of a possible 8 (0:7) with a 32 bit float that represents ms/interval

    MB.W(pfet_wire, 0, 0) -- turn on SMA wire
	-- write a 16 bit 0 = Low to the pfet_wire register DIO0 
    -- is this active low function???
    MB.W(FIO7, 0, 1) -- turn on LED
    -- Pulse loop
    while LJ.CheckInterval(0) == nil and not p_term do
        LJ.IntervalConfig(1, max_pw/max_d) -- Pulse interval
        V_array[sample_count] = MB.R(V_wire, 3) -- Read voltage
        I_array[sample_count] = (MB.R(AIN0, 3) - 0.4) * 0.909091 -- Read present voltage and calculate current
        SW1_array[sample_count] = MB.R(FIO2, 0)
        SW2_array[sample_count] = MB.R(FIO3, 0) 
        -- Timestamp
        ms_ts = MB.R(CLOCK10KHZ, 1) -- Read milliseconds
        RTC_dat = MB.RA(RTC, 0, 6) -- Read RTC
        -- ts[i] = string.format("%02d:%02d.%02d.%04d", RTCRead[4], RTCRead[5], RTCRead[6], msTs) -- Hour, minute, second, milliseconds
        if ms_ts > 9996 then -- Handles an issue where the seconds can increment after the ms has been read creating an error of about 1 second. 
          RTC_dat[6] = s_prev
        end
        ts[sample_count] = string.format("%02d.%04d", RTC_dat[6], ms_ts)

        -- Calculate resistance
        R = V_array[sample_count]/I_array[sample_count] -- Calculate resistance
        
        -- resistance 3 point rolling average
        if sample_count>1 then -- can't do rolling average without 2 previous points
            R_array[sample_count] = (R + R_prev + R_prev2)/3
        end
        
        if sample_count>2 then -- Can't do derivative approximation with 1 point
            local dt = ms_ts - me_prev
            if dt < 0 then -- If ms rolls over, dt will be negative and it needs to be corrected
              dt = dt + 10000
            end
            drdt_array = (R_array[sample_count] - R_array[sample_count-1]) / dt
            drdt_filt[sample_count] = .5*drdt_filt[sample_count-1] + .5*drdt_array
        end
        
        me_prev = ms_ts -- Swap values
        R_prev2 = R_prev
        R_prev = R
        s_prev = RTC_dat[6]
        
        -- Calculate time from start
        local delta_ms = ms_ts - ms_initial
        if delta_ms < 0 then -- if ms has rolled over, correct
          delta_ms = delta_ms + 10000
        end
        
        -- Pulse termination condition checking
        if SW1_array[sample_count] == 0 or SW2_array[sample_count] == 0 then
          p_term = true
        end
        
      
        sample_count = sample_count + 1
        while LJ.CheckInterval(1) == nil and not p_term do -- Wait until interval is up, but if p_term is true, skip waiting and exit
        end
    end
    MB.W(pfet_wire, 0, 1) -- Turn off SMA
	-- write a 16 bit 1 = High to the pfet_wire register DIO0 
    -- is this active low function??? seems that way
    MB.W(FIO7, 0, 0) -- turn off LED
    
    LJ.IntervalConfig(3, wait_t) -- time between pulses
	-- we might want to do a LJ.CheckInterval here 

    -- Write to file
    collectgarbage("collect") -- The file I/O uses a lot of memory, so free up dead objects before
    local file = io.open(Filename, "w") 
    file:write("Timestamp,Voltage,Current,ResistanceRollingAvg,drdtfilter,swdet1,swdet2\n") -- Column headers
    for j=0, max_d do
        local swdet = 0
        if SW1_array[j] == 0 or SW2_array[j] == 0 then
          swdet = 1
        end
        file:write(ts[j] .. ", " .. V_array[j] .. "," .. I_array[j] .. "," .. R_array[j] .. "," .. drdt_filt[j] .. "," .. SW1_array[j] .. "," .. SW2_array[j] .. "\n")
        collectgarbage("collect")
    end
    file:close()
	
    if pfet_wire == FIO0 then  -- Swap which SMA wire is being pulsed between pulses
        pfet_wire = FIO4
        V_wire = AIN4
    elseif pfet_wire == FIO4 then
        pfet_wire = FIO0
        V_wire = AIN2
	else 
		print("pfet wire error")
    end
    num_p = num_p - 1
    
    clear() -- Intitalize all values in arrays
    print("pulse written")
	while LJ.CheckInterval(3) == nil do -- Wait until time between pulses hits threshold (2 seconds)
    end
end
print("mainloop complete")
-- MB.writeName("LUA_RUN", 1, 1) -- End program
MB.W(6000, 1, 0) -- End Program, gets rid of truncation error we still have a modbus error that has gone from 2385 to 2, writing a zero clears memory

-- August 2023 Torque fixture script notes

--  MB.writeName causes a truncation warning when writing a 1 to LUA_RUN; used MB.W instead
--  still gives us a modbus error but its error code 2 instead of error code 2385 
--  added in some debugging print statements; feel free to comment out the setup complete; file written; and mainloop complete lines at any time
-- Try to keep notes elsewhere b/c there isn't much space on the labjack for storing scripts

-- reading through the confluence page for the fixture found that the Derivative threshold and Percent change thresholds are not defined
-- MB.W(address, datatype, value)
