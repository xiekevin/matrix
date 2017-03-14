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

#import "MXOlmEncryption.h"

#import "MXCryptoAlgorithms.h"
#import "MXCrypto_Private.h"

#ifdef MX_CRYPTO

@interface MXOlmEncryption ()
{
    MXCrypto *crypto;

    // The id of the room we will be sending to.
    NSString *roomId;
}

@end


@implementation MXOlmEncryption

+ (void)load
{
    // Register this class as the encryptor for olm
    [[MXCryptoAlgorithms sharedAlgorithms] registerEncryptorClass:MXOlmEncryption.class forAlgorithm:kMXCryptoOlmAlgorithm];
}


#pragma mark - MXEncrypting
- (instancetype)initWithCrypto:(MXCrypto *)theCrypto andRoom:(NSString *)theRoomId
{
    self = [super init];
    if (self)
    {
        crypto = theCrypto;
        roomId = theRoomId;
    }
    return self;
}

- (MXHTTPOperation*)encryptEventContent:(NSDictionary*)eventContent eventType:(MXEventTypeString)eventType
                               forUsers:(NSArray<NSString*>*)users
                                success:(void (^)(NSDictionary *encryptedContent))success
                                failure:(void (^)(NSError *error))failure
{
    return [self ensureSession:users success:^{

        NSMutableArray *participantDevices = [NSMutableArray array];

        for (NSString *userId in users)
        {
            NSArray<MXDeviceInfo *> *devices = [crypto storedDevicesForUser:userId];
            for (MXDeviceInfo *device in devices)
            {
                if ([device.identityKey isEqualToString:crypto.olmDevice.deviceCurve25519Key])
                {
                    // Don't bother setting up session to ourself
                    continue;
                }

                if (device.verified == MXDeviceBlocked)
                {
                    // Don't bother setting up sessions with blocked users
                    continue;
                }

                [participantDevices addObject:device];
            }
        }

        NSDictionary *encryptedMessage = [crypto encryptMessage:@{
                                                                  @"room_id": roomId,
                                                                  @"type": eventType,
                                                                  @"content": eventContent
                                                                  }
                                                     forDevices:participantDevices];
        success(encryptedMessage);

    } failure:failure];
}

- (void)onRoomMembership:(NSString*)userId oldMembership:(MXMembership)oldMembership newMembership:(MXMembership)newMembership;
{
    // No impact for olm
}

- (void)onNewDevice:(NSString *)deviceId forUser:(NSString *)userId
{
    // No impact for olm
}

- (void)onDeviceVerification:(MXDeviceInfo *)device oldVerified:(MXDeviceVerification)oldVerified
{
    // No impact for olm
}


#pragma mark - Private methods
- (MXHTTPOperation*)ensureSession:(NSArray<NSString*>*)users
                          success:(void (^)())success
                          failure:(void (^)(NSError *))failure
{
    // TODO: Avoid to do this request for every message. Instead, manage a queue of messages waiting for encryption
    // XXX: This class is not used so fix it later
    MXHTTPOperation *operation;
    operation = [crypto downloadKeys:users forceDownload:YES success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap) {

        MXHTTPOperation *operation2 = [crypto ensureOlmSessionsForUsers:users success:^(MXUsersDevicesMap<MXOlmSessionResult *> *results) {
            success();
        } failure:failure];

        [operation mutateTo:operation2];

    } failure:failure];

    return operation;
}

@end

#endif
