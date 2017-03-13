/*
 Copyright 2014 OpenMarket Ltd
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import <Foundation/Foundation.h>

/**
 The Matrix iOS SDK version.
 */
FOUNDATION_EXPORT NSString *MatrixSDKVersion;

#import <MatrixSDK/MXRestClient.h>
#import <MatrixSDK/MXSession.h>
#import <MatrixSDK/MXError.h>

#import <MatrixSDK/MXStore.h>
#import <MatrixSDK/MXNoStore.h>
#import <MatrixSDK/MXMemoryStore.h>
#import <MatrixSDK/MXFileStore.h>
#import <MatrixSDK/MXCoreDataStore.h>

#import <MatrixSDK/MXEventsEnumeratorOnArray.h>
#import <MatrixSDK/MXEventsByTypesEnumeratorOnArray.h>

#import <MatrixSDK/MXLogger.h>

#import "MXTools.h"
#import "NSData+MatrixSDK.h"

#import "MXSDKOptions.h"

#import "MXMediaManager.h"

#import "MXLRUCache.h"

#import "MatrixSDK/MXCrypto.h"
#import "MatrixSDK/MXMegolmExportEncryption.h"