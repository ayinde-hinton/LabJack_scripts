-- FIO_swtich_triggering
local FIO0 = 2000
local FIO1 = 2001
local FIO2 = 2002
local FIO3 = 2003
local FIO4 = 2004
local FIO7 = 2007

local AIN0 = 0
local AIN2 = 4
local AIN4 = 8
-- clock registers
local CLOCK10KHZ = 61502 -- synched to RTC gives 0.1ms resolution

-- Configure inputs to use the faster resolution index and be differential measurements
-- MB.W(41500, 0 , 1) -- Resolution index of 1 (fastest; noisier) for analog in 0
-- MB.W(41502, 0 , 1) -- Resolution index of 1 (fastest; noisier) for analog in 2
-- MB.W(41504, 0 , 1) -- Resolution index of 1 (fastest; noisier) for analog in 4
MB.W(41500, 0 , 2) -- Resolution index of 1 (fastest; noisier) for analog in 0
MB.W(41502, 0 , 2) -- Resolution index of 1 (fastest; noisier) for analog in 2
MB.W(41504, 0 , 2) -- Resolution index of 1 (fastest; noisier) for analog in 4

MB.W(41002, 0, 3) -- negative channel; set up for differential reading; AIN3 neg of AIN2
MB.W(41004, 0, 5) -- negative channel; set up for differential reading; AIN5 neg of AIN4

local p_term = false
local pfet_wire = FIO0
local max_d = 120  -- Don't change this
local max_pw = 375

local num_p = 8

-- Variables to hold measurements / calculated values
local V_array = {} -- Voltage for SMA1 or SMA2 whichever is being pulsed
local I_array = {} -- Current
local R_array = {}
local drdt_filt = {}
local ts = {}   -- Timestamp of the measurements
local SW1_array = {}
local SW2_array = {}
--local drdt_array = 0 -- 1st order approximation of resistance
local RTC_dat = {} -- hold the data read from RTC
local ms_ts = 0    -- Variable to hold the milliseconds read from 10KHZ counterr
local ms_prev = 0
local s_prev = 0
local sample_count = 0 -- Counter for samples
local R = 0 -- Current resistance
local R_prev = 0
local R_prev2 = 0

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

RTC_dat = MB.RA(61510, 0, 6) -- get time at start of run [yr, mth, day, hr, min, sec]
s_prev = RTC_dat[6] -- seconds at start of run
local Filename = "/"..string.format("%02d.%02d_%02d.%02d.%02d", RTC_dat[2], RTC_dat[3], RTC_dat[4], RTC_dat[5], RTC_dat[6]) .. "_swdet_resistance_data.csv"
-- makes file labled from month to second called switch detect resistance data
clear()

print("setup complete")

while num_p > 0 do
	-- pre_pulse set up
    LJ.IntervalConfig(0, max_pw) -- max pulse width
	LJ.IntervalConfig(1, max_pw/max_d) -- Pulse interval
	LJ.IntervalConfig(2, 2000) -- time between pulses
	
	pterm = false
	sample_count = 5
	local  ms_initial = MB.R(CLOCK10KHZ, 1)

	-- Wire Drive
    MB.W(pfet_wire, 0, 0) -- turn on SMA wire
    -- this is active low because that's how FETs work
    MB.W(FIO7, 0, 1) -- turn on LED


	while LJ.CheckInterval(0) == nil and not p_term do
        
        V_array[sample_count] = MB.R(AIN2, 3) -- Read voltage
        I_array[sample_count] = (MB.R(AIN0, 3) - 0.4) * 0.909091 -- Read present voltage and calculate current
        -- how do i get these to fill with not zeros???
        SW1_array[sample_count] = MB.R(FIO2, 0)
        SW2_array[sample_count] = MB.R(FIO3, 0)
		
        -- Timestamp
        ms_ts = MB.R(CLOCK10KHZ, 1) -- Read milliseconds
        RTC_dat = MB.RA(61510, 0, 6) -- Read RTC
        if ms_ts > 9996 then -- Handles an issue where the seconds can increment after the ms has been read creating an error of about 1 second. 
          RTC_dat[6] = s_prev
        end
		ts[sample_count] = string.format("%02d.%04d", RTC_dat[6], ms_ts)
		R = V_array[sample_count]/I_array[sample_count]
		
        -- resistance 3 point rolling average
        if sample_count>1 then -- can't do rolling average without 2 previous points
            R_array[sample_count] = (R + R_prev + R_prev2)/3
        end

        if sample_count>2 then -- Can't do derivative approximation with 1 point
            local dt = ms_ts - ms_prev
            if dt < 0 then -- If ms rolls over, dt will be negative and it needs to be corrected
              dt = dt + 10000
            end
            drdt_array = (R_array[sample_count] - R_array[sample_count-1]) / dt
            drdt_filt[sample_count] = .5*drdt_filt[sample_count-1] + .5*drdt_array
        end
        
		-- Calculate time from start
        local delta_ms = ms_ts - ms_initial
        if delta_ms < 0 then -- if ms has rolled over, correct
          delta_ms = delta_ms + 10000
        end
		
		-- Pulse termination condition checking
        -- ERROR: Causes Pulse not to trigger, need a better understanding of what the goal here is
		--if SW1_array[sample_count] == 0 or SW2_array[sample_count] == 0 then
    --      p_term = true
    --    end
        
    print(SW1_array[1])
     
		-- Housekeeping
		ms_prev = ms_ts
        R_prev = R
		R_prev2 = R_prev
        s_prev = RTC_dat[6]
		sample_count = sample_count + 1
		
	
		
		while LJ.CheckInterval(1) == nil and not p_term do
		end
    end
	
	-- Write to file
	-- CONCERN: this process is messing with the timing of wire drive
  --  collectgarbage("collect") -- The file I/O uses a lot of memory, so free up dead objects before
  --  local file = io.open(Filename, "w") 
  --  file:write("Timestamp,Voltage,Current,ResistanceRollingAvg,drdtfilter,swdet1,swdet2\n") -- Column headers
  --  for j=0, max_d do
  --      local swdet = 0
  --      if SW1_array[j] == 0 or SW2_array[j] == 0 then
  --        swdet = 1
  --      end
  --      file:write(ts[j] .. ", " .. V_array[j] .. "," .. I_array[j] .. "," .. R_array[j] .. "," .. drdt_filt[j] .. "," .. SW1_array[j] .. "," .. SW2_array[j] .. "\n")
  --      collectgarbage("collect")
  --  end
  --  file:close()
	
	-- Wire Drive
    MB.W(pfet_wire, 0, 1) -- Turn off SMA
	-- write a 16 bit 1 = High to the pfet_wire register DIO0 
    -- is this active low function??? seems that way
    MB.W(FIO7, 0, 0) -- turn off LED
    
    
    if pfet_wire == FIO0 then  -- Swap which SMA wire is being pulsed between pulses
        pfet_wire = FIO4
		V_wire = AIN4
    elseif pfet_wire == FIO4 then
        pfet_wire = FIO0
		V_wire = AIN2
	  else 
		print ("pfet wire error")
    end    
	  num_p = num_p - 1
    clear() -- Intitalize all values in arrays
    while LJ.CheckInterval(2) == nil do -- Wait until time between pulses hits threshold (2 seconds)
    end
    print("pulse complete")
end
print("mainloop complete")
MB.W(6000, 1, 0)
