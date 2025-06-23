//
//  Filter.swift
//  RTLSDRTesting
//
//  Created by Connor Gibbons  on 4/21/25.
//
import Accelerate

protocol Filter {
    func filteredSignal( _ input: inout [Float])
    func filteredSignal(_ input: inout [DSPComplex])
}

// Class representing cascading biquad IIR filter
class IIRFilter: Filter {
    var params: [FilterParameter]
    var biquad: vDSP.Biquad<Float>?
    
    init() {
        params = []
    }
    
    func addCustomParams(_ params: [FilterParameter]) -> IIRFilter {
        self.params.append(contentsOf: params)
        biquad = nil
        return self
    }
    
    func addLowpassFilter(sampleRate: Int, frequency: Double, q: Double) -> IIRFilter {
        params.append(LowPassFilterParameter(sampleRate: Double(sampleRate), frequency: frequency, q: q))
        biquad = nil
        return self
    }
    
    func addHighpassFilter(sampleRate: Int, frequency: Double, q: Double) -> IIRFilter {
        params.append(HighPassFilterParameter(sampleRate: Double(sampleRate), frequency: frequency, q: q))
        biquad = nil
        return self
    }
    
    func filteredSignal(_ input: inout [Float]) {
        if biquad == nil {
            initBiquad()
        }
        biquad!.apply(input: input, output: &input)
    }
    
    func filteredSignal(_ input: inout [DSPComplex]) {
        if biquad == nil {
            initBiquad()
        }
        var real = [Float].init(repeating: 0.0, count: input.count)
        var imag = [Float].init(repeating: 0.0, count: input.count)
        real.withUnsafeMutableBufferPointer { r in
            imag.withUnsafeMutableBufferPointer { i in
                var splitComplex = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                vDSP.convert(interleavedComplexVector: input, toSplitComplexVector: &splitComplex)
            }
        }
        
        biquad!.apply(input: real, output: &real)
        biquad!.apply(input: imag, output: &imag)
        
        real.withUnsafeMutableBufferPointer { r in
            imag.withUnsafeMutableBufferPointer { i in
                let splitComplex = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                vDSP.convert(splitComplexVector: splitComplex, toInterleavedComplexVector: &input)
            }
        }
    }
    
    private func flattenParams() -> [Double] {
        var allParams: [Double] = []
        for paramList in params {
            allParams.append(contentsOf: [paramList.b0, paramList.b1, paramList.b2, paramList.a1, paramList.a2])
        }
        return allParams
    }

    private func initBiquad() {
        self.biquad = vDSP.Biquad(coefficients: flattenParams(), channelCount: 1, sectionCount: vDSP_Length(params.count), ofType: Float.self)!
    }
    
}

class FIRFilter: Filter {
    var taps: [Float]
    var tapsLength: Int
    var stateBuffer: UnsafeMutableBufferPointer<Float> // Last 'tapsLength - 1' values from previous buffer, need for convolution
    
    init(type: FilterType, cutoffFrequency: Double, sampleRate: Int, tapsLength: Int, windowFunc: vDSP.WindowSequence = .hamming) throws {
        var generatedFilter: [Float]
        switch type {
        case .lowPass:
            generatedFilter = makeFIRLowpassTaps(length: tapsLength, cutoff: cutoffFrequency, sampleRate: sampleRate)
        }
        
        taps = generatedFilter
        self.tapsLength = tapsLength
        stateBuffer = .allocate(capacity: tapsLength - 1)
        stateBuffer.initialize(repeating: 0.0)
    }
    
    init(taps: [Float]) {
        self.taps = taps
        self.tapsLength = taps.count
        stateBuffer = .allocate(capacity: tapsLength - 1)
        stateBuffer.initialize(repeating: 0.0)
    }
    
    func filteredSignal(_ input: inout [Float]) {
        let workingBuffer = UnsafeMutableBufferPointer<Float>.allocate(capacity: input.count + tapsLength - 1)
        defer {
            workingBuffer.deallocate()
        }
        
        workingBuffer.baseAddress!.initialize(from: stateBuffer.baseAddress!, count: stateBuffer.count)
        let currentBufferStartingPoint = workingBuffer.baseAddress!.advanced(by: stateBuffer.count)
        currentBufferStartingPoint.initialize(from: input, count: input.count)
        
        copyToStateBuffer(&input)
        var tempOutputBuffer: [Float] = Array(repeating: 0, count: input.count)
        vDSP.convolve(workingBuffer, withKernel: taps, result: &tempOutputBuffer)
        input = tempOutputBuffer
    }
    
    func filtfilt(_ input: inout [Float]) {
        self.filteredSignal(&input)
        var reversedFilteredSignal: [Float] = input.reversed()
        let freshFilter = FIRFilter(taps: self.taps)
        freshFilter.filteredSignal(&reversedFilteredSignal)
        input = reversedFilteredSignal.reversed()
    }
    
    private func copyToStateBuffer(_ input: inout [Float]) {
        _ = stateBuffer.update(fromContentsOf: input.dropFirst(input.count - tapsLength + 1))
    }
    
    func filteredSignal(_ input: inout [DSPComplex]) {
        
    }
    
    deinit {
        stateBuffer.deallocate()
    }
    
}

class ComplexFIRFilter {
    var taps: [Float]
    var tapsLength: Int
    var stateBuffer: UnsafeMutableBufferPointer<DSPComplex> // Last 'tapsLength - 1' values from previous buffer, need for convolution
    
    init(type: FilterType, cutoffFrequency: Double, sampleRate: Int, tapsLength: Int, windowFunc: vDSP.WindowSequence = .hamming) throws {
        var generatedFilter: [Float]
        switch type {
        case .lowPass:
            generatedFilter = makeFIRLowpassTaps(length: tapsLength, cutoff: cutoffFrequency, sampleRate: sampleRate)
        }
        
        taps = generatedFilter
        self.tapsLength = tapsLength
        stateBuffer = .allocate(capacity: tapsLength - 1)
        stateBuffer.initialize(repeating: DSPComplex(real: 0.0, imag: 0.0))
    }
    
    init(taps: [Float]) {
        self.taps = taps
        self.tapsLength = taps.count
        stateBuffer = .allocate(capacity: tapsLength - 1)
        stateBuffer.initialize(repeating: DSPComplex(real: 0.0, imag: 0.0))
    }
    
    func filteredSignal(_ input: inout [DSPComplex]) {
        let workingBuffer = UnsafeMutableBufferPointer<DSPComplex>.allocate(capacity: input.count + tapsLength - 1)
        defer {
            workingBuffer.deallocate()
        }
        
        workingBuffer.baseAddress!.initialize(from: stateBuffer.baseAddress!, count: stateBuffer.count)
        let currentBufferStartingPoint = workingBuffer.baseAddress!.advanced(by: stateBuffer.count)
        currentBufferStartingPoint.initialize(from: input, count: input.count)
        
        copyToStateBuffer(&input)
        var splitComplexOutputBuffer = DSPSplitComplex(realp: .allocate(capacity: input.count), imagp: .allocate(capacity: input.count))
        var realOutputBuffer = UnsafeMutableBufferPointer(start: splitComplexOutputBuffer.realp, count: input.count)
        var imagOutputBuffer = UnsafeMutableBufferPointer(start: splitComplexOutputBuffer.imagp, count: input.count)
        var splitComplexBuffer = DSPSplitComplex(realp: .allocate(capacity: input.count + tapsLength - 1), imagp: .allocate(capacity: input.count + tapsLength - 1))
        defer {
            splitComplexOutputBuffer.imagp.deallocate()
            splitComplexOutputBuffer.realp.deallocate()
            splitComplexBuffer.imagp.deallocate()
            splitComplexBuffer.realp.deallocate()
        }
        let splitComplexBufferRealBranchPointer: UnsafeMutableBufferPointer<Float> = .init(start: splitComplexBuffer.realp, count: input.count + tapsLength - 1)
        let splitComplexBufferImagBranchPointer: UnsafeMutableBufferPointer<Float> = .init(start: splitComplexBuffer.imagp, count: input.count + tapsLength - 1)
        vDSP.convert(interleavedComplexVector: workingBuffer.dropLast(0),  toSplitComplexVector: &splitComplexBuffer) // .dropLast(0) converts pointer to array (not sure if this results in a copy)
        vDSP.convolve(splitComplexBufferRealBranchPointer, withKernel: taps, result: &realOutputBuffer)
        vDSP.convolve(splitComplexBufferImagBranchPointer, withKernel: taps, result: &imagOutputBuffer)
        vDSP.convert(splitComplexVector: splitComplexOutputBuffer, toInterleavedComplexVector: &input)
    }
    
    func filtfilt(_ input: inout [DSPComplex]) {
        self.filteredSignal(&input)
        var reversedFilteredSignal: [DSPComplex] = input.reversed()
        let freshFilter = FIRFilter(taps: self.taps)
        freshFilter.filteredSignal(&reversedFilteredSignal)
        input = reversedFilteredSignal.reversed()
    }
    
    private func copyToStateBuffer(_ input: inout [DSPComplex]) {
        _ = stateBuffer.update(fromContentsOf: input.dropFirst(input.count - tapsLength + 1))
    }
    
    deinit {
        stateBuffer.deallocate()
    }
    
}

enum FilterType {
    case lowPass
}

class FilterParameter {
    let b0: Double
    let b1: Double
    let b2: Double
    let a1: Double
    let a2: Double

    init(_ b0: Double, _ b1: Double, _ b2: Double, _ a1: Double, _ a2: Double) {
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.a1 = a1
        self.a2 = a2
    }
    
    convenience init(_ b0: Double, _ b1: Double, _ b2: Double, _ a0: Double, _ a1: Double, _ a2: Double) {
        self.init(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
    }
    
    convenience init(_ params: [Double]) throws {
        if(params.count == 5) {
            self.init(params[0], params[1], params[2], params[3], params[4])
        }
        else if(params.count == 6) {
            self.init(params[0], params[1], params[2], params[3], params[4], params[5])
        }
        else {
            // Will probably just crash :(
            self.init(params[0], params[1], params[2], params[3], params[4])
        }
    }
    
    func getvDSPBiquad() -> vDSP.Biquad<Float> {
        return vDSP.Biquad(coefficients: [b0, b1, b2, a1, a2], channelCount: 1, sectionCount: 1, ofType: Float.self)!
    }
}

class LowPassFilterParameter: FilterParameter {
    init(sampleRate: Double, frequency: Double, q: Double) {
        let w0: Double = 2.0 * Double.pi * frequency / sampleRate
        let alpha: Double = sin(w0) / (2.0 * q)

        let a0: Double = 1.0 + alpha
        let a1: Double = -2.0 * cos(w0)
        let a2: Double = 1.0 - alpha
        let b0: Double = (1.0 - cos(w0)) / 2.0
        let b1: Double = 1.0 - cos(w0)
        let b2: Double = (1.0 - cos(w0)) / 2.0

        super.init(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
    }
}

class HighPassFilterParameter: FilterParameter {
    init(sampleRate: Double, frequency: Double, q: Double) {
        let w0: Double = 2.0 * Double.pi * frequency / sampleRate
        let alpha: Double = sin(w0) / (2.0 * q)

        let a0: Double = 1.0 + alpha
        let a1: Double = -2.0 * cos(w0)
        let a2: Double = 1.0 - alpha
        let b0: Double = (1.0 + cos(w0)) / 2.0
        let b1: Double = -1.0 * (1.0 + cos(w0))
        let b2: Double = (1.0 + cos(w0)) / 2.0

        super.init(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
    }
}

// Generates a finite impulse response lowpass filter given a cutoff frequency, sampleRate, and optionally a windowing func
func makeFIRLowpassTaps(length: Int, cutoff: Double, sampleRate: Int, windowSequence: vDSP.WindowSequence = .hamming) -> [Float] {
    let sampleRateAsDouble = Double(sampleRate)
    precondition(length > 0, "Filter length must be > 0")
    precondition(cutoff > 0 && cutoff < sampleRateAsDouble / 2, "Cutoff must be between 0 Hz and Nyquist")
    precondition(length % 2 == 1, "Filter length should be odd")
    let cutoffNormalized = cutoff / sampleRateAsDouble // Now in cycles/sample
    let sincCoeff = 2 * cutoffNormalized
    var sincVals = sinc(count: length, coeff: sincCoeff).map { Float(2 * cutoffNormalized) * Float($0) }
    let window = vDSP.window(ofType: Float.self, usingSequence: windowSequence, count: length, isHalfWindow: false)
    vDSP.multiply(window, sincVals, result: &sincVals)
    let sum = sincVals.reduce(0, +)
    vDSP.divide(sincVals, sum, result: &sincVals)
    return sincVals
}

func getGaussianFilter(baudRate: Double, sampleRate: Double) -> [Float] {
    // 1. Calculate the 3dB bandwidth of the filter.
    let b = 0.4 * baudRate

    // 2. Determine the standard deviation (sigma) from the bandwidth.
    // This formula relates the time-domain sigma to the frequency-domain bandwidth.
    let sigma = sqrt(log(2.0)) / (2.0 * .pi * b)

    // 3. Convert sigma from continuous time to discrete samples.
    let sigmaSamples = sigma * sampleRate

    // 4. Define the length of the filter in taps.
    // It's set to span 3 bit periods to capture the main lobe and some tails.
    let bitPeriod = Int(sampleRate / baudRate)
    var tapCount = bitPeriod * 3
    
    // Ensure the filter has an odd number of taps for a defined center.
    if tapCount % 2 == 0 {
        tapCount += 1
    }

    // 5. Generate the Gaussian window (the filter shape).
    let M = Double(tapCount)
    let n = (M - 1.0) / 2.0
    var window = [Float](repeating: 0.0, count: tapCount)
    
    // Manually compute the Gaussian function at each tap position.
    for i in 0..<tapCount {
        let position = (Double(i) - n) / sigmaSamples
        window[i] = Float(exp(-0.5 * pow(position, 2)))
    }

    // 6. Normalize the coefficients.
    // This ensures the filter has a gain of 1.
    if let sum = vDSP.sum(window) as Float?, sum != 0 {
        return vDSP.divide(window, sum)
    } else {
        return window
    }
}

func sinc(count: Int, coeff: Double) -> [Double] {
    var sincArray: [Double] = .init(repeating: 0, count: count)
    let baseIndex = Int(-Double(count / 2).rounded(.up))
    for i in sincArray.indices {
        sincArray[i] = sinc(x: i + baseIndex, coeff: coeff)
    }
    return sincArray
}

func sinc(x: Int, coeff: Double) -> Double {
    if(x == 0) { return 1.0 }
    else {
        let sincArg = Double.pi * Double(x) * coeff
        return sin(sincArg) / sincArg
    }
}
