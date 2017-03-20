//
//  ViewController.swift
//  LivePhotoToAnimatedGif
//
//  Created by itok on 2016/03/18.
//  Copyright © 2016年 sorakae Inc. All rights reserved.
//

import UIKit
import Photos
import PhotosUI
import ImageIO
import MobileCoreServices

class ViewController: UIViewController {

	@IBOutlet weak var livePhotoView: PHLivePhotoView!
	@IBOutlet weak var webView: UIWebView!
	
	override func viewDidLoad() {
		super.viewDidLoad()
		// Do any additional setup after loading the view, typically from a nib.
		self.checkAuthorization()
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
	}

	func checkAuthorization() {
		PHPhotoLibrary.requestAuthorization { (status) -> Void in
			if status == .authorized {
				self.searchLivePhoto()
			}
		}
	}

    
    func searchLivePhoto() {
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "mediaSubtype & %d != 0", PHAssetMediaSubtype.photoLive.rawValue)
        let result = PHAsset.fetchAssets(with: .image, options: opts)
        // get live photo data
        if let photoAsset = result.lastObject as PHAsset! {
            PHImageManager.default().requestLivePhoto(for: photoAsset, targetSize: CGSize.zero, contentMode: .aspectFit, options: nil, resultHandler: { (livePhoto, _) in
                if let livePhoto = livePhoto{
                    self.livePhotoView.livePhoto = livePhoto                }
            })
        }
        
        
    }
    
    
	@IBAction func convert(_ sender: AnyObject) {
		guard let livePhoto = self.livePhotoView.livePhoto else {
			return
		}
		
		// search movie in live photo
		let resources = PHAssetResource.assetResources(for: livePhoto)
		for resource in resources {
			if resource.type == .pairedVideo {
				self.getMovieData(resource)
				break
			}
		}
	}
	
	func getMovieData(_ resource: PHAssetResource) {
		let moviePath = (NSTemporaryDirectory() as NSString).appendingPathComponent(resource.originalFilename)
		let movieURL = URL(fileURLWithPath: moviePath)
		let movieData = NSMutableData()

		// load movie data
		PHAssetResourceManager.default().requestData(for: resource, options: nil, dataReceivedHandler: { (data) -> Void in
			movieData.append(data)
		}) { (err) -> Void in
			do {
				try movieData.write(to: movieURL, options: NSData.WritingOptions.atomicWrite)
				let movieAsset = AVAsset(url: movieURL)
				self.convertToGif(movieAsset, resource: resource)
			} catch {
				
			}
		}
	}
	
	func convertToGif(_ movieAsset: AVAsset, resource: PHAssetResource) {
		// gif frames
		let numFrame = 30
		let frameValue = movieAsset.duration.value / Int64(numFrame)
		let timeScale = movieAsset.duration.timescale
		var times = Array<NSValue>()
		for i in 0..<numFrame {
			let time = CMTimeMakeWithEpoch(frameValue * Int64(i), timeScale, movieAsset.duration.epoch)
			times.append(NSValue(time: time))
		}
		
		guard let docDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else {
			return
		}
		let gifPath = (docDir as NSString).appendingPathComponent((resource.originalFilename as NSString).deletingPathExtension + ".gif")
		let gifURL = URL(fileURLWithPath: gifPath)

		guard let gif = CGImageDestinationCreateWithURL(gifURL as CFURL, kUTTypeGIF, numFrame, nil) else {
			return
		}
		
		let delay = CMTimeGetSeconds(movieAsset.duration) / Float64(numFrame)
		let frameProperty = [String(kCGImagePropertyGIFDictionary): [String(kCGImagePropertyGIFDelayTime): delay]]
		
		var cnt = 0
		// generate thumbnails and write to gif
		let generator = AVAssetImageGenerator(asset: movieAsset)
		// generate in any timelines
		generator.requestedTimeToleranceBefore = kCMTimeZero
		generator.requestedTimeToleranceAfter = kCMTimeZero
		// apply video transform
		generator.appliesPreferredTrackTransform = true
		generator.maximumSize = CGSize(width: 640, height: 640)
		generator.generateCGImagesAsynchronously(forTimes: times) { (requested, image, actual, result, err) -> Void in
			if let image = image {
				CGImageDestinationAddImage(gif, image, frameProperty as CFDictionary?)
			}
			cnt += 1
			if cnt >= numFrame {
				let gifProperty = [String(kCGImagePropertyGIFDictionary): [String(kCGImagePropertyGIFLoopCount): 0]]
				CGImageDestinationSetProperties(gif, gifProperty as CFDictionary?)
				CGImageDestinationFinalize(gif)
				
				DispatchQueue.main.async(execute: { () -> Void in
					self.webView.loadRequest(URLRequest(url: gifURL))
				})
			}
		}
	}
}

