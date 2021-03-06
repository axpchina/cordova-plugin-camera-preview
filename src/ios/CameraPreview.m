#import <Cordova/CDV.h>
#import <Cordova/CDVPlugin.h>
#import <Cordova/CDVInvokedUrlCommand.h>
#import <MediaPlayer/MediaPlayer.h>

#import "CameraPreview.h"

@implementation CameraPreview

-(void) pluginInitialize{
    // start as transparent
    self.webView.opaque = NO;
    self.webView.backgroundColor = [UIColor clearColor];
    
    motionManager = [[CMMotionManager alloc] init];
    motionManager.accelerometerUpdateInterval = .2;
    motionManager.gyroUpdateInterval = .2;
    
    [motionManager startAccelerometerUpdatesToQueue:[NSOperationQueue currentQueue]
                                        withHandler:^(CMAccelerometerData  *accelerometerData, NSError *error) {
                                            if (!error) {
                                                [self outputAccelertionData:accelerometerData.acceleration];
                                            }
                                            else{
                                                NSLog(@"%@", error);
                                            }
                                        }];
}

- (void)outputAccelertionData:(CMAcceleration)acceleration{
    UIImageOrientation orientationNew;
    
    if (acceleration.x >= 0.75) {
        orientationNew = UIImageOrientationDown;//
    }
    else if (acceleration.x <= -0.75) {
        orientationNew = UIImageOrientationUp;//left
    }
    else if (acceleration.y <= -0.75) {
        orientationNew = UIImageOrientationRight;//
    }
    else if (acceleration.y >= 0.75) {
        orientationNew = UIImageOrientationLeft;
    }
    else {
        // Consider same as last time
        return;
    }
    
    if (orientationNew == imageOrientation)
        return;
    
    imageOrientation = orientationNew;
}


-(void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    
    if ([keyPath isEqual:@"outputVolume"]) {
        float volumeLevel = [[MPMusicPlayerController applicationMusicPlayer] volume];
        if (volumeLevel <= 0.1 || volumeLevel >= 0.9) {
            [[MPMusicPlayerController applicationMusicPlayer] setVolume:(float) 0.5f];
        }
        else{
            [self.commandDelegate evalJs:@"window.volumeButtonTaken()"];
        }
        
    }
}

- (void) startCamera:(CDVInvokedUrlCommand*)command {
    
    CDVPluginResult *pluginResult;
    @try{
        AVAudioSession* audioSession = [AVAudioSession sharedInstance];
        [audioSession setActive:YES error:nil];
        [audioSession addObserver:self
                       forKeyPath:@"outputVolume"
                          options:0
                          context:nil];
    }
    @catch(NSException *exception){
           NSLog(@"Error ocours while installing audo session: %@", exception);
       }
    
    if (self.sessionManager != nil) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Camera already started!"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }
    
    if (command.arguments.count > 3) {
        CGFloat x = (CGFloat)[command.arguments[0] floatValue] + self.webView.frame.origin.x;
        CGFloat y = (CGFloat)[command.arguments[1] floatValue] + self.webView.frame.origin.y;
        CGFloat width = (CGFloat)[command.arguments[2] floatValue];
        CGFloat height = (CGFloat)[command.arguments[3] floatValue];
        NSString *defaultCamera = command.arguments[4];
        BOOL tapToTakePicture = (BOOL)[command.arguments[5] boolValue];
        BOOL dragEnabled = (BOOL)[command.arguments[6] boolValue];
        BOOL toBack = (BOOL)[command.arguments[7] boolValue];
        NSString *index = command.arguments[9];
        NSString *ts = command.arguments[10];
        
        // Create the session manager
        self.sessionManager = [[CameraSessionManager alloc] init];
        
        // render controller setup
        self.cameraRenderController = [[CameraRenderController alloc] init];
        self.cameraRenderController.dragEnabled = dragEnabled;
        self.cameraRenderController.tapToTakePicture = tapToTakePicture;
        self.cameraRenderController.sessionManager = self.sessionManager;
        self.nameIndex = index;
        self.nameTs = ts;
        self.cameraRenderController.view.frame = CGRectMake(x, y, width, height);
        
        self.cameraRenderController.delegate = self;
        
        [self.viewController addChildViewController:self.cameraRenderController];
        
        if (toBack) {
            // display the camera below the webview
            
            // make transparent
            self.webView.opaque = NO;
            self.webView.backgroundColor = [UIColor clearColor];
            
            [self.webView.superview addSubview:self.cameraRenderController.view];
            [self.webView.superview bringSubviewToFront:self.webView];
        } else {
            self.cameraRenderController.view.alpha = (CGFloat)[command.arguments[8] floatValue];
            [self.webView.superview insertSubview:self.cameraRenderController.view aboveSubview:self.webView];
        }
        
        // Setup session
        self.sessionManager.delegate = self.cameraRenderController;
        [self.sessionManager setupSession:defaultCamera];
        
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Invalid number of parameters"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) stopCamera:(CDVInvokedUrlCommand*)command {
    NSLog(@"stopCamera");
    CDVPluginResult *pluginResult;
    @try{
        AVAudioSession* audioSession = [AVAudioSession sharedInstance];
        [audioSession setActive:YES error:nil];
        [audioSession removeObserver:self forKeyPath:@"outputVolume"];
    }
    @catch(NSException *exception){
        NSLog(@"Error ocours while uninstalling audo session: %@", exception);
    }
    if(self.sessionManager != nil) {
        [self.cameraRenderController.view removeFromSuperview];
        [self.cameraRenderController removeFromParentViewController];
        self.cameraRenderController = nil;
        
        [self.sessionManager.session stopRunning];
        self.sessionManager = nil;
        
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    }
    else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Camera not started"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) hideCamera:(CDVInvokedUrlCommand*)command {
    NSLog(@"hideCamera");
    CDVPluginResult *pluginResult;
    
    if (self.cameraRenderController != nil) {
        [self.cameraRenderController.view setHidden:YES];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Camera not started"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) showCamera:(CDVInvokedUrlCommand*)command {
    NSLog(@"showCamera");
    CDVPluginResult *pluginResult;
    
    if (self.cameraRenderController != nil) {
        [self.cameraRenderController.view setHidden:NO];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Camera not started"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) switchCamera:(CDVInvokedUrlCommand*)command {
    NSLog(@"switchCamera");
    CDVPluginResult *pluginResult;
    
    if (self.sessionManager != nil) {
        [self.sessionManager switchCamera];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Camera not started"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getSupportedFocusModes:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;
    
    if (self.sessionManager != nil) {
        NSArray * focusModes = [self.sessionManager getFocusModes];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:focusModes];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not started"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getFocusMode:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;
    
    if (self.sessionManager != nil) {
        NSString * focusMode = [self.sessionManager getFocusMode];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:focusMode];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not started"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) setFocusMode:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;
    
    NSString * focusMode = [[command.arguments objectAtIndex:0] stringValue];
    if (self.sessionManager != nil) {
        [self.sessionManager setFocusMode:focusMode];
        NSString * focusMode = [self.sessionManager getFocusMode];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:focusMode ];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not started"];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getSupportedFlashModes:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;
    
    if (self.sessionManager != nil) {
        NSArray * flashModes = [self.sessionManager getFlashModes];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:flashModes];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Flash not supported"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getFlashMode:(CDVInvokedUrlCommand*)command {
    
    CDVPluginResult *pluginResult;
    
    if (self.sessionManager != nil) {
        NSInteger flashMode = [self.sessionManager getFlashMode];
        NSString * sFlashMode;
        if (flashMode == 0) {
            sFlashMode = @"off";
        } else if (flashMode == 1) {
            sFlashMode = @"on";
        } else if (flashMode == 2) {
            sFlashMode = @"auto";
        } else {
            sFlashMode = @"unsupported";
        }
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:sFlashMode ];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Camera not started"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) setFlashMode:(CDVInvokedUrlCommand*)command {
    NSLog(@"Flash Mode");
    NSString *errMsg;
    CDVPluginResult *pluginResult;
    
    NSString *flashMode = [command.arguments objectAtIndex:0];
    
    if (self.sessionManager != nil) {
        if ([flashMode isEqual: @"off"]) {
            [self.sessionManager setFlashMode:AVCaptureFlashModeOff];
        } else if ([flashMode isEqual: @"on"]) {
            [self.sessionManager setFlashMode:AVCaptureFlashModeOn];
        } else if ([flashMode isEqual: @"auto"]) {
            [self.sessionManager setFlashMode:AVCaptureFlashModeAuto];
        } else if ([flashMode isEqual: @"torch"]) {
            [self.sessionManager setTorchMode];
        } else {
            errMsg = @"Flash Mode not supported";
        }
    } else {
        errMsg = @"Camera not started";
    }
    
    if (errMsg) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errMsg];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) setZoom:(CDVInvokedUrlCommand*)command {
    NSLog(@"Zoom");
    CDVPluginResult *pluginResult;
    
    CGFloat desiredZoomFactor = [[command.arguments objectAtIndex:0] floatValue];
    
    if (self.sessionManager != nil) {
        [self.sessionManager setZoom:desiredZoomFactor];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Camera not not zoomed"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getZoom:(CDVInvokedUrlCommand*)command {
    
    CDVPluginResult *pluginResult;
    
    if (self.sessionManager != nil) {
        CGFloat zoom = [self.sessionManager getZoom];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:zoom ];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Camera not zoomed"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getMaxZoom:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;
    
    if (self.sessionManager != nil) {
        CGFloat maxZoom = [self.sessionManager getMaxZoom];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:maxZoom ];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Camera not zoomed"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getExposureModes:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;
    
    if (self.sessionManager != nil) {
        NSArray * exposureModes = [self.sessionManager getExposureModes];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:exposureModes];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Exposure modes not supported"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getExposureMode:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;
    
    if (self.sessionManager != nil) {
        NSString * exposureMode = [self.sessionManager getExposureMode];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:exposureMode ];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Exposure modes not supported"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) setExposureMode:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;
    
    NSString * exposureMode = [command.arguments objectAtIndex:0];
    if (self.sessionManager != nil) {
        [self.sessionManager setExposureMode:exposureMode];
        NSString * exposureMode = [self.sessionManager getExposureMode];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:exposureMode ];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Exposure modes not supported"];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getSupportedWhiteBalanceModes:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;
    
    if (self.sessionManager != nil) {
        NSArray * whiteBalanceModes = [self.sessionManager getSupportedWhiteBalanceModes];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:whiteBalanceModes ];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"White balance modes not supported"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getWhiteBalanceMode:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;
    
    if (self.sessionManager != nil) {
        NSString * whiteBalanceMode = [self.sessionManager getWhiteBalanceMode];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:whiteBalanceMode ];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"White balance modes not supported"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) setWhiteBalanceMode:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;
    
    NSString * whiteBalanceMode = [command.arguments objectAtIndex:0];
    if (self.sessionManager != nil) {
        [self.sessionManager setWhiteBalanceMode:whiteBalanceMode];
        NSString * wbMode = [self.sessionManager getWhiteBalanceMode];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:wbMode ];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"White balance modes not supported"];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getExposureCompensationRange:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;
    
    if (self.sessionManager != nil) {
        NSArray * exposureRange = [self.sessionManager getExposureCompensationRange];
        NSMutableDictionary *dimensions = [[NSMutableDictionary alloc] init];
        [dimensions setValue:exposureRange[0] forKey:@"min"];
        [dimensions setValue:exposureRange[1] forKey:@"max"];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:dimensions];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"No session started"];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getExposureCompensation:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;
    
    if (self.sessionManager != nil) {
        CGFloat exposureCompensation = [self.sessionManager getExposureCompensation];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:exposureCompensation ];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Camera not started"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) setExposureCompensation:(CDVInvokedUrlCommand*)command {
    NSLog(@"Zoom");
    CDVPluginResult *pluginResult;
    
    CGFloat exposureCompensation = [[command.arguments objectAtIndex:0] floatValue];
    
    if (self.sessionManager != nil) {
        [self.sessionManager setExposureCompensation:exposureCompensation];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:exposureCompensation];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Camera not started"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) takePicture:(CDVInvokedUrlCommand*)command {
    NSLog(@"takePicture");
    CDVPluginResult *pluginResult;
    
    if (self.cameraRenderController != NULL) {
        self.onPictureTakenHandlerId = command.callbackId;
        
        CGFloat width = (CGFloat)[command.arguments[0] floatValue];
        CGFloat height = (CGFloat)[command.arguments[1] floatValue];
        CGFloat quality = (CGFloat)[command.arguments[2] floatValue] / 100;
        NSString *index = command.arguments[3];
        NSString *ts = command.arguments[4];
        
        [self invokeTakePicture:width withHeight:height withQuality:quality withIndex:index withTs:ts isTap:false];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Camera not started"];
        
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
}


-(void) setColorEffect:(CDVInvokedUrlCommand*)command {
    NSLog(@"setColorEffect");
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    NSString *filterName = command.arguments[0];
    
    if(self.sessionManager != nil){
        if ([filterName isEqual: @"none"]) {
            dispatch_async(self.sessionManager.sessionQueue, ^{
                [self.sessionManager setCiFilter:nil];
            });
        } else if ([filterName isEqual: @"mono"]) {
            dispatch_async(self.sessionManager.sessionQueue, ^{
                CIFilter *filter = [CIFilter filterWithName:@"CIMaximumComponent"];
                [filter setDefaults];
                [self.sessionManager setCiFilter:filter];
            });
        } else if ([filterName isEqual: @"negative"]) {
            dispatch_async(self.sessionManager.sessionQueue, ^{
                CIFilter *filter = [CIFilter filterWithName:@"CIColorInvert"];
                [filter setDefaults];
                [self.sessionManager setCiFilter:filter];
            });
        } else if ([filterName isEqual: @"posterize"]) {
            dispatch_async(self.sessionManager.sessionQueue, ^{
                CIFilter *filter = [CIFilter filterWithName:@"CIColorPosterize"];
                [filter setDefaults];
                [self.sessionManager setCiFilter:filter];
            });
        } else if ([filterName isEqual: @"sepia"]) {
            dispatch_async(self.sessionManager.sessionQueue, ^{
                CIFilter *filter = [CIFilter filterWithName:@"CISepiaTone"];
                [filter setDefaults];
                [self.sessionManager setCiFilter:filter];
            });
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Filter not found"];
        }
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Camera not started"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) setPreviewSize: (CDVInvokedUrlCommand*)command {
    
    CDVPluginResult *pluginResult;
    
    if (self.sessionManager == nil) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Camera did not start!"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }
    
    if (command.arguments.count > 1) {
        CGFloat width = (CGFloat)[command.arguments[0] floatValue];
        CGFloat height = (CGFloat)[command.arguments[1] floatValue];
        
        self.cameraRenderController.view.frame = CGRectMake(0, 0, width, height);
        
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Invalid number of parameters"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getSupportedPictureSizes:(CDVInvokedUrlCommand*)command {
    NSLog(@"getSupportedPictureSizes");
    CDVPluginResult *pluginResult;
    
    if(self.sessionManager != nil){
        NSArray *formats = self.sessionManager.getDeviceFormats;
        NSMutableArray *jsonFormats = [NSMutableArray new];
        int lastWidth = 0;
        int lastHeight = 0;
        for (AVCaptureDeviceFormat *format in formats) {
            CMVideoDimensions dim = format.highResolutionStillImageDimensions;
            if (dim.width!=lastWidth && dim.height != lastHeight) {
                NSMutableDictionary *dimensions = [[NSMutableDictionary alloc] init];
                NSNumber *width = [NSNumber numberWithInt:dim.width];
                NSNumber *height = [NSNumber numberWithInt:dim.height];
                [dimensions setValue:width forKey:@"width"];
                [dimensions setValue:height forKey:@"height"];
                [jsonFormats addObject:dimensions];
                lastWidth = dim.width;
                lastHeight = dim.height;
            }
        }
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:jsonFormats];
        
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Camera not started"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (NSString *)getBase64Image:(CGImageRef)imageRef withQuality:(int) quality {
    NSString *base64Image = nil;
    
    @try {
        UIImage *image = [UIImage imageWithCGImage:imageRef];
        NSData *imageData = UIImageJPEGRepresentation(image, quality);
        base64Image = [imageData base64EncodedStringWithOptions:0];
    }
    @catch (NSException *exception) {
        NSLog(@"error while get base64Image: %@", [exception reason]);
    }
    
    return base64Image;
}

- (void) tapToFocus:(CDVInvokedUrlCommand*)command {
    NSLog(@"tapToFocus");
    CDVPluginResult *pluginResult;
    
    CGFloat xPoint = [[command.arguments objectAtIndex:0] floatValue];
    CGFloat yPoint = [[command.arguments objectAtIndex:1] floatValue];
    
    if (self.sessionManager != nil) {
        [self.sessionManager tapToFocus:xPoint yPoint:yPoint];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Camera not tapped to focus"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) invokeTakePicture {
    [self invokeTakePicture:0.0 withHeight:0.0 withQuality:1 withIndex:self.nameIndex withTs:self.nameTs isTap:true];
}

- (NSData *)resizedImageDataFromHighImage:(UIImage *)image withQuality:(int) quality
{
    
    CGFloat smallerWith = image.size.width / 4;
    CGFloat smallerHeight = image.size.height / 4;
    
    UIGraphicsBeginImageContext(CGSizeMake(smallerWith, smallerHeight));
    
    UIGraphicsGetCurrentContext();
    
    [image drawInRect: CGRectMake(0, 0, smallerWith, smallerHeight)];
    
    UIImage *smallImage = UIGraphicsGetImageFromCurrentImageContext();
    
    UIGraphicsEndImageContext();
    
    return UIImageJPEGRepresentation(smallImage, quality);
    
}

- (UIImage *)fixrotation:(UIImage *)image{
    
    if (image.imageOrientation == UIImageOrientationUp) return image;
    CGAffineTransform transform = CGAffineTransformIdentity;
    
    switch (image.imageOrientation) {
        case UIImageOrientationDown:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, image.size.width, image.size.height);
            transform = CGAffineTransformRotate(transform, M_PI);
            break;
            
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
            transform = CGAffineTransformTranslate(transform, image.size.width, 0);
            transform = CGAffineTransformRotate(transform, M_PI_2);
            break;
            
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, 0, image.size.height);
            transform = CGAffineTransformRotate(transform, -M_PI_2);
            break;
        case UIImageOrientationUp:
        case UIImageOrientationUpMirrored:
            break;
    }
    
    switch (image.imageOrientation) {
        case UIImageOrientationUpMirrored:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, image.size.width, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
            
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, image.size.height, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
        case UIImageOrientationUp:
        case UIImageOrientationDown:
        case UIImageOrientationLeft:
        case UIImageOrientationRight:
            break;
    }
    
    // Now we draw the underlying CGImage into a new context, applying the transform
    // calculated above.
    CGContextRef ctx = CGBitmapContextCreate(NULL, image.size.width, image.size.height,
                                             CGImageGetBitsPerComponent(image.CGImage), 0,
                                             CGImageGetColorSpace(image.CGImage),
                                             CGImageGetBitmapInfo(image.CGImage));
    CGContextConcatCTM(ctx, transform);
    switch (image.imageOrientation) {
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            // Grr...
            CGContextDrawImage(ctx, CGRectMake(0,0,image.size.height,image.size.width), image.CGImage);
            break;
            
        default:
            CGContextDrawImage(ctx, CGRectMake(0,0,image.size.width,image.size.height), image.CGImage);
            break;
    }
    
    // And now we just create a new UIImage from the drawing context
    CGImageRef cgimg = CGBitmapContextCreateImage(ctx);
    UIImage *img = [UIImage imageWithCGImage:cgimg];
    CGContextRelease(ctx);
    CGImageRelease(cgimg);
    return img;
}

- (void) invokeTakePicture:(CGFloat) width withHeight:(CGFloat) height withQuality:(int) quality withIndex:(NSString*) index withTs:(NSString*) ts isTap:(bool)isTap{
    AVCaptureConnection *connection = [self.sessionManager.stillImageOutput connectionWithMediaType:AVMediaTypeVideo];
    [self.sessionManager.stillImageOutput captureStillImageAsynchronouslyFromConnection:connection completionHandler:^(CMSampleBufferRef sampleBuffer, NSError *error) {
        
        NSLog(@"Done creating still image");
        if (error) {
            NSLog(@"%@", error);
        } else {
            NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:sampleBuffer];
            UIImage *capturedImage  = [[UIImage alloc] initWithData:imageData];
            
            CIImage *capturedCImage;
            //image resize
            
            if(width > 0 && height > 0){
                CGFloat scaleHeight = width/capturedImage.size.height;
                CGFloat scaleWidth = height/capturedImage.size.width;
                CGFloat scale = scaleHeight > scaleWidth ? scaleWidth : scaleHeight;
                
                CIFilter *resizeFilter = [CIFilter filterWithName:@"CILanczosScaleTransform"];
                [resizeFilter setValue:[[CIImage alloc] initWithCGImage:[capturedImage CGImage]] forKey:kCIInputImageKey];
                [resizeFilter setValue:[NSNumber numberWithFloat:1.0f] forKey:@"inputAspectRatio"];
                [resizeFilter setValue:[NSNumber numberWithFloat:scale] forKey:@"inputScale"];
                capturedCImage = [resizeFilter outputImage];
            }else{
                capturedCImage = [[CIImage alloc] initWithCGImage:[capturedImage CGImage]];
            }
            
            CIImage *imageToFilter;
            CIImage *finalCImage;
            
            //fix front mirroring
            if (self.sessionManager.defaultCamera == AVCaptureDevicePositionFront) {
                CGAffineTransform matrix = CGAffineTransformTranslate(CGAffineTransformMakeScale(1, -1), 0, capturedCImage.extent.size.height);
                imageToFilter = [capturedCImage imageByApplyingTransform:matrix];
            } else {
                imageToFilter = capturedCImage;
            }
            
            CIFilter *filter = [self.sessionManager ciFilter];
            if (filter != nil) {
                [self.sessionManager.filterLock lock];
                [filter setValue:imageToFilter forKey:kCIInputImageKey];
                finalCImage = [filter outputImage];
                [self.sessionManager.filterLock unlock];
            } else {
                finalCImage = imageToFilter;
            }
            
            NSMutableArray *params = [[NSMutableArray alloc] init];
            
            CGImageRef finalImage = [self.cameraRenderController.ciContext createCGImage:finalCImage fromRect:finalCImage.extent];
            UIImage *image = [self fixrotation:[[UIImage alloc]initWithCGImage:finalImage scale:1.0 orientation:imageOrientation]] ;
            NSData *data = UIImageJPEGRepresentation(image, quality);
            NSData *thumbImageData = [self resizedImageDataFromHighImage:image withQuality:0.5];
            
            CGImageRelease(finalImage); // release CGImageRef to remove memory leaks
            
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                 NSUserDomainMask, YES);
            NSString *imgFolder = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"/answerImg/"];
            
            imgFolder = [imgFolder stringByAppendingPathComponent:ts];
            NSError *error;
            if (![[NSFileManager defaultManager] fileExistsAtPath:imgFolder]){
                [[NSFileManager defaultManager] createDirectoryAtPath:imgFolder withIntermediateDirectories:NO attributes:nil error:&error];
            }
            
            //            imgFolder = [imgFolder stringByAppendingString:@"/"];
            NSString *imageName = [index stringByAppendingString:@".jpg"];
            NSString *imagePath = [imgFolder stringByAppendingPathComponent:imageName];
            
            NSString *thumbImageName = [index stringByAppendingString:@"_thumb.jpg"];
            NSString *thumbImagePath = [imgFolder stringByAppendingPathComponent:thumbImageName];
            
            dispatch_group_t group = dispatch_group_create();
            
            dispatch_group_async(group,dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^ {
                NSLog(@"Image writing....");
                
                [data writeToFile:imagePath atomically:YES];
                [thumbImageData writeToFile:thumbImagePath atomically:YES];
                NSLog(@"Image writing done");
            });
            
            dispatch_group_notify(group,dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^ {
                [params addObject:imagePath];
                
                CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:params];
                [pluginResult setKeepCallbackAsBool:true];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:self.onPictureTakenHandlerId];
            });
            
        }
    }];
}


@end

