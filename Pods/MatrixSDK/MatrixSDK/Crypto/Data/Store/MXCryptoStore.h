/*
 Copyright 2016 OpenMarket Ltd

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

#import "MXSDKOptions.h"

#ifdef MX_CRYPTO

#import "MXJSONModels.h"

#import <OLMKit/OLMKit.h>
#import "MXOlmInboundGroupSession.h"
#import "MXDeviceInfo.h"

/**
 The `MXCryptoStore` protocol defines an interface that must be implemented in order to store
 crypto data for a matrix account.
 */
@protocol MXCryptoStore <NSObject>

/**
 Indicate if the store contains data for the passed account.
 YES means that the user enabled the crypto in a previous sesison.
 */
+ (BOOL)hasDataForCredentials:(MXCredentials*)credentials;

/**
 Create a crypto store for the passed credentials.
 
 @param credentials the credentials of the account.
 @return the ready to use store.
 */
+ (instancetype)createStoreWithCredentials:(MXCredentials*)credentials;

/**
 Delete the crypto store for the passed credentials.

 @param credentials the credentials of the account.
 */
+ (void)deleteStoreWithCredentials:(MXCredentials*)credentials;

/**
 Create a crypto store for the passed credentials.

 @param credentials the credentials of the account.
 @return the store. Call the open method before using it.
 */
- (instancetype)initWithCredentials:(MXCredentials *)credentials;

/**
 Open the store corresponding to the passed account.

 The implementation can use a separated thread for loading data but the callback blocks
 must be called from the main thread.

 @param onComplete the callback called once the data has been loaded.
 @param failure the callback called in case of error.
 */
- (void)open:(void (^)())onComplete failure:(void (^)(NSError *error))failure;

/**
 Store the device id.
 */
- (void)storeDeviceId:(NSString*)deviceId;

/**
 The device id.
 */
- (NSString*)deviceId;

/**
 Store the end to end account for the logged-in user.
 */
- (void)storeAccount:(OLMAccount*)account;

/**
 * Load the end to end account for the logged-in user.
 */
- (OLMAccount*)account;

/**
 Store a flag indicating that we have announced the new device.
 */
- (void)storeDeviceAnnounced;

/**
 Check if the "device announced" flag is set.
 */
- (BOOL)deviceAnnounced;

/**
 Store a device for a user.

 @param userId The user's id.
 @param device the device to store.
 */
- (void)storeDeviceForUser:(NSString*)userId device:(MXDeviceInfo*)device;

/**
 Retrieve a device for a user.

 @param deviceId The device id.
 @param userId The user's id.
 @return A map from device id to 'MXDevice' object for the device.
 */
- (MXDeviceInfo*)deviceWithDeviceId:(NSString*)deviceId forUser:(NSString*)userId;

/**
 Store the known devices for a user.

 @param userId The user's id.
 @param devices A map from device id to 'MXDevice' object for the device.
 */
- (void)storeDevicesForUser:(NSString*)userId devices:(NSDictionary<NSString*, MXDeviceInfo*>*)devices;

/**
 Retrieve the known devices for a user.

 @param userId The user's id.
 @return A map from device id to 'MXDevice' object for the device or nil if we haven't
         managed to get a list of devices for this user yet.
 */
- (NSDictionary<NSString*, MXDeviceInfo*>*)devicesForUser:(NSString*)userId;

/**
 Store the crypto algorithm for a room.

 @param roomId the id of the room.
 @algorithm the algorithm.
 */
- (void)storeAlgorithmForRoom:(NSString*)roomId algorithm:(NSString*)algorithm;

/**
 The crypto algorithm used in a room.
 nil if the room is not encrypted.
 */
- (NSString*)algorithmForRoom:(NSString*)roomId;

/**
 Store a session between the logged-in user and another device.

 @param deviceKey the public key of the other device.
 @param session the end-to-end session.
 */
- (void)storeSession:(OLMSession*)session forDevice:(NSString*)deviceKey;

/**
 Retrieve the end-to-end sessions between the logged-in user and another
 device.

 @param deviceKey the public key of the other device.
 @return {object} A map from sessionId to Base64 end-to-end session.
 */
- (NSDictionary<NSString*, OLMSession*>*)sessionsWithDevice:(NSString*)deviceKey;

/**
 Store an inbound group session.

 @param session the inbound group session and its context.
 */
- (void)storeInboundGroupSession:(MXOlmInboundGroupSession*)session;

/**
 Retrieve an inbound group session.

 @param sessionId the session identifier.
 @param the base64-encoded curve25519 key of the sender.
 @return an inbound group session.
 */
- (MXOlmInboundGroupSession*)inboundGroupSessionWithId:(NSString*)sessionId andSenderKey:(NSString*)senderKey;

/**
 Retrieve all inbound group sessions.
 
 @TODO: maybe too heavy.
 
 @return the list of all inbound group sessions.
 */
- (NSArray<MXOlmInboundGroupSession*> *)inboundGroupSessions;


#pragma mark - Methods for unitary tests purpose
/**
 Remove an inbound group session.

 @param sessionId the session identifier.
 @param the base64-encoded curve25519 key of the sender.
 */
- (void)removeInboundGroupSessionWithId:(NSString*)sessionId andSenderKey:(NSString*)senderKey;

@end

#endif
