**SwiftAIS** lets you turn your Mac into a mobile AIS receiver using cheap, simple hardware! Utilizing an RTL-SDR, this software will demodulate AIS signals from vessels within range, 
and output them as NMEA 0183 sentences. These sentences can be plugged into AIS decoders to reveal what information a vessel is broadcasting.

Here's an example NMEA sentence captured in Scituate, MA: !AIVDM,1,1,,A,E>k`HC0VTah9QTb:Pb2h0ab0P00=N97j<4dDP00000<020,4*6C

And here's the output when decoded on https://ccgibbons.com/ais

<img width="300" alt="image" src="https://github.com/user-attachments/assets/d9456ba9-6bcc-41e7-8e6a-a0adc0aa89f7" />

(This site is a work in progress! Certain less common message types can cause it to crash. If you find one, let me know! connor@ccgibbons.com)




**You'll need:**
* An ARM-based Mac running macOS 15 or newer (subject to change -- hoping to add support for Intel & older macOS versions soon!)
* Xcode Command Line Tools (https://developer.apple.com/xcode/resources/)
* RTL-SDR & an antenna. Antennas designed for the VHF range are ideal, but not strictly required.
* Be located near marine activity. Unfortunately, reception will be too weak (likely nonexistent) if not in a coastal area.

**To run:**
* Navigate to the directory in Terminal, run 'swift build'.
* Navigate to /.build/debug and run './SwiftAIS (args)'

**Launch Arguments:**
* *-d* enables extra output for debugging (demodulation time, errors, etc.)
* *-ot* will run the demodulator on a prerecorded .wav file, provided it is in 16-bit interleaved IQ format. You can modify the file path & behavior in the OfflineTesting.swift file.
* *-n* will print valid NMEA packets to the console when received.
* *-agc* will enable Automatic Gain Control on the RTL-SDR. I have not had the opportunity to test whether this positively impacts the reception process yet.
* *-b* (Int) controls the bandwith of the RTL-SDR. 
* *-di* (Int / IP:Port) lets you choose the device index of your RTL-SDR, useful if multiple are present. If an IP address / port combo is entered instead, SwiftAIS will try to establish a connection to an rtl_tcp server. Ex. -di 127.0.0.1:1234
* *-tcp* (Int) lets SwiftAIS act as a TCP server, broadcasting each successfully received sentence as NMEA 0183 packets. Enter a port (1-65535) as an argument. Ex. -tcp 50100
* *-ec* (Int) enables error correction up to a defined number of bits. Setting this value too high (the current maximum allowed is 15, for experimentation) will likely result in slow decoding or crashes. Additionally, it will potentially find combinations of flips that result in a 'correct' CRC even if it doesn't reflect what was actually sent. If enabled, it's ideal to keep it <3 bits.


**Planned Changes / Features**
* Multi-Sentence Messages: Some AIS messages are too long to fit within the NMEA 0183 82-character maximum, so they need to be split across multiple sentences. I have not had the opportunity to test with one of these messages yet, but it will almost certainly be output as one long NMEA sentence (technically invalid, though some decoders might handle it regardless) until logic is in place to handle this.
* ~~Error Correction: I'll (hopefully soon) be adding a togglable feature that will attempt to correct weak signals by flipping most likely candidates for errored bits.~~
    - Update: This is implemented, but untested. I am hoping to run a real-world test on this soon.
* Older macOS Support: Currently this is utilizing features of Apple's Accelerate library that require macOS 15, though there are equivalent functions that will work on older versions. I'd like to support versions going back to High Sierra (and Intel Macs) so that older laptops can be used as receiving stations.
    - Update: Not fully done with this, but SwiftAIS **should** run on 10.15 (Catalina) on Intel macs.
* ~~Networking: An option to send received packets over TCP connections.~~
    - Update: This is implemented! Try adding SwiftAIS as a connection in OpenCPN to visualize your captured data!
* Decoder / Visualizer: At some point I will work on a Swift-based decoder & live ship visualizer for the NMEA output.

If you have any issues / suggestions, please reach out! connor@ccgibbons.com 

**Important Note**
Testing for this tool is limited, and is not certified by any official bodies. It should not be relied upon as a navigational aid or saftey tool. SwiftAIS is created for hobbyist/educational use.
