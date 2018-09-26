//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import AVFoundation
import Foundation
import UIKit

// Media wrapper for media generated from the CameraController
public enum KanvasCameraMedia {
    case image(URL)
    case video(URL)
}

// Error handling
enum CameraControllerError: Swift.Error {
    case exportFailure
    case unknown
}

// Protocol for dismissing CameraController
// or exporting its created media.
public protocol CameraControllerDelegate: class {
    /**
     A function that is called when an image is exported. Can be nil if the export fails
     - parameter media: KanvasCameraMedia - this is the media created in the controller (can be image, video, etc)
     - seealso: enum KanvasCameraMedia
     */
    func didCreateMedia(media: KanvasCameraMedia?, error: Error?)

    /**
     A function that is called when the main camera dismiss button is pressed
     */
    func dismissButtonPressed()
    
    /// Called after the welcome tooltip is dismissed
    func didDismissWelcomeTooltip()
    
    /// Called after the creation tooltip is dismissed
    func didDismissCreationTooltip()
    
    /// Called to ask if welcome tooltip should be shown
    ///
    /// - Returns: Bool for tooltip
    func cameraShouldShowWelcomeTooltip() -> Bool
    
    /// Called to ask if creation tooltip should be shown
    ///
    /// - Returns: Bool for tooltip
    func cameraShouldShowCreationTooltip() -> Bool
}

// A controller that contains and layouts all camera handling views and controllers (mode selector, input, etc).
public class CameraController: UIViewController {

    /// The delegate for camera callback methods
    public weak var delegate: CameraControllerDelegate?

    private lazy var cameraView: CameraView = {
        let view = CameraView()
        view.delegate = self
        view.actionsDelegate = self
        return view
    }()
    private lazy var modeAndShootController: ModeSelectorAndShootController = {
        let controller = ModeSelectorAndShootController(settings: self.settings)
        controller.delegate = self
        return controller
    }()
    private lazy var topOptionsController: OptionsController<CameraController> = {
        let options = getOptions(from: self.settings)
        let controller = OptionsController<CameraController>(options: options, spacing: CameraConstants.ButtonMargin)
        controller.delegate = self
        return controller
    }()
    private lazy var clipsController: MediaClipsEditorViewController = {
        let controller = MediaClipsEditorViewController()
        controller.delegate = self
        return controller
    }()

    private lazy var cameraInputController: CameraInputController = {
        let controller = CameraInputController(settings: self.settings, recorderClass: self.recorderClass, segmentsHandlerClass: self.segmentsHandlerClass)
        return controller
    }()

    private let settings: CameraSettings
    private let analyticsProvider: KanvasCameraAnalyticsProvider?
    private var currentMode: CameraMode
    private var isRecording: Bool
    private var disposables: [NSKeyValueObservation] = []
    private var recorderClass: CameraRecordingProtocol.Type
    private var segmentsHandlerClass: SegmentsHandlerType.Type

    /// Constructs a CameraController that will record from the device camera
    /// and export the result to the device, saving to the phone all in between information
    /// needed to attain the final output.
    ///
    /// - Parameter settings: Settings to configure in which ways should the controller
    /// interact with the user, which options should the controller give the user
    /// and which should be the result of the interaction.
    ///   - analyticsProvider: An class conforming to KanvasCameraAnalyticsProvider
    convenience public init(settings: CameraSettings, analyticsProvider: KanvasCameraAnalyticsProvider?) {
        self.init(settings: settings, recorderClass: CameraRecorder.self, segmentsHandlerClass: CameraSegmentHandler.self, analyticsProvider: analyticsProvider)
    }

    /// Constructs a CameraController that will take care of creating media
    /// as the result of user interaction.
    ///
    /// - Parameters:
    ///   - settings: Settings to configure in which ways should the controller
    /// interact with the user, which options should the controller give the user
    /// and which should be the result of the interaction.
    ///   - recorderClass: Class that will provide a recorder that defines how to record media.
    ///   - segmentsHandlerClass: Class that will provide a segments handler for storing stop
    /// motion segments and constructing final input.
    init(settings: CameraSettings,
         recorderClass: CameraRecordingProtocol.Type,
         segmentsHandlerClass: SegmentsHandlerType.Type,
         analyticsProvider: KanvasCameraAnalyticsProvider?) {
        self.settings = settings
        currentMode = settings.initialMode
        isRecording = false
        self.recorderClass = recorderClass
        self.segmentsHandlerClass = segmentsHandlerClass
        self.analyticsProvider = analyticsProvider
        super.init(nibName: .none, bundle: .none)
    }

    @available(*, unavailable, message: "use init(settings:) instead")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable, message: "use init(settings:) instead")
    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        fatalError("init(nibName:bundle:) has not been implemented")
    }

    override public var prefersStatusBarHidden: Bool {
        return true
    }

    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Requests permissions for video
    ///
    /// - Parameter completion: boolean on whether access was granted
    public func requestAccess(_ completion: ((_ granted: Bool) -> ())?) {
        AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { (videoGranted) -> Void in
            performUIUpdate {
                completion?(videoGranted)
            }
        })
    }
    
    /// logs opening the camera
    public func logOpen() {
        analyticsProvider?.logCameraOpen(mode: currentMode)
    }
    
    /// logs closing the camera
    public func logDismiss() {
        analyticsProvider?.logDismiss()
    }

    // MARK: - View Lifecycle

    override public func loadView() {
        view = cameraView
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        cameraView.addModeView(modeAndShootController.view)
        cameraView.addClipsView(clipsController.view)
        cameraView.addCameraInputView(cameraInputController.view)
        cameraView.addOptionsView(topOptionsController.view)
        bindMediaContentAvailable()
        bindContentSelected()
    }
    
    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if delegate?.cameraShouldShowWelcomeTooltip() == true {
            showOnboardingTooltip()
        }
    }

    // MARK: - navigation
    
    private func showPreviewWithSegments(_ segments: [CameraSegment]) {
        let controller = CameraPreviewViewController(settings: settings, segments: segments, assetsHandler: segmentsHandlerClass.init())
        controller.delegate = self
        self.present(controller, animated: true)
    }
    
    private func showOnboardingTooltip() {
        let viewModel = ModalViewModel(text: NSLocalizedString("You can take a picture or video, or tap “Capture” to switch to Loop mode", comment: "Welcome message for the camera"),
                                       buttonTitle: NSLocalizedString("Got it", comment: "Welcome confirmation"),
                                       buttonCallback: { [unowned self] in
                                        self.delegate?.didDismissWelcomeTooltip()
        })
        let controller = ModalController(viewModel: viewModel)
        present(controller, animated: true, completion: nil)
    }
    
    private func showCreationTooltip() {
        let viewModel = ModalViewModel(text: NSLocalizedString("Looks great! Keep capturing to add more, or hit next to continue.", comment: "Tooltip message for capturing clips"),
                                       buttonTitle: NSLocalizedString("Got it", comment: "Tooltip confirmation"),
                                       buttonCallback: { [unowned self] in
                                        self.delegate?.didDismissCreationTooltip()
        })
        let controller = ModalController(viewModel: viewModel)
        present(controller, animated: true, completion: nil)
    }
    
    private func showDismissTooltip() {
        let viewModel = ModalViewModel(text: NSLocalizedString("Are you sure? If you close this, you'll lose everything you just created.", comment: "Popup message when user discards all their clips"),
                                       confirmTitle: NSLocalizedString("I'm sure", comment: "Confirmation to discard all the clips"),
                                       confirmCallback: { [unowned self] in
                                        performUIUpdate {
                                            self.delegate?.dismissButtonPressed()
                                        }
        },
                                       cancelTitle: NSLocalizedString("Cancel", comment: "Cancel action"),
                                       cancelCallback: {
                                        /// should do nothing here other than dismiss the modal
        },
                                       buttonsLayout: .oneBelowTheOther)
        let controller = ModalController(viewModel: viewModel)
        present(controller, animated: true, completion: nil)
    }
    
    // MARK: - Media Content Creation
    private func saveImageToFile(_ image: UIImage?) -> URL? {
        do {
            guard let image = image, let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return nil
            }
            if !FileManager.default.fileExists(atPath: documentsURL.path, isDirectory: nil) {
                try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true, attributes: nil)
            }
            let fileURL = documentsURL.appendingPathComponent("kanvas-camera-image.jpg", isDirectory: false)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            
            if let jpgImageData = UIImageJPEGRepresentation(image, 1.0) {
                try jpgImageData.write(to: fileURL, options: .atomic)
            }
            return fileURL
        } catch {
            NSLog("failed to save to file. Maybe parent directories couldn't be created.")
            return nil
        }
    }
    
    private func durationStringForAssetAtURL(_ url: URL?) -> String {
        var text = ""
        if let url = url {
            let asset = AVURLAsset(url: url)
            let seconds = CMTimeGetSeconds(asset.duration)
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.minute, .second]
            formatter.zeroFormattingBehavior = .pad
            if let time = formatter.string(from: seconds) {
                text = time
            }
        }
        return text
    }
    
    private func takeGif() {
        cameraInputController.takeGif(completion: { [weak self] url in
            guard let strongSelf = self else { return }
            strongSelf.analyticsProvider?.logCapturedMedia(type: strongSelf.currentMode, cameraPosition: strongSelf.cameraInputController.currentCameraPosition, length: 0)
            performUIUpdate {
                if let url = url {
                    let segment = CameraSegment.video(url)
                    strongSelf.showPreviewWithSegments([segment])
                }
            }
        })
    }
    
    private func takePhoto() {
        cameraInputController.takePhoto(completion: { [weak self] image in
            guard let strongSelf = self else { return }
            strongSelf.analyticsProvider?.logCapturedMedia(type: strongSelf.currentMode, cameraPosition: strongSelf.cameraInputController.currentCameraPosition, length: 0)
            performUIUpdate {
                if let image = image {
                    if strongSelf.currentMode == .photo {
                        strongSelf.showPreviewWithSegments([CameraSegment.image(image, nil)])
                    }
                    else {
                        strongSelf.clipsController.addNewClip(MediaClip(representativeFrame: image, overlayText: nil))
                    }
                }
            }
        })
    }
    
    // MARK : - Mode handling
    private func updateMode(_ mode: CameraMode) {
        if mode != currentMode {
            currentMode = mode
            do {
                try cameraInputController.configureMode(mode)
            } catch {
                // we can ignore this error for now since configuring mode may not succeed for devices without all the modes available (flash, multiple cameras)
            }
        }
    }
    
    private enum RecordingEvent {
        case started
        case ended
    }
    
    private func updateRecordState(event: RecordingEvent) {
        isRecording = event == .started
        cameraView.updateUI(forRecording: isRecording)
        if isRecording {
            modeAndShootController.hideModeButton()
        }
        // If it finished recording, then there is at least one clip and button shouldn't be shown.
    }
    
    // MARK: - UI
    private func enableBottomViewButtons(show: Bool) {
        cameraView.bottomActionsView.updateUndo(enabled: show)
        cameraView.bottomActionsView.updateNext(enabled: show)
        if clipsController.hasClips {
            modeAndShootController.hideModeButton()
        }
        else {
            modeAndShootController.showModeButton()
        }
    }
    
    // MARK : - Private utilities
    private func bindMediaContentAvailable() {
        disposables.append(clipsController.observe(\.hasClips) { [unowned self] object, _ in
            performUIUpdate {
                self.enableBottomViewButtons(show: !object.clipIsSelected && object.hasClips)
            }
        })
        enableBottomViewButtons(show: clipsController.hasClips)
    }
    
    private func bindContentSelected() {
        disposables.append(clipsController.observe(\.clipIsSelected) { [unowned self] object, _ in
            performUIUpdate {
                self.enableBottomViewButtons(show: !object.clipIsSelected && object.hasClips)
            }
        })
    }
}

// MARK: - CameraViewDelegate
extension CameraController: CameraViewDelegate, ActionsViewDelegate {

    func undoButtonPressed() {
        clipsController.undo()
        cameraInputController.deleteSegmentAtIndex(cameraInputController.segments().count - 1)
        analyticsProvider?.logUndoTapped()
    }

    func nextButtonPressed() {
        showPreviewWithSegments(cameraInputController.segments())
        analyticsProvider?.logNextTapped()
    }

    func closeButtonPressed() {
        if clipsController.hasClips {
            showDismissTooltip()
        }
        else {
            delegate?.dismissButtonPressed()
        }
    }

}

// MARK: - ModeSelectorAndShootControllerDelegate
extension CameraController: ModeSelectorAndShootControllerDelegate {

    func didOpenMode(_ mode: CameraMode, andClosed oldMode: CameraMode?) {
        updateMode(mode)
    }

    func didTapForMode(_ mode: CameraMode) {
        switch mode {
        case .gif:
            takeGif()
        case .photo:
            takePhoto()
        case .stopMotion:
            takePhoto()
        }
    }

    func didStartPressingForMode(_ mode: CameraMode) {
        switch mode {
        case .stopMotion:
            let _ = cameraInputController.startRecording()
            performUIUpdate { [weak self] in
                self?.updateRecordState(event: .started)
            }
        default: break
        }
    }

    func didEndPressingForMode(_ mode: CameraMode) {
        switch mode {
        case .stopMotion:
            cameraInputController.endRecording(completion: { [weak self] url in
                guard let strongSelf = self else { return }
                if let videoURL = url {
                    let asset = AVURLAsset(url: videoURL)
                    strongSelf.analyticsProvider?.logCapturedMedia(type: strongSelf.currentMode, cameraPosition: strongSelf.cameraInputController.currentCameraPosition, length: CMTimeGetSeconds(asset.duration))
                }
                performUIUpdate {
                    if let url = url, let image = AVURLAsset(url: url).thumbnail() {
                        strongSelf.clipsController.addNewClip(MediaClip(representativeFrame: image, overlayText: strongSelf.durationStringForAssetAtURL(url)))
                    }
                    strongSelf.updateRecordState(event: .ended)
                }
            })
        default: break
        }
    }

}

// MARK: - OptionsCollectionControllerDelegate (Top Options)
extension CameraController: OptionsControllerDelegate {

    func optionSelected(_ item: CameraDeviceOption) {
        switch item {
        case .flashOn:
            cameraInputController.setFlashMode(on: true)
            analyticsProvider?.logFlashToggled()
        case .flashOff:
            cameraInputController.setFlashMode(on: false)
            analyticsProvider?.logFlashToggled()
        case .backCamera, .frontCamera:
            cameraInputController.switchCameras()
            analyticsProvider?.logFlipCamera()
        }
    }

}

// MARK: - MediaClipsEditorDelegate
extension CameraController: MediaClipsEditorDelegate {

    func mediaClipWasDeleted(at index: Int) {
        cameraInputController.deleteSegmentAtIndex(index)
        analyticsProvider?.logDeleteSegment()
    }

    func mediaClipWasAdded(at index: Int) {
        if delegate?.cameraShouldShowCreationTooltip() == true {
            showCreationTooltip()
        }
    }
}

// MARK: - CameraPreviewControllerDelegate
extension CameraController: CameraPreviewControllerDelegate {
    func didFinishExportingVideo(url: URL?) {
        if let videoURL = url {
            let asset = AVURLAsset(url: videoURL)
            analyticsProvider?.logConfirmedMedia(mode: currentMode, clipsCount: cameraInputController.segments().count, length: CMTimeGetSeconds(asset.duration))
        }
        performUIUpdate { [weak self] in
            self?.delegate?.didCreateMedia(media: url.map { .video($0) }, error: url != nil ? nil : CameraControllerError.exportFailure)
        }
    }

    func didFinishExportingImage(image: UIImage?) {
        analyticsProvider?.logConfirmedMedia(mode: currentMode, clipsCount: 1, length: 0)
        performUIUpdate { [weak self] in
            if let url = self?.saveImageToFile(image) {
                let media = KanvasCameraMedia.image(url)
                self?.delegate?.didCreateMedia(media: media, error: nil)
            }
            else {
                self?.delegate?.didCreateMedia(media: nil, error: CameraControllerError.exportFailure)
            }
        }
    }

    func dismissButtonPressed() {
        analyticsProvider?.logPreviewDismissed()
        performUIUpdate { [weak self] in
            self?.dismiss(animated: true)
        }
    }
}
