//
//  MP3File+ReadTag.swift
//  OutcastID3
//
//  Created by Quentin Zervaas on 30/11/18.
//

import Foundation

public extension OutcastID3.MP3File {
    public enum ReadError: Swift.Error {
        case tagNotFound
        case tagVersionNotFound
        case tagSizeNotFound
        case unsupportedTagVersion
        case corruptedFile
        case corruptedHeader
    }
    
    // TODO: Not handling extended header properly?
    
    func readID3Tag() throws -> TagProperties {
        let fileHandle = try FileHandle(forReadingFrom: self.localUrl)
        
        defer {
            // Will run after function finishes, even for throws
            fileHandle.closeFile()
        }
        
        return try readID3Tag(fileHandle: fileHandle)
    }
    
    public func readID3Tag(fileHandle: FileHandle) throws -> TagProperties {
        // Assumes the ID3 tag is at the start of the file.
        let startingByteOffset: UInt64 = 0
        
        fileHandle.seek(toFileOffset: startingByteOffset)
        
        let id3String = String(bytes: fileHandle.readData(ofLength: 3), encoding: .isoLatin1)
        
        guard id3String == "ID3" else {
            throw ReadError.tagNotFound
        }
        
        guard let versionNumber = fileHandle.readData(ofLength: 1).first else {
            throw ReadError.corruptedHeader
        }
        
        guard let version = OutcastID3.TagVersion(rawValue: versionNumber) else {
            throw ReadError.tagVersionNotFound
        }
        
        fileHandle.seek(toFileOffset: startingByteOffset + 6)
        
        let tagSizeBytes = fileHandle.readData(ofLength: 4)
        
        guard tagSizeBytes.count == 4 else {
            throw ReadError.tagSizeNotFound
        }
        
        // TODO: ID3v2.1 only uses 3 bytes
        
        // 4 bytes, each of 7 bits
        let s1 = UInt32(tagSizeBytes[0] & 0x7f) << 21
        let s2 = UInt32(tagSizeBytes[1] & 0x7f) << 14
        let s3 = UInt32(tagSizeBytes[2] & 0x7f) << 7
        let s4 = UInt32(tagSizeBytes[3] & 0x7f)
        
        let tagByteCount = Int(s1 + s2 + s3 + s4)
        
        fileHandle.seek(toFileOffset: UInt64(version.tagHeaderSizeInBytes))
        let tagData = fileHandle.readData(ofLength: tagByteCount)
        
        let endingByteOffset = fileHandle.offsetInFile
        
        // Parse the tag data into frames
        
        let frames = try OutcastID3.ID3Tag.framesFromData(version: version, data: tagData)
        
        let tag = OutcastID3.ID3Tag(
            version: version,
            frames: frames
        )
        
        return TagProperties(
            tag: tag,
            startingByteOffset: startingByteOffset,
            endingByteOffset: endingByteOffset
        )
    }
}

extension OutcastID3.ID3Tag {
    static func framesFromData(version: OutcastID3.TagVersion, data: Data, throwOnError: Bool = false) throws -> [OutcastID3TagFrame] {
        var ret: [OutcastID3TagFrame] = []
        
        var position = 0
        
        let count = data.count
        
        while position < count {
            do {
                let frameSize = try determineFrameSize(data: data, position: position, version: version)
                
                guard position + frameSize <= count else {
                    print("Frame size too big position=\(position) + frameSize=\(frameSize) = \(position + frameSize), count=\(count)")
                    break
                }
                
                let frameData = data.subdata(in: position ..< position + frameSize)
                
                if let frame = OutcastID3.Frame.RawFrame.parse(version: version, data: frameData) {
                    ret.append(frame)
                }
                
                position += frameSize// frame.data.count
            }
            catch let e {
                if throwOnError {
                    throw e
                }
                else {
                    break
                }
            }
        }
        
        return ret
    }
    
    /// Determine the size of the frame that begins at the given position
    
    static func determineFrameSize(data: Data, position: Int, version: OutcastID3.TagVersion) throws -> Int {
        
        let offset    = position + version.frameSizeOffsetInBytes
        let byteRange = NSMakeRange(offset, version.frameSizeByteCount)
        
        guard byteRange.location + byteRange.length < data.count else {
            throw OutcastID3.MP3File.ReadError.corruptedFile
        }
        
        var frameSize: UInt32 = 0
        
        (data as NSData).getBytes(&frameSize, range: byteRange)
        
        frameSize = frameSize.bigEndian & version.frameSizeMask
        
        return Int(frameSize) + version.frameHeaderSizeInBytes
    }
}
