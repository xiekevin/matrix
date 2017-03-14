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

#import "MXFileCryptoStoreMetaData.h"

@implementation MXFileCryptoStoreMetaData


#pragma mark - NSCoding
- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [self init];
    if (self)
    {
        NSDictionary *dict = [aDecoder decodeObjectForKey:@"dict"];
        _userId = dict[@"userId"];
        _deviceId = dict[@"deviceId"];

        NSNumber *version = dict[@"version"];
        _version = [version unsignedIntegerValue];

        NSNumber *deviceAnnounced = dict[@"deviceAnnounced"];
        _deviceAnnounced = [deviceAnnounced boolValue];

    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    // All properties are mandatory except eventStreamToken
    NSMutableDictionary *dict =[NSMutableDictionary dictionaryWithDictionary:
                                @{
                                  @"userId": _userId,
                                  @"version": @(_version),
                                  @"deviceAnnounced": @(_deviceAnnounced)
                                  }];

    // Device may be not provided by the hs
    if (_deviceId)
    {
        dict[@"deviceId"] = _deviceId;
    }

    [aCoder encodeObject:dict forKey:@"dict"];
}


- (NSString *)description
{
    return [NSString stringWithFormat:@"<MXFileCryptoStoreMetaData: %p> Version: %@. UserId: %@. DeviceId: %@. Announced: %@", self, @(_version), _userId, _deviceId, @(_deviceAnnounced)];
}

@end
