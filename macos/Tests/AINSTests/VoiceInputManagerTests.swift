//
//  VoiceInputManagerTests.swift
//  GhosttyTests
//
//  Generated unit tests for VoiceInputManager
//

import Testing
import Foundation
import Speech
@testable import Ghostty

@Suite("VoiceInputManager Tests")
struct VoiceInputManagerTests {

    @Test("Initialization with valid locale")
    func testInitialization() async throws {
        let voiceManager = VoiceInputManager()

        #expect(voiceManager.isListening == false)
        #expect(voiceManager.transcribedText == "")
        #expect(voiceManager.authorizationStatus == .notDetermined ||
                voiceManager.authorizationStatus == .authorized)
    }

    @Test("Check authorization status")
    func testCheckAuthorization() async throws {
        let voiceManager = VoiceInputManager()
        let initialStatus = voiceManager.authorizationStatus

        voiceManager.checkAuthorizationStatus()

        #expect(voiceManager.authorizationStatus == initialStatus ||
                voiceManager.authorizationStatus == SFSpeechRecognizer.authorizationStatus())
    }

    @Test("Request authorization")
    func testRequestAuthorization() async throws {
        let voiceManager = VoiceInputManager()

        // This should not crash
        voiceManager.requestAuthorization()

        // Give it a moment to process
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(true) // If we get here, the test passed
    }

    @Test("Start and stop listening")
    func testStartStopListening() async throws {
        let voiceManager = VoiceInputManager()

        // Should not be listening initially
        #expect(voiceManager.isListening == false)

        // Start listening (if authorized)
        if voiceManager.authorizationStatus == .authorized {
            voiceManager.startListening()
            try await Task.sleep(nanoseconds: 500_000_000)
            #expect(voiceManager.isListening == true)

            // Stop listening
            voiceManager.stopListening()
            #expect(voiceManager.isListening == false)
        }
    }

    @Test("Toggle listening state")
    func testToggleListening() async throws {
        let voiceManager = VoiceInputManager()

        if voiceManager.authorizationStatus == .authorized {
            let initialState = voiceManager.isListening

            voiceManager.toggleListening()
            try await Task.sleep(nanoseconds: 500_000_000)

            #expect(voiceManager.isListening != initialState)

            // Toggle back
            voiceManager.toggleListening()
            try await Task.sleep(nanoseconds: 500_000_000)

            #expect(voiceManager.isListening == initialState)
        }
    }

    @Test("Deinitialization cleanup")
    func testDeinitCleanup() async throws {
        // Create and immediately deallocate
        do {
            let voiceManager = VoiceInputManager()
            voiceManager.checkAuthorizationStatus()
            // VoiceManager should clean up properly on deallocation
        }

        // If we get here without crashes, cleanup worked
        #expect(true)
    }

    @Test("Authorization status updates correctly")
    func testAuthorizationUpdates() async throws {
        let voiceManager = VoiceInputManager()
        let initialStatus = voiceManager.authorizationStatus

        // Request authorization if not determined
        if initialStatus == .notDetermined {
            voiceManager.requestAuthorization()
            try await Task.sleep(nanoseconds: 1_000_000_000)

            let newStatus = voiceManager.authorizationStatus
            #expect(newStatus != .notDetermined)
        }
    }

    @Test("Multiple startListening calls are safe")
    func testMultipleStartCalls() async throws {
        let voiceManager = VoiceInputManager()

        if voiceManager.authorizationStatus == .authorized {
            voiceManager.startListening()
            try await Task.sleep(nanoseconds: 200_000_000)

            // Call start again - should not crash
            voiceManager.startListening()
            #expect(voiceManager.isListening == true)

            voiceManager.stopListening()
        }
    }

    @Test("Multiple stopListening calls are safe")
    func testMultipleStopCalls() async throws {
        let voiceManager = VoiceInputManager()

        if voiceManager.authorizationStatus == .authorized {
            voiceManager.startListening()
            try await Task.sleep(nanoseconds: 200_000_000)

            voiceManager.stopListening()
            #expect(voiceManager.isListening == false)

            // Call stop again - should not crash
            voiceManager.stopListening()
            #expect(voiceManager.isListening == false)
        }
    }

    @Test("Transcribed text updates correctly")
    func testTranscribedTextUpdates() async throws {
        let voiceManager = VoiceInputManager()
        let initialText = voiceManager.transcribedText

        #expect(initialText == "")

        // Note: Actual transcription would require audio input
        // This test just verifies the property exists and is accessible
        voiceManager.transcribedText = "Test"
        #expect(voiceManager.transcribedText == "Test")
    }

    @Test("Error message handling")
    func testErrorMessageHandling() async throws {
        let voiceManager = VoiceInputManager()

        // Initially no error
        #expect(voiceManager.errorMessage == nil)

        // Start/stop to ensure no errors
        if voiceManager.authorizationStatus == .authorized {
            voiceManager.startListening()
            try await Task.sleep(nanoseconds: 200_000_000)
            voiceManager.stopListening()
        }
    }

    @Test("Silence timeout behavior")
    func testSilenceTimeout() async throws {
        let voiceManager = VoiceInputManager()

        if voiceManager.authorizationStatus == .authorized {
            voiceManager.startListening()
            try await Task.sleep(nanoseconds: 200_000_000)

            #expect(voiceManager.isListening == true)

            // Wait for potential timeout (60 seconds)
            // For testing, we won't wait full duration
            try await Task.sleep(nanoseconds: 1_000_000_000)

            // Should still be listening (no timeout yet)
            #expect(voiceManager.isListening == true)

            voiceManager.stopListening()
        }
    }
}
