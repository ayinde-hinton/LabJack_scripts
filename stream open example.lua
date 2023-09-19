local LJMError;
local handle;
LJMError = LJM_Open(LJM_dtT7, LJM_ctETHERNET, "ANY", &handle);
local err = 0;
local scanRate = 1000;
const int NUM_WRITES = 9;
enum { NUM_SCAN_ADDRESSES = 1 };
const char * scanList[NUM_SCAN_ADDRESSES] = { "STREAM_OUT0" };
int targetAddr = 1000; // DAC0
int streamOutIndex = 0;
int samplesToWrite = 512;

// Make an arbitrary waveform that increases voltage linearly from 0-2.5V
double * values = new double[samplesToWrite];
double increment = double(1) / samplesToWrite;
for (int i = 0; i < samplesToWrite; i++) {
    double sample = 2.5 * increment * i;
    values[i] = sample;
}

// Open first available LabJack device
err = LJM_Open(LJM_dtANY, LJM_ctANY, "LJM_idANY", &handle);
ErrorCheck(err, "LJM_Open");
PrintDeviceInfoFromHandle(handle);
ErrorCheck(err, "PrintDeviceInfoFromHandle");

err = LJM_InitializeAperiodicStreamOut(
    handle,
    streamOutIndex,
    targetAddr,
    scanRate
);
ErrorCheck(err, "LJM_InitializeAperiodicStreamOut");
printf("\n");
int queueVals;
// Write some values to the device buffer before starting the stream
err = LJM_WriteAperiodicStreamOut(
    handle,
    streamOutIndex,
    samplesToWrite,
    values,
    &queueVals
);
ErrorCheck(err, "LJM_WriteAperiodicStreamOut");

int scansPerRead = scanRate / 2;
int aScanList[NUM_SCAN_ADDRESSES];
int aTypes[NUM_SCAN_ADDRESSES];
int deviceScanBacklog;
int ljmScanBacklog;
err = LJM_NamesToAddresses(
    NUM_SCAN_ADDRESSES,
    scanList,
    aScanList,
    aTypes
);
ErrorCheck(err, "LJM_NamesToAddresses scan list");

int startTime = GetCurrentTimeMS();
err = LJM_eStreamStart(
    handle,
    scansPerRead,
    NUM_SCAN_ADDRESSES,
    aScanList,
    &scanRate
);
ErrorCheck(err, "LJM_eStreamStart");

for (int i = 0; i < NUM_WRITES; i++) {
    err = LJM_WriteAperiodicStreamOut(
        handle,
        streamOutIndex,
        samplesToWrite,
        values,
        &queueVals
    );
    ErrorCheck(err, "LJM_WriteAperiodicStreamOut in loop");
}

int runTime = GetCurrentTimeMS() - startTime;
// 512 samples * 10 writes = 5120 samples. scan rate = 1000
// samples/sec, so it should take 5.12 seconds to write all data out
int streamOutMS = 1000 * samplesToWrite * (NUM_WRITES + 2) / scanRate;
if (runTime < streamOutMS) {
    MillisecondSleep(streamOutMS - runTime);
}
err = LJM_eStreamStop(handle);
ErrorCheck(err, "Problem closing stream");
err = LJM_Close(handle);
ErrorCheck(err, "Problem closing device");

delete[] values;