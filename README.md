# SwiftAIS

**SwiftAIS** lets you turn your Mac into a mobile AIS receiver using cheap, simple hardware! Utilizing an RTL-SDR, this software will demodulate AIS signals from vessels within range and output them as NMEA 0183 sentences. These sentences can be plugged into AIS decoders to reveal what information a vessel is broadcasting.

## Example Output

Here's an example NMEA sentence captured in Scituate, MA:
```
!AIVDM,1,1,,A,E>k`HC0VTah9QTb:Pb2h0ab0P00=N97j<4dDP00000<020,4*6C
```

And here's the output when decoded on https://ccgibbons.com/ais:

<img width="300" alt="AIS decoder output" src="https://github.com/user-attachments/assets/d9456ba9-6bcc-41e7-8e6a-a0adc0aa89f7" />

*(This site is a work in progress! Some rarer message types can cause errors when displaying output. If you find one, let me know! connor@ccgibbons.com)*

## Requirements
- An ARM-based Mac running macOS 15 or newer *-- CI builds for macOS 13+. However any version <15 (and Intel macs) are untested.*
- [Xcode Command Line Tools](https://developer.apple.com/xcode/resources/)
- RTL-SDR & an antenna (antennas designed for the VHF range are ideal, but not strictly required)
- Be located near marine activity (Reception range limited by VHF propagation. Inland users are likely out of range.)

## Quick Start
Run:
```
curl -L -o SwiftAIS.zip \
  https://github.com/ConnorGibbons/SwiftAIS/releases/download/1.0.0/SwiftAIS.zip
  unzip SwiftAIS.zip
  cd SwiftAIS
```
Then, if you have an RTL-SDR connected via USB:
```
./SwiftAIS -n
```
Alternatively, if you have a device running rtl\_tcp:
```
./SwiftAIS -n -di <IP>:<Port>
```
To run an offline decoding on the included sample file, run:
```
./SwiftAIS -ot Samples/sample_161992000Hz_96000Hz.wav 161992000 96000 -n
```
You should see:
```
!AIVDM,1,1,,A,B52icIh00Ng42sV2Gf7Q3wtQnDiJ,0*5F
!AIVDM,1,1,,A,H52k1?ALPU@F0<520TT00000000,2*3B
!AIVDM,1,1,,A,B52d3RP00>g41U62GVwQ3wuQnDEr,0*71
!AIVDM,1,1,,B,E>k`HC0VTah9QTb:Pb2h0ab0P00=N97j<4dDP00000<020,4*6F
!AIVDM,1,1,,B,H52d3RTUCBD9qtr000000018413t,0*1E
!AIVDM,1,1,,B,B52ndgh006g3owV2G=SQ3whQjFjJ,0*72
```
Along with output about the time it took to prepare & process the data.
On an M2 Macbook Air, the times are 709.678333 and 349.079542 ms respectively. 

## Launch Arguments

| Argument | Description |
|----------|-------------|
| `-h` | Shows help message containing argument info. |
| `-d [Directory Path]` | Enables extra output for debugging (demodulation time, errors, etc.) Saves a .aisDebug file to specified directory for each failed demod attempt.|
| `-ot [File Path, Int, Int]` | Runs the demodulator on a prerecorded .wav file (must be in 16-bit interleaved IQ format). First argument is file path, then center frequency of recording, then sample rate. |
| `-n` | Prints valid NMEA packets to the console when received |
| `-agc` | Enables Automatic Gain Control on the RTL-SDR |
| `-b [Int]` | Controls the bandwidth of the RTL-SDR |
| `-di [Int/IP:Port]` | Choose device index of your RTL-SDR (useful if multiple are present). If IP:Port is entered, SwiftAIS will connect to an rtl_tcp server. Example: `-di 127.0.0.1:1234` |
| `-tcp [Int]` | Makes SwiftAIS act as a TCP server, broadcasting NMEA 0183 packets. Enter port (1-65535). Example: `-tcp 50100` |
| `-ec [Int]` | Enables error correction up to a defined number of bits. Max allowed is 3. This is experimental, it can cause false corrections. |
| `-s [File Path]` | Saves NMEA 0183 output text to a specified file. |

## Offline Decoding
SwiftAIS can take in .wav files for decoding offline. This allows for use with old captures & without an SDR. Use the `-ot` argument, with subsequent arguments as follows:

### File Path
A path (absolute or relative) to the .wav file for input. Note that it **must** be in 16-bit interleaved raw IQ format to be processed. Audio recordings from SDR frontends will not work. SDR frontends will refer to this as recording 'baseband' or raw IQ. 

### Center Frequency (Hz)
The frequency that was tuned to during the recording, in Hz. If recorded with an SDR frontend like SDR++, this should be in the filename. Ex. 'baseband_161665000Hz_16-03-37_31-05-2025.wav'

### Sample Rate (Hz)
The sample rate of the recording. On macOS, you can right click the recording in finder, click 'Get Info', and see the sample rate listed in kHz. 1 kHz = 1000 Hz. Important note: the sample rate must be an integer multiple of 48,000 Hz. (96,000; 240,000; etc.)


### Example:
`SwiftAIS -ot '/Users/connorgibbons/recordings/baseband_161665000Hz_16-03-37_31-05-2025.wav' 161665000 240000`


## Features

### Older macOS Support (✓/✗)
Working on supporting older versions back to High Sierra and Intel Macs.
- **Update:** SwiftAIS builds on macOS 13 via GitHub Actions. In theory should build on macOS 10.15, but I currently do not have a means of testing this. If you are able to test this, or encounter problems, please email me using the contact below.

### Decoder/Visualizer (✗)
Future plans include a Swift-based decoder and live ship visualizer for the NMEA output.

### Multi-Sentence Messages (✓)
Some AIS messages are too long for the NMEA 0183 82-character maximum and need to be split across multiple sentences. SwiftAIS has been updated to split long messages and assign them sequence IDs. 

### Error Correction (✓)
Many factors (noise, distance, etc.) can cause errors while receiving the packet. When they occur, they are detected by the failure of a CRC (Cyclic Redundancy Check). SwiftAIS will not output messages 
with an incorrect CRC value. With the -ec <Int> launch argument, SwiftAIS will use a heuristic to attempt recovering a packet by flipping most-likely candidate bits and re-evaluating the CRC. During limited testing, this feature *is* able to recover packets, but it should be noted that false corrections are unlikely yet possible. AIS CRCs are only 16 bits long, and there are many inputs that could produce an identical CRC value -- therefore this method is capable of finding incorrect flips that still produce a "valid" seeming packet. Typically it is very clear if this occured, as the position reported could be far out of feasible range. This feature is **experimental**. 

### Networking (✓)
SwiftAIS now has support for networking with regards to both input and output. TCP-based input allows you to specify an IP and Port of a device running rtl\_tcp, and recieve samples remotely. SwiftAIS can also act as a TCP server, outputting NMEA 0183 sentences on a desired port. This allows for connecting chartplotters such as OpenCPN to display captured AIS data live. 

## Contact

If you have any issues or suggestions, please reach out: connor@ccgibbons.com

## Important Notice

**Testing for this tool is limited and it is not certified by any official bodies. It should not be relied upon as a navigational aid or safety tool. SwiftAIS is created for hobbyist/educational use only.**
