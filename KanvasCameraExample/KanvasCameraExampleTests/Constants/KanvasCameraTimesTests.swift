//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

@testable import KanvasCamera
import AVFoundation
import Foundation
import XCTest

final class KanvasCameraTimesTests: XCTestCase {

    func testVideoRecordingTime() {
        XCTAssert(KanvasCameraTimes.videoRecordingTime == 30, "Returned value does not match expected value")
    }

    func testStopMotionFrameDuration() {
        XCTAssert(KanvasCameraTimes.singlePhotoWithVideoFrameDuration == 300, "Returned value does not match expected value")
    }

    func testStopMotionFrameTimescale() {
        XCTAssert(KanvasCameraTimes.stopMotionFrameTimescale == 600, "Returned value does not match expected value")
    }

    func testStopMotionFrameTime() {
        XCTAssert(CMTimeCompare(KanvasCameraTimes.stopMotionFrameTime, CMTime(value: 300, timescale: 600)) == 0, "Returned value does not match expected value")
    }

    func testStopMotionFrameTimeInterval() {
        XCTAssert(KanvasCameraTimes.stopMotionFrameTimeInterval == 0.5, "Returned value does not match expected value")
    }

    func testGifTapRecordingTime() {
        XCTAssert(KanvasCameraTimes.gifTapRecordingTime == 1, "Returned value does not match expected value")
    }

    func testGifHoldRecordingTime() {
        XCTAssert(KanvasCameraTimes.gifHoldRecordingTime == 2, "Returned value does not match expected value")
    }

    func testGifPreferredFramesPerSecond() {
        XCTAssert(KanvasCameraTimes.gifPreferredFramesPerSecond == 10, "Returned value does not match expected value")
    }

    func testGifTapTotalFrames() {
        XCTAssertEqual(KanvasCameraTimes.gifTapNumberOfFrames, 10, "Returned value does not match expected value")
    }

    func testGifHoldTotalFrames() {
        XCTAssertEqual(KanvasCameraTimes.gifHoldNumberOfFrames, 20, "Returned value does not match expected value")
    }

    func testGifRecordingTime() {
        XCTAssertEqual(KanvasCameraTimes.recordingTime(for: .gif, hold: false), 1, "Tapping the GIF shutter should record for 1 second")
        XCTAssertEqual(KanvasCameraTimes.recordingTime(for: .gif, hold: true), 2, "Holding the GIF shutter should record for 2 seconds")
    }

}
