// ProwlCLI/Transport/SocketTransportClient.swift
// Unix domain socket client for communicating with running Prowl app.

import Foundation
import ProwlCLIShared

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

enum SocketTransportClient {
  private static let maximumResponseLength = 32 * 1_024 * 1_024

  /// Send a command envelope to the Prowl app and receive a response.
  static func send(
    _ envelope: CommandEnvelope,
    timeoutMilliseconds: Int? = nil
  ) throws -> Data {
    let socketPath = ProwlSocket.defaultPath

    // Encode request
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let requestData = try encoder.encode(envelope)

    // Create socket
    let clientFD = socket(AF_UNIX, SOCK_STREAM, 0)
    guard clientFD >= 0 else {
      throw ExitError(
        code: CLIErrorCode.transportFailed,
        message: "Failed to create socket."
      )
    }
    defer { close(clientFD) }
    if let timeoutMilliseconds {
      try configureTimeout(clientFD, milliseconds: timeoutMilliseconds)
    }

    let connection = SocketConnectionProbe.connect(socketFD: clientFD, socketPath: socketPath)
    if let error = connection.exitError() {
      throw error
    }

    // Send length-prefixed request: 4-byte big-endian length + JSON payload
    var length = UInt32(requestData.count).bigEndian
    try withUnsafeBytes(of: &length) { try fdWrite(fildes: clientFD, buffer: $0) }
    try requestData.withUnsafeBytes { try fdWrite(fildes: clientFD, buffer: $0) }

    // Read length-prefixed response
    let responseLengthData = try fdRead(fildes: clientFD, count: 4)
    let responseLength = responseLengthData.withUnsafeBytes {
      UInt32(bigEndian: $0.load(as: UInt32.self))
    }

    guard responseLength > 0, responseLength <= maximumResponseLength else {
      throw ExitError(
        code: CLIErrorCode.transportFailed,
        message: "Invalid response length from app."
      )
    }

    return try fdRead(fildes: clientFD, count: Int(responseLength))
  }

  // MARK: - Low-level I/O using Darwin/Glibc read/write

  private static func configureTimeout(_ descriptor: Int32, milliseconds: Int) throws {
    let bounded = max(1, milliseconds)
    var timeout = timeval(
      tv_sec: bounded / 1_000,
      tv_usec: Int32((bounded % 1_000) * 1_000)
    )
    let size = socklen_t(MemoryLayout<timeval>.size)
    let receive = withUnsafePointer(to: &timeout) {
      setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, $0, size)
    }
    let send = withUnsafePointer(to: &timeout) {
      setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, $0, size)
    }
    guard receive == 0, send == 0 else {
      throw ExitError(code: CLIErrorCode.transportFailed, message: "Failed to configure socket deadline.")
    }
  }

  private static func fdWrite(fildes: Int32, buffer: UnsafeRawBufferPointer) throws {
    var offset = 0
    while offset < buffer.count {
      let written = Darwin.write(fildes, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
      guard written > 0 else {
        throw ExitError(code: CLIErrorCode.transportFailed, message: socketWriteFailureMessage(bytesWritten: written))
      }
      offset += written
    }
  }

  private static func fdRead(fildes: Int32, count: Int) throws -> Data {
    var data = Data(capacity: count)
    var remaining = count
    let bufferSize = min(count, 65536)
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 1)
    defer { buffer.deallocate() }
    while remaining > 0 {
      let toRead = min(remaining, bufferSize)
      let bytesRead = Darwin.read(fildes, buffer, toRead)
      guard bytesRead > 0 else {
        throw ExitError(code: CLIErrorCode.transportFailed, message: socketReadFailureMessage(bytesRead: bytesRead))
      }
      data.append(buffer.assumingMemoryBound(to: UInt8.self), count: bytesRead)
      remaining -= bytesRead
    }
    return data
  }

  private static func socketWriteFailureMessage(bytesWritten: Int) -> String {
    if bytesWritten == 0 {
      return "Socket write failed: wrote 0 bytes before the request was complete."
    }
    return "Socket write failed (\(errnoName(errno)): \(String(cString: strerror(errno))))."
  }

  private static func socketReadFailureMessage(bytesRead: Int) -> String {
    if bytesRead == 0 {
      return "Socket read failed: Prowl closed the connection before sending a complete response."
    }
    return "Socket read failed (\(errnoName(errno)): \(String(cString: strerror(errno))))."
  }

  private static func errnoName(_ errorNumber: Int32) -> String {
    switch errorNumber {
    case EACCES: "EACCES"
    case ECONNREFUSED: "ECONNREFUSED"
    case EINVAL: "EINVAL"
    case ENOENT: "ENOENT"
    case ENOTSOCK: "ENOTSOCK"
    case EPERM: "EPERM"
    default: "errno \(errorNumber)"
    }
  }
}
