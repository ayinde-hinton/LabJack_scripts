MB.W(60601, 0, 1) -- write an unsigned 16 bit 1 to FILE_IO_DIR_CURRENT to load current working directory
local numBytesInPath = MB.R(60642, 0) -- read FILE_IO_PATH_READ_LEN_BYTES
local path = MB.RA(60652, 99, numBytesInPath)
print(path)
--
Stream Trigger Index register add to normal Stream
MB.W(4024, 1 , 2)
local Handle = LJM_Open(7, 3, "ANY")
LJM_eStreamStart(Handle, Scansperread, numaddresses, aScanList, ScanRate)
LJM_eStreamStart(Handle, 50000, 2, 12:14, 100000)







