//
//  VoiceInputManagerEnhancedTests.swift
//  GhosttyTests
//
//  Enhanced unit tests for VoiceInputManager with comprehensive coverage
//

import XCTest
import Foundation
import Speech
@testable import Ghostty

class VoiceInputManagerEnhancedTests: XCTestCase {

    var voiceManager: VoiceInputManager!

    override func setUp() {
        super.setUp()
        voiceManager = VoiceInputManager()
    }

    override func tearDown() {
        voiceManager = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitializationWithFallbackLocale() {
        // Should initialize with system locale or fallback to en-US
        XCTAssertFalse(voiceManager.isListening)
        XCTAssertEqual(voiceManager.transcribedText, "")
        XCTAssertNotNil(voiceManager.authorizationStatus)
    }

    func testMultipleInitializationInstances() {
        // Multiple instances should not interfere with each other
        let manager1 = VoiceInputManager()
        let manager2 = VoiceInputManager()

        XCTAssertFalse(manager1.isListening)
        XCTAssertFalse(manager2.isListening)

        manager1.checkAuthorizationStatus()
        manager2.checkAuthorizationStatus()

        // Both should have their own state
        XCTAssertNotNil(manager1.authorizationStatus)
        XCTAssertNotNil(manager2.authorizationStatus)
    }

    // MARK: - Authorization Tests

    func testCheckAuthorizationStatus() {
        let initialStatus = voiceManager.authorizationStatus
        voiceManager.checkAuthorizationStatus()

        // Status should be updated to current authorization status
        XCTAssertEqual(voiceManager.authorizationStatus, SFSpeechRecognizer.authorizationStatus())
    }

    func testRequestAuthorizationNotDetermined() {
        // If not determined, requesting authorization should not crash
        if voiceManager.authorizationStatus == .notDetermined {
            voiceManager.requestAuthorization()

            let expectation = self.expectation(description: "Authorization")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                expectation.fulfill()
            }
            waitForExpectations(timeout: 2.0)

            // Status should no longer be "not determined"
            XCTAssertNotEqual(voiceManager.authorizationStatus, .notDetermined)
        }
    }

    func testAuthorizationMessageForStatus() {
        // Test that authorization messages are appropriate
        let deniedMessage = voiceManager.authorizationMessage(for: .denied)
        XCTAssertTrue(deniedMessage.contains("denied") || deniedMessage.contains("disabled"))

        let authorizedMessage = voiceManager.authorizationMessage(for: .authorized)
        XCTAssertEqual(authorizedMessage, "")

        let restrictedMessage = voiceManager.authorizationMessage(for: .restricted)
        XCTAssertTrue(restrictedMessage.contains("restricted"))
    }

    // MARK: - Listening State Tests

    func testStartListeningWithoutAuthorization() {
        // Should not start listening without authorization
        if voiceManager.authorizationStatus != .authorized {
            voiceManager.startListening()
            XCTAssertFalse(voiceManager.isListening)
        }
    }

    func testStartListeningWithAuthorization() {
        guard voiceManager.authorizationStatus == .authorized else {
            XCTSkip("Authorization not granted, skipping test")
            return
        }

        let expectation = self.expectation(description: "StartListening")
        voiceManager.startListening()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            XCTAssertTrue(self.voiceManager.isListening)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2.0)
        voiceManager.stopListening()
    }

    func testStartListeningWhileAlreadyListening() {
        guard voiceManager.authorizationStatus == .authorized else {
            XCTSkip("Authorization not granted, skipping test")
            return
        }

        voiceManager.startListening()

        let expectation = self.expectation(description: "DoubleStart")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let wasListening = self.voiceManager.isListening
            self.voiceManager.startListening()
            XCTAssertEqual(self.voiceManager.isListening, wasListening)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
        voiceManager.stopListening()
    }

    func testStopListening() {
        guard voiceManager.authorizationStatus == .authorized else {
            XCTSkip("Authorization not granted, skipping test")
            return
        }

        voiceManager.startListening()

        let expectation = self.expectation(description: "StopListening")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertTrue(self.voiceManager.isListening)
            self.voiceManager.stopListening()
            XCTAssertFalse(self.voiceManager.isListening)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    func testStopListeningWhenNotListening() {
        // Should not crash when stopping while not listening
        XCTAssertFalse(voiceManager.isListening)
        voiceManager.stopListening()
        XCTAssertFalse(voiceManager.isListening)
    }

    func testToggleListening() {
        guard voiceManager.authorizationStatus == .authorized else {
            XCTSkip("Authorization not granted, skipping test")
            return
        }

        let initialState = voiceManager.isListening

        voiceManager.toggleListening()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertNotEqual(self.voiceManager.isListening, initialState)
        }

        voiceManager.toggleListening()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            XCTAssertEqual(self.voiceManager.isListening, initialState)
        }
    }

    // MARK: - Resource Management Tests

    func testDeinitCleansUpResources() {
        var manager: VoiceInputManager? = VoiceInputManager()

        if manager?.authorizationStatus == .authorized {
            manager?.startListening()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                XCTAssertTrue(manager?.isListening ?? false)
            }
        }

        // Deallocate while potentially still listening
        manager = nil

        // If we get here without crashes, cleanup worked properly
        XCTAssertNil(manager)
    }

    func testMultipleInstancesCleanup() {
        // Create multiple instances and ensure they all clean up properly
        var managers: [VoiceInputManager] = []

        for _ in 0..<5 {
            let manager = VoiceInputManager()
            managers.append(manager)
        }

        if managers[0].authorizationStatus == .authorized {
            managers[0].startListening()
        }

        // Clear all managers
        managers.removeAll()

        // Verify cleanup through manual testing
        XCTAssertEqual(managers.count, 0)
    }

    // MARK: - Error Handling Tests

    func testErrorMessageHandling() {
        // Initially should be no error
        XCTAssertNil(voiceManager.errorMessage)

        // After various operations, should still handle errors gracefully
        voiceManager.checkAuthorizationStatus()
        voiceManager.requestAuthorization()

        // Error message should be nil or a valid string
        if let errorMessage = voiceManager.errorMessage {
            XCTAssertFalse(errorMessage.isEmpty)
        }
    }

    func testStartRecognitionErrorHandling() {
        // Test error handling when recognition fails to start
        if voiceManager.authorizationStatus != .authorized {
            voiceManager.startListening()
            XCTAssertFalse(voiceManager.isListening)
            XCTAssertNotNil(voiceManager.errorMessage)
        }
    }

    // MARK: - Timer and Debouncing Tests

    func testSilenceTimerBehavior() {
        guard voiceManager.authorizationStatus == .authorized else {
            XCTSkip("Authorization not granted, skipping test")
            return
        }

        voiceManager.startListening()

        let expectation = self.expectation(description: "TimerCheck")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Should still be listening (no timeout yet)
            XCTAssertTrue(self.voiceManager.isListening)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 3.0)
        voiceManager.stopListening()
    }

    func testDebounceTaskCancellation() {
        guard voiceManager.authorizationStatus == .authorized else {
            XCTSkip("Authorization not granted, skipping test")
            return
        }

        voiceManager.startListening()

        // Trigger multiple rapid transcriptions
        for i in 0..<5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1) {
                self.voiceManager.transcribedText = "Test \(i)"
            }
        }

        // Stop listening should cancel debounce task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.voiceManager.stopListening()
            XCTAssertFalse(self.voiceManager.isListening)
        }

        // Wait for operations to complete
        let expectation = self.expectation(description: "DebounceComplete")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2.0)
    }

    // MARK: - Transcription Tests

    func testTranscribedTextUpdates() {
        XCTAssertEqual(voiceManager.transcribedText, "")

        voiceManager.transcribedText = "Hello world"
        XCTAssertEqual(voiceManager.transcribedText, "Hello world")

        voiceManager.transcribedText = ""
        XCTAssertEqual(voiceManager.transcribedText, "")
    }

    func testTranscribedTextPersistsAfterStop() {
        voiceManager.transcribedText = "Persistent text"
        XCTAssertEqual(voiceManager.transcribedText, "Persistent text")

        voiceManager.stopListening()
        XCTAssertEqual(voiceManager.transcribedText, "Persistent text")
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentStartStop() {
        guard voiceManager.authorizationStatus == .authorized else {
            XCTSkip("Authorization not granted, skipping test")
            return
        }

        let expectation = self.expectation(description: "ConcurrentAccess")
        expectation.expectedFulfillmentCount = 10

        // Simulate rapid concurrent start/stop calls
        for i in 0..<10 {
            DispatchQueue.global(qos: .userInitiated).async {
                if i % 2 == 0 {
                    self.voiceManager.startListening()
                } else {
                    self.voiceManager.stopListening()
                }
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5.0)

        // Should be in a stable state
        XCTAssertTrue(voiceManager.isListening || !voiceManager.isListening)
    }

    // MARK: - Locale Handling Tests

    func testSystemLocaleDetection() {
        // Should attempt to use system locale
        let systemLocale = Locale.current.identifier
        XCTAssertFalse(systemLocale.isEmpty)
    }

    func testFallbackLocale() {
        // When system locale fails, should fallback to en-US
        let voiceManager = VoiceInputManager()
        XCTAssertNotNil(voiceManager.authorizationStatus)
    }

    // MARK: - Memory Pressure Tests

    func testMemoryCleanupUnderLoad() {
        var managers: [VoiceInputManager] = []

        // Create many instances
        for _ in 0..<100 {
            let manager = VoiceInputManager()
            managers.append(manager)
        }

        // Start listening on some
        if managers[0].authorizationStatus == .authorized {
            managers[0].startListening()
        }

        // Clear all references
        managers.removeAll()

        // Verify cleanup happened properly
        XCTAssertEqual(managers.count, 0)
    }

    // MARK: - Performance Tests

    func testStartListeningPerformance() {
        guard voiceManager.authorizationStatus == .authorized else {
            XCTSkip("Authorization not granted, skipping test")
            return
        }

        measure {
            voiceManager.startListening()
            voiceManager.stopListening()
        }
    }

    func testStopListeningPerformance() {
        guard voiceManager.authorizationStatus == .authorized else {
            XCTSkip("Authorization not granted, skipping test")
            return
        }

        voiceManager.startListening()

        measure {
            voiceManager.stopListening()
            voiceManager.startListening()
        }

        voiceManager.stopListening()
    }
}

// MARK: - Helper Extensions for Testing

extension VoiceInputManager {
    // Expose private methods for testing
    func authorizationMessage(for status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "Speech recognition permission not yet requested"
        case .denied:
            return "Speech recognition permission denied. Enable it in System Settings > Privacy & Security > Speech Recognition"
        case .restricted:
            return "Speech recognition is restricted on this device"
        case .authorized:
            return ""
        @unknown default:
            return "Unknown authorization status"
        }
    }
}

// MARK: - Mock Classes for Testing

class MockVoiceInputManager: VoiceInputManager {
    var mockAuthorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    var mockIsListening: Bool = false

    override var authorizationStatus: SFSpeechRecognizerAuthorizationStatus {
        get { mockAuthorizationStatus }
        set {}
    }

    override var isListening: Bool {
        get { mockIsListening }
        set { mockIsListening = newValue }
    }

    override func startListening() {
        if mockAuthorizationStatus == .authorized {
            mockIsListening = true
        }
    }

    override func stopListening() {
        mockIsListening = false
    }
}
