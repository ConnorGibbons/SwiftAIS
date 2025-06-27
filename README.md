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
* *-di* (Int) lets you choose the device index of your RTL-SDR, useful if multiple are present.

