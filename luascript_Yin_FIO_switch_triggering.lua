-- FIO_swtich_triggering
local FIO0 = 2000
local FIO1 = 2001
local FIO4 = 2004
local FIO7 = 2007

local p_term = false
local pfet_wire = FIO0

local num_p = 10
while num_p > 0 do
	-- Wire Drive
    MB.W(pfet_wire, 0, 0) -- turn on SMA wire
    -- this is active low because that's how FETs work
    MB.W(FIO7, 0, 1) -- turn on LED
    -- Pulse loop
	-- lua doesn't have a wait statement built in so i either have to use an OS wait; not desireable
	-- or leverage check interval which doesn't seem to work for this simple test
    LJ.IntervalConfig(0, 375)
	while LJ.CheckInterval(0) == nil and not p_term do

    end
	-- Wire Drive
    MB.W(pfet_wire, 0, 1) -- Turn off SMA
	-- write a 16 bit 1 = High to the pfet_wire register DIO0 
    -- is this active low function??? seems that way
    MB.W(FIO7, 0, 0) -- turn off LED
    
    LJ.IntervalConfig(3, 2000) -- time between pulses
    if pfet_wire == FIO0 then  -- Swap which SMA wire is being pulsed between pulses
        pfet_wire = FIO4
    elseif pfet_wire == FIO4 then
        pfet_wire = FIO0
	  else 
		print ("pfet wire error")
    end    
	  num_p = num_p - 1
    --clear() -- Intitalize all values in arrays
    print("pulse complete")
    while LJ.CheckInterval(3) == nil do -- Wait until time between pulses hits threshold (2 seconds)
    end
    
end
print("mainloop complete")
MB.W(6000, 1, 0)
