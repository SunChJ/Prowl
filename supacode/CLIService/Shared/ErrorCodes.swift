// ProwlShared/ErrorCodes.swift
// Stable error codes matching schema.md contracts.

import Foundation

public enum CLIErrorCode {
  // Common
  public static let appNotRunning = "APP_NOT_RUNNING"
  public static let invalidArgument = "INVALID_ARGUMENT"
  public static let targetNotFound = "TARGET_NOT_FOUND"
  public static let targetNotUnique = "TARGET_NOT_UNIQUE"

  // Open
  public static let pathNotFound = "PATH_NOT_FOUND"
  public static let pathNotDirectory = "PATH_NOT_DIRECTORY"
  public static let pathNotAllowed = "PATH_NOT_ALLOWED"
  public static let launchFailed = "LAUNCH_FAILED"
  public static let openFailed = "OPEN_FAILED"

  // List
  public static let listFailed = "LIST_FAILED"

  // Agents
  public static let agentsFailed = "AGENTS_FAILED"

  // Focus
  public static let focusFailed = "FOCUS_FAILED"

  // Send
  public static let emptyInput = "EMPTY_INPUT"
  public static let sendFailed = "SEND_FAILED"
  public static let waitTimeout = "WAIT_TIMEOUT"
  public static let captureUnsupported = "CAPTURE_UNSUPPORTED"

  // Key
  public static let invalidRepeat = "INVALID_REPEAT"
  public static let noActivePane = "NO_ACTIVE_PANE"
  public static let unsupportedKey = "UNSUPPORTED_KEY"
  public static let keyDeliveryFailed = "KEY_DELIVERY_FAILED"

  // Read
  public static let readFailed = "READ_FAILED"

  // Tab
  public static let tabFailed = "TAB_FAILED"

  // Pane
  public static let paneFailed = "PANE_FAILED"

  // Handoff
  public static let handoffFailed = "HANDOFF_FAILED"
  /// Self-handoff invoked without `--brief`/`--no-brief`.
  public static let briefRequired = "BRIEF_REQUIRED"
  /// Inline briefing text failed validation; nothing was written.
  public static let invalidBrief = "INVALID_BRIEF"
  /// No selector was given and the caller is not inside a Prowl pane.
  public static let sourceRequired = "SOURCE_REQUIRED"
  /// A HUD-injected request was already superseded by its fallback.
  public static let handoffRequestSuperseded = "HANDOFF_REQUEST_SUPERSEDED"

  // Transport
  public static let transportFailed = "TRANSPORT_FAILED"
  public static let socketPermissionDenied = "SOCKET_PERMISSION_DENIED"
  public static let timeout = "TIMEOUT"
}
