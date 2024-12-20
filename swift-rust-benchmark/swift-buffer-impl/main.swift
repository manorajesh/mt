import Foundation

func main() {
    // Create buffer and parser
    let buffer = Buffer(rows: 24, cols: 80)
    let parser = AnsiParser(buffer: buffer)
    
    // Setup process
    let process = Process()
    let pipe = Pipe()
    
    process.executableURL = URL(fileURLWithPath: "/bin/cat")
    process.arguments = ["-e", "/Users/mano/Downloads/enwik8.pmd"]
    process.standardOutput = pipe
    
    // Collect output phase
    let collectionStart = DispatchTime.now()
    var outputData: Data = Data()
    
    do {
        try process.run()
        outputData = try pipe.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        
        let collectionEnd = DispatchTime.now()
        let collectionTime = Double(collectionEnd.uptimeNanoseconds - collectionStart.uptimeNanoseconds) / 1_000_000
        // print("Collection time: \(collectionTime) ms")
        print("Bytes collected: \(outputData.count) bytes")
        
        // Parse phase
        let parseStart = DispatchTime.now()
        outputData.forEach { byte in
            parser.parse(byte: byte)
        }
        
        let parseEnd = DispatchTime.now()
        let parseTime = Double(parseEnd.uptimeNanoseconds - parseStart.uptimeNanoseconds) / 1_000_000
        print("Parse time: \(parseTime) ms")
        // print("Total time: \(collectionTime + parseTime) ms")
        
        // Print buffer contents
        for row in 0..<buffer.rows {
            for col in 0..<buffer.cols {
                print(String(UnicodeScalar(buffer[row, col].asciiCode)), terminator: "")
            }
            print()
        }
        
    } catch {
        print("Error: \(error)")
    }
}

main()